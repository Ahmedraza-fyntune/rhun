#!/bin/sh
# The session remembers the open files when rhun quits, also those it asked about before quitting
# (each answer closes that file), and a quit that was cancelled leaves the next one to save it.
set -u
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT HUP INT TERM
# run NAME LINES...: rhun headless in $w/p with the script LINES; output in $w/NAME
run() {
    n=$1
    shift
    printf '%s\n' "$@" > "$w/$n.rsc"
    HOME="$w" XDG_CONFIG_HOME="$w/c" XDG_STATE_HOME="$w/s" \
        build/rhun "$w/p" --headless 800x600 --script "$w/$n.rsc" > "$w/$n" 2>&1
}
fresh() { rm -rf "$w/p" "$w/s" "$w/c"; mkdir -p "$w/p"; for f in a b c; do echo "$f" > "$w/p/$f.txt"; done; }
check() { # NAME EXPECTED: the state the next start brings back
    run "$1-after" print-state quit
    got=$(sed -n 's/^\(tabs=[0-9]* active=[^ ]*\).*/\1/p' "$w/$1-after")
    if [ "$got" = "$2" ]; then echo "ok   session/$1"; else echo "FAIL session/$1: '$got', not '$2'"; fail=1; fi
}
fail=0

# quitting with two changed files: Save for the first, Don't Save (by its button) for the second
fresh
run asked "open $w/p/a.txt" 'type x' "open $w/p/b.txt" 'type y' "open $w/p/c.txt" \
    'cmd quit' 'key Return' 'click 466 295'
check asked "tabs=3 active=c.txt"

# Cancel: no quit, and the next quit saves the session as it is then
fresh
run cancelled "open $w/p/a.txt" 'type x' 'cmd quit' 'key Escape' "open $w/p/b.txt" "open $w/p/c.txt" quit
check cancelled "tabs=3 active=c.txt"
exit $fail
