#!/bin/sh
# runs tests/scripts/*.rsc headless and compares the output with tests/data/<name>.ui.expected
cd "$(dirname "$0")/.."
fail=0
tmp=$(mktemp -d)
for s in tests/scripts/*.rsc; do
    n=$(basename "$s" .rsc)
    XDG_CONFIG_HOME=$tmp/config XDG_STATE_HOME=$tmp/state HOME=$tmp \
        timeout 20 build/rhun "$PWD" --headless 1400x860 --script "$s" > "$tmp/$n.out" 2>&1
    if [ "$1" = update ]; then
        cp "$tmp/$n.out" "tests/data/$n.ui.expected"
    fi
    if cmp -s "$tmp/$n.out" "tests/data/$n.ui.expected"; then
        echo "ok   ui/$n"
    else
        echo "FAIL ui/$n"; diff "tests/data/$n.ui.expected" "$tmp/$n.out" | head -20; fail=1
    fi
done
rm -rf "$tmp"
exit $fail
