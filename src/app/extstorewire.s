# Bounded relocation-free helper snapshots. No handle or pointer crosses wire.
.include "rhun.inc"
.include "app/extstore.inc"
.text
# Counted104-byte logical name compare. Callers validate canonical padding.
FN ext_store_name_cmp
    xor ecx, ecx
1:  cmp ecx, 104
    jae 4f
    movzx eax, byte ptr [rdi + rcx]
    movzx edx, byte ptr [rsi + rcx]
    cmp eax, edx
    jb 2f
    ja 3f
    test eax, eax
    jz 4f
    inc ecx
    jmp 1b
2:  mov rax, -1
    ret
3:  mov eax, 1
    ret
4:  xor eax, eax
    ret
FN ext_store_record_cmp
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_store_name_cmp
    test rax, rax
    jnz 1f
    lea rdi, [rbx + ESR_name]
    lea rsi, [r12 + ESR_name]
    call ext_store_name_cmp
1:  EPILOGUE
.Lesw_swap:
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 2f
    mov rax, [rdi + rcx]
    mov r8, [rsi + rcx]
    mov [rdi + rcx], r8
    mov [rsi + rcx], rax
    add rcx, 8
    jmp 1b
2:  ret
# sift(base,start,count,size,comparator), internal bounded heap.
.Lesw_sift:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
1:  lea rax, [r12*2 + 1]
    cmp rax, r13
    jae 9f
    mov [rsp], rax
    lea rcx, [rax + 1]
    cmp rcx, r13
    jae 3f
    mov [rsp + 8], rcx
    imul rax, r14
    lea rdi, [rbx + rax]
    imul rcx, r14
    lea rsi, [rbx + rcx]
    call r15
    test rax, rax
    jns 3f
    mov rax, [rsp + 8]
    mov [rsp], rax
3:  mov rax, r12
    imul rax, r14
    lea rdi, [rbx + rax]
    mov rax, [rsp]
    imul rax, r14
    lea rsi, [rbx + rax]
    call r15
    test rax, rax
    jns 9f
    mov rax, r12
    imul rax, r14
    lea rdi, [rbx + rax]
    mov rax, [rsp]
    imul rax, r14
    lea rsi, [rbx + rax]
    mov rdx, r14
    call .Lesw_swap
    mov r12, [rsp]
    jmp 1b
9:  EPILOGUE
# sort(base,count,size,comparator), O(n log n), fixed stack, no allocation.
.Lesw_sort:
    cmp rsi, 2
    jb 9f
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, rsi
    shr r15, 1
1:  test r15, r15
    jz 2f
    dec r15
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    call .Lesw_sift
    jmp 1b
2:  dec r12
    jz 8f
    mov rdi, rbx
    mov rax, r12
    imul rax, r13
    lea rsi, [rbx + rax]
    mov rdx, r13
    call .Lesw_swap
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    call .Lesw_sift
    jmp 2b
8:  EPILOGUE
9:  ret

FN ext_store_name_check
    PROLOGUE
    mov rbx, rdi
    call ext_store_identity_len
    test rax, rax
    jz 3f
    mov rcx, rax
1:  cmp rcx, 104
    jae 2f
    cmp byte ptr [rbx + rcx], 0
    jne 4f
    inc rcx
    jmp 1b
2:  mov eax, 1
3:  EPILOGUE
4:  xor eax, eax
    EPILOGUE

FN ext_store_record_check
    PROLOGUE
    mov rbx, rdi
    call ext_store_name_check
    test eax, eax
    jz 9f
    lea rdi, [rbx + ESR_name]
    call ext_store_name_check
    test eax, eax
    jz 9f
    mov rax, [rbx + ESR_status]
    test rax, rax
    jz 2f
    jns 8f
    cmp rax, -4095
    jl 8f
    mov rcx, [rbx + ESR_entries]
    cmp rcx, ES_LIMIT
    jbe 1f
    cmp rcx, ES_LIMIT + 1
    jne 8f
    cmp rax, -27
    jne 8f
1:  jmp 4f
2:  cmp qword ptr [rbx + ESR_entries], ES_LIMIT
    ja 8f
    mov rdx, [rbx + ESR_generation]
    test rdx, rdx
    jz 4f
    lea rdi, [rbx + ESR_index]
    mov esi, EXI_SIZE
    call ext_index_check
    jmp 9f
