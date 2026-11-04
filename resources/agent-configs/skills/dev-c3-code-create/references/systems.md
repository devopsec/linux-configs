# Systems programming: networking, concurrency, atomics, SIMD, Linux, performance (0.8.5)

Verified against the 0.8.5 stdlib and `resources/examples/http_server.c3` (poll + worker
threads + channels — read it as the reference architecture for servers).

## Contents
- TCP/UDP sockets
- Non-blocking I/O, poll, epoll
- Threads, pools, channels, sync
- Atomics and lock-free code
- SIMD vectors
- Memory/cache efficiency
- Linux / POSIX / syscalls
- Benchmarking and profiling

## TCP/UDP sockets (`std::net`, `tcp::`, `udp::`; POSIX + Win32)

```c3
import std::net, std::io, std::time;

TcpServerSocket srv = tcp::listen("0.0.0.0", 8080, 128, REUSEADDR)!;   // backlog, SocketOption...
defer (void)srv.close();
TcpSocket c = tcp::accept(&srv)!;                // fault: net::ACCEPT_FAILED (errno not kept)
defer (void)c.close();
char[4096] buf;
sz n = c.read(&buf)!;                            // 0 = peer closed
io::write_all(&c, "pong\n")!;                    // Socket is an InStream/OutStream; write_all retries

TcpSocket out = tcp::connect("example.org", 443, 5 * time::SEC)!;   // timeout → net::CONNECTION_TIMED_OUT
UdpSocket u = udp::connect("10.0.0.1", 514)!;    // connected UDP only (no sendto/recvfrom wrappers)
```

- Faults: `net::CONNECTION_REFUSED/RESET/TIMED_OUT`, `ADDRESS_IN_USE`, `io::WOULD_BLOCK`,
  `io::INTERRUPTED`, else `io::GENERAL_ERROR`.
- `Socket.write` uses `send(..., 0)` → **SIGPIPE** on a closed peer. Ignore it at startup:
  `fn void no_sigpipe() @init(1001) @feat(!WIN32) { libc::signal(libc::SIGPIPE, fn void(CInt) {}); }`
- Options: `SocketOption` covers boolean `SOL_SOCKET` flags (`REUSEADDR`, `REUSEPORT`,
  `KEEPALIVE`, …). `TCP_NODELAY`, buffer sizes, timeouts → call
  `os::setsockopt(sock.sock, level, opt, &val, (Socklen_t)CInt::size)` with your own constants.
- Addresses: `net::ipv4_from_str`, `ipv6_from_str`, `sock.peer_address()/peer_port()`,
  `net::addrinfo(host, port, family, socktype)` (free with `os::freeaddrinfo`).
- `TcpSocketPair` (socketpair / loopback) for self-pipe wakeups. No HTTP client/server in std
  (URL parsing: `url::parse(mem, s)`); use `vendor-fetch curl` or the example server.
- `net::addrinfo` uses `@pool` internally → raw threads need `@pool_init` before `tcp::connect`.

## Non-blocking I/O, poll, epoll

```c3
(void)srv.sock.set_non_blocking(true);
Poll[2] fds = { { .socket = srv.sock, .events = READ }, { .socket = wake.recv.sock, .events = READ } };
ulong ready = net::poll_ms(&fds, 50) ?? 0;        // or net::poll(fds[..], time::ms(50)); -1 = forever
if (fds[0].revents != (PollEvent)0)
{
    while (try cl = tcp::accept(&srv)) (void)cl.sock.set_non_blocking(true);
}
```

- On `io::WOULD_BLOCK`/`io::INTERRUPTED` from `write`, poll for `WRITE` and retry (see
  `http_server.c3:383`).
- Linux epoll: `std::os::linux` — `epoll_create1`, `epoll_ctl`, `epoll_wait`, `EpollEvent`
  (`@packed`). No kqueue/IOCP/io_uring wrappers: declare `extern fn` bindings or use
  `@syscall(nr, args...)`.

## Threads, pools, channels, sync (`std::thread`)

```c3
import std::thread;

fn int worker(void* arg) => @pool_init(mem, 256 * 1024)   // REQUIRED for tmem/@pool on raw threads
{
    Ctx* ctx = arg;
    while (try job = ctx.queue.pop()) handle(job);         // pop fails with CHANNEL_CLOSED → exit
    return 0;
}

Thread[8] workers;
foreach (&t : workers) t.create(&worker, &ctx)!;   // Thread storage must outlive start (BSD/Darwin)
foreach (t : workers) (void)t.join();

ThreadPool pool; pool.init(mem, os::num_cpu())!;     // workers set up tmem themselves
pool.add_task(&task_fn, arg)!;  pool.destroy();      // destroy drains then joins

UnboundedChannel{Job}* q = channel::create_unbounded(mem)!;   // also create_buffered(mem, n),
q.push(job)!; Job j = q.pop()!; q.close(); q.destroy();       // create_unbuffered, create_one_shot

Mutex mu; mu.init()!; defer mu.destroy();
mu.@in_lock() { shared++; };        // or lock()/unlock(); TimedMutex.lock_timeout(ms)
ConditionVariable cv; cv.init()!; cv.wait(&mu); cv.signal(); cv.wait_timeout(&mu, time::ms(5))
OnceFlag once; once.call(&init_fn);
thread::sleep_ms(1); thread::yield();
```

- `mem` is per-thread (`tlocal`), libc-backed by default (thread-safe). `tmem` is per-thread;
  never hand temp memory to another thread.
