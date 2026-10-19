# Prepare a protected current-user file DACL before stage creation. No fallback to inheritance.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extchoicesdisk.inc"
.ifdef WINDOWS
.section .rodata
.Lecsec_prefix: .asciz "D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;"
.endif
.text
# security_prepare(ECP)->0/-errno; all successfully acquired resources remain ECP-owned.
FN ext_choices_security_prepare
.ifdef WINDOWS
    PROLOGUE 1280
    mov rbx, rdi
    mov rcx, -1
    mov edx, 8                # TOKEN_QUERY
    lea r8, [rbx + ECP_token]
    API OpenProcessToken
    test eax, eax
    jz .Lecsec_error
    mov rcx, [rbx + ECP_token]
    mov edx, 1                # TokenUser, maximum SID size fits the128-byte buffer.
    lea r8, [rsp + 96]
    mov r9d, 128
    lea rax, [rsp + 224]
    mov [rsp + 32], rax
    API GetTokenInformation
    test eax, eax
    jz .Lecsec_error
    mov rcx, [rsp + 96]
    lea rdx, [rbx + ECP_sid]
    API ConvertSidToStringSidW
    test eax, eax
    jz .Lecsec_error
    lea rsi, [rip + .Lecsec_prefix]
    lea rdi, [rsp + 256]
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    mov word ptr [rdi + rcx*2], ax
    inc rcx
    jmp 1b
2:  lea rdi, [rdi + rcx*2]
    mov rsi, [rbx + ECP_sid]
    xor ecx, ecx
3:  movzx eax, word ptr [rsi + rcx*2]
    test eax, eax
    jz 4f
    mov word ptr [rdi + rcx*2], ax
    inc rcx
    cmp rcx, 256
    jb 3b
    mov rax, -7
    EPILOGUE
4:  mov word ptr [rdi + rcx*2], ')'
    mov word ptr [rdi + rcx*2 + 2], 0
    lea rcx, [rsp + 256]
    mov edx, 1                # SDDL_REVISION_1
    lea r8, [rbx + ECP_security]
    xor r9d, r9d
    API ConvertStringSecurityDescriptorToSecurityDescriptorW
    test eax, eax
    jz .Lecsec_error
    xor eax, eax
    EPILOGUE
.Lecsec_error:
    call win_error
    EPILOGUE
.else
    xor eax, eax
    ret
.endif

# security_free(ECP)->0/-errno; failed LocalFree retains that pointer for a later step.
FN ext_choices_security_free
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, rdi
    xor r12d, r12d
    mov rcx, [rbx + ECP_security]
    test rcx, rcx
    jz 2f
    API LocalFree
    test rax, rax
    jz 1f
    call win_error
    mov r12, rax
    jmp 2f
1:  mov qword ptr [rbx + ECP_security], 0
2:  mov rcx, [rbx + ECP_sid]
    test rcx, rcx
    jz 4f
    API LocalFree
    test rax, rax
    jz 3f
    test r12, r12
    jnz 4f
    call win_error
    mov r12, rax
    jmp 4f
3:  mov qword ptr [rbx + ECP_sid], 0
4:  mov rcx, [rbx + ECP_token]
    test rcx, rcx
    jz 5f
    mov qword ptr [rbx + ECP_token], 0
    API CloseHandle
    test eax, eax
    jnz 5f
    test r12, r12
    jnz 5f
    call win_error
    mov r12, rax
5:  mov rax, r12
    EPILOGUE
.else
    xor eax, eax
    ret
.endif
