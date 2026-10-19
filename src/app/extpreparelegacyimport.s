# Pure owned import: no payload handle, pathname availability or runtime resolution.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extpreparelegacy.inc"
.text
# A bounded callback-produced C string equals a counted transcript field.
prep_legacy_span_equal:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov esi, 4095
    call ext_root_length
    cmp rax, r13
    jne 8f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call memeq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# bytes,len,borrowedConfig56 ->pendingEP or0/RDXprimary/RCXcleanup.
# All failure paths leave config lease caller-owned. Payload directory slots stay -1.
FN ext_prepare_import_legacy
    xor r10d, r10d
    jmp .Lelpi_begin
FN ext_prepare_import_legacy_deferred
    mov r10d, 1
.Lelpi_begin:
    PROLOGUE 96
    mov [rsp + 40], r10
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .Lelpi_bad_initial
    cmp qword ptr [r13 + LI_tag], 0
    je .Lelpi_bad_initial
    mov rdi, [r13 + LI_dir]
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lelpi_bad_initial
    mov rdi, [r13 + LI_dir]
    mov rsi, rax
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lelpi_bad_initial
    cmp dword ptr [r13 + 44], 0
    jne .Lelpi_bad_initial
    mov eax, [r13 + LI_drive]
.ifdef WINDOWS
    test eax, eax
    jz .Lelpi_valid_drive
    sub eax, 'A'
    cmp eax, 25
    ja .Lelpi_bad_initial
.Lelpi_valid_drive:
.else
    test eax, eax
    jnz .Lelpi_bad_initial
.endif
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + LI_tag]
    call prep_legacy_snapshot_check
    test rax, rax
    jnz .Lelpi_initial_error
    mov eax, [r13 + LI_drive]
    cmp eax, [rbx + LS_drive]
    jne .Lelpi_bad_initial
    mov rdi, -1
    mov rsi, [r13 + LI_dir]
    mov rdx, [r13 + LI_owner]
    mov rcx, [r13 + LI_name]
    call ext_prepare_alloc_legacy
    test rax, rax
    jz .Lelpi_done
    mov r14, rax
    cmp qword ptr [rsp + 40], 0
    je 8f
    mov rdi, r14
    call ext_prepare_enable_deferred
    test rax, rax
    jnz .Lelpi_fail
8:  mov qword ptr [r14 + EP_legacy_import], 1
    mov [rsp], r13
.ifdef WINDOWS
    mov rdi, r14
    mov rsi, [r13 + LI_cwd]
    mov edx, [r13 + LI_drive]
    call prep_legacy_set_context
    test rax, rax
    jnz .Lelpi_fail
.endif
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r12
    call prep_owned_dup
    test rax, rax
    jz .Lelpi_po_error
    mov rbx, rax
    mov [r14 + EP_legacy_wire], rax
    mov [r14 + EP_legacy_wirelen], r12
    mov eax, [rbx + LS_programlen]
    mov edx, [rbx + LS_scriptlen]
    lea r15, [rbx + rax + LS_HEADER]
    add r15, rdx
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0  # selected absolute SR
.Lelpi_record:
    mov rax, [rsp + 8]
    cmp eax, [rbx + LS_count]
    jae .Lelpi_parse
    lea r12, [r15 + LR_SIZE]
    mov edx, [r15 + LR_pathlen]
    mov rdi, r14
    mov rsi, r12
    mov rcx, [r15 + LR_size]
    mov r8d, [r15 + LR_exec]
    lea r9, [r15 + LR_hash]
    mov r10d, [r15 + LR_roles]
    call prep_source_add
    test rax, rax
    jnz .Lelpi_fail
    mov eax, [r15 + LR_pathlen]
    add r12, rax
    cmp dword ptr [r15 + LR_roles], SR_MANIFEST
    jne 1f
    mov [r14 + EP_manifest], r12
    mov rax, [r15 + LR_datalen]
    mov [r14 + EP_manifestlen], rax
    jmp .Lelpi_next
1:  mov rax, [r14 + EP_sources + VEC_len]
    dec rax
    imul rax, rax, SR_SIZE
    add rax, [r14 + EP_sources + VEC_ptr]
    cmp dword ptr [r15 + LR_roles], SR_LAUNCH | SR_EXTERNAL
    jne 2f
    mov [rsp + 16], rax
    jmp .Lelpi_next
2:  mov [rsp + 24], rax
    mov rdi, r14
    lea rsi, [r14 + EP_plan]
    mov edx, AP_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lelpi_po_error
    mov r13, rax
    mov rax, [rsp + 24]
    mov rcx, [rax + SR_path]
    mov [r13 + AP_path], rcx
    mov rcx, [rax + SR_len]
    mov [r13 + AP_len], rcx
    mov rax, [r15 + LR_size]
    mov [r13 + AP_size], rax
    mov eax, [r15 + LR_exec]
    mov [r13 + AP_exec], rax
    mov [r13 + AP_bytes], r12
    mov rax, [r15 + LR_datalen]
    mov [r13 + AP_byteslen], rax
    mov qword ptr [r13 + AP_kind], AP_GRAMMAR
    mov ecx, 4
    cmp dword ptr [r15 + LR_roles], SR_GRAMMAR
    je 3f
    mov qword ptr [r13 + AP_kind], AP_THEME
    mov ecx, 6
3:  mov edx, [r15 + LR_pathlen]
    sub edx, 7
    sub edx, ecx
    mov rdi, r14
    lea rsi, [r15 + LR_SIZE + 7]
    call prep_owned_dup
    mov [r13 + AP_name], rax
    test rax, rax
    jz .Lelpi_po_error
.Lelpi_next:
    mov rax, [r15 + LR_datalen]
    lea r15, [r12 + rax]
    inc qword ptr [rsp + 8]
    jmp .Lelpi_record
