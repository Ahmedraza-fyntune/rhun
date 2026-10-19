.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.section .rodata
saf_pinned: .ascii "pinned"
saf_disabled: .ascii "disabled"
.text
# Internal view,model,key,len,base ->boolean or negative error.
settings_flag_value:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, r8
    mov r8, rcx
    mov rcx, rdx
    mov rdi, [rip + esv_service_queue]
    mov rsi, [rbx + EV_section]
    mov rdx, [rbx + EV_seclen]
    call ext_settings_queue_find
    test rax, rax
    jz .Lsaf_base
    mov rbx, rax
    mov rax, [rbx + EQC_seq]
    test rax, rax
    jle .Lsaf_stale
    mov rcx, [rip + esv_service_queue]
    cmp rax, [rcx + EQ_seq]
    ja .Lsaf_stale
    cmp rax, [r12 + ELM_sequence]
    jbe .Lsaf_base
    cmp qword ptr [rbx + EC_remove], 0
    je .Lsaf_value
    cmp qword ptr [rbx + EC_remove], 1
    jne .Lsaf_bad
    xor eax, eax
    EPILOGUE
.Lsaf_value:
    mov rdx, [rbx + EC_value]
    test rdx, rdx
    jz .Lsaf_bad
    mov rcx, [rbx + EC_vallen]
    cmp rcx, 3
    jne 1f
    cmp dword ptr [rdx], 0x00736579
    jne .Lsaf_bad
    mov eax, 1
    EPILOGUE
1:  cmp rcx, 2
    jne .Lsaf_bad
    cmp word ptr [rdx], 0x6f6e
    jne .Lsaf_bad
    cmp byte ptr [rdx + 2], 0
    jne .Lsaf_bad
    xor eax, eax
    EPILOGUE
.Lsaf_base:
    mov rax, r13
    EPILOGUE
.Lsaf_bad:
    mov rax, -22
    EPILOGUE
.Lsaf_stale:
    mov rax, -116
    EPILOGUE

# slot,exactEP ->RAX pinned,RDX disabled,RCXerror.
FN ext_settings_effective_flags
    PROLOGUE
    call settings_active_view
    test rax, rax
    jz .Lsaf_refusal
    mov r13, rax
    mov r14, r8
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + saf_pinned]
    mov ecx, 6
    mov r8, [r13 + EV_pinned]
    call settings_flag_value
    test rax, rax
    js .Lsaf_error
    mov r12, rax
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + saf_disabled]
    mov ecx, 8
    mov r8, [r13 + EV_disabled]
    call settings_flag_value
    test rax, rax
    js .Lsaf_error
    mov rdx, rax
    mov rax, r12
    xor ecx, ecx
    EPILOGUE
.Lsaf_error:
    mov rdx, rax
.Lsaf_refusal:
    mov rcx, rdx
    xor eax, eax
    xor edx, edx
    EPILOGUE
