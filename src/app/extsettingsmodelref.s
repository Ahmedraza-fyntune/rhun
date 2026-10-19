# Model references keep source and slot values alive independently of a catalog plan.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.bss
.p2align 3
.globl esv_model_retired_head, esv_model_retired_tail, esv_model_retired_count
esv_model_retired_head: .quad 0
esv_model_retired_tail: .quad 0
esv_model_retired_count: .quad 0
.text
FN ext_settings_model_retain
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + ELM_refs], 0
    jle 1f
    cmp qword ptr [rdi + ELM_ready], 1
    jne 1f
    mov rax, 0x7fffffffffffffff
    cmp [rdi + ELM_refs], rax
    jae 2f
    inc qword ptr [rdi + ELM_refs]
    xor eax, eax
    ret
1:  mov rax, -22
    ret
2:  mov rax, -75
    ret
# Release only appends a preowned node; model GC walks references separately.
FN ext_settings_model_release
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + ELM_refs], 0
    jle 4f
    dec qword ptr [rdi + ELM_refs]
    jnz 3f
    mov qword ptr [rdi + ELM_next], 0
    mov rax, [rip + esv_model_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + ELM_next], rdi
    jmp 2f
1:  mov [rip + esv_model_retired_head], rdi
2:  mov [rip + esv_model_retired_tail], rdi
    inc qword ptr [rip + esv_model_retired_count]
3:  xor eax, eax
    ret
4:  mov rax, -22
    ret
FN ext_settings_model_pending
    mov rax, [rip + esv_model_retired_count]
    ret
