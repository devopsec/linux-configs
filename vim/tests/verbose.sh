#!/usr/bin/env bash

function usage() {
cat <<EOF
Usage:          $0
EOF
}

if (( $# > 0 )); then
    usage
    exit 1
fi

echo '==============================='
echo 'Testing vim'
echo '==============================='

vim -V -c 'qall!'
RES=$?
echo ''
exit "$RES"
