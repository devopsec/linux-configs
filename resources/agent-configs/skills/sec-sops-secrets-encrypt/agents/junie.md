# Junie CLI Specifics for Sec Sops Secrets Encrypt

## Operating notes

- Execute SAD KITTI branches and load only the SOPS workflow needed for the requested file/key change.
- Keep decrypted output out of terminal transcripts; inspect diffs for plaintext before reporting.
- No commits; confirm recipient removal and underlying-secret rotation with the owner.
