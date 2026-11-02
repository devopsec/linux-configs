# Standard library: strings, collections, I/O, OS, time, encoding (0.8.5)

Signatures summarized from the 0.8.5 stdlib; confirm details with `scripts/std-find.sh`.
Networking/threads/atomics/SIMD: `systems.md`. Allocation rules: `allocators.md`.

## Contents
- Printing and formatting
- Strings and DString
- Collections
- Files, streams, paths
- Processes, environment, exit
- Time and sleep
- JSON, Object, other encodings
- Sorting, hashing, random

## Printing and formatting (`std::io`)

```c3
io::printn("hello");             io::print(x);           // macros; any type; errors dropped
io::printfn("%s = %d", name, n); io::printf("%x\n", v);  // return sz?, @maydiscard
io::eprintn("err");  io::eprintfn("%s", err);            // stderr
io::fprintfn(&file, "%s", x)!;   io::bprintf(buf[..], "%d", 7)!;   // stream / fixed buffer
String s  = string::format(mem, "%s-%d", a, b);   // caller frees
String ts = string::tformat("%s-%d", a, b);       // temp
```

- Specifiers: `%d` (any int incl. int128, signed or not — no `%u`/`%lld`), `%x %X %o %b`,
  `%f %e %g %a`, `%c` (Char32 → UTF-8), `%s` (anything: enums print names, faults their
  description, slices `[a, b]`, vectors `[<a, b>]`), `%p`, `%h`/`%H` hex dump; flags `0 - + space #`,
  width/precision incl. `*`. Unknown spec prints `<BAD FORMAT>`.
- `@format(n)` on a function makes c3c check printf formats at compile time.
- `io::printn(my_struct)` prints fields; `printf("%s", my_struct)` prints `<struct ...>` unless
  the type implements `Printable` (`fn sz? to_format(Formatter* f) @dynamic`).
- Flushing: `printn`/`printfn`/`eprintfn` flush; `print`/`printf` (no `\n`) may not.

## Strings and DString

```c3
String s = "  key=value  ";
String t = s.trim();                         // view, no allocation
if (t.starts_with("key")) { }                // ends_with, contains, contains_char, count
if (try i = t.index_of("="))                 // sz? — NOT_FOUND when absent
{
    String key = t[:i];  String val = t[i + 1..];
}
String[] parts = t.split(mem, "=");  defer free(parts);   // array allocated; elements are views
String[] tparts = t.tsplit(",");
Splitter it = t.tokenize(",");  while (try tok = it.next()) { }
int? n = "42".to_int();   double? d = "3.5".to_double();  long? l = s.to_long(16);
String up = s.to_upper_copy(mem);  String j = string::join(mem, parts, ", ");
ZString z = s.zstr_tcopy();                  // NUL-terminated copy for C
String c = s.copy(mem);  c.free(mem);        // or free(c) when allocator is mem
bool same = (a == b);                        // content comparison

DString b = dstring::new(mem);  defer b.free();      // or: DString b; b.init(mem);
b.append("x"); b.append_char('y'); b.appendf("%d", 3);
String view = b.str_view();                 // invalid after next append
String owned = b.copy_str(mem);
```

- Case functions are ASCII-only; `compare_to` returns -1/0/1.
- UTF conversions: `s.to_utf16(mem)`, `s.to_utf32(mem)`, `string::from_utf16(mem, w)`,
  `std::core::string::conv` buffer-based helpers.

## Collections (`std::collections::*`) — generics use `{}` at use sites

```c3
List{int} xs; xs.init(mem); defer xs.free();
xs.push(1); xs.push_all({ 2, 3 }); int? last = xs.pop(); xs[0] = 9;
foreach (x : xs) { }   foreach (&x : xs) *x += 1;
int[] view = xs.array_view();

HashMap{String, int} m; m.init(mem); defer m.free();
m.set("a", 1);                 // copies String keys with the map allocator
int? a = m.get("a");  if (m.has_key("b")) { }  (void)m.remove("a");
m.@each(; String k, int v) { io::printfn("%s=%d", k, v); };
foreach (entry : m.iter()) { }          // HashMap itself is not foreach-able (no @operator(len))
```

| Type | Notes |
|---|---|
| `List{T}` | dynamic array; `init(mem)`/`tinit()`; `ONHEAP` for globals; `remove_at`, `insert_at`, `index_of`, `contains`, `remove_if` |
| `HashMap{K,V}` / `OrderedMap{K,V}` | `K` needs `.hash()`; insertion-ordered variant; old `LinkedHashMap` names deprecated |
| `HashSet{T}` / `OrderedSet{T}` / `TreeSet{T}` | set algebra `set_union` etc.; TreeSet is ordered (red-black) |
| `SortedMap{K,V}` | skip list; `floor_key`/`ceiling_key`; foreach via `iter()` |
| `Deque{T}` | **must** `init(mem)` (no temp fallback) |
| `LinkedList{T}` | iterate with `array_view()` |
| `PriorityQueue{T}` / `PriorityQueueMax{T}` | `push`, `pop` → `T?` |
| `RingBuffer{T, N}` | inline storage, holds N-1, overwrites oldest |
| `FixedList{T, N}` | list without allocation; `push_try` |
| `LinkedBlockingQueue{T}` | thread-safe blocking queue |
| `BitSet{N}`, `GrowableBitSet{T}`, `EnumSet{E}`, `EnumMap{E,V}` | bits/enum-keyed |
| `Maybe{T}`, `Result{Ok,Err}`, `Pair`, `Triple`, `Range` | storable optionals/tuples |
| `AnyList` / `InterfaceList{I}` | heterogeneous, clones elements |

