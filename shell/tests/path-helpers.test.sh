# shellcheck shell=sh
# shellcheck source-path=SCRIPTDIR
# Usage: <shell> path-helpers.test.sh <path-helpers.sh>
# Runs under `set -u` so an unset variable in the helpers fails the run.
set -u
# shellcheck source=path-helpers.sh
. "$1"
fails=0
fail() {
    printf 'FAIL %s\n' "$1"
    fails=$((fails + 1))
}

# PATH result: name, initial PATH (UNSET to unset it), function, arg, expected PATH, rc.
t() {
    if [ "$2" = UNSET ]; then unset PATH; else PATH=$2; fi
    "$3" "$4" 2>/dev/null
    rc=$?
    got=${PATH-UNSET}
    PATH=/usr/bin:/bin
    [ "$got" = "$5" ] && [ "$rc" = "$6" ] ||
        fail "$1: got [$got] rc=$rc, want [$5] rc=$6"
}

# Warning text: name, expected stderr, command...
w() {
    name=$1 want=$2
    shift 2
    got=$("$@" 2>&1 >/dev/null)
    [ "$got" = "$want" ] || fail "$name: got [$got], want [$want]"
}

P=__shell_path_prepend A=__shell_path_append C=__shell_path_clean
t 'prepend new'         /usr/bin:/bin          $P /opt/x      /opt/x:/usr/bin:/bin    0
t 'prepend moves'       /usr/bin:/bin          $P /bin        /bin:/usr/bin           0
t 'prepend dups'        /a:/b:/a:/c            $P /a          /a:/b:/c                0
t 'prepend keeps rest'  /a::/b:/a              $P /a          /a::/b                  0
t 'prepend slash arg'   /usr/bin:/bin          $P /bin/       /bin:/usr/bin           0
t 'prepend slashes arg' /usr/bin:/bin          $P /bin///     /bin:/usr/bin           0
t 'prepend slash ent'   /usr/bin:/bin/         $P /bin        /bin:/usr/bin           0
t 'prepend root'        /usr/bin               $P /           /:/usr/bin              0
t 'prepend root slashes' /usr/bin              $P ///         /:/usr/bin              0
t 'prepend empty PATH'  ''                     $P /a          /a                      0
t 'prepend unset PATH'  UNSET                  $P /a          /a                      0
t 'prepend glob arg'    '/opt/xy:/bin'         $P '/opt/[x]*' '/opt/[x]*:/opt/xy:/bin' 0
t 'prepend glob ent'    '/opt/[x]*:/bin'       $P '/opt/xy'   '/opt/xy:/opt/[x]*:/bin' 0
t 'prepend spaces'      '/a b:/bin'            $P '/a b'      '/a b:/bin'             0
t 'prepend prefix'      /usr/bin2:/bin         $P /usr/bin    /usr/bin:/usr/bin2:/bin 0
t 'append new'          /usr/bin:/bin          $A /opt/x      /usr/bin:/bin:/opt/x    0
t 'append present'      /usr/bin:/bin          $A /usr/bin    /usr/bin:/bin           0
t 'append slash'        /usr/bin/:/bin         $A /usr/bin//  /usr/bin/:/bin          0
t 'append empty PATH'   ''                     $A /a          /a                      0
t 'append unset PATH'   UNSET                  $A /a          /a                      0
t 'reject empty'        /usr/bin               $P ''          /usr/bin                1
t 'reject relative'     /usr/bin               $P bin         /usr/bin                1
t 'reject dot'          /usr/bin               $A .           /usr/bin                1
t 'reject colon'        /usr/bin               $P /a:/b       /usr/bin                1
t 'reject colon end'    /usr/bin               $A /a:         /usr/bin                1
t 'clean noop'          /usr/bin:/bin          $C ''          /usr/bin:/bin           0
t 'clean empties'       ::/usr/bin:.:/bin:     $C ''          /usr/bin:/bin           0
t 'clean relative'      'bin:~/bin:./x:/usr/bin' $C ''        /usr/bin                0
t 'clean keeps root'    /:/usr/bin             $C ''          /:/usr/bin              0
t 'clean empty PATH'    ''                     $C ''          ''                      0
t 'clean unset PATH'    UNSET                  $C ''          ''                      0

w 'warn no args'  "profile: skipping PATH entry '': empty" $P
w 'warn colon'    "profile: skipping PATH entry '/a:/b': contains \":\"" $P /a:/b
w 'warn relative' "profile: skipping PATH entry 'bin': not an absolute path" $A bin
esc=$(printf 'b\033[31m\tc')
w 'warn escapes'  "profile: skipping PATH entry <has non-printable characters>: not an absolute path" $P "$esc"
nl='a
b'
w 'warn newline'  "profile: skipping PATH entry <has non-printable characters>: not an absolute path" $P "$nl"
PATH=':x:/usr/bin'
w 'warn clean'    "profile: skipping PATH entry '': empty
profile: skipping PATH entry 'x': not an absolute path" $C
PATH=/usr/bin:/bin

set | grep -q '^__shell_path_[a-z]*=' && fail 'leaked variables'
echo "fails=$fails"
