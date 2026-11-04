#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only scan of C3 sources (*.c3, *.c3i) and project/manifest JSON for
    syntax and stdlib APIs removed or deprecated between C3 0.6 and the
    target version. Prints file:line, version/kind, the fix, and the line.
    Heuristic (grep-based): c3c is the final judge.

Usage:
    ${0##*/} [-h] [-t <version>] [-f <version>] [-k <kinds>] [-q] [-C] <path>...

Arguments:
    -h            Show this usage documentation.
    -t <version>  Version to port TO, x.y.z (default: ${DEFAULT_TARGET}). Rules newer than
                  this are skipped.
    -f <version>  Version the code currently builds with; rules at or below it are
                  skipped (default: apply all up to the target).
    -k <kinds>    Comma list: removed,deprecated,review (default: all).
    -q            Summary only.
    -C            Do not print the offending source line.
    <path>        Files or directories (build/, out/, .git skipped).

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

DEFAULT_TARGET='0.8.5'
TARGET="$DEFAULT_TARGET"
FROM=''
KINDS='removed,deprecated,review'
QUIET=0
SHOW_CODE=1

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Fields separated by ' %% ': version, kind, scope (c3 | proj), ERE, fix.
# version = release where the old form stops compiling (removed) / is deprecated / needs review.
rules() {
    cat <<'RULES'
0.7.0 %% removed %% c3 %% ^[[:space:]]*def[[:space:]]+[@A-Za-z_] %% alias Name = ...; (def renamed to alias)
0.7.0 %% removed %% c3 %% ^[[:space:]]*distinct[[:space:]]+[A-Z] %% typedef Name = Base; (add @constinit if literals must convert)
0.7.0 %% removed %% c3 %% fn[[:space:]]+[A-Za-z0-9_:{}*]+(\[[^]]*\])?![[:space:]] %% optional return types use ?: fn int? f()
0.7.0 %% removed %% c3 %% ^[[:space:]]*[A-Za-z_][A-Za-z0-9_:{}*]*(\[[^]]*\])?![[:space:]]+[a-z_][A-Za-z0-9_]*[[:space:]]*(=|;) %% optional variables use ?: int? x = ...;
0.7.0 %% removed %% c3 %% \banyfault\b %% fault
0.7.0 %% removed %% c3 %% ^[[:space:]]*fault[[:space:]]+[A-Z][A-Za-z0-9_]*[a-z] %% faults are values now: excuse A, B; (faultdef before 0.8.4)
0.7.0 %% removed %% c3 %% [A-Za-z0-9_]\(<[A-Za-z$] %% generics use {}: List{int}; module foo <Type>;
0.7.0 %% removed %% c3 %% \{\| %% expression blocks removed: use a macro or helper fn
0.7.0 %% removed %% c3 %% \$(foreach|for|switch)[[:space:]]*\( %% trailing-colon form: $foreach $x : $list:   $switch $T:   $for var $i = 0; $i < N; $i++:
0.7.0 %% removed %% c3 %% @return! %% @return? FAULT_A, FAULT_B
0.7.0 %% removed %% c3 %% \$(or|and|concat)\( %% |||  &&&  +++
0.7.0 %% removed %% c3 %% mem::temp_(new|alloc|new_array)\b|string::new_from_|file::load_new|to_utf16_(copy|tcopy) %% mem::tnew / mem::talloc / mem::temp_array; string::from_*; file::load(mem, ...); to_utf16 / to_temp_utf16
0.7.0 %% removed %% c3 %% @pool\([[:space:]]*(mem|tmem|allocator|heap|temp)\b %% @pool() takes no allocator (optional reserve size only)
0.7.0 %% removed %% c3 %% \bvoid![[:space:]]+main\b %% fn void main() / fn int main(String[] args); no optional main
0.7.10 %% removed %% c3 %% enum[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*const\b %% constset Name : Type { A = 1, ... } (constdef before 0.8.4)
0.7.10 %% review %% c3 %% ^[[:space:]]*typedef[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*=[[:space:]] %% typedefs no longer accept literals: add @constinit if code does `Name x = 5;`
0.8.0 %% removed %% c3 %% ^[[:space:]]*module[[:space:]]+[a-z_:0-9]+[[:space:]]*\{[A-Z] %% module foo <Type>;
0.8.0 %% removed %% c3 %% (^|[^[:alnum:]_:])[A-Z][A-Z0-9_]+\?[[:space:]]*[;),] %% create optionals with ~: return FOO~;   io::EOF~
0.8.0 %% removed %% c3 %% (^|[^[:alnum:]_.])[0-9][0-9_]*[iu](8|16|32|64|128)\b %% iXX/uXX suffixes removed: (ichar)1, 1u, 1ul, 1ull
0.8.0 %% removed %% c3 %% \bisz\b %% sz
0.8.0 %% review %% c3 %% \busz\b %% 0.8 sizes/lengths/indices are signed sz; keep usz only for C ABI/bit patterns; no implicit signed<->unsigned conversion
0.8.0 %% removed %% c3 %% (^|[^[:alnum:]_.])(\$?[A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*|int|uint|long|ulong|short|ushort|char|ichar|float|double|bool|usz|sz|isz|iptr|uptr|int128|uint128)\.(sizeof|alignof|nameof|qnameof|extnameof|kindof|typeid|membersof|methodsof|paramsof|returns|inner|names|values|len|max|min|inf|nan|associated|elements|is_eq)([^[:alnum:]_(]|$) %% type properties use :: (Foo::size, int::max, Foo::members, Enum::len, Foo::has_equals)
0.8.0 %% removed %% c3 %% \$(sizeof|alignof|offsetof|nameof|qnameof|extnameof|kindof)\( %% @sizeof(x) / @alignof(x) / @kindof(x) / $reflect(T.f).offset / ::name
0.8.0 %% removed %% c3 %% \$(typeof|typefrom|evaltype)\( %% $Typeof(x) / $Typefrom(...)
0.8.0 %% removed %% c3 %% \$(is_const|assignable|vacount|vasplat|vaexpr|vaconst|vatype)\b %% $defined(...) / $vaarg.len / ...$vaarg / $vaarg[i] / $Typefrom($vaarg[i])
0.8.0 %% removed %% c3 %% @(assignable_to|is_const|is_lvalue|typekind|typeis)\( %% $defined(...) / @kindof(x) / $Typeof(x) == T
0.8.0 %% removed %% c3 %% \.nameof\b %% .description
0.8.0 %% removed %% c3 %% @structlike\b %% typedefs are struct-like by default; @constinit opts into literal conversion
0.8.0 %% removed %% c3 %% @extern\( %% @cname("symbol")
0.8.0 %% removed %% c3 %% @operator\(!=\) %% overload == (and < for ordering) only
0.8.0 %% removed %% c3 %% enum[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*inline\b %% inline enums removed: constset Name : inline Type { ... } or .ordinal
0.8.0 %% removed %% c3 %% [A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*\.lookup\( %% Enum::lookup_field(field, value)
0.8.0 %% removed %% c3 %% \bSubProcess\b|process::create\(|process::execute_stdout_to_buffer %% Process / process::spawn / process::run_capture_stdout
0.8.0 %% removed %% c3 %% \b(encode_buffer|decode_buffer)\(|hex::(encode|decode)_bytes\( %% encode_into / decode_into (dst first); hex::encode_bytes_into
0.8.0 %% removed %% c3 %% @unaligned_(load|store)\( %% mem::load(ptr, align) / mem::store(ptr, value, align)
0.8.0 %% removed %% c3 %% allocator::(heap|temp)\(\) %% mem / tmem
0.8.0 %% removed %% c3 %% json::parse_string\( %% json::parse(mem, string)
0.8.0 %% review %% c3 %% json::parse\( %% 0.8.0: json::parse(alloc, String); streams use json::load(alloc, stream)
0.8.0 %% removed %% c3 %% \.set_cursor\( %% .seek(offset, whence)
0.8.0 %% removed %% c3 %% path::temp\( %% path::tnew(s)
0.8.0 %% removed %% c3 %% \.strip_end\( %% .strip_suffix(s)
0.8.0 %% review %% c3 %% \.strip\( %% String.strip was renamed strip_prefix in 0.8.0
0.8.0 %% removed %% c3 %% \b(cosec|cotan|muladd)\( %% csc / cot / mad
0.8.0 %% removed %% c3 %% math::(PI_2|PI_4|DIV_PI)\b %% math::HALF_PI / QUARTER_PI / INV_PI
0.8.0 %% removed %% c3 %% diff_hour\(|\.set_date\(|datetime::from_date %% diff_hours / DateTime.set / datetime::at_*
0.8.0 %% removed %% c3 %% \.(updatec|update_char)\( %% .update_byte(b)
0.8.0 %% removed %% c3 %% \bElasticArray\b %% FixedList{T, N}
0.8.0 %% removed %% c3 %% \[\*\]\[\*\] %% multi-level inference removed: spell the inner sizes
0.8.0 %% removed %% c3 %% (^|[^(])if[[:space:]]*\([a-z_][A-Za-z0-9_.]*[[:space:]]*=[^=] %% assignment in a condition needs parens: if ((x = f()))
0.8.0 %% review %% c3 %% catch[^;]*\.(lock|unlock|destroy|signal|broadcast|detach)\( %% mutex/thread/condvar lock/unlock/destroy no longer return optionals (0.8.0)
0.8.0 %% review %% c3 %% (\?\?|\?:)[^;,)]*[[:space:]][+-][[:space:]] %% ?? and ?: now bind tighter than + and -: add parens if the old meaning was intended
0.8.0 %% review %% c3 %% [A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*[[:space:]]+[a-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[a-z_][A-Za-z0-9_]*[[:space:]]*[+-][[:space:]]*[0-9]+[[:space:]]*; %% if the left type is an enum: + / - on enums removed (use from_ordinal(e.ordinal + n) or ++/--)
0.8.1 %% deprecated %% c3 %% \$[a-z_]+\.(get|set)\( %% v.$member / v.$member = x (string names: v.$eval form, see docs)
0.8.1 %% deprecated %% c3 %% \bLinkedHash(Map|Set)\b %% OrderedMap / OrderedSet
0.8.1 %% deprecated %% c3 %% @loop_over_ai\b %% @loop_over_addresses (set *retain_socket = true to keep it)
0.8.1 %% deprecated %% c3 %% \bFixedThreadPool\b %% thread::ThreadPool (init(mem, max_threads))
0.8.3 %% deprecated %% c3 %% \$feature\( %% $feat(NAME)
0.8.3 %% review %% c3 %% ^[[:space:]]*(fn|macro|struct|union|enum|bitstruct|typedef|alias|const|extern|module|interface|[A-Z][A-Za-z0-9_{}*]*[[:space:]]+[a-z_]).*@if\( %% top-level @if on non-generic declarations is deprecated: @feat(LINUX | WIN32 ...) (keep @if for generic params)
0.8.3 %% deprecated %% c3 %% json::temp_load\( %% json::tload(stream)
0.8.4 %% review %% c3 %% \b(faultdef|attrdef|constdef)\b %% 0.8.4+ keywords: excuse / attrmacro / constset (old ones accepted until 0.9)
0.8.4 %% review %% c3 %% pool::ThreadPool|\bThreadPoolOld\b %% new thread::ThreadPool is the default; old one needs -D OLD_THREADPOOL
0.8.4 %% review %% c3 %% io::EOF %% InStream.read returns 0 at EOF since 0.8.4 (read_byte/readline still raise io::EOF): check read loops
0.8.5 %% removed %% c3 %% \b(cenum|faultset)\b %% constset / excuse (experimental alternates removed in 0.8.5)
0.8.5 %% deprecated %% c3 %% env::os_is_(posix|darwin)\( %% $feat(POSIX) / $feat(DARWIN)
0.8.5 %% review %% proj %% "(depends-on|env|env-override|compress)"[[:space:]]*:|"source-lib"|\$\{[A-Za-z_] %% project.json feature not available in c3c 0.8.5 (master/0.8.6+): needs a newer compiler
RULES
}

# Copies a C3 file with comments blanked (doc <* *>, /* */, //) so line numbers are kept.
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

ver_le() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]; }

collect_files() {
    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
        elif [[ -d "$p" ]]; then
            find "$p" \( -name build -o -name out -o -name .git \) -prune -o -type f \
                \( -name '*.c3' -o -name '*.c3i' -o -name '*.c3t' -o -name 'project.json' -o -name 'project.json5' \
                -o -name 'manifest.json' \) -print0
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
    TARGET="${TARGET%%_*}"; FROM="${FROM%%_*}"
    [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "-t expects x.y.z, e.g. 0.8.5" 2
    [[ -z "$FROM" || "$FROM" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "-f expects x.y.z, e.g. 0.7.11" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    local -a c3_files=() proj_files=()
    local f
    while IFS= read -r -d '' f; do
        case "$f" in
            *.json|*.json5) proj_files+=("$f") ;;
            *) c3_files+=("$f") ;;
        esac
    done < <(collect_files "$@")
    ((${#c3_files[@]} + ${#proj_files[@]} > 0)) || { printf 'no C3 files found\n' >&2; exit 0; }

    local tmp work i
    tmp="$(mktemp)"
    work="$(mktemp -d)"
    trap 'rm -rf -- "$tmp" "$work"' EXIT
    local -a clean_files=()
    for i in "${!c3_files[@]}"; do
        sanitize "${c3_files[$i]}" >"$work/$i.c3"
        clean_files+=("$work/$i.c3")
    done

    local version kind scope regex fix
    local -a targets
    while IFS=$'\x1f' read -r version kind scope regex fix; do
        [[ -n "$version" ]] || continue
        ver_le "$version" "$TARGET" || continue
        if [[ -n "$FROM" ]] && ver_le "$version" "$FROM"; then continue; fi
        [[ ",$KINDS," == *",$kind,"* ]] || continue
        case "$scope" in
            c3) targets=("${clean_files[@]}") ;;
            proj) targets=("${proj_files[@]}") ;;
            *) die "bad rule scope: $scope" ;;
        esac
        ((${#targets[@]} > 0)) || continue
        grep -nHE -- "$regex" "${targets[@]}" 2>/dev/null |
            awk -v v="$version" -v k="$kind" -v fx="$fix" -v work="$work/" -v names="$(printf '%s\n' "${c3_files[@]}")" '
                BEGIN { n = split(names, orig, "\n") }
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    if (index(file, work) == 1) { idx = substr(file, length(work) + 1); sub(/\.c3$/, "", idx); file = orig[idx + 1] }
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
