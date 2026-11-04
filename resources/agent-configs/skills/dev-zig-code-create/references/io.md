# std.Io: entry points, files, streams, time, concurrency, networking (0.16+, verified on 0.17)

Since 0.16 every operation that can block — files, sockets, sleep, clocks, randomness, mutexes,
child processes — takes an `io: std.Io` parameter. `std.fs.cwd()`, `std.io.getStdOut()`,
`std.net`, `std.time.sleep/timestamp`, `std.Thread.Mutex/Pool`, `std.crypto.random` are gone.
**Do not** reach for libc/pthreads to "work around" this; thread `io` through the call graph.

## Contents
- main signatures
- Getting an `Io` outside main
- stdout / stderr / logging
- Formatting
- Files and directories
- Readers and writers
- Time, sleep, randomness
- Concurrency and synchronization
- Networking
- Child processes, args, environment

## main signatures

```zig
pub fn main() !void {}                                   // no args/env/io
pub fn main(init: std.process.Init.Minimal) !void {}     // raw args + environ only
pub fn main(init: std.process.Init) !void {              // "juicy main" — default choice
    const gpa = init.gpa;                    // SafeAllocator in Debug/ReleaseSafe (leak report on exit)
    const arena = init.arena.allocator();    // process-lifetime, thread-safe
    const io = init.io;                      // std.Io.Threaded
    const args = try init.minimal.args.toSlice(arena);   // []const [:0]const u8
    const home = init.environ_map.get("HOME");           // ?[]const u8
    _ = .{ gpa, io, args, home };
}
```

Return type: `void`, `!void`, `u8`, `!u8`, or `noreturn`. Fatal exit with message:
`std.process.fatal("bad input: {s}", .{path});` — plain exit: `std.process.exit(code)`.

## Getting an `Io` outside main

- Libraries: take `io: std.Io` as a parameter (next to the allocator). Never create one inside.
- Tests: `std.testing.io` (and `std.testing.allocator`).
- Standalone harnesses/tools without juicy main:

```zig
var threaded: std.Io.Threaded = .init(gpa, .{});
defer threaded.deinit();
const io = threaded.io();
```

`std.Io.Threaded.global_single_threaded.io()` exists for last-resort contexts (panic handlers,
legacy shims); prefer passing `io`.

## stdout / stderr / logging

```zig
var stdout_buf: [4096]u8 = undefined;
var stdout_fw: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
const out = &stdout_fw.interface;            // *std.Io.Writer
try out.print("{d} items\n", .{n});
try out.flush();                             // buffered: nothing appears without flush

try std.Io.File.stdout().writeStreamingAll(io, "unbuffered one-shot\n");
std.debug.print("debug {any}\n", .{value});  // stderr, unbuffered, no io needed, ignores errors
std.log.info("starting {s}", .{name});       // stderr; level via std_options
const log = std.log.scoped(.server);         // log.warn(...) prints "warning(server): ..."
```

Root-file overrides: `pub const std_options: std.Options = .{ .log_level = .info };`.

## Formatting

- Specifiers (doc comment on `std.Io.Writer.print`): `{d}` decimal, `{s}` string, `{c}` byte,
  `{u}` code point, `{x}`/`{X}` hex, `{b}`/`{o}` binary/octal, `{e}` sci, `{any}` debug dump,
  `{?d}` optional, `{!d}` error union, `{t}` enum/union/error tag name, `{f}` call `format`,
  `{q}` quoted/escaped string, `{b64}` base64, `{B}`/`{Bi}` byte sizes, `{*}` address.
  `{}` alone is rejected for most types — always pick a specifier.
- Width/fill/precision: `{d:>8}`, `{s:<10}`, `{d:0>4}`, `{d:.3}`.
- Custom formatting (0.15+): `pub fn format(self: T, w: *std.Io.Writer) std.Io.Writer.Error!void`
  and print with `{f}` (`{}` no longer calls it). Alternate renderings: `std.fmt.Alt`.
- Allocate a string: `try gpa.print("{s}-{d}", .{a, b})` **(0.17; `std.fmt.allocPrint` is a
  deprecated alias)**, `gpa.printSentinel(..., 0)`. Into a buffer: `std.fmt.bufPrint(&buf, ...)`.
