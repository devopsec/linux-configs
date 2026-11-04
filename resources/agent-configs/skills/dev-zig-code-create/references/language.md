# Zig language essentials (0.17 baseline)

Baseline: Zig 0.17.0, verified against its langref and std. Version markers: **(0.15+)** etc.
mean "this form requires at least that version". For older code see `dev-zig-version-migrate`.

## Contents
- Style and naming
- Declarations, result types, decl literals
- Errors
- Optionals and pointers
- Casting and conversions
- Arrays, slices, strings
- Control flow
- Containers: struct / enum / union / packed / extern
- comptime and reflection
- Illegal behavior and build modes
- 0.18-dev (master) deltas

## Style and naming (std style guide; `zig fmt` enforces layout only)

- Types and type-returning functions: `TitleCase` (`ArrayList`, `fn Queue(T: type) type`).
- Functions: `camelCase`. Variables, fields, constants, files of namespaces: `snake_case`.
- A file whose top level *is* a struct (has fields) is named `TitleCase.zig` and used as
  `const Server = @import("Server.zig");` with `const Server = @This();` inside.
- Acronyms follow the case rule: `HttpServer`, `readJson` — not `HTTPServer`.
- Name allocators by contract: `gpa` (caller frees), `arena` (bulk-freed), `scratch`.
- Doc comments: `///` on declarations, `//!` at top of file. `zig fmt` on every file you touch.

## Declarations, result types, decl literals

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;     // alias deep namespaces once at file top

var list: std.ArrayList(u8) = .empty;    // decl literal: resolves to std.ArrayList(u8).empty
const point: Point = .{ .x = 1, .y = 2 }; // anonymous init with a result type
const p2: Point = .init(3, 4);           // decl literal calling Point.init (0.14+)
```

- Prefer `const`; the compiler rejects never-mutated `var` and unused locals/params
  (discard with `_ = x;` only when genuinely unused — not to silence a real bug).
- `undefined` means "no value yet"; reading it is illegal behavior. Arithmetic on `undefined`
  is a compile error (0.15+). Initialize counters explicitly.
- Shadowing is not allowed; pick a new name.
- Destructuring: `const a, const b = .{ 1, 2 };` and `const q, const r = divmod(x);`.

## Errors

```zig
const ParseError = error{ Empty, BadDigit };

fn parse(s: []const u8) ParseError!u32 {
    if (s.len == 0) return error.Empty;
    var n: u32 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return error.BadDigit;
        n = try std.math.mul(u32, n, 10);   // overflow -> error.Overflow (widens the set if inferred)
        n += c - '0';
    }
    return n;
}
```

- Prefer explicit error sets on public APIs; `!T` (inferred) is fine internally. Avoid `anyerror`.
- `try x` ≡ `x catch |e| return e`. Handle specific errors with `catch |err| switch (err) { … }`.
- `errdefer` runs only when the scope exits with an error — pair every acquisition in a
  constructor with `errdefer release();`. **0.17: `errdefer |err|` capture is removed**; log the
  error at the call site (`foo() catch |err| { log…; return err; }`) instead.
- `catch unreachable` asserts impossibility — never use it on allocation, I/O, or parse results.
- Error return traces are on in Debug/ReleaseSafe; `@errorReturnTrace()` for custom reporting.

## Optionals and pointers

- `?T` with `orelse`, `if (opt) |v| … else …`, `while (it.next()) |item|`, `.?` (asserts non-null).
- `*T` single item, `[*]T` many-item (no length), `[]T` slice (ptr+len), `[*:0]u8` / `[:0]u8`
  sentinel-terminated. Prefer slices; many-item pointers are for C interop.
- `*const T` for read-only params. Large structs: pass `*const T` or rely on Zig passing
  by-value params as immutable (the compiler may pass by reference) — never take the address
  of a by-value param and return it.
- Returning `&local` is a dangling pointer; the compiler rejects only trivial cases.
- `@fieldParentPtr("field", ptr)` recovers the container from an embedded interface field —
  the basis of `std.Io.Reader/Writer` implementations.

## Casting and conversions

| Need | Use |
|---|---|
| Widen int/float safely | implicit coercion, or `@as(T, x)` |
| Narrow int, panic if out of range (safe modes) | `@intCast(x)` with a result type |
| Narrow int, return null if out of range | `std.math.cast(T, x)` |
| Keep low bits | `@truncate(x)` |
| int ↔ float | `@floatFromInt`, `@intFromFloat` (panics on out-of-range in safe modes) |
| enum/packed ↔ backing int **(0.17)** | `@backingInt(e)`, `@fromBackingInt(i)` (`@intFromEnum`/`@enumFromInt` deprecated; `zig fmt` rewrites) |
| int → enum, untrusted input | `std.enums.fromInt(E, i)` → `?E` |
| bool → int | `@intFromBool(b)` |
| pointer reinterpret | `@ptrCast(p)`; add `@alignCast` when alignment increases |
| same-size value reinterpret | `@bitCast(v)` — **0.17: logical bits, endian-agnostic; not allowed on `extern struct/union`** (use `@ptrCast(&v).*` or an `extern union`) |
| drop const/volatile | `@constCast`, `@volatileCast` (smell; justify) |

Cast builtins infer the destination from the result type: `const n: u8 = @intCast(len);`
or `@as(u8, @intCast(len))` inline.

## Arrays, slices, strings

```zig
var buf: [4096]u8 = undefined;
var zeros: [64]u32 = @splat(0);            // 0.17: `[_]u32{0} ** 64` is removed
const slice = buf[0..n];                   // runtime-length slice
const fixed = buf[0..16];                  // comptime length -> *[16]u8
const tail = s[i..];                       // to end
for (items, 0..) |item, i| { … }           // index capture
for (a, b) |x, y| { … }                    // lockstep; lengths must match (safety-checked)
for (0..n) |i| { … }                       // range
```

- Strings are `[]const u8` (bytes, conventionally UTF-8). Literals are `*const [N:0]u8` and
  coerce to `[]const u8` and `[:0]const u8`.
- Compare with `std.mem.eql(u8, a, b)`, never `==` (that compares pointers/arrays).
- Search: `std.mem.find` / `findScalar` / `findAny` (0.17 names; `indexOf*` are deprecated
  aliases), `std.mem.startsWith`, `std.mem.splitScalar`, `std.mem.tokenizeAny`, `std.mem.trim`. Concatenate at comptime with `++`; at runtime with `allocator.print` (0.17) or
  `std.mem.concat`.
- Multiline literal: lines starting with `\\`.
- 0.17: a slice with comptime-known length can be dereferenced to an array (`s.*`) or coerced to
  `*const [N]T`.

## Control flow

- `switch` must be exhaustive; `else` only when intentional. Ranges `1...5`, multiple `.a, .b =>`.
- Labeled switch for state machines (0.14+): `sw: switch (state) { .a => continue :sw .b, … }`.
- Labeled blocks yield values: `const v = blk: { …; break :blk x; };`.
- `while (cond) : (i += 1) { … }` continue-expression; `inline for`/`inline while` unroll at comptime.
- `defer` runs at scope exit in reverse order — put it on the line right after acquisition.
- `@branchHint(.cold)` / `.unlikely` as the first statement of a block (replaces `@setCold`).

## Containers

```zig
const Shape = union(enum) {                // tagged union: switch to access payload
    circle: f32,
    rect: struct { w: f32, h: f32 },

    pub fn area(self: Shape) f32 {
        return switch (self) {
            .circle => |r| std.math.pi * r * r,
            .rect => |r| r.w * r.h,
        };
    }
};

