# Independent bounded identity ownership and fail-closed catalog membership.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/exthostidentity.inc"
.data
hi_owner: .asciz "owner"
hi_name: .asciz "name"
.ifdef WINDOWS
hi_state: .asciz "C:/state"
.else
hi_state: .asciz "/state"
.endif
.section .rodata
hi_empty: .asciz ""
hi_bad: .asciz ".invalid"
hi_other: .asciz "other"
.bss
.p2align 3
hi_obj: .quad 0
hi_stage: .quad 0
hi_live: .quad 0
hi_charge: .quad 0
hi_host: .zero EXT_SIZE
hi_status: .zero 32
hi_out: .quad 0
hi_ep: .quad 0
hi_metadata_out: .quad 0
hi_copy_host: .zero EXT_SIZE
hi_copy_po: .zero HI_CAP
hi_copy_eo: .zero 128
hi_copy_new_po: .zero HI_CAP
hi_copy_new_eo: .zero 128
hi_new: .quad 0
hi_meta_before: .zero EXT_SIZE
hi_meta_expected: .zero EXT_SIZE
hi_meta_po: .zero HI_CAP
hi_meta_eo: .zero 128
hi_meta_sd: .zero SD_SIZE
hi_runtime_status: .quad 0
hi_runtime_buf: .quad 0
hi_runtime_icon: .quad 0
hi_targets: .zero 16*8
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + hi_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + hi_charge], rax
    call hi_quiet_matrix
    mov qword ptr [rip + hi_stage], 1
    lea rdi, [rip + hi_bad]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, -22
    jne .Lhit_bad
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_empty]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, -22
    jne .Lhit_bad
    mov qword ptr [rip + hi_stage], 2
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz .Lhit_bad
    test rdx, rdx
    jnz .Lhit_bad
    mov [rip + hi_obj], rax
    mov rdi, rax
    call hi_is_ready
    cmp eax, 1
    jne .Lhit_bad
    mov rbx, [rip + hi_obj]
    mov rax, [rbx + PO_eo]
    cmp qword ptr [rax + EO_refs], 1
    jne .Lhit_bad
    cmp qword ptr [rax + EO_lease], -1
    jne .Lhit_bad
    mov byte ptr [rip + hi_owner], 'X'
    cmp byte ptr [rbx + HI_SIZE], 'o'
    jne .Lhit_bad
    mov byte ptr [rip + hi_owner], 'o'
    lea r12, [rip + hi_host]
    mov [r12 + EXT_identity_owner], rbx
    mov rax, [rbx + HI_owner]
    mov [r12 + EXT_owner], rax
    mov rax, [rbx + HI_name]
    mov [r12 + EXT_name], rax
    mov rax, [rbx + HI_state]
    mov [r12 + EXT_state], rax
    mov qword ptr [rip + hi_stage], 3
    mov rdi, r12
    call ext_is_visible
    cmp eax, 1
    jne .Lhit_bad
    call ext_catalog_visibility_check
    test rax, rax
    jnz .Lhit_bad
    call ext_catalog_begin_prepared_pure
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jnz .Lhit_bad
    mov dword ptr [r12 + EXT_catalog_state], 1
    mov rdi, r12
    call ext_can_act
    cmp eax, 1
    jne .Lhit_bad
    mov rdi, r12
    call ext_has_metadata
    test eax, eax
    jnz .Lhit_bad
    # Byte-equal independently owned spelling does not establish typed ownership.
    lea rax, [rip + hi_name]
    mov [r12 + EXT_name], rax
    mov rdi, r12
    call ext_can_act
    test eax, eax
    jnz .Lhit_bad
    mov rax, [rbx + HI_name]
    mov [r12 + EXT_name], rax
    mov dword ptr [r12 + EXT_status], ES_RUNNING
    mov dword ptr [r12 + EXT_wait_slot], 1
    mov dword ptr [r12 + EXT_restart], 1
    mov dword ptr [r12 + EXT_start_armed], 1
    mov rdi, r12
    call ext_slot_hide_pure
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_wait_slot], 0
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_restart], 0
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_start_armed], 0
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_activation_stale], 1
    jne .Lhit_bad
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jnz .Lhit_bad
    mov dword ptr [r12 + EXT_catalog_state], 3
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jnz .Lhit_bad
    mov qword ptr [rip + hi_stage], 4
    mov dword ptr [r12 + EXT_catalog_state], 2
    mov dword ptr [r12 + EXT_activation_required], 1
    mov dword ptr [r12 + EXT_in], -1
    mov dword ptr [r12 + EXT_out], -1
    mov dword ptr [r12 + EXT_log], -1
    mov dword ptr [r12 + EXT_host_child_in], -1
    mov dword ptr [r12 + EXT_host_child_out], -1
    mov dword ptr [r12 + EXT_status], ES_STOPPED
    mov dword ptr [r12 + EXT_retiring], 2
    mov dword ptr [r12 + EXT_stdout_eof], 1
    mov rdi, rbx
    call ext_host_identity_retain
    test rax, rax
    jnz .Lhit_bad
    cmp qword ptr [rbx + PO_refs], 2
    jne .Lhit_bad
    # Snapshot the complete slot, allocation including allocator padding, and EO.
    lea rdi, [rip + hi_copy_host]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + hi_copy_po]
    lea rsi, [rbx - RD_PO_BACK - 16]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    call memcpy
    lea rdi, [rip + hi_copy_eo]
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memcpy
    mov rax, rbx
    call hi_fill_targets
    xor r13d, r13d
3:  lea rax, [rip + hi_targets]
    mov rdx, [rax + r13*8]
    call hi_refuse_swap
    inc r13
    cmp r13, 13
    jb 3b
    mov qword ptr [rip + hi_out], 1
    lea rdx, [rip + hi_out]
    call hi_refuse_swap
    cmp qword ptr [rip + hi_out], 1
    jne .Lhit_bad
    mov qword ptr [rip + hi_out], 0
    call hi_distinct_refusals
    call hi_metadata_test
    # A real write-only pipe read fails; checked collection consumes its endpoint.
    mov rdi, r12
    mov esi, 1
    call ext_host_pipe_create
    test rax, rax
    jnz .Lhit_bad
    mov rdi, r12
    mov esi, 1
    call ext_host_close_field
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, 1
    jne .Lhit_bad
    mov eax, [r12 + EXT_host_child_out]
    mov [r12 + EXT_out], eax
    mov dword ptr [r12 + EXT_host_child_out], -1
    mov dword ptr [r12 + EXT_status], ES_STOPPING
    mov dword ptr [r12 + EXT_retiring], 1
    mov dword ptr [r12 + EXT_stdout_eof], 0
    mov dword ptr [r12 + EXT_host_cleanup_error], 0
    mov dword ptr [r12 + EXT_finish_code], 0
    mov rdi, r12
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhit_bad
    test edx, edx
    jns .Lhit_bad
    cmp dword ptr [r12 + EXT_retiring], 4
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_stdout_eof], 0
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_out], -1
    jne .Lhit_bad
    cmp dword ptr [r12 + EXT_host_cleanup_mask], 0
    jne .Lhit_bad
    mov dword ptr [r12 + EXT_status], ES_FAILED
    call hi_metadata_test
    # Same HI requires a second preheld reference and transfers the exact old ref.
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rip + hi_out]
    call ext_host_identity_swap
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, 1
    jne .Lhit_bad
    cmp [rip + hi_out], rbx
    jne .Lhit_bad
    mov rdi, [rip + hi_out]
    call ext_host_identity_release
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, 1
    jne .Lhit_bad
    mov qword ptr [rip + hi_out], 0
    mov rdi, r12
    lea rsi, [rip + hi_out]
    call ext_host_identity_take
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, 1
    jne .Lhit_bad
    cmp [rip + hi_out], rbx
    jne .Lhit_bad
    cmp qword ptr [r12 + EXT_identity_owner], 0
    jne .Lhit_bad
    cmp qword ptr [r12 + EXT_owner], 0
    jne .Lhit_bad
    cmp qword ptr [r12 + EXT_name], 0
    jne .Lhit_bad
    cmp qword ptr [r12 + EXT_state], 0
    jne .Lhit_bad
    mov rdi, [rip + hi_out]
    call ext_host_identity_release
    test rax, rax
    jnz .Lhit_bad
    cmp rdx, 1
    jne .Lhit_bad
    # Last-ref transfer does no synchronous free. One unit per step drains it.
    mov rbx, 64
