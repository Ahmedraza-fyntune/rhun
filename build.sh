#!/bin/sh
# usage: ./build.sh [release]
set -e
cd "$(dirname "$0")"
mkdir -p build/obj
ASFLAGS="--64 -I src -I build"
[ "$1" = release ] || ASFLAGS="$ASFLAGS -g"
[ -x tools/gen-assets.sh ] && tools/gen-assets.sh > build/assets.s.new && { cmp -s build/assets.s.new build/assets.s || mv build/assets.s.new build/assets.s; }
objs=""
for s in $(find src -name '*.s' | sort) $( [ -f build/assets.s ] && echo build/assets.s ); do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    as $ASFLAGS -o "$o" "$s"
    objs="$objs $o"
done
LDFLAGS="-static -nostdlib --no-dynamic-linker -z noexecstack"
[ "$1" = release ] && LDFLAGS="$LDFLAGS -s"
ld $LDFLAGS -o build/rhun $objs