Alias instantiations you reuse: `alias IntList = List{int};`.

## Files, streams, paths

```c3
char[]? data = file::load(mem, "in.bin");          // whole file; caller frees
if (catch err = data) { if (err == io::FILE_NOT_FOUND) { ... } }
file::save("out.bin", bytes)!;                     // not atomic
File f = file::open("log.txt", "a")!;  defer (void)f.close();
io::fprintfn(&f, "%s", line)!;
File in = file::open("in.txt", "rb")!;  defer (void)in.close();
while (!in.eof()) { @pool() { String line = io::treadline(&in)!; ... }; }
sz n = in.read(buf[..])!;                          // 0 at EOF (0.8.4+); read_byte() raises io::EOF
```

- Streams: `InStream`/`OutStream` interfaces (`File`, `Socket`, `ByteBuffer`, `ByteWriter`,
  `ByteReader`, `ReadBuffer`/`WriteBuffer` (buffered wrappers), `Scanner`, `LimitReader`,
  `DString` as OutStream). Helpers: `io::read_all`, `io::write_all`, `io::read_fully(mem, s)`,
  `io::copy_to(in, out)`, `io::read_be_uint`/`write_le_*`, `io::read_varint`.
- Paths (`std::io::path`): `Path p = path::new(mem, "a/b")!;` `path::tnew`, `p.append(mem, "c")`,
  `p.basename()`, `p.dirname()`, `p.extension()`, `path::cwd(mem)`, `path::ls(mem, dir, mask: "*.c3")`,
  `path::mkdir(p, recursive: true)` (returns `false` if it exists), `path::rmtree`,
  `path::temp_directory(mem)`. `Path` converts to `String` implicitly.
- `file::exists/is_dir/is_file/get_size/last_modified/delete`; `file::mmap_open` for mmap.

## Processes, environment, exit (`std::os::*`)

```c3
import std::os::process;
Process p = process::spawn({ "git", "rev-parse", "HEAD" }, INHERIT_ENV)!;
defer p.destroy();
CInt code = p.join()!;
int? rc = process::run({ "make" }, INHERIT_ENV | INHERIT_STDIO);
String? out = process::run_capture_stdout(buf[..], { "uname", "-r" });
String? home = env::get_var(mem, "HOME");   String? tv = env::tget_var("TERM");
os::exit(1);   int cpus = os::num_cpu();
```

- **`spawn`/`run` start the child with an EMPTY environment unless `INHERIT_ENV`**, and pipe all
  stdio by default (chatty children can block) — use `INHERIT_STDIO` or read the pipes.
- Signals: `libc::signal(libc::SIGINT, &handler)`; POSIX helpers in `std::os::posix`.
- `main(String[] args)`: `args[0]` is the program; the slice is freed after `main` returns.

## Time and sleep

- `Time`/`Duration` are **microseconds** (`time::SEC == 1_000_000`); `Clock`/`NanoDuration` are
  nanoseconds. `time::now()`, `t + 5 * time::SEC`, `t2 - t1` (Duration), `time::ms(250)`.
- Monotonic timing: `Clock c = clock::now(); ... NanoDuration el = c.mark();` (`%s` prints `"12ms"`).
- `datetime::now()`, `datetime::at(2026, NOVEMBER, 1)` (`Month` is 0-based), formatting via
  `dt.format(mem, RFC3339)`.
- Sleep lives in `std::thread`: `thread::sleep_ms(10);`, `thread::sleep(2 * time::SEC);`.

## JSON, Object, other encodings

```c3
Object* o = json::parse(mem, text)!;   defer o.free();       // default flavor JSONC; pass JSON for strict
int port = o.get_int("port")!;   String host = o.get_string("host")!;
Object* t = json::tparse(text)!;                              // temp
Config c = json::unmarshal(mem, text, Config)!;               // struct from JSON (String or InStream)
String out = json::marshal(mem, cfg, SPACE_2);                // aborts on NaN/inf; marshal_try is Optional
json::marshal_to(&file, cfg)!;
```

- `json::load(mem, stream)` / `tload` for streams (`parse` = string since 0.8.0).
- Others: `base64::encode(mem, bytes)` / `decode`, `hex::encode`, `base32`, `csv` (`CsvReader`,
  `@each_row`), `ini`, `xml` (`XmlDocument`), `pem`, `codepage`, experimental `regex`.

## Sorting, hashing, random

- `quicksort(&arr)`, `quicksort(list[..], fn int(Foo a, Foo b) => a.k - b.k)`, `mergesort`,
  `insertionsort`, `countingsort`, `binarysearch`, `is_sorted` — pass a slice or a pointer to
  an array/container; comparator returns a signed int.
- Hashes: `fnv64a::hash(data)`, `crc32::hash`, `wyhash2::hash(data, seed)`, `sha256::hash(data)`
  (→ `char[32]`), streaming `Sha256 h; h.init(); h.update(d); h.final();`, `sha256::hmac(key, msg)`,
  `sha256::pbkdf2`, `siphash24`. Crypto: `std::crypto` (AES, ChaCha20, Ed25519, Argon2, BLAKE3…).
- Random: `DefaultRandom r; random::seed_entropy(&r); random::next(&r, 100);` builtins `rand(n)`,
  `rnd()`; CSPRNG bytes via `std::crypto::entropy`. UUID: `uuid::generate()`.
