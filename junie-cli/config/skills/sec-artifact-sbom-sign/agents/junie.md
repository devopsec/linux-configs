# Junie CLI Specifics for Sec Artifact Sbom Sign

## Operating notes

- Execute SAD KITTI config selection and load only the relevant SBOM/signature reference.
- Bind signatures and attestations to the exact artifact digest; do not expose private signing material.
- No commits; require explicit release-owner approval before changing signing identities or deployment gates.
