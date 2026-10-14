#!/usr/bin/env bash

# root entrypoint for the linux configs installer: sources the shared library and both
# family installers, then installs the selected apps family by family. each family
# (vim, neovim) can also be run on its own via its own install.sh

set -euo pipefail
shopt -s inherit_errexit nullglob

ROOT_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"

source "$ROOT_INSTALL_DIR/installer-libs/common.sh"
source "$ROOT_INSTALL_DIR/vim/install.sh"
source "$ROOT_INSTALL_DIR/neovim/install.sh"

setup_install "$@"

# vim before neovim: plugin sync order matches the original installer
run_install vim neovim

exit 0
