# Actual keys_init oracle and retained prepared inputs for bounded immutable command views.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntime.inc"
.include "app/commandgeneration.inc"
.include "app/keycombo.inc"
.bss
.p2align 3
cgbt_stage: .quad 0
cgbt_alloc_fault: .quad 0
cgbt_alloc_calls: .quad 0
cgbt_all_alloc_calls: .quad 0
cgbt_long_seen: .quad 0
cgbt_long_a: .zero 8193
cgbt_long_b: .zero 8193
cgbt_long_label: .zero 8193
cgbt_long_title: .zero 8193
cgbt_long_value: .zero 20000
cgbt_long_query: .zero 8400
cgbt_live: .quad 0
cgbt_charge: .quad 0
cgbt_context: .zero 24
cgbt_saved: .zero CG_SIZE
cgbt_ini: .zero INI_SIZE
cgbt_exts: .zero 128 * EXT_SIZE
cgbt_retire: .zero 32
cgbt_views: .zero 96
cgbt_slot_out: .zero 16
cgbt_roc: .zero ROC_SIZE
.text
cgbt_fail:
    mov rdi, [rip + cgbt_stage]
    add rdi, 80
    call sys_exit
    ud2
cgbt_new:
    PROLOGUE
    lea rdi, [rip + cgbt_context]
    call command_generation_begin
    test rax, rax
    jz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    test rcx, rcx
    jnz cgbt_fail
    EPILOGUE
# owner,name,title -> actual EP with no source descriptor; ready only after contributions.
cgbt_ep:
    PROLOGUE
    mov r12, rdx
    mov rcx, rsi
    mov rdx, rdi
    mov rdi, -1
    lea rsi, [rip + cgbt_path]
    call ext_prepare_alloc
    test rax, rax
    jz cgbt_fail
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_enable_deferred
    test rax, rax
    jnz cgbt_fail
    mov [rbx + EP_ext + EXT_title], r12
    mov rax, rbx
    EPILOGUE
# EP,key,display-and-defaults -> actual immutable manifest command factory.
cgbt_command:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    call strlen
    mov [rip + cgbt_ini + INI_key], r12
    mov [rip + cgbt_ini + INI_keylen], rax
    mov rdi, r13
    call strlen
    mov [rip + cgbt_ini + INI_val], r13
    mov [rip + cgbt_ini + INI_vallen], rax
    mov rdi, rbx
    lea rsi, [rip + cgbt_ini]
    call ext_prepare_command_add
    test rax, rax
    jnz cgbt_fail
    EPILOGUE
# CG,combo,command -> copied ordered keyline; caller strings are borrowed for these calls only.
cgbt_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    call strlen
    mov r14, rax
    mov rdi, r13
    call strlen
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call command_generation_key_begin
    test rax, rax
    jnz cgbt_fail
    test r14, r14
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call command_generation_key_append
    test rax, rax
    jnz cgbt_fail
1:  test r15, r15
    jz 2f
    mov r14d, 4096
    cmp r14, r15
    cmova r14, r15
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call command_generation_key_append
    test rax, rax
    jnz cgbt_fail
    add r13, r14
    sub r15, r14
    jmp 1b
2:  mov rdi, rbx
    call command_generation_key_finish
    test rax, rax
    jnz cgbt_fail
    EPILOGUE
# CG -> terminal ready/error. Actual budgets vary1..16; no scheduler call may exceed it.
cgbt_build:
    PROLOGUE
    mov rbx, rdi
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
    mov r12d, 2000000
    mov r13d, 1
1:  mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov rdx, r13
    mov r14, [rbx + CG_phase]
    call command_generation_step
    cmp rdx, r13
    ja cgbt_fail
    cmp r14, 8
    ja 2f
    cmp rdx, 1
    jne cgbt_fail
2:  test rax, rax
    jle 3f
    cmp rax, 1
    jne cgbt_fail
    inc r13
    cmp r13, 16
    jbe 4f
    mov r13d, 1
4:  dec r12
    jnz 1b
    jmp cgbt_fail
3:  EPILOGUE
cgbt_drain:
    PROLOGUE
    mov ebx, 200000
1:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgbt_fail
    cmp qword ptr [rip + cgbt_retire], 1
    ja cgbt_fail
    cmp qword ptr [rip + cgbt_retire + 16], 0
    jne cgbt_fail
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp cgbt_fail
2:  call ext_prepare_retire_charge
    cmp rax, [rip + cgbt_charge]
    jne cgbt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cgbt_live]
    jne cgbt_fail
    EPILOGUE
