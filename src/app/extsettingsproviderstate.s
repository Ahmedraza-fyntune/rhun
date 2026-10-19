# Provider action freshness is independent from settings model generation.
.include "rhun.inc"
.bss
.p2align 3
.globl esv_provider_epoch
esv_provider_epoch: .quad 0
.text
FN ext_settings_provider_epoch
    mov rax, [rip + esv_provider_epoch]
    ret
# Called only for an accepted effective change; callers preflight before enqueue.
FN ext_settings_provider_changed
    mov rax, [rip + esv_provider_epoch]
    test rax, rax
    jle 2f
    mov rdx, 0x7fffffffffffffff
    cmp rax, rdx
    jae 1f
    inc rax
    mov [rip + esv_provider_epoch], rax
    xor eax, eax
    ret
1:  mov qword ptr [rip + esv_provider_epoch], 0
2:  mov rax, -75
    ret
