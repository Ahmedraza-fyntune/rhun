# UI-thread source invalidation precedes every raw keyline replacement.
.include "rhun.inc"
.data
.p2align 3
key_source_epoch: .quad 1
.bss
.p2align 3
key_source_loading: .quad 0
.text
FN config_key_source_epoch
    mov rax, [rip + key_source_epoch]
    mov rdx, [rip + key_source_loading]
    ret
FN config_key_source_begin
    mov qword ptr [rip + key_source_loading], 1
    mov rax, [rip + key_source_epoch]
    test rax, rax
    jle 2f
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jae 1f
    inc rax
    mov [rip + key_source_epoch], rax
    xor eax, eax
    ret
1:  mov qword ptr [rip + key_source_epoch], 0
2:  mov rax, -75
    ret
FN config_key_source_end
    mov qword ptr [rip + key_source_loading], 0
    ret
