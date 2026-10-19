# Snapshot lookup and keeper authorization. No activation/cache decisions here.
.include "rhun.inc"
.include "app/extstore.inc"
.text
# ext_store_record_init(dst,owner,name)->0/-EINVAL. Supports key strings in dst.
FN ext_store_record_init
    test rdi, rdi
    jz .Lesk_invalid
    PROLOGUE 208
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    call ext_store_identity_len
    test rax, rax
    jz 8f
    mov r14, rax
    mov rdi, r13
    call ext_store_identity_len
    test rax, rax
    jz 8f
    mov r15, rax
    mov rdi, rsp
    xor esi, esi
    mov edx, 208
    call memset
    mov rdi, rsp
    mov rsi, r12
    lea rdx, [r14 + 1]
    call memcpy
    lea rdi, [rsp + 104]
    mov rsi, r13
    lea rdx, [r15 + 1]
    call memcpy
    mov rdi, rbx
    xor esi, esi
    mov edx, ESR_SIZE
    call memset
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 208
    call memcpy
    xor eax, eax
    EPILOGUE
8:  mov rax, -22
    EPILOGUE
.Lesk_invalid:
    mov rax, -22
    ret

# ext_store_snapshot_find(ESS,owner,name)->borrowed ESR or0, no ordering assumption.
FN ext_store_snapshot_find
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + ESS_entries + VEC_len]
    jae 8f
    mov rax, r14
    imul rax, ESR_SIZE
    add rax, [rbx + ESS_entries + VEC_ptr]
    mov r15, rax
    mov rdi, rax
    mov rsi, r12
    call ext_store_name_cmp
    test rax, rax
    jnz 2f
    lea rdi, [r15 + ESR_name]
    mov rsi, r13
    call ext_store_name_cmp
    test rax, rax
    jz 3f
2:  inc r14
    jmp 1b
3:  mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# snapshot_copy(ESS,initializedESR)->status. Names in destination are query keys.
.Lesk_copy:
    PROLOGUE
    mov rbx, rsi
    lea rdx, [rsi + ESR_name]
    call ext_store_snapshot_find
    test rax, rax
    jz 1f
    mov rsi, rax
    mov rdi, rbx
    mov edx, ESR_SIZE
    call memcpy
1:  mov rax, [rbx + ESR_status]
    EPILOGUE

# ext_store_lookup_guard(guard,owner,name,outESR)->outESR,0,0 or0,primary,secondary.
# Full root/owner discovery prevents missing tombstones on an incomplete root.
FN ext_store_lookup_guard
    test rdi, rdi
    jz .Lesk_lookup_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rcx
    mov rdi, rcx
    call ext_store_record_init
    test rax, rax
    js 3f
    mov rdi, [rbx + ESG_root]
    mov rsi, [rbx + ESG_cancel]
    mov rdx, [rbx + ESG_user]
    call ext_store_snapshot_root_try
    test rax, rax
    jz 2f
    mov r13, rax
    mov rdi, rax
    mov rsi, r12
    call .Lesk_copy
    mov r14, rax
    mov rdi, r13
    call ext_store_snapshot_free
    mov rdx, r14
    xor eax, eax
    test rdx, rdx
    js 4f
    mov rax, r12
4:  xor ecx, ecx
    EPILOGUE
2:  mov [r12 + ESR_status], rdx
    xor eax, eax
    EPILOGUE
3:  mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
.Lesk_lookup_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    ret

# ext_store_lookup_try(root,owner,name,outESR,cancelFn,user)->outESR,0,0 or0,primary,secondary.
FN ext_store_lookup_try
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rcx
    mov [rsp], r8
    mov [rsp + 8], r9
    mov rdi, rcx
    call ext_store_record_init
    test rax, rax
    js 3f
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call ext_store_snapshot_try
    test rax, rax
    jz 2f
    mov r13, rax
    mov rdi, rax
    mov rsi, r12
    call .Lesk_copy
    mov r14, rax
    mov rdi, r13
    call ext_store_snapshot_free
    mov rdx, r14
    xor eax, eax
    test rdx, rdx
    js 4f
    mov rax, r12
4:  xor ecx, ecx
    EPILOGUE
2:  mov [r12 + ESR_status], rdx
    xor eax, eax
    EPILOGUE
3:  mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# ext_store_selection_matches(guard,owner,name,expected160OrNULL)->status,secondary.
FN ext_store_selection_matches
    PROLOGUE 400
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test rcx, rcx
    jz 1f
    mov rdi, rcx
    mov esi, EXI_SIZE
    mov rdx, [rcx + EXI_generation]
    call ext_index_check
    test eax, eax
    jz 4f
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rsp
    call ext_store_lookup_guard
    test rax, rax
    jnz 7f
    mov rax, rdx
    mov rdx, rcx
    jmp 5f
7:
    test r14, r14
    jz 2f
    cmp qword ptr [rsp + ESR_generation], 0
    je 3f
    lea rdi, [rsp + ESR_index]
    mov rsi, r14
    mov edx, EXI_SIZE
    call memeq
    test eax, eax
    jz 3f
    jmp 6f
2:  cmp qword ptr [rsp + ESR_generation], 0
    je 6f
3:  mov rax, -116
    xor edx, edx
    EPILOGUE
4:  mov rax, -22
    xor edx, edx
5:  EPILOGUE
6:  xor eax, eax
    xor edx, edx
    EPILOGUE

# ext_store_snapshot_bind(ESS,guard,expectedEpoch)->0/-errno. Preparation only.
# Root transport already required exact wire tag/job/nonce/EOF/child exit status.
FN ext_store_snapshot_bind
    test rdi, rdi
    jz .Lesk_invalid
    test rsi, rsi
    jz .Lesk_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [rbx + ESS_proof_guard], 0
    mov qword ptr [rbx + ESS_proof_epoch], 0
    cmp rdx, [rsi + ESG_epoch]
    jne 3f
    cmp rdx, [rdi + ESS_tag + EST_epoch]
    jne 3f
    call ext_store_snapshot_check
    test eax, eax
    jz 4f
    mov rdi, [r12 + ESG_root]
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    js 5f
    mov rdi, rsp
    lea rsi, [rbx + ESS_tag + EST_root_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz 3f
    mov [rbx + ESS_proof_guard], r12
    mov [rbx + ESS_proof_epoch], r13
    xor eax, eax
5:  EPILOGUE
3:  mov rax, -116
    EPILOGUE
4:  mov rax, -22
    EPILOGUE
