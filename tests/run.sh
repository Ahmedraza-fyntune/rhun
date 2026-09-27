#!/bin/sh
# builds test binaries and compares their output with tests/data/*.expected
cd "$(dirname "$0")/.."
./build.sh test || exit 1
fail=0
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM
check() { # name cmd...
    name=$1; shift
    if "$@" > "$tmp" 2>&1 && cmp -s "$tmp" "tests/data/$name.expected"; then
        echo "ok   $name"
    else
        echo "FAIL $name"; fail=1
    fi
}
check keymap-names-us-ru build/xkb_test tests/data/keymap-names-us-ru.txt
check keymap-gnome-us build/xkb_test tests/data/keymap-gnome-us.txt
check keymap-pl-intl build/xkb_test tests/data/keymap-pl-intl.txt
check doc build/doc_test
check syntax build/syntax_test
check themes build/theme_test
check term build/term_test
check diff build/diff_test
check images build/image_test $(ls tests/data/images/* | LC_ALL=C sort)
check cpu build/cpu_test
check cols build/cols_test
check strfind build/str_test tests/data/strfind.txt
if [ "$(build/rhun --version)" = "rhun $(cat VERSION)" ]; then echo "ok   version"; else echo "FAIL version"; fail=1; fi
sh tests/files.sh || fail=1
if [ "$(uname -s)" = Darwin ] || command -v strace >/dev/null; then
    status=0
    sh tests/file-faults.sh || status=$?
    [ "$status" = 0 ] || [ "$status" = 77 ] || fail=1
fi
[ -x tests/ui.sh ] && { tests/ui.sh || fail=1; }
exit $fail
