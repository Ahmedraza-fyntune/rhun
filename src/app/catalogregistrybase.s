# Startup-only base capture, bounded string work, and owned qualified-path scratch.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.text
FN registry_base_begin
    PROLOGUE 64
    test rdi, rdi
    jz .Lrbb_invalid
    mov rax, rdi
    add rax, RBI_SIZE
    jc .Lrbb_invalid
    mov rsi, rdi
    mov rdi, rsp
    mov edx, RBI_SIZE
    call memcpy
    cmp qword ptr [rsp + RBI_reserved], 0
    jne .Lrbb_invalid
    cmp qword ptr [rsp + RBI_version], 0
    jle .Lrbb_invalid
    mov rax, [rsp + RBI_ngrammar]
    cmp rax, REG_ROW_CAP
    ja .Lrbb_invalid
    cmp [rsp + RBI_nuser], rax
    ja .Lrbb_invalid
    test rax, rax
    jz 1f
    mov rcx, [rsp + RBI_grammars]
    test rcx, rcx
    jz .Lrbb_invalid
    shl rax, 3
    add rax, rcx
    jc .Lrbb_invalid
1:  mov rax, [rsp + RBI_ntheme]
    cmp rax, REG_ROW_CAP
    ja .Lrbb_invalid
    mov rcx, [rsp + RBI_follow]
    cmp rcx, -1
    je 2f
    cmp rcx, rax
    jae .Lrbb_invalid
2:  test rax, rax
    jz 3f
    mov rcx, [rsp + RBI_themes]
    test rcx, rcx
    jz .Lrbb_invalid
    imul rax, rax, TH_SIZE
    add rax, rcx
    jc .Lrbb_invalid
3:  mov edi, C7_BASE
    call catalog_object_create
    test rax, rax
    jz .Lrbb_return
    test rdx, rdx
    jnz .Lrbb_return
    mov rbx, rax
    lea rdi, [rbx + RB_input]
    mov rsi, rsp
    mov edx, RBI_SIZE
    call memcpy
    mov rax, [rsp + RBI_nuser]
    mov [rbx + RB_nuser], rax
    mov rdx, [rsp + RBI_ngrammar]
    sub rdx, rax
    mov [rbx + RB_nbuiltin], rdx
    mov rax, [rsp + RBI_ntheme]
    mov [rbx + RB_ntheme], rax
    mov rax, [rsp + RBI_follow]
    mov [rbx + RB_follow], rax
    mov rax, [rsp + RBI_version]
    mov [rbx + RB_version], rax
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
.Lrbb_return:
    EPILOGUE
.Lrbb_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    EPILOGUE

# Exact caller-supplied CURRENT startup snapshot, before any borrowed source access.
FN registry_base_input_check
    test rsi, rsi
    jz .Lrbic_bad
    mov rax, rsi
    add rax, RBI_SIZE
    jc .Lrbic_bad
    lea rdi, [rdi + RB_input]
    mov edx, RBI_SIZE
    PROLOGUE
    call memeq
    test eax, eax
    jz 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -116
    EPILOGUE
.Lrbic_bad:
    mov rax, -22
    ret

# Consume one genuinely Small foreign path or an unused reservation. No native close.
# Returns0/consumed1, R8 didWork; invalid shape preserves every pointer and charge.
FN catalog_base_scratch_consume
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + RB_scratch]
    test rdi, rdi
    jz .Lrbsc_reserve
    cmp qword ptr [rbx + RB_reservation], 0
    jne .Lrbsc_bad
    cmp qword ptr [rdi - 16], 8
    ja .Lrbsc_bad
    call prep_pointer_charge
    mov r14, rax
    cmp rax, [rbx + RB_scratch_charge]
    jne .Lrbsc_bad
    test rax, rax
    jz .Lrbsc_bad
    mov r13, [rbx + PO_eo]
    cmp [r13 + EO_used], rax
    jb .Lrbsc_bad
    cmp [rip + prep_total_charge], rax
    jb .Lrbsc_bad
    mov rdi, [rbx + RB_scratch]
    call mem_free
    mov qword ptr [rbx + RB_scratch], 0
    mov qword ptr [rbx + RB_scratch_charge], 0
    sub [r13 + EO_used], r14
    sub [rip + prep_total_charge], r14
    mov r8d, 1
    jmp .Lrbsc_done
