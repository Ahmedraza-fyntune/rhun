.include "rhun.inc"
.bss
.p2align 3
cq_ext: .zero EXT_SIZE
cq_ext_saved: .zero EXT_SIZE
cq_data_saved: .zero 131072
cq_buffer: .quad 0
cq_live: .quad 0
cq_stage: .quad 0
cq_move_bytes: .quad 0
cq_move_calls: .quad 0
.text
cq_fail:
    mov rdi, [rip + cq_stage]
    add rdi, 90
    call sys_exit
    ud2
FN cq_move
    add [rip + cq_move_bytes], rdx
    inc qword ptr [rip + cq_move_calls]
    jmp memmove
cq_capture:
    PROLOGUE
    lea rdi, [rip + cq_ext_saved]
    lea rsi, [rip + cq_ext]
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + cq_data_saved]
    mov rsi, [rip + cq_buffer]
    mov edx, 131072
    call memcpy
    mov qword ptr [rip + cq_move_bytes], 0
    mov qword ptr [rip + cq_move_calls], 0
    EPILOGUE
cq_unchanged:
    PROLOGUE
    cmp qword ptr [rip + cq_move_calls], 0
    jne cq_fail
    lea rdi, [rip + cq_ext_saved]
    lea rsi, [rip + cq_ext]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz cq_fail
    lea rdi, [rip + cq_data_saved]
    mov rsi, [rip + cq_buffer]
    mov edx, 131072
    call memeq
    test eax, eax
    jz cq_fail
    EPILOGUE
cq_call:
    lea rdi, [rip + cq_ext]
    mov esi, 65536
    jmp ext_send_queue_compact_bounded
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + cq_live], rax
    mov edi, 131072
    call mem_alloc_try
    test rax, rax
    jz cq_fail
    mov [rip + cq_buffer], rax
    xor ecx, ecx
1:  mov [rax + rcx], cl
    inc rcx
    cmp rcx, 131072
    jb 1b
    lea rbx, [rip + cq_ext]
    mov [rbx + EXT_wq + SB_ptr], rax
    mov qword ptr [rbx + EXT_wq + SB_cap], 131072
    mov qword ptr [rbx + EXT_wq + SB_len], 65538
    mov qword ptr [rbx + EXT_wq_off], 1
    mov qword ptr [rip + cq_stage], 1
    call cq_capture
    call cq_call
    cmp rax, -11
    jne cq_fail
    call cq_unchanged
    mov qword ptr [rip + cq_stage], 2
    mov qword ptr [rbx + EXT_wq + SB_len], 65537
    call cq_capture
    call cq_call
    test rax, rax
    jnz cq_fail
    cmp qword ptr [rip + cq_move_calls], 1
    jne cq_fail
    cmp qword ptr [rip + cq_move_bytes], 65536
    jne cq_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 65536
    jne cq_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne cq_fail
    mov rdi, [rip + cq_buffer]
    lea rsi, [rip + cq_data_saved + 1]
    mov edx, 65536
    call memeq
    test eax, eax
    jz cq_fail
    # A compact queue needs no copy even if its bytes exceed this call's quota.
    mov qword ptr [rip + cq_stage], 3
    call cq_capture
    mov rdi, rbx
    mov esi, 1
    call ext_send_queue_compact_bounded
    test rax, rax
    jnz cq_fail
    call cq_unchanged
    mov qword ptr [rip + cq_stage], 4
    mov qword ptr [rbx + EXT_wq_off], 65536
    call cq_capture
    call cq_call
    test rax, rax
    jnz cq_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 0
    jne cq_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne cq_fail
    cmp qword ptr [rip + cq_move_calls], 0
    jne cq_fail
    # Corrupt descriptors are numeric-only refusals, preserving all input bytes.
    xor r14d, r14d
.Lcq_bad_loop:
    lea r15, [rip + cq_bad]
    mov rax, r14
    shl rax, 4
    add r15, rax
    lea rax, [r14 + 10]
    mov [rip + cq_stage], rax
    mov rcx, [r15]
    mov r12, [rbx + rcx]
    mov rax, [r15 + 8]
    mov [rbx + rcx], rax
    call cq_capture
    call cq_call
    cmp rax, -22
    jne cq_fail
    call cq_unchanged
    mov rcx, [r15]
    mov [rbx + rcx], r12
    inc r14
    cmp r14, 5
    jb .Lcq_bad_loop
    mov qword ptr [rip + cq_stage], 20
    call cq_capture
    mov rdi, rbx
    xor esi, esi
    call ext_send_queue_compact_bounded
    cmp rax, -22
    jne cq_fail
    call cq_unchanged
    mov rdi, rbx
    mov esi, 65537
    call ext_send_queue_compact_bounded
    cmp rax, -22
    jne cq_fail
    call cq_unchanged
    xor edi, edi
    mov esi, 1
    call ext_send_queue_compact_bounded
    cmp rax, -22
    jne cq_fail
    call cq_unchanged
    # Canonical zero allocation is accepted without dereferencing its pointer.
    mov qword ptr [rip + cq_stage], 21
    mov qword ptr [rbx + EXT_wq + SB_ptr], 0
    mov qword ptr [rbx + EXT_wq + SB_cap], 0
    call cq_call
    test rax, rax
    jnz cq_fail
    mov rdi, [rip + cq_buffer]
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cq_live]
    jne cq_fail
    mov edi, 1
    lea rsi, [rip + cq_ok]
    mov edx, 36
    SYS SYS_write
    xor eax, eax
    EPILOGUE
.section .rodata
.p2align 3
cq_bad:
    .quad EXT_wq_off, 1
    .quad EXT_wq + SB_len, 131073
    .quad EXT_wq + SB_ptr, 0
    .quad EXT_wq + SB_cap, 0
    .quad EXT_wq + SB_ptr, -32
cq_ok: .asciz "ok bounded channel queue compaction\n"
