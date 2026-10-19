.include "rhun.inc"
.include "app/taskcore.inc"
.section .rodata
.p2align 3
tct_text_cases:
    .quad tct_label, 5, 1
    .quad tct_command, 9, 1
    .quad tct_emoji, 4, 1
    .quad tct_replacement, 3, 1
    .quad tct_overlong, 3, 0
    .quad tct_surrogate, 3, 0
    .quad tct_above, 4, 0
    .quad tct_bidi, 3, 0
    .quad tct_zero, 1, 0
    .quad tct_emoji, 3, 0
    .quad 0, 0, 0

tct_cwd: .asciz "/workspace"
tct_label: .asciz "Build"
tct_command: .asciz "echo task"
tct_edited: .ascii "echo edited"
tct_emoji: .byte 0xf0,0x9f,0x98,0x80
tct_replacement: .byte 0xef,0xbf,0xbd
tct_overlong: .byte 0xe0,0x80,0xaf
tct_surrogate: .byte 0xed,0xa0,0x80
tct_above: .byte 0xf4,0x90,0x80,0x80
tct_bidi: .byte 0xe2,0x80,0xae
tct_zero: .byte 0
tct_ok: .asciz "ok managed task ownership, restart and output\n"
.bss
.p2align 3
tct_context: .zero TC_SIZE
tct_snapshot: .zero TC_SIZE
.ifdef TEST_TASK_CORE_FAULT
tct_alloc_calls: .quad 0
tct_fail_at: .quad 0
tct_failure_seen: .quad 0
.endif
tct_stage: .quad 0
tct_live: .quad 0
tct_nonce: .quad 0
tct_id: .quad 0
tct_first: .quad 0
tct_second: .quad 0
tct_third: .quad 0
tct_fourth: .quad 0
tct_fifth: .quad 0
tct_loop: .quad 0
tct_chunk: .zero TASK_READ_MAX
.text
tct_fail:
    mov rdi, [rip + tct_stage]
    inc edi
    call sys_exit
# Prepare under owner11 with fresh nonce. Returns positive ID in rax, record in rdx.
tct_prepare:
    lea rdi, [rip + tct_context]
    mov esi, 11
    inc qword ptr [rip + tct_nonce]
    mov rdx, [rip + tct_nonce]
    lea rcx, [rip + tct_cwd]
    lea r8, [rip + tct_label]
    lea r9, [rip + tct_command]
    jmp task_core_prepare
tct_confirm:
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_id]
    lea rcx, [rip + tct_edited]
    mov r8d, 11
    jmp task_core_confirm
tct_find:
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    jmp task_core_find
tct_start:
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    jmp task_core_started
tct_restart:
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_first]
    inc qword ptr [rip + tct_nonce]
    mov rcx, [rip + tct_nonce]
    jmp task_core_restart
tct_lifetime:
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    jmp task_core_lifetime
tct_eof:
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    xor edx, edx
    jmp task_core_output_end
tct_dispose:
    lea rdi, [rip + tct_context]
    call task_core_dispose
    test rax, rax
    jnz tct_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + tct_live]
    jne tct_fail
    ret
.ifdef TEST_TASK_CORE_FAULT
FN tct_fault_alloc
    inc qword ptr [rip + tct_alloc_calls]
    mov rax, [rip + tct_alloc_calls]
    cmp rax, [rip + tct_fail_at]
    je 1f
    jmp mem_alloc_try
1:  mov qword ptr [rip + tct_failure_seen], 1
    xor eax, eax
    ret

tct_fault_gates:
    PROLOGUE
    mov r12d, 1
1:  lea rdi, [rip + tct_snapshot]
    lea rsi, [rip + tct_context]
    mov edx, TC_SIZE
    call memcpy
    mov [rip + tct_fail_at], r12
    mov qword ptr [rip + tct_alloc_calls], 0
    mov qword ptr [rip + tct_failure_seen], 0
    call tct_prepare
    cmp rax, -12
    jne tct_fail
    cmp qword ptr [rip + tct_failure_seen], 1
    jne tct_fail
    lea rdi, [rip + tct_snapshot]
    lea rsi, [rip + tct_context]
    mov edx, TC_SIZE
    call memeq
    test eax, eax
    jz tct_fail
    mov rax, [rip + tct_live]
    cmp rax, [rip + g_mem_live]
    jne tct_fail
    mov qword ptr [rip + tct_fail_at], 0
    call tct_prepare
    test rax, rax
    jle tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, rax
    call task_core_abort
    test rax, rax
    jnz tct_fail
    inc r12d
    cmp r12d, 4
    jbe 1b
    call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    lea rdi, [rip + tct_snapshot]
    lea rsi, [rip + tct_context]
    mov edx, TC_SIZE
    call memcpy
    mov rax, [rip + g_mem_live]
    mov r13, rax
    mov qword ptr [rip + tct_fail_at], 1
    mov qword ptr [rip + tct_alloc_calls], 0
    call tct_confirm
    cmp rax, -12
    jne tct_fail
    lea rdi, [rip + tct_snapshot]
    lea rsi, [rip + tct_context]
    mov edx, TC_SIZE
    call memeq
    test eax, eax
    jz tct_fail
    cmp r13, [rip + g_mem_live]
    jne tct_fail
    mov qword ptr [rip + tct_fail_at], 0
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    call task_core_abort
    call tct_dispose
    # The exposed counter is never reset by product APIs; only this fresh test instance starts over.
    lea rdi, [rip + tct_context]
    call task_core_init
    mov qword ptr [rip + tct_nonce], 0
    EPILOGUE
