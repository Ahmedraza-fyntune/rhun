.include "rhun.inc"
.include "app/extsettingsjob.inc"
.include "app/extsettingsini.inc"
.include "app/extsettingsqueue.inc"
.section .rodata
esmr_tag: .quad 17,29,0,0
esmr_section: .ascii "owner/tool"
esmr_key: .ascii "setting.x"
esmr_ok: .ascii "ok checked settings release ownership and retry\n"
.bss
.p2align 3
esmr_fail_unmap: .quad 0
.globl esmr_unmap_calls
esmr_unmap_calls: .quad 0
esmr_now: .quad 0
esmr_status: .zero 32
esmr_delta: .zero EC_SIZE
esmr_stage: .quad 0
.text
esmr_fail:
    mov rdi, [rip + esmr_stage]
    add edi, 80
    call sys_exit
FN esmr_time
    mov rax, [rip + esmr_now]
    ret
esmr_status_get:
    lea rdi, [rip + esmr_status]
    jmp ext_settings_memory_status
# Actual native retry only after its advertised backoff, never fake completion.
esmr_drain:
    PROLOGUE
    mov r12d, 16
1:  call ext_settings_memory_pending
    test rax, rax
    jz 2f
    dec r12
    jz esmr_fail
    call ext_settings_memory_timeout
    cmp rax, 1
    jb esmr_fail
    cmp rax, 1000
    ja esmr_fail
    add [rip + esmr_now], rax
    mov edi, 64
    call ext_settings_memory_gc
    test rdx, rdx
    js esmr_fail
    cmp rcx, 64
    ja esmr_fail
    jmp 1b
2:  call ext_settings_memory_ack_cleanup
    test rax, rax
    jnz esmr_fail
    EPILOGUE
esmr_large_frame:
    lea rdi, [rip + esmr_tag]
    mov esi, EW_SNAPSHOT
    mov edx, 1048576
    xor ecx, ecx
    jmp ext_settings_frame_new
FN main
    PROLOGUE 32
    mov r15, [rip + g_mem_live]
    mov qword ptr [rip + esmr_now], 1000
    mov qword ptr [rip + esmr_stage], 1
    mov edi, 131072
    call ext_settings_memory_try
    test rax, rax
    jz esmr_fail
    mov rbx, rax
    mov r12, [rbx - 32]
    cmp r12, 4096
    jb esmr_fail
    mov qword ptr [rip + esmr_fail_unmap], 12
    mov rdi, rbx
    call ext_settings_memory_free
    test rax, rax
    jnz esmr_fail
    test rdx, rdx
    jns esmr_fail
    cmp rcx, 1
    jne esmr_fail
    call esmr_status_get
    cmp [rip + esmr_status], r12
    jne esmr_fail
    cmp qword ptr [rip + esmr_status + 8], 1
    jne esmr_fail
    cmp [rip + esmr_status + 16], r12
    jne esmr_fail
    cmp qword ptr [rip + esmr_status + 24], 0
    jge esmr_fail
    mov rax, r15
    inc rax
    cmp [rip + g_mem_live], rax
    jne esmr_fail
    # A still-mapped RETIRED prefix rejects duplicate caller ownership transfer.
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rax, -22
    jne esmr_fail
    test rdx, rdx
    jnz esmr_fail
    test rcx, rcx
    jnz esmr_fail
    mov r14d, ESM_CAP
    sub r14, r12
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz esmr_fail
    mov edi, 1
    call ext_settings_memory_try
    test rax, rax
    jnz esmr_fail
    cmp rdx, -12
    jne esmr_fail
    mov rdi, r14
    call ext_settings_memory_release
    call ext_settings_memory_ack_cleanup
    cmp rax, -16
    jne esmr_fail
    # Exact16,32,...,1000ms backoff and zero attempts before due.
    mov r13d, 16
    mov r14d, 8
.Lesmr_backoff:
    call ext_settings_memory_timeout
    cmp rax, r13
    jne esmr_fail
    mov rax, [rip + esmr_unmap_calls]
    mov [rsp], rax
    mov edi, 64
    call ext_settings_memory_gc
    test rax, rax
    jnz esmr_fail
    test rdx, rdx
    jnz esmr_fail
    test rcx, rcx
    jnz esmr_fail
    mov rax, [rsp]
    cmp [rip + esmr_unmap_calls], rax
    jne esmr_fail
    add [rip + esmr_now], r13
    mov edi, 64
    call ext_settings_memory_gc
    test rax, rax
    jnz esmr_fail
    test rdx, rdx
    jns esmr_fail
    cmp rcx, 1
    jne esmr_fail
    call ext_settings_memory_total
    cmp rax, r12
    jne esmr_fail
    mov rax, r15
    inc rax
    cmp [rip + g_mem_live], rax
    jne esmr_fail
    add r13, r13
    cmp r13, 1000
    jbe 1f
    mov r13d, 1000
