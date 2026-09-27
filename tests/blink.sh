#!/bin/sh
# The caret blinks: with nothing else to draw, rhun draws a frame each time it turns on or off
# (every 530 ms after the last key)
set -u
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT HUP INT TERM
mkdir -p "$w/proj"
# run NAME LINES...: rhun headless with the script LINES in an empty folder, with the agents panel
# (it refreshes every second) closed; output in $w/NAME
run() {
    n=$1
    shift
    printf '%s\n' 'cmd toggle_agents' 'cmd new_file' "$@" quit > "$w/$n.rsc"
    HOME="$w" XDG_CONFIG_HOME="$w/c" XDG_STATE_HOME="$w/s" \
        build/rhun "$w/proj" --headless 800x600 --script "$w/$n.rsc" > "$w/$n" 2>&1
}
# frames N: the Nth count print-frames printed
frames() { sed -n "s/^frames=//p" "$w/$n" | sed -n "${1}p"; }
between() { [ "${1:-0}" -ge "$2" ] && [ "${1:-0}" -le "$3" ]; }
check() { # WHAT CMD...
    what=$1
    shift
    if "$@"; then echo "ok   blink/$n"; else echo "FAIL blink/$n: $what"; sed 's/^/    | /' "$w/$n"; fail=1; fi
}
fail=0
# on for 530 ms, off at 530, on at 1060, off at 1590
run toggles 'type x' print-frames 'wait 1800' print-frames
f=$(frames 2)
check "3 frames in 1.8 s, not ${f:-none}" between "$f" 3 4
exit $fail
