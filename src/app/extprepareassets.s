# Complete bounded flat asset planning, then one immutable source snapshot per step.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# Record mandatory cleanup without replacing a primary failure.
FN prep_note_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + EP_cleanup], 0
    jne 1f
    mov [rdi + EP_cleanup], rsi
1:  ret

# Scanner user is {EP,kind,heldDir}. Exact suffix match, hidden files included.
prep_asset_entry:
    PROLOGUE 48
    mov rbx, [rdi]
    mov r12, rsi
    mov r13, rdx
    mov r14, [rdi + 8]
    mov r15, [rdi + 16]
    lea rcx, [rip + epa_syn]
    mov r8d, 4
    cmp r14, AP_GRAMMAR
    je 1f
    lea rcx, [rip + epa_theme]
    mov r8d, 6
1:  cmp r13, r8
    jb .Lepae_ok
    mov [rsp + 32], r8
    mov rdi, r12
    add rdi, r13
    sub rdi, r8
    mov rsi, rcx
    mov rdx, r8
    call memeq
    test eax, eax
    jz .Lepae_ok
    mov rdi, r15
    mov rsi, r12
    mov edx, ER_ANY
    xor ecx, ecx
    xor r8d, r8d
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepae_managed_open
    call prep_legacy_open_at
    jmp .Lepae_opened
.Lepae_managed_open:
    call ext_root_open_at
.Lepae_opened:
    test rax, rax
    js .Lepae_open_error
    mov [rsp + 40], rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    mov r15, rax
    mov rdi, [rsp + 40]
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    test r15, r15
    js .Lepae_return
    cmp qword ptr [rbx + EP_cleanup], 0
    jne .Lepae_cleanup_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lepae_ok
    cmp qword ptr [rbx + EP_plan + VEC_len], 256
    jae .Lepae_resource
    mov ecx, 2 * 1024 * 1024
    cmp r14, AP_GRAMMAR
    je 2f
    mov ecx, 65536
2:  mov rax, [rsp + ER_size]
    cmp rax, rcx
    ja .Lepae_resource
    add rax, [rbx + EP_assetbytes]
    jc .Lepae_resource
    cmp rax, 16 * 1024 * 1024
    ja .Lepae_resource
    mov [rbx + EP_assetbytes], rax
    mov rdi, rbx
    lea rsi, [rbx + EP_plan]
    mov edx, AP_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lepae_po_error
    mov r15, rax
    mov [rax + AP_kind], r14
    mov rax, [rsp + ER_size]
    mov [r15 + AP_size], rax
    mov rax, [rsp + ER_exec]
    mov [r15 + AP_exec], rax
    mov rdi, rbx
    lea rsi, [rip + epa_syntax]
    cmp r14, AP_GRAMMAR
    je 3f
    lea rsi, [rip + epa_themes]
3:  mov rdx, r12
    mov rcx, r13
    call prep_owned_join
    mov [r15 + AP_path], rax
    test rax, rax
    jz .Lepae_po_error
    mov rdi, rax
    call strlen
    mov [r15 + AP_len], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    sub rdx, [rsp + 32]
    call prep_owned_dup
    mov [r15 + AP_name], rax
    test rax, rax
    jz .Lepae_po_error
.Lepae_ok:
    xor eax, eax
    EPILOGUE
.Lepae_open_error:
    mov r15, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
.Lepae_return:
    mov rax, r15
    EPILOGUE
.Lepae_po_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lepae_cleanup_error:
    mov rax, [rbx + EP_cleanup]
    EPILOGUE
.Lepae_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE

# Open optional asset directory. Only ENOENT with successful cleanup is clean absence.
prep_asset_dir:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rdx
    mov rdi, [rbx + EP_root]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepad_managed_open
    call prep_legacy_open_at
    jmp .Lepad_opened
.Lepad_managed_open:
    call ext_root_open_at
.Lepad_opened:
    test rax, rax
    jns 2f
    mov r13, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
    cmp r13, -2
    jne 1f
    cmp qword ptr [rbx + EP_cleanup], 0
    jne 1f
    xor r13d, r13d
1:  mov rax, r13
    EPILOGUE
2:  mov rcx, EP_syntax
    cmp r12, AP_GRAMMAR
    je 3f
    mov ecx, EP_themes
3:  mov [rbx + rcx], rax
    mov [rsp], rbx
    mov [rsp + 8], r12
    mov [rsp + 16], rax
    mov rdi, rax
    mov esi, 8192
    lea rdx, [rip + prep_asset_entry]
    mov rcx, rsp
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    EPILOGUE

