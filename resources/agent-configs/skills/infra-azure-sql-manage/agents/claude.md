# Claude specifics — infra-azure-sql-manage

- Load only the matching database reference and preserve IaC ownership.
- State recovery, availability, and data-loss effects before destructive operations.
- Never expose database credentials or commit changes.
