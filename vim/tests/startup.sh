#!/usr/bin/env bash
#
# No-UI headless startup smoke test for the vim family (vim).
# Loads the classic vim config headlessly, captures output, and asserts both a zero
# exit code and the absence of known error-pattern lines. Runs with no neovim present.

set -uo pipefail

function usage() {
cat <<EOF
Usage:          $0
EOF
}

if (( $# > 0 )); then
    usage
    exit 1
fi

# known error signatures from real bug reports (vim errors, module load
# failures, nil-value Lua crashes) -- a clean config load must contain none
declare -gr ERROR_PATTERN='E[0-9]+:|^Error |module .* not found|attempt to call field'

declare -gi OVERALL_RESULT=0

# runs a headless command, captures combined output, and asserts exit code 0
# plus no ERROR_PATTERN match; prints PASS/FAIL and updates OVERALL_RESULT
function assert_clean_run() {
    local name="$1"
    shift
    local output rc

    echo '==============================='
    echo "Testing $name"
    echo '==============================='

    output="$("$@" 2>&1)"
    rc=$?
    echo "$output"
    echo ''

    if (( rc != 0 )); then
        echo "FAIL: $name exited with status $rc"
        OVERALL_RESULT=1
        return 1
    fi

    if grep -qE "$ERROR_PATTERN" <<< "$output"; then
        echo "FAIL: $name produced an error-pattern match in its output"
        OVERALL_RESULT=1
        return 1
    fi

    echo "PASS: $name"
    return 0
}

function test_vim() {
    assert_clean_run vim vim --not-a-term -es --startuptime /dev/stdout -c 'qall!'
}

test_vim

exit "$OVERALL_RESULT"
