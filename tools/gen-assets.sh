#!/bin/sh
# emits build/assets.s: embedded fonts, themes and syntax files
cd "$(dirname "$0")/.."
emit() { # label file
    printf '.globl %s, %s_end\n.p2align 4\n%s: .incbin "%s"\n%s_end: .byte 0\n' "$1" "$1" "$1" "$PWD/$2" "$1"
}
echo '.section .rodata'
emit font_mono assets/fonts/UbuntuSansMono-Regular.ttf
emit font_ui assets/fonts/UbuntuSans-Regular.ttf
# name table of runtime files: pairs of (name ptr, data ptr, data end)
for kind in themes syntax; do
    i=0
    for f in $(ls runtime/$kind 2>/dev/null | LC_ALL=C sort); do
        emit "${kind}_$i" "runtime/$kind/$f"
        printf '%s_%d_name: .asciz "%s"\n' "$kind" $i "$f"
        i=$((i+1))
    done
    printf '.p2align 3\n.globl %s_table, %s_count\n%s_count: .quad %d\n%s_table:\n' $kind $kind $kind $i $kind
    j=0
    while [ $j -lt $i ]; do
        printf '.quad %s_%d_name, %s_%d, %s_%d_end\n' $kind $j $kind $j $kind $j
        j=$((j+1))
    done
done