.Lelpi_parse:
    mov rdi, r14
    mov rsi, [r14 + EP_manifest]
    mov rdx, [r14 + EP_manifestlen]
    call prep_legacy_manifest
    test rax, rax
    jnz .Lelpi_fail
    mov eax, [rbx + LS_programlen]
    lea r12, [rbx + rax + LS_HEADER]
    mov rdi, [r14 + EP_ext + EXT_script]
    test rdi, rdi
    jz .Lelpi_native_argv
    mov rsi, r12
    mov edx, [rbx + LS_scriptlen]
    call prep_legacy_span_equal
    test eax, eax
    jz .Lelpi_changed
    mov rdi, r14
    lea rsi, [rbx + LS_HEADER]
    mov edx, [rbx + LS_programlen]
    call prep_owned_dup
    test rax, rax
    jz .Lelpi_po_error
    mov [rsp + 32], rax
    mov rdi, r14
    mov rsi, [r14 + EP_ext + EXT_prog]
    call prep_owned_free
    test rax, rax
    jnz .Lelpi_fail
    mov rax, [rsp + 32]
    mov [r14 + EP_ext + EXT_prog], rax
    jmp .Lelpi_selected
.Lelpi_native_argv:
    cmp dword ptr [rbx + LS_scriptlen], 0
    jne .Lelpi_changed
    mov rdi, [r14 + EP_ext + EXT_prog]
    lea rsi, [rbx + LS_HEADER]
    mov edx, [rbx + LS_programlen]
    call prep_legacy_span_equal
    test eax, eax
    jz .Lelpi_changed
.Lelpi_selected:
    mov rdi, [r14 + EP_ext + EXT_script]
    test rdi, rdi
    jz 4f
    cmp byte ptr [rdi], 0
    jne 5f
4:  mov rdi, [r14 + EP_ext + EXT_prog]
5:  mov rax, [rsp + 16]
    mov rsi, [rax + SR_path]
    call strcmp_eq
    test eax, eax
    jz .Lelpi_changed
    mov dword ptr [r14 + EP_ext + EXT_manifest_ok], 1
    lea rdi, [r14 + EP_legacy_source]
    lea rsi, [rbx + LS_source]
    mov edx, 32
    call memcpy
    mov rax, [r14 + PO_eo]
    mov rcx, [rsp]
    mov rcx, [rcx + LI_lease]
    mov [rax + EO_lease], rcx
    mov rax, r14
    xor edx, edx
    xor ecx, ecx
.Lelpi_done:
    EPILOGUE
.Lelpi_po_error:
    mov rax, [r14 + PO_error]
.Lelpi_fail:
    mov r12, rax
    mov rdi, r14
    call ext_prepare_release
    mov rcx, rax
    mov rdx, r12
    xor eax, eax
    EPILOGUE
.Lelpi_changed:
    mov rax, -EV_CHANGED
    jmp .Lelpi_fail
.Lelpi_bad_initial:
    mov rax, -EV_CHANGED
.Lelpi_initial_error:
    mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# One immutable asset parsed per call. No payload directory operation is reachable.
FN prep_legacy_import_step
    PROLOGUE 48
    mov rbx, rdi
    cmp qword ptr [rbx + PO_ready], 1
    je .Lelpis_ready
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz .Lelpis_done
    mov r12, [rbx + EP_next]
    cmp r12, [rbx + EP_plan + VEC_len]
    jae .Lelpis_finish
    imul r13, r12, AP_SIZE
    add r13, [rbx + EP_plan + VEC_ptr]
    cmp qword ptr [r13 + AP_kind], AP_THEME
    je .Lelpis_theme
    mov rdi, [r13 + AP_bytes]
    mov rsi, [r13 + AP_byteslen]
    mov rdx, [rbx + PO_eo]
    call grammar_parse_prepare_legacy
    test rax, rax
    jz .Lelpis_parse_error
    mov r14, rax
    mov rdi, rbx
    lea rsi, [rbx + EP_grammars]
    mov edx, 8
    call prep_owned_vec_push
    test rax, rax
    jz .Lelpis_gp_error
    mov [rax], r14
    jmp .Lelpis_next
.Lelpis_theme:
    mov rdi, rbx
    mov rsi, [r13 + AP_bytes]
    mov rdx, [r13 + AP_byteslen]
    mov rcx, r13
    call prep_theme_product
    test rax, rax
    jnz .Lelpis_done
.Lelpis_next:
    inc qword ptr [rbx + EP_next]
    mov eax, 1
    jmp .Lelpis_done
.Lelpis_finish:
    mov rdi, rbx
    call prep_sources_sort
    mov qword ptr [rbx + PO_ready], 1
    mov rdi, rbx
    mov rsi, rsp
    call ext_prepare_source_commitment
    test rax, rax
    jnz .Lelpis_commit_error
    mov rdi, rsp
    lea rsi, [rbx + EP_legacy_source]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lelpis_changed
.Lelpis_ready:
    xor eax, eax
.Lelpis_done:
    test rax, rax
    jns 6f
    cmp qword ptr [rbx + PO_error], 0
    jne 6f
    mov [rbx + PO_error], rax
6:  mov rdx, [rbx + EP_cleanup]
    EPILOGUE
.Lelpis_changed:
    mov rax, -EV_CHANGED
.Lelpis_commit_error:
    mov qword ptr [rbx + PO_ready], 0
    jmp .Lelpis_done
.Lelpis_parse_error:
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rcx
    call prep_note_cleanup
    mov rax, r12
    jmp .Lelpis_done
.Lelpis_gp_error:
    mov rdi, r14
    call grammar_prepare_release
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    mov rax, [rbx + PO_error]
    jmp .Lelpis_done
