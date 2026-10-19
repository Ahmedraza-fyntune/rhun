# Single-attempt endpoint cleanup, preserving consumed and unknown ownership.
.include "rhun.inc"
.text
# EXT,index0..4 -> native status, RDX1 consumed/0 retained/2 unknown.
FN ext_host_close_field
    test rdi, rdi
    jz .Lhcf_bad
    cmp rsi, 5
    jae .Lhcf_bad
    mov rdx, rsi
    lea rax, [rip + ehc_fields]
    mov rax, [rax + rdx*8]
    lea rsi, [rdi + rax]
    jmp ext_host_close_at
.Lhcf_bad:
    mov rax, -22
    xor edx, edx
    ret

# Only a known-unconsumed blocked field can be explicitly attempted once more.
FN ext_host_retry_known
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Lhcr_bad
    cmp r12, 5
    jae .Lhcr_bad
    mov eax, [rbx + EXT_host_cleanup_mask]
    bt eax, r12d
    jc .Lhcr_unknown
    lea ecx, [r12 + 8]
    bt eax, ecx
    jnc .Lhcr_bad
    btr dword ptr [rbx + EXT_host_cleanup_mask], ecx
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    EPILOGUE
.Lhcr_unknown:
    movsxd rax, dword ptr [rbx + EXT_host_cleanup_error]
    test rax, rax
    js 1f
    mov rax, -5
1:  mov edx, 2
    EPILOGUE
.Lhcr_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.section .rodata
.p2align 3
ehc_fields: .quad EXT_in, EXT_out, EXT_log, EXT_host_child_in, EXT_host_child_out
