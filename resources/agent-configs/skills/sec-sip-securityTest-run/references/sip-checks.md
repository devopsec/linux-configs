# Bounded SIP service checks

SIP probing is permitted only for a named, owned test endpoint with written authorization, a source allowlist, an approved window, and a stop contact. Carrier trunks, partner SBCs, and unrelated public endpoints are out of scope by default.

## Tool versions

Versions checked 2026-10-28; use signed distro packages where available and record the installed build.

| Tool | Version | Source |
|---|---:|---|
| Nmap | 7.992 | [official changelog](https://nmap.org/changelog.html) |
| SIPp | 3.8.0 | [official releases](https://github.com/SIPp/sipp/releases) |
| SIPVicious OSS | 0.3.8 | [official releases](https://github.com/EnableSecurity/sipvicious/releases) |

## Allowed verification

Use a single host and expected SIP ports only; do not scan ranges or enumerate extensions/users.

```bash
nmap -sT -sV --version-light -p 5060,5061 --max-rate 1 <approved-test-host>
sipsak -s sip:<test-user>@<approved-test-host>:5060 -v
```

If a functional call is needed, inspect the built-in or supplied SIPp scenario, confirm it has no command execution or unexpected destinations, and limit it to one test call against the approved test endpoint:

```bash
sipp -sn uac <approved-test-host>:5060 -r 1 -m 1 -timeout 10
```

Confirm expected signalling and a controlled two-way media path. RTP port bounds must come from the deployed media-service configuration; never guess them. Do not generate RTP floods, malformed traffic, high-rate calls, or tests that can incur carrier charges.

## Prohibited agent actions

- SIP user/extension enumeration or password guessing
- Flood, load, fuzzing, malformed-message, or denial-of-service testing
- Scanning carrier/partner networks or any target outside the written allowlist
- Running unreviewed SIPp scenario XML or templates that can execute commands or redirect traffic

If a request requires one of these methods, stop and ask for an explicitly approved human-led test plan; do not improvise commands.

## Findings and fixes

Record expected versus observed listeners, source, time, tool versions, result, and a redacted evidence reference. Route perimeter exposure to `sec-sip-exposure-manage`, firewall rules to `sec-linux-hostFirewall-manage` or `sec-gcp-firewall-manage`, certificates to `sec-network-tls-manage`, and application configuration to `dev-kamailio-platform-manage`.