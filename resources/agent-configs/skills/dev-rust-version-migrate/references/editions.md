# Edition migration (2015 → 2018 → 2021 → 2024)

Editions are per crate: crates on different editions link together fine, so migrate one
crate (or workspace member) at a time. Full details: local edition guide
(`<docs>/edition-guide/`, path from `../dev-rust-code-create/scripts/rust-env.sh -f docs`).

| Edition | Minimum rustc | Resolver default |
|---|---|---|
| 2018 | 1.31 | 1 |
| 2021 | 1.56 | 2 |
| 2024 | 1.85 | 3 (MSRV-aware) |

## Procedure (per edition step, per crate)

1. Clean tree, tests passing on the current edition, with all features:
   `cargo test --all-features --all-targets`.
2. `cargo fix --edition --all-features --all-targets [-p crate]` — applies the
   `rust-20xx-compatibility` lint suggestions while still on the old edition. Code behind
   `cfg`s not enabled on this host (other OS/targets) is not fixed: repeat with
   `--target <triple>` for each supported platform target if installed, or fix by hand.
3. Set `edition = "20xx"` in `Cargo.toml` (or `[workspace.package]`); for 2024 also check
   `rust-version >= 1.85` and `resolver = "3"` in virtual workspace manifests.
4. `cargo build --all-targets --all-features`, `cargo test`, `cargo clippy` — fix what
   `cargo fix` couldn't (the `manual` hits of `scripts/scan-legacy.sh`).
5. `cargo fmt` — 2024 also switches the rustfmt *style edition* (formatting changes in a
   separate commit keeps the diff reviewable; `style_edition = "2021"` in `rustfmt.toml`
   defers them).
6. Review behavior changes that compile silently (listed below).

## 2024 (rustc 1.85+)

Automatic (`cargo fix --edition`):
- `extern "C" { }` → `unsafe extern "C" { }`; items may be marked `safe`/`unsafe`.
- `#[no_mangle]`, `#[export_name]`, `#[link_section]` → `#[unsafe(...)]`.
- `unsafe_op_in_unsafe_fn` warns: unsafe operations inside `unsafe fn` get their own
  `unsafe {}` blocks (add SAFETY comments afterwards).
- `gen` is a reserved keyword → `r#gen` (for `rand`, prefer upgrading to 0.9 `random()`).
- Macro `$x:expr` fragments now also match `const { … }` and `_`; ambiguous ones become
  `expr_2021`.
- `Box<[T]>::into_iter()` yields `T` by value (was `&T`).
- `Cargo.toml`: `[project]` → `[package]`; underscore keys (`default_features`, `crate_type`,
  `proc_macro`, `dev_dependencies`, `build_dependencies`) → dashed; inherited
  `default-features = false` removed when the workspace dependency doesn't set it.
- Never-type fallback changes from `()` to `!`: cargo fix adds explicit types where
  inference relied on it (e.g. `f()?` where `f` is generic over its return type).
- `if let` rescope: the lint can rewrite some `if let … else` into `match` to keep old drop
  timing.

Manual / review:
- `std::env::set_var`/`remove_var` (and `CommandExt::before_exec`) are `unsafe`: cargo fix
  wraps calls in `unsafe {}` — you must justify (single-threaded at that point) or remove
  (set env on `Command` instead).
- References to `static mut` are denied (`static_mut_refs`): replace with atomics,
  `Mutex`/`OnceLock`, or `&raw const X`/`&raw mut X` when raw access is truly needed.
- `if let` scrutinee temporaries drop before `else`; tail-expression temporaries drop before
  block locals. Code that relied on a guard (`RefCell::borrow_mut`, `Mutex::lock`) living
  longer now either compiles with different timing or fails borrowck (usually fixes bugs —
  but check lock-protected sequences).
- Return-position `impl Trait` captures all in-scope generic lifetimes; add
  `+ use<'a, T>` to opt out when callers need the returned value to outlive a borrow.
- Match ergonomics reservations: no `ref`/`mut`/`&` modifiers inside patterns that are in a
  by-reference default binding mode — make the pattern fully explicit.
- Prelude adds `Future` and `IntoFuture`: method-name ambiguities with your own traits.
- Rustdoc: doctests from `#[doc = include_str!(…)]` resolve nested `include!` paths relative
  to the Markdown file; combined doctest compilation (tests that rely on being separate
  binaries need `standalone_crate` attribute).
- Cargo: resolver 3 picks dependency versions compatible with `rust-version`.
- Let chains (`if let … && …`) become available (1.88+), useful when cleaning up nested `if let`.

## 2021 (rustc 1.56+)

- Disjoint closure captures: closures capture fields, not whole variables — drop order of
  captured fields may change (cargo fix inserts `let _ = &x;` where it matters).
- `array.into_iter()` iterates by value (was by reference via autoref).
- Prelude adds `TryFrom`, `TryInto`, `FromIterator` (conflicts with same-named trait
  methods in scope).
- `panic!("{}")` / `panic!(s)` with one argument is a format string (use `panic!("{s}")`
  or `std::panic::panic_any`).
- Or-patterns in `macro_rules!` `$x:pat` match `A | B` (use `pat_param` for old behavior).
- Reserved prefixes (`ident#`, `ident"…"`, `ident'…'`): add a space in macro inputs.
- Hard errors: bare trait objects (`Box<Trait>` → `Box<dyn Trait>`), `...` range patterns
  (→ `..=`).
- Cargo: feature resolver 2 (features of build-deps/dev-deps/target-specific deps no longer
  unified with normal deps) — can change which features a dependency is compiled with.

## 2018 (rustc 1.31+)

- Paths: `use crate::…` for crate-local paths; `extern crate` unnecessary (except `alloc`,
  `proc_macro`, `test`, or `#[macro_use]` legacy macros → import macros with `use`).
- `dyn Trait` keyword; anonymous trait-method parameters removed; `async`, `await`, `try`,
  `dyn` reserved; `try!` → `?`.
- NLL borrow checking (also backported to 2015 since).
