# Private managed discovery ownership. Never loads manifests or mutates catalogs.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extdiscovery.inc"
.include "app/extvalidate.inc"
.section .rodata
ed_packages: .asciz ".packages"
ed_lease: .asciz "lease"
ed_payload: .asciz "payload"
.text
ed_current:
    test rdi, rdi
    jz 3f
    mov rax, [rdi + ED_guard]
    test rax, rax
    jz 2f
    mov rcx, [rdi + ED_epoch]
    test rcx, rcx
    jz 2f
    cmp [rax + ESG_epoch], rcx
    jne 2f
    mov rdx, [rdi + ED_snapshot]
    cmp [rdx + ESS_proof_guard], rax
    jne 2f
    cmp [rdx + ESS_proof_epoch], rcx
    jne 2f
    cmp [rdx + ESS_tag + EST_epoch], rcx
    jne 2f
    xor eax, eax
    ret
2:  mov rax, -116
    ret
3:  mov rax, -22
    ret

ed_view:
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + ED_state], ED_READY
    je 1f
    cmp qword ptr [rdi + ED_state], ED_DETACHED
    je 1f
    mov rax, [rdi + ED_error]
    test rax, rax
    js 4f
    mov rax, -11
4:  ret
1:  xor eax, eax
    ret
3:  mov rax, -22
    ret

# Inputs retain ownership unless this returns an owned ED.
FN ext_discovery_begin
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .Led_begin_bad
    test r13, r13
    jz .Led_begin_bad
    cmp [r12 + ESS_proof_guard], r13
    jne .Led_begin_stale
    mov rax, [r13 + ESG_epoch]
    test rax, rax
    jz .Led_begin_stale
    cmp [r12 + ESS_proof_epoch], rax
    jne .Led_begin_stale
    cmp [r12 + ESS_tag + EST_epoch], rax
    jne .Led_begin_stale
    call ext_store_snapshot_check
    test eax, eax
    jz .Led_begin_bad
    mov rdi, [r13 + ESG_path]
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Led_begin_bad
    mov [rsp], rax
    mov edi, ED_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Led_begin_nomem
    mov rbx, rax
    mov rdi, [r13 + ESG_path]
    mov rsi, [rsp]
    call mem_dup_try
    test rax, rax
    jz .Led_begin_unwind
    mov [rbx + ED_rootpath], rax
    mov rdi, [r12 + ESS_live]
    test rdi, rdi
    jz 1f
    shl rdi, 4
    call mem_alloc_try
    test rax, rax
    jz .Led_begin_unwind
    mov [rbx + ED_rows], rax
1:  mov [rbx + ED_snapshot], r12
    mov [rbx + ED_guard], r13
    mov rax, [r13 + ESG_epoch]
    mov [rbx + ED_epoch], rax
    mov rdi, rbx
    call ed_current
    test rax, rax
    js .Led_begin_unwind_stale
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Led_begin_unwind_stale:
    mov qword ptr [rbx + ED_snapshot], 0
    mov [rsp], rax
    mov rdi, rbx
    call ext_discovery_free
    mov rdx, [rsp]
    jmp .Led_begin_null
.Led_begin_unwind:
    mov rdi, rbx
    call ext_discovery_free
.Led_begin_nomem:
    mov rdx, -12
    jmp .Led_begin_null
.Led_begin_bad:
    mov rdx, -22
    jmp .Led_begin_null
.Led_begin_stale:
    mov rdx, -116
.Led_begin_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

FN ext_discovery_step
    PROLOGUE 4096
    mov rbx, rdi
    test rbx, rbx
    jz .Led_step_bad
    cmp qword ptr [rbx + ED_state], ED_FAILED
    je .Led_step_sticky
    cmp qword ptr [rbx + ED_state], ED_READY
    je .Led_step_ready
    cmp qword ptr [rbx + ED_state], ED_BUILDING
    jne .Led_step_stale
    call ed_current
    test rax, rax
    js .Led_step_error
    mov r12, [rbx + ED_snapshot]
    xor r13d, r13d