cgbt_abort:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + g_mem_live]
    call command_generation_release_deferred
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    cmp [rip + g_mem_live], r12
    jne cgbt_fail
    call cgbt_drain
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    mov qword ptr [rip + cgbt_stage], 1
    call cgbt_new
    mov rbx, rax
    lea rdi, [rip + cgbt_one]
    lea rsi, [rip + cgbt_tool]
    lea rdx, [rip + cgbt_title]
    call cgbt_ep
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_runval]
    call cgbt_command
    mov rdi, r12
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov rdi, r12
    lea rsi, [rip + cgbt_pathkey]
    lea rdx, [rip + cgbt_pathval]
    call cgbt_command
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    lea rdi, [rip + cgbt_two]
    lea rsi, [rip + cgbt_other]
    xor edx, edx
    call cgbt_ep
    mov r13, rax
    mov rdi, r13
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_otherval]
    call cgbt_command
    mov rdi, r13
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov qword ptr [r13 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + cgbt_exts + 94 * EXT_SIZE]
    mov ecx, 94
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r13
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_exts + 111 * EXT_SIZE]
    mov edx, 111
    lea rcx, [rip + cgbt_three]
    lea r8, [rip + cgbt_tool]
    call command_generation_add_identity
    test rax, rax
    jnz cgbt_fail
    lea rax, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov [rip + cgbt_roc + ROC_target], rax
    mov qword ptr [rip + cgbt_roc + ROC_session], 7
    lea rax, [rip + cgbt_one]
    mov [rip + cgbt_roc + ROC_owner], rax
    lea rax, [rip + cgbt_tool]
    mov [rip + cgbt_roc + ROC_name], rax
    lea rax, [rip + cgbt_dynamic]
    mov [rip + cgbt_roc + ROC_key], rax
    lea rax, [rip + cgbt_rawtitle]
    mov [rip + cgbt_roc + ROC_title], rax
    lea rax, [rip + cgbt_runtimekeys]
    mov [rip + cgbt_roc + ROC_keys], rax
    mov qword ptr [rip + cgbt_roc + ROC_keyslen], 10
    lea rdi, [rip + cgbt_roc]
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r14, rax
    mov rdi, rbx
    mov rsi, r14
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r14
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo0]
    lea rdx, [rip + cgbt_cmd0]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo1]
    lea rdx, [rip + cgbt_cmd1]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo2]
    lea rdx, [rip + cgbt_cmd2]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo3]
    lea rdx, [rip + cgbt_cmd3]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo4]
    lea rdx, [rip + cgbt_cmd4]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo5]
    lea rdx, [rip + cgbt_cmd5]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo6]
    lea rdx, [rip + cgbt_cmd6]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo7]
    lea rdx, [rip + cgbt_cmd7]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo8]
    lea rdx, [rip + cgbt_cmd8]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo9]
    lea rdx, [rip + cgbt_cmd9]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_combo10]
    lea rdx, [rip + cgbt_cmd10]
    call cgbt_line
    mov rdi, rbx
    lea rsi, [rip + cgbt_emptycombo]
    lea rdx, [rip + cgbt_cmd9]
    call cgbt_line
    # The builder must not touch live vectors, even when their address/count is poisoned.
    mov qword ptr [rip + g_exts], 1
    mov qword ptr [rip + g_exts + VEC_len], -1
    mov qword ptr [rip + g_ext_cmds], 1
    mov qword ptr [rip + g_ext_cmds + VEC_len], -1
    mov qword ptr [rip + g_ext_owner], 1
    mov qword ptr [rip + g_ext_owner + VEC_len], -1
    mov qword ptr [rip + g_keylines], 1
    mov qword ptr [rip + g_keylines + VEC_len], -1
    mov qword ptr [rip + cgbt_stage], 2
    mov rdi, rbx
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + PO_ready], 1
    jne cgbt_fail
    cmp qword ptr [rbx + CG_ncommands], 6
    jne cgbt_fail
    cmp qword ptr [rip + g_exts], 1
    jne cgbt_fail
    cmp qword ptr [rip + g_exts + VEC_len], -1
    jne cgbt_fail
    cmp qword ptr [rip + g_ext_cmds], 1
    jne cgbt_fail
    cmp qword ptr [rip + g_ext_cmds + VEC_len], -1
    jne cgbt_fail
    cmp qword ptr [rip + g_ext_owner], 1
    jne cgbt_fail
    cmp qword ptr [rip + g_ext_owner + VEC_len], -1
    jne cgbt_fail
    cmp qword ptr [rip + g_keylines], 1
    jne cgbt_fail
    cmp qword ptr [rip + g_keylines + VEC_len], -1
    jne cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    call command_generation_check
    test rax, rax
    jnz cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_views]
    call command_generation_views
    test rax, rax
    jnz cgbt_fail
    mov rdi, [rip + cgbt_views]
    mov rsi, [r12 + EP_commands]
    mov edx, 3 * CMD_SIZE
    # PC rows are56 bytes, so compare each actual CMD prefix independently.
    xor r15d, r15d
1:  imul rdi, r15, CMD_SIZE
    add rdi, [rip + cgbt_views]
    imul rsi, r15, PC_SIZE
    add rsi, [r12 + EP_commands]
    mov edx, CMD_SIZE
    call memeq
    test eax, eax
    jz cgbt_fail
    inc r15
    cmp r15, 3
    jb 1b
    mov rax, [rip + cgbt_views]
    mov rdi, [rax + 5 * CMD_SIZE + CMD_title]
    lea rsi, [rip + cgbt_formatted]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rax, [rip + cgbt_views + 48]
    cmp qword ptr [rax + 5 * 64], 1
    jne cgbt_fail
    cmp [rax + 5 * 64 + 8], r14
    jne cgbt_fail
    cmp qword ptr [rax + 5 * 64 + 48], 7
    jne cgbt_fail
    mov rax, [rip + cgbt_views + 24]
    cmp qword ptr [rax], 17
    jne cgbt_fail
    cmp qword ptr [rax + 3 * 8], 94
    jne cgbt_fail
    mov rdi, rbx
    call command_generation_manifest_count
    cmp rax, 5
    jne cgbt_fail
    lea r15, [rip + cgbt_views]
    cmp qword ptr [r15 + VEC_len], 6
    jne cgbt_fail
    cmp qword ptr [r15 + 24 + VEC_len], 6
    jne cgbt_fail
    cmp qword ptr [r15 + 48 + VEC_len], 6
    jne cgbt_fail
    # The second publisher's two complete CMD prefixes are independent supplier data.
    xor r15d, r15d
3:  imul rdi, r15, CMD_SIZE
    add rdi, [rbx + CG_commands]
    add rdi, 3 * CMD_SIZE
    imul rsi, r15, PC_SIZE
    add rsi, [r13 + EP_commands]
    mov edx, CMD_SIZE
    call memeq
    test eax, eax
    jz cgbt_fail
    inc r15
    cmp r15, 2
    jb 3b
    # Every authority tuple and ordinal, not only flattened wire spelling.
    xor r15d, r15d
4:  mov rax, [rbx + CG_owners]
    mov r12, 17
    cmp r15, 3
    jb 5f
    cmp r15, 5
    jae 5f
    mov r12, 94
5:  cmp [rax + r15*8], r12
    jne cgbt_fail
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_slot_out]
    call command_generation_slot
    test rax, rax
    jnz cgbt_fail
    cmp r12, 17
    jne 10f
    cmp qword ptr [rip + cgbt_slot_out], 0
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_slot_out + 8], 3
    jne cgbt_fail
    jmp 11f
10: cmp qword ptr [rip + cgbt_slot_out], 3
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_slot_out + 8], 2
    jne cgbt_fail
11: mov rax, [rbx + CG_authority]
    mov rdx, r15
    shl rdx, 6
    add rax, rdx
    lea rcx, [rip + cgbt_exts]
    imul rdx, r12, EXT_SIZE
    add rcx, rdx
    cmp [rax + 16], rcx
    jne cgbt_fail
    mov rcx, [rbx + CG_slots + CS_ep]
    cmp r12, 17
    je 6f
    mov rcx, [rbx + CG_slots + CS_SIZE + CS_ep]
