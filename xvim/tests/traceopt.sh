#!/usr/bin/env bash

function usage() {
cat <<EOF
Usage:          $0 <app> <option>
EOF
}

if (( $# != 2 )); then
    usage
    exit 1
fi

if [[ "$1" == 'vim' ]]; then
    echo 'vim is currently unsupported'
    exit 1
fi

echo "--- Test session started ---"
XDG_CONFIG_HOME="$(pwd)" \
NVIM_APPNAME="$1" \
NVIM_TRACEOPT="$2" \
nvim --headless \
    --cmd 'lua require("setup.debugging")' \
    -c 'qall!'
echo "--- Test session ended ---"
