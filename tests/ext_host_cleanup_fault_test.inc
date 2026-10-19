# Fake descriptor IDs make fault outcomes deterministic without native retry.
.include "rhun.inc"
.bss
.p2align 3
hc_host: .zero EXT_SIZE
hc_calls: .quad 0
hc_mode: .quad 0
hc_stage: .quad 0
hc_before: .zero EXT_SIZE
.text
FN main
    PROLOGUE
    lea rbx, [rip + hc_host]
    xor r12d, r12d
.Lhct_field:
    mov [rip + hc_stage], r12
    inc qword ptr [rip + hc_stage]
    lea rax, [rip + hc_fields]
    mov rax, [rax + r12*8]
    lea r13, [rbx + rax]
    mov dword ptr [r13], 777
    mov dword ptr [rbx + EXT_host_cleanup_mask], 0
    mov dword ptr [rbx + EXT_host_cleanup_error], 0
    mov qword ptr [rip + hc_calls], 0
    mov qword ptr [rip + hc_mode], 1
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp rax, -5
    jne .Lhct_bad
    cmp rdx, 1
    jne .Lhct_bad
    cmp dword ptr [r13], -1
    jne .Lhct_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], -5
    jne .Lhct_bad
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp rdx, 1
    jne .Lhct_bad
    cmp qword ptr [rip + hc_calls], 1
    jne .Lhct_bad
    # Known retained ownership blocks ordinary retry, explicit retry consumes once.
    mov dword ptr [r13], 777
    mov qword ptr [rip + hc_mode], 0
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp rax, -4
    jne .Lhct_bad
    test rdx, rdx
    jnz .Lhct_bad
    cmp dword ptr [r13], 777
    jne .Lhct_bad
    mov eax, [rbx + EXT_host_cleanup_mask]
    lea ecx, [r12 + 8]
    bt eax, ecx
    jnc .Lhct_bad
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp qword ptr [rip + hc_calls], 2
    jne .Lhct_bad
    mov qword ptr [rip + hc_mode], 1
    mov rdi, rbx
    mov rsi, r12
    call ext_host_retry_known
    cmp rax, -5
    jne .Lhct_bad
    cmp rdx, 1
    jne .Lhct_bad
    cmp qword ptr [rip + hc_calls], 3
    jne .Lhct_bad
    cmp dword ptr [r13], -1
    jne .Lhct_bad
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lhct_bad
    # Unknown ownership is never retried by either API, error1 remains preserved.
    mov dword ptr [r13], 777
    mov qword ptr [rip + hc_mode], 2
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp rax, -9
    jne .Lhct_bad
    cmp rdx, 2
    jne .Lhct_bad
    cmp dword ptr [r13], 777
    jne .Lhct_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], -5
    jne .Lhct_bad
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    cmp rdx, 2
    jne .Lhct_bad
    mov rdi, rbx
    mov rsi, r12
    call ext_host_retry_known
    cmp rdx, 2
    jne .Lhct_bad
    cmp qword ptr [rip + hc_calls], 4
    jne .Lhct_bad
    cmp dword ptr [r13], 777
    jne .Lhct_bad
    # This is a separate fake owner per index. No actual native object exists.
    inc r12
    cmp r12, 5
    jb .Lhct_field
    call hc_setup_matrix
    test rax, rax
    jnz .Lhct_bad
    xor eax, eax
    EPILOGUE
.Lhct_bad:
    mov rax, [rip + hc_stage]
    EPILOGUE
FN hc_close
    inc qword ptr [rip + hc_calls]
    mov rdx, [rip + hc_mode]
    cmp rdx, 3
    jne 3f
    mov edx, 1
    xor eax, eax
    ret
3:  mov rax, -4
    test rdx, rdx
    jz 1f
    mov rax, -5
    cmp rdx, 1
    je 1f
    mov rax, -9
1:  ret
.section .rodata
.p2align 3
hc_fields: .quad EXT_in, EXT_out, EXT_log, EXT_host_child_in, EXT_host_child_out

.text
hc_reset:
    PROLOGUE
    lea rdi, [rip + hc_host]
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    lea rbx, [rip + hc_host]
    xor ecx, ecx
1:  lea rax, [rip + hc_fields]
    mov rax, [rax + rcx*8]
    mov dword ptr [rbx + rax], -1
    inc rcx
    cmp rcx, 5
    jb 1b
    mov qword ptr [rip + hc_calls], 0
    EPILOGUE
hc_setup_matrix:
    PROLOGUE
    mov qword ptr [rip + hc_stage], 20
    call hc_reset
    mov dword ptr [rbx + EXT_host_cleanup_error], -17
    mov dword ptr [rbx + EXT_host_child_out], 777
    mov rdi, rbx
    call ext_host_prepared_start_admit
    cmp rax, -16
    jne .Lhc_setup_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], -17
    jne .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 0
    jne .Lhc_setup_bad
    mov dword ptr [rbx + EXT_host_child_out], -1
    mov rdi, rbx
    call ext_host_prepared_start_admit
    test rax, rax
    jnz .Lhc_setup_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jne .Lhc_setup_bad
    # Consumed negative on both originals remains an error, never two retries.
    mov qword ptr [rip + hc_stage], 21
    mov dword ptr [rbx + EXT_host_child_in], 777
    mov dword ptr [rbx + EXT_host_child_out], 778
    mov qword ptr [rip + hc_mode], 1
    mov rdi, rbx
    call ext_host_prepared_children_close
    cmp rax, -5
    jne .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 2
    jne .Lhc_setup_bad
    mov rdi, rbx
    call ext_host_prepared_children_close
    test rax, rax
    jnz .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 2
    jne .Lhc_setup_bad
    # Every retained class blocks cleanup, and repeated slices never retry it.
    xor r14d, r14d
.Lhc_setup_mode:
    call hc_reset
    mov qword ptr [rip + hc_stage], 22
    xor r13d, r13d
1:  lea rax, [rip + hc_fields]
    mov rax, [rax + r13*8]
    mov dword ptr [rbx + rax], 777
    inc r13
    cmp r13, 5
    jb 1b
    mov [rip + hc_mode], r14
    mov rdi, rbx
    call ext_host_prepared_cleanup
    test rdx, rdx
    jnz .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 5
    jne .Lhc_setup_bad
    mov eax, 0x1f00
    test r14, r14
    jz 2f
    mov eax, 0x1f
2:  cmp [rbx + EXT_host_cleanup_mask], eax
    jne .Lhc_setup_bad
    mov rdi, rbx
    call ext_host_prepared_cleanup
    test rdx, rdx
    jnz .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 5
    jne .Lhc_setup_bad
    add r14, 2
    cmp r14, 2
    jbe .Lhc_setup_mode
    call hc_reset
    mov qword ptr [rip + hc_stage], 23
    mov dword ptr [rbx + EXT_host_child_in], 777
    mov qword ptr [rip + hc_mode], 1
    mov rdi, rbx
    call ext_host_prepared_cleanup
    cmp rax, -5
    jne .Lhc_setup_bad
    cmp rdx, 1
    jne .Lhc_setup_bad
    cmp qword ptr [rip + hc_calls], 1
    jne .Lhc_setup_bad
    call hc_result_matrix
    test rax, rax
    jnz .Lhc_setup_bad
    xor eax, eax
    EPILOGUE
.Lhc_setup_bad:
    mov rax, [rip + hc_stage]
    EPILOGUE

.text
hc_result_matrix:
    PROLOGUE
    mov qword ptr [rip + hc_stage], 24
    call hc_reset
    xor r12d, r12d
.Lhcr_matrix:
    lea rax, [rip + hc_results]
    mov rcx, r12
    imul rcx, 20
    add rax, rcx
    mov ecx, [rax]
    mov [rbx + EXT_host_native_result], ecx
    mov ecx, [rax + 4]
    mov [rbx + EXT_host_setup_error], ecx
    mov ecx, [rax + 8]
    mov [rbx + EXT_host_cleanup_error], ecx
    mov ecx, [rax + 12]
    mov [rbx + EXT_startaccepted], ecx
    mov r13d, [rax + 16]
    lea rdi, [rip + hc_before]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, rbx
    call ext_host_prepared_finish_result
    cmp eax, r13d
    jne .Lhcr_matrix_bad
    lea rdi, [rip + hc_before]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhcr_matrix_bad
    inc r12
    mov rax, r12
    imul rax, 20
    lea rcx, [rip + hc_results]
    add rax, rcx
    lea rcx, [rip + hc_results_end]
    cmp rax, rcx
    jb .Lhcr_matrix
    # Resource-free failed setup retains all five owners and exact primary.
    mov qword ptr [rip + hc_stage], 25
    call hc_reset
    mov dword ptr [rbx + EXT_activation_required], 1
    xor r12d, r12d
