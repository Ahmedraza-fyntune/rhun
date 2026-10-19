# Fallible budgeted ownership for private extension preparation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# Exact allocator block charge for a requested payload, including its allocator header.
FN prep_alloc_charge
    mov rax, rdi
    add rax, 16
    jc 8f
    cmp rax, PREP_CAP
    ja 8f
    cmp rax, 65536
    ja 2f
    mov edx, 32
1:  cmp rdx, rax
    jae 3f
    add rdx, rdx
    jmp 1b
2:  add rax, 4095
    and rax, -4096
    ret
3:  mov rax, rdx
    ret
8:  xor eax, eax
    ret

FN ext_prepare_owner_create
    PROLOGUE
    mov rbx, rdi
    cmp rbx, PREP_CAP
    ja 8f
    mov edi, EO_SIZE + RD_SIZE
    call prep_alloc_charge
    mov r12, rax
    cmp rbx, rax
    jb 8f
    mov rdi, r12
    call prep_global_admit
    test rax, rax
    js 8f
    mov edi, EO_SIZE + RD_SIZE
    call mem_alloc_try
    test rax, rax
    jz 7f
    lea rdx, [rax + RD_SIZE]
    mov [rax + RD_object], rdx
    mov qword ptr [rax + RD_kind], RD_EO
    mov rax, rdx
    add [rip + prep_total_charge], r12
    mov qword ptr [rax + EO_refs], 1
    mov [rax + EO_used], r12
    mov [rax + EO_cap], rbx
    mov qword ptr [rax + EO_lease], -1
    xor edx, edx
    EPILOGUE
7:  mov rdx, -12
    xor eax, eax
    EPILOGUE
8:  mov rdx, -EV_RESOURCE
    xor eax, eax
    EPILOGUE

FN ext_prepare_owner_retain
    test rdi, rdi
    jz .Leor_invalid
    test qword ptr [rdi - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Leor_invalid
    cmp qword ptr [rdi + EO_refs], -1
    je 8f
    cmp qword ptr [rdi + EO_refs], 0
    je .Leor_invalid
    inc qword ptr [rdi + EO_refs]
    xor eax, eax
    ret
8:  mov rax, -75
    ret
.Leor_invalid:
    mov rax, -EV_BAD_PREPARE
    ret

FN ext_prepare_owner_release
    jmp prep_retire_owner_release_sync

# Common owner object creation. The creation block is the last ledger entry freed.
FN prep_object_create
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, PO_SIZE
    jb .Lpom_bad
    test qword ptr [rbx - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lpom_bad
    cmp qword ptr [rbx + EO_refs], 0
    je .Lpom_bad
    cmp qword ptr [rbx + EO_refs], -1
    je .Lpom_overflow
    cmp qword ptr [rbx + EO_error], 0
    jne .Lpom_existing
    lea rdi, [r12 + AO_SIZE + RD_SIZE]
    cmp rdi, r12
    jb .Lpom_resource
    call prep_alloc_charge
    test rax, rax
    jz .Lpom_resource
    mov r13, rax
    mov rdi, rax
    call prep_global_admit
    test rax, rax
    js .Lpom_resource
    mov rax, r13
    add rax, [rbx + EO_used]
    jc .Lpom_resource
    cmp rax, [rbx + EO_cap]
    ja .Lpom_resource
    lea rdi, [r12 + AO_SIZE + RD_SIZE]
    call mem_alloc_try
    test rax, rax
    jz .Lpom_oom
    lea rdx, [rax + RD_SIZE + AO_SIZE]
    mov [rax + RD_object], rdx
    mov qword ptr [rax + RD_kind], RD_LEDGER
    mov qword ptr [rax + RD_state], RDF_PO
    add rax, RD_SIZE
    mov [rax + AO_charge], r13
    lea rdx, [rax + AO_SIZE]
    mov qword ptr [rdx + PO_refs], 1
    mov [rdx + PO_eo], rbx
    mov [rdx + PO_allocs], rax
    add [rbx + EO_used], r13
    add [rip + prep_total_charge], r13
    inc qword ptr [rbx + EO_refs]
    mov rax, rdx
    xor edx, edx
    EPILOGUE
.Lpom_oom:
    mov rax, -12
    jmp .Lpom_error
.Lpom_resource:
    mov rax, -EV_RESOURCE
    jmp .Lpom_error
.Lpom_overflow:
    mov rax, -75
    jmp .Lpom_error
.Lpom_bad:
    mov rax, -EV_BAD_PREPARE
.Lpom_error:
    mov [rbx + EO_error], rax
.Lpom_existing:
    mov rdx, [rbx + EO_error]
    xor eax, eax
    EPILOGUE

# prep_owned_alloc(object,size) -> aligned zeroed object or0, sticky error.
FN prep_owned_alloc
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + PO_error], 0
    jne .Lpoa_existing
    mov r13, [rbx + PO_eo]
    cmp qword ptr [r13 + EO_error], 0
    jne .Lpoa_owner_error
    lea rdi, [r12 + AO_SIZE]
    cmp rdi, r12
    jb .Lpoa_resource
    call prep_alloc_charge
    test rax, rax
    jz .Lpoa_resource
    mov r14, rax
    mov rdi, rax
    call prep_global_admit
    test rax, rax
    js .Lpoa_resource
    mov rax, r14
    add rax, [r13 + EO_used]
    jc .Lpoa_resource
    cmp rax, [r13 + EO_cap]
    ja .Lpoa_resource
    lea rdi, [r12 + AO_SIZE]
    call mem_alloc_try
    test rax, rax
    jz .Lpoa_oom
    mov rcx, [rbx + PO_allocs]
    mov [rax + AO_next], rcx
    mov [rax + AO_charge], r14
    mov [rbx + PO_allocs], rax
    add [r13 + EO_used], r14
    add [rip + prep_total_charge], r14
    add rax, AO_SIZE
    xor edx, edx
    EPILOGUE
.Lpoa_oom:
    mov rax, -12
    jmp .Lpoa_error
.Lpoa_resource:
    mov rax, -EV_RESOURCE
.Lpoa_error:
    mov [r13 + EO_error], rax
.Lpoa_owner_error:
    mov rax, [r13 + EO_error]
    mov [rbx + PO_error], rax
.Lpoa_existing:
    mov rdx, [rbx + PO_error]
    xor eax, eax
    EPILOGUE

# Free one immutable allocation, locating its header without dereferencing a foreign pointer.
FN prep_owned_free
    test rsi, rsi
    jz .Lpof_empty
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + PO_allocs]
1:  mov r13, [r12]
    test r13, r13
    jz 8f
    lea rax, [r13 + AO_SIZE]
    cmp rax, rsi
    je 2f
    lea r12, [r13 + AO_next]
    jmp 1b