- Growable output: `var aw: std.Io.Writer.Allocating = .init(gpa); defer aw.deinit();`
  write via `&aw.writer`, then `aw.written()` (borrowed) or `try aw.toOwnedSlice()`.
- Fixed buffer: `var w: std.Io.Writer = .fixed(&buf); try w.print(...); w.buffered()`.
- Discard but count: `std.Io.Writer.Discarding.init(&buf)`.

## Files and directories

```zig
const cwd = std.Io.Dir.cwd();

// Whole file (bounded): error.StreamTooLong past the limit.
const data = try cwd.readFileAlloc(io, "config.json", gpa, .limited(1 << 20));
defer gpa.free(data);

// Write whole file.
try cwd.writeFile(io, .{ .sub_path = "out.txt", .data = bytes });

// Streaming write.
const file = try cwd.createFile(io, "log.txt", .{ .truncate = true });
defer file.close(io);
var buf: [8192]u8 = undefined;
var fw = file.writer(io, &buf);
try fw.interface.print("{s}\n", .{line});
try fw.interface.flush();

// Line-by-line read.
const in = try cwd.openFile(io, "input.txt", .{});
defer in.close(io);
var rbuf: [4096]u8 = undefined;
var fr = in.reader(io, &rbuf);
while (try fr.interface.takeDelimiter('\n')) |line| { // null at EOF; error.StreamTooLong if > buffer
    _ = line;
}

// Directories.
try cwd.createDirPath(io, "build/out");                // mkdir -p
var dir = try cwd.openDir(io, "src", .{ .iterate = true });
defer dir.close(io);
var it = dir.iterate();
while (try it.next(io)) |entry| {                      // entry.name, entry.kind
    if (entry.kind == .file) {}
}
var walker = try dir.walk(gpa);                        // recursive; walkSelectively to prune
defer walker.deinit();
```

Other `Dir` methods (all take `io`): `access`, `statFile`, `deleteFile`, `deleteTree`, `rename`,
`renamePreserve`, `symLink`, `readLink`, `realPath`, `createFileAtomic` (temp + rename),
`openFileAbsolute`/`openDirAbsolute`. Paths: `std.fs.path.join(gpa, &.{a, b})`,
`std.fs.path.basename/dirname/extension`. `std.fs` itself now holds only `path` and limits.

## Readers and writers

`std.Io.Reader` and `std.Io.Writer` are concrete structs with a caller-provided buffer and a vtable
(not generic, not `anytype`). Implementations (`File.Reader`, `net.Stream.Writer`, …) expose them
as `.interface`; pass `*std.Io.Reader` / `*std.Io.Writer` around.

| Reader op | Meaning |
|---|---|
| `.fixed(bytes)` | read from memory |
| `take(n)` / `takeArray(n)` / `takeByte()` | consume exactly n (error.EndOfStream if short) |
| `peek(n)` / `peekByte()` | look ahead without consuming |
| `takeInt(T, .little)` / `takeLeb128(T)` / `takeStructPointer(T)` | binary decoding |
| `takeDelimiter(d)` → `?[]u8` | line reading; excludes delimiter; null at EOF |
| `takeDelimiterExclusive/Inclusive(d)` | strict variants (EndOfStream at EOF) |
| `readSliceAll(buf)` | fill caller buffer |
| `allocRemaining(gpa, .limited(n))` | read rest into a new allocation |
| `stream(w, limit)` / `streamRemaining(w)` | pipe into a writer |
| `discardAll(n)` | skip |

Slices returned by `take*`/`peek*` point into the reader's buffer and are invalidated by the
next read — copy (`gpa.dupe(u8, s)`) anything you keep. Buffer size bounds the longest line
you can `takeDelimiter`.

Writer ops: `writeAll`, `print`, `writeByte`, `splatByteAll`, `writeInt`, `writeVecAll`,
`sendFileAll(file_reader, limit)` (zero-copy where supported), `flush`. Always `flush` before
the buffer goes out of scope or before handing control to code that reads the output.

## Time, sleep, randomness

