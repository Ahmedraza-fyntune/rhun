# Normalization installs only fully owned values; failed private work stays releasable.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.text
FN esv_normalize_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + EV_phase]
    cmp rax, EVP_NORM_ALLOC
    je .Lnorm_alloc
    cmp rax, EVP_NORM_COPY
    je .Lnorm_copy
    cmp rax, EVP_NORM_INSTALL
    je .Lnorm_install
    cmp rax, EVP_NORMALIZE
    jne .Lnorm_bad
    cmp qword ptr [rbx + EV_subphase], 0
    je .Lnorm_init
    cmp qword ptr [rbx + EV_normtype], SDT_CHOICE
    je .Lnorm_choice
    call esv_scalar_step
    jmp .Lnorm_done
.Lnorm_choice:
    call esv_choice_step
    jmp .Lnorm_done
.Lnorm_init:
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lnorm_input_error
    test rdx, rdx
    jnz .Lnorm_remove
    mov rax, [rax + EC_vallen]
    mov [rbx + EV_normright], rax
    mov qword ptr [rbx + EV_normleft], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_number], 0
    mov qword ptr [rbx + EV_seen], 0
    mov qword ptr [rbx + EV_optionpos], 0
    mov qword ptr [rbx + EV_optionmatch], 0
    mov qword ptr [rbx + EV_optionlen], 0
    mov eax, SDT_BOOL
    cmp qword ptr [rbx + EV_rawkind], 3
    jne 1f
    imul rax, [rbx + EV_rowindex], SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    mov ecx, [rax + SD_min]
    mov [rbx + EV_min], rcx
    mov ecx, [rax + SD_max]
    mov [rbx + EV_max], rcx
    mov eax, [rax + SD_type]
1:  cmp eax, SDT_CHOICE
    ja .Lnorm_bad
    mov [rbx + EV_normtype], rax
    mov qword ptr [rbx + EV_subphase], 1
    jmp .Lnorm_return
.Lnorm_remove:
    cmp qword ptr [rbx + EV_rawkind], 3
    je 1f
    mov qword ptr [rbx + EV_number], 0
    mov rdi, rbx
    call esv_norm_accept
    jmp .Lnorm_done
1:  or qword ptr [rbx + EV_workflags], EVF_REMOVE
    mov qword ptr [rbx + EV_phase], EVP_NORM_INSTALL
    jmp .Lnorm_return
.Lnorm_alloc:
    cmp qword ptr [rbx + EV_allocsleft], 0
    je .Lnorm_return
    mov rdi, [rbx + EV_worklen]
    inc rdi
    dec qword ptr [rbx + EV_allocsleft]
    call ext_settings_memory_try
    test rax, rax
    jz .Lnorm_input_error
    mov [rbx + EV_work], rax
    mov qword ptr [rbx + EV_copypos], 0
    mov qword ptr [rbx + EV_phase], EVP_NORM_COPY
    jmp .Lnorm_return
.Lnorm_copy:
    test qword ptr [rbx + EV_workflags], EVF_DECIMAL
    jnz 1f
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lnorm_input_error
    mov rsi, [rax + EC_value]
    jmp 2f
1:  lea rsi, [rbx + EV_decimal]
2:  add rsi, [rbx + EV_normleft]
    add rsi, [rbx + EV_copypos]
    mov rdx, [rbx + EV_worklen]
    sub rdx, [rbx + EV_copypos]
    jz 3f
    mov rax, [rbx + EV_bytesleft]
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .Lnorm_return
    mov r12, rdx
    mov rdi, [rbx + EV_work]
    add rdi, [rbx + EV_copypos]
    call memcpy
    add [rbx + EV_copypos], r12
    sub [rbx + EV_bytesleft], r12
    mov rax, [rbx + EV_copypos]
    cmp rax, [rbx + EV_worklen]
    jne .Lnorm_return
3:  mov qword ptr [rbx + EV_phase], EVP_NORM_INSTALL
    jmp .Lnorm_return
.Lnorm_install:
    imul r12, [rbx + EV_rowindex], EVR_SIZE
    lea r12, [rbx + r12 + EV_rows]
    test qword ptr [r12 + EVR_flags], EVR_ALIAS_BASE
    jnz 2f
    cmp qword ptr [rbx + EV_allocsleft], 0
    je .Lnorm_return
    mov rdi, [r12 + EVR_value]
    dec qword ptr [rbx + EV_allocsleft]
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lnorm_done
    test rdx, rdx
    jns 2f
    cmp qword ptr [rbx + EV_cleanup], 0
    jne 2f
    mov [rbx + EV_cleanup], rdx
2:  test qword ptr [rbx + EV_workflags], EVF_REMOVE
    jz 3f
    mov rax, [r12 + EVR_base]
    mov rcx, [r12 + EVR_baselen]
    mov edx, EVR_ALIAS_BASE | EVR_DIRTY
    jmp 5f
3:  mov rax, [rbx + EV_work]
    mov rcx, [rbx + EV_worklen]
    mov qword ptr [rbx + EV_work], 0
    mov edx, EVR_RAW_VALID
    test qword ptr [rbx + EV_workflags], EVF_FALLBACK
    jz 4f
    mov edx, EVR_FALLBACK
4:  test qword ptr [rbx + EV_workflags], EVF_DIRTY
    jz 5f
    mov edx, EVR_DIRTY
