# Rust sources of truth

Rust ships every 6 weeks with strong backward compatibility: code that compiled on 1.x keeps
compiling. The risk is the other direction — using an API newer than the project's MSRV, an
edition-2024 feature in a 2021 crate, or a crate API from a different major version than
`Cargo.lock` resolves. Model memory thins out after ~1.88 (mid-2025); the local release notes
cover the rest.

## Order of trust

1. **The compiler and Clippy** on the project's toolchain — `scripts/check.sh`. `rustc --explain
   E0502` prints the long form of any error code offline.
2. **Std source of the active toolchain** — `scripts/api-find.sh <name> [path]`. The
   `#[stable(feature = "…", since = "1.xx.0")]` attribute is the MSRV of that API;
   `#[unstable]`/`#[rustc_const_unstable]` means nightly-only. Needs the `rust-src` component;
   without it, `RUSTUP_TOOLCHAIN=nightly scripts/api-find.sh …` uses nightly's source — its
   date is in the version label, and anything stabilized after that date shows as unstable,
   so cross-check with `scripts/releases.sh -g <name>`.
3. **Dependency source at the locked version** — `scripts/api-find.sh -c <crate> <name>` reads
   `~/.cargo/registry/src/…/<crate>-<locked version>/`. Also read that crate's `CHANGELOG.md`
   there. docs.rs for a *different* version is not evidence.
4. **Local docs** (`rust-docs` component; path from `scripts/rust-env.sh -f docs`): `std/`,
   `book/`, `reference/`, `nomicon/`, `edition-guide/`, `cargo/`, `rustc/`, `clippy/`,
   `rust-by-example/`, `error_codes/`, and `releases.md` (`scripts/releases.sh`).
5. **Online docs for the matching version** (`stable` → a version number pins them):
   - Std: <https://doc.rust-lang.org/std/> · versioned: `https://doc.rust-lang.org/1.85.0/std/`
   - The Book: <https://doc.rust-lang.org/book/>
   - Reference: <https://doc.rust-lang.org/reference/>
   - Rustonomicon (unsafe): <https://doc.rust-lang.org/nomicon/>
   - Async book: <https://rust-lang.github.io/async-book/>
   - Unstable book (nightly features): <https://doc.rust-lang.org/unstable-book/>
   - Edition guide: <https://doc.rust-lang.org/edition-guide/>
   - Cargo book: <https://doc.rust-lang.org/cargo/> · Clippy lints: <https://rust-lang.github.io/rust-clippy/stable/>
   - API guidelines: <https://rust-lang.github.io/api-guidelines/>
   - Release notes: <https://doc.rust-lang.org/stable/releases.html> · blog: <https://blog.rust-lang.org/>
   - Crate docs at a version: `https://docs.rs/<crate>/<version>/` · crate metadata:
     `cargo info <crate>@<version>` (network)
   - Tokio tutorial: <https://tokio.rs/tokio/tutorial> · Rust Performance Book:
     <https://nnethercote.github.io/perf-book/> · Rust Atomics and Locks:
     <https://marabos.nl/atomics/>
