#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only scan of Zig sources (*.zig, build.zig, build.zig.zon) for APIs
    and syntax that were removed or deprecated between Zig 0.14 and the
    target version. Prints file:line, the version/kind, the fix, and the
    offending line. Heuristic (grep-based): the compiler is the final judge.

Usage:
    ${0##*/} [-h] [-t <series>] [-f <series>] [-k <kinds>] [-q] [-C] <path>...

Arguments:
    -h            Show this usage documentation.
    -t <series>   Target series to port TO (default: ${DEFAULT_TARGET}). Only rules
                  whose version is <= target are applied.
    -f <series>   Series the code currently targets. Only rules whose version
                  is > this are applied (default: apply all up to target).
    -k <kinds>    Comma list of kinds to report: removed,deprecated,review
                  (default: all).
    -q            Summary only (counts per version and kind).
    -C            Do not print the offending source line.
    <path>        Files or directories to scan. .zig-cache, zig-out, zig-pkg,
                  and .git are skipped.

Environment:
    DEBUG=1       Trace execution.

Exit Codes:
    0   no findings
    1   findings reported
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

DEFAULT_TARGET='0.17'
TARGET="$DEFAULT_TARGET"
FROM=''
KINDS='removed,deprecated,review'
QUIET=0
SHOW_CODE=1

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Rule table, fields separated by ' %% ': version, kind, scope, ERE, fix
#   version: series where the old form stops compiling (removed) or is deprecated
#   scope:   zig (all .zig), build (build.zig only), zon (build.zig.zon only)
rules() {
    cat <<'RULES'
0.14 %% removed %% zig %% @setCold\( %% @branchHint(.cold) as the first statement of the block
0.14 %% removed %% zig %% @fence\( %% use stronger orderings on the atomic operations themselves
0.14 %% removed %% zig %% @setAlignStack\( %% callconv(.withStackAlign(.c, n))
0.14 %% removed %% zig %% @typeInfo\([^)]*\)\.(Struct|Enum|Union|Int|Float|Pointer|Array|Optional|Fn|ErrorSet|ErrorUnion|Opaque|Vector)\b %% lowercase tags: .@"struct", .@"enum", .@"union", .int, .pointer, .@"fn" ...
0.14 %% removed %% zig %% \.size == \.(One|Many|Slice|C)\b %% Pointer.Size tags are lowercase: .one .many .slice .c
0.14 %% removed %% zig %% std\.mem\.page_size\b %% std.heap.page_size_min / std.heap.pageSize()
0.14 %% removed %% zon %% ^[[:space:]]*\.name[[:space:]]*=[[:space:]]*" %% .name = .enum_literal and add a zig-generated .fingerprint
0.15 %% removed %% zig %% callconv\(\.C\) %% callconv(.c)
0.15 %% removed %% zig %% (^|[^.[:alnum:]_])usingnamespace[[:space:]] %% explicit re-exports: pub const x = other.x;
0.15 %% removed %% zig %% (^|[^.[:alnum:]_])(async[[:space:]]+[@[:alpha:]_][[:alnum:]_.]*\(|await[[:space:]]+[[:alpha:]_][[:alnum:]_.]*[[:space:]]*[;)]) %% async/await keywords removed; 0.16+: io.async(f, .{...}) and future.await(io)
0.15 %% removed %% zig %% getStd(Out|Err|In)\( %% 0.15: std.fs.File.stdout().writer(&buf); 0.16+: std.Io.File.stdout().writer(io, &buf) -> .interface, flush()
0.15 %% deprecated %% zig %% std\.io\. %% std.Io (the lowercase std.io alias is removed in 0.16)
0.15 %% deprecated %% zig %% fixedBufferStream %% std.Io.Writer.fixed(&buf) / std.Io.Reader.fixed(bytes) (removed in 0.16)
0.15 %% deprecated %% zig %% \b(AnyWriter|GenericWriter|AnyReader|GenericReader)\b %% *std.Io.Writer / *std.Io.Reader (concrete) (removed in 0.16)
0.15 %% removed %% zig %% \b(bufferedWriter|bufferedReader|countingWriter)\( %% buffers are built into std.Io.Writer/Reader; Writer.Discarding counts
0.15 %% deprecated %% zig %% \bcountingReader\( %% track bytes consumed manually or wrap a std.Io.Reader (removed in 0.16)
0.15 %% deprecated %% zig %% readUntilDelimiter %% reader.takeDelimiterExclusive(d) / takeDelimiter(d) (0.16+: ?[]u8 at EOF) (removed in 0.16)
0.15 %% removed %% zig %% \bBoundedArray\b %% std.ArrayList(T).initBuffer(&buf) + appendBounded
0.15 %% removed %% zig %% LinearFifo|std\.fifo|\bRingBuffer\b %% std.Io.Reader/Writer buffers or std.Deque (0.16+)
0.15 %% removed %% zig %% ArrayList\([^)]*\)\.init\( %% unmanaged default: var l: std.ArrayList(T) = .empty; l.append(gpa, x); l.deinit(gpa)
0.15 %% removed %% zig %% fn format\([^)]*comptime[^)]*\[\]const u8 %% pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void, print with {f}
0.15 %% deprecated %% zig %% std\.fmt\.format\( %% writer.print(fmt, args) (removed in 0.16)
0.15 %% removed %% zig %% fmtSliceHex(Lower|Upper)|fmtIntSize(Dec|Bin)|fmtDuration|fmtSliceEscape %% {x} {X} {B} {Bi} {D}(0.15 only) {q}
0.15 %% removed %% zig %% std\.json\.stringify(Alloc)?\( %% std.json.Stringify.value(v, .{}, w) / std.json.Stringify.valueAlloc
0.15 %% deprecated %% zig %% \.(writer|reader)\(\) %% File.writer(&buf)/reader(&buf) (0.16+: (io, &buf)) and use .interface (removed in 0.16)
0.15 %% removed %% build %% add(StaticLibrary|SharedLibrary)\( %% b.addLibrary(.{ .linkage = .static/.dynamic, .root_module = ... })
0.15 %% removed %% build %% add(Executable|Test|Object|Library)\(\.\{[^}]*root_source_file %% move root_source_file/target/optimize into .root_module = b.createModule(.{ ... })
0.16 %% removed %% zig %% std\.fs\.(cwd|File|Dir|openFileAbsolute|openDirAbsolute|createFileAbsolute|deleteFileAbsolute|makeDirAbsolute|realpath|selfExePath|getAppDataDir)\b %% std.Io.Dir.cwd() / std.Io.File / std.Io.Dir; methods take io
0.16 %% removed %% zig %% std\.net\. %% std.Io.net (IpAddress.parse/connect/listen, HostName.connect) with io
0.16 %% removed %% zig %% std\.time\.(sleep|timestamp|milliTimestamp|microTimestamp|nanoTimestamp|Timer|Instant)\b %% io.sleep(.fromMilliseconds(n), .awake); std.Io.Clock.real/awake.now(io); Timestamp.untilNow
0.16 %% removed %% zig %% std\.Thread\.(Mutex|Condition|RwLock|Semaphore|ResetEvent|Futex|Pool|WaitGroup|sleep)\b %% std.Io.Mutex/Condition/RwLock/Semaphore/Event, io.futexWait, std.Io.Group, io.sleep
0.16 %% removed %% zig %% std\.once\( %% removed: avoid the global or hand-roll with std.atomic
0.16 %% removed %% zig %% std\.crypto\.random %% io.random(&buf) / io.randomSecure(&buf) / std.Random.IoSource{ .io = io }
0.16 %% removed %% zig %% posix\.(getrandom|socket|bind|listen|accept|connect|exit|getcwd|mlock[a-z0-9]*)\( %% go up to std.Io / std.process, or down to std.posix.system
0.16 %% removed %% zig %% std\.process\.(argsAlloc|argsFree|args|argsWithAllocator|getEnvVarOwned|getEnvMap|hasEnvVar|getCwd|getCwdAlloc|execv)\b %% main(init: std.process.Init): init.minimal.args, init.environ_map, process.currentPathAlloc(io, gpa), process.replace
0.16 %% removed %% zig %% Child\.(init|run)\( %% std.process.spawn(io, .{ .argv = ... }) / std.process.run(gpa, io, .{ .argv = ... })
0.16 %% removed %% zig %% @Type\( %% @Int / @Struct / @Union / @Enum / @Pointer / @Fn / @Tuple / @EnumLiteral or plain type syntax
0.16 %% removed %% zig %% std\.(Auto|String)?ArrayHashMap\( %% std.array_hash_map.Auto/String/Custom (unmanaged, .empty)
0.16 %% deprecated %% zig %% (Auto|String)?ArrayHashMapUnmanaged\( %% std.array_hash_map.Auto / String / Custom
0.16 %% removed %% zig %% ThreadSafeAllocator %% ArenaAllocator is thread-safe since 0.16; otherwise lock explicitly
0.16 %% removed %% zig %% SegmentedList %% removed; ArrayList of chunks or MultiArrayList
0.16 %% removed %% zig %% std\.meta\.intToEnum %% std.enums.fromInt(E, i) -> ?E
0.16 %% removed %% zig %% \bFormatOptions\b %% std.fmt.Options
0.16 %% removed %% zig %% lockStderrWriter %% std.debug.lockStderr(&buf) / io.lockStderr(&buf, null)
0.16 %% deprecated %% zig %% std\.mem\.(indexOf|lastIndexOf)[[:alnum:]]*\( %% std.mem.find / findLast / findScalar / findAny ...
0.16 %% review %% zig %% \.close\(\) %% std.Io File/Dir/Stream close now take io: x.close(io)
0.16 %% review %% zig %% \.(readFileAlloc|readToEndAlloc)\( %% 0.16: dir.readFileAlloc(io, path, gpa, .limited(n)); readToEndAlloc -> reader.interface.allocRemaining
0.16 %% removed %% build %% \b(exe|lib|tests?|unit_tests|exe_tests|lib_tests)\.(linkSystemLibrary|addIncludePath|addCSourceFiles?|linkLibC|linkLibCpp|addLibraryPath|addObjectFile)\( %% moved to Module: exe.root_module.<method>(...) / .link_libc = true
0.17 %% deprecated %% zig %% @(intFromEnum|enumFromInt)\( %% @backingInt / @fromBackingInt(@intCast(n)); run zig fmt to auto-upgrade
0.17 %% removed %% zig %% \}[[:space:]]*\*\*[[:space:]]*[[:alnum:]_(] %% array multiplication removed: const a: [N]T = @splat(x);
0.17 %% removed %% zig %% errdefer[[:space:]]*\| %% errdefer capture removed: split into inner fn and handle with catch |err|
0.17 %% removed %% zig %% void\{\} %% use {}
0.17 %% removed %% zig %% (:|\(|\[|\?|\*|,|=)[[:space:]]*i0\b %% use u0
0.17 %% removed %% zig %% enum\((u|i|c_)[[:alnum:]_]*\)[[:space:]]*\{[[:space:]]*\} %% empty enums with an explicit tag type need enum(noreturn) {}
0.17 %% removed %% zig %% \.@"(struct|union|enum)"\.(fields|decls)\b %% struct-of-arrays reflection: .field_names / .field_types / .field_attrs / .field_values / .decl_names
0.17 %% removed %% zig %% std\.meta\.(fields|fieldInfo|fieldNames|fieldTypes)\( %% use @typeInfo(T).@"struct".field_names etc.
0.17 %% removed %% zig %% @cImport\( %% translate_c package: Translator.init(b.dependency("translate_c", .{}), ...) -> .mod
0.16 %% removed %% zig %% \bGeneralPurposeAllocator\b %% 0.16: std.heap.DebugAllocator(.{}) = .init; 0.17+: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{}); or init.gpa from juicy main
0.17 %% deprecated %% zig %% \bDebugAllocator\b %% std.heap.SafeAllocator = .init(std.heap.page_allocator, .{}); deinit() returns leak count
0.17 %% removed %% zig %% StackFallbackAllocator|stackFallback\( %% std.heap.BufferFirstAllocator.init(&buf, fallback)
0.17 %% deprecated %% zig %% std\.fmt\.allocPrint(Sentinel)?\( %% allocator.print(fmt, args) / allocator.printSentinel(fmt, args, 0)
0.17 %% removed %% zig %% std\.fmt\.bufPrintZ\( %% std.fmt.bufPrintSentinel(buf, fmt, args, 0)
0.17 %% deprecated %% zig %% \.getLast(OrNull)?\(\) %% list.last() (?T) / list.last().?
0.17 %% removed %% zig %% fromSliceAlloc\( %% std.zon.parse.fromSlice(T, .{ .gpa, .arena, .source, .diagnostics })
0.17 %% deprecated %% zig %% \b(IntegerBitSet|ArrayBitSet|StaticBitSet|DynamicBitSetUnmanaged|DynamicBitSet)\b %% std.bit_set.Integer / Array / Static / Dynamic / DynamicManaged
0.17 %% removed %% zig %% \.init(Empty|Full)\(\) %% .empty / .full decl literals
0.17 %% review %% zig %% containsAtLeastScalar\( %% ARGUMENTS SWAPPED in 0.17: (T, haystack, element, minimum) - may still compile
0.17 %% removed %% zig %% (read|write)PackedInt(Native|Foreign) %% std.mem.readPackedInt / writePackedInt
0.17 %% removed %% zig %% indexOfIgnoreCase %% std.ascii.findIgnoreCase*
0.17 %% removed %% zig %% std\.gpu\b %% std.spirv
0.17 %% deprecated %% zig %% std\.builtin\. %% std.lang.* (std.builtin is a deprecated alias)
0.17 %% deprecated %% zig %% \bOptimizeMode\b %% std.lang.Optimize with .debug/.safe/.fast/.small
0.17 %% deprecated %% zig %% builtin\.(cpu|os|abi|object_format)\b %% @import("builtin").target.cpu/os/abi/ofmt (old names removed in 0.18)
0.17 %% review %% zig %% @bitCast\( %% 0.17 logical-bit semantics: extern struct/union is an error; arrays/vectors may change on big-endian
0.17 %% removed %% build %% \bb\.args\b %% run_cmd.addPassthruArgs()
0.17 %% review %% build %% \.findProgram\( %% b.findProgramLazy(...) keeps the configure cache pure
0.17 %% deprecated %% build %% lazyDependency\( %% try b.dependencyLazy(name, args) with build() !void
0.17 %% removed %% build %% \bbuild_root\b %% b.root (Cache.Path)
0.17 %% deprecated %% build %% addTranslateC\( %% translate_c package (Translator) from codeberg.org/ziglang/translate-c
RULES
}

# Prints 0 if dotted series $1 <= $2.
series_le() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]
}

collect_files() {
    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
        elif [[ -d "$p" ]]; then
            find "$p" \( -name .zig-cache -o -name zig-cache -o -name zig-out -o -name zig-pkg -o -name .git \) \
                -prune -o -type f \( -name '*.zig' -o -name 'build.zig.zon' \) -print0
        else
            die "no such file or directory: $p" 2
        fi
    done
}

main() {
    local opt
    while getopts ':ht:f:k:qC' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            t) TARGET="$OPTARG" ;;
            f) FROM="$OPTARG" ;;
            k) KINDS="$OPTARG" ;;
            q) QUIET=1 ;;
            C) SHOW_CODE=0 ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# > 0)) || { usage >&2; exit 2; }
    [[ "$TARGET" =~ ^[0-9]+\.[0-9]+$ ]] || die "-t expects a series like 0.17" 2
    [[ -z "$FROM" || "$FROM" =~ ^[0-9]+\.[0-9]+$ ]] || die "-f expects a series like 0.15" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    local -a zig_files=() build_files=() zon_files=()
    local f
    while IFS= read -r -d '' f; do
        case "${f##*/}" in
            build.zig.zon) zon_files+=("$f") ;;
            build.zig) build_files+=("$f"); zig_files+=("$f") ;;
            *.zig) zig_files+=("$f") ;;
        esac
    done < <(collect_files "$@")
    ((${#zig_files[@]} + ${#zon_files[@]} > 0)) || { printf 'no Zig files found\n' >&2; exit 0; }

    local tmp
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' EXIT

    local version kind scope regex fix
    local -a targets
    while IFS=$'\x1f' read -r version kind scope regex fix; do
        [[ -n "$version" ]] || continue
        series_le "$version" "$TARGET" || continue
        if [[ -n "$FROM" ]] && series_le "$version" "$FROM"; then continue; fi
        [[ ",$KINDS," == *",$kind,"* ]] || continue
        case "$scope" in
            zig) targets=("${zig_files[@]}") ;;
            build) targets=("${build_files[@]}") ;;
            zon) targets=("${zon_files[@]}") ;;
            *) die "bad rule scope: $scope" ;;
        esac
        ((${#targets[@]} > 0)) || continue
        # Skip comment-only lines; emit "file<TAB>line<TAB>version<TAB>kind<TAB>fix<TAB>code".
        grep -nHE -- "$regex" "${targets[@]}" 2>/dev/null |
            awk -v v="$version" -v k="$kind" -v fx="$fix" '
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    if (code ~ /^[[:space:]]*\/\//) next
                    gsub(/\t/, " ", code)
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, line, v, k, fx, code
                }' >>"$tmp" || true
    done < <(rules | sed 's/ %% /\x1f/g')

    if [[ ! -s "$tmp" ]]; then
        printf 'no legacy patterns found (target %s%s)\n' "$TARGET" "${FROM:+, from $FROM}"
        exit 0
    fi

    if ((!QUIET)); then
        sort -t $'\t' -k1,1 -k2,2n "$tmp" |
            awk -F'\t' -v show="$SHOW_CODE" '{
                printf "%s:%s: [%s %s] %s\n", $1, $2, $3, $4, $5
                if (show) { c = $6; sub(/^[[:space:]]+/, "", c); printf "    > %s\n", substr(c, 1, 160) }
            }'
        printf '\n'
    fi
    printf '== summary (target %s%s) ==\n' "$TARGET" "${FROM:+, from $FROM}"
    awk -F'\t' '{ n[$3 " " $4]++ } END { for (k in n) printf "%-22s %d\n", k, n[k] }' "$tmp" | sort -V
    printf '%-22s %d\n' 'total' "$(wc -l <"$tmp")"
    exit 1
}

main "$@"