6:  cmp r15, 5
    je 7f
    cmp qword ptr [rax], 0
    jne cgbt_fail
    cmp [rax + 8], rcx
    jne cgbt_fail
    cmp qword ptr [rax + 48], 0
    jne cgbt_fail
    cmp qword ptr [rax + 56], 0
    jne cgbt_fail
    mov rdx, r15
    cmp r15, 3
    jb 8f
    sub rdx, 3
8:  imul rdx, rdx, PC_SIZE
    add rdx, [rcx + EP_commands]
    mov r8, [rdx + PC_key]
    cmp [rax + 40], r8
    jne cgbt_fail
    jmp 9f
7:  cmp qword ptr [rax], 1
    jne cgbt_fail
    cmp [rax + 8], r14
    jne cgbt_fail
    cmp qword ptr [rax + 48], 7
    jne cgbt_fail
    mov rdx, [r14 + RO_incarnation]
    cmp [rax + 56], rdx
    jne cgbt_fail
9:  mov rdx, [rcx + EP_ext + EXT_owner]
    cmp [rax + 24], rdx
    jne cgbt_fail
    mov rdx, [rcx + EP_ext + EXT_name]
    cmp [rax + 32], rdx
    jne cgbt_fail
    inc r15
    cmp r15, 6
    jb 4b
    # Restore supplier register used by the existing lifetime assertion.
    mov r12, [rbx + CG_slots + CS_ep]
    mov rdi, rbx
    mov esi, 111
    lea rdx, [rip + cgbt_slot_out]
    call command_generation_slot
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rip + cgbt_slot_out], 5
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_slot_out + 8], 0
    jne cgbt_fail
    mov rdi, rbx
    mov esi, 127
    lea rdx, [rip + cgbt_slot_out]
    call command_generation_slot
    cmp rax, -2
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_check_metadata
    # Build the actual legacy binding oracle over these final rows and all visible identities.
    xor ecx, ecx
2:  imul rax, rcx, EXT_SIZE
    lea rdx, [rip + cgbt_exts]
    add rax, rdx
    mov dword ptr [rax + EXT_status], ES_REMOVED
    inc rcx
    cmp rcx, 128
    jb 2b
    lea rax, [rip + cgbt_one]
    mov [rip + cgbt_exts + 17 * EXT_SIZE + EXT_owner], rax
    lea rax, [rip + cgbt_tool]
    mov [rip + cgbt_exts + 17 * EXT_SIZE + EXT_name], rax
    mov dword ptr [rip + cgbt_exts + 17 * EXT_SIZE + EXT_status], ES_STOPPED
    lea rax, [rip + cgbt_two]
    mov [rip + cgbt_exts + 94 * EXT_SIZE + EXT_owner], rax
    lea rax, [rip + cgbt_other]
    mov [rip + cgbt_exts + 94 * EXT_SIZE + EXT_name], rax
    mov dword ptr [rip + cgbt_exts + 94 * EXT_SIZE + EXT_status], ES_STOPPED
    lea rax, [rip + cgbt_three]
    mov [rip + cgbt_exts + 111 * EXT_SIZE + EXT_owner], rax
    lea rax, [rip + cgbt_tool]
    mov [rip + cgbt_exts + 111 * EXT_SIZE + EXT_name], rax
    mov dword ptr [rip + cgbt_exts + 111 * EXT_SIZE + EXT_status], ES_DISABLED
    lea rax, [rip + cgbt_exts]
    mov [rip + g_exts], rax
    mov qword ptr [rip + g_exts + VEC_len], 128
    mov rax, [rbx + CG_commands]
    mov [rip + g_ext_cmds], rax
    mov qword ptr [rip + g_ext_cmds + VEC_len], 6
    mov rax, [rbx + CG_owners]
    mov [rip + g_ext_owner], rax
    mov qword ptr [rip + g_ext_owner + VEC_len], 6
    lea rax, [rip + cgbt_lines]
    mov [rip + g_keylines], rax
    mov qword ptr [rip + g_keylines + VEC_len], 12
    mov qword ptr [rip + cgbt_stage], 3
    call keys_reload
    call cgbt_bindings
    mov r15, rax
    cmp qword ptr [rip + cgbt_views + 72 + VEC_cap], CG_BINDING_CAP
    jne cgbt_fail
    mov rax, [rip + cgbt_views + 72 + VEC_len]
    cmp [r15 + VEC_len], rax
    jne cgbt_fail
    shl rax, 4
    mov rdi, [r15]
    mov rsi, [rip + cgbt_views + 72]
    mov rdx, rax
    call memeq
    test eax, eax
    jz cgbt_fail
    mov rdi, [r15]
    call mem_free
    mov qword ptr [r15], 0
    mov qword ptr [r15 + VEC_len], 0
    mov qword ptr [r15 + VEC_cap], 0
    # Detach the borrowed views before exercising real runtime registration allocation/formatting.
    lea rdi, [rip + g_ext_cmds]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    lea rdi, [rip + g_ext_owner]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    lea rdi, [rip + g_keylines]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    lea rax, [rip + cgbt_title]
    mov [rip + cgbt_exts + 17 * EXT_SIZE + EXT_title], rax
    lea rdi, [rip + cgbt_exts + 17 * EXT_SIZE]
    lea rsi, [rip + cgbt_dynamic]
    mov edx, 7
    lea rcx, [rip + cgbt_runtimekeys]
    mov r8d, 10
    lea r9, [rip + cgbt_rawtitle]
    call ext_cmd_register
    test rax, rax
    jnz cgbt_fail
    mov r15, [rip + g_ext_cmds]
    mov rax, [rbx + CG_commands]
    mov rdi, [r15 + CMD_title]
    mov rsi, [rax + 5 * CMD_SIZE + CMD_title]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rdi, r14
    mov esi, 3
    call ext_runtime_get
    mov rdi, rax
    mov r15, rax
    lea rsi, [rip + cgbt_rawtitle]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rax, [rbx + CG_commands]
    cmp [rax + 5 * CMD_SIZE + CMD_title], r15
    je cgbt_fail
    mov r15, [rip + g_ext_cmds]
    mov rdi, [r15 + CMD_name]
    call mem_free
    mov rdi, [r15 + CMD_title]
    call mem_free
    mov rdi, [r15 + CMD_keys]
    call mem_free
    lea rdi, [rip + g_ext_cmds]
    call vec_free
    lea rdi, [rip + g_ext_owner]
    call vec_free
    call cgbt_ext_tmp
    mov rdi, rax
    call sb_free
    call cgbt_bindings
    mov rdi, rax
    call vec_free
    # Pure getters and ready-step reject actual changed context; invalid full-width budgets do not mutate.
    mov qword ptr [rip + cgbt_stage], 4
    lea rdi, [rip + cgbt_saved]
    mov rsi, rbx
    mov edx, CG_SIZE
    call memcpy
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov rdx, 0x100000001
    call command_generation_step
    cmp rax, -22
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_saved]
    mov edx, CG_SIZE
    call memeq
    test eax, eax
    jz cgbt_fail
    inc qword ptr [rip + cgbt_context + 8]
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    call command_generation_check
    cmp rax, -116
    jne cgbt_fail
    cmp qword ptr [rbx + PO_error], 0
    jne cgbt_fail
    dec qword ptr [rip + cgbt_context + 8]
    mov rdi, rbx
    call command_generation_retain
    test rax, rax
    jnz cgbt_fail
    mov rdi, rbx
    call command_generation_release_deferred
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    call cgbt_adversarial
    call cgbt_routing_collisions
    call cgbt_terminal_freshness
    call cgbt_long_work
    call cgbt_limits
    call cgbt_build_limits
    call cgbt_retire_faults
    lea rdi, [rip + cgbt_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + cgbt_ok]
    call write_all
    xor edi, edi
    call sys_exit
    ud2
