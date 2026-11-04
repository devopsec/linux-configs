#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Install claude-code/config/ into ~/.claude as fresh copies, resolving the
    symlinks into resources/agent-configs/:
      skills/, custom/, themes/   mirrored (files removed from the repo are deleted)
      commands/                   rendered from the shared templates, mirrored
      settings.json               repo version, plus the local-only keys listed in
                                  PRESERVE_SETTINGS (autoMode) taken from the current file
      mcp/mcp.json                each server is added, or replaced when it differs,
                                  in ~/.claude.json via 'claude mcp'; servers not in
                                  the repo are left alone and reported
      CLAUDE.md                   generated: junie-cli AGENTS.md sections 0-5 converted
                                  for Claude Code, then CLAUDE.security.md and
                                  CLAUDE.workdir.md appended
    Runtime state (projects/, sessions, history, credentials, plugins, ...) is
    never touched.

Usage:
    ${0##*/} [-h] [-n]

Arguments:
    -h    Show this usage documentation.
    -n    Dry run: list what would change, be deleted or be updated; write nothing.

Environment:
    CLAUDE_HOME=<dir>   Target instead of ~/.claude. MCP servers are only applied
                        to the real ~/.claude, so a test home never touches ~/.claude.json.

Exit Codes:
    0   synced (or dry run finished)
    1   rsync, jq or claude failed
    2   usage error
EOF
}

set -Eeuo pipefail

# settings.json keys that stay local: autoMode describes work repositories and is
# kept out of this repo, so the current value survives the fresh copy.
PRESERVE_SETTINGS='["autoMode"]'
MIRROR_DIRS=(skills custom themes)

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
src="$here/config"
agents_md="$here/../junie-cli/config/AGENTS.md"
claude="${CLAUDE_HOME:-$HOME/.claude}"
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

opts=(-rcL --delete --exclude=__pycache__/)
if ((dry)); then opts+=(--dry-run --itemize-changes); else opts+=(--info=del); fi

# Installs $1 as $2 unless identical; reports instead of writing in dry-run mode.
install_file() {
    local new="$1" dest="$2" mode="$3"
    if [[ -f "$dest" ]] && cmp -s "$new" "$dest"; then
        return 0
    fi
    if ((dry)); then
        echo "would update $dest"
    else
        install -m "$mode" "$new" "$dest"
        echo "updated $dest"
    fi
}

((dry)) || mkdir -p "$claude"

for d in "${MIRROR_DIRS[@]}"; do
    rsync "${opts[@]}" "$src/$d/" "$claude/$d/"
done

mkdir -p "$tmp/commands"
for f in "$src/commands/"*.md; do
    sed -e 's|{{agent_home}}|~/.claude|g' -e 's|{{agent}}|claude|g' -e 's|{{args}}|$ARGUMENTS|g' \
        "$f" > "$tmp/commands/${f##*/}"
done
rsync "${opts[@]}" "$tmp/commands/" "$claude/commands/"

# settings.json: the repo copy wins; only PRESERVE_SETTINGS keys are carried over.
if [[ -f "$claude/settings.json" ]]; then
    jq -s --argjson keep "$PRESERVE_SETTINGS" \
        '.[1] + (.[0] | with_entries(select(.key as $k | $keep | index($k))))' \
        "$claude/settings.json" "$src/settings.json" > "$tmp/settings.json"
else
    jq . "$src/settings.json" > "$tmp/settings.json"
fi
install_file "$tmp/settings.json" "$claude/settings.json" 600

# User-scope MCP servers live in ~/.claude.json, which Claude Code owns: change it only via
# the CLI, and only for the real ~/.claude.
if [[ "$claude" != "$HOME/.claude" ]]; then
    echo "mcp: skipped (CLAUDE_HOME is not ~/.claude)"
elif ! command -v claude >/dev/null 2>&1; then
    echo "mcp: skipped (claude CLI not found)" >&2
else
    state="$HOME/.claude.json"
    [[ -f "$state" ]] || echo '{}' > "$tmp/empty.json"
    [[ -f "$state" ]] || state="$tmp/empty.json"
    while IFS=$'\t' read -r name json; do
        if jq -e --arg n "$name" --argjson want "$json" '(.mcpServers // {})[$n] == $want' "$state" >/dev/null; then
            echo "mcp: $name up to date"
        elif jq -e --arg n "$name" '(.mcpServers // {}) | has($n)' "$state" >/dev/null; then
            if ((dry)); then
                echo "mcp: would replace $name"
            else
                claude mcp remove --scope user "$name" >/dev/null
                claude mcp add-json --scope user "$name" "$json"
            fi
        elif ((dry)); then
            echo "mcp: would add $name"
        else
            claude mcp add-json --scope user "$name" "$json"
        fi
    done < <(jq -r '.mcpServers | to_entries[] | "\(.key)\t\(.value | tojson)"' "$src/mcp/mcp.json")
    jq -r --slurpfile repo "$src/mcp/mcp.json" \
        '(.mcpServers // {}) | keys[] | select(. as $k | $repo[0].mcpServers | has($k) | not)' "$state" |
        while read -r name; do echo "mcp: $name not in repo (left as is)"; done
fi

# CLAUDE.md: Claude's own copy of custom/ is used, so ~/.junie/custom/ paths point at ~/.claude/custom/.
sed -n '1,/^## 6\. /p' "$agents_md" | sed '$d' \
    | sed -e 's/Junie co-author trailer/Claude co-author trailer/' \
          -e 's/Skills are auto-listed by Junie; project `\.junie\/skills\/` override global `~\/\.junie\/skills\/`\./Skills are auto-listed by Claude; project `.claude\/skills\/` override global `~\/.claude\/skills\/`./' \
          -e 's/`grep_search`\/`glob_search`/`Grep`\/`Glob`/' \
          -e 's/`get_file_structure` first, then targeted `open`/`Grep` for symbols first, then targeted `Read` with offset\/limit/' \
          -e 's/Never `cat` files to terminal\./Never `cat` files in Bash./' \
          -e 's|~/\.junie/custom/|~/.claude/custom/|g' \
    > "$tmp/CLAUDE.md"
cat "$src/CLAUDE.security.md" "$src/CLAUDE.workdir.md" >> "$tmp/CLAUDE.md"
install_file "$tmp/CLAUDE.md" "$claude/CLAUDE.md" 644

if ((dry)); then
    echo "dry run: nothing written ($src -> $claude)"
else
    echo "synced: $src -> $claude"
fi
