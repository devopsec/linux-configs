# Rust language patterns

Idioms for edition 2021/2024 on a recent stable. Items marked *(1.xx)* need that MSRV; check
`rust-version` before using them. Verify std signatures with `scripts/api-find.sh`.

## Contents
1. Ownership and borrowing
2. Types and modeling
3. Traits and generics
4. Pattern matching and control flow
5. Iterators and closures
6. Smart pointers and interior mutability
7. Strings, paths, and conversions
8. Modules, visibility, macros, const

## 1. Ownership and borrowing

- Take the weakest parameter type that works: `&str` over `&String`, `&[T]` over `&Vec<T>`,
  `&Path` over `&PathBuf`, `impl AsRef<Path>` for public file APIs. Return owned values.
- Take ownership (`T`, `String`, `Vec<T>`) only when the callee stores or consumes it; let the
  caller decide to clone. `impl Into<String>` for constructors that store a string.
- Fighting the borrow checker usually means the data layout is wrong. Before reaching for
  `clone()`/`Rc<RefCell<_>>`: shorten borrows (compute, then mutate), split structs so fields
  borrow independently, use indices/IDs into a `Vec` instead of references between nodes, or
  restructure as a pass that returns new values.
- Disjoint field borrows work on `self.a` and `self.b` directly, not through `&mut self`
  methods. Closures capture disjoint fields (2021+).
- `std::mem::take`/`replace`/`swap` move out of `&mut` fields without cloning.
- Need two `&mut` into one slice: `split_at_mut`, `get_disjoint_mut` *(1.86)*, or
  `chunks_mut`; for maps `HashMap::get_disjoint_mut` *(1.86)*.
- Lifetimes: elide where possible; name them when a returned reference ties to one specific
  input. Structs holding references (`struct Parser<'a> { src: &'a str }`) are fine for
  short-lived views; owning types are simpler for anything long-lived or sent across threads.
  `'static` bounds mean "owns its data", not "lives forever".
- Return-position `impl Trait` in 2024 captures all in-scope lifetimes; restrict with
  `-> impl Iterator<Item = u8> + use<'a, T>` when the caller must not be tied to a borrow.

## 2. Types and modeling

- Make invalid states unrepresentable: enums with data over structs of optional fields +
  flags; newtypes (`struct UserId(u64)`) for units/IDs; "parse, don't validate" — constructors
  that validate and return `Result<Self, E>`, then trust the type.
- Typestate (generic marker or separate types) for protocols with ordering rules
  (`Connection<Unauthenticated>` → `Connection<Ready>`).
- Public library types: `#[derive(Debug)]` always; `Clone, PartialEq, Eq, Hash, Default` when
  meaningful; `#[non_exhaustive]` on public enums/structs that may grow; `#[must_use]` on
  builders and pure functions whose result matters.
- Bools in signatures: prefer two-variant enums (`Overwrite::Yes`) for readability.
- Integer choice: `usize` for indices/lengths, fixed widths for protocol/disk formats.
  Conversions with `From`/`TryFrom` (`u32::try_from(len)?`), not `as` (silently truncates/wraps).
  Overflow panics in debug and wraps in release unless `overflow-checks = true`; use
  `checked_*`/`saturating_*`/`wrapping_*` explicitly, or `strict_*` *(1.91)* to always panic.
- Floats: no `Eq`/`Ord`; use `total_cmp` for sorting.

## 3. Traits and generics

- Static dispatch (`fn f(x: impl Trait)` / `<T: Trait>`) by default; `dyn Trait` for
  heterogeneous collections, plugin points, or to cut monomorphization bloat. Object-safe
  (dyn-compatible) traits: no generic methods, no `Self` returns without `where Self: Sized`.
- Associated types when there is one natural choice per impl (`Iterator::Item`); generic
  parameters when a type can implement the trait many ways (`From<T>`).
- Implement `From`, not `Into`. Implement `Display` (and get `ToString` free), not `ToString`.
  Implement `FromStr` for parsing, `TryFrom` for fallible conversions, `FromIterator`/`Extend`
  for collections, `AsRef`/`Borrow` thoughtfully (`Borrow` requires identical `Hash`/`Eq`).
- `async fn` in traits *(1.75)* works for static dispatch; it does not make futures `Send` and
  is not dyn-compatible. For `Send` bounds use `-> impl Future<Output = T> + Send` in the trait
  (or the `trait-variant` crate); for `dyn` use boxing (`Pin<Box<dyn Future + Send + '_>>`) or
  the `async-trait` crate.
- Sealed traits (private supertrait) when downstream must not implement them.
- Trait upcasting `&dyn Sub` → `&dyn Super` *(1.86)*.
- Blanket impls (`impl<T: Display> MyTrait for T`) are a semver commitment in libraries.

## 4. Pattern matching and control flow

- `let Some(x) = opt else { return Err(...) };` (let-else) for early exits.
- Let chains *(1.88, edition 2024 only)*: `if let Some(x) = a && x > 3 && let Ok(y) = f(x) {}`.
  In edition 2021 nest the `if let`s instead.
