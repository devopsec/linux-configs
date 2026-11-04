# Claude specifics — dev-zig-version-migrate

- Large ports: run `scan-legacy.sh -q` first and share the summary before editing; for trees
  with hundreds of hits, port one directory per turn and rebuild between them.
- Use Edit per hit rather than sed across the tree — many replacements need surrounding
  context (adding `io`/allocator params changes signatures and every call site).
- Threading `io: std.Io` through call graphs (0.16): change the leaf signatures, rebuild, and
  follow the compiler's "expected N arguments" errors upward; batch independent files.
- Long compiles: `run_in_background` or an extended Bash timeout; side-by-side compilers via
  `ZIG=…` on the scripts.
- Downloading another Zig version or editing CI/toolchain pins needs the user's approval.
  Don't commit.
