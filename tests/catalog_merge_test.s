# Real parsed managed/legacy products, exact merge ordinals and independent owners.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.include "app/themecapturecandidate.inc"
.include "app/themecapture.inc"
.include "app/catalogregistrywork.inc"
.include "app/catalogregistrymap.inc"
.equ CM_CANCEL_PHASE, -1
.equ CM_CANCEL_POINT, -1
.equ CM_OOM_N, 0
.equ CM_REF_FAULT, 0
.equ CM_PURE_IO, 0
.section .rodata
cm_dir: .asciz "/registry/payload"
cm_owner: .asciz "fixture"
cm_name: .asciz "registry"
cm_shared: .ascii "name = Shared\nfiles = *.shared\n"
cm_shared_end: .byte 0
cm_case: .ascii "name = Case\n"
cm_case_end: .byte 0
cm_lower: .ascii "name = case\n"
cm_lower_end: .byte 0
cm_null: .ascii "files = *.null\n"
cm_null_end: .byte 0
cm_empty: .ascii "name = \n"
cm_empty_end: .byte 0
cm_sources:
 .quad cm_shared,cm_shared_end-cm_shared
 .quad cm_case,cm_case_end-cm_case
 .quad cm_lower,cm_lower_end-cm_lower
 .quad cm_null,cm_null_end-cm_null
 .quad cm_empty,cm_empty_end-cm_empty
cm_theme: .ascii "name = Blue\nkind = dark\nbg = #112233\n"
cm_theme_end: .byte 0
cm_themelen: .quad cm_theme_end-cm_theme
cm_path1: .asciz "themes/shared.theme"
cm_path2: .asciz "themes/other.theme"
cm_path3: .asciz "themes/Shared.theme"
cm_path4: .asciz "themes/last.theme"
cm_path5: .asciz "themes/theme-only.theme"
cm_id: .asciz "dup"
cm_followid: .asciz "follow"
cm_userpath: .asciz "/registry/payload/themes/shared.theme"
cm_aliaspath: .asciz "themes/relative.theme"
cm_followname: .asciz "Follow"
cm_username: .asciz "User"
cm_builtinname: .asciz "Builtin"
cm_sharedname: .asciz "Shared"
.data
.p2align 3
cm_usergr: .zero GR_SIZE
cm_builtingr: .zero GR_SIZE
cm_grammars: .quad cm_usergr,cm_builtingr
cm_th:
 .quad cm_followid,cm_followname,0,0,0,0,0
 .quad cm_id,cm_username,0,0,0,cm_userpath,0
 .quad cm_id,cm_builtinname,0,cm_theme,cm_theme_end-cm_theme,0,0
 .quad cm_id,cm_username,0,0,0,cm_aliaspath,0
cm_input: .quad cm_grammars,2,1,cm_th,4,0,31,0
.bss
.p2align 3
cm_base: .quad 0
cm_rg: .quad 0
cm_eps: .zero 40
cm_stage: .quad 0
cm_charge: .quad 0
cm_live: .quad 0
cm_keptgp: .quad 0
cm_doc: .quad 0
cm_alloc_calls: .quad 0
cm_ref_target: .quad 0
cm_ref_refs: .quad 0
cm_ref_armed: .quad 0
cm_lease: .quad 0
cm_identity: .zero 32
cm_tconfig: .zero TCFG_SIZE
cm_trequest: .quad 0
cm_tcharge: .quad 0
cm_lookup_cursor: .zero TCL_SIZE
cm_report: .zero 32
.text
cm_fail:
 mov rdi, [rip + cm_stage]
 add rdi, 40
 call sys_exit
 ud2
cm_drain:
 PROLOGUE
 mov r12d, 100000
1: mov edi, 1
 lea rsi, [rip + cm_report]
 call ext_prepare_retire_step
 test rax, rax
 js cm_fail
 cmp qword ptr [rip + cm_report], 1
 ja cm_fail
 cmp qword ptr [rip + cm_report + 16], 0
 jne cm_fail
 test rax, rax
 jz 2f
 dec r12
 jnz 1b
 jmp cm_fail
