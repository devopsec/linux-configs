#!/usr/bin/env bash

function usage() {
cat <<EOF
Usage:          $0 [app]
  all apps:     $0
  one app:      $0 nvimgit
EOF
}

if (( $# > 1 )); then
    usage
    exit 1
fi

if (( $# == 1 )); then
    echo '==============================='
    echo "Testing $1"
    echo '==============================='

    if [[ "$1" == 'vim' ]]; then
        vim -V -c 'qall!'
        RES=$?
    else
        NVIM_APPNAME="$1" nvim --headless -V -c 'qall!'
        RES=$?
    fi
    echo ''
    exit "$RES"
fi

RES=0
for nvim_app in nvim nvimgit nvimpager; do
    echo '==============================='
    echo "Testing $nvim_app"
    echo '==============================='

    NVIM_APPNAME="$nvim_app" nvim --headless -V -c 'qall!'
    RES+=$?
    echo ''
done
vim -V -c 'qall!'
RES+=$?
echo ''
exit "$RES"
