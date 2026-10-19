# Caller holds both owners and grants this cursor exclusive destination key-input mutation.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/commandgeneration.inc"
.include "app/keylinesnapshot.inc"
.text
FN keyline_snapshot_copy_begin
    xor r8d, r8d
    jmp keyline_copy_begin
FN keyline_copy_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r15, rdx
    mov r14, r8
    test r15, r15
    jz .Lkscb_invalid
    mov rsi, r14
    call keyline_copy_source
    test rax, rax
    jnz .Lkscb_return
    mov rdi, r12
    call cg_active
    test rax, rax
    jnz .Lkscb_return
    mov rax, [r12 + PO_error]
    test rax, rax
    jnz .Lkscb_return
    cmp qword ptr [r12 + CG_phase], CG_INPUT
    jne .Lkscb_invalid
    cmp qword ptr [r12 + CG_nkeys], 0
    jne .Lkscb_invalid
    cmp qword ptr [r12 + CG_openkey], 0
    jne .Lkscb_invalid
    xor ecx, ecx
1:  cmp qword ptr [r15 + rcx*8], 0
    jne .Lkscb_invalid
    inc rcx
    cmp rcx, 8
    jb 1b
    mov [r15 + KSC_ksi], rbx
    mov [r15 + KSC_cg], r12
    mov qword ptr [r15 + KSC_phase], KSI_ROW
    mov [r15 + KSC_kind], r14
    xor eax, eax
.Lkscb_return:
    EPILOGUE
.Lkscb_invalid:
    mov rax, -22
    EPILOGUE
# cursor64,budget1..16 ->1pending/0done/-errno, RDXunits. Allocations end this call.
FN keyline_snapshot_copy_step
    PROLOGUE 32
    mov r15, rdi
    mov r12, rsi
    xor r14d, r14d
    test r15, r15
    jz .Lksc_invalid
    lea rax, [rsi - 1]
    cmp rax, 15
    ja .Lksc_invalid
    cmp qword ptr [r15 + KSC_done], 1
    je .Lksc_done
    cmp qword ptr [r15 + KSC_done], 0
    jne .Lksc_bad
    mov rax, [r15 + KSC_error]
    test rax, rax
    jnz .Lksc_return
.Lksc_loop:
    mov rbx, [r15 + KSC_ksi]
    mov r13, [r15 + KSC_cg]
    mov rdi, rbx
    mov rsi, [r15 + KSC_kind]
    call keyline_copy_source
    test rax, rax
    jnz .Lksc_fail
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov rdi, r13
    call cg_active
    test rax, rax
    jnz .Lksc_fail
    mov rax, [r13 + PO_error]
    test rax, rax
    jnz .Lksc_fail
    cmp qword ptr [r13 + CG_phase], CG_INPUT
    jne .Lksc_bad
    mov rax, [r15 + KSC_row]
    cmp [r13 + CG_nkeys], rax
    jne .Lksc_bad
    inc r14
    cmp rax, [rsp + 16]
    ja .Lksc_bad
    je .Lksc_finish_all
    shl rax, 5
    add rax, [rsp + 24]
    mov [rsp], rax
    mov rdx, [r15 + KSC_phase]
    cmp rdx, KSI_ROW
    je .Lksc_begin_row
    cmp qword ptr [r13 + CG_openkey], 0
    je .Lksc_bad
    mov rcx, [rax + 8]
    cmp [r13 + CG_combolen], rcx
    jne .Lksc_bad
    mov rsi, [rax + 24]
    cmp [r13 + CG_commandlen], rsi
    jne .Lksc_bad
    cmp rdx, KSI_COMBO
    je .Lksc_combo
    cmp rdx, KSI_COMMAND
    je .Lksc_command
    cmp rdx, KSI_FINISH
    jne .Lksc_bad
    cmp qword ptr [r15 + KSC_offset], 0
    jne .Lksc_bad
    add rcx, rsi
    cmp [r13 + CG_keycursor], rcx
    jne .Lksc_bad
    mov rdi, r13
    call command_generation_key_finish
    test rax, rax
    jnz .Lksc_fail
    inc qword ptr [r15 + KSC_row]
    mov qword ptr [r15 + KSC_phase], KSI_ROW
    jmp .Lksc_next
.Lksc_begin_row:
    cmp qword ptr [r13 + CG_openkey], 0
    jne .Lksc_bad
    cmp qword ptr [r15 + KSC_offset], 0
    jne .Lksc_bad
    mov rsi, [rax + 8]
    mov rdx, [rax + 24]
    mov rdi, r13
    call command_generation_key_begin
    test rax, rax
    jnz .Lksc_fail
    mov qword ptr [r15 + KSC_phase], KSI_COMBO
    jmp .Lksc_pending
.Lksc_combo:
    mov rdx, [r15 + KSC_offset]
    cmp rdx, rcx
    ja .Lksc_bad
    cmp [r13 + CG_keycursor], rdx
    jne .Lksc_bad
    mov rsi, [rax]
    mov rcx, [rax + 8]
    jmp .Lksc_append
.Lksc_command:
    mov rdx, [r15 + KSC_offset]
    cmp rdx, rsi
    ja .Lksc_bad
    add rcx, rdx
    cmp [r13 + CG_keycursor], rcx
    jne .Lksc_bad
    mov rsi, [rax + 16]
    mov rcx, [rax + 24]
.Lksc_append:
    sub rcx, rdx
    jz .Lksc_skip
    add rsi, rdx
    mov edx, 4096
    cmp rcx, rdx
    cmova rcx, rdx
    mov rdx, rcx
    mov [rsp + 8], rcx
    mov rdi, r13
    call command_generation_key_append
    test rax, rax
    jnz .Lksc_fail
    mov rax, [rsp + 8]
    add [r15 + KSC_offset], rax
    jmp .Lksc_next
.Lksc_skip:
    inc qword ptr [r15 + KSC_phase]
    mov qword ptr [r15 + KSC_offset], 0
.Lksc_next:
    cmp r14, r12
    jb .Lksc_loop
.Lksc_pending:
    mov eax, 1
    jmp .Lksc_return
.Lksc_finish_all:
    cmp qword ptr [r15 + KSC_phase], KSI_ROW
    jne .Lksc_bad
    cmp qword ptr [r13 + CG_openkey], 0
    jne .Lksc_bad
    mov qword ptr [r15 + KSC_done], 1
.Lksc_done:
    xor eax, eax
    jmp .Lksc_return
.Lksc_bad:
    mov rax, -22
.Lksc_fail:
    cmp qword ptr [r15 + KSC_error], 0
    jne 1f
    mov [r15 + KSC_error], rax
1:  mov rax, [r15 + KSC_error]
    jmp .Lksc_return
.Lksc_invalid:
    mov rax, -22
.Lksc_return:
    mov rdx, r14
    EPILOGUE