# Only real allocator admission is faulted, after construction/input capture has completed.
FN cgbt_alloc
    inc qword ptr [rip + cgbt_all_alloc_calls]
    cmp qword ptr [rip + cgbt_alloc_fault], 0
    je cgbt_real_alloc
    inc qword ptr [rip + cgbt_alloc_calls]
    mov rax, [rip + cgbt_alloc_calls]
    cmp rax, [rip + cgbt_alloc_fault]
    jne cgbt_real_alloc
    xor eax, eax
    ret
# runtime key -> CG,borrowed EP,borrowed RO. Actual factories, caller supplier refs relinquished.
cgbt_small:
    PROLOGUE
    mov r15, rdi
    call cgbt_new
    mov rbx, rax
    lea rdi, [rip + cgbt_one]
    lea rsi, [rip + cgbt_tool]
    xor edx, edx
    call cgbt_ep
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_runval]
    call cgbt_command
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    lea rax, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov [rip + cgbt_roc + ROC_target], rax
    mov qword ptr [rip + cgbt_roc + ROC_session], 7
    lea rax, [rip + cgbt_one]
    mov [rip + cgbt_roc + ROC_owner], rax
    lea rax, [rip + cgbt_tool]
    mov [rip + cgbt_roc + ROC_name], rax
    mov [rip + cgbt_roc + ROC_key], r15
    lea rax, [rip + cgbt_rawtitle]
    mov [rip + cgbt_roc + ROC_title], rax
    lea rax, [rip + cgbt_runtimekeys]
    mov [rip + cgbt_roc + ROC_keys], rax
    mov qword ptr [rip + cgbt_roc + ROC_keyslen], 10
    lea rdi, [rip + cgbt_roc]
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rax, rbx
    mov rdx, r12
    mov rcx, r13
    EPILOGUE
cgbt_adversarial:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 5
    mov r12d, 1
.Lcgbta_fault:
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov [rip + cgbt_alloc_fault], r12
    mov qword ptr [rip + cgbt_alloc_calls], 0
    mov rdi, rbx
    call cgbt_build
    cmp rax, -12
    jne cgbt_fail
    mov qword ptr [rip + cgbt_alloc_fault], 0
    cmp [rip + cgbt_alloc_calls], r12
    jne cgbt_fail
    cmp qword ptr [rbx + PO_ready], 0
    jne cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 16
    call command_generation_step
    cmp rax, -12
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    inc r12
    cmp r12, 9
    jbe .Lcgbta_fault
    mov qword ptr [rip + cgbt_stage], 6
    # A runtime wire colliding with an own manifest is rejected after bounded exact equality.
    lea rdi, [rip + cgbt_run]
    call cgbt_small
    mov rbx, rax
    mov r12, rdx
    mov r13, rcx
    mov rdi, rbx
    call cgbt_build
    cmp rax, -17
    jne cgbt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgbt_fail
    cmp qword ptr [r13 + RO_live], 1
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    mov qword ptr [rip + cgbt_stage], 7
    # A real pending string scan is poisoned. Changed actual context must fail before following it.
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov rdi, rbx
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
    mov r12d, 128
1:  mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 1
    call command_generation_step
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rbx + CG_phase], 10
    je 2f
    dec r12
    jnz 1b
    jmp cgbt_fail
2:  mov r13, [rbx + CG_source]
    mov qword ptr [rbx + CG_source], 1
    inc qword ptr [rip + cgbt_context]
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 16
    call command_generation_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    dec qword ptr [rip + cgbt_context]
    mov [rbx + CG_source], r13
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE

# Test-only lookup of a final KB, using the existing native combination parser.
cgbt_find_binding:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rsi, rax
    mov rdi, r12
    call parse_combo
    mov r12d, eax
    mov r13d, edx
    xor ecx, ecx
1:  cmp rcx, [rbx + CG_bindings + VEC_len]
    jae 3f
    mov rax, rcx
    shl rax, 4
    add rax, [rbx + CG_bindings]
    inc rcx
    cmp [rax + KB_mods], r13d
    jne 1b
    cmp [rax + KB_key], r12d
    jne 1b
    mov rax, [rax + KB_cmd]
    EPILOGUE
3:  xor eax, eax
    EPILOGUE
cgbt_routing_collisions:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 8
    call cgbt_new
    mov rbx, rax
    xor r14d, r14d
1:  imul rax, r14, EXT_SIZE
    lea rdx, [rip + cgbt_exts]
    add rax, rdx
    mov dword ptr [rax + EXT_status], ES_REMOVED
    inc r14
    cmp r14, 128
    jb 1b
    xor r14d, r14d
.Lcgbtc_add:
    mov r12, r14
    imul r12, r12, 40
    lea rax, [rip + cgbt_route_sources]
    add r12, rax
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    xor edx, edx
    call cgbt_ep
    mov r13, rax
    mov rdi, r13
    mov rsi, [r12 + 16]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov qword ptr [r13 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r13
    imul rdx, [r12 + 32], EXT_SIZE
    lea rax, [rip + cgbt_exts]
    add rdx, rax
    mov rcx, [r12 + 32]
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    imul rax, [r12 + 32], EXT_SIZE
    lea rdx, [rip + cgbt_exts]
    add rax, rdx
    mov rdx, [r13 + EP_ext + EXT_owner]
    mov [rax + EXT_owner], rdx
    mov rdx, [r13 + EP_ext + EXT_name]
    mov [rax + EXT_name], rdx
    mov dword ptr [rax + EXT_status], ES_STOPPED
    mov rdi, r13
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    inc r14
    cmp r14, 5
    jb .Lcgbtc_add
    xor r14d, r14d
.Lcgbtc_lines:
    mov r12, r14
    imul r12, r12, 24
    lea rax, [rip + cgbt_route_queries]
    add r12, rax
    mov rdi, rbx
    mov rsi, [r12]
    mov rdx, [r12 + 8]
    call cgbt_line
    inc r14
    cmp r14, 8
    jb .Lcgbtc_lines
    mov rdi, rbx
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    lea rax, [rip + cgbt_exts]
    mov [rip + g_exts], rax
    mov qword ptr [rip + g_exts + VEC_len], 128
    mov rax, [rbx + CG_commands]
    mov [rip + g_ext_cmds], rax
    mov qword ptr [rip + g_ext_cmds + VEC_len], 5
    mov rax, [rbx + CG_owners]
    mov [rip + g_ext_owner], rax
    mov qword ptr [rip + g_ext_owner + VEC_len], 5
    xor r14d, r14d
.Lcgbtc_query:
    mov r12, r14
    imul r12, r12, 24
    lea rax, [rip + cgbt_route_queries]
    add r12, rax
    mov rdi, [r12 + 8]
    call strlen
    mov rsi, rax
    mov rdi, [r12 + 8]
    call cmd_find
    test rax, rax
    jnz 1f
    call keys_none_command
1:  mov r15, rax
    mov rax, [r12 + 16]
    cmp rax, -1
    je 2f
    shl rax, 5
    add rax, [rbx + CG_commands]
    jmp 3f
2:  call keys_none_command
3:  cmp rax, r15
    jne cgbt_fail
    mov rdi, rbx
    mov rsi, [r12]
    call cgbt_find_binding
    cmp rax, r15
    jne cgbt_fail
    inc r14
    cmp r14, 8
    jb .Lcgbtc_query
    # Equal qualified flattened wires retain DIFFERENT exact name/local-key authority.
    mov r12, [rbx + CG_authority]
    mov rdi, [r12 + 2 * 64 + 32]
    lea rsi, [rip + cgbt_ab]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rdi, [r12 + 2 * 64 + 40]
    lea rsi, [rip + cgbt_c]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rdi, [r12 + 3 * 64 + 32]
    lea rsi, [rip + cgbt_a]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rdi, [r12 + 3 * 64 + 40]
    lea rsi, [rip + cgbt_bc]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
.ifdef CGBT_COLLISIONS
    cmp qword ptr [rip + cgbt_forced_hash_calls], 0
    je cgbt_fail
    cmp qword ptr [rip + cgbt_forced_binding_calls], 0
    je cgbt_fail
    mov rax, [rbx + CG_bindingmap]
    cmp qword ptr [rax + 8], 0
    je cgbt_fail
    cmp qword ptr [rax + (CG_BINDING_MAP_CAP - 1) * 16 + 8], 0
    je cgbt_fail
    mov rax, [rbx + CG_qualified]
    cmp qword ptr [rax + 8], 0
    je cgbt_fail
    cmp qword ptr [rax + 24 + 8], 0
    je cgbt_fail
.endif
    # Borrowed final views are detached without freeing CG-owned arrays.
    lea rdi, [rip + g_ext_cmds]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    lea rdi, [rip + g_ext_owner]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE

# Every actual epoch is checked on pending and ready steps; ready/error never read supplier bytes.
cgbt_terminal_freshness:
    PROLOGUE 128
    mov qword ptr [rip + cgbt_stage], 9
    xor r14d, r14d
.Lcgbtf_epoch:
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov rdi, rbx
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov rax, [rbx + CG_commands]
    mov rdi, [rax + CMD_SIZE + CMD_title]
    lea rsi, [rip + cgbt_fallback_title]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    lea r15, [rip + cgbt_context]
    mov r12, [rbx + CG_commands]
    mov r13, [rbx + CG_source]
    mov rax, [rbx + CG_runtimes]
    mov [rsp + 0], rax
    mov qword ptr [rbx + CG_runtimes], 1
    mov rax, [rbx + CG_slots + CS_ep]
    mov [rsp + 8], rax
    mov qword ptr [rbx + CG_slots + CS_ep], 1
    mov rax, [rbx + CG_slots + CS_owner]
    mov [rsp + 16], rax
    mov qword ptr [rbx + CG_slots + CS_owner], 1
    mov rax, [rbx + CG_slots + CS_name]
    mov [rsp + 24], rax
    mov qword ptr [rbx + CG_slots + CS_name], 1
    mov rax, [rbx + CG_authority]
    mov [rsp + 32], rax
    mov qword ptr [rbx + CG_authority], 1
    mov rax, [rbx + CG_bindings]
    mov [rsp + 40], rax
    mov qword ptr [rbx + CG_bindings], 1
    mov rax, [rbx + CG_metadata]
    mov [rsp + 48], rax
    mov qword ptr [rbx + CG_metadata], 1
    mov rax, [rbx + CG_owners]
    mov [rsp + 56], rax
    mov qword ptr [rbx + CG_owners], 1
    mov rax, [rbx + CG_qualified]
    mov [rsp + 64], rax
    mov qword ptr [rbx + CG_qualified], 1
    mov rax, [rbx + CG_owned]
    mov [rsp + 72], rax
    mov qword ptr [rbx + CG_owned], 1
    mov rax, [rbx + CG_wordsource]
    mov [rsp + 80], rax
    mov qword ptr [rbx + CG_wordsource], 1
    mov rax, [rbx + CG_label]
    mov [rsp + 88], rax
    mov qword ptr [rbx + CG_label], 1
    mov rax, [rbx + CG_kc + KC_ptr]
    mov [rsp + 96], rax
    mov qword ptr [rbx + CG_kc + KC_ptr], 1
    mov rax, [rbx + CG_bindingmap]
    mov [rsp + 104], rax
    mov qword ptr [rbx + CG_bindingmap], 1
    mov qword ptr [rbx + CG_commands], 1
    mov qword ptr [rbx + CG_source], 1
    mov rdi, rbx
    mov rsi, r15
    mov edx, 16
    call command_generation_step
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov rdi, rbx
    mov rsi, r15
    mov edx, 1
    call command_generation_step
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov [rbx + CG_commands], r12
    mov [rbx + CG_source], r13
    mov rax, [rsp + 0]
    mov [rbx + CG_runtimes], rax
    mov rax, [rsp + 8]
    mov [rbx + CG_slots + CS_ep], rax
    mov rax, [rsp + 16]
    mov [rbx + CG_slots + CS_owner], rax
    mov rax, [rsp + 24]
    mov [rbx + CG_slots + CS_name], rax
    mov rax, [rsp + 32]
    mov [rbx + CG_authority], rax
    mov rax, [rsp + 40]
    mov [rbx + CG_bindings], rax
    mov rax, [rsp + 48]
    mov [rbx + CG_metadata], rax
    mov rax, [rsp + 56]
    mov [rbx + CG_owners], rax
    mov rax, [rsp + 64]
    mov [rbx + CG_qualified], rax
    mov rax, [rsp + 72]
    mov [rbx + CG_owned], rax
    mov rax, [rsp + 80]
    mov [rbx + CG_wordsource], rax
    mov rax, [rsp + 88]
    mov [rbx + CG_label], rax
    mov rax, [rsp + 96]
    mov [rbx + CG_kc + KC_ptr], rax
    mov rax, [rsp + 104]
    mov [rbx + CG_bindingmap], rax
    inc qword ptr [r15 + r14*8]
    mov rdi, rbx
    mov rsi, r15
    call command_generation_check
    cmp rax, -116
    jne cgbt_fail
    cmp qword ptr [rbx + PO_error], 0
    jne cgbt_fail
    mov r12, [rbx + CG_commands]
    mov qword ptr [rbx + CG_commands], 1
    mov qword ptr [rbx + CG_source], 1
    mov rdi, rbx
    mov rsi, r15
    mov edx, 16
    call command_generation_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    dec qword ptr [r15 + r14*8]
    # A repeated error call with original valid epochs remains independent of poisoned sources.
    mov rdi, rbx
    mov rsi, r15
    mov edx, 1
    call command_generation_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov [rbx + CG_commands], r12
    mov rdi, rbx
    call cgbt_abort
    # Pending source admission refuses each changed epoch before any allocation/work.
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov rdi, rbx
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
    inc qword ptr [r15 + r14*8]
    mov rdi, rbx
    mov rsi, r15
    mov edx, 16
    call command_generation_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    dec qword ptr [r15 + r14*8]
    mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 3
    jb .Lcgbtf_epoch
    mov qword ptr [rip + cgbt_stage], 10
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov qword ptr [rip + cgbt_finish_stale], 1
    mov rdi, rbx
    call cgbt_build
    cmp rax, -116
    jne cgbt_fail
    cmp qword ptr [rbx + PO_ready], 0
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_finish_stale], 0
    jne cgbt_fail
    dec qword ptr [rip + cgbt_context]
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE

# Each counted phase below is executed with actual workbudget1, never only reported accounting.
cgbt_one_builder:
    PROLOGUE 32
    mov rbx, rdi
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
    mov r14d, 200000
.Lcgbto_loop:
    mov r12, [rbx + CG_phase]
    mov rax, [rbx + CG_scanfield]
    mov [rsp + 8], rax
    mov r13, [rbx + CG_scanoffset]
    cmp r12, 16
    jne 1f
    mov r13, [rbx + CG_hashoffset]
1:  cmp r12, 13
    je 2f
    cmp r12, 14
    jne 3f
2:  mov r13, [rbx + CG_titleoffset]
3:  cmp r12, 20
    je 4f
    cmp r12, 34
    jne 5f
4:  mov r13, [rbx + CG_compareoffset]
5:  cmp r12, 23
    jne 6f
    mov r13, [rbx + CG_wordcursor]
6:  cmp r12, 24
    jne 7f
    mov r13, [rbx + CG_kc + KC_cursor]
7:  mov r15, [rip + cgbt_all_alloc_calls]
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 1
    cmp r12, 8
    jbe 8f
    cmp r12, 12
    jne 9f
8:  mov edx, 16
9:  call command_generation_step
    mov [rsp], rax
    cmp rdx, 1
    jne cgbt_fail
    mov rcx, [rip + cgbt_all_alloc_calls]
    sub rcx, r15
    cmp rcx, 1
    ja cgbt_fail
    cmp r12, 12
    jne 10f
    cmp rcx, 1
    jne cgbt_fail
10: cmp [rbx + CG_phase], r12
    jne .Lcgbto_next
    cmp r12, 10
    jne 19f
    mov rax, [rbx + CG_scanfield]
    cmp [rsp + 8], rax
    jne .Lcgbto_next
19: mov r15, [rbx + CG_scanoffset]
    mov r8d, 4096
    xor r9d, r9d
    cmp r12, 10
    jne 11f
    mov r9d, 1
11: cmp r12, 16
    jne 12f
    mov r15, [rbx + CG_hashoffset]
    mov r9d, 2
12: cmp r12, 13
    je 13f
    cmp r12, 14
    jne 14f
13: mov r15, [rbx + CG_titleoffset]
    mov r9d, 8
    cmp r12, 13
    je 14f
    mov r9d, 16
14: cmp r12, 20
    je 15f
    cmp r12, 34
    jne 16f
15: mov r15, [rbx + CG_compareoffset]
    mov r8d, 2048
    mov r9d, 4
    cmp r12, 20
    je 16f
    mov r9d, 128
16: cmp r12, 23
    jne 17f
    mov r15, [rbx + CG_wordcursor]
    mov r9d, 32
17: cmp r12, 24
    jne 18f
    mov r15, [rbx + CG_kc + KC_cursor]
    mov r9d, 64
18: test r9, r9
    jz .Lcgbto_next
    sub r15, r13
    cmp r15, r8
    ja cgbt_fail
    test r15, r15
    jz .Lcgbto_next
    or [rip + cgbt_long_seen], r9
.Lcgbto_next:
    mov rax, [rsp]
    test rax, rax
    jle .Lcgbto_return
    cmp rax, 1
    jne cgbt_fail
    dec r14
    jnz .Lcgbto_loop
    jmp cgbt_fail
.Lcgbto_return:
    EPILOGUE
