# Checked native slot close. Native callers own the exact indexed host slot.
.include "rhun.inc"
.text
# EXT, owned FD slot, index0..4 -> status, RDX consumed1/retained0/unknown2.
FN ext_host_close_at
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rsi
    test rbx, rbx
    jz .Lhcf_bad
    test r13, r13
    jz .Lhcf_bad
    test r13b, 3
    jnz .Lhcf_bad
    cmp r12, 5
    jae .Lhcf_bad
    mov eax, [rbx + EXT_host_cleanup_mask]
    bt eax, r12d
    jc .Lhcf_unknown
    lea ecx, [r12 + 8]
    bt eax, ecx
    jc .Lhcf_known
    mov edi, [r13]
    test edi, edi
    js .Lhcf_consumed
    call ext_fd_close_checked
    mov r14, rax
    mov r15, rdx
    cmp r15, 2
    jbe 1f
    mov r15d, 2
1:  cmp r15, 1
    je 2f
    test r14, r14
    js 2f
    mov r14, -5
2:  test r14, r14
    jns 3f
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jne 3f
    mov [rbx + EXT_host_cleanup_error], r14d
3:  cmp r15, 1
    jne 4f
    mov dword ptr [r13], -1
    jmp .Lhcf_result
4:  mov rax, r12
    cmp r15, 2
    je 5f
    add eax, 8
5:  bts dword ptr [rbx + EXT_host_cleanup_mask], eax
.Lhcf_result:
    mov rax, r14
    mov rdx, r15
    EPILOGUE
.Lhcf_unknown:
    mov edx, 2
    jmp .Lhcf_saved
.Lhcf_known:
    xor edx, edx
.Lhcf_saved:
    movsxd rax, dword ptr [rbx + EXT_host_cleanup_error]
    test rax, rax
    js 6f
    mov rax, -5
6:  EPILOGUE
.Lhcf_consumed:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lhcf_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE

