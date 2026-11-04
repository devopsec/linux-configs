# linux-configs

Personal Linux configuration files and tooling.

## Contents

| Directory                            | Description                                                                         |
|--------------------------------------|-------------------------------------------------------------------------------------|
| [`fonts/`](fonts/)                   | Downloaded/distro fonts, fontconfig rules, installer and tests                      |
| [`neovim/`](neovim/)                 | Neovim configs (`nvim`, `nvimgit`, `nvimpager`) and their installer and tests       |
| [`vim/`](vim/)                       | Vim configs (`vim`, `vimpager`) and their installer and tests                       |
| [`installer-libs/`](installer-libs/) | Shared installer library used by all families                                       |
| [`junie-cli/`](junie-cli/)           | Junie CLI home (`~/.junie`): agent guidelines, skills, commands, tooling            |
| [`claude-code/`](claude-code/)       | Claude Code home (`~/.claude`): non-sensitive settings, theme, MCP servers          |
| [`resources/`](resources/)           | Bundled packages (`flatpaks/`, `debs/`) and shared agent configs (`agent-configs/`) |

## Installation

Run the root installer to install and configure selected apps (all registered apps are selected by default):

```bash
./install.sh -cc
```

Each family can also be installed on its own by running its own installer, e.g. `fonts/install.sh`, `neovim/install.sh` or `vim/install.sh`.

Flags: `-h` help, `-cc` clean configs, `-cp` clean packages, `-sp` skip packages, `-sc` skip configs, `-im` install mode (`system`, `user`, `auto`),
`-cm` config mode (`global`, `users`, `local`, `auto`).

### Installer Layout

`installer-libs/common.sh` is a compatibility entrypoint that loads focused modules: `cli.sh` parses flags, `registry.sh` stores family/app
declarations and requirements, `scope.sh` resolves user/system access, `fsops.sh` handles scoped file operations, `run.sh` dispatches optional family
hooks, and `pkg/` contains the system-package, Flatpak, release-binary and app backends. Each family registers its apps, declares system requirements
once, and implements only the hooks it needs. The root runner batches the selected families' missing, available system requirements into one
package-manager transaction; optional hooks need no placeholder functions.

### App Documentation

The editor families include `man-db` and `bash-completion` as system requirements. System-package installs use the package's own documentation;
Flatpak installs copy available man pages and shell completions from the app, and release-binary installs fetch a registered man page when available.
Where a generator is configured, bash, zsh and fish completions are generated only when the system does not already provide them. User-scope docs are
installed under `$XDG_DATA_HOME` (default `~/.local/share`); system-scope docs go under `/usr/local/share`. Zsh users may need to add
`~/.local/share/zsh/site-functions` (or `$XDG_DATA_HOME/zsh/site-functions` when `XDG_DATA_HOME` is set) to `fpath`.

## Neovim Look & Behavior

- **Theme:** all three configs default to "Catppuccin Coffee" (a grey-neutral catppuccin-mocha). In `nvim` run `:Themery` to preview and switch live
  between Catppuccin Coffee, Kanagawa (Wave/Dragon), Gruvbox dark, JB and Darcula Dark; the choice is saved in `stdpath("data")/themery/state.json`.