.Lrbsc_reserve:
    cmp qword ptr [rbx + RB_scratch_charge], 0
    jne .Lrbsc_bad
    mov rax, [rbx + RB_reservation]
    test rax, rax
    jz .Lrbsc_empty
    cmp rax, REG_SMALL_RESERVATION
    ja .Lrbsc_bad
    mov rcx, [rbx + PO_eo]
    cmp [rcx + EO_used], rax
    jb .Lrbsc_bad
    cmp [rip + prep_total_charge], rax
    jb .Lrbsc_bad
    sub [rcx + EO_used], rax
    sub [rip + prep_total_charge], rax
    mov qword ptr [rbx + RB_reservation], 0
    mov r8d, 1
    jmp .Lrbsc_done
.Lrbsc_empty:
    xor r8d, r8d
.Lrbsc_done:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lrbsc_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    xor r8d, r8d
    EPILOGUE

# Dedicated startup operation. It is not hidden inside a budgeted merge/copy step.
FN registry_base_qualify_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, C7_BASE
    call catalog_is_owned
    test eax, eax
    jz .Lrbq_invalid
    mov rax, [rbx + PO_error]
    test rax, rax
    js .Lrbq_terminal
    cmp qword ptr [rbx + RB_phase], RB_READY
    je .Lrbq_ready
    cmp qword ptr [rbx + RB_phase], RB_NEEDS_QUALIFY
    jne .Lrbq_invalid
    mov rdi, rbx
    mov rsi, r12
    call registry_base_input_check
    test rax, rax
    js .Lrbq_fail
    cmp qword ptr [rbx + RB_scratch], 0
    jne .Lrbq_corrupt
    cmp qword ptr [rbx + RB_reservation], 0
    jne .Lrbq_corrupt
    cmp qword ptr [rbx + RB_scratch_charge], 0
    jne .Lrbq_corrupt
    mov r13, [rbx + PO_eo]
    mov rax, [r13 + EO_used]
    add rax, REG_SMALL_RESERVATION
    jc .Lrbq_resource
    cmp rax, [r13 + EO_cap]
    ja .Lrbq_resource
    mov edi, REG_SMALL_RESERVATION
    call prep_global_admit
    test rax, rax
    js .Lrbq_fail
    add qword ptr [r13 + EO_used], REG_SMALL_RESERVATION
    add qword ptr [rip + prep_total_charge], REG_SMALL_RESERVATION
    mov qword ptr [rbx + RB_reservation], REG_SMALL_RESERVATION
    mov rax, [rbx + RB_current]
    mov rdi, [rax + TH_path]
    call theme_capture_path_snapshot
    test rax, rax
    jz .Lrbq_helper_failure
    mov [rbx + RB_scratch], rax
    cmp qword ptr [rax - 16], 8
    ja .Lrbq_corrupt
    cmp qword ptr [rax - 8], 0
    je .Lrbq_corrupt
    cmp qword ptr [rax - 8], 4096
    ja .Lrbq_corrupt
    mov rdi, rax
    call prep_pointer_charge
    mov [rbx + RB_scratch_charge], rax
    mov rcx, REG_SMALL_RESERVATION
    sub rcx, rax
    sub [r13 + EO_used], rcx
    sub [rip + prep_total_charge], rcx
    mov qword ptr [rbx + RB_reservation], 0
    mov qword ptr [rbx + RB_subphase], 0
    mov qword ptr [rbx + RB_phase], RB_COPY_QUALIFIED
.Lrbq_ready:
    xor eax, eax
.Lrbq_terminal:
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    EPILOGUE
.Lrbq_helper_failure:
    mov r14, rdx
    mov rdi, rbx
    call catalog_base_scratch_consume
    test rax, rax
    js .Lrbq_fail
    mov rax, r14
    test rax, rax
    js .Lrbq_fail
.Lrbq_corrupt:
    mov rax, -EV_BAD_PREPARE
    jmp .Lrbq_fail
