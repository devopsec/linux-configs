#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Install junie-cli/config/ into ~/.junie as fresh copies: every top-level
    file is overwritten and every top-level directory is mirrored (files that
    were removed from the repo are deleted), with symlinks into
    resources/agent-configs/ resolved. Slash commands are rendered from the
    shared templates for Junie. Runtime state outside the managed entries
    (sessions, logs, caches, credentials, settings.json, ...) is never touched.

Usage:
    ${0##*/} [-h] [-n]

Arguments:
    -h    Show this usage documentation.
    -n    Dry run: list what would change or be deleted; write nothing.

Environment:
    JUNIE_HOME=<dir>   Target instead of ~/.junie.

Exit Codes:
    0   synced (or dry run finished)
    1   rsync or rendering failed
    2   usage error
EOF
}

set -Eeuo pipefail

# Paths inside managed directories that are local-only and must survive the mirror:
#   extensions/marketplaces/  installed by Junie at runtime
#   models/inactive/          local model configs (hold API keys; kept out of the repo)
KEEP=(extensions/marketplaces/ models/inactive/)

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
src="$here/config"
junie="${JUNIE_HOME:-$HOME/.junie}"
dry=0

while getopts ':hn' opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        n) dry=1 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
(($# == 0)) || { usage >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

opts=(-rcL --exclude=__pycache__/)
if ((dry)); then opts+=(--dry-run --itemize-changes); else opts+=(--info=del); fi

# Render the shared command templates for Junie.
mkdir -p "$tmp/commands"
for f in "$src/commands/"*.md; do
    sed -e 's|{{agent_home}}|~/.junie|g' -e 's|{{agent}}|junie|g' -e 's|{{args}}|$prompt|g' \
        "$f" > "$tmp/commands/${f##*/}"
done

((dry)) || mkdir -p "$junie"
for entry in "$src"/*; do
    name="${entry##*/}"
    if [[ -d "$entry" ]]; then
        from="$entry/"
        [[ "$name" == commands ]] && from="$tmp/commands/"
        filters=()
        for k in "${KEEP[@]}"; do
            [[ "$k" == "$name/"* ]] && filters+=("--filter=P /${k#"$name"/}")
        done
        rsync "${opts[@]}" --delete "${filters[@]}" "$from" "$junie/$name/"
    else
        rsync "${opts[@]}" "$entry" "$junie/$name"
    fi
done

if ((dry)); then
    echo "dry run: nothing written ($src -> $junie)"
else
    echo "synced: $src -> $junie"
fi
