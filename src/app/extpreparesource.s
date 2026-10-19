# Exact source snapshots and source commitments for private preparation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# prep_snapshot(EP,ownedFile,max)->owned bytes/RDX length, or0/RDX primary.
# Always consumes the file and records the first mandatory close error on EP.
FN prep_snapshot
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Leps_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Leps_changed
    mov r14, [rsp + ER_size]
    cmp r14, r13
    ja .Leps_resource
    mov rdi, rbx
    lea rsi, [r14 + 1]
    call prep_owned_alloc
    test rax, rax
    jz .Leps_alloc_error
    mov [rsp + 64], rax
    xor r15d, r15d
1:  cmp r15, r14
    jae 2f
    mov rdi, r12
    mov rsi, [rsp + 64]
    add rsi, r15
    mov rdx, r14
    sub rdx, r15
    mov rcx, r15
    call ext_root_read
    test rax, rax
    js .Leps_error
    jz .Leps_changed
    add r15, rax
    cmp r15, r14
    ja .Leps_changed
    jmp 1b
2:  mov rdi, r12
    lea rsi, [rsp + 72]
    mov edx, 1
    mov rcx, r14
    call ext_root_read
    test rax, rax
    js .Leps_error
    jnz .Leps_changed
    mov rdi, r12
    lea rsi, [rsp + 32]
    call ext_root_stat
    test rax, rax
    js .Leps_error
    mov rdi, rsp
    lea rsi, [rsp + 32]
    mov edx, ER_STAT_SIZE
    call memeq
    test eax, eax
    jz .Leps_changed
    xor r13d, r13d
    jmp .Leps_close
.Leps_alloc_error:
    mov rax, [rbx + PO_error]
    jmp .Leps_error
.Leps_changed:
    mov rax, -EV_CHANGED
    jmp .Leps_error
.Leps_resource:
    mov rax, -EV_RESOURCE
.Leps_error:
    mov r13, rax
.Leps_close:
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rbx + EP_cleanup], 0
    jne 3f
    mov [rbx + EP_cleanup], rax
3:  test r13, r13
    jnz 4f
    mov r13, rax
4:  test r13, r13
    js 5f
    mov rax, [rsp + 64]
    mov rdx, r14
    EPILOGUE
5:  mov rdx, r13
    xor eax, eax
    EPILOGUE

# prep_source_add(EP,path,len,size,exec,hash32), role is the internal extra argument R10.
# Unique paths merge roles only when their exact accepted content metadata agrees.
FN prep_source_add
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp + 24], r10
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov [rsp + 16], r9
    xor r14d, r14d
1:  cmp r14, [rbx + EP_sources + VEC_len]
    jae 3f
    imul r15, r14, SR_SIZE
    add r15, [rbx + EP_sources + VEC_ptr]
    cmp [r15 + SR_len], r13
    jne 2f
    mov rdi, [r15 + SR_path]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jnz 5f
2:  inc r14
    jmp 1b
3:  cmp r14, 258
    jae .Lepsa_resource
    mov rdi, rbx
    lea rsi, [rbx + EP_sources]
    mov edx, SR_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lepsa_done
    mov r15, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call prep_owned_dup
    mov [r15 + SR_path], rax
    test rax, rax
    jz .Lepsa_done
    mov [r15 + SR_len], r13
    mov rax, [rsp]
    mov [r15 + SR_size], rax
    mov rax, [rsp + 8]
    mov [r15 + SR_exec], rax
    lea rdi, [r15 + SR_hash]
    mov rsi, [rsp + 16]
    mov edx, 32
    call memcpy
    jmp 6f
5:  mov rax, [rsp]
    cmp [r15 + SR_size], rax
    jne .Lepsa_changed
    mov rax, [rsp + 8]
    cmp [r15 + SR_exec], rax
    jne .Lepsa_changed
    lea rdi, [r15 + SR_hash]
    mov rsi, [rsp + 16]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lepsa_changed
6:  mov rax, [rsp + 24]
    or [r15 + SR_roles], rax
.Lepsa_done:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lepsa_resource:
    mov qword ptr [rbx + PO_error], -EV_RESOURCE
    jmp .Lepsa_done
.Lepsa_changed:
    mov qword ptr [rbx + PO_error], -EV_CHANGED
    jmp .Lepsa_done

# Snapshot SHA256, no allocation. The digest is caller-owned 32 bytes.
FN prep_hash_bytes
    PROLOGUE SH256_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call sha256_update
    mov rdi, rsp
    mov rsi, r13
    call sha256_final
    EPILOGUE

# Source order is established once before readiness, using the shared bytewise sorter.
FN prep_sources_sort
    lea rax, [rdi + EP_sources]
    mov rdi, [rax + VEC_ptr]
    mov rsi, [rax + VEC_len]
    jmp ext_validate_records_sort

FN ext_prepare_source_commitment
    cmp qword ptr [rdi + EP_kind], 2
    je ext_prepare_legacy_source_commitment
    cmp qword ptr [rdi + PO_ready], 1
    jne .Lepsc_bad
    PROLOGUE SH256_SIZE + 32
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    lea rsi, [rip + eps_domain]
    mov edx, 25
    call sha256_update
    mov eax, [rbx + EP_sources + VEC_len]
    mov [rsp + SH256_SIZE], eax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    xor r13d, r13d
1:  cmp r13, [rbx + EP_sources + VEC_len]
    jae 2f
    imul r14, r13, SR_SIZE
    add r14, [rbx + EP_sources + VEC_ptr]
    mov eax, [r14 + SR_len]
    mov [rsp + SH256_SIZE], eax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    mov rsi, [r14 + SR_path]
    mov rdx, [r14 + SR_len]
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_size]
    mov edx, 8
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_exec]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_hash]
    mov edx, 32
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_roles]
    mov edx, 4
    call sha256_update
    inc r13
    jmp 1b
2:  mov rdi, [rbx + EP_ext + EXT_prog]
    call strlen
    mov [rsp + SH256_SIZE], eax
    mov r14, rax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    mov rsi, [rbx + EP_ext + EXT_prog]
    mov rdx, r14
    call sha256_update
    mov rdi, rsp
    mov rsi, r12
    call sha256_final
    xor eax, eax
    EPILOGUE
.Lepsc_bad:
    mov rax, -EV_BAD_PREPARE
    ret
.section .rodata
eps_domain: .asciz "rhun-prepared-sources-v1"