cgbt_long_work:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 11
    lea rdi, [rip + cgbt_long_a]
    mov esi, 'a'
    mov edx, 8192
    call memset
    lea rdi, [rip + cgbt_long_b]
    mov esi, 'a'
    mov edx, 8192
    call memset
    mov byte ptr [rip + cgbt_long_b + 8191], 'b'
    lea rdi, [rip + cgbt_long_label]
    mov esi, 'L'
    mov edx, 8192
    call memset
    lea rdi, [rip + cgbt_long_title]
    mov esi, 'R'
    mov edx, 8192
    call memset
    # A long whitespace run and long invalid key word, followed by a valid default.
    lea rdi, [rip + cgbt_long_value]
    lea rsi, [rip + cgbt_long_prefix]
    mov edx, 18
    call memcpy
    lea rdi, [rip + cgbt_long_value + 18]
    mov esi, ' '
    mov edx, 8192
    call memset
    lea rdi, [rip + cgbt_long_value + 8210]
    lea rsi, [rip + cgbt_ctrl]
    mov edx, 5
    call memcpy
    lea rdi, [rip + cgbt_long_value + 8215]
    mov esi, 'a'
    mov edx, 8192
    call memset
    lea rdi, [rip + cgbt_long_value + 16407]
    lea rsi, [rip + cgbt_long_tail]
    mov edx, 12
    call memcpy
    call cgbt_new
    mov rbx, rax
    lea rdi, [rip + cgbt_one]
    lea rsi, [rip + cgbt_long_name]
    xor edx, edx
    call cgbt_ep
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + cgbt_long_label]
    mov edx, 8192
    call prep_owned_dup
    test rax, rax
    jz cgbt_fail
    mov [r12 + EP_ext + EXT_title], rax
    mov rdi, r12
    lea rsi, [rip + cgbt_long_a]
    lea rdx, [rip + cgbt_long_value]
    call cgbt_command
    mov rdi, r12
    lea rsi, [rip + cgbt_long_b]
    lea rdx, [rip + cgbt_long_value]
    call cgbt_command
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    lea rax, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov [rip + cgbt_roc + ROC_target], rax
    lea rax, [rip + cgbt_long_name]
    mov [rip + cgbt_roc + ROC_name], rax
    lea rax, [rip + cgbt_dynamic]
    mov [rip + cgbt_roc + ROC_key], rax
    lea rax, [rip + cgbt_long_title]
    mov [rip + cgbt_roc + ROC_title], rax
    lea rdi, [rip + cgbt_roc]
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    lea rdi, [rip + cgbt_long_query]
    lea rsi, [rip + cgbt_long_qualified]
    mov edx, 9
    call memcpy
    lea rdi, [rip + cgbt_long_query + 9]
    lea rsi, [rip + cgbt_long_b]
    mov edx, 8193
    call memcpy
    mov rdi, rbx
    lea rsi, [rip + cgbt_long_combo]
    lea rdx, [rip + cgbt_long_query]
    call cgbt_line
    # Caller source buffers may disappear; only owned EP/RO/keyline bytes remain authoritative.
    mov byte ptr [rip + cgbt_long_label], '!'
    mov byte ptr [rip + cgbt_long_title], '!'
    mov byte ptr [rip + cgbt_long_query], '!'
    mov qword ptr [rip + cgbt_long_seen], 0
    mov rdi, rbx
    call cgbt_one_builder
    test rax, rax
    jnz cgbt_fail
    mov rax, [rip + cgbt_long_seen]
    and eax, 251
    cmp eax, 251
    jne cgbt_fail
.ifdef CGBT_COLLISIONS
    test qword ptr [rip + cgbt_long_seen], 4
    jz cgbt_fail
.endif
    mov rdi, rbx
    lea rsi, [rip + cgbt_long_combo]
    call cgbt_find_binding
    mov rdx, [rbx + CG_commands]
    add rdx, CMD_SIZE
    cmp rax, rdx
    jne cgbt_fail
    mov rax, [rbx + CG_commands]
    mov r12, [rax + 2 * CMD_SIZE + CMD_title]
    mov rdi, r12
    call strlen
    cmp rax, 16387
    jne cgbt_fail
    cmp byte ptr [r12], 'R'
    jne cgbt_fail
    cmp byte ptr [r12 + 8191], 'R'
    jne cgbt_fail
    cmp byte ptr [r12 + 8192], ' '
    jne cgbt_fail
    cmp byte ptr [r12 + 8193], '('
    jne cgbt_fail
    cmp byte ptr [r12 + 8194], 'L'
    jne cgbt_fail
    cmp byte ptr [r12 + 16385], 'L'
    jne cgbt_fail
    cmp byte ptr [r12 + 16386], ')'
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE

# Golden six-row source metadata is verified independently of final CMDs used by keys_reload.
cgbt_check_metadata:
    PROLOGUE
    mov rbx, rdi
    xor r15d, r15d
.Lcgbtm_row:
    mov r13, r15
    shl r13, 6
    add r13, [rbx + CG_metadata]
    xor r14d, r14d
    cmp r15, 3
    jb 1f
    cmp r15, 5
    jae 1f
    mov r14d, 1
1:  cmp [r13 + CM_slot], r14
    jne cgbt_fail
    cmp r15, 5
    je .Lcgbtm_runtime
    imul r12, r14, CS_SIZE
    mov r12, [rbx + r12 + CG_slots + CS_ep]
    mov rax, r15
    cmp r14, 0
    je 2f
    sub rax, 3
2:  imul rax, rax, PC_SIZE
    mov r12, [r12 + EP_commands]
    add r12, rax
    mov rdi, [r12 + CMD_name]
    call strlen
    cmp [r13 + CM_wirelen], rax
    jne cgbt_fail
    mov rdi, [r12 + PC_key]
    call strlen
    cmp [r13 + CM_keylen], rax
    jne cgbt_fail
    mov rdi, [r12 + CMD_keys]
    call strlen
    cmp [r13 + CM_keyslen], rax
    jne cgbt_fail
    jmp .Lcgbtm_next
.Lcgbtm_runtime:
    mov r14, [rbx + CG_runtimes]
    mov r12, [rbx + CG_commands]
    add r12, 5 * CMD_SIZE
    lea rax, [rip + ext_cmd_run]
    cmp [r12 + CMD_fn], rax
    jne cgbt_fail
    mov rdi, r14
    mov esi, 5
    call ext_runtime_get
    cmp [r12 + CMD_name], rax
    jne cgbt_fail
    mov rdi, rax
    call strlen
    cmp [r13 + CM_wirelen], rax
    jne cgbt_fail
    mov rdi, r14
    mov esi, 4
    call ext_runtime_get
    cmp [r12 + CMD_keys], rax
    jne cgbt_fail
    mov rdi, rax
    call strlen
    cmp [r13 + CM_keyslen], rax
    jne cgbt_fail
    mov rdi, r14
    mov esi, 2
    call ext_runtime_get
    mov rdx, [rbx + CG_authority]
    cmp [rdx + 5 * 64 + 40], rax
    jne cgbt_fail
    mov rdi, rax
    call strlen
    cmp [r13 + CM_keylen], rax
    jne cgbt_fail
