# linux-configs

Personal Linux configuration files and tooling.

## Contents

| Directory                            | Description                                                                   |
|--------------------------------------|-------------------------------------------------------------------------------|
| [`fonts/`](fonts/)                   | Downloaded/distro fonts, fontconfig rules, installer and tests                |
| [`neovim/`](neovim/)                 | Neovim configs (`nvim`, `nvimgit`, `nvimpager`) and their installer and tests |
| [`vim/`](vim/)                       | Vim configs (`vim`, `vimpager`) and their installer and tests                 |
| [`installer-libs/`](installer-libs/) | Shared installer library used by all families                                 |

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

## License

[GPL-3.0](LICENSE.md)
