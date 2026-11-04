#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only heuristic scan of Zig sources for patterns that often hide bugs:
    swallowed errors, catch unreachable, disabled safety, unchecked casts,
    allocations without a nearby defer/errdefer, possible usize underflow,
    stray debug output. Every hit is a lead for human review, not a verdict.

Usage:
    ${0##*/} [-h] [-l <level>] [-T] [-q] [-C] <path>...

Arguments:
    -h            Show this usage documentation.
    -l <level>    Minimum severity to report: high, medium (default), low.
    -T            Also scan test blocks' files under test/ and tests/ dirs
                  (default: skipped; inline test blocks are always scanned).
    -q            Summary only (counts per rule).
    -C            Do not print the offending source line.
    <path>        Files or directories. .zig-cache, zig-out, zig-pkg, .git skipped.

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
WITH_TEST_DIRS=0
QUIET=0
SHOW_CODE=1

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Rule table, fields separated by ' %% ': severity, id, ERE, advice
rules() {
    cat <<'RULES'
high %% catch-unreachable %% catch[[:space:]]+unreachable %% asserts the error is impossible; propagate with try or handle it (never on alloc, I/O, parsing)
high %% swallowed-error %% catch[[:space:]]*(\|[[:alnum:]_]+\|[[:space:]]*)?\{[[:space:]]*\} %% error silently ignored; handle, log, or propagate (TigerStyle: all errors must be handled)
high %% safety-off %% @setRuntimeSafety\(false\) %% disables bounds/overflow checks for the scope; needs a measured justification and a test
high %% ptr-cast-int %% @ptrFromInt\( %% integer to pointer: check alignment, provenance, and lifetime
medium %% ptr-cast %% @(ptrCast|alignCast)\( %% reinterpreting memory: verify size, alignment, and that the pointee outlives the result
medium %% const-cast %% @(constCast|volatileCast)\( %% casting away qualifiers: writing through it is illegal if the memory is really const
medium %% int-cast %% @(intCast|truncate|intFromFloat)\( %% narrowing: panics (or wraps for @truncate) on out-of-range input; use std.math.cast for untrusted values
medium %% len-minus %% \.len[[:space:]]*-[[:space:]]*[0-9] %% usize underflow when the slice is empty; guard len > 0 first
medium %% panic %% @panic\( %% libraries should return errors; reserve panics for programmer errors
medium %% unwrap %% [][:alnum:]_)]\.\?([^[:alnum:]_]|$) %% .? panics on null; prove non-null or use orelse / if (x) |v|
medium %% global-mutable %% ^(pub[[:space:]]+)?(threadlocal[[:space:]]+)?var[[:space:]] %% module-level mutable state: thread-safety, testability, init order
medium %% raw-thread %% std\.Thread\.spawn\( %% raw threads bypass std.Io cancelation; prefer io.async / std.Io.Group (0.16+)
low %% anyerror %% \banyerror\b %% prefer explicit or inferred error sets on public APIs
low %% debug-print %% std\.debug\.print\( %% stray debug output? use std.log or a writer in production code
low %% unbounded-loop %% while[[:space:]]*\(true\) %% unbounded loop: assert why it terminates or give it an upper bound (TigerStyle)
low %% page-allocator %% std\.heap\.page_allocator %% page_allocator maps whole pages per call; back an arena/pool with it instead
low %% todo %% (TODO|FIXME|XXX) %% unfinished work marker
low %% bitcast %% @bitCast\( %% 0.17 logical-bit semantics; check extern types and array/vector endianness
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
            if ((WITH_TEST_DIRS)); then
                find "$p" \( -name .zig-cache -o -name zig-cache -o -name zig-out -o -name zig-pkg -o -name .git \) \
                    -prune -o -type f -name '*.zig' -print0
            else
                find "$p" \( -name .zig-cache -o -name zig-cache -o -name zig-out -o -name zig-pkg -o -name .git \
                    -o -name test -o -name tests \) -prune -o -type f -name '*.zig' -print0
            fi
        else
            die "no such file or directory: $p" 2
        fi
    done
}

# Flags allocations whose next 3 lines contain no defer/errdefer/return/ownership hand-off.
missing_defer() {
    awk '
        FNR == 1 { pending = 0 }
        /^[[:space:]]*\/\// { next }
        pending > 0 {
            if ($0 ~ /(errdefer|defer)/) { pending = 0 }
            else if ($0 ~ /(^|[^[:alnum:]_])try[[:space:]]/) {
                printf "%s\t%s\tmedium\talloc-no-defer\tallocation followed by try before any defer/errdefer: leaks on that error path (fine if the allocator is an arena)\t%s\n", FILENAME, aline, acode
                pending = 0
            }
            else if ($0 ~ /(return|toOwnedSlice|\.append|\.put|= .*\.\*|\.items)/) { pending = 0 }
            else if (--pending == 0) { printf "%s\t%s\tlow\talloc-no-defer\tno defer/errdefer within 3 lines of this allocation: who frees it?\t%s\n", FILENAME, aline, acode }
        }
        /(const|var)[[:space:]]+[[:alnum:]_]+[[:space:]]*(:[^=]*)?=[[:space:]]*try[[:space:]]+[[:alnum:]_.]+\.(alloc|create|dupe|dupeSentinel|alignedAlloc|print|printSentinel|allocPrint|readFileAlloc|allocRemaining|toOwnedSlice)\(/ {
            pending = 3; aline = FNR; acode = $0; gsub(/\t/, " ", acode)
        }
    ' "$@"
}

main() {
    local opt
    while getopts ':hl:TqC' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            l) level_rank "$OPTARG" >/dev/null || die "-l expects high, medium, or low" 2
               LEVEL="$OPTARG" ;;
            T) WITH_TEST_DIRS=1 ;;
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
    ((${#files[@]} > 0)) || { printf 'no Zig files found\n' >&2; exit 0; }

    local tmp min
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' EXIT
    min="$(level_rank "$LEVEL")"

    local severity id regex advice
    while IFS=$'\x1f' read -r severity id regex advice; do
        [[ -n "$severity" ]] || continue
        (($(level_rank "$severity") >= min)) || continue
        grep -nHE -- "$regex" "${files[@]}" 2>/dev/null |
            awk -v s="$severity" -v id="$id" -v adv="$advice" '
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    if (code ~ /^[[:space:]]*\/\// && id != "todo") next
                    gsub(/\t/, " ", code)
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, line, s, id, adv, code
                }' >>"$tmp" || true
    done < <(rules | sed 's/ %% /\x1f/g')
    if ((min <= 2)); then
        missing_defer "${files[@]}" | awk -F'\t' -v min="$min" '($3 == "medium") || min <= 1' >>"$tmp"
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