1:  mov edi, 1
    lea rsi, [rip + hi_status]
    call ext_prepare_retire_step
    test rax, rax
    js .Lhit_bad
    cmp qword ptr [rip + hi_status], 1
    ja .Lhit_bad
    cmp qword ptr [rip + hi_status + 16], 0
    jne .Lhit_bad
    cmp qword ptr [rip + hi_status + 24], 0
    jne .Lhit_bad
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp .Lhit_bad
2:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + hi_live]
    jne .Lhit_bad
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + hi_charge]
    jne .Lhit_bad
    xor eax, eax
    EPILOGUE
.Lhit_bad:
    mov rax, [rip + hi_stage]
    EPILOGUE

# Both complete ownership graphs must be unchanged before any cleanup/reset.
hi_refuse_swap:
    PROLOGUE
    mov rdi, r12
    mov rsi, rbx
    call ext_host_identity_swap
    cmp rax, -22
    jne .Lhir_abort
    test rdx, rdx
    jnz .Lhir_abort
    lea rdi, [rip + hi_copy_host]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhir_abort
    lea rdi, [rip + hi_copy_po]
    lea rsi, [rbx - RD_PO_BACK - 16]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    call memeq
    test eax, eax
    jz .Lhir_abort
    lea rdi, [rip + hi_copy_eo]
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Lhir_abort
    EPILOGUE
.Lhir_abort:
    mov edi, 88
    jmp sys_exit

# Exact borrowed schema/field adoption, retained HI and consumed EP transfer.
hi_metadata_test:
    PROLOGUE
    mov rdi, -1
    lea rsi, [rip + hi_state]
    lea rdx, [rip + hi_owner]
    lea rcx, [rip + hi_name]
    call ext_prepare_alloc
    test rax, rax
    jz .Lhim_abort
    mov r14, rax
    mov [rip + hi_ep], rax
    mov qword ptr [r14 + EP_kind], 2
    mov rdi, r14
    call ext_prepare_enable_deferred
    test rax, rax
    jnz .Lhim_abort
    mov rdi, r14
    mov esi, SD_SIZE
    call prep_owned_alloc
    test rax, rax
    jz .Lhim_abort
    mov dword ptr [rax + SD_pad], 1
    mov [r14 + EP_ext + EXT_sdefs + VEC_ptr], rax
    mov qword ptr [r14 + EP_ext + EXT_sdefs + VEC_len], 1
    mov qword ptr [r14 + EP_ext + EXT_sdefs + VEC_cap], 1
    # Every pointer borrows one actual owned EP string, never external storage.
    mov r15, [r14 + EP_ext + EXT_dir]
    xor r13d, r13d
1:  lea rax, [rip + hi_metadata_fields]
    mov rax, [rax + r13*8]
    mov [r14 + EP_ext + rax], r15
    mov [r12 + rax], r15
    inc r13
    cmp r13, 31
    jb 1b
    mov dword ptr [r14 + EP_ext + EXT_on], 1
    mov dword ptr [r14 + EP_ext + EXT_needs], NEEDS_PROJECT_READ
    mov dword ptr [r14 + EP_ext + EXT_manifest_ok], 1
    mov dword ptr [r14 + EP_ext + EXT_color], 123
    mov dword ptr [r12 + EXT_on], 1
    mov dword ptr [r12 + EXT_needs], NEEDS_PROJECT_READ
    mov dword ptr [r12 + EXT_manifest_ok], 1
    mov dword ptr [r12 + EXT_color], 123
    lea rdi, [r12 + EXT_sdefs]
    lea rsi, [r14 + EP_ext + EXT_sdefs]
    mov edx, VEC_SIZE
    call memcpy
    mov qword ptr [r14 + PO_ready], 1
    mov [r12 + EXT_metadata_owner], r14
    mov dword ptr [r12 + EXT_cmd0], 77
    mov dword ptr [r12 + EXT_ncmd], 4
    cmp dword ptr [r12 + EXT_host_cleanup_error], 0
    js 9f
    mov dword ptr [r12 + EXT_host_cleanup_error], -5
