.include "rhun.inc"
.include "app/extsettingsservice.inc"
.globl svt_poison_fail, svt_fail_alloc, svt_alloc_count, svt_fail_context, svt_poison, svt_refuse_free
.section .rodata
svt_ok: .ascii "ok settings domain constructor and retained retirement\n"
.equ SVT_OKLEN, 55
.data
.ifdef WINDOWS
svt_path: .asciz "C:/settings.ini"
.equ SVT_PATHLEN, 15
.else
svt_path: .asciz "/tmp/settings.ini"
.equ SVT_PATHLEN, 17
.endif
svt_input: .quad svt_path, SVT_PATHLEN, 37, 11, 29
svt_relative: .asciz "settings.ini"
.bss
.p2align 3
svt_stage: .quad 0
svt_fail_alloc: .quad 0
svt_alloc_count: .quad 0
svt_fail_context: .quad 0
svt_poison: .quad 0
svt_refuse_free: .quad 0
svt_svc: .quad 0
svt_model: .quad 0
svt_baseline: .quad 0
.text
svt_fail:
    mov rdi, [rip + svt_stage]
    call sys_exit
svt_poison_fail:
    mov edi, 190
    call sys_exit
svt_clean:
    PROLOGUE
    mov r12d, 8
1:  mov edi, 1
    call ext_settings_service_gc
    test rdx, rdx
    js svt_fail
    cmp rax, 1
    ja svt_fail
    dec r12
    jnz 1b
    call ext_settings_service_pending
    test rax, rax
    jnz svt_fail
    call ext_settings_memory_total
    test rax, rax
    jnz svt_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + svt_baseline], rax
    jne svt_fail
    EPILOGUE
svt_globals_clear:
    cmp qword ptr [rip + settings_service_current], 0
    jne svt_fail
    cmp qword ptr [rip + esv_service_queue], 0
    jne svt_fail
    cmp qword ptr [rip + esv_cfg_context], 0
    jne svt_fail
    ret
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + svt_baseline], rax
    mov qword ptr [rip + svt_stage], 170
    xor edi, edi
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    lea rdi, [rip + svt_input]
    mov qword ptr [rdi + SVI_length], 0
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    mov qword ptr [rip + svt_input + SVI_length], SVT_PATHLEN
    call svt_globals_clear
    call svt_clean
    # Count bounds and embedded NUL fail before any allocation or global mutation.
    mov qword ptr [rip + svt_input + SVI_length], 4096
    mov qword ptr [rip + svt_input + SVI_path], 1
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    lea rax, [rip + svt_path]
    mov [rip + svt_input + SVI_path], rax
    mov qword ptr [rip + svt_input + SVI_length], SVT_PATHLEN
    movzx r13d, byte ptr [rip + svt_path + 2]
    mov byte ptr [rip + svt_path + 2], 0
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    mov [rip + svt_path + 2], r13b
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    mov qword ptr [rip + svt_input + SVI_context], 0
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    mov qword ptr [rip + svt_input + SVI_context], 37
    call svt_globals_clear
    call svt_clean
    # Owned copied-path validation refusal keeps its partial constructor reachable.
    lea rax, [rip + svt_relative]
    mov [rip + svt_input + SVI_path], rax
    mov qword ptr [rip + svt_input + SVI_length], 12
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -22
    jne svt_fail
    call svt_globals_clear
    call svt_clean
    lea rax, [rip + svt_path]
    mov [rip + svt_input + SVI_path], rax
    mov qword ptr [rip + svt_input + SVI_length], SVT_PATHLEN
    # Each allocation refusal, then context publication refusal after all3 allocations.
    mov r12d, 1