- Safe builds create error-checking mutexes: relocking aborts ("Mutex deadlock").
- `ThreadPool` idle workers exit after `keep_alive` (default 60 s); `try_add_task` →
  `THREAD_QUEUE_FULL` on bounded queues. `FixedThreadPool`/`ThreadPoolOld` are deprecated.
- `LinkedBlockingQueue{T}` (collections) for bounded producer/consumer with timeouts.

## Atomics and lock-free code

```c3
import std::atomic;
Atomic{int} hits;                        // struct Atomic <Type>; methods default SEQ_CONSISTENT
hits.add(1, RELAXED);  int v = hits.load(ACQUIRE);  hits.store(0, RELEASE);
int expected = 5;
bool ok = hits.compare_exchange(&expected, 6, ACQUIRE_RELEASE, ACQUIRE);  // writes current into expected on failure

int counter;
atomic::fetch_add(&counter, 1, RELAXED);          // returns the OLD value; also fetch_sub/or/and/xor/max/min
int x = @atomic_load(flag, ACQUIRE);  @atomic_store(flag, 1, RELEASE);
int old = mem::compare_exchange(&slot, 0, 1);      // returns witnessed value; NOTE default $volatile = true
thread::fence(SEQ_CONSISTENT);
```

- Orderings: `NOT_ATOMIC, UNORDERED, RELAXED, ACQUIRE, RELEASE, ACQUIRE_RELEASE, SEQ_CONSISTENT`.
- Atomic ops require native-width types (ints, pointers, bool, float ≤ pointer size).
- No exchange/swap macro: build it with a CAS loop.
- Pad hot shared counters to their own cache line to avoid false sharing:
  `struct Padded @align(64) { Atomic{long} v; }` (allocate with `mem::new_aligned`).
- Validate with `--sanitize=thread`.

## SIMD vectors

```c3
float[<4>] a = { 1, 2, 3, 4 };
float[<4>] b = a * 2.0f + 1;                  // element-wise; scalars broadcast
float s = (a * b).sum();  float m = a.max();  float d = a.dot(b);
bool[<4>] gt = a.comp_gt(b);  float[<4>] sel = math::select(gt, a, b);
int[<8>] xs = mem::load((int[<8>]*)p, int::alignment);   // unaligned-safe load (also mem::store)
int[<8>] g = mem::gather(ptrs, mask, passthru);          // masked_load / masked_store / scatter
v.xy = v.zw;  color.rg += { 1, 2 };           // swizzles
alias Vec8i = int[<8>] @simd;                 // @simd: SIMD alignment/ABI for the type
```

- Vectors convert implicitly to/from same-sized arrays; explicitly between element types.
- `--x86cpu=avx2-v2` / `native`, `--x86vec=avx`, project `"x86cpu"`/`"x86vec"`/`"cpu-flags"` control
  codegen; `-O3`+ adds `--loop-vectorize`. Check runtime CPU features before using wide paths
  in portable binaries.
- `--max-vector-size` bounds vector widths (default 4096 bits).

## Memory/cache efficiency

- Prefer arenas/pools for many small objects (`DynamicArenaAllocator`, `FixedBlockPool`,
  `@stack_mem`), `@pool` per request/frame, and `list.reserve(n)` / `init(mem, capacity)`.
- Struct-of-arrays by hand or with `List` per field; `@packed`/`@compact` to shrink, `@align`
  to separate hot data. `Type::size`, `Type::alignment`, `$reflect(Type.field).offset` to check.
- `@prefetch(ptr, NEAR, false)`, `@likely(cond)`, `@unlikely(cond)`, `@expect`.
- Slices bounds-check in safe builds; hot loops can be measured in `-O2` but keep the safe
  build as the default and test both.

## Linux / POSIX / syscalls

- Modules: `std::os::posix`, `std::os::linux` (epoll, ELF types), `std::libc` (C stdlib +
  POSIX bindings: `libc::open`, `mmap`, `shm_open`, `ftruncate`, `signal`, `kill`, `waitpid`…),
  `std::os` (`dlopen`/`dlsym` via `os::dlopen`, `num_cpu`, `exit`).
- errno: `Errno e = libc::errno();` (constset per OS: `EAGAIN`, `EINTR`, …).
- Raw syscalls: `uptr r = @syscall(nr, (uptr)arg1, ...);` (Linux; you supply the number).
- Gate platform code with `@feat(LINUX)` / `$if $feat(POSIX):`.
- Static binaries: `--linux-libc=musl` (or project `"linux-libc": "musl"`); cross targets via
  `--target linux-aarch64` etc.

## Benchmarking and profiling

```c3
fn void bench_parse() @benchmark { parse(SAMPLE)!!; }
fn void setup() @init { set_benchmark_warmup_iterations(5); set_benchmark_max_iterations(1000); }
```

- Run: `c3c benchmark [target]` (project) or `c3c compile-benchmark file.c3`;
  `--benchmark-csv-report` for CSV. Benchmark the optimization level you ship.
- Ad-hoc timing: `Clock c = clock::now(); ...; io::printfn("%s", c.mark());`.
- Profile with `perf record`/`perf report` on a `-O2 -g` build (`-O0`–`-O5` keep debug info;
  project `"debug-info": "full"`), `valgrind --tool=callgrind`, or Tracy (`c3c vendor-fetch tracy`).
- `--print-large-functions` finds compile-time hotspots; `-O3`+ uses single-module builds.