2: EPILOGUE
# Input ep, source table index. Actual owned parser and vector transfer.
cm_gp:
 PROLOGUE
 mov rbx, rdi
 mov r13, rsi
 lea rax, [rip + cm_sources]
 shl rsi, 4
 add rsi, rax
 mov rdi, [rsi]
 mov rsi, [rsi + 8]
 mov rdx, [rbx + PO_eo]
 cmp qword ptr [rbx + EP_kind], 2
 je 1f
 call grammar_parse_prepare
 jmp 2f
1: call grammar_parse_prepare_legacy
2: test rax, rax
 jz cm_fail
 mov r12, rax
 # Native NULL-name input is distinct from the parser's present empty default.
 cmp r13, 3
 jne 3f
 mov qword ptr [r12 + GP_gr + GR_name], 0
3: mov rdi, rbx
 lea rsi, [rbx + EP_grammars]
 mov edx, 8
 call prep_owned_vec_push
 test rax, rax
 jz cm_fail
 mov [rax], r12
 EPILOGUE
# Input ep, relative path. PT source/id live in EP ledger, not fixture storage.
cm_pt:
 PROLOGUE AP_SIZE
 mov rbx, rdi
 mov r12, rsi
 mov rdi, r12
 call strlen
 mov [rsp + AP_path], r12
 mov [rsp + AP_len], rax
 mov rdi, rbx
 lea rsi, [rip + cm_id]
 mov edx, 3
 call prep_owned_dup
 test rax, rax
 jz cm_fail
 mov [rsp + AP_name], rax
 mov rdi, rbx
 lea rsi, [rip + cm_theme]
 mov rdx, [rip + cm_themelen]
 call prep_owned_dup
 test rax, rax
 jz cm_fail
 mov rsi, rax
 mov rdi, rbx
 mov rdx, [rip + cm_themelen]
 mov rcx, rsp
 call prep_theme_product
 test rax, rax
 jnz cm_fail
 EPILOGUE
FN main
 PROLOGUE
 mov rax, [rip + g_mem_live]
 mov [rip + cm_live], rax
 mov rax, [rip + prep_total_charge]
 mov [rip + cm_charge], rax
 mov qword ptr [rip + cm_stage], 1
 call catalog_kind7_init
 test rax, rax
 jnz cm_fail
 call theme_capture_startup_begin
 test rax, rax
 jnz cm_fail
 lea rax, [rip + cm_sharedname]
 mov [rip + cm_usergr + GR_name], rax
 mov [rip + cm_builtingr + GR_name], rax
 lea rdi, [rip + cm_input]
 call registry_base_begin
 test rax, rax
 jz cm_fail
 mov [rip + cm_base], rax
 mov r12d, 100000
1: mov rdi, [rip + cm_base]
 cmp qword ptr [rdi + RB_phase], RB_NEEDS_QUALIFY
 jne 2f
 lea rsi, [rip + cm_input]
 call registry_base_qualify_one
 test rax, rax
 js cm_fail
2: mov rdi, [rip + cm_base]
 lea rsi, [rip + cm_input]
 mov edx, 1
 call registry_base_step
 cmp r8, 1
 ja cm_fail
 cmp r9, 16
 ja cm_fail
 test rax, rax
 js cm_fail
 jz 3f
 dec r12
 jnz 1b
 jmp cm_fail
3: mov qword ptr [rip + cm_stage], 2
 xor r12d, r12d
4: mov rdi, -1
 lea rsi, [rip + cm_dir]
 lea rdx, [rip + cm_owner]
 lea rcx, [rip + cm_name]
 call ext_prepare_alloc
 test rax, rax
 jz cm_fail
 mov r13, rax
 lea rcx, [rip + cm_eps]
 mov [rcx + r12*8], rax
 mov rcx, [rax + PO_eo]
 mov qword ptr [rcx + EO_deferred], 1
 mov qword ptr [rax + EP_kind], 2
 cmp r12, 1
 jne 5f
 mov qword ptr [rax + EP_kind], 1
5: cmp r12, 4
 jne 28f
 lea rsi, [rip + cm_path5]
 mov rdi, r13
 call cm_pt
 jmp 8f
28: mov rdi, r13
 xor esi, esi
 call cm_gp
 cmp r12, 0
 je 8f
 cmp r12, 1
 jne 6f
 mov rdi, r13
 mov esi, 1
 call cm_gp
 lea rsi, [rip + cm_path2]
 mov rdi, r13
 call cm_pt
 jmp 7f
