# C3 language essentials (0.8.5 baseline)

For C programmers: what is the same, what differs, and what the compiler enforces. Syntax that
changed recently is tagged **(0.8.x)**. Older forms: `dev-c3-version-migrate`.

## Contents
- Naming rules (enforced)
- Modules and imports
- Declarations and types
- Integers, sizes and conversions (0.8 signedness rules)
- Arrays, slices, strings
- Control flow
- Functions, methods, lambdas
- Structs, unions, bitstructs, enums, constsets, typedefs, aliases
- Conditional compilation
- Undefined behaviour and safety

## Naming rules (enforced by the parser)

| Kind | Rule | Example |
|---|---|---|
| Types (struct/union/enum/typedef/alias/interface) | `PascalCase`, ≥1 lowercase letter | `HttpRequest`, `Vec3` |
| Functions, macros, variables, params, members | start lowercase | `parse_header`, `@pool` |
| Global constants, enum members, faults | ALL CAPS | `MAX_CONNS`, `FILE_NOT_FOUND` |
| Modules | lowercase + digits + `_`, path segments ≤31 chars | `myapp::net` |

Stdlib convention: `snake_case` everything except types/constants; methods take `self`; Allman
braces and tab indentation in stdlib/vendor. Use `@cname("c_name")` for C-facing names.

## Modules and imports

```c3
module myapp::server;          // every file in a project starts with a module declaration
import std::io, std::net;       // imports are recursive (sub-modules included)
import std;                     // whole stdlib (common in small programs/examples)
import mylib @norecurse;        // only this module, not its children

fn void run() @private { }     // module-private;  @local = file-private
```

- Call functions/macros/globals with the **last module segment**: `io::printn`, `tcp::listen`,
  `string::format`. Types need no prefix unless ambiguous (`List`, `File`, `TcpSocket`).
- `std::core` (and its sub-modules) is implicitly imported; `@builtin` symbols need no prefix
  (`malloc`, `free`, `@pool`, `@clone`, `tmalloc`, `quicksort`, `anycast`, `@catch`, `@ok`).
- Same-root modules see each other (`foo::a` implicitly imports `foo`, `foo::b`).
- One file may hold several `module` sections (e.g. a `module foo @test;` section for tests).
- `import x @public` grants access to `x`'s `@private` symbols (library internals).

## Declarations and types

```c3
int x;                      // zero-initialized (locals too)
int y @noinit;              // explicitly uninitialized
const int MAX = 64;         // compile-time constant (const is a storage class, not a qualifier)
const DEFAULT_PORT = 8080;  // untyped constant
int a; int b = 4;           // no `int a, b = 4;`
var v @safeinfer = foo();   // `var` only in macros/lambdas unless @safeinfer
static int counter;         // function-local static
tlocal int per_thread;      // thread-local
```

No `const`/`volatile` qualifiers: use `@param [in]` contracts, `@volatile_load`/`@volatile_store`.
Function pointers must be aliased: `alias Handler = fn void(int code);`.

## Integers, sizes and conversions (0.8 rules)

- Fixed widths: `ichar/char` 8, `short/ushort` 16, `int/uint` 32, `long/ulong` 64,
  `int128/uint128`; `sz/usz` pointer-difference sized; `iptr/uptr`. C types: `CInt`, `CLong`,
  `CChar`, … (`CLong` ≠ `long` on Windows).
- **Sizes, lengths and indices are signed `sz` (0.8.0, "szmageddon")**: `.len`, `Type::size`,
  container `len()`, slice indices. Use `sz`/`int` for counts and loops; reserve `usz`/unsigned
  for bit patterns, wire formats, hashes. Code full of `usz` is pre-0.8 style.
- **No implicit signed↔unsigned conversion** (0.8.0) — cast explicitly; `unsigned % signed` and
  `/` need casts; comparing unsigned `< 0` is a compile error.
- Small unsigned types promote to `int` (value promotion, like C, 0.8.0).
- Narrowing always needs a cast; implicit widening only for "simple" expressions
  (`long d = a;` ok, `long g = a + b;` error — write `(long)(a + b)` or `(long)a + b`).
- `float`→int needs a cast; int→float is implicit. Literals: decimal = `int` (or wider if
  needed), hex/octal/binary = unsigned; suffixes `u l ul ll ull f d`; `0o777` octal (no `0777`).
