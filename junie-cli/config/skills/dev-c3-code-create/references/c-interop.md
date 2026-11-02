# C interop (0.8.5)

C3 is C-ABI compatible both ways. There is no header translator: write `extern fn`
declarations (or use a vendor binding / third-party generator such as bc3).

## Calling C

```c3
// Style of the official vendor binding (vendor/libraries/sqlite3.c3l/sqlite.c3i) —
// prefer `c3c vendor-fetch sqlite3` over writing it yourself.
module sqlite3;                                // module named after the library
alias SqliteHandle = void*;                    // opaque handle (or `typedef Opaque = void;` + `Opaque*` for type safety)
alias SqliteExecCallback = fn CInt(void* ctx, CInt ncols, ZString* vals, ZString* names);
extern fn CInt open(ZString filename, SqliteHandle* db) @cname("sqlite3_open");
extern fn CInt close(SqliteHandle db) @cname("sqlite3_close");
extern fn ZString errmsg(SqliteHandle db) @cname("sqlite3_errmsg");

extern fn CInt printf(ZString fmt, ...);       // C varargs: only for extern fns
extern CInt some_c_global @cname("lib_global");// extern global

// usage (other module)
SqliteHandle db;
if (sqlite3::open("data.db", &db) != 0) return OPEN_FAILED~;
defer sqlite3::close(db);
```

- Link: `-l sqlite3` / project `"linked-libraries": ["sqlite3"]` + `"linker-search-paths"`, or
  `@link("sqlite3")` on the module/function. libc is linked by default (`link-libc`).
- `@cname("sym")` sets the external symbol; `@asmname` (0.8.5) skips platform decoration
  (macOS leading underscore). `@extern` was removed in 0.8.0.
- Alternative naming style for prefixed C APIs: keep the C name and mark it `@builtin`
  (`extern fn CInt sqlite3_open(...) @builtin;`) — never both prefix-in-module and prefix-in-name
  (`sqlite3::sqlite3_open` is bad).
- Platform-specific declarations: `@feat(LINUX)`, `@feat(WIN32)`.

## Type mapping

| C | C3 |
|---|---|
| `int`, `unsigned`, `long`, `long long`, `char` | `CInt`, `CUInt`, `CLong`, `CLongLong`, `CChar` (`long` is NOT `CLong` on Windows) |
| `int32_t`, `uint64_t`, `size_t`, `ssize_t`, `intptr_t` | `int`, `ulong`, `usz`, `sz`, `iptr` |
| `const char*` string | `ZString` (convert: `s.zstr_tcopy()`, back: `z.str_view()`) |
| `T*` / `T[]` param / `T[4]` param | `T*` / `T*` / `T[4]*` (arrays never decay) |
| `void*` | `void*` (converts implicitly to/from any pointer) |
| struct / union | same declaration (C layout); `@packed`, `@align` as needed |
| enum | `CInt` constants or `constset Foo : CInt { A = 1, … }`; C enums with gaps → `constset` |
| bitfields | `bitstruct` with explicit bit ranges per platform |
| `volatile` | `@volatile_load(x)` / `@volatile_store(x, v)` |
| `_Atomic` | `Atomic{T}` / atomic macros (not ABI-equivalent to C11 atomics in structs) |
| function pointer | `alias Fn = fn void(CInt);` |
| array by value | wrap in a struct |

Names: C type names that violate C3 rules get a minimal prefix in direct bindings
(`HANDLE` → `Win32_HANDLE`, `foo_t` → `Posix_foo_t`); map `size_t` → `usz`, `UINT32` → `uint`.

## Exporting to C

```c3
module mylib;
fn CInt mylib_add(CInt a, CInt b) @export("mylib_add") => a + b;   // explicit unmangled name
fn void? mylib_load(ZString p) @export("mylib_load") { ... }       // C sees: c3fault_t mylib_load(const char*)
```

- Build with `c3c static-lib`/`dynamic-lib` or a `"static-lib"`/`"dynamic-lib"` target; write
  the `.h` by hand (`--header-output` exists but check the result).
- Optionals cross as `c3fault_t f(T* out)`; slices as `{ void* ptr; sz len; }` structs —
  prefer pointer+length parameters on exported APIs.
- Don't let panics or temp memory cross the boundary; allocate with the C side's allocator or
  provide `mylib_free`.

## Compiling C alongside C3

```json5
"c-sources": ["csrc/**"], "c-include-dirs": ["csrc/include"], "cflags": "-O2 -Wall", "cc": "cc"
```

C files are compiled with the project's C compiler and linked in; libraries can ship C sources
in `.c3l` manifests.

## Gotchas

- Memory from C `malloc` → C `free` (or C3 `free`, which is libc-backed by default — but not if
  `mem` was swapped via `@scoped`). Never free C memory with an arena/temp allocator.
- C strings returned by C APIs are borrowed: copy with `z.copy(mem)` before the C side frees them.
- Callbacks into C3 must use C types and must not rethrow Optionals; set up `@pool_init` if a C
  library calls you on its own threads and you touch `tmem`.
- `int` is always 32-bit in C3; `long` 64-bit everywhere (C `long` is 32-bit on Windows).
- Passing `String` (slice) where C expects `char*` compiles via the pointer conversion but is
  not NUL-terminated unless it came from a literal/`copy` — use `ZString`.
