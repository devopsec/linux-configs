# Memory: allocators, temp pools, ownership (verified on 0.8.5 stdlib)

Manual memory like C, plus: an `Allocator` interface passed explicitly ("allocator first"), a
per-thread temp allocator scoped by `@pool`, and leak tracking built into `c3c test`.

## The two default allocators

| Name | What | Free with |
|---|---|---|
| `mem` | per-thread heap (`alias mem @builtin = thread_allocator`; libc malloc by default) | `free(p)`, `x.free()`, `alloc::free(mem, p)` |
| `tmem` | current temp allocator (`alias tmem @builtin = current_temp`) | nothing — released when the enclosing `@pool` ends |

`mem` is both a value (the allocator) and a module (`mem::new(Foo)`).

## Allocation API

```c3
Foo* f   = mem::new(Foo);               // zeroed;   mem::new(Foo, { .x = 1 }) initializes
Foo* g   = mem::alloc(Foo);             // uninitialized
int[] xs = mem::new_array(int, n);      // zeroed slice;  mem::alloc_array = uninitialized
void* raw = malloc(64);  free(raw);     // @builtin, no prefix (also calloc/realloc)
int* c   = @clone(42);   int[] d = @clone_slice(xs);
Foo* t   = mem::tnew(Foo);  int[] ta = mem::temp_array(int, n);  void* tr = tmalloc(64);
Foo* h   = alloc::new(my_alloc, Foo);   // explicit allocator: alloc::malloc/new/new_array/clone/free
void*? q = alloc::malloc_try(my_alloc, 64);   // *_try variants return Optionals (OUT_OF_MEMORY)
```

- Plain `alloc::*`/`mem::*` panic on OOM; `*_try` return `mem::OUT_OF_MEMORY~`.
- Types aligned above 16 bytes (`@align(64)`, big SIMD vectors): use `new_aligned`/
  `alloc_aligned`/`@clone_aligned` and free with `free_aligned`.

## Temp memory and @pool

```c3
fn void handle(Request* r) => @pool()        // everything t-allocated below is freed on exit
{
    String body = string::tformat("%s:%d", r.host, r.port);
    List{int} ids; ids.tinit();
    ...
}

fn String build_reply(Allocator a, Request* r)   // return results in the CALLER's allocator
{
    @pool()
    {
        String tmp = r.path.tconcat("/index.html");
        return tmp.copy(a);                       // copy out before the pool ends
    };
}
```

- `@pool` nests; inner pools free only their own allocations.
- The main thread has a temp allocator implicitly. **Raw threads do not**: wrap the thread body
  in `@pool_init(mem, 256 * 1024) { ... }` or the first `tmem` use aborts. `ThreadPool` workers
  set this up themselves.
- Never store temp memory in globals, struct fields that outlive the pool, or pass it to
  another thread. Debug misuse with `-D VMEM_TEMP` (freed temp pages segfault on access).
- `mem::@scoped(tmem) { ... }` swaps what `mem` means for a block.

## Allocator-taking API conventions

- Free functions: allocator first — `string::format(mem, ...)`, `file::load(mem, path)`,
  `path::new(mem, s)`, `json::parse(mem, s)`, `io::readline(mem)`.
- Methods: allocator after `self` — `s.copy(mem)`, `s.split(mem, ",")`, `list.init(mem)`.
- `t`-prefixed twins use `tmem`: `tformat`, `tcopy`, `tsplit`, `tinit`, `treadline`, `tnew`,
  `file::load_temp`, `path::tnew`, `json::tparse` (naming is not fully regular: `temp_array`,
  `to_temp_utf16`, `load_temp`).
- Zero-initialized `List`/`HashMap`/`DString`/sets **silently use `tmem`** on first use. For
  long-lived containers call `x.init(mem)` or start from `list::ONHEAP` / `map::ONHEAP` (globals).
- Containers free their buffers, **not** their elements: free owned elements first.

## Concrete allocators (`std::core::mem::allocators`)

| Allocator | Use | Key API |
|---|---|---|
| `ArenaAllocator` | fixed buffer, bump + mark/reset | `allocators::wrap(&buf)`, `.mark()`, `.reset(m)`, `.clear()` |
| `DynamicArenaAllocator` | growing pages, reset only | `.init(mem, page_size)`, `.reset()`, `.free()` |
| `BackedArenaAllocator` | preallocated block + heap fallback, mark/reset | `allocators::new_backed_allocator(size, mem)!`, `.destroy()` |
| `OnStackAllocator` | stack buffer then fallback | `@stack_mem(4096; Allocator a) { ... };` |
| `TempAllocator` | what `tmem` is | `allocators::push_pool()` / `pop_pool(state)` |
| `TrackingAllocator` | leak detection/report | `.init(mem)`, `.has_leaks()`, `.print_report()`, `.free()` |
| `FixedBlockPool` (`std::core::mem::mempool`) | same-size objects | `.init(mem, block_size)`, `.alloc()`, `.dealloc(p)` |
| `Vmem` (POSIX/Win32) | reserve-then-commit virtual memory | `.init(size)`, `mark/reset/free` |

Implement your own: `struct MyAlloc (Allocator) { ... }` plus `@dynamic` methods
`acquire(sz size, AllocInitType init, sz alignment = 0) -> void*?`, `resize(...)`,
`release(void* ptr, bool aligned)`. Pass it as `Allocator a = &my_alloc;`.

## Ownership rules (write them in doc comments)

1. Whoever passes the allocator owns the result and frees it with the same allocator.
2. Views (`trim`, `strip_prefix`, `split` *elements*, `str_view`, `[a..b]`) borrow from the
   source — the source must outlive them; `DString.str_view()` dies on the next append.
3. `HashMap`/`OrderedMap` copy `String` keys with the map's allocator; `HashSet`, `SortedMap`,
   `TreeSet` do not; values are never owned.
4. `@pool` is the lifetime of every `t*` allocation inside it.

## Leak checking

- `c3c test` runs every `@test` under a `TrackingAllocator` inside a `@pool` and fails on leaks
  (`--test-noleak` to disable — don't, fix the leak).
- `@assert_leak() { ... };` (safe builds or `-D MEMORY_ASSERTS`), `mem::@report_heap_allocs_in_scope() { ... };`
- `--sanitize=address` (ASan, also finds UAF/overflows), `--sanitize=thread` (TSan).
- Test builds poison memory: new allocations filled with `0xAA`, freed memory first byte `0xBA`.
