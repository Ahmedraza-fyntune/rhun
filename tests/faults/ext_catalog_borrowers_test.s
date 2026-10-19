# Pure publication revokes authority while retaining owned bytes and native ownership.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
.globl pi_guard
pi_guard: .quad 0
pi_host: .zero EXT_SIZE
pi_host_copy: .zero EXT_SIZE
pi_doc: .zero DOC_SIZE
pi_live: .quad 0
pi_charge: .quad 0
.text
.globl pi_forbidden
FN pi_forbidden
    mov edi, 199
    SYS SYS_exit_group
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + pi_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + pi_charge], rax
    mov r15d, 1
    lea rbx, [rip + pi_host]
    mov dword ptr [rbx + EXT_catalog_state], 2
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov qword ptr [rbx + EXT_keeper], 1
    mov qword ptr [rbx + EXT_metadata_owner], 1
    mov qword ptr [rbx + EXT_identity_owner], 1
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 1
    lea r12, [rip + pi_doc]
    mov [rip + g_doc], r12
    mov [r12 + DOC_oown], rbx
    mov [r12 + DOC_oown + 8], rbx
    mov dword ptr [r12 + DOC_oval], 99
    mov dword ptr [r12 + DOC_oval + 4], 2
    mov dword ptr [rip + cfg_tab_width], 4
    mov dword ptr [rip + cfg_insert_spaces], 0
    lea rdi, [rip + pi_host_copy]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov qword ptr [rip + g_xp_detail], 1
    mov qword ptr [rip + pi_xp_prompt_sd], 1
    mov qword ptr [rip + pi_xb_ext], 1
    mov qword ptr [rip + pi_rm_ext], 1
    mov qword ptr [rip + pi_pp_state], 1
    mov qword ptr [rip + pi_pp_ext], 1
    mov qword ptr [rip + pi_pp_transfer], 1
    mov qword ptr [rip + pi_pp_deadline], 1
    mov qword ptr [rip + pi_cp_due], 1
    mov qword ptr [rip + pi_sg_ext], 1
    mov qword ptr [rip + pi_lf_ws_ext], 1
    mov qword ptr [rip + pi_lf_deadline], 1
    mov qword ptr [rip + g_hover_doc], 1
    mov qword ptr [rip + g_hover_pos], 1
    mov dword ptr [rip + pi_xp_scroll], 1
    mov dword ptr [rip + pi_xp_content_h], 1
    mov dword ptr [rip + pi_xb_open], 1
    mov dword ptr [rip + pi_cp_open], 1
    mov dword ptr [rip + pi_cp_nshown], 1
    mov dword ptr [rip + pi_cp_rect + 12], 1
    mov dword ptr [rip + pi_sg_open], 1
    mov dword ptr [rip + pi_sg_wait], 1
    mov dword ptr [rip + pi_sg_again], 1
    mov dword ptr [rip + pi_lf_kind], 1
    mov dword ptr [rip + pi_lf_ready], 1
    mov dword ptr [rip + pi_lf_list_kind], 1
    mov dword ptr [rip + g_hover_sent], 1
    mov qword ptr [rip + pi_pr_ext], 1
    mov qword ptr [rip + pi_pr_body], 1
    mov qword ptr [rip + pi_pr_cmd + SB_ptr], 1
    mov qword ptr [rip + pi_pp_path], 1
    mov qword ptr [rip + pi_pp_language], 1
    mov qword ptr [rip + pi_pp_choices + VEC_ptr], 1
    mov qword ptr [rip + pi_cp_items + VEC_ptr], 1
    mov qword ptr [rip + pi_cp_bytes + SB_ptr], 1
    mov qword ptr [rip + pi_cp_reqs + VEC_ptr], 1
    mov qword ptr [rip + pi_sg_text + SB_ptr], 1
    mov qword ptr [rip + pi_lf_reqs + VEC_ptr], 1
    mov qword ptr [rip + pi_lf_res + VEC_ptr], 1
    mov qword ptr [rip + pi_lf_bytes + SB_ptr], 1
    mov qword ptr [rip + pi_cp_items + VEC_len], 3
    mov qword ptr [rip + pi_cp_bytes + SB_len], 3
    mov qword ptr [rip + pi_cp_reqs + VEC_len], 3
    mov qword ptr [rip + pi_sg_text + SB_len], 3
    mov qword ptr [rip + pi_lf_reqs + VEC_len], 3
    mov qword ptr [rip + pi_lf_res + VEC_len], 3
    mov qword ptr [rip + pi_lf_bytes + SB_len], 3
    mov dword ptr [rip + pi_cp_session], 2147483647
    mov byte ptr [rip + g_hover_text], 65
    mov qword ptr [rip + pi_pr_revoked], 0
    mov dword ptr [rip + pi_pal_mode], 11
    mov qword ptr [rip + pi_pal_label], 1
    mov qword ptr [rip + pi_items + VEC_ptr], 1
    mov qword ptr [rip + pi_items + VEC_len], 3
    mov qword ptr [rip + pi_results + VEC_ptr], 1
    mov qword ptr [rip + pi_results + VEC_len], 3
    mov dword ptr [rip + pi_dlg_kind], 4
    mov qword ptr [rip + pi_dlg_title], 1
    mov qword ptr [rip + pi_dlg_text], 1
    mov qword ptr [rip + pi_dlg_ok], 1
    lea rax, [rip + pi_remove_commit]
    mov [rip + pi_dlg_fn], rax
    mov qword ptr [rip + pi_dlg_cancel], 0
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    mov dword ptr [rip + pi_menu_open], 1
    lea rax, [rip + pi_xb_items]
    mov [rip + pi_menu_list], rax
    mov qword ptr [rip + pi_guard], 1
    call ext_catalog_borrowers_invalidate_pure
    mov qword ptr [rip + pi_guard], 0
    lea rdi, [rip + pi_host]
    lea rsi, [rip + pi_host_copy]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz pi_bad
    inc r15d
    cmp qword ptr [rip + g_xp_detail], 0
    jne pi_bad
    cmp qword ptr [rip + pi_xp_prompt_sd], 0
    jne pi_bad
    cmp qword ptr [rip + pi_xb_ext], 0
    jne pi_bad
    cmp qword ptr [rip + pi_rm_ext], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pp_state], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pp_ext], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pp_transfer], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pp_deadline], 0
    jne pi_bad
    cmp qword ptr [rip + pi_cp_due], 0
    jne pi_bad
    cmp qword ptr [rip + pi_sg_ext], 0
    jne pi_bad
    cmp qword ptr [rip + pi_lf_ws_ext], 0
    jne pi_bad
    cmp qword ptr [rip + pi_lf_deadline], 0
    jne pi_bad
    cmp qword ptr [rip + g_hover_doc], 0
    jne pi_bad
    cmp qword ptr [rip + g_hover_pos], 0
    jne pi_bad
    cmp dword ptr [rip + pi_xp_scroll], 0
    jne pi_bad
    cmp dword ptr [rip + pi_xp_content_h], 0
    jne pi_bad
    cmp dword ptr [rip + pi_xb_open], 0
    jne pi_bad
    cmp dword ptr [rip + pi_cp_open], 0
    jne pi_bad
    cmp dword ptr [rip + pi_cp_nshown], 0
    jne pi_bad
    cmp dword ptr [rip + pi_cp_rect + 12], 0
    jne pi_bad
    cmp dword ptr [rip + pi_sg_open], 0
    jne pi_bad
    cmp dword ptr [rip + pi_sg_wait], 0
    jne pi_bad
    cmp dword ptr [rip + pi_sg_again], 0
    jne pi_bad
    cmp dword ptr [rip + pi_lf_kind], 0
    jne pi_bad
    cmp dword ptr [rip + pi_lf_ready], 0
    jne pi_bad
    cmp dword ptr [rip + pi_lf_list_kind], 0
    jne pi_bad
    cmp dword ptr [rip + g_hover_sent], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pr_ext], 1
    jne pi_bad
    cmp qword ptr [rip + pi_pr_body], 1
    jne pi_bad
    cmp qword ptr [rip + pi_pr_cmd + SB_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_pp_path], 1
    jne pi_bad
    cmp qword ptr [rip + pi_pp_language], 1
    jne pi_bad
    cmp qword ptr [rip + pi_pp_choices + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_cp_items + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_cp_bytes + SB_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_cp_reqs + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_sg_text + SB_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_lf_reqs + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_lf_res + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_lf_bytes + SB_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_cp_items + VEC_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_cp_bytes + SB_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_cp_reqs + VEC_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_sg_text + SB_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_lf_reqs + VEC_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_lf_res + VEC_len], 3
    jne pi_bad
    cmp qword ptr [rip + pi_lf_bytes + SB_len], 3
    jne pi_bad
    cmp dword ptr [rip + pi_cp_session], 2147483647
    jne pi_bad
    cmp byte ptr [rip + g_hover_text], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pr_revoked], 1
    jne pi_bad
    cmp dword ptr [rip + pi_pal_mode], 0
    jne pi_bad
    cmp dword ptr [rip + pi_dlg_kind], 0
    jne pi_bad
    cmp dword ptr [rip + pi_menu_open], 0
    jne pi_bad
    cmp qword ptr [rip + pi_pal_label], 0
    jne pi_bad
    cmp qword ptr [rip + pi_items + VEC_len], 0
    jne pi_bad
    cmp qword ptr [rip + pi_results + VEC_len], 0
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_title], 0
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_text], 0
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_ok], 0
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_fn], 0
    jne pi_bad
    cmp qword ptr [rip + pi_items + VEC_ptr], 1
    jne pi_bad
    cmp qword ptr [rip + pi_results + VEC_ptr], 1
    jne pi_bad
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne pi_bad
    cmp dword ptr [rip + g_tab_width], 4
    jne pi_bad
    cmp dword ptr [rip + g_insert_spaces], 0
    jne pi_bad
    mov dword ptr [rip + pi_pal_mode], 6
    mov dword ptr [rip + pi_pal_prompt], PROMPT_SAVE_AS
    mov qword ptr [rip + pi_pal_label], 1
    mov qword ptr [rip + pi_items + VEC_len], 3
    mov dword ptr [rip + pi_dlg_kind], 4
    mov qword ptr [rip + pi_dlg_fn], 1
    mov qword ptr [rip + pi_dlg_title], 1
    mov qword ptr [rip + pi_dlg_cancel], 0
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    mov dword ptr [rip + pi_menu_open], 1
    mov qword ptr [rip + pi_menu_list], 1
    mov qword ptr [rip + pi_guard], 1
    call ext_catalog_borrowers_invalidate_pure
    mov qword ptr [rip + pi_guard], 0
    lea rdi, [rip + pi_host]
    lea rsi, [rip + pi_host_copy]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz pi_bad
    inc r15d
    cmp dword ptr [rip + pi_pal_mode], 6
    jne pi_bad
    cmp dword ptr [rip + pi_pal_prompt], PROMPT_SAVE_AS
    jne pi_bad
    cmp qword ptr [rip + pi_pal_label], 1
    jne pi_bad
    cmp qword ptr [rip + pi_items + VEC_len], 3
    jne pi_bad
    cmp dword ptr [rip + pi_dlg_kind], 4
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_fn], 1
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_title], 1
    jne pi_bad
    cmp dword ptr [rip + g_focus], FOCUS_DIALOG
    jne pi_bad
    cmp dword ptr [rip + pi_menu_open], 1
    jne pi_bad
    cmp qword ptr [rip + pi_menu_list], 1
    jne pi_bad
    lea rax, [rip + pi_remove_commit]
    mov [rip + pi_dlg_fn], rax
    mov qword ptr [rip + pi_dlg_cancel], 1
    mov qword ptr [rip + pi_guard], 1
    call ext_catalog_borrowers_invalidate_pure
    mov qword ptr [rip + pi_guard], 0
    lea rdi, [rip + pi_host]
    lea rsi, [rip + pi_host_copy]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz pi_bad
    inc r15d
    cmp dword ptr [rip + pi_dlg_kind], 4
    jne pi_bad
    cmp qword ptr [rip + pi_dlg_cancel], 1
    jne pi_bad
    cmp dword ptr [rip + g_focus], FOCUS_DIALOG
    jne pi_bad
    mov dword ptr [rip + pi_cp_source], 1
    mov dword ptr [rip + pi_cp_open], 2
    mov qword ptr [rip + pi_cp_due], 77
    mov dword ptr [rip + pi_cp_nshown], 3
    mov dword ptr [rip + pi_cp_rect + 12], 10
    mov dword ptr [rip + pi_pal_mode], 11
    mov dword ptr [rip + g_focus], FOCUS_TERMINAL
    mov qword ptr [rip + pi_guard], 1
    call ext_catalog_borrowers_invalidate_pure
    mov qword ptr [rip + pi_guard], 0
    lea rdi, [rip + pi_host]
    lea rsi, [rip + pi_host_copy]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz pi_bad
    inc r15d
    cmp dword ptr [rip + pi_cp_open], 2
    jne pi_bad
    cmp qword ptr [rip + pi_cp_due], 77
    jne pi_bad
    cmp dword ptr [rip + pi_cp_nshown], 3
    jne pi_bad
    cmp dword ptr [rip + pi_cp_rect + 12], 10
    jne pi_bad
    cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    jne pi_bad
    cmp dword ptr [rip + pi_pal_mode], 0
    jne pi_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + pi_live]
    jne pi_bad
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + pi_charge]
    jne pi_bad
    xor eax, eax
    EPILOGUE
pi_bad:
    mov edi, r15d
    SYS SYS_exit_group
