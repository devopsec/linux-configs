# HashiCorp Vault and OpenBao

Vault is appropriate for dynamic credentials, internal PKI, or a multi-cloud broker when a simpler managed secret service is insufficient. HashiCorp Vault `v2.2.1` was the latest release page version checked on `2026-10-28`; pin the binary and image to an immutable release and verify signatures/checksums. OpenBao is API-compatible for many patterns here but has a separate release lifecycle and license; confirm its exact version separately before selecting it.

## Server baseline

Use Raft storage with TLS for a self-managed deployment. Keep addresses, paths, and cloud key identifiers as runtime configuration, not fixed site values.

```hcl
storage "raft" {
  path    = "<data-directory>"
  node_id = "<unique-node-id>"
}

listener "tcp" {
  address         = "<private-address>:8200"
  cluster_address = "<private-address>:8201"
  tls_cert_file   = "<certificate-path>"
  tls_key_file    = "<private-key-path>"
  tls_min_version = "tls12"
}
```

Limit the API listener to approved clients; allow cluster traffic only between Vault nodes. Use an external KMS auto-unseal only after confirming the service identity, key policy, recovery access, and key availability.

## Initialization and authentication

Initialization is a controlled operator task. Store recovery material with separated custodians, protect it outside the terminal transcript, and revoke the initial root token after establishing administrative auth. Never paste initialization output into chat, issues, or scripts.

Prefer workload identity or short-lived AppRole credentials for automation; configure narrow token TTLs and renewal. Avoid long-lived tokens in files or environment dumps.

## Engines and policies

Enable only the required engines. For KV v2, policies use `data/` and `metadata/` paths while CLI `vault kv` commands hide those segments. Dynamic database credentials should use a dedicated least-privilege database account and short lease TTLs. Limit PKI roles by allowed names, usages, and maximum TTL.

```hcl
path "secret/data/<app>/*" { capabilities = ["read"] }
path "secret/metadata/<app>/*" { capabilities = ["list"] }
path "database/creds/<role>" { capabilities = ["read"] }
```

## Operations and recovery

Enable audit logging and ship logs to a protected destination. Take encrypted Raft snapshots, protect access separately from the cluster, and rehearse restores. Before `operator init`, restore, seal, key rotation, or destructive changes, present impact and require explicit operator confirmation.