- `if let` guards in `match` arms *(1.95)*: `Some(s) if let Ok(n) = s.parse::<u32>() => …`.
- `matches!(v, Pat if cond)` for boolean checks; `assert_matches!` *(1.96)* in tests.
- Exhaustive matches on your own enums — avoid `_ =>` so new variants cause compile errors;
  required `_` arm for foreign `#[non_exhaustive]` enums.
- Edition 2024 match ergonomics: inside a pattern that already auto-dereferenced (matching
  `&T` with a non-reference pattern), writing `ref`/`mut`/`&` on bindings is an error — write
  the pattern fully explicit (`&Some(ref x)`) or drop the modifier.
- Edition 2024 temporaries: an `if let` scrutinee's temporaries drop before the `else` block,
  and a block's tail-expression temporaries drop before its locals — guards (`RefCell`
  borrows, `Mutex` locks) no longer live as long as they did in 2021.
- `loop { … break value; }` returns values; labeled breaks `'outer:` for nested loops.

## 5. Iterators and closures

- Prefer iterator chains for transforms (`filter_map`, `flat_map`, `zip`, `enumerate`,
  `windows`, `chunks_exact`, `array_windows` *(1.94)*); a `for` loop is better when the body
  has side effects, early returns with `?`, or complex state.
- Don't `collect()` just to iterate again; return `impl Iterator<Item = T> + '_` from accessors.
- Collect into `Result<Vec<_>, E>` to stop on the first error: `.map(parse).collect::<Result<Vec<_>, _>>()?`.
- `iter()` borrows, `iter_mut()` mutably borrows, `into_iter()` consumes. Arrays and (2024)
  `Box<[T]>` iterate by value with `into_iter()`.
- `extract_if` *(1.87)* / `retain` for in-place filtering; `sort_unstable_by_key` unless stability matters.
- Closures: `move` when the closure outlives the scope (threads, tasks, returned closures).
  Accept `impl Fn(…)`/`FnMut`/`FnOnce` — the weakest the body needs is `FnOnce` for the caller.
  Async closures `async |x| {}` and `AsyncFn*` bounds *(1.85)*.

## 6. Smart pointers and interior mutability

| Need | Single-thread | Multi-thread |
|---|---|---|
| Heap/indirection, recursive types, trait objects | `Box<T>` | `Box<T>` |
| Shared ownership | `Rc<T>` | `Arc<T>` |
| Mutate through `&` (Copy values) | `Cell<T>` | atomics |
| Mutate through `&` (other values) | `RefCell<T>` | `Mutex<T>` / `RwLock<T>` |
| Init once / lazily | `OnceCell` / `LazyCell` | `OnceLock` / `LazyLock` *(1.80)* |
| Break cycles | `rc::Weak` | `sync::Weak` |

- `Rc<RefCell<T>>` in a public API usually signals a design problem (shared mutable graph);
  prefer ownership trees, arenas with indices, or message passing.
- `Rc<str>`/`Arc<[T]>` instead of `Rc<String>`/`Arc<Vec<T>>` (one fewer indirection).
- `Cow<'a, str>` for "usually borrowed, sometimes owned" returns (e.g. escaping).
- `Clone` on `Arc` is cheap; write `Arc::clone(&x)` so it reads as a refcount bump.

## 7. Strings, paths, and conversions

- `String`/`&str` are UTF-8; index by byte ranges at char boundaries (`get(a..b)` returns
  `Option`), iterate `chars()`/`char_indices()`; `len()` is bytes.
- OS strings and paths are not UTF-8: keep `PathBuf`/`OsString`; display with
  `path.display()`; convert with `to_str()` (fallible) or `to_string_lossy()`.
- Build strings with `format!`, `write!` into a `String` (`use std::fmt::Write`), or
  `push_str`; avoid `+` chains in loops. Formatting shorthand `format!("{name}: {value:?}")`.
- Bytes: `&[u8]`/`Vec<u8>`; `bytes::Bytes` for cheap shared slices in network code.
- C strings: `CString`/`CStr`, literals `c"text"` *(1.77)*.

## 8. Modules, visibility, macros, const

- Visibility as narrow as possible: private by default, `pub(crate)` for internal sharing,
  `pub` only for the real API. Re-export the public surface from `lib.rs`.
- File layout: `foo.rs` + `foo/bar.rs` (no `mod.rs`) is the modern convention; match the repo.
- Functions and generics before macros. `macro_rules!` for repetitive impls/DSLs; fragment
  `expr` matches `const {}` and `_` in 2024 (use `expr_2021` for the old behavior).
  Procedural macros only when declarative ones cannot express it (separate crate).
- `const fn` for compile-time construction; inline `const { … }` blocks *(1.79)* for
  compile-time asserts: `const { assert!(size_of::<Header>() == 16) };`.
- `cfg_select!` *(1.95)* replaces the `cfg-if` crate; `#[cfg_attr(…)]` for conditional attributes.
- `static` needs `Sync`; mutable global state → `static X: Mutex<T>` / atomics / `OnceLock`.
  `static mut` references are denied in 2024 — use `&raw const`/`&raw mut` if truly needed.
