# Actual GP borrow used independently for every API/state transition.
.bss
.p2align 3
api_export: .skip PGE_SIZE
api_export_copy: .skip PGE_SIZE
api_req: .skip 40
api_out: .skip 80
.text
FN xfer_export_api_matrix
    PROLOGUE
    lea rdi, [rip + api_export]
    mov esi, 0xa5
    mov edx, PGE_SIZE
    call memset
    mov qword ptr [rip + api_export + PGE_state], PGE_NEW
    mov [rip + api_req], r14
    mov rax, [r14 + GP_legacy]
    inc rax
    mov [rip + api_req + 8], rax
    mov [rip + api_req + 16], r12
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + probe_cases]
    mov rax, [rcx + rax + 8]
    mov [rip + api_req + 24], rax
    mov qword ptr [rip + api_req + 32], 0
    xor r13d, r13d
.Lxapi_state:
    cmp r13, 5
    jae .Lxapi_done
    test r13, r13
    jz .Lxapi_ready
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_req]
    call pg_export_begin
    test rax, rax
    jne .Lxpe_fail
    cmp r13, PGE_MEASURE
    je .Lxapi_ready
.Lxapi_measure:
    lea rdi, [rip + api_export]
    mov esi, 65536
    call pg_export_measure_step
    test rax, rax
    js .Lxpe_fail
    jnz .Lxapi_measure
    cmp r13, PGE_SIZED
    je .Lxapi_ready
.Lxapi_emit:
    lea rdi, [rip + api_export]
    lea rsi, [rip + output]
    mov edx, 1
    mov ecx, 2
    call pg_export_emit_step
    test rax, rax
    js .Lxpe_fail
    cmp r13, PGE_EMIT
    je .Lxapi_ready
    test rax, rax
    jnz .Lxapi_emit
.Lxapi_ready:
    cmp [rip + api_export + PGE_state], r13
    jne .Lxpe_fail
    lea rdi, [rip + api_export_copy]
    lea rsi, [rip + api_export]
    mov edx, PGE_SIZE
    call memcpy
    # Every structural refusal preserves the complete native context.
    lea rdi, [rip + api_export]
    xor esi, esi
    call pg_export_measure_step
    cmp rax, -22
    jne .Lxpe_fail
    or rdx, rcx
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    mov esi, 65537
    call pg_export_measure_step
    cmp rax, -22
    jne .Lxpe_fail
    or rdx, rcx
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    lea rsi, [rip + output]
    xor edx, edx
    mov ecx, 2
    call pg_export_emit_step
    cmp rax, -22
    jne .Lxpe_fail
    or rdx, rcx
    or rdx, r8
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    lea rsi, [rip + output]
    mov edx, 1
    mov ecx, 1
    call pg_export_emit_step
    cmp rax, -22
    jne .Lxpe_fail
    or rdx, rcx
    or rdx, r8
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_export + 1]
    mov edx, 1
    mov ecx, 2
    call pg_export_emit_step
    cmp rax, -22
    jne .Lxpe_fail
    or rdx, rcx
    or rdx, r8
    jnz .Lxpe_fail
    lea rdi, [rip + api_export_copy]
    lea rsi, [rip + api_export]
    mov edx, PGE_SIZE
    call memeq
    test eax, eax
    jz .Lxpe_fail
    # Native status/info outputs are untouched on refusal.
    lea rdi, [rip + api_out]
    mov esi, 0xa5
    mov edx, 80
    call memset
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_out]
    call pg_export_status
    mov r15, -22
    test r13, r13
    jz 1f
    xor r15d, r15d
1:  cmp rax, r15
    jne .Lxpe_fail
    test r13, r13
    jnz 2f
    call xfer_api_out_unchanged
2:  lea rdi, [rip + api_out]
    mov esi, 0xa5
    mov edx, 80
    call memset
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_out]
    call pg_export_info
    mov r15, -22
    cmp r13, PGE_SIZED
    jb 3f
    xor r15d, r15d
3:  cmp rax, r15
    jne .Lxpe_fail
    test r15, r15
    jz 4f
    call xfer_api_out_unchanged
4:  test r13, r13
    jnz .Lxapi_cancel
    lea rdi, [rip + api_export]
    call pg_export_cancel
    cmp rax, -22
    jne .Lxpe_fail
    jmp .Lxapi_next
.Lxapi_cancel:
    # A valid active or DONE borrow terminates without releasing the actual GP.
    lea rdi, [rip + api_export]
    call pg_export_cancel
    test rax, rax
    jne .Lxpe_fail
    cmp qword ptr [rip + api_export + PGE_state], PGE_FAILED
    jne .Lxpe_fail
    cmp qword ptr [rip + api_export + PGE_error], -125
    jne .Lxpe_fail
    lea rdi, [rip + api_export]
    call pg_export_cancel
    test rax, rax
    jne .Lxpe_fail
    lea rdi, [rip + api_export]
    mov esi, 1
    call pg_export_measure_step
    cmp rax, -125
    jne .Lxpe_fail
    or rdx, rcx
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    lea rsi, [rip + output]
    mov edx, 1
    mov ecx, 2
    call pg_export_emit_step
    cmp rax, -125
    jne .Lxpe_fail
    or rdx, rcx
    or rdx, r8
    jnz .Lxpe_fail
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_out]
    call pg_export_status
    test rax, rax
    jne .Lxpe_fail
    cmp qword ptr [rip + api_out + 8], -125
    jne .Lxpe_fail
    lea rdi, [rip + api_out]
    mov esi, 0xa5
    mov edx, 80
    call memset
    lea rdi, [rip + api_export]
    lea rsi, [rip + api_out]
    call pg_export_info
    cmp rax, -22
    jne .Lxpe_fail
    call xfer_api_out_unchanged
.Lxapi_next:
    inc r13
    jmp .Lxapi_state
.Lxapi_done:
    EPILOGUE
FN xfer_api_out_unchanged
    lea rax, [rip + api_out]
    mov ecx, 10
1:  mov rdx, 0xa5a5a5a5a5a5a5a5
    cmp [rax], rdx
    jne .Lxpe_fail
    add rax, 8
    dec rcx
    jnz 1b
    ret