.Lrbq_resource:
    mov rax, -EV_RESOURCE
.Lrbq_fail:
    mov rdi, rbx
    call catalog_fail
    jmp .Lrbq_terminal
.Lrbq_invalid:
    mov rax, -22
    mov rdx, rax
    xor ecx, ecx
    EPILOGUE

# One bounded string unit. Subphase1 scan,2 allocation,3 copy; DX1 allocation attempt.
FN registry_base_string_unit
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + RB_subphase]
    cmp rax, 1
    je .Lrbs_scan
    cmp rax, 2
    je .Lrbs_allocate
    cmp rax, 3
    je .Lrbs_copy
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    EPILOGUE
.Lrbs_scan:
    mov r14, [rbx + RB_budget]
    sub r14, [rbx + RB_bytes]
    jz .Lrbs_pending
    cmp r14, REG_BYTE_UNIT
    jbe 1f
    mov r14d, REG_BYTE_UNIT
1:  inc qword ptr [rbx + RB_units]
    mov r12, [rbx + RB_string_source]
    mov r13, [rbx + RB_string_cursor]
    mov rcx, [rbx + RB_string_limit]
    xor r15d, r15d
2:  movzx eax, byte ptr [r12 + r13]
    inc r15
    dec r14
    test eax, eax
    jz .Lrbs_length_done
    cmp r13, rcx
    jae .Lrbs_too_long
    inc r13
    test r14, r14
    jnz 2b
    add [rbx + RB_bytes], r15
    mov [rbx + RB_string_cursor], r13
    jmp .Lrbs_pending
.Lrbs_length_done:
    add [rbx + RB_bytes], r15
    mov [rbx + RB_string_length], r13
    mov rax, [rbx + RB_length_slot]
    mov [rax], r13
    mov qword ptr [rbx + RB_subphase], 2
    jmp .Lrbs_pending
.Lrbs_too_long:
    add [rbx + RB_bytes], r15
    mov rax, [rbx + RB_string_error]
    xor edx, edx
    EPILOGUE
.Lrbs_allocate:
    inc qword ptr [rbx + RB_units]
    mov rsi, [rbx + RB_string_length]
    inc rsi
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lrbs_allocation_failed
    mov [rbx + RB_string_dest], rax
    mov rcx, [rbx + RB_string_slot]
    mov [rcx], rax
    mov qword ptr [rbx + RB_string_cursor], 0
    mov qword ptr [rbx + RB_subphase], 3
    mov eax, 1
    mov edx, 1
    EPILOGUE
.Lrbs_allocation_failed:
    mov rax, rdx
    mov edx, 1
    EPILOGUE
.Lrbs_copy:
    mov r14, [rbx + RB_budget]
    sub r14, [rbx + RB_bytes]
    jz .Lrbs_pending
    cmp r14, REG_BYTE_UNIT
    jbe 3f
    mov r14d, REG_BYTE_UNIT
3:  mov r13, [rbx + RB_string_cursor]
    mov rax, [rbx + RB_string_length]
    inc rax
    sub rax, r13
    cmp r14, rax
    cmova r14, rax
    mov rdi, [rbx + RB_string_dest]
    add rdi, r13
    mov rsi, [rbx + RB_string_source]
    add rsi, r13
    mov rdx, r14
    call memcpy
    add [rbx + RB_bytes], r14
    inc qword ptr [rbx + RB_units]
    add r13, r14
    mov [rbx + RB_string_cursor], r13
    mov rax, [rbx + RB_string_length]
    inc rax
    cmp r13, rax
    jb .Lrbs_pending
    mov qword ptr [rbx + RB_subphase], 0
    mov qword ptr [rbx + RB_string_source], 0
    mov qword ptr [rbx + RB_string_dest], 0
    mov qword ptr [rbx + RB_string_slot], 0
    mov qword ptr [rbx + RB_length_slot], 0
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lrbs_pending:
    mov eax, 1
    xor edx, edx
    EPILOGUE

