# Azure networking — VNets, NSGs, NAT, peering, Private Link, Firewall, App Gateway

Host firewall and TLS controls are separate from Azure network security groups and belong at the guest/application layer.

## Contents
- Topology (hub-spoke)
- VNets and subnets
- NSGs / ASGs
- Egress: NAT Gateway (default outbound retired)
- Peering
- Private endpoints + private DNS
- Azure Firewall + UDRs
- Application Gateway + WAF / Load Balancer
- Diagnostics (Network Watcher, flow logs)
- CI auth (workload identity federation)
- Terraform/OpenTofu
- Troubleshooting

## Topology

```
hub-vnet <approved-hub-cidr>      AzureFirewallSubnet <firewall-subnet-cidr>, GatewaySubnet <gateway-subnet-cidr>, AzureBastionSubnet <bastion-subnet-cidr>
spoke-<env> <approved-spoke-cidr> web <web-subnet-cidr>, app <app-subnet-cidr>, data <data-subnet-cidr> (private endpoints)
```

Reserved subnet names are exact (`AzureFirewallSubnet`, `GatewaySubnet`, `AzureBastionSubnet`). Avoid overlap with all user-provided on-premises and peer ranges. For many spokes or SD-WAN consider Virtual WAN; use Azure Virtual Network Manager for connectivity and security admin rules at scale.

## VNets and subnets

```bash
az network vnet create -g <rg> -n hub-vnet --address-prefixes "$HUB_CIDR" --location "$REGION"
az network vnet subnet create -g <rg> --vnet-name hub-vnet -n AzureFirewallSubnet --address-prefixes "$FIREWALL_SUBNET_CIDR"
az network vnet subnet create -g <rg> --vnet-name hub-vnet -n AzureBastionSubnet --address-prefixes "$BASTION_SUBNET_CIDR"
az network vnet create -g <rg> -n spoke-<env>-vnet --address-prefixes "$SPOKE_CIDR"
az network vnet subnet create -g <rg> --vnet-name spoke-<env>-vnet -n web --address-prefixes "$WEB_SUBNET_CIDR" --default-outbound-access false
az network vnet subnet create -g <rg> --vnet-name spoke-<env>-vnet -n app --address-prefixes "$APP_SUBNET_CIDR" --default-outbound-access false
az network vnet subnet create -g <rg> --vnet-name spoke-<env>-vnet -n data --address-prefixes "$DATA_SUBNET_CIDR" --default-outbound-access false
```

## NSGs / ASGs

Rules: priority 100–4096 (lower wins); defaults allow VNet↔VNet and AzureLoadBalancer — add explicit denies where needed. Use service tags (`Internet`, `VirtualNetwork`, `AzureLoadBalancer`, `Sql.<region>`) and Application Security Groups instead of IP lists.

```bash
az network nsg create -g <rg> -n web-nsg
# Only allow Internet here when this endpoint is intentionally public; otherwise use an approved source range.
az network nsg rule create -g <rg> --nsg-name web-nsg -n AllowHttpsIn --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --destination-port-ranges 443
az network asg create -g <rg> -n app-asg
az network nsg create -g <rg> -n app-nsg
az network nsg rule create -g <rg> --nsg-name app-nsg -n AllowFromWeb --priority 100 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes "$WEB_SUBNET_CIDR" \
  --destination-asgs app-asg --destination-port-ranges "$APP_PORT"
az network nsg rule create -g <rg> --nsg-name app-nsg -n DenyVnetIn --priority 4000 --direction Inbound \
  --access Deny --protocol '*' --source-address-prefixes VirtualNetwork --destination-port-ranges '*'
az network vnet subnet update -g <rg> --vnet-name spoke-<env>-vnet -n web --network-security-group web-nsg
az network vnet subnet update -g <rg> --vnet-name spoke-<env>-vnet -n app --network-security-group app-nsg

# Add only application-required ports and source ranges supplied by the user/config.
```

## Egress: NAT Gateway

Default outbound access is retired for new VNets (since 2025-09-30). Give private subnets explicit egress:

```bash
az network public-ip create -g <rg> -n natgw-pip --sku Standard --zone 1 2 3
az network nat gateway create -g <rg> -n <env>-natgw --public-ip-addresses natgw-pip --idle-timeout 10
az network vnet subnet update -g <rg> --vnet-name spoke-<env>-vnet -n app --nat-gateway <env>-natgw
```

NAT Gateway availability and zone behavior depend on region and SKU; use Azure Firewall instead when egress must be FQDN-filtered.

## Peering

Must exist in **both** directions:

```bash
az network vnet peering create -g <rg> -n hub-to-<env> --vnet-name hub-vnet --remote-vnet spoke-<env>-vnet \
  --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit
az network vnet peering create -g <rg> -n <env>-to-hub --vnet-name spoke-<env>-vnet --remote-vnet hub-vnet \
  --allow-vnet-access --allow-forwarded-traffic --use-remote-gateways     # only if hub has a VPN/ER gateway
az network vnet peering list -g <rg> --vnet-name hub-vnet -o table          # peeringState: Connected
```

Non-transitive: spoke↔spoke via hub firewall/NVA + UDRs or AVNM. Cross-subscription: pass the full remote VNet resource ID. For other clouds or on-premises networks, use an approved VPN/private-connectivity design and confirm BGP and DNS ownership.

## Private endpoints + private DNS

