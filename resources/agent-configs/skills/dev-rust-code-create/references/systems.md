# Linux systems and network programming

Prefer std, then safe wrappers (`rustix`, `nix`, `socket2`), then raw `libc` in a small unsafe
module. Check crate APIs at the locked version — `nix` gates modules behind features
(`features = ["socket", "signal", "fs"]`) and changes signatures between majors.

## Crate map

| Need | Crate / API |
|---|---|
| Syscalls with safe types (fds, files, sockets, mmap, time) | `rustix` (no libc needed), `nix` |
| Socket options before bind/connect (SO_REUSEPORT, TCP_NODELAY, buffers, v6only) | `socket2` → convert into std/tokio sockets |
| Readiness I/O (epoll) without a runtime | `mio`; polling crate `polling` |
| Async networking | `tokio::net` (`async.md`) |
| io_uring | `tokio-uring`, `monoio`, `glommio`, or `io-uring` (low level) — thread-per-core models; benchmark against epoll first |
| Signals | `tokio::signal`, `signal-hook` (sync) |
| Memory maps | `memmap2` (mapping is `unsafe`: the file can change underneath) |
| File locking | `File::lock`/`try_lock`/`lock_shared` *(1.89)*, else `fs4`/`fd-lock` |
| Process spawn | `std::process::Command` (never via `sh -c` with interpolated input) |
| User/group, capabilities, namespaces | `nix::unistd`, `caps`, `nix::sched` |
| systemd notify / journald | `sd-notify`, `tracing-journald` |
| inotify / file watching | `notify` |
| eBPF | `aya` |
| Netlink | `rtnetlink`, `neli` |
| Zero-copy buffers | `bytes::{Bytes, BytesMut}`; `zerocopy`/`bytemuck` for wire structs |

## Files and I/O

- Wrap `File` in `BufReader`/`BufWriter` for small reads/writes; `BufWriter` must be
  `flush()`ed (drop flushes but swallows the error).
- Atomic file replace: write to a temp file in the same directory (`tempfile::NamedTempFile::new_in`),
  `sync_all()`, then `persist()`/`rename`; fsync the directory for durability.
- Large files: stream with `read_buf`/`io::copy` (uses `copy_file_range`/`sendfile` where
  possible on Linux) instead of `read_to_end`.
- Permissions: create sensitive files with `OpenOptionsExt::mode(0o600)` at creation, not
  `chmod` afterwards. `std::os::unix::fs::{PermissionsExt, MetadataExt, symlink}`.
- Untrusted paths: canonicalize and check the prefix, or open relative to a directory fd
  (`rustix::fs::openat` with `RESOLVE_BENEATH` via `openat2`); beware TOCTOU between check and use.

## Sockets

- Servers: set `SO_REUSEADDR` (std/tokio listeners do on Unix), consider `SO_REUSEPORT` +
  one listener per core for high accept rates (via `socket2`), set `TCP_NODELAY` for
  request/response protocols, and bound the backlog.
- Timeouts on everything: `set_read_timeout`/`set_write_timeout` (sync) or
  `tokio::time::timeout` (async). Idle connection limits and max frame sizes protect against
  slowloris and memory exhaustion.
- Framing: length-prefixed with a maximum length checked *before* allocating; never trust a
  peer-supplied length for `Vec::with_capacity`.
- Parse network data with explicit endianness (`u32::from_be_bytes`, `bytes::Buf::get_u32`)
  — not by transmuting into `repr(C)` structs (unless via `zerocopy` with checked layout).
- Linux extras in std: `std::os::linux::net::TcpStreamExt::set_quickack` *(1.89)*,
  `SocketAddrExt` for abstract Unix sockets, `UnixStream::pair`, `std::io::pipe` *(1.87)*.
- UDP: one `recv_from` per datagram, buffer sized to the max datagram; for throughput use
  `recvmmsg`/GSO/GRO via `quinn-udp` or `nix`.

## Processes and signals

- `Command::new(prog).args([...])` passes args without a shell; validate `prog` against an
  allow-list if it comes from config. Capture output with `.output()`; stream with
  `Stdio::piped()` and read stdout/stderr concurrently (or one may fill and deadlock).
- Reap children (`wait`), and on shutdown forward SIGTERM to them.
- Signal handlers: never do work in the raw handler; use `signal-hook`'s flag/pipe or
  `tokio::signal::unix::signal(SignalKind::terminate())` and handle in normal code.
- Daemons under systemd: don't fork/daemonize; log to stdout/stderr (journald), use
  `Type=notify` + `sd-notify` for readiness, handle SIGTERM within `TimeoutStopSec`.

## Privilege and hardening

- Drop privileges after binding low ports (`nix::unistd::setgid` then `setuid`), or use
  `CAP_NET_BIND_SERVICE` / systemd socket activation instead of running as root.
- Read secrets from files/env via `secrecy::SecretString` and zeroize (`zeroize`) after use;
  never log them (`#[derive(Debug)]` on a config struct leaks them — implement `Debug` manually).
- `seccomp` (`seccompiler`, `libseccomp`) and `landlock` for sandboxing long-running services.

## Low-level performance knobs

See `performance.md` for profiling. Linux-specific: `SO_BUSY_POLL`, `SO_RCVBUF` sizing,
`sched_setaffinity` (`core_affinity` crate) for thread-per-core designs, huge pages via
`madvise`/`memmap2::MmapOptions::populate`, `posix_fadvise` for streaming reads.
