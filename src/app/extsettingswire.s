# Allocation-free fixed frame checks and off-UI counted delta decoding.
.include "rhun.inc"
.include "app/extchoices.inc"
.include "app/extsettingswire.inc"
.text
# encode(header64,descriptor)->0/-errno. No payload bytes are copied.
FN ext_settings_wire_encode
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [r12 + EWE_kind], EW_DISCARDED
    ja .Lew_encode_bad
    mov r13, [r12 + EWE_tag]
    test r13, r13
    jz .Lew_encode_bad
    mov rax, 0x31424f4a43454852 # RHECJOB1
    mov [rbx], rax
    mov dword ptr [rbx + 8], 1
    mov eax, [r12 + EWE_kind]
    mov [rbx + 12], eax
    mov rax, [r13 + EWT_job]
    mov [rbx + 16], rax
    mov rax, [r13 + EWT_context]
    mov [rbx + 24], rax
    mov rax, [r13 + EWT_nonce]
    mov [rbx + 32], rax
    mov rax, [r13 + EWT_nonce + 8]
    mov [rbx + 40], rax
    mov rax, [r12 + EWE_length]
    mov [rbx + 48], rax
    mov rax, [r12 + EWE_round]
    mov [rbx + 56], rax
    mov rdi, rbx
    mov rsi, r13
    call ext_settings_wire_check
    EPILOGUE
.Lew_encode_bad:
    mov rax, -22
    EPILOGUE

# check(header64,tag32)->0/-EPROTO, RDX kind,R8 body length,R9 round on success.
# Constant work only. The caller checks complete body availability and phase legality.
FN ext_settings_wire_check
    mov rax, 0x31424f4a43454852
    cmp [rdi], rax
    jne .Lew_bad
    cmp dword ptr [rdi + 8], 1
    jne .Lew_bad
    mov rax, [rsi + EWT_job]
    test rax, rax
    jle .Lew_bad
    cmp [rdi + 16], rax
    jne .Lew_bad
    mov rax, [rsi + EWT_context]
    test rax, rax
    jle .Lew_bad
    cmp [rdi + 24], rax
    jne .Lew_bad
    mov rax, [rsi + EWT_nonce]
    cmp [rdi + 32], rax
    jne .Lew_bad
    mov rax, [rsi + EWT_nonce + 8]
    cmp [rdi + 40], rax
    jne .Lew_bad
    mov edx, [rdi + 12]
    cmp edx, EW_REQUEST
    jb .Lew_bad
    cmp edx, EW_DISCARDED
    ja .Lew_bad
    mov r8, [rdi + 48]
    cmp r8, EW_LIMIT
    ja .Lew_bad
    mov r9, [rdi + 56]
    cmp r9, 3
    ja .Lew_bad
    cmp edx, EW_REQUEST
    je .Lew_request
    cmp edx, EW_SNAPSHOT
    je .Lew_snapshot
    cmp edx, EW_RESULT
    je .Lew_result
    cmp edx, EW_RELEASE
    je .Lew_empty
    test r9, r9
    jz .Lew_bad
    cmp edx, EW_DELTA
    je .Lew_delta
    cmp edx, EW_PREPARED
    je .Lew_prepared
    cmp edx, EW_COMMITTED
    je .Lew_committed
    cmp edx, EW_DISCARDED
    je .Lew_result
.Lew_empty:
    test r8, r8
    jnz .Lew_bad
    jmp .Lew_ok
.Lew_request:
    test r9, r9
    jnz .Lew_bad
    cmp r8, 56
    jb .Lew_bad
    jmp .Lew_ok
.Lew_snapshot:
    cmp r8, 48
    jb .Lew_bad
    cmp r8, EC_LIMIT + 48
    ja .Lew_bad
    jmp .Lew_ok
.Lew_result:
    cmp r8, 32
    jne .Lew_bad
    jmp .Lew_ok
.Lew_delta:
    cmp r8, 8 + 16
    jb .Lew_bad
    jmp .Lew_ok
.Lew_prepared:
    cmp r8, 48
    jne .Lew_bad
    jmp .Lew_ok
.Lew_committed:
    cmp r8, 80
    jb .Lew_bad
    cmp r8, EC_LIMIT + 80
    ja .Lew_bad
.Lew_ok:
    xor eax, eax
    ret
.Lew_bad:
    mov rax, -71
    ret

# deltas(bytes,length,count,outEC128)->0/-EPROTO.
# Worker-only full validation. Output spans borrow immutable owned input bytes.
# The caller never uses partially populated outputs after refusal.
FN ext_settings_wire_deltas
    test rdx, rdx
    jz .Lew_bad
    cmp rdx, EC_BATCH
    ja .Lew_bad
    cmp rsi, EW_LIMIT
    ja .Lew_bad
    test rdi, rdi
    jz .Lew_bad
    test rcx, rcx
    jz .Lew_bad
    mov rax, rdi
    add rax, rsi
    jc .Lew_bad
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rax
    mov r13, rdx
    mov r14, rcx
    mov [rsp], rcx
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
1:  test r13, r13
    jz .Lew_delta_end
    mov rax, r12
    sub rax, rbx
    cmp rax, 16
    jb .Lew_delta_bad
    mov eax, [rbx]
    mov [r14 + EC_seclen], rax
    mov edx, [rbx + 4]
    mov [r14 + EC_keylen], rdx
    add rax, rdx
    mov edx, [rbx + 8]
    mov [r14 + EC_vallen], rdx
    add rax, rdx
    add [rsp + 16], rax
    cmp qword ptr [rsp + 16], EC_LIMIT
    ja .Lew_delta_bad
    mov edx, [rbx + 12]
    mov [r14 + EC_remove], rdx
    test edx, edx
    jz 5f
    cmp qword ptr [r14 + EC_vallen], 0
    jne .Lew_delta_bad
5:
    add rbx, 16
    mov rdx, r12
    sub rdx, rbx
    cmp rax, rdx
    ja .Lew_delta_bad
    mov [r14 + EC_section], rbx
    add rbx, [r14 + EC_seclen]
    mov [r14 + EC_key], rbx
    add rbx, [r14 + EC_keylen]
    mov [r14 + EC_value], rbx
    add rbx, [r14 + EC_vallen]
    mov rdi, r14
    call ext_choices_validate_delta
    test rax, rax
    js .Lew_delta_bad
    # Exact duplicates are invalid even if their values/removal flags differ.
    mov r15, [rsp]
2:  cmp r15, r14
    jae 4f
    mov rdi, [r14 + EC_section]
    mov rsi, [r14 + EC_seclen]
    mov rdx, [r15 + EC_section]
    mov rcx, [r15 + EC_seclen]
    call str_eq
    test eax, eax
    jz 3f
    mov rdi, [r14 + EC_key]
    mov rsi, [r14 + EC_keylen]
    mov rdx, [r15 + EC_key]
    mov rcx, [r15 + EC_keylen]
    call str_eq
    test eax, eax
    jnz .Lew_delta_bad
3:  add r15, EC_SIZE
    jmp 2b
4:  add r14, EC_SIZE
    dec r13
    jmp 1b
.Lew_delta_end:
    cmp rbx, r12
    jne .Lew_delta_bad
    xor eax, eax
    EPILOGUE
.Lew_delta_bad:
    mov rax, -71
    EPILOGUE
