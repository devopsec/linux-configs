# shellcheck shell=bash
#
# Shared installer entrypoint. The implementation lives in focused modules;
# this file preserves one stable source path for the root and family installers.
#

if [[ -n "${LINUX_CONFIGS_COMMON_LOADED:-}" ]]; then
    return 0
fi
declare -g LINUX_CONFIGS_COMMON_LOADED=1

INSTALLER_LIB_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
SCRIPT_DIR="$(dirname "$INSTALLER_LIB_DIR")"

# shellcheck source=installer-libs/log.sh
source "$INSTALLER_LIB_DIR/log.sh"
# shellcheck source=installer-libs/registry.sh
source "$INSTALLER_LIB_DIR/registry.sh"
# shellcheck source=installer-libs/scope.sh
source "$INSTALLER_LIB_DIR/scope.sh"
# shellcheck source=installer-libs/cli.sh
source "$INSTALLER_LIB_DIR/cli.sh"
# shellcheck source=installer-libs/fsops.sh
source "$INSTALLER_LIB_DIR/fsops.sh"
# shellcheck source=installer-libs/pkg/system.sh
source "$INSTALLER_LIB_DIR/pkg/system.sh"
# shellcheck source=installer-libs/pkg/flatpak.sh
source "$INSTALLER_LIB_DIR/pkg/flatpak.sh"
# shellcheck source=installer-libs/pkg/bin.sh
source "$INSTALLER_LIB_DIR/pkg/bin.sh"
# shellcheck source=installer-libs/docs.sh
source "$INSTALLER_LIB_DIR/docs.sh"
# shellcheck source=installer-libs/pkg/app.sh
source "$INSTALLER_LIB_DIR/pkg/app.sh"
# shellcheck source=installer-libs/run.sh
source "$INSTALLER_LIB_DIR/run.sh"