#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Run a gcli command that normally opens an editor (comment, pulls create,
    issues create, releases create, approve -T …) non-interactively: the
    prepared message file is copied into gcli's temporary message file in
    place of an interactive editor. gcli runs the editor with
    execlp(GIT_EDITOR|VISUAL|EDITOR, file), so this script installs itself as
    GIT_EDITOR for the one command it runs.

    WARNING: gcli treats a non-TTY stdin as "yes" to every confirmation
    (gcli_cmd_should_do_always_yes() == !isatty(0)); this script runs gcli
    with stdin from /dev/null, so the command SUBMITS immediately. There is no
    dry run: get the user's approval of the target repo and the message
    before calling this. Passing -y as well documents the intent.

    A stale ./gcli_message (saved by a failed submission) triggers an
    unguarded recall prompt that spins forever on EOF, so it is refused.

Usage:
    ${0##*/} [-h] <message-file> gcli [gcli-args...]

Arguments:
    -h              Show this usage documentation.
    <message-file>  Markdown file with the exact body to submit. Lines that
                    start with '!' are rejected: gcli strips them as comments.
    gcli ...        The gcli command line to run (must start with gcli).

Environment:
    GCLI_MSG_SRC    Internal: set by this script for its editor invocation.
    DEBUG=1         Trace execution.

Exit Codes:
    0   gcli succeeded
    1   gcli failed, or the message could not be installed
    2   usage error (missing file, not a gcli command, '!' lines, stale
        ./gcli_message that would trigger an interactive recall prompt)
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Editor mode: gcli calls us as "<this script> /tmp/gcli_message.XXXXXXX".
editor_mode() {
    local target="$1"
    [[ -f "$GCLI_MSG_SRC" ]] || die "message source vanished: $GCLI_MSG_SRC"
    [[ "$target" == /tmp/gcli_message.* || "$target" == "${TMPDIR:-/tmp}"/gcli_message.* ]] ||
        die "refusing to write unexpected editor target: $target"
    cat -- "$GCLI_MSG_SRC" >"$target"
}

main() {
    if [[ -n "${GCLI_MSG_SRC:-}" && $# -eq 1 ]]; then
        editor_mode "$1"
        return
    fi
    [[ "${1:-}" == -h ]] && { usage; exit 0; }
    (($# >= 2)) || { usage >&2; exit 2; }
    local msg="$1"
    shift
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    [[ -f "$msg" && -r "$msg" ]] || die "message file not readable: $msg" 2
    [[ "${1##*/}" == gcli ]] || die "expected a gcli command after the message file, got: $1" 2
    command -v -- "$1" >/dev/null 2>&1 || die "gcli not found"
    if grep -nE '^!' -- "$msg" >&2; then
        die "lines starting with '!' are dropped by gcli; reword or indent them" 2
    fi
    if [[ -e gcli_message ]]; then
        die "./gcli_message exists (saved from a failed submission); gcli would prompt to recall it. Inspect and remove it first" 2
    fi

    local self
    self="$(readlink -f -- "$0")"
    GCLI_MSG_SRC="$(readlink -f -- "$msg")"
    export GCLI_MSG_SRC
    # GIT_EDITOR has the highest precedence in gcli; VISUAL/EDITOR are left untouched.
    GIT_EDITOR="$self" GCLI_NOSPINNER=1 "$@" </dev/null || exit 1
}

main "$@"
