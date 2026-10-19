# Settings service epochs. Publication is coordinated with catalog visibility.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.bss
.p2align 3
.globl esv_service_queue, esv_cfg_context, esv_registry_epoch, esv_model_epoch, esv_live_model
esv_service_queue: .quad 0
esv_cfg_context: .quad 0
esv_registry_epoch: .quad 0
esv_model_epoch: .quad 0
esv_live_model: .quad 0
.text
# Once-only service initialization. Queue is borrowed until all users/GC drain.
FN ext_settings_model_context_init
    test rdi, rdi
    jz 2f
    test rsi, rsi
    jle 2f
    cmp qword ptr [rdi + EQ_epoch], 0
    jle 2f
    cmp qword ptr [rip + esv_service_queue], 0
    jne 1f
    mov [rip + esv_service_queue], rdi
    mov [rip + esv_cfg_context], rsi
    mov qword ptr [rip + esv_registry_epoch], 1
    mov qword ptr [rip + esv_model_epoch], 1
    mov qword ptr [rip + esv_provider_epoch], 1
    xor eax, eax
    ret
1:  mov rax, -114
    ret
2:  mov rax, -22
    ret
FN ext_settings_registry_epoch
    mov rax, [rip + esv_registry_epoch]
    ret
FN ext_settings_model_epoch
    mov rax, [rip + esv_model_epoch]
    ret
FN ext_settings_dirty_epoch
    mov rax, [rip + esv_service_queue]
    test rax, rax
    jz 1f
    mov rax, [rax + EQ_epoch]
1:  ret
# Called before independent visibility/schema changes. Zero blocks preparation.
FN ext_settings_registry_changed
    mov rax, [rip + esv_registry_epoch]
    test rax, rax
    jle 2f
    mov rdx, 0x7fffffffffffffff
    cmp rax, rdx
    jae 1f
    inc rax
    mov [rip + esv_registry_epoch], rax
    xor eax, eax
    ret
1:  mov qword ptr [rip + esv_registry_epoch], 0
2:  mov rax, -75
    ret
