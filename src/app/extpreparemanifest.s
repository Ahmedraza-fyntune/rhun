# Private manifest products, direct owned strings, commands and compatible mutable defaults.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# prep_owned_join(EP,dir,span,len), matching legacy absolute/relative interpretation.
FN prep_owned_join
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test r14, r14
    jz 1f
.ifdef WINDOWS
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepj_posix_absolute
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call prep_legacy_absolute_join
    test rax, rax
    jnz .Lepj_done
    cmp qword ptr [rbx + PO_error], 0
    jne .Lepj_done
.Lepj_posix_absolute:
.endif
    cmp byte ptr [r13], '/'
    jne 1f
    mov rsi, r13
    mov rdx, r14
    call prep_owned_dup
    EPILOGUE
1:  mov rdi, r12
    call strlen
    mov r15, rax
    lea rsi, [rax + r14 + 2]
    cmp rsi, 4097
    ja .Lepj_bad
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lepj_done
    mov [rsp], rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r15
    call memcpy
    mov rdi, [rsp]
    mov byte ptr [rdi + r15], '/'
    lea rdi, [rdi + r15 + 1]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rax, [rsp]
    lea rcx, [r15 + r14 + 1]
    mov byte ptr [rax + rcx], 0
.Lepj_done:
    EPILOGUE
.Lepj_bad:
    cmp qword ptr [rbx + PO_error], 0
    jne 2f
    mov qword ptr [rbx + PO_error], -EV_BAD_PATH
2:  xor eax, eax
    EPILOGUE

# prep_owned_list_append(EP,slot,span,len), no application scratch SB.
FN prep_owned_list_append
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, [r12]
    xor r15d, r15d
    test rdi, rdi
    jz 1f
    call strlen
    mov r15, rax
1:  mov rsi, r15
    test r15, r15
    jz 2f
    inc rsi
2:  add rsi, r14
    jc .Lepla_bad
    inc rsi
    jz .Lepla_bad
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lepla_done
    mov [rsp], rax
    mov rdi, rax
    mov rsi, [r12]
    mov rdx, r15
    call memcpy
    mov rdi, [rsp]
    add rdi, r15
    test r15, r15
    jz 3f
    mov byte ptr [rdi], ' '
    inc rdi
3:  mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rax, [rsp]
    lea rcx, [r15 + r14]
    test r15, r15
    jz 4f
    inc rcx
4:  mov byte ptr [rax + rcx], 0
    mov rdi, rbx
    mov rsi, [r12]
    call prep_owned_free
    test rax, rax
    jnz .Lepla_done
    mov rax, [rsp]
    mov [r12], rax
.Lepla_done:
    EPILOGUE
.Lepla_bad:
    cmp qword ptr [rbx + PO_error], 0
    jne 5f
    mov qword ptr [rbx + PO_error], -EV_RESOURCE
5:  xor eax, eax
    EPILOGUE

# Exact local key tuple plus compatible CMD prefix, never global registration.
FN ext_prepare_command_add
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rdi + EP_commands]
    mov edx, PC_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lepc_done
    mov r13, rax
    mov rax, [rbx + EP_ext + EXT_owner]
    mov [r13 + PC_owner], rax
    mov rax, [rbx + EP_ext + EXT_name]
    mov [r13 + PC_extension], rax
    lea rax, [rip + ext_cmd_run]
    mov [r13 + CMD_fn], rax
    mov rdi, rbx
    mov rsi, [r12 + INI_key]
    mov rdx, [r12 + INI_keylen]
    call prep_owned_dup
    mov [r13 + PC_key], rax
    test rax, rax
    jz .Lepc_done
    mov rdi, [rbx + EP_ext + EXT_name]
    call strlen
    mov r14, rax
    lea rsi, [rax + 2]
    add rsi, [r12 + INI_keylen]
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lepc_done
    mov [r13 + CMD_name], rax
    mov rdi, rax
    mov rsi, [rbx + EP_ext + EXT_name]
    mov rdx, r14
    call memcpy
    mov rdi, [r13 + CMD_name]
    mov byte ptr [rdi + r14], '.'
    lea rdi, [rdi + r14 + 1]
    mov rsi, [r12 + INI_key]
    mov rdx, [r12 + INI_keylen]
    call memcpy
    # Split title and keys at the first bar, retaining legacy trim behavior.
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + epm_bar]
    mov ecx, 1
    call str_find
    mov r14, rax
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    test r14, r14
    js 1f
    mov rsi, r14
1:  call trim
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov r15, [rbx + EP_ext + EXT_title]
    test r15, r15
    jnz 2f
    mov r15, [rbx + EP_ext + EXT_name]
2:  mov rdi, r15
    call strlen
    mov [rsp + 16], rax
    lea rsi, [rax + 4]
    add rsi, [rsp + 8]
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lepc_done
    mov [r13 + CMD_title], rax
    mov rdi, rax
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call memcpy
    mov rdi, [r13 + CMD_title]
    add rdi, [rsp + 8]
    mov word ptr [rdi], 0x2820
    add rdi, 2
    mov rsi, r15
    mov rdx, [rsp + 16]
    call memcpy
    mov rax, [r13 + CMD_title]
    mov rcx, [rsp + 8]
    add rcx, [rsp + 16]
    mov byte ptr [rax + rcx + 2], ')'
    lea rsi, [rip + epm_empty]
    xor edx, edx
    test r14, r14
    js 3f
    mov rdi, [r12 + INI_val]
    lea rdi, [rdi + r14 + 1]
    mov rsi, [r12 + INI_vallen]
    sub rsi, r14
    dec rsi
    call trim
    mov rsi, rax
