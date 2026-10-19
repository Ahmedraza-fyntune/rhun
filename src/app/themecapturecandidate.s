# Pure resumable first-match lookup over a retained sealed counted candidate view.
.include "rhun.inc"
.include "app/themecapturecandidate.inc"
.section .rodata
tcl_dark: .ascii "rhun-dark"
tcl_light: .ascii "rhun-light"
.text
FN theme_capture_candidate_begin
    xor r8d, r8d
    jmp tcl_begin
FN theme_capture_fallback_begin
    cmp rdx, 1
    ja .Ltcl_bad_leaf
    lea rax, [rip + tcl_dark]
    lea r9, [rip + tcl_light]
    test rdx, rdx
    cmovnz rax, r9
    lea rcx, [rdx + 9]
    mov rdx, rax
    mov r8d, 1
tcl_begin:
    PROLOGUE 64
    test rdi, rdi
    jz .Ltcl_bad
    test rsi, rsi
    jz .Ltcl_bad
    test rdx, rdx
    jz .Ltcl_bad
    cmp rcx, 4096
    ja .Ltcl_long
    mov [rsp], rdi
    mov [rsp + 8], r8
    mov [rsp + 48], rdx
    mov [rsp + 56], rcx
    lea rdi, [rsp + 16]
    mov edx, TCNR_SIZE
    call memcpy
    mov r12, [rsp + 16]
    mov r13, [rsp + 24]
    cmp r13, TCL_ROW_CAP
    ja .Ltcl_large
    mov r14, [rsp + 32]
    cmp qword ptr [rsp + 40], 0
    jle .Ltcl_bad
    test r13, r13
    jz 1f
    test r12, r12
    jz .Ltcl_bad
    mov rax, r13
    shl rax, 4
    add rax, r12
    jc .Ltcl_bad
    cmp r14, -1
    je 2f
    cmp r14, r13
    jae .Ltcl_bad
    jmp 2f
1:  cmp r14, -1
    jne .Ltcl_bad
2:  cmp qword ptr [rsp + 8], 0
    jne 3f
    mov rdi, [rsp + 48]
    mov rsi, [rsp + 56]
    call theme_capture_omarchy_alias
    test rdx, rdx
    js .Ltcl_bad
    mov [rsp + 48], rax
    mov [rsp + 56], rdx
3:  mov rbx, [rsp]
    mov rdi, rbx
    xor esi, esi
    mov edx, TCL_SIZE
    call memset
    mov [rbx + TCL_rows], r12
    mov [rbx + TCL_count], r13
    mov [rbx + TCL_follow], r14
    mov rax, [rsp + 40]
    mov [rbx + TCL_epoch], rax
    mov rax, [rsp + 48]
    mov [rbx + TCL_query], rax
    mov rax, [rsp + 56]
    mov [rbx + TCL_query_length], rax
    mov rax, [rsp + 8]
    mov [rbx + TCL_kind], rax
    mov qword ptr [rbx + TCL_result], -11
    test r13, r13
    jz 4f
    cmp qword ptr [rbx + TCL_query_length], TCL_ID_CAP
    jbe 5f
4:  mov qword ptr [rbx + TCL_state], TCL_DONE
    mov qword ptr [rbx + TCL_result], -2
5:  xor eax, eax
    EPILOGUE
.Ltcl_bad:
    mov rax, -22
    EPILOGUE
.Ltcl_large:
    mov rax, -7
    EPILOGUE
.Ltcl_long:
    mov rax, -36
    EPILOGUE
.Ltcl_bad_leaf:
    mov rax, -22
    ret

# step(cursor,exactEpoch,budget1..65536)->pending/done/error, actual payload bytes, fixed units.
FN theme_capture_candidate_step
    test rdi, rdi
    jz .Ltcl_step_bad_leaf
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + TCL_bytes], 0
    mov qword ptr [rbx + TCL_units], 0
    test rdx, rdx
    jz .Ltcls_bad
    cmp rdx, 65536
    ja .Ltcls_bad
    cmp qword ptr [rbx + TCL_state], TCL_DONE
    je .Ltcls_done
    cmp qword ptr [rbx + TCL_state], TCL_FAILED
    je .Ltcls_failed
    cmp qword ptr [rbx + TCL_state], TCL_PENDING
    jne .Ltcls_bad
    test rsi, rsi
    jle .Ltcls_stale
    cmp [rbx + TCL_epoch], rsi
    jne .Ltcls_stale
    mov r12, rdx
    mov r13d, 16
.Ltcls_row:
    cmp qword ptr [rbx + TCL_loaded], 0
    jne .Ltcls_compare
    test r13, r13
    jz .Ltcls_pending
    dec r13
    inc qword ptr [rbx + TCL_units]
    mov rax, [rbx + TCL_index]
    cmp rax, [rbx + TCL_count]
    jae .Ltcls_absent
    shl rax, 4
    add rax, [rbx + TCL_rows]
    mov rcx, [rax]
    mov rdx, [rax + 8]
    test rcx, rcx
    jz .Ltcls_invalid_row
    cmp rdx, TCL_ID_CAP
    ja .Ltcls_long_row
    mov [rbx + TCL_current], rcx
    mov [rbx + TCL_length], rdx
    mov qword ptr [rbx + TCL_loaded], 1
    mov qword ptr [rbx + TCL_offset], 0
    mov qword ptr [rbx + TCL_has_held], 0
    cmp rdx, [rbx + TCL_query_length]
    jne .Ltcls_next
    test rdx, rdx
    jz .Ltcls_match