.endif
# A fresh isolated core verifies that native negative nonces cannot collide with wire requests.
tct_native_nonce:
    PROLOGUE
    mov qword ptr [rip + tct_stage], 8
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, -1
    lea rcx, [rip + tct_cwd]
    lea r8, [rip + tct_label]
    lea r9, [rip + tct_command]
    call task_core_prepare
    cmp rax, -22
    jne tct_fail
    test rdx, rdx
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    xor edx, edx
    call task_core_prepare
    cmp rax, -22
    jne tct_fail
    call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    mov [rip + tct_first], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -5
    call task_core_launch_failed
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_first]
    mov rcx, -1
    call task_core_restart
    cmp rax, -22
    jne tct_fail
    test rdx, rdx
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_first]
    mov ecx, 1
    call task_core_restart_native
    cmp rax, -22
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_first]
    xor ecx, ecx
    call task_core_restart_native
    cmp rax, -22
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_first]
    mov rcx, 0x8000000000000000
    call task_core_restart_native
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    mov rax, 0x8000000000000000
    cmp [rdx + TK_nonce], rax
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, 0x8000000000000000
    call task_core_cancel
    call tct_find
    test rax, rax
    jz tct_fail
    cmp dword ptr [rax + TK_state], TASK_PREPARED
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    call task_core_abort
    test rax, rax
    jnz tct_fail
    call tct_dispose
    # Only a fresh test instance is reset. Product ID counters are never reset.
    lea rdi, [rip + tct_context]
    call task_core_init
    mov qword ptr [rip + tct_nonce], 0
    EPILOGUE

# Service failure is independent of output EOF and retains exact-once disposal ownership.
tct_process_failure:
    PROLOGUE
    mov qword ptr [rip + tct_stage], 9
    call tct_prepare
    mov [rip + tct_id], rax
    test rax, rax
    jle tct_fail
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 901
    call tct_start
    cmp eax, 1
    jne tct_fail
    call tct_eof
    test rax, rax
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -5
    call task_core_process_failed
    cmp rax, 901
    jne tct_fail
    call tct_find
    cmp qword ptr [rax + TK_process], 901
    jne tct_fail
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne tct_fail
    cmp qword ptr [rip + tct_context + TC_active], 1
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -13
    call task_core_process_failed
    cmp rax, 901
    jne tct_fail
    xor edx, edx
    call tct_lifetime
    cmp rax, 901
    jne tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_FAILED
    jne tct_fail
    cmp dword ptr [rax + TK_exit], -5
    jne tct_fail
    cmp qword ptr [rax + TK_process], 0
    jne tct_fail
    cmp qword ptr [rip + tct_context + TC_active], 0
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -5
    call task_core_process_failed
    test rax, rax
    jnz tct_fail
    call tct_eof
    test rax, rax
    jnz tct_fail
    xor edx, edx
    call tct_lifetime
    test rax, rax
    jnz tct_fail
    call tct_dispose
    call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 902
    call tct_start
    cmp eax, 1
    jne tct_fail
    xor edx, edx
    call tct_lifetime
    test rax, rax
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -13
    call task_core_process_failed
    cmp rax, 902
    jne tct_fail
    # A later read error cannot replace the earlier service failure.
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -12
    call task_core_output_end
    cmp rax, 902
    jne tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_FAILED
    jne tct_fail
    cmp dword ptr [rax + TK_exit], -13
    jne tct_fail
    cmp qword ptr [rax + TK_process], 0
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -4096
    call task_core_process_failed
    cmp rax, -22
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    xor edx, edx
    call task_core_process_failed
    cmp rax, -22
    jne tct_fail
    call tct_dispose
    # Fresh test instance, no product counter reset.
    lea rdi, [rip + tct_context]
    call task_core_init
    mov qword ptr [rip + tct_nonce], 0
    EPILOGUE

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + tct_live], rax
    lea rdi, [rip + tct_context]
    call task_core_init
.ifdef TEST_TASK_CORE_FAULT
    call tct_fault_gates