9:  mov rdi, r12
    call ext_slot_metadata_check
    test rax, rax
    jnz .Lhim_abort
    # Real independent runtime allocations must remain retained by the host.
    mov edi, 64
    call mem_alloc
    mov [rip + hi_runtime_status], rax
    mov [r12 + EXT_status_text], rax
    mov edi, 64
    call mem_alloc
    mov [rip + hi_runtime_buf], rax
    mov [r12 + EXT_rbuf + SB_ptr], rax
    mov qword ptr [r12 + EXT_rbuf + SB_len], 7
    mov qword ptr [r12 + EXT_rbuf + SB_cap], 64
    mov edi, 64
    call mem_alloc
    mov [rip + hi_runtime_icon], rax
    mov [r12 + EXT_icon_px], rax
    mov dword ptr [r12 + EXT_icon_sz], 8
    mov dword ptr [r12 + EXT_features], 0x13579
    mov qword ptr [r12 + EXT_hreq], 12345
    mov dword ptr [r12 + EXT_pinned], 1
    call hi_metadata_snapshot
    lea rdi, [rip + hi_meta_expected]
    lea rsi, [rip + hi_meta_before]
    mov edx, EXT_SIZE
    call memcpy
    xor r13d, r13d
2:  lea rax, [rip + hi_metadata_fields]
    mov rax, [rax + r13*8]
    lea rcx, [rip + hi_meta_expected]
    mov qword ptr [rcx + rax], 0
    inc r13
    cmp r13, 31
    jb 2b
    lea rax, [rip + hi_meta_expected]
    mov dword ptr [rax + EXT_on], 0
    mov dword ptr [rax + EXT_needs], 0
    mov dword ptr [rax + EXT_manifest_ok], 0
    mov dword ptr [rax + EXT_color], 0
    mov dword ptr [rax + EXT_cmd0], 0
    mov dword ptr [rax + EXT_ncmd], 0
    mov qword ptr [rax + EXT_sdefs + VEC_ptr], 0
    mov qword ptr [rax + EXT_sdefs + VEC_len], 0
    mov qword ptr [rax + EXT_sdefs + VEC_cap], 0
    mov qword ptr [rax + EXT_metadata_owner], 0
    # Busy native and unresolved ownership are never treated as collected.
    mov qword ptr [r12 + EXT_keeper], 1
    mov rdi, r12
    call ext_slot_metadata_check
    cmp rax, -16
    jne .Lhim_abort
    mov qword ptr [r12 + EXT_keeper], 0
    mov dword ptr [r12 + EXT_host_cleanup_mask], 1
    mov rdi, r12
    call ext_slot_metadata_check
    cmp rax, -16
    jne .Lhim_abort
    mov dword ptr [r12 + EXT_host_cleanup_mask], 0
    # Every adopted pointer and schema descriptor lane must exactly match its EP.
    xor r13d, r13d
.Lhim_mismatch:
    cmp r13, 31
    jae .Lhim_schema_lane
    lea rax, [rip + hi_metadata_fields]
    mov r15, [rax + r13*8]
    jmp .Lhim_flip_lane
.Lhim_schema_lane:
    lea r15, [r13*8 + EXT_sdefs - 31*8]
.Lhim_flip_lane:
    xor qword ptr [r12 + r15], 1
    call hi_metadata_snapshot
    mov rdi, r12
    lea rsi, [rip + hi_metadata_out]
    call ext_slot_metadata_take
    cmp rax, -22
    jne .Lhim_abort
    test rdx, rdx
    jnz .Lhim_abort
    cmp qword ptr [rip + hi_metadata_out], 0
    jne .Lhim_abort
    call hi_metadata_unchanged
    xor qword ptr [r12 + r15], 1
    inc r13
    cmp r13, 34
    jb .Lhim_mismatch
    call hi_metadata_snapshot
    # Each actual EP/HI allocation and EO span is independently forbidden.
    mov rax, r14
    call hi_fill_targets
    xor r15d, r15d
.Lhimalias_family:
    xor r13d, r13d
3:  lea rax, [rip + hi_targets]
    mov rsi, [rax + r13*8]
    mov rdi, r12
    call ext_slot_metadata_take
    cmp rax, -22
    jne .Lhim_abort
    test rdx, rdx
    jnz .Lhim_abort
    call hi_metadata_unchanged
    inc r13
    cmp r13, 13
    jb 3b
    test r15, r15
    jnz 4f
    mov rax, rbx
    call hi_fill_targets
    inc r15
    jmp .Lhimalias_family
