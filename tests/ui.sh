#!/bin/sh
# runs tests/scripts/*.rsc headless and compares the output with tests/data/<name>.ui.expected
cd "$(dirname "$0")/.."
fail=0
tmp=$(mktemp -d)
# agent session fixtures under the fake HOME
slug=$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$tmp/.claude/projects/$slug" "$tmp/.codex/sessions/2026/09/26"
sed "s|@PROJECT@|$PWD|g" tests/data/agents/claude.jsonl > "$tmp/.claude/projects/$slug/s1.jsonl"
sed "s|@PROJECT@|$PWD|g" tests/data/agents/codex.jsonl > "$tmp/.codex/sessions/2026/09/26/rollout-c1.jsonl"
cp tests/data/agents/other.jsonl "$tmp/.codex/sessions/2026/09/26/rollout-c2.jsonl"
touch -d '2026-09-26 06:00' "$tmp/.claude/projects/$slug/s1.jsonl"
touch -d '2026-09-26 07:00' "$tmp/.codex/sessions/2026/09/26/rollout-c1.jsonl"
for s in tests/scripts/*.rsc; do
    n=$(basename "$s" .rsc)
    # tests/data/NAME.home: a HOME of its own; @HOME@ in the script names it
    home=$tmp
    if [ -d "tests/data/$n.home" ]; then
        home=$tmp/home-$n
        cp -r "tests/data/$n.home" "$home"
    fi
    sed "s|@HOME@|$home|g" "$s" > "$tmp/$n.rsc"
    XDG_CONFIG_HOME=$tmp/config-$n XDG_STATE_HOME=$tmp/state-$n HOME=$home XCOMPOSEFILE=$PWD/tests/data/compose.txt XCURSOR_PATH=tests/data/icons XCURSOR_THEME=child SHELL=/bin/sh \
        timeout 20 build/rhun "$PWD" --headless 1400x860 --script "$tmp/$n.rsc" > "$tmp/$n.out" 2>&1
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
