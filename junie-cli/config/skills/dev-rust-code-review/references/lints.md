# Lint configuration and Clippy as a review tool

## Clippy leads for a review (read-only besides `target/`)

Run on the project (this compiles it and executes `build.rs`/proc macros — ask first for
code that isn't the user's own):

```bash
cargo clippy --all-targets --all-features --message-format=short -- \
  -W clippy::pedantic -W clippy::unwrap_used -W clippy::expect_used \
  -W clippy::undocumented_unsafe_blocks -W clippy::multiple_unsafe_ops_per_block \
  -W clippy::indexing_slicing -W clippy::arithmetic_side_effects \
  -W clippy::cast_possible_truncation -W clippy::cast_sign_loss \
  -W clippy::await_holding_lock -W clippy::large_futures \
  -W clippy::dbg_macro -W clippy::todo -W clippy::print_stdout \
  -A clippy::module_name_repetitions -A clippy::must_use_candidate 2>&1 | sort | uniq -c | sort -rn | head -80
```

`pedantic`, `indexing_slicing`, and `arithmetic_side_effects` are noisy: use them to find
leads on untrusted-input paths, not as findings by themselves. Correctness lints
(`clippy::correctness`, deny by default) and `suspicious` are always worth reporting.

Other read-only tools if installed (`../dev-rust-code-create/scripts/rust-env.sh` lists them):
`cargo audit` (RustSec advisories in Cargo.lock), `cargo deny check` (advisories, licenses,
bans, sources), `cargo machete`/`cargo +nightly udeps` (unused deps), `cargo semver-checks`
(public API breaks), `cargo geiger` (unsafe usage in the dependency tree).

## Recommended `[lints]` block

Adapted from BeautifulRust's tested config (morganlinton/BeautifulRust, MIT). Suggest it when
a project has no lint policy; don't impose it in a review of a single change. `[lib]` = fits
libraries; applications can drop those.

```toml
[lints.rust]
unsafe_op_in_unsafe_fn = "warn"            # each unsafe op in its own unsafe block (default in 2024)
missing_debug_implementations = "warn"     # [lib]
missing_docs = "warn"                      # [lib]
unreachable_pub = "warn"
rust_2018_idioms = { level = "warn", priority = -1 }
# unsafe_code = "forbid"                   # crates that should never need unsafe

[lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
# panics
unwrap_used = "warn"
expect_used = "allow"                      # expect("why") is the sanctioned form
panic_in_result_fn = "warn"
missing_panics_doc = "warn"                # [lib]
missing_errors_doc = "warn"                # [lib]
# suppressions must explain themselves (needs rust-version >= 1.81)
allow_attributes = "warn"
allow_attributes_without_reason = "warn"
# unsafe must be justified
undocumented_unsafe_blocks = "warn"
multiple_unsafe_ops_per_block = "warn"
# API shape
fn_params_excessive_bools = "warn"
clone_on_ref_ptr = "warn"
rc_buffer = "warn"
exhaustive_enums = "warn"                  # [lib]
# leftovers
dbg_macro = "warn"
todo = "warn"
print_stdout = "warn"                      # [lib]
print_stderr = "warn"                      # [lib]
# lossy casts
as_conversions = "warn"
cast_possible_truncation = "warn"
cast_sign_loss = "warn"
# pedantic noise
module_name_repetitions = "allow"
must_use_candidate = "allow"
```

`clippy.toml` next to `Cargo.toml`:

```toml
allow-unwrap-in-tests = true
allow-expect-in-tests = true
allow-print-in-tests = true
# msrv = "1.85"    # only if Cargo.toml has no rust-version (clippy reads it from there)
```

CI: `cargo clippy --all-targets --all-features -- -D warnings`. Workspaces: put the tables
under `[workspace.lints.*]` and add `[lints] workspace = true` to each member.

## Suppressions

- Prefer fixing. When a lint is wrong for a site: `#[expect(clippy::x, reason = "…")]`
  (1.81+) — it warns when the suppression becomes unnecessary. `#[allow]` without a reason is
  a review finding (nit, or minor when it hides `unwrap_used`/unsafe lints).
- Crate-wide `#![allow(...)]` in `lib.rs`/`main.rs` deserves a question in review.