.Lsvt_fault:
    mov rax, r12
    add rax, 170
    mov [rip + svt_stage], rax
    mov [rip + svt_fail_alloc], r12
    mov qword ptr [rip + svt_alloc_count], 0
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -12
    jne svt_fail
    call svt_globals_clear
    mov qword ptr [rip + svt_fail_alloc], 0
    call svt_clean
    inc r12
    cmp r12, 4
    jb .Lsvt_fault
    mov qword ptr [rip + svt_stage], 174
    mov qword ptr [rip + svt_fail_context], 1
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -75
    jne svt_fail
    call svt_globals_clear
    mov qword ptr [rip + svt_fail_context], 0
    call svt_clean
    # Real constructor, copied path, exact queue/context, final-ref protection.
    mov qword ptr [rip + svt_stage], 175
    lea rdi, [rip + svt_input]
    call ext_settings_service_create
    test rax, rax
    jz svt_fail
    test rdx, rdx
    jnz svt_fail
    mov rbx, rax
    mov [rip + svt_svc], rax
    cmp [rip + settings_service_current], rax
    jne svt_fail
    cmp qword ptr [rax + SV_refs], 1
    jne svt_fail
    cmp qword ptr [rax + SV_state], SV_LIVE
    jne svt_fail
    mov rdi, [rax + SV_path]
    lea rsi, [rip + svt_path]
    cmp rdi, rsi
    je svt_fail
    mov rdx, SVT_PATHLEN + 1
    call memeq
    test eax, eax
    jz svt_fail
    mov rax, [rbx + SV_queue]
    cmp [rip + esv_service_queue], rax
    jne svt_fail
    cmp qword ptr [rip + esv_cfg_context], 37
    jne svt_fail
    mov edi, 1 # Current domain rejection precedes proposed input dereference.
    call ext_settings_service_create
    test rax, rax
    jnz svt_fail
    cmp rdx, -114
    jne svt_fail
    mov rdi, rbx
    call ext_settings_service_retain
    test rax, rax
    jnz svt_fail
    mov rdi, rbx
    call ext_settings_service_release
    test rax, rax
    jnz svt_fail
    cmp rcx, 1
    jne svt_fail
    mov qword ptr [rip + svt_stage], 176
    mov rdi, rbx
    call ext_settings_service_release
    cmp rax, -16
    jne svt_fail
    test rcx, rcx
    jnz svt_fail
    cmp qword ptr [rbx + SV_refs], 1
    jne svt_fail
    mov rdi, rbx
    call ext_settings_service_detach_check
    cmp rax, -16
    jne svt_fail
    mov qword ptr [rbx + SV_state], SV_SHUTTING
    mov qword ptr [rbx + SV_job], 1
    mov rdi, rbx
    call ext_settings_service_detach_check
    cmp rax, -16
    jne svt_fail
    mov qword ptr [rbx + SV_job], 0
    # Independently allocated empty ready model: exact reference-transfer proof only.
    mov edi, ELM_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz svt_fail
    mov [rip + svt_model], rax
    mov qword ptr [rax + ELM_refs], 1
    mov qword ptr [rax + ELM_ready], 1
    mov [rip + esv_live_model], rax
    mov qword ptr [rip + svt_stage], 177
    mov qword ptr [rip + svt_poison], 1
    mov rdi, rbx
    call ext_settings_service_detach_check
    test rax, rax
    jnz svt_fail
    mov rdi, rbx
    call ext_settings_service_detach_publish
    mov qword ptr [rip + svt_poison], 0
    call svt_globals_clear
    cmp qword ptr [rip + esv_live_model], 0
    jne svt_fail
    cmp qword ptr [rip + esv_registry_epoch], 0
    jne svt_fail
    cmp qword ptr [rip + esv_model_epoch], 0
    jne svt_fail
    cmp qword ptr [rip + esv_provider_epoch], 0
    jne svt_fail
    mov rax, [rip + svt_model]
    cmp [rbx + SV_detached_model], rax
    jne svt_fail
    cmp qword ptr [rax + ELM_refs], 1
    jne svt_fail
    mov rdi, rbx
    call ext_settings_service_release
    test rax, rax
    jnz svt_fail
    cmp rcx, 1
    jne svt_fail
    # Unit1 transfers exactlyone modelref; it does not free the supplier inline.
    mov edi, 1
    call ext_settings_service_gc
    cmp rax, 1
    jne svt_fail
    cmp qword ptr [rbx + SV_detached_model], 0
    jne svt_fail
    mov rax, [rip + svt_model]
    cmp qword ptr [rax + ELM_refs], 0
    jne svt_fail
    # Synthetic unconsumed child refusal must retain exact slot and service owner.
    mov qword ptr [rip + svt_stage], 178
    mov rax, [rbx + SV_queue]
    mov [rip + svt_refuse_free], rax
    mov edi, 1
    call ext_settings_service_gc
    test rax, rax
    jnz svt_fail
    cmp rdx, -16
    jne svt_fail
    mov rax, [rip + svt_refuse_free]
    cmp [rbx + SV_queue], rax
    jne svt_fail
    mov qword ptr [rip + svt_refuse_free], 0
    mov edi, 1
    call ext_settings_service_gc
    cmp rax, 1
    jne svt_fail
    test rdx, rdx
    js svt_fail
    cmp qword ptr [rbx + SV_queue], 0
    jne svt_fail
    mov rax, [rbx + SV_path]
    mov [rip + svt_refuse_free], rax
    mov edi, 1
    call ext_settings_service_gc
    test rax, rax
    jnz svt_fail
    cmp rdx, -16
    jne svt_fail
    mov rax, [rip + svt_refuse_free]
    cmp [rbx + SV_path], rax
    jne svt_fail
    mov qword ptr [rip + svt_refuse_free], 0
    # Separate ready-model boundedGC, then path+self retirement with budget1.
    mov r12d, 4
1:  mov edi, 64
    call ext_settings_model_gc
    test rdx, rdx
    js svt_fail
    dec r12
    jnz 1b
    call svt_clean
    xor edi, edi
    call ext_settings_service_gc
    cmp rax, -22
    jne svt_fail
    mov edi, 1
    lea rsi, [rip + svt_ok]
    mov edx, SVT_OKLEN
    SYS SYS_write
    xor edi, edi
    call sys_exit