FN registry_base_step
    PROLOGUE
    mov rbx, rdi
    mov r14, rsi
    mov r15, rdx
    test r15, r15
    jz .Lrb_invalid
    cmp r15, REG_STEP_BYTES
    ja .Lrb_invalid
    mov esi, C7_BASE
    call catalog_is_owned
    test eax, eax
    jz .Lrb_invalid
    mov rax, [rbx + PO_error]
    test rax, rax
    js .Lrb_cached_terminal
    cmp qword ptr [rbx + RB_phase], RB_READY
    je .Lrb_cached_ready
    mov qword ptr [rbx + RB_units], 0
    mov qword ptr [rbx + RB_bytes], 0
    mov [rbx + RB_budget], r15
    mov rdi, rbx
    mov rsi, r14
    call registry_base_input_check
    test rax, rax
    js .Lrb_fail
.Lrb_loop:
    cmp qword ptr [rbx + RB_units], REG_STEP_UNITS
    jae .Lrb_pending
    mov rax, [rbx + RB_phase]
    cmp rax, RB_ALLOCATE
    je .Lrb_allocate
    cmp rax, RB_COPY_GR
    je .Lrb_grammar
    cmp rax, RB_COPY_THEME
    je .Lrb_theme
    cmp rax, RB_NEEDS_QUALIFY
    je .Lrb_pending
    cmp rax, RB_COPY_QUALIFIED
    je .Lrb_qualified
    cmp rax, RB_FINALIZE
    je .Lrb_finalize
    mov rax, -EV_BAD_PREPARE
    jmp .Lrb_fail
.Lrb_allocate:
    mov rax, [rbx + RB_alloc_stage]
    test rax, rax
    jz .Lrb_alloc_users
    cmp rax, 1
    je .Lrb_alloc_builtins
    cmp rax, 2
    je .Lrb_alloc_themes
    cmp rax, 3
    je .Lrb_alloc_meta
    cmp rax, 4
    jne .Lrb_corrupt
    mov qword ptr [rbx + RB_phase], RB_COPY_GR
    mov qword ptr [rbx + RB_index], 0
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_alloc_users:
    mov rsi, [rbx + RB_nuser]
    shl rsi, 3
    lea r13, [rbx + RB_users]
    jmp .Lrb_do_allocate
.Lrb_alloc_builtins:
    mov rsi, [rbx + RB_nbuiltin]
    shl rsi, 3
    lea r13, [rbx + RB_builtins]
    jmp .Lrb_do_allocate
.Lrb_alloc_themes:
    imul rsi, [rbx + RB_ntheme], TH_SIZE
    lea r13, [rbx + RB_themes]
    jmp .Lrb_do_allocate
.Lrb_alloc_meta:
    imul rsi, [rbx + RB_ntheme], BTM_SIZE
    lea r13, [rbx + RB_meta]
.Lrb_do_allocate:
    inc qword ptr [rbx + RB_units]
    inc qword ptr [rbx + RB_alloc_stage]
    test rsi, rsi
    jz .Lrb_loop
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lrb_allocation_failure
    mov [r13], rax
    jmp .Lrb_pending
.Lrb_grammar:
    mov r13, [rbx + RB_index]
    cmp r13, [rbx + RB_input + RBI_ngrammar]
    jae .Lrb_grammar_done
    mov rax, [rbx + RB_input + RBI_grammars]
    mov rax, [rax + r13*8]
    test rax, rax
    jz .Lrb_corrupt
    cmp qword ptr [rax + GR_owner], 0
    jne .Lrb_corrupt
    mov rcx, [rbx + RB_nuser]
    cmp r13, rcx
    jae 4f
    mov rcx, [rbx + RB_users]
    mov [rcx + r13*8], rax
    jmp 5f
4:  sub r13, rcx
    mov rcx, [rbx + RB_builtins]
    mov [rcx + r13*8], rax
