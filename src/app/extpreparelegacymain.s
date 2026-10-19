# Isolated initial legacy snapshot, before app_init and with inherited-anchor close before output.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extpreparelegacy.inc"
.text
FN ext_legacy_snapshot_anchored_main
    PROLOGUE 304
    mov rbx, rsi
    mov r12, -1
    mov r13, -EV_USAGE
    xor r14d, r14d
    mov [rsp + 288], rdi
    mov rdi, rsp
    xor esi, esi
    mov edx, 288
    call memset
    mov rax, 0x00003153534c4852
    mov [rsp], rax
    mov dword ptr [rsp + 8], 1
    mov dword ptr [rsp + 12], LS_HEADER
    mov qword ptr [rsp + LS_total], LS_HEADER
    cmp qword ptr [rsp + 288], 10
    jne .Lelssa_emit
    mov rdi, [rbx + 8]
    lea rsi, [rip + elss_option]
    call strcmp_eq
    test eax, eax
    jz .Lelssa_emit
    mov rdi, [rbx + 16]
    call prep_legacy_decimal
    test rdx, rdx
    jnz .Lelssa_emit
    test rax, rax
    js .Lelssa_emit
.ifndef WINDOWS
    cmp rax, 0x7fffffff
    ja .Lelssa_emit
.endif
    mov r12, rax
    mov rdi, [rbx + 48]
    call prep_legacy_decimal
    test rdx, rdx
    jnz .Lelssa_close
    test rax, rax
    jz .Lelssa_close
    mov [rsp + LS_tag], rax
    mov rdi, [rbx + 56]
    call prep_legacy_decimal
    test rdx, rdx
    jnz .Lelssa_close
    test rax, rax
    jz .Lelssa_close
    mov [rsp + LS_tag + 8], rax
    mov rdi, [rbx + 64]
    lea rsi, [rsp + LS_tag + 16]
    mov edx, 32
    call prep_legacy_unhex
    test rax, rax
    jnz .Lelssa_close
    mov rdi, r12
    lea rsi, [rsp + LS_tag + 32]
    call ext_root_identity
    test rax, rax
    js .Lelssa_error
    mov rdi, [rbx + 72]
    cmp word ptr [rdi], '-'
    jne .Lelssa_close
    call ext_store_job_legacy_child_context
    test rax, rax
    js .Lelssa_error
    mov rdi, r12
    mov rsi, [rbx + 24]
    mov rdx, [rbx + 32]
    mov rcx, [rbx + 40]
    lea r8, [rsp + LS_tag]
    lea r9, [rsp + 192]
    call ext_legacy_snapshot_build
    mov r13, rax
    mov r14, rdx
    jmp .Lelssa_close
.Lelssa_error:
    mov r13, rax
.Lelssa_close:
    mov rdi, r12
    mov r12, -1
    call ext_root_close
    test r14, r14
    jnz 2f
    mov r14, rax
2:  test r13, r13
    jnz .Lelssa_emit
    mov r13, r14
.Lelssa_emit:
    mov [rsp + LS_primary], r13
    mov [rsp + LS_secondary], r14
    test r13, r13
    jnz 3f
    test r14, r14
    jnz 3f
    mov edi, 1
    mov rsi, [rsp + 192]
    mov rdx, [rsp + 200]
    jmp 5f
3:  mov edi, 1
    mov rsi, rsp
    mov edx, LS_HEADER
5:  call write_all
    mov r15, rax
    mov rdi, [rsp + 192]
    call mem_free
    test r15, r15
    jnz 4f
    xor eax, eax
    test r13, r13
    setnz al
    EPILOGUE
4:  mov eax, 1
    EPILOGUE

.section .rodata
elss_option: .asciz "--snapshot-legacy-anchored"