const Id = enum(u32) { _ };                // distinct integer type (non-exhaustive enum)
const Flags = packed struct(u8) { read: bool, write: bool, _pad: u6 = 0 };
const CHeader = extern struct { magic: u32, len: u32 };   // C ABI layout
```

- Plain `struct` has **no defined layout** — the compiler may reorder fields. Use `extern` for
  C ABI/on-disk formats and `packed` for bit-exact layouts.
- Methods are namespaced functions; `self: *T` to mutate, `self: T` / `*const T` to read.
- Reading an inactive union field is safety-checked illegal behavior — switch on the tag.
- `@This()` names the enclosing type; `usingnamespace` no longer exists (0.15) — re-export
  explicitly: `pub const foo = other.foo;`.
- Interfaces: either `anytype` + duck typing (comptime) or a vtable struct
  `{ ptr: *anyopaque, vtable: *const VTable }` (runtime), as `std.mem.Allocator` and `std.Io` do.

## comptime and reflection

```zig
fn Stack(comptime T: type, comptime cap: usize) type {
    return struct {
        items: [cap]T = undefined,
        len: usize = 0,
        const Self = @This();
        pub fn push(self: *Self, v: T) error{Full}!void {
            if (self.len == cap) return error.Full;
            self.items[self.len] = v;
            self.len += 1;
        }
    };
}
```

- `comptime` params make generics; `anytype` params are inferred per call site (document the
  expected interface; check with `@hasDecl`/`@TypeOf` and `@compileError` messages).
- `@hasDecl` sees **only `pub`** declarations (0.17).
- Reflection (0.17, struct-of-arrays): `@typeInfo(T).@"struct".field_names`, `.field_types`,
  `.field_attrs`; enums: `.field_names`, `.field_values`. Iterate with
  `inline for (info.field_names, info.field_types) |name, FT| { … @field(value, name) … }`.
  Tags are lowercase and keyword-quoted: `.@"struct"`, `.@"enum"`, `.@"union"`, `.@"fn"`,
  `.int`, `.pointer`, `.optional`.
- Type construction: `@Int(.unsigned, 7)`, `@Struct(layout, BackingInt, names, types, attrs)`,
  `@Union(...)`, `@Enum(TagInt, mode, names, values)`, `@Pointer`, `@Fn`, `@Tuple`,
  `@EnumLiteral()` (`@Type` was removed in 0.16). Default attrs: `&@splat(.{})`; the attrs type
  is `std.lang.Type.Struct.FieldAttributes` in 0.17 (`std.builtin.Type.StructField.Attributes` in 0.16).
- Long comptime loops need `@setEvalBranchQuota(n)`.
- `std.meta`: `FieldEnum`, `Tag`, `activeTag`, `eql`, `ArgsTuple` (`std.meta.fields` is a
  `@compileError` in 0.17 — use `@typeInfo`); `std.enums`:
  `EnumArray`, `EnumMap`, `EnumSet`, `fromInt`.

## Illegal behavior and build modes

| Mode | `-Doptimize=` | Safety checks | Use |
|---|---|---|---|
| Debug | (default) | on | development, tests |
| ReleaseSafe | `ReleaseSafe` | on | production default for most software |
| ReleaseFast | `ReleaseFast` | off | measured hot paths only |
| ReleaseSmall | `ReleaseSmall` | off | size-constrained targets |

Safety-checked illegal behavior (panics in Debug/ReleaseSafe, UB otherwise): integer overflow on
`+ - * /`, out-of-bounds index, `.?` on null, wrong union field, invalid enum value,
`unreachable`, misaligned `@alignCast`, `@intCast` out of range, division by zero. Use
`+%` / `+|` for intentional wrapping / saturating math, `std.math.add/mul` for checked math
returning `error.Overflow`. `@setRuntimeSafety(false)` only inside measured, reviewed blocks.
`std.lang.Optimize` (0.17 name; `std.builtin.OptimizeMode` is a deprecated alias) has
lowercase tags `.debug/.safe/.fast/.small`; build options still use `ReleaseSafe` spelling.

## 0.18-dev (master) deltas — only if `zig-env.sh` reports `0.18.0-dev…`

- **Partial operator precedence**: mixing operators without a defined relative precedence is a
  compile error — parenthesize. Errors include `a or b and c`, `x orelse y == z`,
  `a catch b orelse c`, `1 ^ 2 | 3`, `a << b << c`, `a % b % c`, chained comparisons. Arithmetic
  `+ - * /` and homogeneous `and`/`or`/`&`/`|`/`^` chains are fine. Writing explicit parens
  now keeps code valid on both 0.17 and 0.18.
- `@splat` accepts a scalar result type (returns the element).
- `\u{…}` escapes accept any code point (incl. surrogates); `'\u{10000}'` is an integer literal.