6: cmp r12, 2
 jne 9f
 mov rdi, r13
 mov esi, 2
 call cm_gp
 mov rdi, r13
 mov esi, 3
 call cm_gp
 mov rdi, r13
 mov esi, 4
 call cm_gp
 lea rsi, [rip + cm_path3]
 mov rdi, r13
 call cm_pt
7: lea rsi, [rip + cm_path1]
 mov rdi, r13
 call cm_pt
 jmp 8f
9: mov rdi, r13
 mov esi, 4
 call cm_gp
 lea rsi, [rip + cm_path4]
 mov rdi, r13
 call cm_pt
8: mov qword ptr [r13 + PO_ready], 1
 inc r12
 cmp r12, 5
 jb 4b
 # An actual owned directory handle follows the final supplier EO into DOC's GP.
 cmp qword ptr [rip + g_argc], 2
 jne cm_fail
 mov rax, [rip + g_argv]
 mov rdi, [rax + 8]
 call ext_root_open
 test rax, rax
 js cm_fail
 mov [rip + cm_lease], rax
 mov rcx, [rip + cm_eps + 24]
 mov rcx, [rcx + PO_eo]
 mov [rcx + EO_lease], rax
 mov qword ptr [rip + cm_stage], 3
 mov rdi, [rip + cm_base]
 mov esi, 67
 call registry_begin
 test rax, rax
 jz cm_fail
 test rdx, rdx
 jnz cm_fail
 mov rbx, rax
 mov [rip + cm_rg], rax
 mov rdi, rbx
 mov esi, 1
 call registry_step
 cmp rax, -16
 jne cm_fail
 xor r12d, r12d
10: mov rdi, rbx
 lea rax, [rip + cm_eps]
 mov rsi, [rax + r12*8]
 call registry_add_ep
 test rax, rax
 jnz cm_fail
 lea rax, [rip + cm_eps]
 mov rdi, [rax + r12*8]
 call ext_prepare_release_deferred
 cmp rdx, 1
 jne cm_fail
 inc r12
 cmp r12, 5
 jb 10b
 mov rdi, [rip + cm_base]
 call registry_base_release_deferred
 cmp rdx, 1
 jne cm_fail
 .if CM_CANCEL_PHASE == 0
 jmp cm_cancel
 .endif
 mov rdi, rbx
 call registry_seal_inputs
 test rax, rax
 jnz cm_fail
 mov rdi, rbx
 call registry_seal_inputs
 test rax, rax
 jnz cm_fail
 mov rdi, rbx
 lea rax, [rip + cm_eps]
 mov rsi, [rax + 8]
 call registry_add_ep
 cmp rax, -16
 jne cm_fail
 mov qword ptr [rip + cm_stage], 4
 mov r12d, 1000000
11:
 .if CM_CANCEL_PHASE > 0
 cmp qword ptr [rbx + RG_phase], CM_CANCEL_PHASE
 je cm_cancel
 .endif
 .if CM_CANCEL_POINT == 100
 cmp qword ptr [rbx + RG_phase], RG_GRAMMAR
 jne 20f
 cmp qword ptr [rbx + RW_stage], 3
 je cm_cancel
20:
 .endif
 .if CM_CANCEL_POINT == 101
 # The public step commits+releases in one no-yield slice. Exercise its actual
 # single-unit helper boundary directly, without changing production limits.
 cmp qword ptr [rbx + RG_phase], RG_GRAMMAR
 jne 27f
 cmp qword ptr [rbx + RW_stage], 3
 jne 27f
 mov rdi, rbx
 call registry_grammar_one
 test rax, rax
 js cm_fail
27: cmp qword ptr [rbx + RG_old_gp], 0
 jne cm_cancel
 .endif
 .if CM_CANCEL_POINT == 102
 cmp qword ptr [rbx + RG_phase], RG_GRAMMAR
 jne 21f
 mov rax, [rbx + RG_grammar_map]
 test rax, rax
 jz 21f
 cmp qword ptr [rax + RM_phase], RM_COMPARE
 je cm_cancel
21:
 .endif
 .if CM_CANCEL_POINT == 103
 cmp qword ptr [rbx + RG_phase], RG_THEME
 jne 22f
 cmp qword ptr [rbx + RW_stage], 4
 jne 22f
 cmp qword ptr [rbx + RW_scanlen], 0
 jne cm_cancel