5:  inc qword ptr [rbx + RB_index]
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_grammar_done:
    mov qword ptr [rbx + RB_index], 0
    mov qword ptr [rbx + RB_phase], RB_COPY_THEME
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_theme:
    mov rax, [rbx + RB_index]
    cmp rax, [rbx + RB_ntheme]
    jae .Lrb_theme_done
    mov r13, [rbx + RB_task]
    test r13, r13
    jz .Lrb_theme_start
    cmp r13, 4
    je .Lrb_theme_finish
    cmp qword ptr [rbx + RB_subphase], 0
    jne .Lrb_string
    mov r12, [rbx + RB_current]
    imul r14, rax, BTM_SIZE
    add r14, [rbx + RB_meta]
    cmp r13, 1
    je .Lrb_start_id
    cmp r13, 2
    je .Lrb_start_name
    cmp r13, 3
    jne .Lrb_corrupt
    cmp qword ptr [r14 + BTM_kind], REG_USER
    jne .Lrb_next_task
    mov rax, [r12 + TH_path]
    lea rcx, [r12 + TH_path]
    lea rdx, [r14 + BTM_keylen]
    mov rsi, 4095
    jmp .Lrb_start_short
.Lrb_start_id:
    mov rax, [r12 + TH_id]
    lea rcx, [r12 + TH_id]
    lea rdx, [r14 + BTM_idlen]
    mov rsi, 4095
.Lrb_start_short:
    mov qword ptr [rbx + RB_string_error], -36
    jmp .Lrb_start_string
.Lrb_start_name:
    mov rax, [r12 + TH_name]
    lea rcx, [r12 + TH_name]
    lea rdx, [r14 + BTM_namelen]
    mov rsi, [rbx + PO_eo]
    mov rdi, [rsi + EO_cap]
    sub rdi, [rsi + EO_used]
    jbe .Lrb_resource
    lea rsi, [rdi - 1]
    mov qword ptr [rbx + RB_string_error], -EV_RESOURCE
.Lrb_start_string:
    test rax, rax
    jz .Lrb_corrupt
    mov [rbx + RB_string_source], rax
    mov [rbx + RB_string_slot], rcx
    mov [rbx + RB_length_slot], rdx
    mov [rbx + RB_string_limit], rsi
    mov qword ptr [rbx + RB_string_cursor], 0
    mov qword ptr [rbx + RB_subphase], 1
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_string:
    mov r13, [rbx + RB_units]
    mov rdi, rbx
    call registry_base_string_unit
    test rax, rax
    js .Lrb_fail
    test rdx, rdx
    jnz .Lrb_pending
    test rax, rax
    jz .Lrb_task_done
    cmp [rbx + RB_units], r13
    je .Lrb_pending
    jmp .Lrb_loop
.Lrb_next_task:
    inc qword ptr [rbx + RB_units]
.Lrb_task_done:
    inc qword ptr [rbx + RB_task]
    jmp .Lrb_loop
.Lrb_theme_start:
    imul r13, rax, TH_SIZE
    add r13, [rbx + RB_input + RBI_themes]
    cmp qword ptr [r13 + TH_owner], 0
    jne .Lrb_corrupt
    mov r12d, REG_FOLLOW
    cmp rax, [rbx + RB_follow]
    je .Lrb_class_follow
    cmp qword ptr [r13 + TH_src], 0
    je .Lrb_class_user
    cmp qword ptr [r13 + TH_path], 0
    jne .Lrb_corrupt
    mov r12d, REG_BUILTIN
    jmp .Lrb_copy_descriptor
.Lrb_class_user:
    cmp qword ptr [r13 + TH_path], 0
    je .Lrb_corrupt
    mov r12d, REG_USER
    jmp .Lrb_copy_descriptor
.Lrb_class_follow:
    cmp qword ptr [r13 + TH_src], 0
    jne .Lrb_corrupt
    cmp qword ptr [r13 + TH_path], 0
    jne .Lrb_corrupt
