#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Grep-based inventory of Rust code and Cargo.toml that must or should
    change when moving to a newer edition (2018/2021/2024), raising the MSRV
    (crates/patterns now in std), or upgrading common crates across a major
    version. Prints file:line, kind, rule, and the fix per hit. Read-only.
    'cargo fix --edition' handles most 'edition' hits automatically; 'manual'
    hits need a human; the compiler remains the final judge.

Usage:
    ${0##*/} [-h] [-f <edition>] [-t <edition>] [-m <msrv>] [-k <kinds>] [-q] [-C] <path>...

Arguments:
    -h              Show this usage documentation.
    -f <edition>    Source edition: 2015, 2018, 2021 (default: 2015 = report
                    every edition step up to -t).
    -t <edition>    Target edition: 2018, 2021, 2024 (default: 2024).
    -m <msrv>       Target MSRV for 'superseded' hits (default: installed
                    rustc). Hits needing a newer rustc are hidden.
    -k <kinds>      Comma list of kinds to report (default: all):
                      edition     changes 'cargo fix --edition' applies
                      manual      edition changes needing a human
                      superseded  crate/pattern replaced by std at <= msrv
                      deprecated  deprecated std APIs
                      crate       renames across crate major versions
                                  (only relevant when upgrading that crate)
    -q              Summary only.
    -C              Do not print the offending source line.
    <path>          Files or directories (*.rs and Cargo.toml; target/,
                    .git/, vendor/ skipped).

Environment:
    DEBUG=1         Trace execution.

Exit Codes:
    0   no 'edition' or 'manual' hits
    1   at least one 'edition' or 'manual' hit (work needed for the target edition)
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

FROM=2015
TARGET=2024
MSRV=''
KINDS='edition,manual,superseded,deprecated,crate'
QUIET=0
SHOW_CODE=1

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Rule table, fields separated by ' %% ': kind, gate, id, file (rs|toml), ERE, advice.
# gate = edition year for edition/manual, minimum rustc for superseded/deprecated, '-' for crate.
rules() {
    cat <<'RULES'
edition %% 2018 %% try-macro %% rs %% (^|[^[:alnum:]_#])try!\( %% try! is reserved: use the ? operator
edition %% 2021 %% bare-trait-object %% rs %% (Box|Arc|Rc)<[[:space:]]*(Fn|FnMut|FnOnce|Error|Any|Iterator|Future)[[:space:]<(>] %% bare trait objects are a hard error in 2021: Box<dyn Trait> (cargo fix adds dyn)
superseded %% 1.30 %% extern-crate %% rs %% ^[[:space:]]*(#\[[^]]*\][[:space:]]*)*extern[[:space:]]+crate[[:space:]]+[[:alnum:]_]+[[:space:]]*; %% unnecessary since 2018 (except `extern crate alloc/proc_macro/test`): use `use`
edition %% 2021 %% panic-fmt %% rs %% (^|[^[:alnum:]_])(panic|unreachable)!\("[^"]*\{[^"]*"\) %% 2021: single-argument panic! is a format string; use panic!("{}", s) or escape braces
manual %% 2021 %% range-pattern-dots %% rs %% [0-9a-zA-Z_'][[:space:]]*\.\.\.[[:space:]]*[0-9a-zA-Z_'] %% `...` range patterns are a hard error in 2021: use ..=
edition %% 2021 %% array-into-iter %% rs %% \][[:space:]]*\.into_iter\(\) %% arrays iterate by value with into_iter() in 2021; use .iter() if references were intended
superseded %% 1.55 %% convert-import %% rs %% use[[:space:]]+(std|core)::convert::\{?(TryFrom|TryInto)|use[[:space:]]+(std|core)::iter::FromIterator %% in the 2021 prelude: drop the import (keep only for 2015/2018 crates)
edition %% 2024 %% unsafe-extern-block %% rs %% ^[[:space:]]*(#\[[^]]*\][[:space:]]*)*extern[[:space:]]*("[^"]*")?[[:space:]]*\{ %% 2024: extern blocks must be `unsafe extern "C" { … }` (cargo fix adds it); consider marking items `safe fn`
edition %% 2024 %% unsafe-attr %% rs %% #\[(no_mangle|export_name|link_section)([^[:alnum:]_]|$) %% 2024: write #[unsafe(no_mangle)] / #[unsafe(export_name = "…")] / #[unsafe(link_section = "…")]
manual %% 2024 %% env-set-var %% rs %% env::(set_var|remove_var)\( %% 2024: unsafe fn (racy in multi-threaded programs); wrap in unsafe with a SAFETY argument, or pass env to Command instead
manual %% 2024 %% static-mut %% rs %% static[[:space:]]+mut[[:space:]] %% 2024 denies references to static mut: use atomics/Mutex/OnceLock, or &raw const/&raw mut
edition %% 2024 %% gen-keyword %% rs %% (\.|fn[[:space:]]+|let[[:space:]]+(mut[[:space:]]+)?|[(,][[:space:]]*)gen([[:space:]]*[(:=<,)]|::<) %% `gen` is reserved in 2024: r#gen, or rand 0.9 `random()`
edition %% 2024 %% expr-fragment %% rs %% \$[[:alnum:]_]+:expr([^_[:alnum:]]|$) %% 2024: $x:expr also matches `const { }` and `_`; cargo fix rewrites to expr_2021 where ambiguous — check macro arms
manual %% 2024 %% if-let-temporary %% rs %% if[[:space:]]+let[[:space:]].*\.(lock|borrow|borrow_mut|read|write|try_lock)\(\) %% 2024: if-let scrutinee temporaries drop before else; guards no longer live into the else branch
edition %% 2024 %% unsafe-fn-body %% rs %% (^|[[:space:]])unsafe[[:space:]]+fn[[:space:]] %% 2024 warns on unsafe ops directly in unsafe fn bodies; cargo fix wraps them in unsafe { } — then add a SAFETY comment per block
edition %% 2024 %% box-slice-into-iter %% rs %% Box<\[[^]]*\]>.*into_iter\(\) %% 2024: Box<[T]>::into_iter yields T by value (was &T)
edition %% 2024 %% cargo-project-table %% toml %% ^[[:space:]]*\[project\] %% 2024: use [package]
edition %% 2024 %% cargo-underscore-keys %% toml %% (^|[[:space:]{,[])(default_features|crate_type|proc_macro|dev_dependencies|build_dependencies)([[:space:]]*=|\]) %% 2024: use the dashed key (default-features, crate-type, proc-macro, dev-dependencies, build-dependencies)
manual %% 2024 %% cargo-inherited-default-features %% toml %% workspace[[:space:]]*=[[:space:]]*true.*default-features[[:space:]]*=[[:space:]]*false|default-features[[:space:]]*=[[:space:]]*false.*workspace[[:space:]]*=[[:space:]]*true %% 2024: error unless the [workspace.dependencies] entry also sets default-features = false (1.99 allows the override for 2024 members)
manual %% 2024 %% cargo-resolver %% toml %% resolver[[:space:]]*=[[:space:]]*"[12]" %% edition 2024 defaults to resolver 3 (MSRV-aware); virtual workspaces must set resolver = "3" explicitly
superseded %% 1.59 %% num-cpus %% rs %% num_cpus::get(_physical)?\( %% std::thread::available_parallelism() (cgroup-aware)
superseded %% 1.68 %% pin-macro %% rs %% (pin_utils::pin_mut|futures::pin_mut|futures_util::pin_mut)! %% std::pin::pin!(fut)
superseded %% 1.70 %% atty %% rs %% atty::is\( %% std::io::IsTerminal: std::io::stdout().is_terminal()
superseded %% 1.70 %% once-cell-oncecell %% rs %% once_cell::(sync|unsync)::OnceCell %% std::sync::OnceLock / std::cell::OnceCell
superseded %% 1.80 %% once-cell-lazy %% rs %% once_cell::(sync|unsync)::Lazy %% std::sync::LazyLock / std::cell::LazyCell
superseded %% 1.80 %% lazy-static %% rs %% lazy_static!|lazy_static::lazy_static %% static X: LazyLock<T> = LazyLock::new(|| …);
superseded %% 1.75 %% async-trait %% rs %% #\[(async_trait::)?async_trait(\]|\() %% native async fn in traits — but not dyn-compatible and no Send bound: keep async-trait (or trait-variant) where dyn/Send is required
superseded %% 1.77 %% memoffset %% rs %% memoffset::offset_of|use[[:space:]]+memoffset %% std::mem::offset_of!(Type, field)
superseded %% 1.79 %% static-assertions %% rs %% const_assert(_eq)?!|static_assertions:: %% const { assert!(…) }; (inline const, 1.79)
superseded %% 1.82 %% addr-of %% rs %% (ptr::)?addr_of(_mut)?!\( %% &raw const place / &raw mut place
superseded %% 1.88 %% bench-attr %% rs %% #\[bench\] %% #[bench] is destabilized: use criterion or divan in benches/ with harness = false
superseded %% 1.89 %% fs-lock-crates %% rs %% (fs2|fs4|fd_lock)::|FileExt::(lock_exclusive|try_lock_exclusive|lock_shared) %% std File::lock / try_lock / lock_shared / unlock
superseded %% 1.95 %% cfg-if %% rs %% cfg_if::cfg_if!|(^|[^[:alnum:]_])cfg_if![[:space:]]*\{ %% std cfg_select! { cfg(...) => { … } _ => { … } }
superseded %% 1.96 %% assert-matches %% rs %% assert!\([[:space:]]*matches!\( %% std assert_matches!(value, Pattern)
deprecated %% 1.0 %% mem-uninitialized %% rs %% mem::uninitialized %% MaybeUninit (mem::uninitialized is UB for most types)
deprecated %% 1.30 %% trim-left-right %% rs %% \.trim_(left|right)(_matches)?\( %% trim_start / trim_end (_matches)
deprecated %% 1.42 %% error-description %% rs %% \.description\(\)|fn[[:space:]]+description\(&self\) %% Error::description is deprecated: implement/use Display
deprecated %% 1.33 %% error-cause %% rs %% \.cause\(\)|fn[[:space:]]+cause\(&self\) %% Error::cause is deprecated: use source()
deprecated %% 1.51 %% spin-loop-hint %% rs %% atomic::spin_loop_hint|ATOMIC_(USIZE|BOOL|ISIZE)_INIT %% std::hint::spin_loop / AtomicUsize::new(0)
crate %% - %% rand-09 %% rs %% thread_rng\(\)|\.gen_range\(|\.gen::<|\.gen\(\)|gen_bool\(|rand::random::<|distributions:: %% rand 0.9: rand::rng(), random_range, random::<T>(), random_bool, distr:: (gen is a 2024 keyword)
crate %% - %% axum-08-paths %% rs %% \.route\("[^"]*/[:*][[:alnum:]_]+ %% axum 0.8: path params are /{id} and wildcards /{*rest}
crate %% - %% axum-08-async-trait %% rs %% #\[(axum::)?async_trait\][[:space:]]*$|impl<[^>]*>[[:space:]]+FromRequest(Parts)?< %% axum 0.8: FromRequest/FromRequestParts impls use native async fn (drop #[async_trait])
crate %% - %% hyper-1 %% rs %% hyper::(Body|Server|Client)([^[:alnum:]_]|$)|hyper::body::to_bytes %% hyper 1.0: http_body_util (Full, BodyExt::collect), hyper_util server/client legacy builders
crate %% - %% base64-engine %% rs %% base64::(encode|decode)(_config)?\( %% base64 0.21+: use base64::engine::general_purpose::STANDARD.encode/decode (Engine trait)
crate %% - %% tokio-02 %% rs %% time::delay_for|time::delay_until|tokio::io::split\(|Runtime::block_on_all %% tokio 1.x: time::sleep / sleep_until; into_split() on TcpStream
crate %% - %% structopt %% rs %% structopt::|#\[structopt\( %% clap 4 derive: #[derive(Parser)], #[arg(...)], #[command(...)]
crate %% - %% clap-3-attrs %% rs %% #\[clap\((short|long|value_name|default_value|about|version|subcommand) %% clap 4: field attrs are #[arg(...)], struct attrs #[command(...)]
crate %% - %% failure-error-chain %% rs %% failure::|error_chain! %% unmaintained: thiserror (libraries) / anyhow (applications)
crate %% - %% chrono-deprecated %% rs %% Utc::today\(\)|Local::today\(\)|NaiveDateTime::from_timestamp(_opt)?\(|\.timestamp_nanos\(\)|NaiveDate::from_ymd\( %% chrono 0.4.35+: Utc::now().date_naive(), DateTime::from_timestamp, timestamp_nanos_opt, from_ymd_opt
crate %% - %% tempdir-crate %% rs %% tempdir::TempDir|extern[[:space:]]+crate[[:space:]]+tempdir %% tempdir is deprecated: tempfile::tempdir()
crate %% - %% nix-fd-types %% rs %% nix::unistd::(close|dup2?|dup3|pipe2?)\( %% nix 0.27+: OwnedFd/BorrowedFd/AsFd instead of RawFd; check the nix CHANGELOG at the target version
RULES
}

# Succeeds when version $1 <= version $2.
version_le() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]
}

collect_files() {
    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
        elif [[ -d "$p" ]]; then
            find "$p" \( -name target -o -name .git -o -name vendor -o -name node_modules \) -prune \
                -o -type f \( -name '*.rs' -o -name Cargo.toml \) -print0
        else
            die "no such file or directory: $p" 2
        fi
    done
}

main() {
    local opt
    while getopts ':hf:t:m:k:qC' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            f) FROM="$OPTARG" ;;
            t) TARGET="$OPTARG" ;;
            m) MSRV="$OPTARG" ;;
            k) KINDS="$OPTARG" ;;
            q) QUIET=1 ;;
            C) SHOW_CODE=0 ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# > 0)) || { usage >&2; exit 2; }
    [[ "$FROM" =~ ^(2015|2018|2021)$ ]] || die "-f expects 2015, 2018, or 2021" 2
    [[ "$TARGET" =~ ^(2018|2021|2024)$ ]] || die "-t expects 2018, 2021, or 2024" 2
    ((FROM < TARGET)) || die "source edition $FROM is not older than target $TARGET" 2
    if [[ -z "$MSRV" ]]; then
        MSRV="$(rustc -V 2>/dev/null | awk '{ print $2 }')"
        MSRV="${MSRV%%-*}"
        MSRV="${MSRV:-999.0}"
    fi
    [[ "$MSRV" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "-m expects a version like 1.85" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    local -a rs=() toml=()
    local f
    while IFS= read -r -d '' f; do
        if [[ "$f" == *.rs ]]; then rs+=("$f"); else toml+=("$f"); fi
    done < <(collect_files "$@")
    ((${#rs[@]} + ${#toml[@]} > 0)) || { printf 'no Rust or Cargo.toml files found\n' >&2; exit 0; }

    local tmp
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' EXIT

    local kind gate id scope regex advice
    local -a targets
    while IFS=$'\x1f' read -r kind gate id scope regex advice; do
        [[ -n "$kind" && ",$KINDS," == *",$kind,"* ]] || continue
        case "$kind" in
            edition | manual) ((gate > FROM && gate <= TARGET)) || continue ;;
            superseded | deprecated) version_le "$gate" "$MSRV" || continue ;;
        esac
        if [[ "$scope" == toml ]]; then targets=("${toml[@]}"); else targets=("${rs[@]}"); fi
        ((${#targets[@]} > 0)) || continue
        grep -nHE -- "$regex" "${targets[@]}" 2>/dev/null |
            awk -v k="$kind" -v g="$gate" -v id="$id" -v adv="$advice" '
                {
                    file = $0; sub(/:.*/, "", file)
                    rest = substr($0, length(file) + 2)
                    line = rest; sub(/:.*/, "", line)
                    code = substr(rest, length(line) + 2)
                    if (code ~ /^[[:space:]]*(\/\/|#[^[]|#$)/) next
                    gsub(/\t/, " ", code)
                    tag = (g == "-") ? k : k " " g
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, line, tag, id, adv, code
                }' >>"$tmp" || true
    done < <(rules | sed 's/ %% /\x1f/g')

    if [[ ! -s "$tmp" ]]; then
        printf 'no findings (%s -> %s, msrv %s, kinds %s)\n' "$FROM" "$TARGET" "$MSRV" "$KINDS"
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
    printf '== summary (%s -> %s, msrv %s) ==\n' "$FROM" "$TARGET" "$MSRV"
    awk -F'\t' '{ n[$3 "  " $4]++ } END { for (k in n) printf "%-44s %d\n", k, n[k] }' "$tmp" | sort
    printf '%-44s %d\n' 'total' "$(wc -l <"$tmp")"
    if awk -F'\t' '$3 ~ /^(edition|manual) / { found = 1 } END { exit !found }' "$tmp"; then exit 1; fi
    exit 0
}

main "$@"
