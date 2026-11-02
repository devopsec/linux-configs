# Generics, macros, compile time, reflection, interfaces, operators (0.8.5)

## Contents
- Generics
- Macros
- Compile-time evaluation
- Reflection (0.8 `::` / `$reflect` model)
- `any`, interfaces, `@dynamic`
- Operator overloading

## Generics

```c3
module mylib::pair <Type>;               // whole module section generic (one instantiation group)
struct Pair { Type a, b; }
fn Type Pair.sum(self) => self.a + self.b;

module mylib;
struct Box <Type> { Type value; }         // declaration-level generic (0.7.9+)
fn Type twice(Type x) <Type> => x + x;    // generic function: params AFTER the parameter list
alias Grid <Type> = Type[16][16];         // generic alias

// Use sites always use {}:
Box{int} b = { 3 };
int t = mylib::twice{int}(21);
alias IntPair = Pair{int};
List{int} l = list::ONHEAP;               // generic args inferred from the target type
```

- Parameters may be types (`Type`, `Key`) or constants (`SIZE`, `MAX`) — named like aliases.
- Declarations sharing a module section *and* identical parameter names instantiate together.
- `@if(cond)` on members/declarations inside generics: `Type last @if(Type::kind == SIGNED_INT);`
- Constrain with contracts on the declaration: `<* @require Type::is_ordered : "needs < " *>`.
- Methods on generic types: `fn Type Box.get(self) => self.value;` (from any module).
- `module foo {Type}` (removed 0.8.0) and `Foo(<int>)` (removed 0.7.0) are obsolete syntax.

## Macros

```c3
macro square(x) => x * x;                          // function-like: no @ prefix needed
macro max_of($Type) => $Type::max;                 // $ = compile-time param
macro void @swap(#a, #b)                           // # = unevaluated expression → name needs @
{
    var tmp = #a; #a = #b; #b = tmp;
}
macro @time(String label; @body())                 // trailing block
{
    Clock c = clock::now();
    @body();
    io::printfn("%s: %s", label, c.mark());
}
@time("parse") { parse_all(); };                   // note the trailing ';'
macro dbg(...)                                     // raw vaargs
{
    $for var $i = 0; $i < $vaarg.len; $i++:
        io::printfn("%s = %s", $stringify($vaarg[$i]), $vaarg[$i]);
    $endfor
}
macro opt(x, int y = ...) { $if $defined(y): return x + y; $else return x; $endif }
```

- Names: `@` prefix required when the macro takes `#expr` params or a trailing `@body`.
- Macros return values (expression macros); recursion is limited (`macro-recursion-depth`).
- `$vaarg.len`, `$vaarg[i]`, `...$vaarg` splat (0.8.0; `$vacount`/`$vasplat`/`$vaexpr` are gone).
- Macro methods: `macro Foo.build(&self) { ... }`.
- `attrmacro @DeprecatedInline = @deprecated, @inline;` (0.8.4 name; `attrdef` earlier) bundles
  attributes: `fn int foo(int x) @DeprecatedInline { ... }`.

## Compile-time evaluation

```c3
$if $feat(LINUX) &&& $defined(linux::epoll_create1):
    use_epoll();
$else
    use_poll();
$endif
$switch $Type::kind:
    $case SIGNED_INT: ...
    $default: ...
$endswitch
$foreach $m : Foo::members:  io::printn($m.name);  $endforeach
$for var $i = 0; $i < 4; $i++:  sum += arr[$i];  $endfor
const int[*] TABLE = @gen_table();                 // macros with only $ params fold to constants
```

- `$if/$switch/$for/$foreach` use trailing `:` (0.7.0) and are only valid inside functions/macros.
  Top-level: `@feat(...)` (and `@if` in generics), `$assert`, `$include`, `$exec`, `$expand`.
- `&&&` / `|||` / `???` (ternary): compile-time operators that skip checking the dead side.
- `$defined(expr, ...)`, `$eval("name")`, `$stringify(#x)`, `$Typeof(x)`, `$Typefrom("int")`,
  `$embed("file", max_len)`, `$echo`, `$error`, `+++` (compile-time concat), `@sprintf(...)`.
