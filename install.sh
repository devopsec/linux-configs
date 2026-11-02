#!/usr/bin/env bash

# root entrypoint for the linux configs installer: sources the shared library and both
# family installers, then installs the selected apps family by family. each family
# (fonts, vim, neovim) can also be run on its own via its own install.sh

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

REPO_ROOT_DIR="$(realpath -m -- "${BASH_SOURCE[0]}/..")"

# shellcheck source=installer-libs/common.sh
source "$REPO_ROOT_DIR/installer-libs/common.sh"
# shellcheck source=fonts/install.sh
source "$REPO_ROOT_DIR/fonts/install.sh"
# shellcheck source=vim/install.sh
source "$REPO_ROOT_DIR/vim/install.sh"
# shellcheck source=neovim/install.sh
source "$REPO_ROOT_DIR/neovim/install.sh"

setup_install "$@"

# registered order keeps fonts available before the editor families run
run_install "${FAMILY_ORDER[@]}"

exit 0