22:
 .endif
 .if CM_CANCEL_POINT == 104
 cmp qword ptr [rbx + RG_phase], RG_FINAL_REFS
 jne 23f
 cmp qword ptr [rbx + RG_index], 2
 jae cm_cancel
23:
 .endif
 .if CM_CANCEL_POINT == 105
 cmp qword ptr [rbx + RG_phase], RG_DROP_INPUT
 jne 24f
 cmp qword ptr [rbx + RG_index], 1
 jae cm_cancel
24:
 .endif
 .if CM_CANCEL_POINT == 106
 cmp qword ptr [rbx + RG_phase], RG_ALLOCATE
 jne 25f
 cmp qword ptr [rbx + RW_alloc], 7
 je cm_cancel
25:
 .endif
 .if CM_CANCEL_POINT == 107
 cmp qword ptr [rbx + RG_phase], RG_COPY_BASE
 jne 26f
 cmp qword ptr [rbx + RW_stage], 2
 je cm_cancel
26:
 .endif
 mov rdi, rbx
 mov esi, 1
 call registry_step
 cmp r8, 1
 ja cm_fail
 cmp r9, 16
 ja cm_fail
 test rax, rax
 .if CM_OOM_N + CM_REF_FAULT > 0
 js cm_expected_failure
 .else
 js cm_fail
 .endif
 jz 12f
 dec r12
 jnz 11b
 jmp cm_fail
