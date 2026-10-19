# Fixed-slot population and counted duplicate identity detection.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN cp_capture_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + CP_phase]
    cmp rax, CPP_MODEL_ALLOC
    je .Lcpb_model
    cmp rax, CPP_MODEL_SOURCE
    je .Lcpb_source
    cmp rax, CPP_SLOTS
    je .Lcpb_slot
    cmp rax, CPP_ID_HASH
    je .Lcpb_hash
    cmp rax, CPP_ID_INSERT
    je .Lcpb_insert
    cmp rax, CPP_ID_COMPARE
    je .Lcpb_compare
    jmp .Lcpb_bad
.Lcpb_model:
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lcpb_zero
    dec qword ptr [rbx + CP_allocsleft]
    mov edi, ELM_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lcpb_alloc_error
    mov [rbx + CP_model], rax
    mov qword ptr [rax + ELM_refs], 1
    mov qword ptr [rbx + CP_phase], CPP_MODEL_SOURCE
    jmp .Lcpb_zero
.Lcpb_source:
    mov rdi, [rbx + CP_source]
    call ext_settings_snapshot_retain
    test rax, rax
    jnz .Lcpb_return
    mov rax, [rbx + CP_source]
    mov rcx, [rbx + CP_model]
    mov [rcx + ELM_source], rax
    mov qword ptr [rbx + CP_phase], CPP_SLOTS
    jmp .Lcpb_zero
.Lcpb_slot:
    mov r12, [rbx + CP_index]
    cmp r12, [rbx + CP_count]
    jae .Lcpb_ids_begin
    imul rax, r12, CPR_SIZE
    lea r13, [rbx + CP_rows + rax]
    mov r14, [r13 + CPR_view]
    mov rdi, r14
    call ext_settings_view_retain
    test rax, rax
    jnz .Lcpb_return
    mov rcx, [r13 + CPR_slot]
    mov rax, [rbx + CP_model]
    mov [rax + ELM_slots + rcx * 8], r14
    inc qword ptr [rbx + CP_index]
    jmp .Lcpb_zero
.Lcpb_ids_begin:
    mov qword ptr [rbx + CP_index], 0
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_hash], 5381
    mov qword ptr [rbx + CP_phase], CPP_ID_HASH
    jmp .Lcpb_zero
.Lcpb_hash:
    mov r12, [rbx + CP_index]
    cmp r12, [rbx + CP_count]
    jae .Lcpb_providers
    imul rax, r12, CPR_SIZE
    mov r13, [rbx + CP_rows + rax + CPR_view]
    mov r14, [r13 + EV_section]
1:  mov rcx, [rbx + CP_scanpos]
    cmp rcx, [r13 + EV_seclen]
    jae 2f
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lcpb_zero
    movzx eax, byte ptr [r14 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    mov rdx, [rbx + CP_hash]
    mov r8, rdx
    shl rdx, 5
    add rdx, r8
    xor rdx, rax
    mov [rbx + CP_hash], rdx
    inc qword ptr [rbx + CP_scanpos]
    jmp 1b
2:  mov rax, [rbx + CP_hash]
    mov [rbx + CP_hashes + r12 * 8], rax
    and eax, 511
    mov [rbx + CP_probe], rax
    mov qword ptr [rbx + CP_phase], CPP_ID_INSERT
    jmp .Lcpb_zero
.Lcpb_insert:
    mov rcx, [rbx + CP_probe]
    mov rax, [rbx + CP_buckets + rcx * 8]
    test rax, rax
    jz 1f
    dec rax
    mov [rbx + CP_rowindex], rax
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_phase], CPP_ID_COMPARE
    jmp .Lcpb_zero
1:  mov rax, [rbx + CP_index]
    inc rax
    mov [rbx + CP_buckets + rcx * 8], rax
    inc qword ptr [rbx + CP_index]
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_hash], 5381
    mov qword ptr [rbx + CP_phase], CPP_ID_HASH
    jmp .Lcpb_zero
.Lcpb_compare:
    mov rcx, [rbx + CP_rowindex]
    mov rax, [rbx + CP_hash]
    cmp [rbx + CP_hashes + rcx * 8], rax
    jne .Lcpb_probe_next
    imul rax, [rbx + CP_index], CPR_SIZE
    mov r12, [rbx + CP_rows + rax + CPR_view]
    imul rax, rcx, CPR_SIZE
    mov r13, [rbx + CP_rows + rax + CPR_view]
    mov rax, [r12 + EV_seclen]
    cmp [r13 + EV_seclen], rax
    jne .Lcpb_probe_next
    mov r14, [r12 + EV_section]
    mov r15, [r13 + EV_section]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, [r12 + EV_seclen]
    jae .Lcpb_bad
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lcpb_zero
    movzx eax, byte ptr [r14 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r15 + rcx]
    jne .Lcpb_probe_next
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
.Lcpb_probe_next:
    inc qword ptr [rbx + CP_probe]
    and qword ptr [rbx + CP_probe], 511
    mov qword ptr [rbx + CP_phase], CPP_ID_INSERT
    jmp .Lcpb_zero
.Lcpb_providers:
    mov qword ptr [rbx + CP_phase], CPP_PROVIDERS
    mov qword ptr [rbx + CP_scanpos], 0
.Lcpb_zero:
    xor eax, eax
.Lcpb_return:
    EPILOGUE
.Lcpb_bad:
    mov rax, -22
    EPILOGUE
.Lcpb_alloc_error:
    mov rax, rdx
    EPILOGUE