4:  xor ecx, ecx
5:  cmp qword ptr [rbx + rcx + ESR_index], 0
    jne 8f
    add ecx, 8
    cmp ecx, EXI_SIZE
    jb 5b
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# ext_store_snapshot_free(owned ESS) ->0. No handles are retained in a snapshot.
FN ext_store_snapshot_free
    test rdi, rdi
    jz 2f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ESS_entries + VEC_ptr]
    call mem_free
    mov rdi, [rbx + ESS_owners + VEC_ptr]
    call mem_free
    mov rdi, rbx
    call mem_free
    xor eax, eax
    EPILOGUE
2:  xor eax, eax
    ret

# Job-owned ESS disposal. Partial vectors remain owned until consumed.
FN ext_store_snapshot_free_try
    test rdi, rdi
    jz 9f
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
    mov r14d, 1
1:  mov rdi, [rbx + r12]
    call prep_cleanup_free
    test rdx, rdx
    jz 2f
    mov qword ptr [rbx + r12], 0
    jmp 3f
2:  xor r14d, r14d
3:  test rax, rax
    jns 4f
    test r13, r13
    jnz 4f
    mov r13, rax
4:  add r12, ESS_owners
    cmp r12, ESS_owners
    jbe 1b
    test r14, r14
    jz 5f
    mov rdi, rbx
    call prep_cleanup_free
    test rax, rax
    jns 6f
    test r13, r13
    jnz 6f
    mov r13, rax
6:  mov r14, rdx
5:  mov rax, r13
    mov rdx, r14
    EPILOGUE
9:  xor eax, eax
    mov edx, 1
    ret

# Internal shape check before sorting or walking owned vector memory.
.Lesw_shape:
    test rdi, rdi
    jz .Lesw_false
    cmp qword ptr [rdi + ESS_entries + VEC_len], ES_LIMIT
    ja .Lesw_false
    cmp qword ptr [rdi + ESS_owners + VEC_len], ES_LIMIT
    ja .Lesw_false
    mov rax, [rdi + ESS_entries + VEC_len]
    cmp rax, [rdi + ESS_entries + VEC_cap]
    ja .Lesw_false
    test rax, rax
    jz 1f
    cmp qword ptr [rdi + ESS_entries + VEC_ptr], 0
    je .Lesw_false
1:  mov rax, [rdi + ESS_owners + VEC_len]
    cmp rax, [rdi + ESS_owners + VEC_cap]
    ja .Lesw_false
    test rax, rax
    jz 2f
    cmp qword ptr [rdi + ESS_owners + VEC_ptr], 0
    je .Lesw_false
2:  mov eax, 1
    ret
.Lesw_false:
    xor eax, eax
    ret

# Complete canonical snapshot check, including sorted uniqueness/owner merge.
FN ext_store_snapshot_check
    PROLOGUE 32
    mov rbx, rdi
    call .Lesw_shape
    test eax, eax
    jz .Lesw_check_bad
    mov rax, [rbx + ESS_entries + VEC_len]
    cmp rax, [rbx + ESS_identity_count]
    jne .Lesw_check_bad
    cmp qword ptr [rbx + ESS_live], ES_LIVE_LIMIT
    ja .Lesw_check_bad
    cmp qword ptr [rbx + ESS_root_entries], ES_LIMIT
    ja .Lesw_check_bad
    mov rax, [rbx + ESS_owners + VEC_len]
    cmp rax, [rbx + ESS_root_entries]
    ja .Lesw_check_bad
    xor r12d, r12d
.Lesw_owner:
    cmp r12, [rbx + ESS_owners + VEC_len]
    jae .Lesw_records
    mov rax, r12
    imul rax, ESO_SIZE
    add rax, [rbx + ESS_owners + VEC_ptr]
    mov r13, rax
    mov rdi, rax
    call ext_store_name_check
    test eax, eax
    jz .Lesw_check_bad
    cmp qword ptr [r13 + ESO_entries], ES_LIMIT
    ja .Lesw_check_bad
    test r12, r12
    jz 1f
    lea rdi, [r13 - ESO_SIZE]
    mov rsi, r13
    call ext_store_name_cmp
    test rax, rax
    jns .Lesw_check_bad
1:  inc r12
    jmp .Lesw_owner
.Lesw_records:
    xor r12d, r12d
    xor r13d, r13d              # owner index in sorted merge
    xor r14d, r14d              # records in current owner
    mov qword ptr [rsp], 0     # live count
.Lesw_row:
    cmp r12, [rbx + ESS_entries + VEC_len]
    jae .Lesw_check_finish
    mov rax, r12
    imul rax, ESR_SIZE
    add rax, [rbx + ESS_entries + VEC_ptr]
    mov r15, rax
    mov rdi, rax
    call ext_store_record_check
    test eax, eax
    jz .Lesw_check_bad
    test r12, r12
    jz 1f
    lea rdi, [r15 - ESR_SIZE]
    mov rsi, r15
    call ext_store_record_cmp
    test rax, rax
    jns .Lesw_check_bad
