# Fixed-field withdrawal after visibility and complete native ownership collection.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# Hidden prepared slot, no native/action owner. Strong checked-keeper dependency.
FN ext_slot_native_quiet
    PROLOGUE
    mov rbx, rdi
    call ext_host_native_quiet
    test rax, rax
    jnz .Lesq_done
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 1
    jne .Lesq_bad
    cmp dword ptr [rbx + EXT_catalog_state], 2
    jne .Lesq_busy
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lesq_bad
    cmp qword ptr [rbx + EXT_activation_owner], 0
    jne .Lesq_busy
    cmp qword ptr [rbx + EXT_activation_plan], 0
    jne .Lesq_busy
    cmp qword ptr [rbx + EXT_pending], 0
    jne .Lesq_busy
    cmp dword ptr [rbx + EXT_start_armed], 0
    jne .Lesq_busy
    cmp dword ptr [rbx + EXT_wait_slot], 0
    jne .Lesq_busy
    cmp dword ptr [rbx + EXT_restart], 0
    jne .Lesq_busy
    xor eax, eax
.Lesq_done:
    EPILOGUE
.Lesq_bad:
    mov rax, -22
    EPILOGUE
.Lesq_busy:
    mov rax, -16
    EPILOGUE

# SLOT, EP-or0 ->0 if every borrowed field has the exact adopted layout.
FN ext_slot_metadata_fields_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rax, [rip + em_pointer_fields]
    mov rax, [rax + r13*8]
    xor ecx, ecx
    test r12, r12
    jz 2f
    mov rcx, [r12 + EP_ext + rax]
2:  cmp [rbx + rax], rcx
    jne .Lesmf_bad
    inc r13
    cmp r13, 31
    jb 1b
    xor r13d, r13d
3:  lea rax, [rip + em_scalar_fields]
    mov rax, [rax + r13*8]
    xor ecx, ecx
    test r12, r12
    jz 4f
    mov ecx, [r12 + EP_ext + rax]
4:  cmp [rbx + rax], ecx
    jne .Lesmf_bad
    inc r13
    cmp r13, 4
    jb 3b
    xor r13d, r13d
5:  xor eax, eax
    test r12, r12
    jz 6f
    mov rax, [r12 + EP_ext + EXT_sdefs + r13*8]
6:  cmp [rbx + EXT_sdefs + r13*8], rax
    jne .Lesmf_bad
    inc r13
    cmp r13, 3
    jb 5b
    test r12, r12
    jnz 7f
    cmp dword ptr [rbx + EXT_cmd0], 0
    jne .Lesmf_bad
    cmp dword ptr [rbx + EXT_ncmd], 0
    jne .Lesmf_bad
7:  xor eax, eax
    EPILOGUE
.Lesmf_bad:
    mov rax, -22
    EPILOGUE

FN ext_slot_metadata_check
    PROLOGUE
    mov rbx, rdi
    call ext_slot_native_quiet
    test rax, rax
    jnz .Lesmc_done
    mov rdi, rbx
    call ext_host_identity_matches
    test eax, eax
    jz .Lesmc_bad
    mov r12, [rbx + EXT_metadata_owner]
    test r12, r12
    jz .Lesmc_fields
    cmp qword ptr [r12 - RD_PO_BACK + RD_kind], RD_EP
    jne .Lesmc_bad
    mov rax, [r12 - RD_PO_BACK + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lesmc_bad
    test eax, RDF_PO
    jz .Lesmc_bad
    cmp qword ptr [r12 + PO_refs], 0
    je .Lesmc_bad
    cmp qword ptr [r12 + PO_ready], 1
    jne .Lesmc_bad
    cmp qword ptr [r12 - AO_SIZE + AO_charge], RD_PO_BACK + 16 + EP_SIZE
    jb .Lesmc_bad
    cmp qword ptr [r12 - AO_SIZE + AO_charge], PREP_TOTAL_CAP
    ja .Lesmc_bad
    mov rax, [r12 + PO_eo]
    test rax, rax
    jz .Lesmc_bad
    cmp qword ptr [rax - RD_SIZE + RD_kind], RD_EO
    jne .Lesmc_bad
    test qword ptr [rax - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lesmc_bad
    cmp qword ptr [rax + EO_refs], 0
    je .Lesmc_bad
    cmp qword ptr [rax + EO_deferred], 1
    jne .Lesmc_bad
    mov rax, [r12 + EP_kind]
    dec rax
    cmp rax, 1
    ja .Lesmc_bad
.Lesmc_fields:
    mov rdi, rbx
    mov rsi, r12
    call ext_slot_metadata_fields_check
.Lesmc_done:
    EPILOGUE
.Lesmc_bad:
    mov rax, -22
    EPILOGUE

# Transfer the slot's exact EP ref to dedicated initially-empty output storage.
FN ext_slot_metadata_take
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_slot_metadata_check
    test rax, rax
    jnz .Lesmt_refuse
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rbx + EXT_metadata_owner]
    mov rcx, [rbx + EXT_identity_owner]
    call ext_owned_output_check
    test rax, rax
    jnz .Lesmt_refuse
    call extpage_prompt_invalidate_pure
    xor r13d, r13d
1:  lea rax, [rip + em_pointer_fields]
    mov rax, [rax + r13*8]
    mov qword ptr [rbx + rax], 0
    inc r13
    cmp r13, 31
    jb 1b
    xor r13d, r13d
2:  lea rax, [rip + em_scalar_fields]
    mov rax, [rax + r13*8]
    mov dword ptr [rbx + rax], 0
    inc r13
    cmp r13, 4
    jb 2b
    mov qword ptr [rbx + EXT_sdefs], 0
    mov qword ptr [rbx + EXT_sdefs + 8], 0
    mov qword ptr [rbx + EXT_sdefs + 16], 0
    mov dword ptr [rbx + EXT_cmd0], 0
    mov dword ptr [rbx + EXT_ncmd], 0
    mov rax, [rbx + EXT_metadata_owner]
    mov qword ptr [rbx + EXT_metadata_owner], 0
    mov [r12], rax
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lesmt_refuse:
    xor edx, edx
    EPILOGUE
.section .rodata
.p2align 3
em_native_fields: .quad EXT_in, EXT_out, EXT_log, EXT_host_child_in, EXT_host_child_out
em_scalar_fields: .quad EXT_on, EXT_needs, EXT_manifest_ok, EXT_color
.globl em_pointer_fields
em_pointer_fields:
.quad EXT_title, EXT_version, EXT_dir, EXT_prog, EXT_script, EXT_args
.quad EXT_on_langs, EXT_on_globs, EXT_sub_opened, EXT_sub_saved, EXT_sub_changed
.quad EXT_sub_cursor, EXT_sub_selection, EXT_sub_edits, EXT_sub_hover
.quad EXT_mname, EXT_mowner, EXT_runs, EXT_desc, EXT_icon
.quad EXT_pv_complete, EXT_pv_ctrig, EXT_pv_signature, EXT_pv_strig
.quad EXT_pv_definition, EXT_pv_references, EXT_pv_symbols, EXT_pv_actions
.quad EXT_pv_rename, EXT_pv_format, EXT_pv_save_actions