1:  dec r14
    jnz .Lesmr_backoff
    xor edi, edi
    call ext_settings_memory_gc
    cmp rax, -22
    jne esmr_fail
    mov edi, 65
    call ext_settings_memory_gc
    cmp rax, -22
    jne esmr_fail
    mov qword ptr [rip + esmr_fail_unmap], 0
    call esmr_drain
    # Do not touch rbx: actual native release has now consumed its mapping.
    call ext_settings_memory_total
    test rax, rax
    jnz esmr_fail
    cmp [rip + g_mem_live], r15
    jne esmr_fail

    mov qword ptr [rip + esmr_stage], 2
    # ESB gc(1) transfers the failed large frame, then its owner on the next call.
    call esmr_large_frame
    test rax, rax
    jz esmr_fail
    mov rbx, rax
    mov qword ptr [rax + EJF_body], 1
    mov qword ptr [rax + EJF_body + 8], 1048528
    mov qword ptr [rax + EJF_sealed], 1
    lea rdi, [rbx + EJF_body + 48]
    mov esi, 'x'
    mov edx, 1048528
    call memset
    mov byte ptr [rbx + EJF_body + 48], ';'
    mov byte ptr [rbx + EJF_body + 1048575], 10
    lea rdi, [rbx + EJF_body + 48]
    mov esi, 1048528
    lea rdx, [rbx + EJF_body + 16]
    call sha256_hash
    cmp eax, 1
    jne esmr_fail
    mov r14, [rbx - 32]
    mov rax, rbx
    mov rdi, rax
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jz esmr_fail
    mov r12, rax
    mov rdi, rax
    call ext_settings_snapshot_release
    mov qword ptr [rip + esmr_fail_unmap], 1
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne esmr_fail
    test rdx, rdx
    jns esmr_fail
    cmp qword ptr [r12 + ESB_frame], 0
    jne esmr_fail
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne esmr_fail
    # r12 owner consumed; failed frame belongs solely to the global disposer.
    call ext_settings_memory_total
    cmp rax, r14
    jne esmr_fail
    call esmr_drain
    cmp [rip + g_mem_live], r15
    jne esmr_fail

    mov qword ptr [rip + esmr_stage], 3
    mov edi, ECJ_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz esmr_fail
    mov rbx, rax
    call esmr_large_frame
    mov [rbx + ECJ_tx], rax
    mov qword ptr [rip + esmr_fail_unmap], 1
    mov rdi, rbx
    call ecj_drop_tx
    test rax, rax
    jnz esmr_fail
    cmp qword ptr [rbx + ECJ_tx], 0
    jne esmr_fail
    cmp qword ptr [rbx + ECJ_cleanup], 0
    jge esmr_fail
    call esmr_large_frame
    mov [rbx + ECJ_rx], rax
    mov qword ptr [rip + esmr_fail_unmap], 1
    mov rdi, rbx
    call ecj_drop_rx
    test rax, rax
    jnz esmr_fail
    cmp qword ptr [rbx + ECJ_rx], 0
    jne esmr_fail
    call ext_settings_memory_pending
    cmp rax, 2
    jne esmr_fail
    mov rdi, rbx
    call ext_settings_memory_free
    test rax, rax
    jnz esmr_fail
    call esmr_drain
    cmp [rip + g_mem_live], r15
    jne esmr_fail

    mov qword ptr [rip + esmr_stage], 4
    call ext_settings_queue_create
    test rax, rax
    jz esmr_fail
    mov rbx, rax
    mov edi, 70000
    call ext_settings_memory_try
    test rax, rax
    jz esmr_fail
    mov r12, rax
    mov rdi, rax
    mov esi, 'x'
    mov edx, 70000
    call memset
    lea rdi, [rip + esmr_delta]
    lea rax, [rip + esmr_section]
    mov [rdi + EC_section], rax
    mov qword ptr [rdi + EC_seclen], 10
    lea rax, [rip + esmr_key]
    mov [rdi + EC_key], rax
    mov qword ptr [rdi + EC_keylen], 9
    mov [rdi + EC_value], r12
    mov qword ptr [rdi + EC_vallen], 70000
    mov rsi, rdi
    mov rdi, rbx
    call ext_settings_queue_put
    test rax, rax
    jnz esmr_fail
    mov rdi, r12
    call ext_settings_memory_free
    mov rax, [rbx + EQ_slots + EQS_cell]
    mov r14, [rax - 32]
    mov rdi, rbx
    call ext_settings_queue_discard_step
    test rax, rax
    jnz esmr_fail
    mov qword ptr [rip + esmr_fail_unmap], 1
    mov rdi, rbx
    call ext_settings_queue_gc
    cmp rax, 1
    jne esmr_fail
    test rdx, rdx
    jns esmr_fail
    mov rdi, rbx
    call ext_settings_queue_free
    test rax, rax
    jnz esmr_fail
    call ext_settings_memory_total
    cmp rax, r14
    jne esmr_fail
    call esmr_drain
    cmp [rip + g_mem_live], r15
    jne esmr_fail
    call ext_settings_memory_total
    test rax, rax
    jnz esmr_fail
    call ext_settings_memory_timeout
    cmp rax, -1
    jne esmr_fail
    xor edi, edi
    call ext_settings_memory_free
    test rax, rax
    jnz esmr_fail
    test rdx, rdx
    jnz esmr_fail
    cmp rcx, 1
    jne esmr_fail
    mov edi, 1
    lea rsi, [rip + esmr_ok]
    mov edx, 48
    call write_all
    xor eax, eax
    EPILOGUE
