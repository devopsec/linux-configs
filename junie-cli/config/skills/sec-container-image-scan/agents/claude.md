# Claude Specifics for Sec Container Image Scan

## Operating notes

- Follow the SAD KITTI config branch and load only the container scanning guidance needed.
- Use immutable image digests and private/redacted report output; do not suppress findings broadly.
- Confirm before making a vulnerability gate blocking or changing an image registry policy.
