# Modules, modparam, RPC

## Module load

```
loadmodule "pike.so"
modparam("pike", "sampling_time_unit", 2)
```

- Place `loadmodule` near existing module block; keep dependencies ordered (e.g. `tm` before modules using it).
- Shared libraries must exist under `mpath`.

## Runtime-updatable parameters

Many platforms expose selected params via:

- **RPC** `cfg.get` / `cfg.set` / module-specific commands (`kamcmd`, `jsonrpc`)
- **GUI** (dSIPRouter) writing DB or files then triggering reload
- **`htable`** for dynamic keys

When adding a tunable:

1. Check if the module param is marked changeable at runtime in Kamailio docs.
2. Wire GUI/DB/RPC the same way sibling params are wired.
3. Document default + valid range.

## Hot reload

- `kamcmd core.killn` / module reloads vary; prefer project’s existing reload path.
- Some changes (listen, module load list) **require restart** — label them clearly.
- After reload, read back param values to confirm.

## Debugging aids

- `xlog` levels already used in cfg (`L_ERR`, `L_INFO`) — match them.
- `debugger` / `siptrace` only if already accepted in that environment.
