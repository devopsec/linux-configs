# xvim

A collection of Vim-like editor configurations for Linux, designed to be installed and used alongside each other via a
single installer script.

## Included Configurations

| Config       | App    | Purpose                                              |
|--------------|--------|------------------------------------------------------|
| `nvim/`      | Neovim | Full-featured daily-driver editor                    |
| `nvimgit/`   | Neovim | Git-focused config (diff tool, commit editor, pager) |
| `nvimpager/` | Neovim | Neovim used as a terminal pager (`$PAGER`)           |
| `vim/`       | Vim    | Lightweight classic Vim config (`~/.vimrc`)          |
| `vimpager/`  | Vim    | Classic Vim used as a terminal pager (`~/.vimpagerrc`) |

## Requirements

- `neovim`, `vim`, `git`, `curl`, `unzip`, `build-essential`, `tree-sitter-cli`
- At least one supported package backend:
    - system package manager: `apt-get` (Debian/Ubuntu), `pacman` (Arch), or `nix` (NixOS)
    - `flatpak` (sandboxed apps; `io.neovim.nvim` / `org.vim.Vim`)
    - `bin` ([marcosnils/bin](https://github.com/marcosnils/bin), generic GitHub-release binary manager)
- Target user must have `sudo` privileges for system-scope (`-im system`) dependency/config installation

## Installation

```bash
./install.sh
```

### Options

| Flag                | Description                                                                        |
|---------------------|-------------------------------------------------------------------------------------|
| `-h`                | Show help                                                                          |
| `-ci`               | Clean install — wipe existing config/cache first                                  |
| `-sp`               | Skip package installation                                                         |
| `-sc`               | Skip editor configuration installation                                            |
| `-im INSTALL_MODE`  | Where packages are installed: `system`, `user`, `auto` (default: `auto`)          |
| `-cm CONFIG_MODE`   | Where editor configs are installed: `global`, `users`, `local`, `auto` (default: `auto`) |

`INSTALL_MODE=auto` resolves to `system` when running as root (`EUID=0`), else `user`.
`CONFIG_MODE=auto` resolves to `users` when the resolved install mode is `system`, else `local`.

### Example: fresh install

```bash
./install.sh -ci
```

### Example: install without touching system packages

```bash
./install.sh -sp
```

### Example: user-local install (no root, no system packages touched)

```bash
./install.sh -im user
```

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

Startup and performance test scripts are in `tests/`:

```bash
tests/startup.sh # basic startup smoke test
tests/verbose.sh # verbose startup output
tests/traceopt.sh # startup option tracing
```

## License

[GPL-3.0](../LICENSE.md)
