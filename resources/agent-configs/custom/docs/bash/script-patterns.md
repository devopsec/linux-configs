# Bash script patterns (full examples)

Companion to `guidelines.md` (same folder); load only when you need the full header/strict-mode/cleanup templates.

## Usage Documentation

The `usage()` function for a script should be defined immediately after the header comments.
This makes the logic easier to understand at a quick glance.
Library scripts do not require defining a usage function.

Here is an example header section in an install script:

```bash
#!/usr/bin/env bash

function usage() {
    cat <<EOF
Summary:
    Configure all system software for the contract-enforcer platform.

Usage:
    ${0##*/} [-h] [-d] [-f] [-e <env>]

Arguments:
    -h          Show this usage documentation.
    -d          Turn on debugging.
    -f          Force install (overwrite any previous configurations).
                Default is to ask for each existing component.
    -e <env>    Environment to install. One of prod, or dev.
                Default environment is prod.

Examples:
    ${0##*/} -h
    ${0##*/} -f
    ${0##*/} -e prod
    ${0##*/} -d -e dev

Exit Codes:
    0           ok
    1           failure
    2           usage error
    3           not implemented

Requirements:
    Debian >= 12
    root privileges (must be run as root user)
EOF
}


```

## Strict Mode as Default

The next section sets the bash session flags and debug handling logic.  
The default is to setup the session with strict error handling.  
There are cases where this may not be desired in the script, use your best judgment.  

Here is an example handling the session setup:

```bash
# When debugging, some debuggers may need different bash flags
# Debuggers detected:   bashdb
if [[ -n "${_Dbg_set_debug:-}" ]]; then
    INSIDE_DEBUGGER=1
    set -Euo pipefail
else
    INSIDE_DEBUGGER=0
    set -Eeuo pipefail
fi
shopt -s inherit_errexit nullglob

#
# Typically CLI option / argument parsing happens here
#

# Now we can determine if we are in debugging mode or not
export DEBUG="${DEBUG:-0}"
(( DEBUG == 1 )) && set -x

# Define paths in the repo we will utilize
REPO_ROOT_DIR=$(realpath -m "${BASH_SOURCE[0]}/../../..")
REPO_PKGS_DIR="$REPO_ROOT_DIR/packages"

# Import debugging utilities and Setup the traceback handler
# shellcheck source=../packages/common/signals.sh
source "$REPO_ROOT_DIR/packages/common/signals.sh"
# shellcheck source=../packages/common/debugging.sh
source "$REPO_PKGS_DIR/common/debugging.sh"
if (( INSIDE_DEBUGGER == 0 )); then
    trap_push 'backtrace "$LINENO"' ERR
fi
```
## Temporary Resource Cleanup

Temporary resources should always be cleaned up, even during unexpected failures.

Trapping signals is the preferred method to cleanup temporary resources.  
The typical pattern is to handle cleanup using the `EXIT` signal.

For example to cleanup a temporary directory:

```bash
function install_app1() {
    local tmpdir
    
    trap "rm -rf '$tmpdir' || true;" EXIT

    tmpdir=$(mktemp -d -t app1.XXX)
    (
        cd "$tmpdir"
        curl -sL 'https://example.com/app1-rel.tar.gz' | tar -xzf -
        make install
    )
} 

if ! command -v app1 &>/dev/null; then
    echo 'failed installing app1' >&2
    exit 1
fi

echo 'install was successful'
exit 0
```

If an unhandled error occurs, the temporary directory will be cleaned up before exiting.  
Note that the failsafe `|| true` is required to avoid duplicate signal handling.

Usage of function / variable references is allowed, but not preferred.  
You must be careful to avoid those references going out of scope.  
This can be harder to maintain over time as the conditions your logic is used in become more complex.

Correct usage:

```bash
function cleanup_cache() {
    rm -rf /var/cache/app1/
}
trap 'cleanup_cache' EXIT

app1-server --cache=/var/cache/app1/
```

**Incorrect** usage:

```bash
#!/usr/bin/env bash

set -Eeuo pipefail
echo 'installing app2'

install_app2() {
  local tnow_posix=$(date '+%s')
  BACKUP_DIR="/var/backups/$tnow_posix"
  trap 'rm -rf /opt/app2/ && mv -f "$BACKUP_DIR" /opt/app2 || true;' ERR

  # developer forgot to check for existing 

  cp -af /opt/app2/ "$BACKUP_DIR"
}

install_app2
echo 'app2 installed'
```

Some common use cases: 

- build directories
- tempfiles used
- lock files were used
- background jobs exist