12:
 .if CM_CANCEL_POINT >= 100
 jmp cm_fail
 .endif
 .if CM_OOM_N > 0
 jmp cm_fail
 .endif
 .if CM_REF_FAULT > 0
 .if CM_REF_FAULT < 6
 jmp cm_fail
 .endif
 .endif
 mov qword ptr [rip + cm_stage], 5
 .if CM_REF_FAULT == 6
 mov rdi, rbx
 call registry_status
 cmp rax, RG_READY
 jne cm_fail
 test rdx, rdx
 jnz cm_fail
 cmp rcx, -5
 jne cm_fail
 cmp r8, 1
 jne cm_fail
 .endif
 mov rdi, rbx
 call registry_view
 test rax, rax
 jz cm_fail
 cmp qword ptr [rax + 8], 7
 jne cm_fail
 cmp qword ptr [rax + 32], 8
 jne cm_fail
 cmp qword ptr [rax + 56], 8
 jne cm_fail
 cmp qword ptr [rax + 64], 0
 jne cm_fail
 cmp qword ptr [rax + 72], 67
 jne cm_fail
 cmp qword ptr [rax + 96], 31
 jne cm_fail
 mov r12, rax
 mov r13, [rax]
 # Every extension TH is the exact expected immutable PT copy at its ordinal.
 .macro CM_TH_AT ordinal, input, asset
 lea rax, [rip + cm_eps]
 mov r15, [rax + 8*\input]
 mov r14, \asset
 imul r14, PT_SIZE
 add r14, [r15 + EP_themeviews + VEC_ptr]
 mov rdi, [r12 + 24]
 add rdi, TH_SIZE*\ordinal
 mov rsi, r14
 mov edx, TH_SIZE
 call memeq
 test eax, eax
 jz cm_fail
 mov rax, [rbx + RG_meta]
 add rax, TM_SIZE*\ordinal
 cmp qword ptr [rax + TM_kind], REG_EXTENSION
 jne cm_fail
 cmp qword ptr [rax + TM_supplier], \input
 jne cm_fail
 cmp [rax + TM_pt], r14
 jne cm_fail
 mov rcx, [r14 + TH_path]
 cmp [rax + TM_key], rcx
 jne cm_fail
 mov r15, rax
 cmp qword ptr [r15 + TM_path], 0
 jne cm_fail
 cmp qword ptr [r15 + TM_pathlen], 0
 jne cm_fail
 cmp qword ptr [r15 + TM_baseordinal], -1
 jne cm_fail
 mov rdi, [r14 + TH_path]
 call strlen
 cmp [r15 + TM_keylen], rax
 jne cm_fail
 mov rdi, [r14 + TH_id]
 call strlen
 cmp [r15 + TM_idlen], rax
 jne cm_fail
 mov rdi, [r14 + TH_name]
 call strlen
 cmp [r15 + TM_namelen], rax
 jne cm_fail
 mov rax, [r12 + 48]
 mov rcx, [r14 + TH_id]
 cmp [rax + 16*\ordinal], rcx
 jne cm_fail
 mov rcx, [r15 + TM_idlen]
 cmp [rax + 16*\ordinal + 8], rcx
 jne cm_fail
 .endm
 CM_TH_AT 1,2,1
 CM_TH_AT 4,1,0
 CM_TH_AT 5,2,0
 CM_TH_AT 6,3,0
 CM_TH_AT 7,4,0
 # Follow, builtin and raw-spelling alias keep their exact base descriptors.
 mov rax, [rbx + RG_base]
 mov r15, [rax + RB_themes]
 mov r14, [r12 + 24]
 xor rdi, rdi
 .macro CM_BASE_FIELD dst, source
 mov rdx, [rcx + \source]
 cmp [rax + \dst], rdx
 jne cm_fail
 .endm
 .macro CM_BASE_TH ordinal
 lea rdi, [r14 + TH_SIZE*\ordinal]
 lea rsi, [r15 + TH_SIZE*\ordinal]
 mov edx, TH_SIZE
 call memeq
 test eax, eax
 jz cm_fail
 mov rax, [rbx + RG_meta]
 add rax, TM_SIZE*\ordinal
 cmp qword ptr [rax + TM_baseordinal], \ordinal
 jne cm_fail
 cmp qword ptr [rax + TM_supplier], -1
 jne cm_fail
 cmp qword ptr [rax + TM_pt], 0
 jne cm_fail
 mov rcx, [rbx + RG_base]
 mov rcx, [rcx + RB_meta]
 add rcx, BTM_SIZE*\ordinal
 CM_BASE_FIELD TM_kind,BTM_kind
 CM_BASE_FIELD TM_key,BTM_key
 CM_BASE_FIELD TM_keylen,BTM_keylen
 CM_BASE_FIELD TM_path,BTM_path
 CM_BASE_FIELD TM_pathlen,BTM_pathlen
 CM_BASE_FIELD TM_idlen,BTM_idlen
 CM_BASE_FIELD TM_namelen,BTM_namelen
 mov rcx, [r12 + 48]
 mov rdx, [r15 + TH_SIZE*\ordinal + TH_id]
 cmp [rcx + 16*\ordinal], rdx
 jne cm_fail
 mov rdx, [rax + TM_idlen]
 cmp [rcx + 16*\ordinal + 8], rdx
 jne cm_fail
 .endm
 CM_BASE_TH 0
 CM_BASE_TH 2
 CM_BASE_TH 3
 lea rax, [rip + cm_usergr]
 cmp [r13], rax
 jne cm_fail
 lea rax, [rip + cm_builtingr]
 cmp [r13 + 48], rax
 jne cm_fail
 # Assert every extension identity at its original output ordinal, not only counts.
 .macro CM_GR_AT ordinal, input, asset
 lea rax, [rip + cm_eps]
 mov rax, [rax + 8*\input]
 mov rax, [rax + EP_grammars + VEC_ptr]
 mov rax, [rax + 8*\asset]
 add rax, GP_gr
 cmp [r13 + 8*\ordinal], rax
 jne cm_fail
 .endm
 CM_GR_AT 1,3,0
 CM_GR_AT 2,1,1
 CM_GR_AT 3,2,1
 CM_GR_AT 4,2,2
 CM_GR_AT 5,3,1
 mov rax, [r13 + 32]
 cmp qword ptr [rax + GR_name], 0
 jne cm_fail
 mov rax, [r13 + 40]
 mov rax, [rax + GR_name]
 test rax, rax
 jz cm_fail
 cmp byte ptr [rax], 0
 jne cm_fail
 mov rax, [r13 + 8]
 mov r15, [rax + GR_owner]
 lea rcx, [rip + cm_eps]
 mov rdx, [rcx + 24]
 mov rsi, [rdx + EP_grammars + VEC_ptr]
 cmp [rsi], r15
 jne cm_fail
 cmp qword ptr [r15 + PO_refs], 2
 jne cm_fail
 mov [rip + cm_keptgp], r15
 call doc_new
 mov [rip + cm_doc], rax
 mov rdi, rax
 lea rsi, [r15 + GP_gr]
 call doc_set_grammar
 test rax, rax
 jnz cm_fail
 mov rdi, rbx
 call registry_segments
 cmp rax, 1
 jne cm_fail
 cmp rdx, 5
 jne cm_fail
 cmp rcx, 1
 jne cm_fail
 cmp r8, 7
 jne cm_fail
 # The first input has no wins and no surviving final supplier reference.
 mov rax, [rbx + RG_suppliers]
 cmp qword ptr [rax], 0
 jne cm_fail
 lea rcx, [rip + cm_eps]
 mov rdx, [rcx + 8]
 cmp qword ptr [rdx + PO_refs], 1
 jne cm_fail
 mov rdx, [rcx + 16]
 cmp qword ptr [rdx + PO_refs], 1
 jne cm_fail
 mov rdx, [rcx + 24]
 cmp qword ptr [rdx + PO_refs], 1
 jne cm_fail
 mov rdx, [rcx + 32]
 cmp qword ptr [rdx + PO_refs], 1
 jne cm_fail
 cmp qword ptr [rdx + EP_grammars + VEC_len], 0
 jne cm_fail
 mov rax, [rbx + RG_suppliers]
 cmp qword ptr [rax + 4*RGS_SIZE + RGS_grammars], 0
 jne cm_fail
 cmp qword ptr [rax + 4*RGS_SIZE + RGS_themes], 1
 jne cm_fail
 cmp [rax + 4*RGS_SIZE + RGS_ep], rdx
 jne cm_fail
 mov rax, [rbx + RG_inputs]
 cmp qword ptr [rax + RGS_grammars], 0
 jne cm_fail
 cmp qword ptr [rax + RGS_themes], 0
 jne cm_fail
 cmp qword ptr [rax], 0
 jne cm_fail
 cmp qword ptr [rax + RGS_SIZE], 0
 jne cm_fail
 cmp qword ptr [rax + 2*RGS_SIZE], 0
 jne cm_fail
 cmp qword ptr [rax + 3*RGS_SIZE], 0
 jne cm_fail
 cmp qword ptr [rax + 4*RGS_SIZE], 0
 jne cm_fail
 mov rdi, rbx
 mov esi, 1
 call registry_theme_source
 test rax, rax
 jz cm_fail
 cmp qword ptr [rax + TM_kind], REG_EXTENSION
 jne cm_fail
 cmp qword ptr [rax + TM_supplier], 2
 jne cm_fail
 cmp qword ptr [rax + TM_path], 0
 jne cm_fail
 mov rdi, rbx
 mov esi, 3
 call registry_theme_source
 cmp qword ptr [rax + TM_kind], REG_USER
 jne cm_fail
 cmp qword ptr [rax + TM_baseordinal], 3
 jne cm_fail
 # The relative raw key remains distinct from an independently qualified IO path.
 mov r14, rax
 mov rdi, [rax + TM_key]
 call tc_path_len
 test rax, rax
 jns cm_fail
 mov rdi, [r14 + TM_path]
 call tc_path_len
 test rax, rax
 jle cm_fail
 cmp [r14 + TM_pathlen], rax
 jne cm_fail
 mov rax, [rip + g_theme_capture_charge]
 mov [rip + cm_tcharge], rax
 mov qword ptr [rip + cm_tconfig + TCFG_job], 1
 mov qword ptr [rip + cm_tconfig + TCFG_context], 67
 mov qword ptr [rip + cm_tconfig + TCFG_nonce], 1
 lea rdi, [rip + cm_tconfig]
 xor esi, esi
 call theme_capture_request_begin
 test rax, rax
 jz cm_fail
 mov [rip + cm_trequest], rax
 mov rdi, rax
 mov esi, 3
 mov rdx, [r14 + TM_path]
 call theme_capture_request_add
 test rax, rax
 jnz cm_fail
 mov rax, [rip + cm_trequest]
 cmp qword ptr [rax + TCQ_count], 1
 jne cm_fail
 mov rax, [rax + TCQ_wire]
 cmp dword ptr [rax + TC_HEADER_SIZE], 3
 jne cm_fail
 mov edx, [rax + TC_HEADER_SIZE + 4]
 cmp [r14 + TM_pathlen], rdx
 jne cm_fail
 lea rdi, [rax + TC_HEADER_SIZE + TC_REQUEST_ROW]
 mov rsi, [r14 + TM_path]
 call memeq
 test eax, eax
 jz cm_fail
 mov rdi, [rip + cm_trequest]
 call theme_capture_request_seal
 test rax, rax
 jnz cm_fail
 mov rdi, [rip + cm_trequest]
 call theme_capture_request_free
 cmp rdx, 1
 jne cm_fail
 mov rax, [rip + cm_tcharge]
 cmp [rip + g_theme_capture_charge], rax
 jne cm_fail
 # Deep-copied base membership/descriptors were never overwritten by replacement.
 mov rdi, rbx
 call registry_base_owner
 mov rax, [rax + RB_themes]
 cmp qword ptr [rax + TH_SIZE + TH_owner], 0
 jne cm_fail
 mov rdi, [rax + TH_SIZE + TH_name]
 lea rsi, [rip + cm_username]
 call strcmp_eq
 test eax, eax
 jz cm_fail
 call cm_drain
 mov rax, [rip + cm_eps + 32]
 cmp qword ptr [rax + PO_refs], 1
 jne cm_fail
 CM_TH_AT 7,4,0
 mov rdi, r12
 lea rsi, [rip + cm_id]
 mov edx, 3
 mov ecx, 1
 xor r8d, r8d
 call cm_lookup
 mov rdi, r12
 lea rsi, [rip + cm_followid]
 mov edx, 6
 mov rcx, -2
 mov r8d, 1
 call cm_lookup
 mov qword ptr [rip + cm_stage], 6
 mov rdi, rbx
 call registry_release_deferred
 cmp rdx, 1
 jne cm_fail
 call cm_drain
 mov rdi, [rip + cm_keptgp]
 call grammar_prepare_gr
 test rax, rax
 jz cm_fail
 mov rdi, [rax + GR_name]
 lea rsi, [rip + cm_sharedname]
 call strcmp_eq
 test eax, eax
 jz cm_fail
 mov rdi, [rip + cm_lease]
 lea rsi, [rip + cm_identity]
 call ext_root_identity
 test rax, rax
 js cm_fail
 mov rdi, [rip + cm_doc]
 mov rax, [rip + cm_keptgp]
 cmp [rdi + DOC_language_owner], rax
 jne cm_fail
 call doc_free
 call cm_drain
 mov rdi, [rip + cm_lease]
 lea rsi, [rip + cm_identity]
 call ext_root_identity
 test rax, rax
 jns cm_fail
cm_check_balance:
 mov rax, [rip + prep_total_charge]
 cmp rax, [rip + cm_charge]
 jne cm_fail
 mov rax, [rip + g_mem_live]
 cmp rax, [rip + cm_live]
 jne cm_fail
 xor eax, eax
 EPILOGUE

cm_cancel:
 mov qword ptr [rip + cm_stage], 6
 mov rdi, rbx
 call registry_release_deferred
 cmp rdx, 1
 jne cm_fail
 call cm_drain
 jmp cm_check_balance

# Real counted candidate lookup consumes the sealed view, duplicate IDs remain first-match.
cm_lookup:
 PROLOGUE
 mov r12, rdi
 mov r13, rcx
 mov r14, r8
 mov rcx, rdx
 mov rdx, rsi
 lea rsi, [r12 + 48]
 lea rdi, [rip + cm_lookup_cursor]
 call theme_capture_candidate_begin
 test rax, rax
 jnz cm_fail
 mov r15d, 1000
1: lea rdi, [rip + cm_lookup_cursor]
 mov esi, 67
 mov edx, 1
 call theme_capture_candidate_step
 cmp rdx, 1
 ja cm_fail
 cmp rcx, 16
 ja cm_fail
 test rax, rax
 js cm_fail
 jz 2f
 dec r15
 jnz 1b
 jmp cm_fail
2: cmp [rip + cm_lookup_cursor + TCL_result], r13
 jne cm_fail
 cmp [rip + cm_lookup_cursor + TCL_self], r14
 jne cm_fail
 EPILOGUE

cm_expected_failure:
 mov r14, rax
 .if CM_OOM_N > 0
 cmp rax, -12
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 1
 cmp rax, -75
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 2
 cmp rax, -5
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 3
 cmp rax, -75
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 4
 cmp rax, -5
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 2
 mov rax, [rip + cm_ref_target]
 cmp [rbx + RG_old_gp], rax
 jne cm_fail
 mov rcx, [rip + cm_ref_refs]
 cmp [rax + PO_refs], rcx
 jne cm_fail
 .endif
 .if CM_REF_FAULT == 4
 mov rax, [rbx + RG_index]
 imul rax, rax, RGS_SIZE
 add rax, [rbx + RG_inputs]
 mov rcx, [rip + cm_ref_target]
 cmp [rax + RGS_ep], rcx
 jne cm_fail
 mov rax, [rip + cm_ref_refs]
 cmp [rcx + PO_refs], rax
 jne cm_fail
 .endif
 cmp qword ptr [rbx + PO_ready], 0
 jne cm_fail
 cmp qword ptr [rbx + RG_phase], RG_FAILED
 jne cm_fail
 mov rdi, rbx
 call registry_view
 test rax, rax
 jnz cm_fail
 mov rdi, rbx
 mov esi, 65536
 call registry_step
 cmp rax, r14
 jne cm_fail
 test r8, r8
 jnz cm_fail
 test r9, r9
 jnz cm_fail
 jmp cm_cancel

