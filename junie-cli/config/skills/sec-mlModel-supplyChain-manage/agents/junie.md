# Junie CLI Specifics for Sec Mlmodel Supplychain Manage

## Operating notes

- Execute SAD KITTI config selection and load only model integrity guidance needed.
- Treat weights and conversion utilities as untrusted; do not deserialize arbitrary pickle artifacts.
- No commits; verify provenance, digest, and evaluation gates before promotion.
