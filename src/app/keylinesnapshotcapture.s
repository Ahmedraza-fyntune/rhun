.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/keycombo.inc"
.include "app/keylinesnapshot.inc"
.text
# Reacquire source by epoch and row index. No borrowed row pointer survives a step call.
FN ksi_source_check
    PROLOGUE
    mov rbx, rdi
    call config_key_source_epoch
    test rdx, rdx
    jnz 8f
    test rax, rax
    jle 8f
    cmp [rbx + KSI_epoch], rax
    jne 8f
    call ksi_source_shape
    test rdx, rdx
    jnz 8f
    cmp [rbx + KSI_nrows], rax
    jne 8f
    xor eax, eax
    EPILOGUE
8:  mov rax, -116
    EPILOGUE
# KSI,budget1..16 ->1pending/0ready/-errno, RDXactual units.
FN keyline_snapshot_step
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    xor r14d, r14d
    lea rax, [rsi - 1]
    cmp rax, 15
    ja .Lkss_invalid
    call ksi_active
    test rax, rax
    jnz .Lkss_return
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz .Lkss_return
    cmp qword ptr [rbx + PO_ready], 1
    je .Lkss_ready
.Lkss_loop:
    mov rdi, rbx
    call ksi_source_check
    test rax, rax
    jnz .Lkss_fail
    inc r14
    mov rax, [rbx + KSI_row]
    cmp rax, [rbx + KSI_nrows]
    ja .Lkss_bad
    je .Lkss_finish_all
    shl rax, 5
    lea r13, [rbx + rax + KSI_rows]
    add rax, [rip + g_keylines + VEC_ptr]
    mov r15, rax
    mov rax, [rbx + KSI_phase]
    cmp rax, KSI_ROW
    je .Lkss_allocate
    cmp rax, KSI_COMBO
    je .Lkss_copy_combo
    cmp rax, KSI_COMMAND
    je .Lkss_copy_command
    cmp rax, KSI_FINISH
    jne .Lkss_bad
    mov rax, [rbx + KSI_open]
    test rax, rax
    jz .Lkss_bad
    mov [r13], rax
    add rax, [r13 + 8]
    inc rax
    mov [r13 + 16], rax
    mov qword ptr [rbx + KSI_open], 0
    mov qword ptr [rbx + KSI_offset], 0
    mov qword ptr [rbx + KSI_phase], KSI_ROW
    inc qword ptr [rbx + KSI_row]
    jmp .Lkss_next
.Lkss_allocate:
    mov rax, [r15 + 8]
    cmp rax, KC_CAP
    ja .Lkss_resource
    mov rcx, [r15 + 24]
    cmp rcx, KC_CAP
    ja .Lkss_resource
    mov [rsp], rax
    mov [rsp + 8], rcx
    add rax, rcx
    jc .Lkss_resource
    add rax, [rbx + KSI_bytes]
    jc .Lkss_resource
    cmp rax, KSI_MAX_BYTES
    ja .Lkss_resource
    mov [rsp + 16], rax
    mov rsi, [rsp]
    add rsi, [rsp + 8]
    add rsi, 2
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lkss_alloc_error
    mov [rbx + KSI_open], rax
    mov rax, [rsp]
    mov [r13 + 8], rax
    mov rax, [rsp + 8]
    mov [r13 + 24], rax
    mov rax, [rsp + 16]
    mov [rbx + KSI_bytes], rax
    mov qword ptr [rbx + KSI_phase], KSI_COMBO
    mov qword ptr [rbx + KSI_offset], 0
    jmp .Lkss_pending
.Lkss_copy_combo:
    mov rsi, [r15]
    mov rdx, [r15 + 8]
    cmp [r13 + 8], rdx
    jne .Lkss_bad
    mov rdi, [rbx + KSI_open]
    jmp .Lkss_copy
.Lkss_copy_command:
    mov rsi, [r15 + 16]
    mov rdx, [r15 + 24]
    cmp [r13 + 24], rdx
    jne .Lkss_bad
    mov rdi, [rbx + KSI_open]
    test rdi, rdi
    jz .Lkss_bad
    add rdi, [r13 + 8]
    inc rdi
.Lkss_copy:
    test rdi, rdi
    jz .Lkss_bad
    mov rax, [rbx + KSI_offset]
    cmp rax, rdx
    ja .Lkss_bad
    je .Lkss_skip
    test rsi, rsi
    jz .Lkss_bad
    mov rcx, rsi
    add rcx, rdx
    jc .Lkss_bad
    sub rdx, rax
    mov ecx, 4096
    cmp rdx, rcx
    cmova rdx, rcx
    add rdi, rax
    add rsi, rax
    mov [rsp], rdx
    call memcpy
    mov rax, [rsp]
    add [rbx + KSI_offset], rax
    jmp .Lkss_next
.Lkss_skip:
    inc qword ptr [rbx + KSI_phase]
    mov qword ptr [rbx + KSI_offset], 0
.Lkss_next:
    cmp r14, r12
    jb .Lkss_loop
.Lkss_pending:
    mov eax, 1
    jmp .Lkss_return
.Lkss_finish_all:
    cmp qword ptr [rbx + KSI_open], 0
    jne .Lkss_bad
    cmp qword ptr [rbx + KSI_phase], KSI_ROW
    jne .Lkss_bad
    mov qword ptr [rbx + KSI_phase], KSI_READY
    mov qword ptr [rbx + PO_ready], 1
.Lkss_ready:
    xor eax, eax
    jmp .Lkss_return
.Lkss_alloc_error:
    mov rax, [rbx + PO_error]
    jmp .Lkss_fail
.Lkss_resource:
    mov rax, -EV_RESOURCE
    jmp .Lkss_fail
.Lkss_bad:
    mov rax, -22
.Lkss_fail:
    cmp qword ptr [rbx + PO_error], 0
    jne 1f
    mov [rbx + PO_error], rax
1:  mov rax, [rbx + PO_error]
    jmp .Lkss_return
.Lkss_invalid:
    mov rax, -22
.Lkss_return:
    mov rdx, r14
    EPILOGUE
