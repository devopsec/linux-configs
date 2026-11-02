# Claude specifics — Kustomize

- Select the renderer from the optional config; keep versions and cluster API compatibility explicit.
- Verify selector/namespace changes and secret-generation behavior in rendered output.
- Do not apply or prune without a reviewed diff and approval.
