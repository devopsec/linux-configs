# Google Cloud DNS operations

## Zone and record discovery

Confirm project, zone, visibility, authoritative nameservers, and IaC ownership before changing a zone. Use trailing-dot FQDNs for record-set operations.

```bash
gcloud dns managed-zones list
gcloud dns managed-zones describe <zone>
gcloud dns record-sets list --zone=<zone> --name=<fqdn>.
dig @<authoritative-nameserver> <fqdn> <type> +norecurse
```

Use public zones for internet resolution and private/forwarding zones only for their bound networks. Document split-horizon behavior and resolver paths before changing a private zone.

## Record changes

Show the complete current and proposed RRset, owner, type, TTL, and answer data before applying. Use transactions for a logically atomic multi-record change:

```bash
gcloud dns record-sets transaction start --zone=<zone>
gcloud dns record-sets transaction remove --zone=<zone> --name=<fqdn>. --type=<type> --ttl=<old-ttl> <old-data>
gcloud dns record-sets transaction add --zone=<zone> --name=<fqdn>. --type=<type> --ttl=<new-ttl> <new-data>
gcloud dns record-sets transaction execute --zone=<zone>
```

If validation fails, abort the transaction. Export/import is a bulk replacement workflow; never use delete-all-existing until every current and proposed record has been reviewed and backed up.

## SIP NAPTR/SRV discovery

SIP discovery follows NAPTR → SRV → A/AAAA. Confirm the SIP domain, live Kamailio transports, TLS certificate names, carrier behavior, service priorities/weights, target hostnames, and approved listener ports before publishing records. These are runtime/site inputs, not defaults to infer.

```text
<sip-domain>.       <ttl> IN NAPTR <order> <preference> "s" "<service-string>" "" <srv-name>.
<srv-name>.         <ttl> IN SRV   <priority> <weight> <approved-port> <target-hostname>.
<target-hostname>.  <ttl> IN A     <approved-address>
```

SRV targets must resolve directly to A/AAAA names; do not use CNAME targets. Lower SRV priority numbers are preferred; weights distribute selection among records with equal priority. Publish only transports that the service actually listens on. SIP signaling discovery does not configure RTP/media routing.

Verify each layer after publication:

```bash
dig +short NAPTR <sip-domain>
dig +short SRV <srv-name>
dig +short A <target-hostname>
```

Coordinate SIP changes with `dev-kamailio-platform-manage` and certificate policy with `sec-network-tls-manage`.

## DNSSEC, CAA, and email authentication

- For DNSSEC enablement or provider migration, confirm DS/DNSKEY state with the registrar; a stale DS can make the domain fail validation.
- CAA records must authorize every certificate authority used by the domain, including managed certificate services.
- SPF, DKIM, and DMARC values must come from the mail provider/owner. Start policy changes with a reporting period and review before enforcement.
- Scope DNS-01 credentials to the required zone/records and use the approved secret store.

## TTL and migration

Use the zone owner's approved TTL. Lower it far enough ahead of a migration for the existing TTL/cache lifetime to expire; maintain the old zone/answers until delegation and record caches have converged. Compare authoritative and recursive answers before and after nameserver changes.

## Troubleshooting

| Symptom | Check |
|---|---|
| Change not visible | authoritative answer, prior TTL, negative cache, delegation |
| SERVFAIL | DS versus DNSKEY chain, zone signing, authoritative reachability |
| SIP client selects wrong transport | NAPTR order/service strings and actual listener support |
| Private answer absent | zone network binding and client resolver path |
| Certificate issuance fails | CAA, DNS-01 TXT visibility, credential scope |