4:  mov qword ptr [rip + hi_metadata_out], 1
    mov rdi, r12
    lea rsi, [rip + hi_metadata_out]
    call ext_slot_metadata_take
    cmp rax, -22
    jne .Lhim_abort
    test rdx, rdx
    jnz .Lhim_abort
    cmp qword ptr [rip + hi_metadata_out], 1
    jne .Lhim_abort
    call hi_metadata_unchanged
    mov qword ptr [rip + hi_metadata_out], 0
    mov rdi, r12
    lea rsi, [rip + hi_metadata_out]
    call ext_slot_metadata_take
    test rax, rax
    jnz .Lhim_abort
    cmp rdx, 1
    jne .Lhim_abort
    cmp [rip + hi_metadata_out], r14
    jne .Lhim_abort
    cmp qword ptr [r12 + EXT_metadata_owner], 0
    jne .Lhim_abort
    lea rdi, [rip + hi_meta_expected]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhim_abort
    call hi_metadata_graphs
    mov eax, [rip + hi_meta_before + EXT_host_cleanup_error]
    cmp [r12 + EXT_host_cleanup_error], eax
    jne .Lhim_abort
    mov rdi, r12
    call ext_slot_metadata_check
    test rax, rax
    jnz .Lhim_abort
    cmp [r12 + EXT_identity_owner], rbx
    jne .Lhim_abort
    mov rdi, r14
    call ext_prepare_release_deferred
    test rax, rax
    jnz .Lhim_abort
    cmp rdx, 1
    jne .Lhim_abort
    mov qword ptr [rip + hi_metadata_out], 0
    mov rdi, [rip + hi_runtime_status]
    call mem_free
    mov rdi, [rip + hi_runtime_buf]
    call mem_free
    mov rdi, [rip + hi_runtime_icon]
    call mem_free
    # Ordinary later runtime cleanup restores this fixture's original host graph.
    mov rdi, r12
    lea rsi, [rip + hi_copy_host]
    mov edx, EXT_SIZE
    call memcpy
    EPILOGUE
.Lhim_abort:
    mov edi, 89
    jmp sys_exit
.section .rodata
.p2align 3
hi_metadata_fields:
.quad EXT_title, EXT_version, EXT_dir, EXT_prog, EXT_script, EXT_args
.quad EXT_on_langs, EXT_on_globs, EXT_sub_opened, EXT_sub_saved, EXT_sub_changed
.quad EXT_sub_cursor, EXT_sub_selection, EXT_sub_edits, EXT_sub_hover
.quad EXT_mname, EXT_mowner, EXT_runs, EXT_desc, EXT_icon
.quad EXT_pv_complete, EXT_pv_ctrig, EXT_pv_signature, EXT_pv_strig
.quad EXT_pv_definition, EXT_pv_references, EXT_pv_symbols, EXT_pv_actions
.quad EXT_pv_rename, EXT_pv_format, EXT_pv_save_actions

.text
# Build the complete forbidden span family for one actual owned PO.
hi_fill_targets:
    mov r10, rax
    lea rax, [r12 + EXT_identity_owner]
    mov [rip + hi_targets], rax
    lea rax, [r12 - 4]
    mov [rip + hi_targets + 8], rax
    lea rax, [r12 + EXT_SIZE - 4]
    mov [rip + hi_targets + 16], rax
    lea rax, [r10 + HI_owner]
    mov [rip + hi_targets + 24], rax
    lea rax, [r10 + HI_SIZE]
    mov [rip + hi_targets + 32], rax
    lea rax, [r10 - RD_PO_BACK]
    mov [rip + hi_targets + 40], rax
    lea rax, [r10 - RD_PO_BACK - 16]
    mov [rip + hi_targets + 48], rax
    mov rax, [r10 - AO_SIZE + AO_charge]
    lea rax, [r10 + rax - RD_PO_BACK - 24]
    mov [rip + hi_targets + 56], rax
    mov rax, [r10 + PO_eo]
    mov [rip + hi_targets + 64], rax
    sub rax, RD_SIZE + 16
    mov [rip + hi_targets + 72], rax
    mov rax, [r10 + PO_eo]
    add rax, EO_SIZE - 8
    mov [rip + hi_targets + 80], rax
    mov qword ptr [rip + hi_targets + 88], -8
    lea rax, [rip + hi_out + 1]
    mov [rip + hi_targets + 96], rax
    ret