```zig
const start = std.Io.Clock.awake.now(io);              // monotonic; .real = wall clock, .boot
// ... work ...
const elapsed = start.untilNow(io, .awake);            // std.Io.Duration
std.log.info("took {d} ms", .{elapsed.toMilliseconds()});

const unix_s = std.Io.Clock.real.now(io).toSeconds();  // wall-clock seconds since epoch
try io.sleep(.fromMilliseconds(250), .awake);          // error.Canceled is possible

var seed: u64 = undefined;
io.random(std.mem.asBytes(&seed));                     // fast, non-crypto
var prng: std.Random.DefaultPrng = .init(seed);
const r = prng.random();
_ = r.intRangeAtMost(u8, 1, 6);

var key: [32]u8 = undefined;
try io.randomSecure(&key);                             // CSPRNG; error.EntropyUnavailable
```

`std.time` keeps only constants (`ns_per_ms`, …) and `std.time.epoch` calendar helpers.

## Concurrency and synchronization

```zig
// Fire-and-await one task.
var fut = io.async(fetchOne, .{ io, gpa, url });       // returns std.Io.Future(T)
const body = try fut.await(io);                        // or fut.cancel(io) on early exit

// Fan-out with a group (replaces std.Thread.Pool + WaitGroup).
var group: std.Io.Group = .init;
defer group.cancel(io);                                // cancels anything still running on error paths
for (jobs) |job| group.async(io, runJob, .{ io, job });
try group.await(io);

// Shared state.
var mutex: std.Io.Mutex = .init;
try mutex.lock(io);                                    // cancelation point; lockUncancelable(io) otherwise
defer mutex.unlock(io);
```

- `io.async` may run inline (no thread available); `io.concurrent` / `group.concurrent`
  *require* true concurrency and return `error.ConcurrencyUnavailable` otherwise — use it for
  producer/consumer pairs that would deadlock if serialized.
- Other primitives: `std.Io.Condition`, `std.Io.Event`, `std.Io.Semaphore`, `std.Io.RwLock`,
  `std.Io.Queue(T)` (`.init(&buf)`, `putOne/getOne(io, …)`, `close(io)`), `std.Io.Select`.
- Cancelation: blocking `Io` calls can return `error.Canceled`; propagate it (do not swallow) so
  `cancel` can unwind. `std.atomic.Value(T)` for lock-free counters.
- Raw threads still exist: `std.Thread.spawn(.{}, func, .{args})` + `join()`; they do not get
  cancelation — prefer `Io` APIs.

## Networking (`std.Io.net`)

```zig
// Client by IP or by host name.
const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 8080);
var stream = try addr.connect(io, .{ .mode = .stream });
defer stream.close(io);

const host: std.Io.net.HostName = try .init("example.com");
var s2 = try host.connect(io, 443, .{ .mode = .stream });
defer s2.close(io);

var wbuf: [1024]u8 = undefined;
var sw = stream.writer(io, &wbuf);
try sw.interface.writeAll("ping\n");
try sw.interface.flush();
var rbuf: [1024]u8 = undefined;
var sr = stream.reader(io, &rbuf);
const reply = try sr.interface.takeDelimiter('\n');

// Server.
var server = try addr.listen(io, .{ .reuse_address = true });
defer server.deinit(io);
while (true) {
    const conn = try server.accept(io);
    group.async(io, handle, .{ io, conn });            // handle() closes conn
}
```

HTTP: `std.http.Client` (`.{ .allocator = gpa, .io = io }`; check `std-find.sh -b Client http`)
and `std.http.Server` sit on these streams. TLS: `std.crypto.tls.Client`.

## Child processes, args, environment

```zig
const result = try std.process.run(gpa, io, .{ .argv = &.{ "git", "rev-parse", "HEAD" } });
defer { gpa.free(result.stdout); gpa.free(result.stderr); }
switch (result.term) { .exited => |code| if (code != 0) return error.GitFailed, else => return error.GitCrashed }

var child = try std.process.spawn(io, .{ .argv = argv });   // long-running; then child.wait(io)
```

- Args: `init.minimal.args.iterate()` (lazy) or `.toSlice(arena)`.
- Env: `init.environ_map.get("KEY")`; pass `*const std.process.Environ.Map` to code that needs
  it — there is no global `getenv` in std anymore.
- Paths: `std.process.currentPathAlloc(io, gpa)`, `std.process.executablePathAlloc(io, gpa)`.