.Led_step_loop:
    mov rax, [rbx + ED_cursor]
    cmp rax, [r12 + ESS_entries + VEC_len]
    jae .Led_step_complete
    cmp r13, 16
    jae .Led_step_more
    inc r13
    inc qword ptr [rbx + ED_cursor]
    imul rax, ESR_SIZE
    add rax, [r12 + ESS_entries + VEC_ptr]
    mov r14, rax
    cmp qword ptr [rax + ESR_status], 0
    jne .Led_step_loop
    cmp qword ptr [rax + ESR_generation], 0
    je .Led_step_loop
    cmp dword ptr [rax + ESR_index + EXI_flags], EXI_ACTIVE
    jne .Led_step_loop
    mov rax, [rbx + ED_count]
    cmp rax, [r12 + ESS_live]
    jae .Led_step_bad
    mov rdi, rsp
    mov rsi, [rbx + ED_rootpath]
    lea rdx, [r14 + ESR_owner]
    lea rcx, [r14 + ESR_name]
    lea r8, [r14 + ESR_index + EXI_active]
    call ext_store_payload_path
    test rax, rax
    js .Led_step_error
    mov rdi, rsp
    call strlen
    mov rsi, rax
    mov rdi, rsp
    call mem_dup_try
    test rax, rax
    jz .Led_step_nomem
    mov rcx, [rbx + ED_count]
    shl rcx, 4
    add rcx, [rbx + ED_rows]
    mov [rcx + EDR_record], r14
    mov [rcx + EDR_path], rax
    inc qword ptr [rbx + ED_count]
    # One bounded path formatter per call; remaining pure rows resume next tick.
    jmp .Led_step_more
.Led_step_complete:
    mov rax, [rbx + ED_count]
    cmp rax, [r12 + ESS_live]
    jne .Led_step_bad
    mov qword ptr [rbx + ED_state], ED_READY
.Led_step_ready:
    mov eax, 1
    EPILOGUE
.Led_step_more:
    xor eax, eax
    EPILOGUE
.Led_step_nomem:
    mov rax, -12
    jmp .Led_step_error
.Led_step_stale:
    mov rax, -116
    jmp .Led_step_error
.Led_step_bad:
    mov rax, -22
.Led_step_error:
    test rbx, rbx
    jz 1f
    mov [rbx + ED_error], rax
    mov qword ptr [rbx + ED_state], ED_FAILED
1:  EPILOGUE
.Led_step_sticky:
    mov rax, [rbx + ED_error]
    EPILOGUE

FN ext_discovery_count
    PROLOGUE
    mov rbx, rdi
    call ed_view
    test rax, rax
    js 1f
    mov rax, [rbx + ED_count]
1:  EPILOGUE
FN ext_discovery_row
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ed_view
    test rax, rax
    js .Led_query_error
    cmp r12, [rbx + ED_count]
    jae .Led_query_missing
    mov rax, r12
    shl rax, 4
    add rax, [rbx + ED_rows]
    xor edx, edx
    EPILOGUE
FN ext_discovery_snapshot
    PROLOGUE
    mov rbx, rdi
    call ed_view
    test rax, rax
    js .Led_query_error
    mov rax, [rbx + ED_snapshot]
    xor edx, edx
    EPILOGUE
.Led_query_missing:
    mov rax, -2
.Led_query_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE

# Exact complete snapshot lookup. No directory or manifest IO.
FN ext_discovery_find
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ed_view
    test rax, rax
    js .Led_query_error
    mov rdi, r12
    call ext_store_identity_len
    test rax, rax
    jz .Led_find_bad
    mov rdi, r13
    call ext_store_identity_len
    test rax, rax
    jz .Led_find_bad
    mov rax, [rbx + ED_snapshot]
    mov r14, [rax + ESS_entries + VEC_ptr]
    mov r15, [rax + ESS_entries + VEC_len]
    mov qword ptr [rsp], 0