hi_distinct_refusals:
    PROLOGUE
    lea rdi, [rip + hi_other]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz .Lhid_abort
    test rdx, rdx
    jnz .Lhid_abort
    mov r14, rax
    mov [rip + hi_new], rax
    lea rdi, [rip + hi_copy_new_po]
    lea rsi, [r14 - RD_PO_BACK - 16]
    mov rdx, [r14 - AO_SIZE + AO_charge]
    call memcpy
    lea rdi, [rip + hi_copy_new_eo]
    mov rsi, [r14 + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memcpy
    xor r15d, r15d
.Lhid_family:
    xor r13d, r13d
1:  lea rax, [rip + hi_targets]
    mov rdx, [rax + r13*8]
    mov rdi, r12
    mov rsi, r14
    call ext_host_identity_swap
    cmp rax, -22
    jne .Lhid_abort
    test rdx, rdx
    jnz .Lhid_abort
    call hi_assert_old_new
    inc r13
    cmp r13, 13
    jb 1b
    test r15, r15
    jnz 2f
    mov rax, r14
    call hi_fill_targets
    inc r15
    jmp .Lhid_family
2:  mov rax, rbx
    call hi_fill_targets
    xor r13d, r13d
3:  lea rax, [rip + hi_targets]
    mov rsi, [rax + r13*8]
    mov rdi, r12
    call ext_host_identity_take
    cmp rax, -22
    jne .Lhid_abort
    test rdx, rdx
    jnz .Lhid_abort
    call hi_assert_old_new
    inc r13
    cmp r13, 13
    jb 3b
    # Distinct incoming ownership and exact outgoing reference, then swap back.
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + hi_out]
    call ext_host_identity_swap
    test rax, rax
    jnz .Lhid_abort
    cmp rdx, 1
    jne .Lhid_abort
    cmp [rip + hi_out], rbx
    jne .Lhid_abort
    mov qword ptr [rip + hi_out], 0
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rip + hi_out]
    call ext_host_identity_swap
    test rax, rax
    jnz .Lhid_abort
    cmp rdx, 1
    jne .Lhid_abort
    cmp [rip + hi_out], r14
    jne .Lhid_abort
    call hi_assert_old_new
    mov rdi, [rip + hi_out]
    call ext_host_identity_release
    test rax, rax
    jnz .Lhid_abort
    cmp rdx, 1
    jne .Lhid_abort
    mov qword ptr [rip + hi_out], 0
    EPILOGUE
.Lhid_abort:
    mov edi, 91
    jmp sys_exit