6. **Community agent-skill packs** — orientation only, never authoritative; none are installed
   here (importing one requires the `dev-agents-skill-create` audit):
   - leonardomso/rust-skills (<https://github.com/leonardomso/rust-skills>, MIT): ~265 rules in
     26 prefixed categories (`own-`, `err-`, `async-`, `mem-`, `perf-`, `unsafe-`, `api-`,
     `anti-`…). Good checklist material; rules are generic, not version-aware.
   - morganlinton/BeautifulRust (<https://github.com/morganlinton/BeautifulRust>, MIT):
     `rust-best-practices`, `rust-review`, porting guidance, a tested `[lints]` block and
     `clippy.toml` (adapted in `dev-rust-code-review/references/lints.md`).
   - laurigates/claude-plugins `rust-development`, full-stack-skills/rust-skills (29 small
     skills), microsoft/skills (Rust SDK skills), rsvalerio/ai — smaller or narrower; check
     the version each targets before copying advice.

## Toolchain resolution gotchas

- Precedence: `cargo +tc` > `RUSTUP_TOOLCHAIN` env > directory override > `rust-toolchain.toml`
  > default. A global `RUSTUP_TOOLCHAIN` (e.g. exported by mise or a shell profile) silently
  defeats every project's `rust-toolchain.toml`; `scripts/rust-env.sh` warns and exits 3.
- A pinned toolchain that is not installed makes rustup download it on the first `cargo`
  call (unless `RUSTUP_AUTO_INSTALL=0`). The bundled scripts set that; ask before installing.
- `rust-version` (MSRV) in `Cargo.toml` is enforced by cargo (`error: package requires rustc
  1.xx`) and drives the MSRV-aware resolver (default with `resolver = "3"` / edition 2024).

## Version facts (as of 2026-11; verify with `scripts/releases.sh <ver>`)

| Version | Date | Notable for code you write |
|---|---|---|
| 1.80 | 2024-07 | `LazyCell`/`LazyLock` (drop `lazy_static`/`once_cell`), exclusive ranges in patterns |
| 1.81 | 2024-09 | `#[expect(lint, reason = "…")]`, `core::error::Error` |
| 1.82 | 2024-10 | `&raw const`/`&raw mut`, `unsafe extern` blocks, `unsafe` attributes, `cargo info` |
| 1.83 | 2024-11 | `&mut` / interior mutability in `const`, many `const fn` |
| 1.84 | 2025-01 | MSRV-aware resolver, strict-provenance APIs |
| 1.85 | 2025-02 | **edition 2024**, async closures (`async \|\| {}`, `AsyncFn*` traits) |
| 1.86 | 2025-04 | trait upcasting (`&dyn Sub` → `&dyn Super`), `get_disjoint_mut`, safe `#[target_feature]` fns |
| 1.87 | 2025-05 | `std::io::pipe`, `Vec::extract_if`, precise capturing `use<..>` in traits, `asm_goto` |
| 1.88 | 2025-06 | let chains (2024 edition), naked functions, `Cell::update`, `hint::select_unpredictable`, cargo cache GC |
| 1.89 | 2025-08 | `File::lock`/`try_lock`, `Result::flatten`, explicit `_` const generic args, `repr(u128)` |
| 1.90 | 2025-09 | `cargo publish --workspace`, lld default linker on x86_64-linux |
| 1.91 | 2025-10 | `strict_*` integer ops, `AtomicPtr::fetch_ptr_add`, `Duration::from_mins/hours`, `build.build-dir` |
| 1.92 | 2025-12 | `RwLockWriteGuard::downgrade`, `Box/Rc/Arc::new_zeroed` |
| 1.93 | 2026-01 | `Vec/String::into_raw_parts`, `fmt::from_fn`, `<[T]>::as_array` |
| 1.94 | 2026-03 | `<[T]>::array_windows`, `LazyLock::get`, Cargo config `include`, TOML 1.1 |
| 1.95 | 2026-04 | `if let` guards in `match`, `cfg_select!`, `Vec::push_mut`, atomic `update`, `hint::cold_path` |
| 1.96 | 2026-05 | `assert_matches!`, new `core::range` types |
| 1.97 | 2026-07 | `isolate_*_one`/`bit_width` int ops, `resolver.lockfile-path` |
| 1.98 | 2026-08 | `bool::ok_or`, `str::substr_range`, `String::from_utf16le/be`, `NumBuffer`/`format_into` |
| 1.99 | 2026-10 | C-variadic fn definitions, `Vec::into_parts`/`from_parts`, `fs::set_times`, `debug` cargo profile |

Edition detail and porting live in `dev-rust-version-migrate`.

## Quick lookups

```bash
scripts/rust-env.sh .                         # toolchain, pins, MSRV, edition, tools present
scripts/api-find.sh push_mut                  # declaration + #[stable(since)] in std
scripts/api-find.sh -d -b 'try_lock' fs       # with docs and body, only under fs
scripts/api-find.sh -c tokio -d 'spawn_blocking'   # in tokio at the Cargo.lock version
scripts/api-find.sh -a 'since = "1.9[5-9]' sync    # what in std::sync is newer than 1.95?
scripts/releases.sh -g 'LazyLock|let.chains'  # when did X stabilize?
scripts/releases.sh -s 'language|stabilized' 1.90..   # what changed since 1.90
rustc --explain E0499                          # long-form error explanation
```