3:  mov rdi, rbx
    call prep_owned_dup
    mov [r13 + CMD_keys], rax
    test rax, rax
    jz .Lepc_done
    inc dword ptr [rbx + EP_ext + EXT_ncmd]
.Lepc_done:
    mov rax, [rbx + PO_error]
    EPILOGUE

# Initial coercion parity; SD_value must stay a normal heap allocation for later user choices.
FN ext_prepare_defaults
    PROLOGUE 64
    mov rbx, rdi
    xor r12d, r12d
.Lepd_next:
    cmp r12, [rbx + EP_ext + EXT_sdefs + VEC_len]
    jae .Lepd_done
    cmp qword ptr [rbx + PO_error], 0
    jne .Lepd_done
    imul r13, r12, SD_SIZE
    add r13, [rbx + EP_ext + EXT_sdefs + VEC_ptr]
    mov r14, [r13 + SD_default]
    test r14, r14
    jnz 1f
    lea r14, [rip + epm_empty]
1:  mov eax, [r13 + SD_type]
    cmp eax, SDT_BOOL
    je .Lepd_bool
    cmp eax, SDT_INT
    je .Lepd_int
    cmp eax, SDT_CHOICE
    je .Lepd_choice
    jmp .Lepd_copy
.Lepd_bool:
    mov rdi, r14
    lea rsi, [rip + epm_yes]
    call strcmp_eq
    lea r14, [rip + epm_yes]
    test eax, eax
    jnz .Lepd_copy
    lea r14, [rip + epm_no]
    jmp .Lepd_copy
.Lepd_int:
    mov rdi, r14
    call strlen
    mov rsi, rax
    mov rdi, r14
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepd_managed_int
    call ext_prepare_parse_int31
    jmp .Lepd_int_parsed
.Lepd_managed_int:
    call parse_u64
.Lepd_int_parsed:
    cmp eax, [r13 + SD_min]
    jge 2f
    mov eax, [r13 + SD_min]
2:  cmp eax, [r13 + SD_max]
    jle 3f
    mov eax, [r13 + SD_max]
3:  mov esi, eax
    mov rdi, rsp
    call fmt_u64
    mov byte ptr [rdi], 0
    mov r14, rsp
    jmp .Lepd_copy
.Lepd_choice:
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepd_managed_choice
    mov rdi, r13
    mov rsi, r14
    call sdef_is_option
    test eax, eax
    jnz .Lepd_copy
    mov rdi, [r13 + SD_opts]
    test rdi, rdi
    jz .Lepd_copy
    call strlen
    mov rsi, rax
    mov rdi, [r13 + SD_opts]
    call next_word
    test rdx, rdx
    jz .Lepd_copy
    mov r14, rax
    mov r15, rdx
    jmp .Lepd_span
.Lepd_managed_choice:
    cmp qword ptr [r13 + SD_default], 0
    jne .Lepd_copy
    mov rdi, [r13 + SD_opts]
    test rdi, rdi
    jz .Lepd_bad
    call strlen
    mov rsi, rax
    mov rdi, [r13 + SD_opts]
    call next_word
    mov r14, rax
    mov r15, rdx
    jmp .Lepd_span
.Lepd_copy:
    mov rdi, r14
    call strlen
    mov r15, rax
.Lepd_span:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call prep_owned_dup
    test rax, rax
    jz .Lepd_done
    mov [rsp + 48], rax
    mov rdi, rbx
    mov rsi, [r13 + SD_default]
    call prep_owned_free
    test rax, rax
    jnz .Lepd_done
    mov rax, [rsp + 48]
    mov [r13 + SD_default], rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r15
    call prep_value_dup
    mov [r13 + SD_value], rax
    test rax, rax
    jz .Lepd_done
    inc r12
    jmp .Lepd_next
.Lepd_bad:
    mov qword ptr [rbx + PO_error], -EV_BAD_SETTINGS
.Lepd_done:
    mov rax, [rbx + PO_error]
    EPILOGUE

FN ext_prepare_runs_check
    PROLOGUE
    mov rbx, rdi
    mov r12, [rdi + EP_ext + EXT_runs]
    test r12, r12
    jz 9f
    mov rdi, r12
    call strlen
    mov r13, rax
1:  test r13, r13
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call next_word
    cmp rdx, 4096
    jae 8f
    add r12, rcx
    sub r13, rcx
    jmp 1b
8:  mov qword ptr [rbx + PO_error], -EV_BAD_MANIFEST
9:  mov rax, [rbx + PO_error]
    EPILOGUE
.section .rodata
epm_empty: .asciz ""
epm_bar: .asciz "|"
epm_yes: .asciz "yes"
epm_no: .asciz "no"
