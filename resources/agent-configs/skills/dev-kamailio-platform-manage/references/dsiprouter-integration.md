# dSIPRouter integration

## Mental model

- dSIPRouter = GUI + orchestration around Kamailio (and often RTPEngine, DB).
- Python/Flask (or project equivalent) + templates generate or patch Kamailio config.
- DB settings may override file defaults.

## Change patterns

1. **GUI-only setting** — form + validation + DB + apply job that writes cfg/RPC.
2. **Kamailio behavior** — cfg/module change + GUI exposure if operators must tune it.
3. **Install path** — `dsiprouter.sh` / ansible / terraform images must receive path updates.

## Rules

- Follow existing plugin/module directory layout for new GUI modules.
- Hot-save paths should not require SSH manual edits.
- When upstream Kamailio diverges, isolate patches and document rebase notes.