.Lrb_copy_descriptor:
    imul r14, rax, BTM_SIZE
    add r14, [rbx + RB_meta]
    mov [r14 + BTM_kind], r12
    mov rax, [rbx + RB_index]
    imul rdi, rax, TH_SIZE
    add rdi, [rbx + RB_themes]
    mov [rbx + RB_current], rdi
    mov rsi, r13
    mov edx, TH_SIZE
    call memcpy
    mov qword ptr [rbx + RB_task], 1
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_theme_finish:
    imul r13, [rbx + RB_index], BTM_SIZE
    add r13, [rbx + RB_meta]
    cmp qword ptr [r13 + BTM_kind], REG_USER
    jne .Lrb_next_theme
    mov rax, [rbx + RB_current]
    mov rax, [rax + TH_path]
    mov [r13 + BTM_key], rax
    mov qword ptr [rbx + RB_phase], RB_NEEDS_QUALIFY
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_pending
.Lrb_next_theme:
    inc qword ptr [rbx + RB_index]
    mov qword ptr [rbx + RB_task], 0
    mov qword ptr [rbx + RB_subphase], 0
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_theme_done:
    mov qword ptr [rbx + RB_phase], RB_FINALIZE
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_qualified:
    cmp qword ptr [rbx + RB_subphase], 4
    je .Lrb_qualified_free
    cmp qword ptr [rbx + RB_subphase], 0
    jne .Lrb_qualified_string
    imul r13, [rbx + RB_index], BTM_SIZE
    add r13, [rbx + RB_meta]
    mov rax, [rbx + RB_scratch]
    test rax, rax
    jz .Lrb_corrupt
    mov [rbx + RB_string_source], rax
    mov rax, [rax - 8]
    dec rax
    mov [rbx + RB_string_length], rax
    mov [r13 + BTM_pathlen], rax
    lea rax, [r13 + BTM_path]
    mov [rbx + RB_string_slot], rax
    lea rax, [r13 + BTM_pathlen]
    mov [rbx + RB_length_slot], rax
    mov qword ptr [rbx + RB_subphase], 2
    inc qword ptr [rbx + RB_units]
    jmp .Lrb_loop
.Lrb_qualified_string:
    mov r13, [rbx + RB_units]
    mov rdi, rbx
    call registry_base_string_unit
    test rax, rax
    js .Lrb_fail
    test rdx, rdx
    jnz .Lrb_pending
    test rax, rax
    jz 6f
    cmp [rbx + RB_units], r13
    je .Lrb_pending
    jmp .Lrb_loop
6:  mov qword ptr [rbx + RB_subphase], 4
    jmp .Lrb_loop
.Lrb_qualified_free:
    mov rdi, rbx
    call catalog_base_scratch_consume
    test rax, rax
    js .Lrb_fail
    inc qword ptr [rbx + RB_units]
    inc qword ptr [rbx + RB_index]
    mov qword ptr [rbx + RB_task], 0
    mov qword ptr [rbx + RB_subphase], 0
    mov qword ptr [rbx + RB_phase], RB_COPY_THEME
    jmp .Lrb_pending
.Lrb_finalize:
    lea rdi, [rbx + RB_view]
    lea rsi, [rbx + RB_users]
    mov edx, 64
    call memcpy
    mov rax, [rbx + RB_ntheme]
    mov [rbx + RB_view + 40], rax
    mov rax, [rbx + RB_meta]
    mov [rbx + RB_view + 48], rax
    mov rax, [rbx + RB_version]
    mov [rbx + RB_view + 64], rax
    mov qword ptr [rbx + RB_view + 72], 0
    mov qword ptr [rbx + RB_input + RBI_grammars], 0
    mov qword ptr [rbx + RB_input + RBI_themes], 0
    mov qword ptr [rbx + RB_current], 0
    mov qword ptr [rbx + PO_ready], 1
    mov qword ptr [rbx + RB_phase], RB_READY
    inc qword ptr [rbx + RB_units]
.Lrb_ready:
    xor eax, eax
    jmp .Lrb_return
.Lrb_allocation_failure:
    mov rax, rdx
    jmp .Lrb_fail
.Lrb_resource:
    mov rax, -EV_RESOURCE
    jmp .Lrb_fail
.Lrb_corrupt:
    mov rax, -EV_BAD_PREPARE
.Lrb_fail:
    mov rdi, rbx
    call catalog_fail
.Lrb_terminal:
    mov rax, [rbx + PO_error]
    jmp .Lrb_return
.Lrb_pending:
    mov eax, 1
.Lrb_return:
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    mov r8, [rbx + RB_bytes]
    mov r9, [rbx + RB_units]
    EPILOGUE
.Lrb_cached_ready:
    xor eax, eax
.Lrb_cached_terminal:
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
.Lrb_invalid:
    mov rax, -22
    mov rdx, rax
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