.Led_find_loop:
    mov rax, [rsp]
    cmp rax, r15
    jae .Led_find_none
    add rax, r15
    shr rax, 1
    mov [rsp + 8], rax
    imul rax, ESR_SIZE
    add rax, r14
    mov [rsp + 16], rax
    mov rdi, r12
    lea rsi, [rax + ESR_owner]
    call ext_store_name_cmp
    test rax, rax
    jnz 1f
    mov rdi, r13
    mov rsi, [rsp + 16]
    add rsi, ESR_name
    call ext_store_name_cmp
1:  test rax, rax
    js .Led_find_lower
    jnz .Led_find_upper
    mov rax, [rsp + 16]
    xor edx, edx
    EPILOGUE
.Led_find_lower:
    mov r15, [rsp + 8]
    jmp .Led_find_loop
.Led_find_upper:
    mov rax, [rsp + 8]
    inc rax
    mov [rsp], rax
    jmp .Led_find_loop
.Led_find_none:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Led_find_bad:
    mov rax, -22
    jmp .Led_query_error

FN ext_discovery_shadow
    PROLOGUE
    call ext_discovery_find
    test rdx, rdx
    js 3f
    test rax, rax
    jz 2f
    cmp qword ptr [rax + ESR_status], 0
    jl 1f
    cmp qword ptr [rax + ESR_generation], 0
    jne 1f
2:  xor eax, eax
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
3:  mov rax, rdx
    EPILOGUE

FN ext_discovery_detach
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 3f
    cmp qword ptr [rbx + ED_state], ED_READY
    jne 3f
    call ed_current
    test rax, rax
    js 4f
    mov qword ptr [rbx + ED_guard], 0
    mov qword ptr [rbx + ED_epoch], 0
    mov qword ptr [rbx + ED_state], ED_DETACHED
    mov rax, [rbx + ED_snapshot]
    mov qword ptr [rax + ESS_proof_guard], 0
    mov qword ptr [rax + ESS_proof_epoch], 0
    xor eax, eax
4:  EPILOGUE
3:  mov rax, -22
    EPILOGUE
FN ext_discovery_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 3f
    xor r12d, r12d
1:  cmp r12, [rbx + ED_count]
    jae 2f
    mov rax, r12
    shl rax, 4
    add rax, [rbx + ED_rows]
    mov rdi, [rax + EDR_path]
    call mem_free
    inc r12
    jmp 1b
2:  mov rdi, [rbx + ED_rows]
    call mem_free
    mov rdi, [rbx + ED_rootpath]
    call mem_free
    mov rdi, [rbx + ED_snapshot]
    call ext_store_snapshot_free
    mov rdi, rbx
    call mem_free
3:  xor eax, eax
    EPILOGUE

