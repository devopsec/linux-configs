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

## Requirements

- `neovim`, `vim`, `git`, `curl`, `ripgrep`, `fd`, `unzip`, `build-essential`
- A system package manager: `apt-get` (Debian/Ubuntu) or `pacman` (Arch)
- Target user must have `sudo` privileges for dependency installation

## Installation

```bash
./install.sh
```

### Options

| Flag  | Description                                      |
|-------|--------------------------------------------------|
| `-h`  | Show help                                        |
| `-ci` | Clean install — wipe existing config/cache first |
| `-sd` | Skip dependency installation                     |

### Example: fresh install

```bash
./install.sh -ci
```

### Example: install without touching system packages

```bash
./install.sh -sd
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