.endif
    call tct_native_nonce
    call tct_process_failure
    mov qword ptr [rip + tct_stage], 1
    lea rbx, [rip + tct_text_cases]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 2f
    mov rsi, [rbx + 8]
    call task_core_text
    cmp rax, [rbx + 16]
    jne tct_fail
    add rbx, 24
    jmp 1b
2:  call tct_prepare
    cmp rax, 1
    jne tct_fail
    mov [rip + tct_id], rax
    mov [rip + tct_first], rax
    lea rdi, [rip + tct_context]
    mov esi, 22
    mov edx, 1
    call task_core_lookup
    test rax, rax
    jnz tct_fail
    dec qword ptr [rip + tct_nonce]
    call tct_prepare
    cmp rax, -17
    jne tct_fail
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 101
    call tct_start
    cmp eax, 1
    jne tct_fail
    mov qword ptr [rip + tct_stage], 2
    # Invalid lengths and overflow reject before even a non-NULL unreadable source is touched.
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, 1
    mov ecx, TASK_READ_MAX+1
    call task_core_output
    cmp rax, -22
    jne tct_fail
    call tct_find
    mov qword ptr [rax + TK_total], -1
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, 1
    mov ecx, 1
    call task_core_output
    cmp rax, -75
    jne tct_fail
    call tct_find
    cmp qword ptr [rax + TK_total], -1
    jne tct_fail
    cmp qword ptr [rax + TK_length], 0
    jne tct_fail
    mov qword ptr [rax + TK_total], 0
    mov qword ptr [rip + tct_loop], 0
3:  lea rdi, [rip + tct_chunk]
    mov rsi, [rip + tct_loop]
    add esi, 'A'
    mov edx, TASK_READ_MAX
    call memset
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    lea rdx, [rip + tct_chunk]
    mov ecx, TASK_READ_MAX
    call task_core_output
    test rax, rax
    jnz tct_fail
    inc qword ptr [rip + tct_loop]
    cmp qword ptr [rip + tct_loop], 5
    jb 3b
    call tct_find
    cmp qword ptr [rax + TK_length], TASK_OUTPUT_MAX
    jne tct_fail
    cmp qword ptr [rax + TK_total], TASK_READ_MAX*5
    jne tct_fail
    mov rdx, [rax + TK_output]
    cmp byte ptr [rdx], 'B'
    jne tct_fail
    cmp byte ptr [rdx + TASK_OUTPUT_MAX-1], 'E'
    jne tct_fail
    mov edx, 7
    call tct_lifetime
    test rax, rax
    jnz tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    jne tct_fail
    cmp dword ptr [rax + TK_exit], -1
    jne tct_fail
    call tct_eof
    cmp rax, 101
    jne tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_EXITED
    jne tct_fail
    cmp dword ptr [rax + TK_exit], 7
    jne tct_fail
    call tct_eof
    test rax, rax
    jnz tct_fail
    mov qword ptr [rip + tct_stage], 3
    call tct_restart
    test rax, rax
    jle tct_fail
    mov [rip + tct_second], rax
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 102
    call tct_start
    cmp eax, 1
    jne tct_fail
    call tct_restart
    test rax, rax
    jle tct_fail
    mov [rip + tct_third], rax
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    cmp rdx, 102
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_third]
    call task_core_can_start
    test eax, eax
    jnz tct_fail
    call tct_restart
    cmp rax, -11
    jne tct_fail
    mov rax, [rip + tct_second]
    mov [rip + tct_id], rax
    xor edx, edx
    call tct_lifetime
    test rax, rax
    jnz tct_fail
    call tct_eof
    cmp rax, 102
    jne tct_fail
    mov rax, [rip + tct_third]
    mov [rip + tct_id], rax
    mov edx, 103
    call tct_start
    cmp eax, 1
    jne tct_fail
    call tct_restart
    test rax, rax
    jle tct_fail
    mov [rip + tct_fourth], rax
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    cmp rdx, 103
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 22
    mov rdx, [rip + tct_nonce]
    call task_core_cancel
    test rax, rax
    jnz tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_QUEUED
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_nonce]
    call task_core_cancel
    test rax, rax
    jnz tct_fail
    # A canceled queued replacement must not hide its still-stopping predecessor.
    call tct_restart
    test rax, rax
    jle tct_fail
    mov [rip + tct_fifth], rax
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    cmp rdx, 103
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_fifth]
    call task_core_can_start
    test eax, eax
    jnz tct_fail
    mov rax, [rip + tct_third]
    mov [rip + tct_id], rax
    lea rdi, [rip + tct_context]
    mov rsi, rax
    mov edx, -5
    call task_core_output_end
    cmp rax, 103
    jne tct_fail
    xor edx, edx
    call tct_lifetime
    cmp rax, 103
    jne tct_fail
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_FAILED
    jne tct_fail
    cmp dword ptr [rax + TK_exit], -5
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_fifth]
    call task_core_can_start
    cmp eax, 1
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_fifth]
    call task_core_stop
    test rax, rax
    jnz tct_fail
    call tct_dispose
    mov qword ptr [rip + tct_stage], 4
    mov qword ptr [rip + tct_loop], 0
