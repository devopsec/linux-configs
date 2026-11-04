#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only heuristic scan of C3 sources for patterns that often hide bugs:
    ignored excuses, force-unwraps, temp memory escaping its @pool, String to
    ZString casts, compile-time code execution, C ABI mismatches, allocations
    followed by a rethrow before any defer. Comments and <* *> blocks are
    ignored. Every hit is a lead for human review, not a verdict.

Usage:
    ${0##*/} [-h] [-l <level>] [-T] [-q] [-C] <path>...

Arguments:
    -h            Show this usage documentation.
    -l <level>    Minimum severity: high, medium (default), low.
    -T            Include test/ and tests/ directories (default: skipped).
    -q            Summary only.
    -C            Do not print the offending source line.
    <path>        Files or directories (build/, out/, lib/, .git skipped).

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

# Fields separated by ' %% ': severity, id, ERE, advice.
rules() {
    cat <<'RULES'
high %% catch-ignored %% if[[:space:]]*\([[:space:]]*catch[^{]*\)[[:space:]]*\{[[:space:]]*\} %% excuse caught and ignored: handle, log, or rethrow with `!`
high %% temp-escapes %% (self|[a-z_][A-Za-z0-9_]*)\.[a-z_][A-Za-z0-9_.]*[[:space:]]*=[^=;]*(tmalloc|tcalloc|trealloc|mem::(tnew|talloc|temp_array|talloc_array)|@tclone|tformat|\.tcopy\(|\.tsplit\(|\.tconcat\(|treadline|load_temp|\btmem\b) %% temp memory stored in a field: dangles when the enclosing @pool ends; allocate with the owner's allocator
high %% zstring-cast %% \((ZString|char\*)\)[[:space:]]*[a-z_][A-Za-z0-9_.]*([^A-Za-z0-9_(]|$) %% String slices are not NUL-terminated (only literals/copies are): use s.zstr_tcopy() / s.zstr_copy(alloc) for C
high %% compile-exec %% \$(exec|include)\( %% compile-time code/file inclusion (needs --trust): review what runs at build time
medium %% force-unwrap %% [][A-Za-z0-9_)]!![^=] %% `!!` panics on any excuse: OK in tests/impossible cases, not on I/O, parsing or user input
medium %% discard-optional %% \(void\)[[:space:]]*[@A-Za-z_][A-Za-z0-9_:.@]*\( %% Optional result discarded: is ignoring this excuse (close/flush/write errors) intended?
medium %% noinit %% @noinit %% uninitialized memory: must be fully written before any read
medium %% unreachable %% (^|[^A-Za-z0-9_])unreachable\( %% UB in unsafe builds if reachable: prove it or handle the case
medium %% c-long %% extern[[:space:]]+fn[^;{]*[^A-Za-z_]long[^A-Za-z_] %% C3 long is 64-bit; C long is 32-bit on Windows: use CLong / CInt for C prototypes
medium %% raw-thread %% \.create\([[:space:]]*&?[a-z_][A-Za-z0-9_]*[[:space:]]*, %% raw Thread: body must use @pool_init(...) before any tmem/@pool use, and Thread storage must outlive start
medium %% global-mutable %% ^(tlocal[[:space:]]+)?([A-Z][][A-Za-z0-9_{}*]*|(int|uint|long|ulong|short|ushort|char|ichar|bool|float|double|sz|usz|iptr|uptr)[][*]*)[[:space:]]+[a-z_][A-Za-z0-9_]*[[:space:]]*(=[^=].*)?;[[:space:]]*$ %% module-level mutable state: thread safety, init order, testability
medium %% len-minus %% \.len[[:space:]]*-[[:space:]]*1 %% empty slice ⇒ -1 index (traps in safe builds, UB in -O2+): guard len > 0
low %% usz %% \busz\b %% 0.8 style prefers signed sz for sizes/indices; unsigned only for C ABI/bit patterns
low %% builtin %% \$\$[a-z_]+\( %% compiler builtins outside the stdlib (--warn-builtin): prefer the std wrapper
low %% libc %% \blibc::[a-z_]+\( %% raw libc call: is there a std wrapper with Optionals?
low %% todo %% TODO|FIXME|XXX %% unfinished work marker
RULES
}

level_rank() {
    case "$1" in high) printf 3 ;; medium) printf 2 ;; low) printf 1 ;; *) return 1 ;; esac
}

# Same comment stripping as dev-c3-version-migrate/scripts/scan-legacy.sh (keeps line numbers).
sanitize() {
    awk '
        {
            line = $0; out = ""
            while (length(line) > 0) {
                if (indoc) {
                    p = index(line, "*>"); if (!p) { line = ""; break }
                    line = substr(line, p + 2); indoc = 0; continue
                }
                if (inblock) {
                    p = index(line, "*/"); if (!p) { line = ""; break }
                    line = substr(line, p + 2); inblock = 0; continue
                }
                d = index(line, "<*"); b = index(line, "/*")
                c = match(line, /(^|[[:space:]])\/\//)
                first = 0
                if (d && (!first || d < first)) { first = d; kind = "doc" }
                if (b && (!first || b < first)) { first = b; kind = "block" }
                if (c && (!first || c < first)) { first = c; kind = "line" }
                if (!first) { out = out line; break }
                out = out substr(line, 1, first - 1)
                if (kind == "line") break
                line = substr(line, first + 2)
                if (kind == "doc") indoc = 1; else inblock = 1
            }
            print out
        }' "$1"
}

# Allocation followed (within 4 lines) by a `!` rethrow before any defer/free/return.
alloc_rethrow() {
    awk -v orig="$2" '
        /^[[:space:]]*(|.*[^A-Za-z0-9_])(mem::(new|alloc|new_array|alloc_array|new_aligned)|malloc|calloc|@clone|@clone_slice|alloc::(new|malloc|calloc|new_array|alloc_array|clone)|string::format\([[:space:]]*mem|\.copy\([[:space:]]*mem|\.concat\([[:space:]]*mem|file::load\([[:space:]]*mem|dstring::new\([[:space:]]*mem|path::new\([[:space:]]*mem)/ \
            && !/^[[:space:]]*return/ && !/defer/ {
            pending = 4; aline = FNR; acode = $0; gsub(/\t/, " ", acode); next
        }
        pending > 0 {
            if ($0 ~ /defer|free|\.free\(|return/) { pending = 0; next }
            if ($0 ~ /[]A-Za-z0-9_)]![^!=]/ || $0 ~ /[]A-Za-z0-9_)]!;/) {
                printf "%s\t%s\tmedium\talloc-rethrow\tallocation followed by a `!` rethrow before any defer/free: leaks on that path (use defer (catch) or move the allocation)\t%s\n", orig, aline, acode
                pending = 0; next
            }
            pending--
        }
    ' "$1"
}

collect_files() {
    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
        elif [[ -d "$p" ]]; then
            if ((WITH_TESTS)); then
                find "$p" \( -name build -o -name out -o -name lib -o -name .git \) -prune -o -type f \
                    \( -name '*.c3' -o -name '*.c3i' \) -print0
            else
                find "$p" \( -name build -o -name out -o -name lib -o -name .git -o -name test -o -name tests \) \
                    -prune -o -type f \( -name '*.c3' -o -name '*.c3i' \) -print0
            fi
        else
            die "no such file or directory: $p" 2
        fi
    done
}

main() {
    local opt
    while getopts ':hl:TqC' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            l) level_rank "$OPTARG" >/dev/null || die "-l expects high, medium or low" 2; LEVEL="$OPTARG" ;;
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

    local -a files=() clean=()
    local f i
    while IFS= read -r -d '' f; do files+=("$f"); done < <(collect_files "$@")
    ((${#files[@]} > 0)) || { printf 'no C3 files found\n' >&2; exit 0; }

    local tmp work min
    tmp="$(mktemp)"
    work="$(mktemp -d)"
    trap 'rm -rf -- "$tmp" "$work"' EXIT
    min="$(level_rank "$LEVEL")"
    for i in "${!files[@]}"; do
        sanitize "${files[$i]}" >"$work/$i.c3"
        clean+=("$work/$i.c3")
    done

    local severity id regex advice
    while IFS=$'\x1f' read -r severity id regex advice; do
        [[ -n "$severity" ]] || continue
        (($(level_rank "$severity") >= min)) || continue
        grep -nHE -- "$regex" "${clean[@]}" 2>/dev/null |
            awk -v s="$severity" -v id="$id" -v adv="$advice" -v work="$work/" \
                -v names="$(printf '%s\n' "${files[@]}")" '
                BEGIN { split(names, orig, "\n") }
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    idx = substr(file, length(work) + 1); sub(/\.c3$/, "", idx); file = orig[idx + 1]
                    gsub(/\t/, " ", code)
                    if (id == "temp-escapes" && code ~ /allocator[[:space:]]*=[[:space:]]*tmem/) next
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, line, s, id, adv, code
                }' >>"$tmp" || true
    done < <(rules | sed 's/ %% /\x1f/g')
    # TODO markers live in comments, so scan the originals for them.
    if ((min <= 1)); then
        grep -nHE 'TODO|FIXME|XXX' "${files[@]}" 2>/dev/null |
            awk '{ file = $0; sub(/:.*/, "", file); rest = substr($0, length(file) + 2); line = rest; sub(/:.*/, "", line)
                   code = substr(rest, length(line) + 2); gsub(/\t/, " ", code)
                   printf "%s\t%s\tlow\ttodo\tunfinished work marker\t%s\n", file, line, code }' >>"$tmp" || true
    fi
    if ((min <= 2)); then
        for i in "${!files[@]}"; do alloc_rethrow "${clean[$i]}" "${files[$i]}"; done >>"$tmp"
    fi

    if [[ ! -s "$tmp" ]]; then
        printf 'no findings at level >= %s\n' "$LEVEL"
        exit 0
    fi
    if ((!QUIET)); then
        sort -t $'\t' -k1,1 -k2,2n "$tmp" | awk -F'\t' -v show="$SHOW_CODE" '{
            printf "%s:%s: [%s %s] %s\n", $1, $2, $3, $4, $5
            if (show) { c = $6; sub(/^[[:space:]]+/, "", c); printf "    > %s\n", substr(c, 1, 160) }
        }'
        printf '\n'
    fi
    printf '== summary (level >= %s) ==\n' "$LEVEL"
    awk -F'\t' '{ n[$3 " " $4]++ } END { for (k in n) printf "%-30s %d\n", k, n[k] }' "$tmp" | sort
    printf '%-30s %d\n' 'total' "$(wc -l <"$tmp")"
    if awk -F'\t' '$3 == "high" { f = 1 } END { exit !f }' "$tmp"; then exit 1; fi
    exit 0
}

main "$@"