FN prep_asset_plan
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + epa_syntax]
    mov edx, AP_GRAMMAR
    call prep_asset_dir
    test rax, rax
    jnz 9f
    mov rdi, rbx
    lea rsi, [rip + epa_themes]
    mov edx, AP_THEME
    call prep_asset_dir
    test rax, rax
    jnz 9f
    # Bounded insertion sort moves one complete AP record on the stack.
    mov rdi, rbx
    call prep_plan_sort
9:  EPILOGUE

prep_plan_sort:
    PROLOGUE AP_SIZE
    mov rbx, rdi
    mov r12d, 1
1:  cmp r12, [rbx + EP_plan + VEC_len]
    jae 9f
    imul r13, r12, AP_SIZE
    add r13, [rbx + EP_plan + VEC_ptr]
    mov rdi, rsp
    mov rsi, r13
    mov edx, AP_SIZE
    call memcpy
    mov r14, r12
2:  test r14, r14
    jz 4f
    lea rdi, [r13 - AP_SIZE]
    mov rsi, rsp
    call ext_validate_records_compare
    test rax, rax
    jle 4f
    mov rdi, r13
    lea rsi, [r13 - AP_SIZE]
    mov edx, AP_SIZE
    call memcpy
    sub r13, AP_SIZE
    dec r14
    jmp 2b
4:  mov rdi, r13
    mov rsi, rsp
    mov edx, AP_SIZE
    call memcpy
    inc r12
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# Theme name uses the actual header spelling, or exact filename stem when absent.
FN prep_theme_product
    PROLOGUE INI_SIZE + 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp r13, 65536
    ja .Leptp_bad
    cmp qword ptr [rbx + EP_kind], 2
    jne .Leptp_allocate
    mov rdi, r12
    mov rsi, r13
    call prep_ini_text_valid
    test eax, eax
    jz .Leptp_bad
.Leptp_allocate:
    mov rdi, rbx
    lea rsi, [rbx + EP_themeviews]
    mov edx, PT_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Leptp_po_error
    mov r15, rax
    mov [rax + TH_owner], rbx
    mov [rax + TH_src], r12
    mov [rax + TH_len], r13
    mov rax, [r14 + AP_name]
    mov [r15 + TH_id], rax
    mov [rsp + INI_SIZE], rax
    mov rdi, rax
    call strlen
    mov [rsp + INI_SIZE + 8], rax
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call ini_init
1:  mov rdi, rsp
    call ini_next
    test eax, eax
    jz 3f
    cmp qword ptr [rbx + EP_kind], 2
    je .Leptp_header_key
    cmp qword ptr [rsp + INI_seclen], 0
    jne 1b
.Leptp_header_key:
    mov rdi, rsp
    lea rsi, [rip + epa_name]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rax, [rsp + INI_val]
    mov [rsp + INI_SIZE], rax
    mov rax, [rsp + INI_vallen]
    mov [rsp + INI_SIZE + 8], rax
    jmp 1b
3:  mov rsi, [rsp + INI_SIZE + 8]
    cmp qword ptr [rbx + EP_kind], 2
    je .Leptp_copy_name
    cmp rsi, 128
    ja .Leptp_bad
    mov rdi, [rsp + INI_SIZE]
    call ext_validate_text
    test eax, eax
    jz .Leptp_bad
.Leptp_copy_name:
    mov rdi, rbx
    mov rsi, [rsp + INI_SIZE]
    mov rdx, [rsp + INI_SIZE + 8]
    call prep_owned_dup
    mov [r15 + TH_name], rax
    test rax, rax
    jz .Leptp_po_error
    mov rdi, rbx
    mov rsi, [rbx + EP_ext + EXT_dir]
    mov rdx, [r14 + AP_path]
    mov rcx, [r14 + AP_len]
    call prep_owned_join
    mov [r15 + TH_path], rax
    test rax, rax
    jz .Leptp_po_error
    lea rdi, [r15 + PT_palette]
    lea rsi, [r15 + PT_defined]
    lea rdx, [r15 + TH_dark]
    mov rcx, r12
    mov r8, r13
    mov r9d, 1
    cmp qword ptr [rbx + EP_kind], 2
    jne .Leptp_parse
    xor r9d, r9d
.Leptp_parse:
    call theme_parse_into
    test rax, rax
    jnz .Leptp_done
    xor eax, eax
.Leptp_done:
    EPILOGUE
.Leptp_po_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Leptp_bad:
    mov rax, -EV_BAD_THEME
    EPILOGUE

