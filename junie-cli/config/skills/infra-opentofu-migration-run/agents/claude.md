# Claude specifics — OpenTofu migration

- Separate compatibility analysis from backend or provider upgrades.
- Compare plans using identical inputs and state, and block cutover on unexplained replacements.
- Do not perform production applies or state surgery without explicit approval.
