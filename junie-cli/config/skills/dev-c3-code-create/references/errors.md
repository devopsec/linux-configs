# Errors, cleanup and contracts (0.8.5)

C3 has no exceptions and no `errno`-style sentinels: fallible functions return an **Optional**
(`T?`) that holds either a value or an **excuse** (a `fault` value). Programmer errors are
**contracts**/`assert`s, not faults.

## Declaring faults

```c3
excuse PARSE_FAILED, TOO_LONG;           // 0.8.4+ keyword; stdlib uses it
excuse { BAD_HEADER, BAD_LENGTH }        // block form
faultdef OLD_STYLE;                      // 0.7.0–0.8.x spelling; prefer `excuse` on 0.8.4+
```

- A `fault` is pointer-sized and globally unique; compare with `==`; print with `%s`
  (`err.description` → `"mymod::PARSE_FAILED"`).
- Common stdlib faults: `io::FILE_NOT_FOUND`, `io::EOF`, `io::WOULD_BLOCK`,
  `net::CONNECTION_REFUSED`, `mem::OUT_OF_MEMORY`, builtins `NOT_FOUND`, `NO_MORE_ELEMENT`,
  `TYPE_MISMATCH`, `TIMEOUT`. Find others: `scripts/std-find.sh -a '<NAME>'`.

## Producing and propagating

```c3
fn int? parse_port(String s)
{
    int? n = s.to_int();          // Optional-returning stdlib call
    if (catch err = n) return PARSE_FAILED~;   // translate the excuse
    if (n < 1 || n > 65535) return TOO_LONG~;  // `FAULT~` makes an empty Optional
    return n;                     // n is unwrapped after the catch-return
}

fn void? serve(String host, String port_s)
{
    int port = parse_port(port_s)!;            // `!` rethrows to the caller
    TcpServerSocket srv = tcp::listen(host, port, 128, REUSEADDR)!;
    defer (void)srv.close();
    ...
}
```

| Operation | Syntax |
|---|---|
| return an excuse | `return FAULT~;` |
| rethrow if empty | `expr!` (function must itself return an Optional) |
| panic if empty (tests, truly impossible cases) | `expr!!` |
| default value | `expr ?? fallback` |
| replace the excuse | `expr ?? OTHER_FAULT~`, then rethrow: `expr ?? OTHER_FAULT~!` |
| handle | `if (catch err = expr) { ... }` — `expr` is unwrapped after a scope-exiting catch |
| use value | `if (try v = expr) { ... }`, `while (try v = it.next())`; `&&` allowed, `\|\|` not |
| extract excuse | `fault f = @catch(expr);` / `bool ok = @ok(expr);` |
| ignore deliberately | `(void)file.close();` — discarding an Optional without `(void)` is an error unless `@maydiscard` |

Rules:
- Optionals appear only in variable declarations, expressions and return types — not
  parameters or struct fields (use `Maybe{T}` / `Result{Ok, Err}` from `std::collections`).
- An Optional used in an expression makes the whole expression Optional; a call with Optional
  arguments only runs if all have values (first excuse wins, left to right).
- `void?` cannot be stored; `main` cannot return an Optional.
- **0.8.0 precedence:** `??` and `?:` bind tighter than `+`/`-`: `foo() ?? 0 + 3` is
  `(foo() ?? 0) + 3`.
- C ABI: `fn int? f()` is exported as `c3fault_t f(int* out)`.
- Document faults: `<* @return? io::EOF, parse_port! *>` (`fn!` includes another fn's faults).

## Cleanup with defer

```c3
File f = file::open(path, "rb")!;
defer (void)f.close();                  // runs at every scope exit after this line, LIFO

char[] buf = mem::new_array(char, n);
defer (catch err) free(buf);            // only when leaving with an excuse (ownership transfer on success)
defer try io::printn("committed");      // only on success
```

Declare the `defer` on the line after acquiring the resource — a `!` between acquisition and
`defer` leaks. `defer` also fires on `break`/`continue`/`!`.

## Contracts (`<* *>` blocks)

```c3
<*
 Copies at most dst.len bytes.
 @param [&out] dst : "destination, non-null"
 @param [in] src
 @require [n] n >= 0 && n <= dst.len : "n out of range"
 @ensure return <= n
 @return? io::OVERFLOW
*>
fn sz? copy_n(char[] dst, char[] src, sz n) { ... }
```

- `@require` (pre), `@ensure` (post, `return` names the result), `@param [in|out|inout|&in|own|drop|init]`,
  `@return`, `@return?`, `@deprecated`, `@pure`. Description after `:` is mandatory syntax (0.8.0).
- c3c checks `@require` at call sites too and folds constant violations into compile errors;
  safe builds assert them at runtime; unsafe builds (`-O2+`) **assume** them (UB if violated).
- Use contracts for caller bugs, Optionals for runtime conditions (missing file, bad input,
  network errors). Validate untrusted input with real checks, never only with `@require`.
- Macros: `@require $defined(x.len, x[0]) : "needs indexable"` gives readable errors.

## Assertions and panics

`assert(cond, "fmt %s", x)` (safe builds only), `always_assert(cond, "fmt")` (all builds),
`unreachable("why")`, `$assert(compile_time_cond)`, `$error "msg"`. Panics print a backtrace in
safe builds; `--panic-msg=no`/`-O4+` strip messages.