hi_assert_old_new:
    PROLOGUE
    lea rdi, [rip + hi_copy_host]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhid_abort
    lea rdi, [rip + hi_copy_po]
    lea rsi, [rbx - RD_PO_BACK - 16]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    call memeq
    test eax, eax
    jz .Lhid_abort
    lea rdi, [rip + hi_copy_eo]
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Lhid_abort
    lea rdi, [rip + hi_copy_new_po]
    lea rsi, [r14 - RD_PO_BACK - 16]
    mov rdx, [r14 - AO_SIZE + AO_charge]
    call memeq
    test eax, eax
    jz .Lhid_abort
    lea rdi, [rip + hi_copy_new_eo]
    mov rsi, [r14 + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Lhid_abort
    EPILOGUE

.text
hi_metadata_snapshot:
    PROLOGUE
    lea rdi, [rip + hi_meta_before]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + hi_meta_po]
    lea rsi, [r14 - RD_PO_BACK - 16]
    mov rdx, [r14 - AO_SIZE + AO_charge]
    cmp rdx, HI_CAP
    ja .Lhim_abort
    call memcpy
    lea rdi, [rip + hi_meta_eo]
    mov rsi, [r14 + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memcpy
    lea rdi, [rip + hi_meta_sd]
    mov rsi, [r14 + EP_ext + EXT_sdefs + VEC_ptr]
    mov edx, SD_SIZE
    call memcpy
    EPILOGUE
hi_metadata_unchanged:
    PROLOGUE
    lea rdi, [rip + hi_meta_before]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhim_abort
    call hi_metadata_graphs
    EPILOGUE
hi_metadata_graphs:
    PROLOGUE
    lea rdi, [rip + hi_meta_po]
    lea rsi, [r14 - RD_PO_BACK - 16]
    mov rdx, [r14 - AO_SIZE + AO_charge]
    call memeq
    test eax, eax
    jz .Lhim_abort
    lea rdi, [rip + hi_meta_eo]
    mov rsi, [r14 + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Lhim_abort
    lea rdi, [rip + hi_meta_sd]
    mov rsi, [r14 + EP_ext + EXT_sdefs + VEC_ptr]
    mov edx, SD_SIZE
    call memeq
    test eax, eax
    jz .Lhim_abort
    lea rdi, [rip + hi_copy_po]
    lea rsi, [rbx - RD_PO_BACK - 16]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    call memeq
    test eax, eax
    jz .Lhim_abort
    lea rdi, [rip + hi_copy_eo]
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Lhim_abort
    EPILOGUE

.text
# Independent truth table: six phases, both EOF states, cleanup presence, nine statuses.
hi_quiet_matrix:
    PROLOGUE
    xor r13d, r13d
.Lhiq_case:
    lea rbx, [rip + hi_host]
    mov rdi, rbx
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_host_child_in], -1
    mov dword ptr [rbx + EXT_host_child_out], -1
    mov rax, r13
    xor edx, edx
    mov ecx, 9
    div rcx
    mov [rbx + EXT_status], edx
    mov r14d, edx
    mov rcx, rax
    and ecx, 1
    neg ecx
    and ecx, -5
    mov [rbx + EXT_host_cleanup_error], ecx
    mov rdx, rax
    shr edx, 1
    and edx, 1
    mov [rbx + EXT_stdout_eof], edx
    shr eax, 2
    mov [rbx + EXT_retiring], eax
    xor r15d, r15d
    # Explicit accepted states, independent from the production branch table.
    cmp r14d, 1
    je .Lhiq_probe
    cmp r14d, 2
    je .Lhiq_probe
    cmp r14d, 3
    je .Lhiq_probe
    test eax, eax
    jz .Lhiq_accept
    cmp eax, 2
    jne 1f
    test edx, edx
    jnz .Lhiq_accept
    jmp .Lhiq_probe
1:  cmp eax, 4
    jne .Lhiq_probe
    test edx, edx
    jnz .Lhiq_probe
    test ecx, ecx
    jns .Lhiq_probe
.Lhiq_accept:
    mov r15d, 1
.Lhiq_probe:
    lea rdi, [rip + hi_copy_host]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, rbx
    call ext_host_native_quiet
    test r15d, r15d
    jnz .Lhiq_positive
    cmp rax, -16
    jne .Lhiq_bad
    jmp .Lhiq_unchanged
.Lhiq_positive:
    test rax, rax
    jnz .Lhiq_bad
.Lhiq_unchanged:
    lea rdi, [rip + hi_copy_host]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhiq_bad
    inc r13
    cmp r13, 216
    jb .Lhiq_case
    mov dword ptr [rbx + EXT_status], ES_STOPPED
    mov dword ptr [rbx + EXT_retiring], 4
    mov dword ptr [rbx + EXT_stdout_eof], 0
    mov dword ptr [rbx + EXT_host_cleanup_error], -5
    xor r13d, r13d
.Lhiq_owned:
    lea rax, [rip + hi_quiet_busy_fields]
    mov r14, [rax + r13*8]
    mov r15d, [rbx + r14]
    mov dword ptr [rbx + r14], 1
    cmp r13, 8
    jne 2f
    mov dword ptr [rbx + r14], 256
2:  lea rdi, [rip + hi_copy_host]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, rbx
    call ext_host_native_quiet
    cmp rax, -16
    jne .Lhiq_bad
    lea rdi, [rip + hi_copy_host]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Lhiq_bad
    mov [rbx + r14], r15d
    inc r13
    cmp r13, 9
    jb .Lhiq_owned
    xor edi, edi
    call ext_host_native_quiet
    cmp rax, -22
    jne .Lhiq_bad
    mov rdi, rbx
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    EPILOGUE
.Lhiq_bad:
    mov edi, 89
    call sys_exit

.section .rodata
.p2align 3
hi_quiet_busy_fields: .quad EXT_in,EXT_out,EXT_log,EXT_host_child_in,EXT_host_child_out,EXT_pid,EXT_keeper,EXT_host_cleanup_mask,EXT_host_cleanup_mask