1:  cmp r13, [rbx + ESS_owners + VEC_len]
    jae .Lesw_check_bad
    mov rax, r13
    imul rax, ESO_SIZE
    add rax, [rbx + ESS_owners + VEC_ptr]
    mov [rsp + 8], rax
    mov rdi, r15
    mov rsi, rax
    call ext_store_name_cmp
    test rax, rax
    js .Lesw_check_bad
    jz 2f
    inc r13
    xor r14d, r14d
    jmp 1b
2:  inc r14
    mov rax, [rsp + 8]
    cmp r14, [rax + ESO_entries]
    ja .Lesw_check_bad
    cmp qword ptr [r15 + ESR_status], 0
    jne 3f
    cmp qword ptr [r15 + ESR_generation], 0
    je 3f
    cmp dword ptr [r15 + ESR_index + EXI_flags], EXI_ACTIVE
    jne 3f
    inc qword ptr [rsp]
3:  inc r12
    jmp .Lesw_row
.Lesw_check_finish:
    mov rax, [rsp]
    cmp rax, [rbx + ESS_live]
    jne .Lesw_check_bad
    mov eax, 1
    EPILOGUE
.Lesw_check_bad:
    xor eax, eax
    EPILOGUE

# ext_store_snapshot_pack_try(ESS,tag64) -> owned bytes,length or0,-errno.
# Sort private source vectors before serializing, never serialize local pointers.
FN ext_store_snapshot_pack_try
    test rsi, rsi
    jz .Lesw_pack_invalid
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    call .Lesw_shape
    test eax, eax
    jz .Lesw_pack_bad
    lea rdi, [rbx + ESS_tag + EST_root_id]
    lea rsi, [r12 + EST_root_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lesw_pack_bad
    mov rdi, [rbx + ESS_entries + VEC_ptr]
    mov rsi, [rbx + ESS_entries + VEC_len]
    mov edx, ESR_SIZE
    lea rcx, [rip + ext_store_record_cmp]
    call .Lesw_sort
    mov rdi, [rbx + ESS_owners + VEC_ptr]
    mov rsi, [rbx + ESS_owners + VEC_len]
    mov edx, ESO_SIZE
    lea rcx, [rip + ext_store_name_cmp]
    call .Lesw_sort
    mov rdi, rbx
    call ext_store_snapshot_check
    test eax, eax
    jz .Lesw_pack_bad
    mov r13, [rbx + ESS_entries + VEC_len]
    imul r13, ESR_SIZE
    mov r14, [rbx + ESS_owners + VEC_len]
    imul r14, ESO_SIZE
    lea rdi, [r13 + r14 + ESW_HEADER_SIZE]
    mov [rsp], rdi
    call mem_alloc_try
    test rax, rax
    jz .Lesw_pack_oom
    mov r15, rax
    mov rax, 0x00524f5453454852
    mov [r15], rax
    mov dword ptr [r15 + 8], 1
    mov dword ptr [r15 + 12], ESW_HEADER_SIZE
    mov rax, [rbx + ESS_entries + VEC_len]
    mov [r15 + 16], eax
    mov rax, [rbx + ESS_owners + VEC_len]
    mov [r15 + 20], eax
    mov rax, [rbx + ESS_live]
    mov [r15 + 24], eax
    mov rax, [rbx + ESS_identity_count]
    mov [r15 + 32], rax
    mov rax, [rbx + ESS_root_entries]
    mov [r15 + 40], rax
    lea rdi, [r15 + 48]
    mov rsi, r12
    mov edx, EST_SIZE
    call memcpy
    lea rdi, [r15 + ESW_HEADER_SIZE]
    mov rsi, [rbx + ESS_entries + VEC_ptr]
    mov rdx, r13
    call memcpy
    lea rdi, [r15 + r13 + ESW_HEADER_SIZE]
    mov rsi, [rbx + ESS_owners + VEC_ptr]
    mov rdx, r14
    call memcpy
    mov rax, r15
    mov rdx, [rsp]
    xor ecx, ecx
    EPILOGUE
.Lesw_pack_oom:
    mov rdx, -12
    jmp .Lesw_pack_fail
.Lesw_pack_bad:
    mov rdx, -22
.Lesw_pack_fail:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
.Lesw_pack_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    ret

# ext_store_snapshot_unpack_try(bytes,count,expectedTag64)->owned ESS or0,-errno.
FN ext_store_snapshot_unpack_try
    xor ecx, ecx
    jmp .Lesw_unpack_begin
# Orphan slot receives a known-unconsumed partial ESS on failed unpack only.
FN ext_store_snapshot_unpack_owned_try
    test rcx, rcx
    jz .Lesw_pack_invalid
    mov qword ptr [rcx], 0
.Lesw_unpack_begin:
    test rdi, rdi
    jz .Lesw_pack_invalid
    test rdx, rdx
    jz .Lesw_pack_invalid
    cmp rsi, ESW_HEADER_SIZE
    jb .Lesw_unpack_invalid
    cmp rsi, ESW_WIRE_MAX
    ja .Lesw_unpack_invalid
    PROLOGUE 32
    mov [rsp + 16], rcx
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r15d, r15d
    mov rax, 0x00524f5453454852
    cmp [rbx], rax
    jne .Lesw_unpack_bad
    cmp dword ptr [rbx + 8], 1
    jne .Lesw_unpack_bad
    cmp dword ptr [rbx + 12], ESW_HEADER_SIZE
    jne .Lesw_unpack_bad
    cmp dword ptr [rbx + 16], ES_LIMIT
    ja .Lesw_unpack_bad
    cmp dword ptr [rbx + 20], ES_LIMIT
    ja .Lesw_unpack_bad
    cmp dword ptr [rbx + 24], ES_LIVE_LIMIT
    ja .Lesw_unpack_bad
    cmp dword ptr [rbx + 28], 0
    jne .Lesw_unpack_bad
    cmp qword ptr [rbx + 112], 0
    jne .Lesw_unpack_bad
    cmp qword ptr [rbx + 120], 0
    jne .Lesw_unpack_bad
    lea rdi, [rbx + 48]
    mov rsi, r13
    mov edx, EST_SIZE
    call memeq
    test eax, eax
    jz .Lesw_unpack_bad
    mov r14d, [rbx + 16]
    imul r14, ESR_SIZE
    mov [rsp], r14
    mov eax, [rbx + 20]
    imul rax, ESO_SIZE
    mov [rsp + 8], rax
    lea rax, [rax + r14 + ESW_HEADER_SIZE]
    cmp rax, r12
    jne .Lesw_unpack_bad
    mov edi, ESS_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lesw_unpack_oom
    mov r15, rax
    mov eax, [rbx + 16]
    mov [r15 + ESS_entries + VEC_len], rax
    mov [r15 + ESS_entries + VEC_cap], rax
    mov eax, [rbx + 20]
    mov [r15 + ESS_owners + VEC_len], rax
    mov [r15 + ESS_owners + VEC_cap], rax
    mov eax, [rbx + 24]
    mov [r15 + ESS_live], rax
    mov rax, [rbx + 32]
    mov [r15 + ESS_identity_count], rax
    mov rax, [rbx + 40]
    mov [r15 + ESS_root_entries], rax
    lea rdi, [r15 + ESS_tag]
    lea rsi, [rbx + 48]
    mov edx, EST_SIZE
    call memcpy
    mov rdi, [rsp]
    test rdi, rdi
    jz 1f
    call mem_alloc_try
    test rax, rax
    jz .Lesw_unpack_oom
    mov [r15 + ESS_entries + VEC_ptr], rax
    mov rdi, rax
    lea rsi, [rbx + ESW_HEADER_SIZE]
    mov rdx, [rsp]
    call memcpy
1:  mov rdi, [rsp + 8]
    test rdi, rdi
    jz 2f
    call mem_alloc_try
    test rax, rax
    jz .Lesw_unpack_oom
    mov [r15 + ESS_owners + VEC_ptr], rax
    mov rdi, rax
    mov rax, [rsp]
    lea rsi, [rbx + rax + ESW_HEADER_SIZE]
    mov rdx, [rsp + 8]
    call memcpy
2:  mov rdi, r15
    call ext_store_snapshot_check
    test eax, eax
    jz .Lesw_unpack_bad
    mov rax, r15
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesw_unpack_oom:
    mov r14, -12
    jmp .Lesw_unpack_release
.Lesw_unpack_bad:
    mov r14, -5
.Lesw_unpack_release:
    cmp qword ptr [rsp + 16], 0
    jne 3f
    mov rdi, r15
    call ext_store_snapshot_free
    xor ecx, ecx
    jmp 5f
3:  mov rdi, r15
    call ext_store_snapshot_free_try
    mov rcx, rax
    test rdx, rdx
    jnz 5f
    mov rax, [rsp + 16]
    mov [rax], r15
5:  xor eax, eax
    mov rdx, r14
    EPILOGUE
.Lesw_unpack_invalid:
    xor eax, eax
    mov rdx, -5
    xor ecx, ecx
    ret
