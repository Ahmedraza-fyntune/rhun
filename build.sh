#!/bin/sh
# usage: ./build.sh [release|test]
set -e
cd "$(dirname "$0")"
mkdir -p build/obj
ASFLAGS="--64 -I src -I build"
[ "$1" = release ] || ASFLAGS="$ASFLAGS -g"
tools/gen-assets.sh > build/assets.s.new
cmp -s build/assets.s.new build/assets.s || mv build/assets.s.new build/assets.s
objs=""
for s in $(find src -name '*.s' | sort) build/assets.s; do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    if [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ src/rhun.inc -nt "$o" ]; then
        as $ASFLAGS -o "$o" "$s"
    fi
    objs="$objs $o"
done
LDFLAGS="-static -nostdlib --no-dynamic-linker -z noexecstack"
[ "$1" = release ] && LDFLAGS="$LDFLAGS -s"
ld $LDFLAGS -o build/rhun $objs
if [ "$1" = test ]; then
    lib=$(echo $objs | tr ' ' '\n' | grep -v 'src_main.o')
    for t in tests/*.s; do
        n=$(basename "$t" .s)
        as $ASFLAGS -o "build/obj/test_$n.o" "$t"
        ld $LDFLAGS -o "build/$n" "build/obj/test_$n.o" $lib
    done
fi