5:  mov [r12 + EVR_value], rax
    mov [r12 + EVR_vallen], rcx
    mov [r12 + EVR_flags], rdx
    mov rdi, rbx
    call esv_field_advance
    jmp .Lnorm_done
.Lnorm_return:
    xor eax, eax
.Lnorm_done:
    EPILOGUE
.Lnorm_input_error:
    mov rax, rdx
    EPILOGUE
.Lnorm_bad:
    mov rax, -22
    EPILOGUE

# Called after type validation, with worklen/normleft and scalar number prepared.
FN esv_norm_accept
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EV_rawkind], 3
    je 3f
    mov eax, 1
    lea rcx, [rbx + EV_pinned]
    cmp qword ptr [rbx + EV_rawkind], 1
    je 1f
    mov eax, 2
    lea rcx, [rbx + EV_disabled]
1:  mov rdx, [rbx + EV_number]
    mov [rcx], rdx
    or [rbx + EV_flagvalid], rax
    mov rdi, rbx
    call esv_field_advance
    EPILOGUE
3:  imul rax, [rbx + EV_rowindex], EVR_SIZE
    mov rax, [rbx + rax + EV_rows + EVR_keylen]
    add rax, [rbx + EV_worklen]
    jc 4f
    add rax, 12
    jc 4f
    cmp rax, EXT_LINE_MAX
    ja 4f
    mov qword ptr [rbx + EV_phase], EVP_NORM_ALLOC
    xor eax, eax
    EPILOGUE
4:  mov rdi, rbx
    call esv_norm_invalid
    EPILOGUE

# Invalid persisted values retain an earlier valid value or same-schema prior value.
# Invalid current dirty intent blocks preparation and remains queued.
FN esv_norm_invalid
    test qword ptr [rdi + EV_workflags], EVF_DIRTY
    jnz .Lninvalid_dirty
    PROLOGUE
    mov rbx, rdi
    inc qword ptr [rbx + EV_invalid]
    cmp qword ptr [rbx + EV_rawkind], 3
    je .Lninvalid_setting
    mov eax, 1
    lea r12, [rbx + EV_pinned]
    mov r13d, EV_pinned
    cmp qword ptr [rbx + EV_rawkind], 1
    je 1f
    mov eax, 2
    lea r12, [rbx + EV_disabled]
    mov r13d, EV_disabled
1:  test [rbx + EV_flagvalid], rax
    jnz .Lninvalid_skip
    mov rax, [rbx + EV_previous]
    xor edx, edx
    test rax, rax
    jz 2f
    mov rdx, [rax + r13]
2:  mov [r12], rdx
    jmp .Lninvalid_skip
.Lninvalid_setting:
    imul r12, [rbx + EV_rowindex], EVR_SIZE
    lea r12, [rbx + r12 + EV_rows]
    test qword ptr [r12 + EVR_flags], EVR_RAW_VALID | EVR_FALLBACK
    jnz .Lninvalid_skip
    mov rax, [rbx + EV_previous]
    test rax, rax
    jz .Lninvalid_skip
    mov rcx, [rbx + EV_ep]
    cmp [rax + EV_ep], rcx
    jne .Lninvalid_skip
    imul rcx, [rbx + EV_rowindex], EVR_SIZE
    lea rax, [rax + rcx + EV_rows]
    mov rcx, [rax + EVR_value]
    mov rdx, [rax + EVR_vallen]
    mov [rbx + EV_rawvalue], rcx
    mov [rbx + EV_rawvallen], rdx
    mov [rbx + EV_worklen], rdx
    mov qword ptr [rbx + EV_normleft], 0
    mov qword ptr [rbx + EV_workflags], EVF_RAW | EVF_FALLBACK
    mov qword ptr [rbx + EV_phase], EVP_NORM_ALLOC
    xor eax, eax
    EPILOGUE
.Lninvalid_skip:
    mov rdi, rbx
    call esv_field_advance
    EPILOGUE
.Lninvalid_dirty:
    mov rax, -22
    ret

# Each finish unit is bounded; native cleanup cannot change normalized/commit truth.
FN esv_finish_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + EV_subphase]
    test rax, rax
    jz 1f
    cmp rax, 1
    je 3f
    mov rdi, rbx
    call esv_check_epochs
    test rax, rax
    jnz 5f
    mov qword ptr [rbx + EV_phase], EVP_READY
    jmp 5f
1:  mov rdi, [rbx + EV_cursor]
    test rdi, rdi
    jz 2f
    cmp qword ptr [rbx + EV_allocsleft], 0
    je 6f
    dec qword ptr [rbx + EV_allocsleft]
    call ext_settings_ini_free
    cmp rcx, 1
    jne 5f
    test rdx, rdx
    jns 2f
    cmp qword ptr [rbx + EV_cleanup], 0
    jne 2f
    mov [rbx + EV_cleanup], rdx
2:  mov qword ptr [rbx + EV_cursor], 0
    mov qword ptr [rbx + EV_subphase], 1
    jmp 6f
3:  mov rdi, [rbx + EV_previous]
    call ext_settings_view_release
    test rax, rax
    jnz 5f
    mov qword ptr [rbx + EV_previous], 0
    mov qword ptr [rbx + EV_subphase], 2
6:  xor eax, eax
5:  EPILOGUE