# Selected candidate retains a coherent lease/payload from one actual ID container.
FN ext_discovery_candidate_try
    PROLOGUE 512
    mov r12, rdi
    call ext_discovery_row
    test rax, rax
    jz .Ledc_null_from_row
    mov r13, [rax + EDR_record]
    mov [rsp + 480], rax
    mov rdi, r12
    call ed_current
    test rax, rax
    js .Ledc_null_error
    mov edi, EDC_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Ledc_nomem
    mov rbx, rax
    mov qword ptr [rbx + EDC_lease], -1
    mov qword ptr [rbx + EDC_payload], -1
    mov rax, [r12 + ED_guard]
    mov [rbx + EDC_guard], rax
    mov rax, [r12 + ED_epoch]
    mov [rbx + EDC_epoch], rax
    lea rdi, [rbx + EDC_owner]
    lea rsi, [r13 + ESR_owner]
    mov edx, 104
    call memcpy
    lea rdi, [rbx + EDC_name]
    lea rsi, [r13 + ESR_name]
    mov edx, 104
    call memcpy
    lea rdi, [rbx + EDC_expected]
    lea rsi, [r13 + ESR_index]
    mov edx, 160
    call memcpy
    lea rdi, [rbx + EDC_id]
    lea rsi, [r13 + ESR_index + EXI_active]
    mov edx, 64
    call memcpy
    mov rax, [rsp + 480]
    mov rdi, [rax + EDR_path]
    call strlen
    lea rdx, [rax + 1]
    mov rax, [rsp + 480]
    mov rsi, [rax + EDR_path]
    lea rdi, [rbx + EDC_path]
    call memcpy
    mov rax, [r12 + ED_snapshot]
    lea rsi, [rax + ESS_tag + EST_root_id]
    lea rdi, [rbx + EDC_rootid]
    mov edx, 32
    call memcpy
    mov rdi, rsp
    mov esi, 255
    mov edx, 32
    call memset
    lea rdi, [rbx + EDC_owner]
    call ext_store_identity_len
    mov rdx, rax
    lea rdi, [rsp + 64]
    lea rsi, [rbx + EDC_owner]
    call ext_store_identity_encode
    lea rdi, [rbx + EDC_name]
    call ext_store_identity_len
    mov rdx, rax
    lea rdi, [rsp + 272]
    lea rsi, [rbx + EDC_name]
    call ext_store_identity_encode
    lea rax, [rip + ed_packages]
    mov [rsp + 32], rax
    lea rax, [rsp + 64]
    mov [rsp + 40], rax
    lea rax, [rsp + 272]
    mov [rsp + 48], rax
    lea rax, [rbx + EDC_id]
    mov [rsp + 56], rax
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
.Ledc_open_dirs:
    mov rdi, [rbx + EDC_guard]
    call ext_store_cancel
    test rax, rax
    js .Ledc_operation_error
    mov rax, [rbx + EDC_guard]
    mov rdi, [rax + ESG_root]
    test r13, r13
    jz 1f
    mov rdi, [rsp + r13*8 - 8]
1:  mov rsi, [rsp + 32 + r13*8]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Ledc_adapter_error
    mov [rsp + r13*8], rax
    test rdx, rdx
    js .Ledc_secondary_primary
    inc r13
    cmp r13, 4
    jb .Ledc_open_dirs
    mov rdi, [rbx + EDC_guard]
    call ext_store_cancel
    test rax, rax
    js .Ledc_operation_error
    mov rdi, [rsp + 24]
    lea rsi, [rip + ed_lease]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Ledc_adapter_error
    mov [rbx + EDC_lease], rax
    test rdx, rdx
    js .Ledc_secondary_primary
    mov rdi, rax
    xor esi, esi
    call ext_store_raw_lock
    test rax, rax
    js .Ledc_operation_error
    mov rdi, [rbx + EDC_guard]
    call ext_store_cancel
    test rax, rax
    js .Ledc_operation_error
    mov rdi, [rsp + 24]
    lea rsi, [rip + ed_payload]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Ledc_adapter_error
    mov [rbx + EDC_payload], rax
    test rdx, rdx
    js .Ledc_secondary_primary
    mov rdi, rax
    lea rsi, [rbx + EDC_payloadid]
    call ext_root_identity
    test rax, rax
    js .Ledc_operation_error
    jmp .Ledc_close_parents
.Ledc_secondary_primary:
    mov rax, rdx
    jmp .Ledc_operation_error
.Ledc_adapter_error:
    test rdx, rdx
    jns .Ledc_operation_error
    mov r15, rdx
.Ledc_operation_error:
    mov r14, rax
.Ledc_close_parents:
    mov r13d, 4
1:  dec r13
    mov rdi, [rsp + r13*8]
    mov qword ptr [rsp + r13*8], -1
    test rdi, rdi
    js 3f
    call ext_root_close
    test rax, rax
    jns 3f
    test r14, r14
    jnz 2f
    mov r14, rax
    jmp 3f
2:  test r15, r15
    jnz 3f
    mov r15, rax
3:  test r13, r13
    jnz 1b
    test r14, r14
    jnz .Ledc_fail_owned
    mov rdi, [rbx + EDC_guard]
    call ext_store_cancel
    test rax, rax
    js .Ledc_finish_error
    mov rdi, r12
    call ed_current
    test rax, rax
    js .Ledc_finish_error
    mov qword ptr [rbx + EDC_flags], 1
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ledc_finish_error:
    mov r14, rax
.Ledc_fail_owned:
    mov rdi, rbx
    call ext_discovery_candidate_free
    test r15, r15
    jnz 1f
    test rax, rax
    jns 2f
    mov r15, rax
    jmp 1f
2:  test rdx, rdx
    jns 1f
    mov r15, rdx
1:  xor eax, eax
    mov rdx, r14
    mov rcx, r15
    EPILOGUE
.Ledc_nomem:
    mov rax, -12
    jmp .Ledc_null_error
.Ledc_null_from_row:
    mov rax, rdx
.Ledc_null_error:
    mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# Pure checked handoff. No borrowed ED pointers survive in EDC.
FN ext_discovery_candidate_check
    test rdi, rdi
    jz .Ledc_check_bad
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EDC_flags], 1
    jne .Ledc_check_owned_bad
    cmp qword ptr [rbx + EDC_payload], 0
    jl .Ledc_check_owned_bad
    mov rax, [rbx + EDC_guard]
    test rax, rax
    jz .Ledc_check_stale
    mov rcx, [rbx + EDC_epoch]
    test rcx, rcx
    jz .Ledc_check_stale
    cmp [rax + ESG_epoch], rcx
    jne .Ledc_check_stale
    lea rdi, [rbx + EDC_expected]
    mov esi, EXI_SIZE
    mov rdx, [rbx + EDC_expected + EXI_generation]
    call ext_index_check
    test eax, eax
    jz .Ledc_check_owned_bad
    cmp dword ptr [rbx + EDC_expected + EXI_flags], EXI_ACTIVE
    jne .Ledc_check_owned_bad
    cmp byte ptr [rbx + EDC_id + 64], 0
    jne .Ledc_check_owned_bad
    lea rdi, [rbx + EDC_id]
    lea rsi, [rbx + EDC_expected + EXI_active]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Ledc_check_owned_bad
    xor eax, eax
    EPILOGUE
.Ledc_check_stale:
    mov rax, -116
    EPILOGUE
.Ledc_check_owned_bad:
    mov rax, -22
    EPILOGUE
.Ledc_check_bad:
    mov rax, -22
    ret
FN ext_discovery_candidate_root
    PROLOGUE
    mov rbx, rdi
    call ext_discovery_candidate_check
    test rax, rax
    js 1f
    mov rax, [rbx + EDC_payload]
1:  EPILOGUE
FN ext_discovery_candidate_take
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .Ledc_take_bad
    call ext_discovery_candidate_check
    test rax, rax
    js 1f
    mov rax, [rbx + EDC_lease]
    test rax, rax
    js .Ledc_take_missing
    mov [r12 + EH_lease], rax
    mov rax, [rbx + EDC_payload]
    mov [r12 + EH_root], rax
    lea rax, [rbx + EDC_path]
    mov [r12 + EH_dir], rax
    lea rax, [rbx + EDC_owner]
    mov [r12 + EH_owner], rax
    lea rax, [rbx + EDC_name]
    mov [r12 + EH_name], rax
    mov qword ptr [rbx + EDC_lease], -1
    xor eax, eax
1:  EPILOGUE
.Ledc_take_missing:
    mov rax, -2
    EPILOGUE
.Ledc_take_bad:
    mov rax, -22
    EPILOGUE
FN ext_discovery_candidate_free
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
    test rbx, rbx
    jz 3f
    mov rdi, [rbx + EDC_payload]
    test rdi, rdi
    js 1f
    call ext_root_close
    test rax, rax
    jns 1f
    mov r12, rax
1:  mov rdi, [rbx + EDC_lease]
    test rdi, rdi
    js 2f
    call ext_root_close
    test rax, rax
    jns 2f
    test r12, r12
    jnz 11f
    mov r12, rax
    jmp 2f
11: mov r13, rax
2:  mov rdi, rbx
    call mem_free
3:  mov rax, r12
    mov rdx, r13
    EPILOGUE