- `$include`/`$exec`/project `exec` run at compile time and need `--trust=include`/`--trust=full`
  — treat third-party code using them as code execution.

## Reflection (0.8 model)

| What | Syntax |
|---|---|
| type properties | `Foo::size`, `::alignment`, `::name`, `::qname`, `::kind` (`TypeKind`), `::members`, `::methods`, `::inner`, `::len`, `::min/::max`, `::values`, `::typeid`, `::has_equals`, `::is_ordered`, `::tags`, `::params`, `::returns`, `::param_struct`, `::generic_args` |
| value properties | `$reflect(x).size`, `.offset`, `.name`, `.qname`, `.cname`, `.alignment`, `.bitoffset/.bitsize`, `.tags` |
| shortcuts | `@sizeof(x)`, `@alignof(x)`, `@kindof(x)` |
| member access | `$foreach $m : $Typeof(v)::members: ... v.$m ... $m.name ... $m.type ... $endforeach` |
| tags | `struct Foo @tag("json", "foo")`, `Foo::get_tag("json")`, `Foo::has_tag("json")` |
| enums | `E::len`, `E::values`, `E::names`, `e.description`, `E::from_ordinal(i)`, `E::lookup_field(...)` |
| runtime | `typeid t = Foo::typeid; t.size; t.kind; t.inner; t.names` |

Removed in 0.8.0 (do not use): `Foo.sizeof`, `$sizeof`, `$alignof`, `$offsetof`, `$nameof`,
`$kindof`, `.nameof` (→ `.description`), `Enum.associated`/`.elements`, `$typeof`/`$typefrom`
(→ `$Typeof`/`$Typefrom`), `$assignable`, `$is_const`. 0.8.1: `$m.get(v)`/`$m.set(v, x)` →
`v.$m` / `v.$m = x`.

## `any`, interfaces, `@dynamic`

```c3
interface Shape { fn double area(); fn String name() @optional; }
struct Circle (Shape) { double r; }
fn double Circle.area(&self) @dynamic => math::PI * self.r * self.r;

fn void report(Shape s)                      // interface value = any with method table lookup
{
    io::printfn("%f", s.area());
    if (&s.name) io::printn(s.name());       // optional method present?
}
report(&circle);

any a = &value;                              // typed void*: a.type, a.ptr
switch (a.type) { case int: int* ip = (int*)a; default: }
int*? ip = anycast(a, int);                  // TYPE_MISMATCH on mismatch
```

- Dynamic methods are resolved at runtime (Objective-C style), not vtables in the struct;
  `inline` substructs inherit them. Plain vtable structs of function pointers remain an option
  for hot paths.
- `Printable` (`to_format(Formatter*)`) customizes `%s`; stdlib uses `@dynamic` throughout.

## Operator overloading

```c3
fn Vec2i Vec2i.add(self, Vec2i o) @operator(+) => { self.x + o.x, self.y + o.y };
fn Vec2i Vec2i.scale(self, int k) @operator_s(*) => { self.x * k, self.y * k };   // both orders
fn bool Money.eq(self, Money o) @operator(==) => self.cents == o.cents;
fn bool Money.lt(self, Money o) @operator(<) => self.cents < o.cents;             // + == ⇒ all comparisons (0.8.0)
fn int Buf.get(&self, sz i) @operator([]) => self.data[i];
fn int* Buf.ref(&self, sz i) @operator(&[]) => &self.data[i];
fn void Buf.set(&self, sz i, int v) @operator([]=) { self.data[i] = v; }
fn sz Buf.len(&self) @operator(len) => self.count;                                 // [] + len ⇒ foreach, [^1]
```

- Arithmetic/bitwise overloads only on user-defined types; `+=` derives from `+` unless
  overloaded; `@operator_r` for reversed operand order; `@operator(!=)` was removed (0.8.0).
- Keep semantics conventional (`+` adds; no `<<` for streaming).
