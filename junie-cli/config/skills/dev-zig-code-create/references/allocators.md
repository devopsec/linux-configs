# Memory: allocators, ownership, containers (verified on 0.17)

Zig has no hidden allocation. Anything that allocates takes a `std.mem.Allocator`; anything that
returns allocated memory documents who frees it. Most containers are **unmanaged** (0.15+): they
do not store the allocator, so every allocating method takes it.

## Choosing an allocator

| Situation | Allocator |
|---|---|
| Application `main` | `init.gpa` from juicy main (SafeAllocator in safe modes, smp/c allocator in fast modes) |
| Tests | `std.testing.allocator` (fails the test on leaks) |
| Request/frame/phase lifetime | `std.heap.ArenaAllocator.init(gpa)` → free everything with one `deinit` / `reset(.retain_capacity)`; thread-safe since 0.16 |
| Process lifetime | `init.arena.allocator()` |
| Bounded scratch, no heap | `std.heap.FixedBufferAllocator.init(&buf)` |
| Small-usually, sometimes big | `std.heap.BufferFirstAllocator.init(&buf, gpa)` **(0.17; replaces `StackFallbackAllocator(N)`)** |
| Many same-type objects | `std.heap.MemoryPool(T)` — `.empty`, `create(gpa)`, `destroy(ptr)`, `deinit(gpa)` |
| Release, multithreaded, no libc | `std.heap.smp_allocator` |
| Linking libc anyway | `std.heap.c_allocator` |
| Debugging leaks/UAF yourself | `var s: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{}); defer _ = s.deinit();` **(0.17; `DebugAllocator`/`GeneralPurposeAllocator` are deprecated/removed)** — `deinit` returns the leak count |

`std.heap.page_allocator` maps whole pages per call — back other allocators with it, don't use
it directly for small objects.

## Allocator API

```zig
const p = try gpa.create(Node);        defer gpa.destroy(p);
const buf = try gpa.alloc(u8, n);      defer gpa.free(buf);
const copy = try gpa.dupe(u8, src);    // owned copy; dupeSentinel(u8, src, 0) for [:0]u8
const s = try gpa.print("{s}:{d}", .{ host, port });   // 0.17 (std.fmt.allocPrint deprecated)
buf2 = try gpa.realloc(buf2, new_len); // may move; resize()/remap() try in place
```

## Ownership rules

- `defer free` on the line after a successful allocation; `errdefer free` when ownership
  transfers to the caller on success:

```zig
pub fn init(gpa: Allocator, name: []const u8) !Server {
    const owned = try gpa.dupe(u8, name);
    errdefer gpa.free(owned);
    const table = try gpa.alloc(Entry, 64);
    errdefer gpa.free(table);
    return .{ .name = owned, .table = table };
}

pub fn deinit(self: *Server, gpa: Allocator) void {
    gpa.free(self.table);
    gpa.free(self.name);
    self.* = undefined;      // poison: use-after-deinit trips safety checks in Debug
}
```

- Store the allocator in a struct only when it truly owns long-lived resources; otherwise pass
  it to each method (`deinit(self, gpa)`), matching std style.
- Never free with a different allocator than allocated; never free arena memory individually
  (it's a no-op at best, confusing at worst).
- Slices returned from containers (`list.items`, `map.get`) are invalidated by any mutation that
  can reallocate. Pointers into an `ArrayList` die on `append`.
- Prefer returning owned data via out-param buffers or `toOwnedSlice` over exposing internals.

## Containers

```zig
var list: std.ArrayList(u32) = .empty;          // unmanaged (std.array_list.Managed is the legacy form)
defer list.deinit(gpa);
try list.append(gpa, 1);
try list.appendSlice(gpa, &.{ 2, 3 });
try list.ensureUnusedCapacity(gpa, 10);
list.appendAssumeCapacity(4);
_ = list.pop();                                  // ?T
const last = list.last();                        // 0.17: ?T  (getLast/getLastOrNull deprecated)
for (list.items) |x| _ = x;
const owned = try list.toOwnedSlice(gpa);        // list is empty afterwards
defer gpa.free(owned);

var stack_buf: [16]u32 = undefined;              // fixed-capacity list, no allocator
var bounded: std.ArrayList(u32) = .initBuffer(&stack_buf);
try bounded.appendBounded(7);                    // error.OutOfMemory when full (replaces BoundedArray)

var map: std.StringHashMapUnmanaged(u32) = .empty;
defer map.deinit(gpa);
try map.put(gpa, "a", 1);
const gop = try map.getOrPut(gpa, key);          // insert-or-update without double hashing
if (!gop.found_existing) gop.value_ptr.* = 0;
gop.value_ptr.* += 1;
// Maps do NOT copy string keys: dupe them if the source buffer is temporary.

var ordered: std.array_hash_map.String(u32) = .empty;   // insertion-ordered; .keys()/.values() slices
var by_id: std.AutoHashMapUnmanaged(u64, *Node) = .empty;
```

- `std.AutoHashMap`/`std.StringHashMap` (managed, stores allocator, `.init(gpa)`) still exist;
  new code should use the `…Unmanaged` forms with `.empty`.
- 0.16 removed managed array hash maps: use `std.array_hash_map.Auto/String/Custom`.
- `std.MultiArrayList(T)` — struct-of-arrays storage (`.items(.field)`), cache-friendly loops.
- `std.Deque(T)`, `std.PriorityQueue(T, Ctx, lessThan)` (`push`/`pop` since 0.16),
  `std.SinglyLinkedList` / `DoublyLinkedList` (intrusive: embed the node, recover with
  `@fieldParentPtr`), `std.bit_set.Static/Dynamic/Integer` (0.17 names), `std.EnumArray/EnumSet/EnumMap`,
  `std.StaticStringMap(V).initComptime(.{ .{ "k", v } })` for comptime lookup tables.
- When unsure of a container's current method names: `scripts/std-find.sh -b 'Aligned' array_list`.

## Data-oriented tips

- Index into arrays (`u32` ids) instead of storing pointers in long-lived graphs: stable across
  reallocation, half the size, serializable. Wrap ids as `enum(u32) { _ }` for type safety.
- Split hot and cold fields (`MultiArrayList`), keep structs small, avoid per-item allocation in
  hot loops (arena or pool instead).
- Measure before using `ReleaseFast` or disabling safety — ReleaseSafe is usually fast enough.