4:  call tct_prepare
    test rax, rax
    jle tct_fail
    inc qword ptr [rip + tct_loop]
    cmp qword ptr [rip + tct_loop], TASK_ACTIVE_MAX
    jb 4b
    call tct_prepare
    cmp rax, -11
    jne tct_fail
    lea rdi, [rip + tct_context]
    call task_core_dispose
    cmp rax, -16
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    call task_core_retire
    cmp qword ptr [rip + tct_context + TC_active], 0
    jne tct_fail
    call tct_dispose
    mov qword ptr [rip + tct_stage], 5
    mov qword ptr [rip + tct_loop], 0
5:  call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    cmp qword ptr [rip + tct_loop], 0
    jne 6f
    mov [rip + tct_first], rax
6:  call tct_confirm
    test rax, rax
    jnz tct_fail
    lea rdi, [rip + tct_context]
    mov rsi, [rip + tct_id]
    mov edx, -2
    call task_core_launch_failed
    test rax, rax
    jnz tct_fail
    inc qword ptr [rip + tct_loop]
    cmp qword ptr [rip + tct_loop], TASK_RECORDS
    jb 5b
    call tct_restart
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 200
    call tct_start
    cmp eax, 1
    jne tct_fail
    # A completed output can precede lifetime confirmation without releasing ownership.
    call tct_eof
    test rax, rax
    jnz tct_fail
    xor edx, edx
    call tct_lifetime
    cmp rax, 200
    jne tct_fail
    call tct_dispose
    mov qword ptr [rip + tct_stage], 6
    call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    lea rdi, [rip + tct_context]
    call task_core_project_changed
    call tct_find
    cmp dword ptr [rax + TK_state], TASK_FAILED
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    mov rdx, [rip + tct_id]
    inc qword ptr [rip + tct_nonce]
    mov rcx, [rip + tct_nonce]
    call task_core_restart
    cmp rax, -116
    jne tct_fail
    call tct_dispose
    mov qword ptr [rip + tct_stage], 7
    mov qword ptr [rip + tct_loop], 0
7:  call tct_prepare
    test rax, rax
    jle tct_fail
    mov [rip + tct_id], rax
    call tct_confirm
    test rax, rax
    jnz tct_fail
    mov edx, 1000
    add rdx, [rip + tct_loop]
    call tct_start
    cmp eax, 1
    jne tct_fail
    inc qword ptr [rip + tct_loop]
    cmp qword ptr [rip + tct_loop], TASK_ACTIVE_MAX
    jb 7b
    xor r12d, r12d
    xor r13d, r13d
8:  lea rdi, [rip + tct_context]
    call task_core_next_output
    test rax, rax
    jz tct_fail
    lea rdx, [rip + tct_context + TC_records]
    sub rax, rdx
    shr rax, 7
    mov ecx, eax
    mov edx, 1
    shl rdx, cl
    test r12, rdx
    jnz tct_fail
    or r12, rdx
    inc r13d
    cmp r13d, TASK_ACTIVE_MAX
    jb 8b
    cmp r12, 255
    jne tct_fail
    lea rdi, [rip + tct_context]
    mov esi, 11
    call task_core_retire
    cmp qword ptr [rip + tct_context + TC_active], TASK_ACTIVE_MAX
    jne tct_fail
    xor r12d, r12d
9:  mov rax, r12
    shl rax, 7
    lea rdx, [rip + tct_context + TC_records]
    add rax, rdx
    mov rax, [rax + TK_id]
    mov [rip + tct_id], rax
    call tct_eof
    test rax, rax
    jnz tct_fail
    xor edx, edx
    call tct_lifetime
    lea rdx, [r12 + 1000]
    cmp rax, rdx
    jne tct_fail
    inc r12d
    cmp r12d, TASK_ACTIVE_MAX
    jb 9b
    call tct_dispose
    mov rax, 0x7fffffffffffffff
    mov [rip + tct_context + TC_project], rax
    lea rdi, [rip + tct_context]
    call task_core_project_changed
    lea rdi, [rip + tct_context]
    call task_core_project_changed
    cmp qword ptr [rip + tct_context + TC_project], 0
    jne tct_fail
    call tct_prepare
    cmp rax, -75
    jne tct_fail
    call tct_dispose
    mov qword ptr [rip + tct_context + TC_project], 1
    mov rax, 0x7fffffffffffffff
    mov [rip + tct_context + TC_next], rax
    call tct_prepare
    cmp rax, -75
    jne tct_fail
    call tct_dispose
    lea rdi, [rip + tct_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
