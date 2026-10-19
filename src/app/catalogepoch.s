# Nonreused catalog epochs. Only the coordinator publishes catalogs after preflight.
.include "rhun.inc"
.text
# mask: grammar1, theme2, commands4. No mutation, allocation, callback or IO.
FN catalog_epochs_check
    cmp rdi, 7
    ja 8f
    test dil, 1
    jz 1f
    cmp qword ptr [rip + syntax_catalog_epoch], -1
    je 9f
1:  test dil, 2
    jz 2f
    cmp qword ptr [rip + theme_catalog_epoch], -1
    je 9f
2:  test dil, 4
    jz 3f
    cmp qword ptr [rip + command_catalog_epoch], -1
    je 9f
3:  xor eax, eax
    ret
8:  mov rax, -22
    ret
9:  mov rax, -75
    ret

# catalog_epochs_advance(mask) ->0/-errno, all epochs unchanged on failure.
# Called in the same nonyielding publication as the actual registry pointer swaps.
FN catalog_epochs_advance
    PROLOGUE
    mov rbx, rdi
    call catalog_epochs_check
    test rax, rax
    js 9f
    test bl, 1
    jz 1f
    inc qword ptr [rip + syntax_catalog_epoch]
1:  test bl, 2
    jz 2f
    inc qword ptr [rip + theme_catalog_epoch]
2:  test bl, 4
    jz 3f
    inc qword ptr [rip + command_catalog_epoch]
3:  test rbx, rbx
    jz 4f
    call palette_close_catalogs_pure
4:  xor eax, eax
9:  EPILOGUE
