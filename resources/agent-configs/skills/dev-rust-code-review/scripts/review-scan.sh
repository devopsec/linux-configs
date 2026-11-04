#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only heuristic scan of Rust sources for patterns that often hide
    bugs or unsoundness: unsafe without a SAFETY comment, unsafe Send/Sync
    impls, transmute/uninit memory, static mut, panicking unwrap/expect/
    indexing helpers, blocking calls and std lock guards held across .await
    in async fns, SQL built with format!, disabled TLS verification,
    shell-invoked commands, unbounded channels, lint suppressions without a
    reason. Every hit is a lead for human review, not a verdict.

Usage:
    ${0##*/} [-h] [-l <level>] [-T] [-q] [-C] <path>...

Arguments:
    -h            Show this usage documentation.
    -l <level>    Minimum severity to report: high, medium (default), low.
    -T            Also apply panic/style rules inside #[cfg(test)] modules and
                  tests/, benches/, examples/ dirs (default: only unsafe and
                  security rules apply there).
    -q            Summary only (counts per rule).
    -C            Do not print the offending source line.
    <path>        Files or directories. target/, .git/, vendor/ are skipped.

Environment:
    DEBUG=1       Trace execution.

Exit Codes:
    0   no high-severity findings
    1   at least one high-severity finding
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

LEVEL='medium'
WITH_TESTS=0
QUIET=0
SHOW_CODE=1

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Rule table, fields separated by ' %% ': severity, id, scope (all|src), ERE, advice.
# scope=src rules are skipped in test code unless -T.
rules() {
    cat <<'RULES'
high %% unsafe-send-sync %% all %% unsafe[[:space:]]+impl[^{]*[[:space:]](Send|Sync)([[:space:]]|$|\{) %% asserting thread-safety the compiler could not prove: needs a SAFETY argument covering every field and method
high %% static-mut %% all %% static[[:space:]]+mut[[:space:]] %% data-race prone; references to static mut are denied in edition 2024: use atomics, Mutex, OnceLock
high %% transmute %% all %% (mem::)?transmute(_copy)?(::<[^>]*>)?\( %% layout reinterpretation: prefer from_*_bytes/to_bits/bytemuck/zerocopy; repr(Rust) layouts are unspecified
high %% mem-uninitialized %% all %% mem::uninitialized %% always UB for most types; use MaybeUninit
high %% tls-verify-off %% all %% danger_accept_invalid_(certs|hostnames)\(true\)|dangerous\(\)\.set_certificate_verifier|NoCertificateVerification %% TLS verification disabled: MITM; gate behind an explicit test-only flag or remove
high %% sql-format %% all %% format!\([[:space:]]*"[^"]*\b(SELECT|INSERT|UPDATE|DELETE|select|insert|update|delete)[[:space:]] %% SQL built with format!: injection risk; use bind parameters
medium %% mem-zeroed %% all %% mem::zeroed %% all-zero must be a valid value of the type (not references, NonZero, many enums); prefer MaybeUninit or Default
medium %% raw-parts %% all %% from_raw_parts(_mut)?\(|\.set_len\(|from_raw\( %% raw reconstruction: verify length, capacity, allocator, alignment, initialization, and single ownership
medium %% unchecked %% all %% (get_unchecked(_mut)?|from_utf8_unchecked|unwrap_unchecked|new_unchecked|assume_init(_ref|_mut|_read)?)\( %% UB if the precondition fails: needs a SAFETY proof (or the checked version)
medium %% ptr-read-write %% all %% ptr::(read|write)(_unaligned|_volatile|_bytes)?\(|\.(read|write)_unaligned\( %% raw pointer access: validity, alignment, aliasing, initialization
medium %% env-set-var %% all %% env::(set_var|remove_var)\( %% unsafe in edition 2024 and racy with any thread or C code reading env; pass env to Command instead
medium %% shell-exec %% all %% Command::new\("(/bin/|/usr/bin/)?(sh|bash|zsh)"\) %% shell invocation: injection risk if any argument is derived from input; call the program directly with args
medium %% secret-literal %% all %% (password|passwd|secret|token|api_?key)[[:space:]]*(:[^=]*)?=[[:space:]]*"[^"]{6,}" %% possible hardcoded secret; load from env/file/secret store
medium %% unwrap %% src %% \.unwrap\(\) %% panics on None/Err: propagate with ?, handle, or expect("invariant") when impossible
medium %% panic-macro %% src %% (^|[^[:alnum:]_])(panic|todo|unimplemented)!\( %% panic in non-test code: return an error, or document under # Panics
medium %% len-minus %% src %% \.len\(\)[[:space:]]*-[[:space:]]*[0-9] %% usize underflow (panic in debug, wrap in release) on empty input; use checked_sub or guard is_empty
medium %% dbg-macro %% src %% (^|[^[:alnum:]_])dbg!\( %% leftover debug output
medium %% forget-leak %% all %% mem::forget\(|Box::leak\( %% intentional leak? destructors skipped; check it's bounded (not per request)
low %% expect %% src %% \.expect\( %% fine for proven invariants; not for input/I/O/env/parse errors
low %% unreachable %% src %% (^|[^[:alnum:]_])unreachable!\( %% verify it is truly unreachable for every input
low %% as-narrowing %% src %% [^[:alnum:]_]as[[:space:]]+(u8|u16|u32|i8|i16|i32|f32)([^[:alnum:]_]|$) %% `as` silently truncates/wraps: use TryFrom (or document why it fits)
low %% unbounded-channel %% src %% unbounded_channel\(|mpsc::unbounded|channel::unbounded\( %% no backpressure: memory grows without bound under load; use a bounded channel
low %% detached-spawn %% src %% ^[[:space:]]*(tokio::)?(task::)?spawn(_blocking)?\( %% JoinHandle dropped: task errors and panics are lost and shutdown can't wait for it
low %% allow-no-reason %% all %% #!?\[allow\([^)]*\)\][[:space:]]*$ %% suppression without a reason: use #[expect(lint, reason = "...")]
low %% relaxed-ordering %% all %% Ordering::Relaxed %% fine for counters; a bug if the atomic guards other memory: check Acquire/Release pairing
low %% rc-refcell %% src %% Rc<RefCell< %% shared mutable graph: consider ownership tree, arena + indices, or message passing
low %% process-exit %% src %% process::exit\( %% skips destructors (unflushed BufWriter, temp files); return ExitCode from main
low %% print-in-lib %% src %% (^|[^[:alnum:]_])e?println!\( %% stdout/stderr in library code? use tracing/log (fine in main.rs/bin)
low %% todo %% all %% (TODO|FIXME|XXX|HACK) %% unfinished work marker
RULES
}

level_rank() {
    case "$1" in
        high) printf '3' ;;
        medium) printf '2' ;;
        low) printf '1' ;;
        *) return 1 ;;
    esac
}

collect_files() {
    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
        elif [[ -d "$p" ]]; then
            find "$p" \( -name target -o -name .git -o -name vendor -o -name node_modules \) -prune \
                -o -type f -name '*.rs' -print0
        else
            die "no such file or directory: $p" 2
        fi
    done
}

# Prints "file<TAB>first-test-line" (0 = whole file is test code) for every file.
test_regions() {
    local f
    for f in "$@"; do
        if [[ "$f" =~ (^|/)(tests|benches|examples)/ ]]; then
            printf '%s\t0\n' "$f"
        else
            awk -v f="$f" '/^[[:space:]]*#\[cfg\(test\)\]/ { print f "\t" FNR; found = 1; exit }
                END { if (!found) print f "\t999999999" }' "$f"
        fi
    done
}

# Multi-line heuristics: unsafe without SAFETY, blocking in async fn, std guard across .await.
multiline() {
    awk '
        FNR == 1 {
            if (pend) flush_pending()
            in_async = 0; depth = 0; guard = ""; gdepth = 0; safety = 0; pend = 0
        }
        function flush_pending() {
            printf "%s\t%s\tmedium\tunsafe-no-safety\tunsafe block/impl without a // SAFETY: comment directly above (or first line inside) stating why the preconditions hold\t%s\n", pfile, pend, pcode
            pend = 0
        }
        function emit(sev, id, adv) {
            code = $0; gsub(/\t/, " ", code)
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", FILENAME, FNR, sev, id, adv, code
        }
        {
            line = $0
            if (line ~ /^[[:space:]]*\/\//) {
                if (line ~ /SAFETY|[Ss]afety:/) { safety = 1; pend = 0 }
                next
            }
            if (pend) flush_pending()
            if (line ~ /^[[:space:]]*#\[/) next
            if (line ~ /(^|[^[:alnum:]_])fn[[:space:]]+[[:alnum:]_]+/) {
                in_async = (line ~ /async[[:space:]]+(unsafe[[:space:]]+)?(extern[[:space:]]+"[^"]*"[[:space:]]+)?fn[[:space:]]/)
                guard = ""
            }
            if (line ~ /(^|[^[:alnum:]_])unsafe[[:space:]]*\{|unsafe[[:space:]]+impl[[:space:]<]/ &&
                !safety && line !~ /SAFETY|[Ss]afety:/) {
                pend = FNR; pfile = FILENAME; pcode = $0; gsub(/\t/, " ", pcode)
            }
            safety = 0
            if (in_async && line ~ /std::thread::sleep|thread::sleep\(|std::fs::|reqwest::blocking|\.blocking_(lock|recv|send|read|write)\(|std::net::TcpStream::connect|\.recv\(\)\.unwrap|std::sync::mpsc/) {
                emit("medium", "blocking-in-async", "blocking call inside async fn stalls a runtime worker: use the async equivalent or spawn_blocking")
            }
            opens = gsub(/\{/, "{", line); closes = gsub(/\}/, "}", line)
            if (in_async && guard == "" && $0 ~ /let[[:space:]]+(mut[[:space:]]+)?[[:alnum:]_]+[[:space:]]*(:[^=]*)?=.*\.(lock|read|write)\(\)(\.unwrap\(\)|\.expect\([^)]*\)|\?)?;[[:space:]]*$/) {
                g = $0; sub(/^.*let[[:space:]]+(mut[[:space:]]+)?/, "", g); sub(/[^[:alnum:]_].*$/, "", g)
                guard = g; gdepth = depth + opens - closes; gline = FNR; gcode = $0
            } else if (guard != "") {
                if ($0 ~ ("drop\\(" guard "\\)")) guard = ""
                else if ($0 ~ /\.await/) {
                    code = gcode; gsub(/\t/, " ", code)
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", FILENAME, gline, "medium", "guard-across-await",
                        "std lock guard `" guard "` appears to live across .await (line " FNR "): !Send future / deadlock; drop it before awaiting", code
                    guard = ""
                }
            }
            depth += opens - closes
            if (guard != "" && depth < gdepth) guard = ""
        }
        END { if (pend) flush_pending() }
    ' "$@"
}

main() {
    local opt
    while getopts ':hl:TqC' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            l) level_rank "$OPTARG" >/dev/null || die "-l expects high, medium, or low" 2
               LEVEL="$OPTARG" ;;
            T) WITH_TESTS=1 ;;
            q) QUIET=1 ;;
            C) SHOW_CODE=0 ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# > 0)) || { usage >&2; exit 2; }
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    local -a files=()
    local f
    while IFS= read -r -d '' f; do files+=("$f"); done < <(collect_files "$@")
    ((${#files[@]} > 0)) || { printf 'no Rust files found\n' >&2; exit 0; }

    local tmp regions min
    tmp="$(mktemp)"
    regions="$(mktemp)"
    trap 'rm -f -- "$tmp" "$regions"' EXIT
    min="$(level_rank "$LEVEL")"
    test_regions "${files[@]}" >"$regions"

    local severity id scope regex advice
    while IFS=$'\x1f' read -r severity id scope regex advice; do
        [[ -n "$severity" ]] || continue
        (($(level_rank "$severity") >= min)) || continue
        grep -nHE -- "$regex" "${files[@]}" 2>/dev/null |
            awk -v s="$severity" -v id="$id" -v adv="$advice" -v scope="$scope" \
                -v all="$WITH_TESTS" -v regions="$regions" '
                BEGIN { while ((getline r < regions) > 0) { split(r, a, "\t"); start[a[1]] = a[2] } }
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    if (code ~ /^[[:space:]]*\/\// && id != "todo") next
                    if (scope == "src" && !all && (file in start) && line + 0 >= start[file] + 0) next
                    gsub(/\t/, " ", code)
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, line, s, id, adv, code
                }' >>"$tmp" || true
    done < <(rules | sed 's/ %% /\x1f/g')
    if ((min <= 2)); then
        multiline "${files[@]}" >>"$tmp"
    fi

    if [[ ! -s "$tmp" ]]; then
        printf 'no findings at level >= %s\n' "$LEVEL"
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
    printf '== summary (level >= %s) ==\n' "$LEVEL"
    awk -F'\t' '{ n[$3 " " $4]++ } END { for (k in n) printf "%-30s %d\n", k, n[k] }' "$tmp" | sort
    printf '%-30s %d\n' 'total' "$(wc -l <"$tmp")"
    if awk -F'\t' '$3 == "high" { found = 1 } END { exit !found }' "$tmp"; then exit 1; fi
    exit 0
}

main "$@"
