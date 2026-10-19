# Live results may borrow queue cells. Copy before any mutation or yield.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingscatalog.inc"
.text
# slot,exact readyEP,index -> canonical borrow/NULL,RDXerror,RCXlength.
FN ext_settings_effective_value
    PROLOGUE 272
    mov r12, rdx
    mov r13, rsi
    call settings_active_view
    test rax, rax
    jz .Lsev_refusal
    mov rbx, rax
    mov r14, r8
    cmp r12, [rbx + EV_count]
    jae .Lsev_invalid
    imul rax, r12, EVR_SIZE
    lea r15, [rbx + EV_rows + rax]
    mov rcx, [r15 + EVR_keylen]
    test rcx, rcx
    jz .Lsev_invalid
    cmp rcx, 248
    ja .Lsev_model
    mov rax, 0x2e676e6974746573
    mov [rsp], rax
    lea rdi, [rsp + 8]
    mov rsi, [r15 + EVR_key]
    mov rdx, rcx
    call memcpy
    mov rdi, [rip + esv_service_queue]
    mov rsi, [rbx + EV_section]
    mov rdx, [rbx + EV_seclen]
    mov rcx, rsp
    mov r8, [r15 + EVR_keylen]
    add r8, 8
    call ext_settings_queue_find
    test rax, rax
    jz .Lsev_model
    mov rbx, rax
    mov rax, [rbx + EQC_seq]
    test rax, rax
    jle .Lsev_stale
    mov rcx, [rip + esv_service_queue]
    cmp rax, [rcx + EQ_seq]
    ja .Lsev_stale
    cmp rax, [r14 + ELM_sequence]
    jbe .Lsev_model
    cmp qword ptr [rbx + EC_remove], 0
    je .Lsev_new_value
    cmp qword ptr [rbx + EC_remove], 1
    jne .Lsev_invalid
    mov rax, [r15 + EVR_base]
    mov rcx, [r15 + EVR_baselen]
    xor edx, edx
    EPILOGUE
.Lsev_new_value:
    mov rdi, r13
    mov rsi, r12
    mov rdx, [rbx + EC_value]
    mov rcx, [rbx + EC_vallen]
    mov r8, [r15 + EVR_keylen]
    call ext_settings_canonical_value
    test rax, rax
    jnz .Lsev_error
    mov rax, [rbx + EC_value]
    mov rcx, [rbx + EC_vallen]
    xor edx, edx
    EPILOGUE
.Lsev_model:
    mov rax, [r15 + EVR_value]
    mov rcx, [r15 + EVR_vallen]
    xor edx, edx
    EPILOGUE
.Lsev_invalid:
    mov rax, -22
    jmp .Lsev_error
.Lsev_stale:
    mov rax, -116
.Lsev_error:
    mov rdx, rax
.Lsev_refusal:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
