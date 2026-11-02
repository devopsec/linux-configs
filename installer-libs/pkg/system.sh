# shellcheck shell=bash
# System package metadata and the small dependency-install API used by families.

declare -gA PKG_APT=()
declare -gA PKG_PACMAN=()
declare -gA PKG_NIX=()
declare -g SYS_PKG_MANAGER=""

function pkg_define() {
    local package_id="$1" mapping
    shift
    [[ -n "$package_id" ]] || { log_error "pkg_define requires a package id"; return 2; }

    for mapping in "$@"; do
        case "$mapping" in
        apt=*) PKG_APT["$package_id"]="${mapping#apt=}" ;;
        pacman=*) PKG_PACMAN["$package_id"]="${mapping#pacman=}" ;;
        nix=*) PKG_NIX["$package_id"]="${mapping#nix=}" ;;
        *) log_error "Invalid package mapping '$mapping' for '$package_id'"; return 2 ;;
        esac
    done
}

pkg_define git apt=git pacman=git nix=git
pkg_define curl apt=curl pacman=curl nix=curl
pkg_define unzip apt=unzip pacman=unzip nix=unzip
pkg_define build-tools apt=build-essential pacman=base-devel nix=stdenv
pkg_define man-db apt=man-db pacman=man-db nix=man-db
pkg_define bash-completion apt=bash-completion pacman=bash-completion nix=bash-completion

function sys_pkg_manager() {
    if [[ -z "$SYS_PKG_MANAGER" ]]; then
        if command -v apt-get &>/dev/null; then SYS_PKG_MANAGER="apt"
        elif command -v pacman &>/dev/null; then SYS_PKG_MANAGER="pacman"
        elif command -v nix &>/dev/null; then SYS_PKG_MANAGER="nix"
        else SYS_PKG_MANAGER="none"
        fi
    fi
    printf '%s\n' "$SYS_PKG_MANAGER"
}

function sys_pkg_name() {
    local package_id="$1" manager="${2:-$(sys_pkg_manager)}"
    case "$manager" in
    apt) printf '%s\n' "${PKG_APT[$package_id]:-}" ;;
    pacman) printf '%s\n' "${PKG_PACMAN[$package_id]:-}" ;;
    nix) printf '%s\n' "${PKG_NIX[$package_id]:-}" ;;
    *) return 1 ;;
    esac
}

function sys_pkg_installed() {
    local package_id="$1" manager package_name
    manager="$(sys_pkg_manager)"
    package_name="$(sys_pkg_name "$package_id" "$manager")"
    [[ -n "$package_name" ]] || return 1

    case "$manager" in
    apt)
        command -v dpkg-query &>/dev/null || return 1
        dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q 'ok installed'
        ;;
    pacman)
        pacman -Q "$package_name" &>/dev/null
        ;;
    nix)
        nix profile list 2>/dev/null | grep -Fq "$package_name"
        ;;
    *) return 1 ;;
    esac
}

function sys_pkg_available() {
    local package_id="$1" manager package_name
    manager="$(sys_pkg_manager)"
    package_name="$(sys_pkg_name "$package_id" "$manager")"
    [[ -n "$package_name" ]] || return 1

    case "$manager" in
    apt)
        command -v apt-cache &>/dev/null && apt-cache show "$package_name" &>/dev/null
        ;;
    pacman)
        pacman -Si "$package_name" &>/dev/null
        ;;
    nix)
        nix eval --raw "nixpkgs#${package_name}.pname" &>/dev/null
        ;;
    *) return 1 ;;
    esac
}

# shellcheck disable=SC2154
function sys_pkg_install() {
    local package_id="$1" version="${2:-latest}" manager package_name
    manager="$(sys_pkg_manager)"
    package_name="$(sys_pkg_name "$package_id" "$manager")"
    [[ -n "$package_name" ]] || return 1

    case "$manager" in
    apt)
        [[ "$version" == latest ]] || package_name="$package_name=$version"
        run_priv apt-get install -y "$package_name"
        ;;
    pacman)
        [[ "$version" == latest ]] || log_notice "pacman does not support pinned versions; installing latest '$package_name'"
        run_priv pacman -S --noconfirm --needed "$package_name"
        ;;
    nix)
        [[ "$version" == latest ]] || log_notice "nix package mappings do not support pinned versions; installing latest '$package_name'"
        if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then
            run_priv nix profile install "nixpkgs.$package_name"
        else
            nix profile install "nixpkgs#$package_name"
        fi
        ;;
    *) return 1 ;;
    esac
}

function sys_pkg_remove() {
    local package_id="$1" manager package_name
    manager="$(sys_pkg_manager)"
    package_name="$(sys_pkg_name "$package_id" "$manager")"
    [[ -n "$package_name" ]] || return 1

    case "$manager" in
    apt) run_priv apt-get remove -y "$package_name" ;;
    pacman) run_priv pacman -Rns --noconfirm "$package_name" ;;
    nix) log_notice "Removing '$package_name' from a Nix profile is not automated"; return 1 ;;
    *) return 1 ;;
    esac
}

function sys_pkgs_ensure() {
    local package_id package_name manager
    local -a to_install=() nix_args=()
    local -A package_seen=()
    manager="$(sys_pkg_manager)"

    if [[ "$manager" == none ]]; then
        log_notice "No supported system package manager found; cannot install declared requirements"
        return 0
    fi

    for package_id in "$@"; do
        package_name="$(sys_pkg_name "$package_id" "$manager")"
        if [[ -z "$package_name" ]]; then
            log_notice "No '$manager' package mapping for requirement '$package_id'; skipping"
            continue
        fi
        sys_pkg_installed "$package_id" && continue
        if sys_pkg_available "$package_id"; then
            if [[ -z "${package_seen[$package_name]:-}" ]]; then
                package_seen["$package_name"]=1
                to_install+=("$package_name")
            fi
        else
            log_notice "Package '$package_name' for requirement '$package_id' is unavailable in '$manager'"
        fi
    done

    (( ${#to_install[@]} > 0 )) || return 0
    if ! can_use_sudo && [[ "$manager" != nix ]]; then
        log_notice "Missing system packages (not installed without sudo): ${to_install[*]}"
        return 0
    fi

    log_info "Installing declared system requirements via $manager: ${to_install[*]}"
    case "$manager" in
    apt)
        run_priv apt-get update -y
        run_priv apt-get install -y "${to_install[@]}"
        ;;
    pacman) run_priv pacman -S --noconfirm --needed "${to_install[@]}" ;;
    nix)
        if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then
            for package_name in "${to_install[@]}"; do nix_args+=("nixpkgs.$package_name"); done
            run_priv nix-env -iA "${nix_args[@]}"
        else
            for package_name in "${to_install[@]}"; do nix_args+=("nixpkgs#$package_name"); done
            nix profile install "${nix_args[@]}"
        fi
        ;;
    esac
}