.Ltcls_compare:
    test r12, r12
    jz .Ltcls_pending
    test r13, r13
    jz .Ltcls_pending
    dec r13
    inc qword ptr [rbx + TCL_units]
    mov r14d, 4096
    cmp r14, r12
    cmova r14, r12
.Ltcls_byte:
    mov rcx, [rbx + TCL_offset]
    cmp qword ptr [rbx + TCL_has_held], 0
    jne .Ltcls_candidate_byte
    mov rax, [rbx + TCL_query]
    movzx eax, byte ptr [rax + rcx]
    dec r12
    dec r14
    inc qword ptr [rbx + TCL_bytes]
    test eax, eax
    jz .Ltcls_invalid_row
    mov [rbx + TCL_held], rax
    mov qword ptr [rbx + TCL_has_held], 1
    test r14, r14
    jz .Ltcls_compare
.Ltcls_candidate_byte:
    mov rax, [rbx + TCL_current]
    movzx eax, byte ptr [rax + rcx]
    dec r12
    dec r14
    inc qword ptr [rbx + TCL_bytes]
    test eax, eax
    jz .Ltcls_invalid_row
    cmp rax, [rbx + TCL_held]
    jne .Ltcls_next
    mov qword ptr [rbx + TCL_has_held], 0
    inc qword ptr [rbx + TCL_offset]
    mov rax, [rbx + TCL_offset]
    cmp rax, [rbx + TCL_length]
    je .Ltcls_match
    test r14, r14
    jnz .Ltcls_byte
    jmp .Ltcls_compare
.Ltcls_next:
    inc qword ptr [rbx + TCL_index]
    mov qword ptr [rbx + TCL_loaded], 0
    mov qword ptr [rbx + TCL_current], 0
    mov qword ptr [rbx + TCL_length], 0
    mov qword ptr [rbx + TCL_has_held], 0
    jmp .Ltcls_row
.Ltcls_match:
    mov rax, [rbx + TCL_index]
    cmp qword ptr [rbx + TCL_kind], 0
    jne 1f
    cmp rax, [rbx + TCL_follow]
    jne 1f
    mov qword ptr [rbx + TCL_self], 1
    mov rax, -2
1:  mov [rbx + TCL_result], rax
    mov qword ptr [rbx + TCL_state], TCL_DONE
.Ltcls_done:
    xor eax, eax
    jmp .Ltcls_return
.Ltcls_absent:
    mov qword ptr [rbx + TCL_result], -2
    mov qword ptr [rbx + TCL_state], TCL_DONE
    jmp .Ltcls_done
.Ltcls_pending:
    mov eax, 1
    jmp .Ltcls_return
.Ltcls_stale:
    mov rax, -116
    jmp .Ltcls_set_error
.Ltcls_invalid_row:
    mov rax, -22
    jmp .Ltcls_set_error
.Ltcls_long_row:
    mov rax, -36
.Ltcls_set_error:
    mov [rbx + TCL_result], rax
    mov qword ptr [rbx + TCL_state], TCL_FAILED
    jmp .Ltcls_return
.Ltcls_failed:
    mov rax, [rbx + TCL_result]
    jmp .Ltcls_return
.Ltcls_bad:
    mov rax, -22
.Ltcls_return:
    mov rdx, [rbx + TCL_bytes]
    mov rcx, [rbx + TCL_units]
    EPILOGUE
.Ltcl_step_bad_leaf:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
FN theme_capture_candidate_cancel
    test rdi, rdi
    jz .Ltcl_bad_leaf
    mov qword ptr [rdi + TCL_rows], 0
    mov qword ptr [rdi + TCL_query], 0
    mov qword ptr [rdi + TCL_current], 0
    mov qword ptr [rdi + TCL_has_held], 0
    mov qword ptr [rdi + TCL_state], TCL_FAILED
    mov qword ptr [rdi + TCL_result], -125
    mov qword ptr [rdi + TCL_bytes], 0
    mov qword ptr [rdi + TCL_units], 0
    xor eax, eax
    ret
FN theme_capture_candidate_status
    test rdi, rdi
    jz .Ltcl_bad_leaf
    test rsi, rsi
    jz .Ltcl_bad_leaf
    mov rax, [rdi + TCL_state]
    cmp rax, TCL_FAILED
    ja .Ltcl_bad_leaf
    test rax, rax
    setnz al
    movzx eax, al
    mov [rsi], rax
    mov rax, [rdi + TCL_result]
    mov [rsi + 8], rax
    mov rax, [rdi + TCL_self]
    mov [rsi + 16], rax
    xor eax, eax
    ret