2:  cmp rsi, rbx
    je 8f
    mov r15, [r13 + AO_next]
    mov r14, [r13 + AO_charge]
    mov rdi, r13
    call prep_cleanup_free
    test rax, rax
    js .Lpof_failed
    mov [r12], r15
    mov rcx, [rbx + PO_eo]
    sub [rcx + EO_used], r14
    sub [rip + prep_total_charge], r14
    xor eax, eax
    EPILOGUE
.Lpof_failed:
    mov r12, rax
    mov rdi, [rbx + PO_eo]
    mov rsi, rax
    call prep_owner_note_cleanup
    mov rax, r12
    cmp qword ptr [rbx + PO_error], 0
    jne 9f
    mov [rbx + PO_error], rax
    EPILOGUE
8:  mov rax, -EV_BAD_PREPARE
    cmp qword ptr [rbx + PO_error], 0
    jne 9f
    mov [rbx + PO_error], rax
9:  EPILOGUE
.Lpof_empty:
    xor eax, eax
    ret

# Caller has taken the last object reference. No allocation can occur here.
FN prep_owned_dispose
    jmp prep_retire_dispose

FN prep_object_retain
    test rdi, rdi
    jz 8f
    test qword ptr [rdi - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz 8f
    cmp qword ptr [rdi + PO_refs], -1
    je 7f
    cmp qword ptr [rdi + PO_refs], 0
    je 8f
    cmp qword ptr [rdi + PO_ready], 1
    jne 8f
    inc qword ptr [rdi + PO_refs]
    xor eax, eax
    ret
7:  mov rax, -75
    ret
8:  mov rax, -EV_BAD_PREPARE
    ret

# prep_owned_dup(object,bytes,len) -> owned terminated copy or0.
FN prep_owned_dup
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rsi, [rdx + 1]
    test rsi, rsi
    jz 8f
    call prep_owned_alloc
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [r14 + r13], 0
    mov rax, r14
9:  EPILOGUE
8:  cmp qword ptr [rbx + PO_error], 0
    jne 81f
    mov qword ptr [rbx + PO_error], -EV_RESOURCE
81: xor eax, eax
    EPILOGUE

# prep_owned_vec_push(owner,vec,itemSize) -> new zeroed slot or0 unchanged.
FN prep_owned_vec_push
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .Lpov_bad
    cmp qword ptr [rbx + PO_error], 0
    jne .Lpov_zero
    mov r14, [r12 + VEC_len]
    cmp r14, [r12 + VEC_cap]
    ja .Lpov_bad
    jb .Lpov_slot
    lea r15, [r14 + r14]
    cmp r15, r14
    jb .Lpov_bad
    mov eax, 8
    cmp r15, rax
    cmovb r15, rax
    mov rax, r15
    mul r13
    test rdx, rdx
    jnz .Lpov_bad
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, rax
    call prep_owned_alloc
    test rax, rax
    jz .Lpov_zero
    mov [rsp + 8], rax
    mov rdi, rax
    mov rsi, [r12 + VEC_ptr]
    mov rdx, r14
    imul rdx, r13
    call memcpy
    mov rdi, rbx
    mov rsi, [r12 + VEC_ptr]
    call prep_owned_free
    test rax, rax
    jnz .Lpov_zero
    mov rax, [rsp + 8]
    mov [r12 + VEC_ptr], rax
    mov [r12 + VEC_cap], r15
.Lpov_slot:
    mov rax, r14
    imul rax, r13
    add rax, [r12 + VEC_ptr]
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, r13
    call memset
    inc qword ptr [r12 + VEC_len]
    mov rax, r15
    EPILOGUE
.Lpov_bad:
    cmp qword ptr [rbx + PO_error], 0
    jne .Lpov_zero
    mov qword ptr [rbx + PO_error], -EV_RESOURCE
.Lpov_zero:
    xor eax, eax
    EPILOGUE