# Scoped primitive wrappers are linked only by the corresponding explicit fault.
 .if CM_OOM_N > 0
FN mem_alloc_try
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_mem_alloc_try
 inc qword ptr [rip + cm_alloc_calls]
 cmp qword ptr [rip + cm_alloc_calls], CM_OOM_N
 jne cm_actual_mem_alloc_try
 xor eax, eax
 ret
 .endif
 .if CM_REF_FAULT == 1
FN grammar_prepare_retain
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_grammar_prepare_retain
 mov rax, -75
 ret
 .endif
 .if CM_REF_FAULT == 3
FN ext_prepare_retain
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_ext_prepare_retain
 mov rax, -75
 ret
 .endif
 .if CM_REF_FAULT == 2
FN prep_object_release_deferred
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_prep_object_release_deferred
 mov rax, [rip + cm_rg]
 cmp [rax + RG_old_gp], rdi
 jne cm_actual_prep_object_release_deferred
 cmp qword ptr [rip + cm_ref_armed], 0
 jne cm_actual_prep_object_release_deferred
 mov qword ptr [rip + cm_ref_armed], 1
 mov [rip + cm_ref_target], rdi
 mov rax, [rdi + PO_refs]
 mov [rip + cm_ref_refs], rax
 mov rax, -5
 xor edx, edx
 ret
 .endif
 .if CM_REF_FAULT == 4
FN ext_prepare_release_deferred
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_ext_prepare_release_deferred
 cmp qword ptr [rip + cm_ref_armed], 0
 jne cm_actual_ext_prepare_release_deferred
 mov qword ptr [rip + cm_ref_armed], 1
 mov [rip + cm_ref_target], rdi
 mov rax, [rdi + PO_refs]
 mov [rip + cm_ref_refs], rax
 mov rax, -5
 xor edx, edx
 ret
 .endif
 .if CM_REF_FAULT == 6
FN prep_object_release_deferred
 cmp qword ptr [rip + cm_stage], 4
 jne cm_actual_prep_object_release_deferred
 mov rax, [rip + cm_rg]
 cmp [rax + RG_old_gp], rdi
 jne cm_actual_prep_object_release_deferred
 cmp qword ptr [rip + cm_ref_armed], 0
 jne cm_actual_prep_object_release_deferred
 mov qword ptr [rip + cm_ref_armed], 1
 PROLOGUE
 call cm_actual_prep_object_release_deferred
 cmp rdx, 1
 jne cm_fail
 mov rax, -5
 EPILOGUE
 .endif

# Preparation may parse/open; the sealed merge phase may only use owned byte spans.
 .if CM_PURE_IO
FN ext_root_open
 cmp qword ptr [rip + cm_stage], 4
 je cm_fail
 jmp cm_actual_ext_root_open
FN file_read_limited_try
 cmp qword ptr [rip + cm_stage], 4
 je cm_fail
 jmp cm_actual_file_read_limited_try
FN grammar_fill_context
 cmp qword ptr [rip + cm_stage], 4
 je cm_fail
 jmp cm_actual_grammar_fill_context
FN theme_parse_into
 cmp qword ptr [rip + cm_stage], 4
 je cm_fail
 jmp cm_actual_theme_parse_into
 .endif
