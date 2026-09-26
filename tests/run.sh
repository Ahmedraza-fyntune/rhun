#!/bin/sh
# builds test binaries and compares their output with tests/data/*.expected
cd "$(dirname "$0")/.."
./build.sh test || exit 1
fail=0
check() { # name cmd...
    name=$1; shift
    if "$@" 2>&1 | cmp -s - "tests/data/$name.expected"; then
        echo "ok   $name"
    else
        echo "FAIL $name"; fail=1
    fi
}
check keymap-names-us-ru build/xkb_test tests/data/keymap-names-us-ru.txt
check keymap-gnome-us build/xkb_test tests/data/keymap-gnome-us.txt
check doc build/doc_test
check syntax build/syntax_test
check themes build/theme_test
[ -x tests/ui.sh ] && { tests/ui.sh || fail=1; }
exit $fail
