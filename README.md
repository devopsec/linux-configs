# linux-configs

Personal Linux configuration files and tooling.

## Contents

| Directory                 | Description                                    |
|---------------------------|------------------------------------------------|
| [`neovim/`](neovim/)      | Neovim configs (`nvim`, `nvimgit`, `nvimpager`) and their installer and tests |
| [`vim/`](vim/)            | Vim configs (`vim`, `vimpager`) and their installer and tests |
| [`lib/`](lib/)            | Shared installer library used by both families |

## Installation

Run the root installer to install and configure the selected apps (all apps by default):

```bash
./install.sh -cc
```

Each family can also be installed on its own by running its own installer, e.g. `neovim/install.sh` or `vim/install.sh`.

Flags: `-h` help, `-cc` clean configs, `-cp` clean packages, `-sp` skip packages, `-sc` skip configs, `-im` install mode (`system`, `user`, `auto`), `-cm` config mode (`global`, `users`, `local`, `auto`).

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

Headless, no-UI config-load tests are per family:

```bash
neovim/tests/startup.sh # nvim, nvimgit, nvimpager and the nvimpager runtime-load case
vim/tests/startup.sh    # vim
```

## License

[GPL-3.0](LICENSE.md)
