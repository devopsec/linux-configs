# Junie CLI Specifics for Sec Python Dependency Scan

## Operating notes

- Execute SAD KITTI branches; read dependency config before selecting scanners and use only pinned versions.
- Scan the locked dependency set and keep raw reports in protected temporary storage.
- No commits; keep ignores time-limited and do not grant PR scanners publish credentials.
