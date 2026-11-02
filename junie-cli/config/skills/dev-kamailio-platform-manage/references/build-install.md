# Build and install

## Source build

- Modules selected via `modules.lst` / make cfg / CMake options depending on tree age.
- Flex/Bison generated files: watch **duplicate Ninja rules** (`lex.yy.c`, `cfg.tab.c`).
- Out-of-tree builds: keep prefix (`PUBLIC_DIR`, `CFG_DIR`) consistent with runtime.

## Install scripts

- Idempotent install/configure where the project already aims for that.
- `bwrap` or sandbox wrappers: preserve them when editing.
- Package (deb/rpm/image): version modules path with prefix.

## Cross-link

Build log cascades → `dev-project-fixIssue-fromLogs`.