.Lcgbtm_next:
    inc r15
    cmp r15, 6
    jb .Lcgbtm_row
    EPILOGUE

.section .rodata
cgbt_path: .asciz "/fixture"
cgbt_one: .asciz "one"
cgbt_two: .asciz "two"
cgbt_three: .asciz "three"
cgbt_tool: .asciz "tool"
cgbt_other: .asciz "other"
cgbt_title: .asciz "Tool A"
cgbt_run: .asciz "run"
cgbt_runval: .asciz "Run | ctrl+alt+a ctrl+s a ctrl+alt+n ctrl+p"
cgbt_dupval: .asciz "Second | ctrl+alt+b"
cgbt_pathkey: .asciz "q/r.s"
cgbt_pathval: .asciz "Path | ctrl+alt+c"
cgbt_otherval: .asciz "Other | ctrl+alt+a ctrl+alt+d ctrl+alt+n"
cgbt_dynamic: .asciz "dynamic"
cgbt_rawtitle: .asciz "Dynamic"
cgbt_runtimekeys: .asciz "ctrl+alt+e"
cgbt_formatted: .asciz "Dynamic (Tool A)"
cgbt_ok: .asciz "ok bounded command rows, exact routing and legacy binding oracle\n"
cgbt_combo0: .asciz "ctrl+alt+f"
cgbt_cmd0: .asciz "one/tool.run"
cgbt_combo1: .asciz "ctrl+alt+g"
cgbt_cmd1: .asciz "tool.q/r.s"
cgbt_combo2: .asciz "ctrl+alt+h"
cgbt_cmd2: .asciz "one/tool.q/r.s"
cgbt_combo3: .asciz "ctrl+alt+i"
cgbt_cmd3: .asciz "other.run"
cgbt_combo4: .asciz "ctrl+alt+j"
cgbt_cmd4: .asciz "tool.run"
cgbt_combo5: .asciz "ctrl+alt+k"
cgbt_cmd5: .asciz "one/tool.dynamic"
cgbt_combo6: .asciz "ctrl+s"
cgbt_cmd6: .asciz "other.run"
cgbt_combo7: .asciz "ctrl+alt+a"
cgbt_cmd7: .asciz "save"
cgbt_combo8: .asciz "ctrl+alt+l"
cgbt_cmd8: .asciz "missing"
cgbt_combo9: .asciz "ctrl+alt+m"
cgbt_cmd9: .asciz ""
cgbt_combo10: .asciz "ctrl+alt+m"
cgbt_cmd10: .asciz "one/tool.q/r.s"

.p2align 3
cgbt_emptycombo: .asciz "ctrl+alt+o"

.p2align 3
cgbt_lines:
    .quad cgbt_combo0,10,cgbt_cmd0,12
    .quad cgbt_combo1,10,cgbt_cmd1,10
    .quad cgbt_combo2,10,cgbt_cmd2,14
    .quad cgbt_combo3,10,cgbt_cmd3,9
    .quad cgbt_combo4,10,cgbt_cmd4,8
    .quad cgbt_combo5,10,cgbt_cmd5,16
    .quad cgbt_combo6,6,cgbt_cmd6,9
    .quad cgbt_combo7,10,cgbt_cmd7,4
    .quad cgbt_combo8,10,cgbt_cmd8,7
    .quad cgbt_combo9,10,cgbt_cmd9,0
    .quad cgbt_combo10,10,cgbt_cmd10,14
    .quad cgbt_emptycombo,10,cgbt_cmd9,0

cgbt_ab: .asciz "a.b"
cgbt_a: .asciz "a"
cgbt_bc: .asciz "b.c"
cgbt_c: .asciz "c"
cgbt_dotted: .asciz "dotted.name"
.p2align 3
cgbt_route_sources:
    .quad cgbt_one,cgbt_tool,cgbt_run,0,17
    .quad cgbt_two,cgbt_tool,cgbt_run,0,94
    .quad cgbt_one,cgbt_ab,cgbt_c,0,3
    .quad cgbt_one,cgbt_a,cgbt_bc,0,7
    .quad cgbt_three,cgbt_dotted,cgbt_run,0,111
cgbt_rc0: .asciz "ctrl+alt+1"
cgbt_rq0: .asciz "one/tool.run"
cgbt_rc1: .asciz "ctrl+alt+2"
cgbt_rq1: .asciz "two/tool.run"
cgbt_rc2: .asciz "ctrl+alt+3"
cgbt_rq2: .asciz "tool.run"
cgbt_rc3: .asciz "ctrl+alt+4"
cgbt_rq3: .asciz "one/a.b.c"
cgbt_rc4: .asciz "ctrl+alt+5"
cgbt_rq4: .asciz "a.b.c"
cgbt_rc5: .asciz "ctrl+alt+6"
cgbt_rq5: .asciz "dotted.name.run"
cgbt_rc6: .asciz "ctrl+alt+7"
cgbt_rq6: .asciz "three/dotted.name.run"
cgbt_rc7: .asciz "ctrl+alt+8"
cgbt_rq7: .asciz "one/tool.missing"

.p2align 3
cgbt_route_queries:
    .quad cgbt_rc0,cgbt_rq0,0
    .quad cgbt_rc1,cgbt_rq1,1
    .quad cgbt_rc2,cgbt_rq2,-1
    .quad cgbt_rc3,cgbt_rq3,-1
    .quad cgbt_rc4,cgbt_rq4,3
    .quad cgbt_rc5,cgbt_rq5,-1
    .quad cgbt_rc6,cgbt_rq6,4
    .quad cgbt_rc7,cgbt_rq7,-1

cgbt_fallback_title: .asciz "Dynamic (tool)"

cgbt_long_name: .asciz "long"
cgbt_long_prefix: .ascii "Long | ctrl+alt+x "
cgbt_ctrl: .ascii "ctrl+"
cgbt_long_tail: .asciz " ctrl+alt+z"
cgbt_long_qualified: .ascii "one/long."
cgbt_long_combo: .asciz "ctrl+alt+y"