- **Signed overflow wraps (2's complement) — defined behaviour.** Opt into traps with
  `--trap-on-wrap`/`"trap-on-wrap": true` while testing; use `math::overflow_add` etc. when you
  need detection.
- Bit operators bind tighter than comparison: `a & b == c` is `(a & b) == c`.
- Evaluation order is defined: left to right; arguments in parameter order.

## Arrays, slices, strings

```c3
int[4] arr = { 1, 2, 3, 4 };      // value type, copied on assignment, no decay
int[*] inferred = { 1, 2, 3 };    // int[3]
int[] s = &arr;                   // slice (ptr + sz len) from array pointer
int[] mid = arr[1..2];            // INCLUSIVE end: { 2, 3 }
int[] two = arr[1:2];             // start:length
int last = arr[^1];               // from the end
int* p = &arr;                    // explicit, no decay
foreach (i, &e : arr) *e += (int)i;   // index is sz; &e by reference
foreach_r (e : s) { }
int[4][2] m;                      // dims read inner-first; index m[1][3]
int[3]* ap = &arr3; int v = ap.[1];   // `.[]` derefs a pointer-to-array before indexing
```

- `String` = `typedef String @constinit = inline char[]` (slice, length-tracked, **not**
  guaranteed NUL-terminated); `ZString` = `inline char*` (C string); `WString` = UTF-16;
  `DString` = growable builder. `==` on `String`/slices compares contents.
- Literals: `"..."` (has hidden `\0`), raw `` `C:\path` ``, `x"DE AD"` hex bytes,
  `b64"..."` base64 bytes, `'FOUR'` multi-char integer literals, `$embed("file.bin")`.
- Slices of strings (`split`, `trim`, `[a..b]`) are NOT NUL-terminated — use
  `s.zstr_tcopy()` / `s.zstr_copy(alloc)` before passing to C.

## Control flow

```c3
switch (x)
{
    case 1:           // empty case falls through to the next
    case 2:
        handle();     // implicit break
    case 3:
        prep();
        nextcase;     // explicit fallthrough
    case 4..9:        // ranges
        nextcase 1;   // jump to another case (structured goto)
    default:
        break;
}
switch { case a > 0: pos(); case a < 0: neg(); }   // if-else chain form
switch (op) @jump { ... }                           // force jump table (interpreters)
for OUTER: (int i = 0; i < n; i++) { for (int j = 0; j < m; j++) if (done) break OUTER; }
do { if (!x) break; } ;        // do-without-while = once
while (try line = it.next()) { }                   // loop while an Optional has a value
```

- No `goto`: use labelled `break`/`continue`, `nextcase`, `defer`.
- Assignment inside a condition needs parentheses: `if ((x = next()))`.
- `/* */` nests; `#!` first line is a comment; `<* *>` is a doc/contract block, not a comment.

## Functions, methods, lambdas

```c3
fn int add(int a, int b = 1) => a + b;              // default args, short body
add(2, b: 3);                                        // named args after positional
fn void log_all(String fmt, args...) {}              // implicit any-vaargs
fn void sum(int... xs) {}  sum(...arr);              // typed vaargs + splat
fn void Point.move(&self, int dx) { self.x += dx; } // method; &self = non-null pointer
p.move(3);                                           // also Point.move(&p, 3)
fn bool State.is_done(self) => self == DONE;         // methods on enums/any type
alias Cmp = fn int(int, int);
Cmp c = fn (a, b) => a - b;                          // lambda: does NOT capture locals
fn void boot() @init { }   fn void bye() @finalizer { }
fn void main(String[] args) { }                      // or fn int main(...); no optional return
```

Methods are for operating on a value (`list.push(x)`), not for "do the whole job" APIs —
prefer `server::run(cfg)` over `cfg.run_server()` (stdlib guideline).

## Structs, unions, bitstructs, enums, constsets, typedefs, aliases

```c3
struct Header @packed { char version; ushort len; }      // no trailing ';'
struct Msg { inline Header hdr; char[] body; union { int code; float f; } }
Msg m = { .hdr.version = 1, .body = data };              // designated init, rest zeroed
Msg m2 = { ...m, .code = 7 };                            // copy-then-override splat

bitstruct Flags : ushort { bool fin : 0; bool syn : 1; char opcode : 4..7; }
bitstruct Perms : char { bool r; bool w; bool x; }      // bool-only short form

enum State : char (String label) { IDLE { "idle" }, RUNNING { "running" } }
State s = RUNNING;           // inferred
s.label; s.ordinal; (int)s;  State::from_ordinal(1);  s.description /* "RUNNING" */
s++;                         // wraps at the ends (0.8.0); `s + 1` is an error

constset Key : int { ESC = 27, SPACE = 32, BANG }       // C-style non-contiguous constants (0.8.4 name; was constdef)
constset Mime : inline String { JSON = "application/json" }

typedef UserId = long;                 // distinct type: no implicit conversion either way
typedef Port @constinit = ushort;      // ... but literals convert:  Port p = 8080;
typedef Bytes = inline char[];         // converts TO char[] implicitly, not from
alias Buffer = char[4096];             // plain alias (C typedef)
alias println = io::printn;            // function/variable alias
```

- `inline` member = subtyping: `Msg*` converts to `Header*`; methods/`@dynamic` inherited.
- Struct layout follows C unless `@packed`, `@align(n)`, `@compact`; use `extern`-compatible
  fixed-width members for ABI/wire data, `@bigendian`/`@littleendian` bitstructs for protocols.
- Struct/union members may not share names with methods.

## Conditional compilation

```c3
fn void poll_impl() @feat(LINUX) { }          // top level: @feat (0.8.3+), not @if
module myapp::win32 @feat(WIN32);             // whole module section
$if $feat(POSIX):                             // inside function bodies
    posix_path();
$endif
const bool HAVE_TLS = env::LINUX || env::DARWIN;   // env:: constants mirror features
```

Features come from the target (`LINUX`, `DARWIN`, `WIN32`, `POSIX`, `LIBC`, `WASM`, …) and
`-D NAME` / project `"features"`. `@if(...)` remains only for generic-parameter conditions.

## Undefined behaviour and safety

- Safe builds (`-O0`, `-O1`, project `"safe": true`) trap with a backtrace on: index out of
  bounds, null deref, division by zero, bad shifts, `unreachable()`, failed `assert`, contract
  violations, reading `@noinit` before write (where detectable).
- `-O2`+ are **unsafe**: checks removed, `assert`/contracts become optimizer assumptions.
  Ship safe builds (`-O1`) unless profiling justifies `-O2`+; `always_assert(cond, "msg")` survives.
- `unreachable("why")`, `assert(cond, "fmt %d", x)`, compile-time `$assert`.
- Comparing/subtracting pointers of different provenance, out-of-range float→int, writing
  string literals: implementation-defined.