1:  lea rax, [rip + hc_fields]
    mov rax, [rax + r12*8]
    mov dword ptr [rbx + rax], 777
    inc r12
    cmp r12, 5
    jb 1b
    mov qword ptr [rip + hc_mode], 0
    mov rdi, rbx
    mov rsi, -28
    call ext_host_prepared_abort
    cmp eax, -28
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_setup_error], -28
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_native_result], 0
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], -4
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_finish_code], -28
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_retiring], 3
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_status], ES_FAILED
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Lhcr_matrix_bad
    cmp qword ptr [rip + hc_calls], 5
    jne .Lhcr_matrix_bad
    mov rdi, rbx
    call ext_host_prepared_collect
    test eax, eax
    jnz .Lhcr_matrix_bad
    cmp qword ptr [rip + hc_calls], 5
    jne .Lhcr_matrix_bad
    # Only explicit known retries consume those five fake owners, once each.
    xor r12d, r12d
    mov qword ptr [rip + hc_mode], 1
2:  mov rdi, rbx
    mov rsi, r12
    call ext_host_retry_known
    cmp rdx, 1
    jne .Lhcr_matrix_bad
    inc r12
    cmp r12, 5
    jb 2b
    mov rdi, rbx
    call ext_host_prepared_collect
    cmp eax, 1
    jne .Lhcr_matrix_bad
    cmp edx, -28
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_retiring], 4
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], -4
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_native_result], 0
    jne .Lhcr_matrix_bad
    cmp qword ptr [rip + hc_calls], 10
    jne .Lhcr_matrix_bad
    # Clean prechild refusal is FAILED, phase0, no fabricated EOF or native result.
    mov qword ptr [rip + hc_stage], 26
    call hc_reset
    mov dword ptr [rbx + EXT_activation_required], 1
    mov dword ptr [rbx + EXT_host_child_in], 777
    mov qword ptr [rip + hc_mode], 3
    mov rdi, rbx
    mov rsi, -24
    call ext_host_prepared_abort
    cmp eax, -24
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_setup_error], -24
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jne .Lhcr_matrix_bad
    # Owned positive keeper and accepted START cannot enter no-KX shortcut.
    mov qword ptr [rbx + EXT_keeper], 123
    mov rdi, rbx
    mov rsi, -28
    call ext_host_prepared_abort
    cmp rax, -16
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_setup_error], -24
    jne .Lhcr_matrix_bad
    mov qword ptr [rbx + EXT_keeper], 0
    mov dword ptr [rbx + EXT_startaccepted], 1
    mov rdi, rbx
    mov rsi, -28
    call ext_host_prepared_abort
    cmp rax, -22
    jne .Lhcr_matrix_bad
    cmp dword ptr [rbx + EXT_host_setup_error], -24
    jne .Lhcr_matrix_bad
    xor eax, eax
    EPILOGUE
.Lhcr_matrix_bad:
    mov rax, [rip + hc_stage]
    EPILOGUE
.section .rodata
.p2align 3
# Native, local, cleanup, accepted, expected reported result.
hc_results:
.long -125,-28,-5,0,-28
.long -2,-28,-5,0,-2
.long 0,-28,-5,0,-28
.long 7,-28,-5,0,-28
.long 111,-28,-5,0,-28
.long 255,-28,-5,0,-28
.long 0,0,-5,0,-5
.long 7,0,-5,0,7
.long -125,0,-5,0,-125
.long 0,-28,-5,1,-5
.long 7,-28,-5,1,7
.long 0,0,0,0,0
hc_results_end:
