# Config and routing

## Layout patterns

- Monolithic `kamailio.cfg`
- Split: `kamailio.cfg` + `include_file` / `import_file` fragments (`routes/*.cfg`, `modules-enabled/*.cfg`)
- Platform overlay: install copies templates then sed/env-substitutes paths

## Editing rules

- Preserve `#!KAMAILIO` / version guards and existing `#!ifdef` feature flags.
- Route names: stick to project vocabulary (`REQINIT`, `WITHINDLG`, `NATMANAGE`, custom `NS_*`).
- Prefer early returns / explicit `exit` patterns already used in-file.
- Keep SIP method filters (`is_method`) consistent with nearby blocks.

## Validation

```bash
kamailio -c -f /path/to/kamailio.cfg
# or project wrapper:
./scripts/check-kamailio-config.sh
```

## Common pitfalls

- Listen sockets changed in cfg but not in firewall/unit files
- `mpath` module path wrong after custom prefix install
- Duplicate `request_route` definitions after include mistakes
- IPv6 listen lines left half-migrated
