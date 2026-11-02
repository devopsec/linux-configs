# Junie specifics — infra-azure-network-manage

- Load only the network reference and source address/port values from config or user input.
- Inspect effective NSGs, routes, DNS, and connectivity before suggesting a change.
- Do not commit; require confirmation for production/public connectivity changes.