FN ext_prepare_step
    cmp qword ptr [rdi + EP_legacy_import], 1
    je prep_legacy_import_step
    PROLOGUE 112
    mov rbx, rdi
    cmp qword ptr [rbx + PO_ready], 1
    je .Lepstep_ready
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz .Lepstep_done
    mov r12, [rbx + EP_next]
    cmp r12, [rbx + EP_plan + VEC_len]
    jae .Lepstep_finish
    imul r13, r12, AP_SIZE
    add r13, [rbx + EP_plan + VEC_ptr]
    mov rdi, [rbx + EP_root]
    mov rsi, [r13 + AP_path]
    mov rdx, [r13 + AP_len]
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepstep_managed_open
    call prep_legacy_open_relative
    jmp .Lepstep_opened
.Lepstep_managed_open:
    call ext_validate_open_relative
.Lepstep_opened:
    test rax, rax
    js .Lepstep_open_error
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2 * 1024 * 1024
    cmp qword ptr [r13 + AP_kind], AP_GRAMMAR
    je 1f
    mov edx, 65536
1:  call prep_snapshot
    test rax, rax
    jz .Lepstep_snapshot_error
    mov r14, rax
    mov r15, rdx
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepstep_snapshot_stored
    mov [r13 + AP_bytes], rax
    mov [r13 + AP_byteslen], rdx
.Lepstep_snapshot_stored:
    cmp rdx, [r13 + AP_size]
    jne .Lepstep_changed
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rsp + 64]
    call prep_hash_bytes
    mov rdi, rbx
    mov rsi, [r13 + AP_path]
    mov rdx, [r13 + AP_len]
    mov rcx, r15
    mov r8, [r13 + AP_exec]
    lea r9, [rsp + 64]
    mov r10d, SR_GRAMMAR
    cmp qword ptr [r13 + AP_kind], AP_GRAMMAR
    je 2f
    mov r10d, SR_THEME
2:  call prep_source_add
    test rax, rax
    jnz .Lepstep_done
    cmp qword ptr [r13 + AP_kind], AP_GRAMMAR
    jne .Lepstep_theme
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rbx + PO_eo]
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepstep_managed_grammar
    call grammar_parse_prepare_legacy
    jmp .Lepstep_grammar_parsed
.Lepstep_managed_grammar:
    call grammar_parse_prepare
.Lepstep_grammar_parsed:
    test rax, rax
    jnz .Lepstep_grammar_owned
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rcx
    call prep_note_cleanup
    mov rax, r12
    jmp .Lepstep_done
.Lepstep_grammar_owned:
    mov [rsp + 96], rax
    mov rdi, rbx
    lea rsi, [rbx + EP_grammars]
    mov edx, 8
    call prep_owned_vec_push
    test rax, rax
    jnz 3f
    mov rdi, [rsp + 96]
    call grammar_prepare_release
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    mov rax, [rbx + PO_error]
    jmp .Lepstep_done
3:  mov rcx, [rsp + 96]
    mov [rax], rcx
    jmp .Lepstep_parsed
.Lepstep_theme:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, r13
    call prep_theme_product
    test rax, rax
    jnz .Lepstep_done
.Lepstep_parsed:
    cmp qword ptr [rbx + EP_kind], 2
    je .Lepstep_next
    cmp qword ptr [r13 + AP_kind], AP_THEME
    je .Lepstep_next
    mov rdi, rbx
    mov rsi, r14
    call prep_owned_free
    test rax, rax
    jnz .Lepstep_done
.Lepstep_next:
    inc qword ptr [rbx + EP_next]
    mov eax, 1
    jmp .Lepstep_done
.Lepstep_finish:
    mov rdi, rbx
    call prep_sources_sort
    xor r12d, r12d
4:  cmp r12, 3
    jae 6f
    lea rdi, [rbx - RD_PO_BACK]
    lea rsi, [rbx + r12*8 + EP_root]
    mov rdx, r12
    call prep_retire_close_slot
    mov r13, rax
    mov rdi, rbx
    mov rsi, rcx
    call prep_note_cleanup
    test r13, r13
    js 6f
    inc r12
    jmp 4b
6:  mov rax, [rbx + EP_cleanup]
    test rax, rax
    jnz .Lepstep_done
    mov qword ptr [rbx + PO_ready], 1
.Lepstep_ready:
    xor eax, eax
    jmp .Lepstep_done
.Lepstep_changed:
    mov rax, -EV_CHANGED
    jmp .Lepstep_done
.Lepstep_snapshot_error:
    mov rax, rdx
    jmp .Lepstep_done
.Lepstep_open_error:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
    mov rax, r12
.Lepstep_done:
    test rax, rax
    jns 7f
    cmp qword ptr [rbx + PO_error], 0
    jne 7f
    mov [rbx + PO_error], rax
7:  mov rdx, [rbx + EP_cleanup]
    EPILOGUE
.section .rodata
epa_syn: .asciz ".syn"
epa_theme: .asciz ".theme"
epa_syntax: .asciz "syntax"
epa_themes: .asciz "themes"
epa_name: .asciz "name"