- **Font:** provided by the `fonts` app (see [Fonts](#fonts)). Terminal Neovim cannot set its own font: select "JetBrainsMono Nerd Font" in your
  terminal emulator (`guifont` covers GUIs).
- **Popups:** menus, cmdline, search and the message console are opaque and distinct from the editor background (derived from the active theme); the
  console has its own border colour.
- **Mouse:** `mouse=a`; the wheel never changes mode and scrolls completion, command-line and right-click menus.
- **Menus:** Up/Down move, Left/Right descend/ascend submenus (otherwise no-op), Tab fills without accepting, Shift+Tab does nothing, Enter or left
  click accepts, Home/End first/last entry, PageUp/PageDown move one page.
- **Tabs:** Ctrl+PageUp/PageDown previous/next (wrapping), Ctrl+Home/End first/last.
- **Splits:** Ctrl+Alt+PageUp/PageDown previous/next (wrapping), Ctrl+Alt+Home/End first/last, Ctrl+Alt+arrows move to the nearest split in that
  direction (no wrapping).

## Fonts

`fonts/install.sh` (the fonts family runs before editor families in the root installer; `./install.sh nvim` does not touch fonts) installs:

- **Downloaded fonts:** JetBrainsMono, Symbols Nerd Font Mono (`NerdFontsSymbolsOnly`), FiraCode, FiraMono, Mononoki and Hack Nerd Fonts, plus Gelasio
  and Comic Relief (used by the metric-substitution rules). Each family is stored in its own directory under `~/.local/share/fonts` (`-im user`) or
  `/usr/local/share/fonts` (`-im system`). Already installed fonts are skipped; offline or missing download tools only logs a notice. The Nerd Font
  list is the `NERD_FONTS` array in `fonts/install.sh`.
- **Distro font packages:** the installer declares `fontconfig`, `curl`, `unzip`, and the available equivalents of Croscore, Caladea, Carlito, DejaVu,
  Droid fallback, Font Awesome, FreeFont, Inter, Lato, Liberation, Linux Libertine, Noto (core/extra/mono/UI/CJK/emoji), Open Sans, Gentium, STIX,
  Ubuntu, URW and Inconsolata. It also requests Comic Neue where the distribution provides it. Requirements already installed or unavailable in the
  selected package manager are handled without duplicate installs; font packages currently have apt and pacman mappings, not Nix mappings.
- **Fontconfig rules** from `fonts/fontconfig/conf.d/` into `~/.config/fontconfig/conf.d` (`-cm local`/`users`) or `/etc/fonts/conf.avail` +
  `/etc/fonts/conf.d` symlinks (`-cm global`):
    - `10-nerd-font-symbols.conf`: Symbols Nerd Font Mono as fallback for `monospace` and common mono fonts, so icons render with non-Nerd fonts.
    - `50-metric-substitutes.conf`: Arial, Calibri, Cambria, Consolas, Helvetica, Times New Roman etc. map to metric-compatible fonts.
    - `60-monospace-default.conf`: `monospace` prefers JetBrainsMono Nerd Font (delete this file to keep the distro default).

`-cp` removes only the font directories created by this installer, `-cc` removes only the rule files shipped here. Terminal emulators still need their
font set manually. Test: `fonts/tests/install.sh` (offline).

## Post-Install Shell Configuration

Add the following to `~/.bashrc` to wire up the installed apps:

```bash
export PAGER='nvimpager'
export MANPAGER='nvimpager -p'
export EDITOR='nvim'
export VISUAL='nvim'
```

## Post-Install Git Configuration

Add the following to `~/.gitconfig` to use `nvimgit` as your Git editor and diff/merge tool:

```ini
[core]
pager = nvimpager -a
editor = NVIM_APPNAME=nvimgit nvim
[diff]
tool = nvim
[difftool "nvim"]
cmd = NVIM_APPNAME=nvimgit nvim -d "$LOCAL" "$REMOTE"
[merge]
tool = nvim
[mergetool "nvim"]
cmd = NVIM_APPNAME=nvimgit nvim -d "$LOCAL" "$MERGED" "$REMOTE"
```

## Tests

Installer and headless, no-UI config-load tests:

```bash
fonts/tests/install.sh
installer-libs/tests/run.sh
neovim/tests/startup.sh # nvim, nvimgit, nvimpager and the nvimpager runtime-load case
vim/tests/startup.sh # vim
```

## Agent Configs

| Directory                  | Synced to                  | Contents                                                                                                                                      |
|----------------------------|----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| `resources/agent-configs/` | `~/.junie` and `~/.claude` | `skills/`, `commands/` (agent-agnostic templates) and `custom/` (docs, scripts, shims) used by both agents                                    |
| `junie-cli/config/`        | `~/.junie`                 | `AGENTS.md`, `config.json`, `extensions/`, `mcp/`, `models/`, `sandbox.json`; `skills`/`commands`/`custom` link to `resources/agent-configs/` |
| `claude-code/config/`      | `~/.claude`                | `settings.json`, `themes/`, `mcp/mcp.json`, `CLAUDE.{security,workdir}.md`; `skills`/`commands`/`custom` link to `resources/agent-configs/`   |

Each agent dir has a `sync.sh` that installs **fresh copies** into the agent's home: top-level files are overwritten and each managed directory is
mirrored, so files removed from the repo are deleted there too. Symlinks into `resources/agent-configs/` are resolved, `__pycache__/` is ignored, and runtime state
outside the managed entries (sessions, logs, caches, credentials, history) is never touched. `-n` prints what would change or be deleted without
writing anything.

- `junie-cli/sync.sh` mirrors every entry of `junie-cli/config/` into `~/.junie` (`JUNIE_HOME` overrides). Local-only paths inside managed
  directories are kept: `extensions/marketplaces/` (installed by Junie) and `models/inactive/` (model configs holding API keys); extend the `KEEP`
  list in the script for more.
- `claude-code/sync.sh` mirrors `skills/`, `commands/`, `custom/` and `themes/` into `~/.claude` (`CLAUDE_HOME` overrides). `settings.json` becomes
  the repo version plus only the local keys listed in `PRESERVE_SETTINGS` (`autoMode`, which names work repositories), so keys removed from the
  repo disappear locally. Each MCP server in `mcp/mcp.json` is added to `~/.claude.json` with `claude mcp add-json`, or replaced when it differs;
  servers that are not in the repo are left alone and listed (only for the real `~/.claude`). `~/.claude/CLAUDE.md` is generated from
  `junie-cli/config/AGENTS.md` sections 0-5 (pointing at `~/.claude/custom/`) plus `CLAUDE.security.md` and `CLAUDE.workdir.md`.

Slash commands in `resources/agent-configs/commands/` are templates: each sync renders `{{agent_home}}`, `{{agent}}` and `{{args}}` to
`~/.junie`/`junie`/`$prompt` or `~/.claude`/`claude`/`$ARGUMENTS`. `histmgr` (session history) and `agentmgr` (agent config) work on either agent:
`--agent junie|claude`, else `AGENT_TARGET`, else the calling agent, else the only installed agent, else an interactive prompt when the shims in
`~/.<agent>/custom/bin/` are run from a terminal. See `resources/agent-configs/custom/docs/commands-catalog.md`.

Only non-sensitive files are tracked. Left out on purpose: `~/.claude/.credentials.json`, `~/.claude.json` (account and project state; its MCP
servers are mirrored in `claude-code/config/mcp/mcp.json`), session data (`projects/`, `history.jsonl`, `file-history/`, `sessions/`, caches,
`plans/`), server-managed `policy-limits*`/`remote-settings*` files, plugin caches, Junie's `models/inactive/`, and the `autoMode` block of
`settings.json`, which describes work repositories.

## License

[GPL-3.0](LICENSE.md)
