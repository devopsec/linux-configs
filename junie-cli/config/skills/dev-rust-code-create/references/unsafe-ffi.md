# Unsafe Rust and FFI

`unsafe` means "the compiler can't check this; a human proved it". Every unsafe block needs a
`// SAFETY:` comment that names the preconditions and why they hold. Keep unsafe in small
modules behind safe APIs whose signatures make misuse impossible. If safe code can trigger UB
through your API, the API is unsound — even if no current caller does it.

## Edition 2024 rules (also good style in 2021)

- `unsafe_op_in_unsafe_fn` warns: inside `unsafe fn`, wrap each unsafe operation in its own
  `unsafe {}` block with its own SAFETY comment.
- `extern` blocks must be `unsafe extern "C" { … }`; items inside may be marked `safe fn` /
  `unsafe fn` *(1.82)*.
- Attributes that can cause UB are unsafe: `#[unsafe(no_mangle)]`, `#[unsafe(export_name =
  "…")]`, `#[unsafe(link_section = "…")]`.
- `std::env::set_var`/`remove_var` are `unsafe` (racy with C code reading the environment);
  set env for children via `Command::env` instead.
- No references to `static mut` (`&STATIC_MUT` is denied); use atomics, `Mutex`, `OnceLock`,
  `SyncUnsafeCell`-style wrappers, or `&raw mut STATIC` with care.

## Checklist for unsafe code

- Pointers: non-null, aligned, pointing to an initialized value of the right type, within one
  allocation, not aliased mutably while a `&`/`&mut` to the same memory is live. Prefer
  `NonNull<T>`, `ptr::read_unaligned` for packed/network data, `&raw const`/`&raw mut`
  *(1.82)* to make pointers without creating references.
- Uninitialized memory: `MaybeUninit<T>`, never `mem::uninitialized`/`mem::zeroed` for types
  where zero is invalid (references, `NonZero`, enums, `bool` patterns). Use slice helpers
  `write_copy_of_slice`/`assume_init_ref` *(1.93)*.
- `Vec::set_len` only after initializing the elements; `from_raw_parts` needs the exact
  allocator, capacity, and layout; `Vec::into_parts`/`from_parts` *(1.99)* /
  `into_raw_parts` *(1.93)* round-trip safely.
- `transmute`: almost always replaceable by `from_ne_bytes`/`to_bits`/`cast`/pointer casts or
  `bytemuck`/`zerocopy` (derive-checked safe casts). Never transmute between types without a
  defined layout (`repr(Rust)` structs, `Vec`, fat pointers).
- `unsafe impl Send/Sync`: see `concurrency.md`.
- Lifetimes of returned references from raw pointers are unbounded — tie them to `&self`.
- Drop/panic safety: if code between taking ownership of raw memory and restoring invariants
  can panic, use a guard struct whose `Drop` restores them.

Validate with Miri (`cargo +nightly miri test`; `-Zmiri-strict-provenance`) and sanitizers
(ASan: `RUSTFLAGS=-Zsanitizer=address cargo +nightly test --target x86_64-unknown-linux-gnu`).

## Calling C from Rust

- Generate bindings with `bindgen` (in `build.rs` or checked in), link with `pkg-config` /
  `cc` in `build.rs`; put raw bindings in a `*-sys` crate and a safe wrapper on top.
- Types: `core::ffi::{c_int, c_char, c_void, CStr}`, `std::ffi::CString`; `#[repr(C)]`
  structs and `#[repr(C)]`/`#[repr(u32)]` enums (C enums are not Rust-enum-safe: an unknown
  integer value in a Rust enum is UB — receive the integer and convert with `TryFrom`).
- Strings: `CString::new(s)?` (fails on interior NUL); keep it alive while C uses the pointer
  (`let c = CString::new(..)?; f(c.as_ptr());` — not `CString::new(..)?.as_ptr()`, which dangles).
- Ownership: memory allocated by C is freed by C's free function; memory from Rust (`Box`,
  `CString::into_raw`) is freed by Rust (`Box::from_raw`, `CString::from_raw`).
- Callbacks: `extern "C" fn` trampolines with a `*mut c_void` user-data pointer to a boxed
  Rust closure/state; catch panics with `std::panic::catch_unwind` at the boundary or declare
  `extern "C-unwind"` when unwinding through C is intended.
- C-variadic: calling `printf`-like functions works everywhere; *defining* C-variadic
  functions is stable for several ABIs *(1.91–1.99)*.
- Errors: map C return codes/`errno` (`std::io::Error::last_os_error()`) to `Result` right at
  the wrapper.

## Exposing Rust to C

- `#[unsafe(no_mangle)] pub extern "C" fn mylib_do(…) -> c_int` (2024 syntax); `crate-type =
  ["cdylib", "staticlib"]`; generate headers with `cbindgen`.
- Opaque handles: `Box::into_raw(Box::new(State))` out, `Box::from_raw` in a matching
  `mylib_free`; accept null and document thread-safety.
- Never let a panic unwind out of `extern "C"` (aborts since 1.81); wrap bodies in
  `catch_unwind` and return an error code.

## Inline assembly and target features

- `std::arch::asm!` / `global_asm!` are stable for x86, ARM, RISC-V, LoongArch, s390x, PowerPC;
  document clobbers and use `options(nostack, preserves_flags)` precisely.
- `#[target_feature(enable = "avx2")]` functions can be safe *(1.86)*; calling them from code
  without the feature is unsafe — gate with `is_x86_feature_detected!("avx2")`.