```bash
az network private-endpoint create -g <rg> -n <svc>-pe --vnet-name spoke-<env>-vnet --subnet data \
  --private-connection-resource-id <resource-id> --group-id <postgresqlServer|sqlServer|blob|vault|sites> \
  --connection-name <svc>-pe-conn
az network private-dns zone create -g <rg> -n privatelink.postgres.database.azure.com
az network private-dns link vnet create -g <rg> --zone-name privatelink.postgres.database.azure.com \
  -n <env>-link --virtual-network spoke-<env>-vnet --registration-enabled false
az network private-endpoint dns-zone-group create -g <rg> --endpoint-name <svc>-pe -n default \
  --private-dns-zone privatelink.postgres.database.azure.com --zone-name postgres
```

Zone names: `privatelink.database.windows.net` (SQL), `privatelink.postgres.database.azure.com` (PG flexible PE), `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`, `privatelink.azurewebsites.net`. Centralise zones where appropriate and link required VNets; non-Azure resolvers can forward to an Azure DNS Private Resolver inbound endpoint. Then disable public network access on the target resource.

## Azure Firewall + UDRs

Use Firewall Policy (classic rules are legacy):

```bash
az network firewall policy create -g <rg> -n hub-fwpolicy --sku Standard --threat-intel-mode Deny
az network firewall policy rule-collection-group create -g <rg> --policy-name hub-fwpolicy -n egress --priority 200
az network firewall policy rule-collection-group collection add-filter-collection -g <rg> \
  --policy-name hub-fwpolicy --rcg-name egress -n allow-fqdn --collection-priority 100 --action Allow \
  --rule-type ApplicationRule --rule-name os-updates --protocols Https=443 \
  --source-addresses "$SPOKE_CIDR" --target-fqdns "<approved-update-fqdns>"
az network firewall create -g <rg> -n hub-fw --sku AZFW_VNet --tier Standard --firewall-policy hub-fwpolicy \
  --vnet-name hub-vnet --public-ip hub-fw-pip
FW_IP=$(az network firewall show -g <rg> -n hub-fw --query "ipConfigurations[0].privateIPAddress" -o tsv)
az network route-table create -g <rg> -n <env>-rt --disable-bgp-route-propagation true
az network route-table route create -g <rg> --route-table-name <env>-rt -n default --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance --next-hop-ip-address "$FW_IP"
az network vnet subnet update -g <rg> --vnet-name spoke-<env>-vnet -n app --route-table <env>-rt
```

Review asymmetric routing and firewall throughput/SNAT capacity when public inbound traffic uses a different path than outbound traffic.

## Application Gateway + WAF / Load Balancer

- HTTP(S): Application Gateway v2 with a WAF policy and an explicitly selected managed ruleset version supported by the chosen SKU; TLS certificates from Key Vault via managed identity; end-to-end TLS to backends. Global entry: Front Door.
- L4 (TCP/UDP): Standard Load Balancer; health probe on a TCP/HTTP health port (UDP probes aren't supported).

## Diagnostics

```bash
az network nic list-effective-nsg -g <rg> -n <nic>
az network nic show-effective-route-table -g <rg> -n <nic> -o table
az network watcher test-ip-flow --vm <vm-id> --direction Inbound --protocol <protocol> --local <local-ip>:<port> --remote <peer-ip>:<port>
az network watcher show-next-hop --vm <vm-id> --source-ip <src> --dest-ip <dst>
az network watcher test-connectivity --source-resource <vm-id> --dest-address <host> --dest-port 5432
az network watcher flow-log create -g <rg> -n <env>-vnet-flowlog --location <region> \
  --vnet spoke-<env>-vnet --storage-account <sa-id> --workspace <law-id> --traffic-analytics true
```

Use VNet flow logs for new work. NSG flow log creation was retired in June 2025, with full retirement scheduled in 2027 (checked 2026-10-28).

## CI auth (workload identity federation)

No client secrets in CI. Create a user-assigned managed identity (or app registration) with a federated credential:

```bash
az identity create -g <rg> -n <ci-identity>
# GitHub Actions
az identity federated-credential create -g <rg> --identity-name <ci-identity> -n gha-main \
  --issuer https://token.actions.githubusercontent.com --subject repo:<org>/<repo>:ref:refs/heads/main \
  --audiences api://AzureADTokenExchange
az role assignment create --assignee <identity-principal-id> --role Contributor --scope <rg-id>   # scope narrowly
```

## Terraform/OpenTofu

Prefer Azure Verified Modules where suitable and pin an exact module release reviewed for the workload; see `infra-terraform-avmModule-develop`. Minimal raw form:

```hcl
resource "azurerm_subnet" "app" {
  name                            = "app"
  resource_group_name             = azurerm_resource_group.net.name
  virtual_network_name            = azurerm_virtual_network.spoke.name
  address_prefixes                = var.application_subnet_cidrs
  default_outbound_access_enabled = false
}
resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}
```

Provider baseline: `hashicorp/azurerm` `5.11.0` (checked 2026-10-28); pin it in the IaC configuration and lock file.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No internet from VM | NAT GW / firewall UDR; default outbound retired |
| Peering `Disconnected`/`Initiated` | create the reverse peering |
| Private endpoint resolves public IP | DNS zone link missing / custom DNS not forwarding to 168.63.129.16 |
| NSG rule ignored | higher-priority rule; NIC-level NSG also applies (both must allow) |
| App Gateway 502 | backend NSG must allow `GatewayManager` 65200-65535 + probe path |
| SNAT exhaustion | NAT GW (64k ports per IP) instead of LB outbound rules |
