# Owned evidence, exact launch borrows and independent stopped metadata lifetime.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.section .rodata
.ifdef WINDOWS
af_root: .asciz "C:/rhun"
af_dir: .asciz "C:/rhun/owner/name"
af_state: .asciz "C:/state"
af_program: .asciz "C:/Windows/System32/cmd.exe"
.else
af_root: .asciz "/rhun"
af_dir: .asciz "/rhun/owner/name"
af_state: .asciz "/state"
af_program: .asciz "/bin/sh"
.endif
af_owner: .asciz "owner"
af_name: .asciz "name"
af_runs: .asciz "git"
af_args: .asciz "--accepted"
af_other: .asciz "different"
af_bad_utf8: .byte 0xff,0
af_launch_fields: .quad EXT_dir, EXT_prog, EXT_script, EXT_runs, EXT_args
af_binding_fields: .quad EXT_owner, EXT_name, EXT_dir, EXT_prog, EXT_script, EXT_runs
af_busy_fields: .quad EXT_keeper, EXT_pid, EXT_in, EXT_out, EXT_log, EXT_host_child_in, EXT_host_child_out, EXT_host_cleanup_mask
.data
af_id: .asciz "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
af_managed_tree: .byte 0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa
af_capture: .asciz "captured"
af_source: .byte 1
.zero 31
af_tree: .zero 32
.bss
.p2align 3
af_ep: .quad 0
af_ea: .quad 0
af_old: .quad 0
af_live: .quad 0
af_charge: .quad 0
af_stage: .quad 0
af_expected: .zero EXI_SIZE
af_path: .zero 4096
af_proto: .zero KE_SIZE
af_host: .zero EXT_SIZE
af_out: .zero EAP_SIZE
af_status: .zero 32
af_words: .zero SB_SIZE
af_long: .zero 4097
.p2align 3
af_incoming: .quad 0
af_graph_owners: .zero 32
af_graph_po: .zero 4*65536
af_graph_eo: .zero 4*128
af_host_before: .zero EXT_SIZE
af_graph_count: .quad 0
af_ledger_count: .quad 0
af_ledger_desc: .zero 64*16
af_ledger_bytes: .zero 64*65536
af_running_before: .zero EXT_SIZE
af_span_targets: .zero 13*8
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + af_live], rax
    cmp qword ptr [rip + g_argc], 2
    jne .Laf_bad
    call af_setup
    mov qword ptr [rip + af_stage], 1
    lea rax, [rip + af_capture]
    mov [rip + af_proto + KE_home], rax
    call af_new
    test rax, rax
    jz .Laf_bad
    test rdx, rdx
    jnz .Laf_bad
    mov [rip + af_ea], rax
    mov rdi, [rax + PO_eo]
    cmp qword ptr [rdi + EO_refs], 1
    jne .Laf_bad
    mov rdi, rax
    lea rsi, [rip + af_out]
    call ext_activation_owner_proof
    test rax, rax
    jnz .Laf_bad
    cmp qword ptr [rip + af_out + EAP_kind], EA_LEGACY
    jne .Laf_bad
    cmp byte ptr [rip + af_out + EAP_source], 1
    jne .Laf_bad
    mov byte ptr [rip + af_source], 0
    mov rdi, [rip + af_ea]
    lea rsi, [rip + af_out]
    call ext_activation_owner_proof
    test rax, rax
    jnz .Laf_bad
    cmp byte ptr [rip + af_out + EAP_source], 1
    jne .Laf_bad
    mov byte ptr [rip + af_source], 1
    mov rdi, [rip + af_ea]
    call ext_activation_owner_plan
    test rax, rax
    jz .Laf_bad
    mov r12, rax
    mov byte ptr [rip + af_capture], 'x'
    mov rdi, [r12 + KE_home]
    cmp byte ptr [rdi], 'c'
    jne .Laf_bad
    mov byte ptr [rip + af_capture], 'c'
    mov qword ptr [rip + af_proto + KE_home], 0
    lea rdi, [rip + af_proto]
    cmp rax, rdi
    je .Laf_bad
    mov rdi, [r12 + KE_owner]
    lea rsi, [rip + af_owner]
    call strcmp_eq
    test eax, eax
    jz .Laf_bad
    mov rbx, [rip + af_ea]
    mov qword ptr [rbx + PO_refs], -1
    mov rdi, rbx
    call ext_activation_owner_retain
    cmp rax, -75
    jne .Laf_bad
    mov qword ptr [rbx + PO_refs], 1
    mov r13, [rip + g_mem_live]
    mov rdi, rbx
    call ext_activation_owner_release
    call af_consumed
    cmp [rip + g_mem_live], r13
    jne .Laf_bad
    mov rdi, rbx
    call ext_activation_owner_plan
    test rax, rax
    jnz .Laf_bad
    call af_drain
    mov rdi, [rip + af_ep]
    cmp qword ptr [rdi + PO_refs], 1
    jne .Laf_bad
    # Every post-PO wire/binding error returns an explicitly owned failed object.
    mov qword ptr [rip + af_stage], 2
    mov dword ptr [rip + af_proto + KE_needs], 128
    call af_new
    call af_failed
    mov dword ptr [rip + af_proto + KE_needs], NEEDS_PROJECT_READ
    lea rax, [rip + af_bad_utf8]
    mov [rip + af_proto + KE_home], rax
    call af_new
    call af_failed
    mov qword ptr [rip + af_proto + KE_home], 0
    lea rax, [rip + af_other]
    mov [rip + af_proto + KE_runs], rax
    call af_new
    call af_failed
    lea rax, [rip + af_runs]
    mov [rip + af_proto + KE_runs], rax
    lea rdi, [rip + af_long]
    mov esi, 'a'
    mov edx, 4096
    call memset
    lea rax, [rip + af_long]
    mov [rip + af_proto + KE_project], rax
    call af_new
    call af_failed
    mov qword ptr [rip + af_proto + KE_project], 0
    mov byte ptr [rip + af_long + 4095], 0
    lea rax, [rip + af_long]
    mov [rip + af_proto + KE_project], rax
    call af_new
    test rax, rax
    jz .Laf_bad
    test rdx, rdx
    jnz .Laf_bad
    mov rdi, rax
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    mov qword ptr [rip + af_proto + KE_project], 0
    xor r14d, r14d
1:  lea rax, [rip + af_binding_fields]
    mov r15, [rax + r14*8]
    mov rbx, [rip + af_ep]
    mov r12, [rbx + EP_ext + r15]
    lea rax, [rip + af_other]
    mov [rbx + EP_ext + r15], rax
    call af_new
    mov [rbx + EP_ext + r15], r12
    call af_failed
    inc r14
    cmp r14, 6
    jb 1b
    mov rbx, [rip + af_ep]
    mov qword ptr [rbx + PO_refs], -1
    call af_new
    test rax, rax
    jz .Laf_bad
    cmp rdx, -75
    jne .Laf_bad
    mov qword ptr [rbx + PO_refs], 1
    mov rdi, rax
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    # Preallocation evidence/type/lease/context checks preserve parent ownership.
    mov qword ptr [rip + af_stage], 3
    mov byte ptr [rip + af_tree], 1
    call af_new
    test rax, rax
    jnz .Laf_bad
    cmp rdx, -22
    jne .Laf_bad
    mov byte ptr [rip + af_tree], 0
    mov rax, [rip + af_proto + KE_lease]
    mov [rsp], rax
    mov qword ptr [rip + af_proto + KE_lease], -1
    call af_new
    test rax, rax
    jnz .Laf_bad
    cmp rdx, -22
    jne .Laf_bad
    mov rax, [rsp]
    mov [rip + af_proto + KE_lease], rax
    mov rax, [rip + af_proto + KE_context]
    mov [rsp], rax
    inc qword ptr [rip + af_proto + KE_context]
    call af_new
    test rax, rax
    jnz .Laf_bad
    cmp rdx, -116
    jne .Laf_bad
    mov rax, [rsp]
    mov [rip + af_proto + KE_context], rax
    call ext_prepare_retire_charge
    mov [rsp], rax
    mov qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    call af_new
    test rax, rax
    jnz .Laf_bad
    cmp rdx, -EV_RESOURCE
    jne .Laf_bad
    mov rax, [rsp]
    mov [rip + prep_total_charge], rax
    # Both managed keeper modes use the same owned receipt boundary.
    call af_managed_matrix
    # Host metadata owns a separate EP reference before any plan can bind.
    mov qword ptr [rip + af_stage], 4
    call af_new
    test rax, rax
    jz .Laf_bad
    test rdx, rdx
    jnz .Laf_bad
    mov [rip + af_ea], rax
    call af_host_setup
    mov rdi, [rip + af_ep]
    call ext_prepare_retain
    test rax, rax
    jnz .Laf_bad
    mov rax, [rip + af_ep]
    mov [rip + af_host + EXT_metadata_owner], rax
    mov rdi, [rip + af_ea]
    call ext_activation_owner_retain
    test rax, rax
    jnz .Laf_bad
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    cmp qword ptr [rip + af_old], 0
    jne .Laf_bad
    mov rdi, [rip + af_ea]
    call ext_activation_owner_release
    call af_consumed
    mov rdi, [rip + af_ep]
    call ext_prepare_release_deferred
    call af_consumed
    lea rdi, [rip + af_host]
    call ext_activation_host_check
    test rax, rax
    jnz .Laf_bad
    call af_output_refusals
    # A same-owner transfer needs a separately held reference, returned as old ownership.
    mov rdi, [rip + af_ea]
    call ext_activation_owner_retain
    test rax, rax
    jnz .Laf_bad
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    mov rdi, [rip + af_old]
    cmp rdi, [rip + af_ea]
    jne .Laf_bad
    mov qword ptr [rip + af_old], 0
    call ext_activation_owner_release
    call af_consumed
    # Reject every changed launch pointer, including same-identity argument changes.
    xor r14d, r14d
1:  lea rax, [rip + af_launch_fields]
    mov r15, [rax + r14*8]
    lea rbx, [rip + af_host]
    mov r12, [rbx + r15]
    lea rax, [rip + af_other]
    mov [rbx + r15], rax
    mov rdi, rbx
    call ext_activation_host_check
    cmp rax, -116
    jne .Laf_bad
    mov [rbx + r15], r12
    inc r14
    cmp r14, 5
    jb 1b
    # No descriptor/status shorthand can take ownership before real collection.
    xor r14d, r14d
2:  lea rax, [rip + af_busy_fields]
    mov r15, [rax + r14*8]
    lea rbx, [rip + af_host]
    mov r12, [rbx + r15]
    cmp r14, 0
    jne 21f
    mov qword ptr [rbx + r15], 1
    jmp 22f
21: mov dword ptr [rbx + r15], 1
22: mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    cmp rax, -16
    jne .Laf_bad
    test rdx, rdx
    jnz .Laf_bad
    cmp r14, 0
    jne 23f
    mov [rbx + r15], r12
    jmp 24f
23: mov [rbx + r15], r12d
24: inc r14
    cmp r14, 8
    jb 2b
    call af_running_matrix
    mov dword ptr [rip + af_host + EXT_status], ES_STOPPING
    mov dword ptr [rip + af_host + EXT_retiring], 1
    lea rdi, [rip + af_host]
    xor esi, esi
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    cmp rax, -16
    jne .Laf_bad
    call ext_activation_invalidate
    lea rdi, [rip + af_host]
    call ext_activation_host_check
    cmp rax, -116
    jne .Laf_bad
    # Collected detach keeps metadata, persistent required latch, and independent state.
    mov qword ptr [rip + af_stage], 5
    mov dword ptr [rip + af_host + EXT_retiring], 2
    mov dword ptr [rip + af_host + EXT_status], ES_STOPPED
    mov dword ptr [rip + af_host + EXT_stdout_eof], 1
    lea rdi, [rip + af_host]
    xor esi, esi
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    cmp qword ptr [rip + af_host + EXT_activation_owner], 0
    jne .Laf_bad
    cmp qword ptr [rip + af_host + EXT_activation_plan], 0
    jne .Laf_bad
    cmp dword ptr [rip + af_host + EXT_activation_required], 1
    jne .Laf_bad
    mov rdi, [rip + af_old]
    mov qword ptr [rip + af_old], 0
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    mov qword ptr [rip + af_stage], 51
    mov rbx, [rip + af_host + EXT_metadata_owner]
    cmp qword ptr [rbx + PO_refs], 1
    jne .Laf_bad
    mov rdi, [rip + af_host + EXT_runs]
    lea rsi, [rip + af_runs]
    call strcmp_eq
    test eax, eax
    jz .Laf_bad
    mov rdi, [rip + af_host + EXT_state]
    lea rsi, [rip + af_state]
    call strcmp_eq
    test eax, eax
    jz .Laf_bad
    mov qword ptr [rip + af_stage], 52
    # Read actual stopped-host permission metadata after EA storage has retired.
    lea rdi, [rip + af_host]
    lea rsi, [rip + af_words]
    call ext_needs_words
    mov rdx, [rip + af_words + SB_len]
    cmp rdx, 3
    jb .Laf_bad
    mov rdi, [rip + af_words + SB_ptr]
    add rdi, rdx
    sub rdi, 3
    lea rsi, [rip + af_runs]
    mov edx, 3
    call memeq
    test eax, eax
    jz .Laf_bad
    lea rdi, [rip + af_words]
    call sb_free
    mov qword ptr [rip + af_stage], 53
    call af_host_drop
    mov qword ptr [rip + af_stage], 54
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Laf_bad
    mov qword ptr [rip + af_stage], 55
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + af_live]
    jne .Laf_bad
    xor eax, eax
    EPILOGUE
.Laf_bad:
    mov rax, [rip + af_stage]
    inc rax
    EPILOGUE

af_new:
    mov rdi, [rip + af_ep]
    lea rsi, [rip + af_proto]
    mov edx, EA_LEGACY
    lea rcx, [rip + af_source]
    lea r8, [rip + af_tree]
    jmp ext_activation_owner_create

af_consumed:
    test rax, rax
    jnz .Laf_abort
    cmp rdx, 1
    jne .Laf_abort
    ret
.Laf_abort:
    mov edi, 88
    jmp sys_exit

af_failed:
    PROLOGUE
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jns .Laf_abort
    mov rbx, rax
    cmp qword ptr [rax + PO_ready], 0
    jne .Laf_abort
    mov rdi, [rax + PO_eo]
    cmp qword ptr [rdi + EO_refs], 1
    jne .Laf_abort
    mov rdi, rbx
    call ext_activation_owner_plan
    test rax, rax
    jnz .Laf_abort
    mov rdi, rbx
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    EPILOGUE

af_drain:
    PROLOGUE
    mov rbx, 4096
1:  mov edi, 1
    lea rsi, [rip + af_status]
    call ext_prepare_retire_step
    test rax, rax
    js .Laf_abort
    cmp qword ptr [rip + af_status], 1
    ja .Laf_abort
    cmp qword ptr [rip + af_status + 16], 0
    jne .Laf_abort
    cmp qword ptr [rip + af_status + 24], 0
    jne .Laf_abort
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp .Laf_abort
2:  EPILOGUE

af_setup:
    PROLOGUE
    mov rdi, -1
    lea rsi, [rip + af_dir]
    lea rdx, [rip + af_owner]
    lea rcx, [rip + af_name]
    call ext_prepare_alloc
    test rax, rax
    jz .Laf_abort
    mov rbx, rax
    mov [rip + af_ep], rax
    mov qword ptr [rax + EP_kind], 2
    mov rdi, rax
    call ext_prepare_enable_deferred
    test rax, rax
    jnz .Laf_abort
    lea rsi, [rip + af_program]
    call af_dup
    mov [rbx + EP_ext + EXT_prog], rax
    lea rsi, [rip + af_runs]
    call af_dup
    mov [rbx + EP_ext + EXT_runs], rax
    lea rsi, [rip + af_args]
    call af_dup
    mov [rbx + EP_ext + EXT_args], rax
    mov dword ptr [rbx + EP_ext + EXT_needs], NEEDS_PROJECT_READ
    mov qword ptr [rbx + PO_ready], 1
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call ext_root_open
    test rax, rax
    js .Laf_abort
    mov rdi, [rbx + PO_eo]
    mov [rdi + EO_lease], rax
    lea rdi, [rip + af_proto]
    mov [rdi + KE_lease], rax
    lea rax, [rip + af_root]
    mov [rdi + KE_root], rax
    lea rax, [rip + af_owner]
    mov [rdi + KE_owner], rax
    lea rax, [rip + af_name]
    mov [rdi + KE_name], rax
    lea rax, [rip + af_dir]
    mov [rdi + KE_payload], rax
    lea rax, [rip + af_state]
    mov [rdi + KE_state], rax
    lea rax, [rip + af_program]
    mov [rdi + KE_program], rax
    lea rax, [rip + af_runs]
    mov [rdi + KE_runs], rax
    mov dword ptr [rdi + KE_needs], NEEDS_PROJECT_READ
    mov qword ptr [rdi + KE_kind], KA_LEGACY
    call ext_activation_epoch_get
    mov [rip + af_proto + KE_context], rax
    EPILOGUE

af_dup:
    PROLOGUE
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call prep_owned_dup
    test rax, rax
    jz .Laf_abort
    EPILOGUE

af_host_setup:
    PROLOGUE
    lea rdi, [rip + af_owner]
    lea rsi, [rip + af_name]
    lea rdx, [rip + af_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    lea rdi, [rip + af_host]
    mov [rdi + EXT_identity_owner], rax
    mov rdx, [rax + HI_owner]
    mov [rdi + EXT_owner], rdx
    mov rdx, [rax + HI_name]
    mov [rdi + EXT_name], rdx
    mov rdx, [rax + HI_state]
    mov [rdi + EXT_state], rdx
    mov rsi, [rip + af_ep]
    xor ecx, ecx
1:  lea rax, [rip + af_launch_fields]
    mov rax, [rax + rcx*8]
    mov rdx, [rsi + EP_ext + rax]
    mov [rdi + rax], rdx
    inc rcx
    cmp rcx, 5
    jb 1b
    mov eax, [rsi + EP_ext + EXT_needs]
    mov [rdi + EXT_needs], eax
    mov dword ptr [rdi + EXT_in], -1
    mov dword ptr [rdi + EXT_out], -1
    mov dword ptr [rdi + EXT_log], -1
    mov dword ptr [rdi + EXT_host_child_in], -1
    mov dword ptr [rdi + EXT_host_child_out], -1
    mov dword ptr [rdi + EXT_status], ES_IDLE
    mov dword ptr [rdi + EXT_catalog_state], 1
    EPILOGUE

# Separate synthetic managed EP; preserve the legacy parent/plan for host lifetime cases.
af_managed_matrix:
    PROLOGUE 144
    mov rax, [rip + af_ep]
    mov [rsp + 128], rax
    mov rdi, rsp
    lea rsi, [rip + af_proto]
    mov edx, KE_SIZE
    call memcpy
    call af_setup
    mov rbx, [rip + af_ep]
    mov qword ptr [rbx + EP_kind], 1
    lea rdi, [rip + af_path]
    lea rsi, [rip + af_root]
    lea rdx, [rip + af_owner]
    lea rcx, [rip + af_name]
    lea r8, [rip + af_id]
    call ext_store_payload_path
    test rax, rax
    js .Laf_abort
    lea rsi, [rip + af_path]
    call af_dup
    mov [rbx + EP_ext + EXT_dir], rax
    mov [rip + af_proto + KE_payload], rax
    lea rax, [rip + af_id]
    mov [rip + af_proto + KE_id], rax
    mov qword ptr [rip + af_proto + KE_kind], KA_CANDIDATE
    call af_new_managed
    call af_managed_ok
    # Cross-kind source-only evidence cannot authorize managed activation.
    call af_new
    test rax, rax
    jnz .Laf_abort
    cmp rdx, -22
    jne .Laf_abort
    lea rdi, [rip + af_expected]
    mov esi, 7
    mov edx, EXI_ACTIVE
    lea rcx, [rip + af_id]
    xor r8d, r8d
    call ext_index_pack
    cmp eax, 1
    jne .Laf_abort
    lea rax, [rip + af_expected]
    mov [rip + af_proto + KE_expected], rax
    mov qword ptr [rip + af_proto + KE_kind], KA_SELECTED
    call af_new_managed
    call af_managed_ok
    mov dword ptr [rip + af_expected + EXI_flags], 0
    call af_new_managed
    call af_failed
    mov dword ptr [rip + af_expected + EXI_flags], EXI_ACTIVE
    mov byte ptr [rip + af_id], 'A'
    call af_new_managed
    call af_failed
    mov byte ptr [rip + af_id], 'a'
    mov rdi, [rip + af_ep]
    call ext_prepare_release_deferred
    call af_consumed
    call af_drain
    lea rdi, [rip + af_proto]
    mov rsi, rsp
    mov edx, KE_SIZE
    call memcpy
    mov rax, [rsp + 128]
    mov [rip + af_ep], rax
    EPILOGUE

af_new_managed:
    mov rdi, [rip + af_ep]
    lea rsi, [rip + af_proto]
    mov edx, EA_MANAGED
    lea rcx, [rip + af_source]
    lea r8, [rip + af_managed_tree]
    jmp ext_activation_owner_create

af_managed_ok:
    PROLOGUE
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    mov rbx, rax
    mov rdi, [rax + PO_eo]
    cmp qword ptr [rdi + EO_refs], 1
    jne .Laf_abort
    mov rdi, rbx
    lea rsi, [rip + af_out]
    call ext_activation_owner_proof
    test rax, rax
    jnz .Laf_abort
    cmp qword ptr [rip + af_out + EAP_kind], EA_MANAGED
    jne .Laf_abort
    cmp byte ptr [rip + af_out + EAP_tree], 0xaa
    jne .Laf_abort
    call af_host_setup
    mov rdi, [rip + af_ep]
    call ext_prepare_retain
    test rax, rax
    jnz .Laf_abort
    mov rax, [rip + af_ep]
    mov [rip + af_host + EXT_metadata_owner], rax
    lea rdi, [rip + af_host]
    mov rsi, rbx
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    lea rdi, [rip + af_host]
    call ext_activation_host_check
    test rax, rax
    jnz .Laf_abort
    cmp dword ptr [rip + af_host + EXT_activation_required], 1
    jne .Laf_abort
    lea rdi, [rip + af_host]
    xor esi, esi
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    mov rdi, [rip + af_old]
    mov qword ptr [rip + af_old], 0
    call ext_activation_owner_release
    call af_consumed
    call af_host_drop
    EPILOGUE

.text
# Both managed and legacy fixture hosts use actual fieldwise EP/HI transfers.
af_host_drop:
    PROLOGUE
    lea r12, [rip + af_host]
    mov r13, [r12 + EXT_metadata_owner]
    mov qword ptr [rip + g_ext_prepared_catalog_active], 1
    mov rdi, r12
    call ext_slot_hide_pure
    mov rdi, r12
    lea rsi, [rip + af_old]
    call ext_slot_metadata_take
    call af_consumed
    cmp [rip + af_old], r13
    jne .Laf_abort
    mov rdi, [rip + af_old]
    mov qword ptr [rip + af_old], 0
    call ext_prepare_release_deferred
    call af_consumed
    mov rdi, r12
    lea rsi, [rip + af_old]
    call ext_host_identity_take
    call af_consumed
    mov rdi, [rip + af_old]
    mov qword ptr [rip + af_old], 0
    call ext_host_identity_release
    call af_consumed
    call af_drain
    EPILOGUE

.text
# Snapshot every byte of both distinct EA allocation graphs plus the retained EP.
af_output_refusals:
    PROLOGUE
    mov qword ptr [rip + af_graph_count], 3
    call af_new
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    mov [rip + af_incoming], rax
    mov [rip + af_graph_owners + 8], rax
    mov rax, [rip + af_ea]
    mov [rip + af_graph_owners], rax
    mov rax, [rip + af_ep]
    mov [rip + af_graph_owners + 16], rax
    lea rdi, [rip + af_host_before]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memcpy
    xor r12d, r12d
.Lafs_snapshot:
    lea rax, [rip + af_graph_owners]
    mov rbx, [rax + r12*8]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    cmp rdx, 65536
    ja .Laf_abort
    lea rdi, [rip + af_graph_po]
    mov rax, r12
    shl rax, 16
    add rdi, rax
    lea rsi, [rbx - RD_PO_BACK - 16]
    call memcpy
    lea rdi, [rip + af_graph_eo]
    mov rax, r12
    shl rax, 7
    add rdi, rax
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memcpy
    inc r12
    cmp r12, 3
    jb .Lafs_snapshot
    call af_graph_ledger_snapshot
    xor r12d, r12d
.Lafs_family:
    lea rax, [rip + af_graph_owners]
    mov r10, [rax + r12*8]
    lea rax, [rip + af_host + EXT_activation_owner]
    mov [rip + af_span_targets], rax
    lea rax, [rip + af_host - 4]
    mov [rip + af_span_targets + 8], rax
    lea rax, [rip + af_host + EXT_SIZE - 4]
    mov [rip + af_span_targets + 16], rax
    lea rax, [r10 + EA_plan]
    mov [rip + af_span_targets + 24], rax
    lea rax, [r10 + EA_wire]
    mov [rip + af_span_targets + 32], rax
    lea rax, [r10 - RD_PO_BACK]
    mov [rip + af_span_targets + 40], rax
    lea rax, [r10 - RD_PO_BACK - 16]
    mov [rip + af_span_targets + 48], rax
    mov rax, [r10 - AO_SIZE + AO_charge]
    lea rax, [r10 + rax - RD_PO_BACK - 24]
    mov [rip + af_span_targets + 56], rax
    mov rax, [r10 + PO_eo]
    mov [rip + af_span_targets + 64], rax
    sub rax, RD_SIZE + 16
    mov [rip + af_span_targets + 72], rax
    mov rax, [r10 + PO_eo]
    add rax, EO_SIZE - 8
    mov [rip + af_span_targets + 80], rax
    mov qword ptr [rip + af_span_targets + 88], -8
    lea rax, [rip + af_old + 1]
    mov [rip + af_span_targets + 96], rax
    xor r13d, r13d
.Lafs_target:
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_incoming]
    lea rax, [rip + af_span_targets]
    mov rdx, [rax + r13*8]
    call ext_activation_host_swap
    cmp rax, -22
    jne .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    call af_graph_unchanged
    inc r13
    cmp r13, 13
    jb .Lafs_target
    inc r12
    cmp r12, 2
    jb .Lafs_family
    mov qword ptr [rip + af_old], 1
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_incoming]
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    cmp rax, -22
    jne .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    cmp qword ptr [rip + af_old], 1
    jne .Laf_abort
    call af_graph_unchanged
    mov qword ptr [rip + af_old], 0
    # Distinct positive swap and swap-back transfer each sole preheld owner exactly.
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_incoming]
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    mov rax, [rip + af_ea]
    cmp [rip + af_old], rax
    jne .Laf_abort
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_old]
    mov qword ptr [rip + af_old], 0
    lea rdx, [rip + af_old]
    call ext_activation_host_swap
    call af_consumed
    mov rdi, [rip + af_old]
    cmp rdi, [rip + af_incoming]
    jne .Laf_abort
    mov qword ptr [rip + af_old], 0
    mov qword ptr [rip + af_incoming], 0
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    EPILOGUE

af_graph_unchanged:
    PROLOGUE
    lea rdi, [rip + af_host_before]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz .Laf_abort
    xor r14d, r14d
.Lafg_owner:
    lea rax, [rip + af_graph_owners]
    mov rbx, [rax + r14*8]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    lea rdi, [rip + af_graph_po]
    mov rax, r14
    shl rax, 16
    add rdi, rax
    lea rsi, [rbx - RD_PO_BACK - 16]
    call memeq
    test eax, eax
    jz .Laf_abort
    lea rdi, [rip + af_graph_eo]
    mov rax, r14
    shl rax, 7
    add rdi, rax
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memeq
    test eax, eax
    jz .Laf_abort
    inc r14
    cmp r14, [rip + af_graph_count]
    jb .Lafg_owner
    call af_graph_ledger_unchanged
    EPILOGUE

.text
# Preserve a genuine retained graph while changing only test-owned host state.
af_running_matrix:
    PROLOGUE
    mov qword ptr [rip + af_stage], 46
    lea rdi, [rip + af_running_before]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memcpy
    call af_new
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    mov [rip + af_incoming], rax
    mov [rip + af_graph_owners + 24], rax
    mov rax, [rip + af_ea]
    mov [rip + af_graph_owners], rax
    mov rax, [rip + af_ep]
    mov [rip + af_graph_owners + 8], rax
    mov rax, [rip + af_host + EXT_identity_owner]
    mov [rip + af_graph_owners + 16], rax
    mov qword ptr [rip + af_graph_count], 4
    mov rdi, [rip + af_ea]
    call ext_activation_owner_retain
    test rax, rax
    jnz .Laf_abort
    lea rbx, [rip + af_host]
    mov qword ptr [rbx + EXT_keeper], 123
    mov dword ptr [rbx + EXT_in], 124
    mov dword ptr [rbx + EXT_out], 125
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_startaccepted], 1
    call af_running_snapshot
    call af_running_call
    test rax, rax
    jnz .Laf_abort
    call af_graph_unchanged
    # Each field refusal preserves the complete input graph, not just refs.
    xor r12d, r12d
.Lafr_field:
    lea rax, [rip + af_running_fields]
    lea rcx, [r12 + r12*2]
    mov r13, [rax + rcx*8]
    mov r15, [rax + rcx*8 + 8]
    mov r14, [rbx + r13]
    cmp qword ptr [rax + rcx*8 + 16], 4
    jne 1f
    mov [rbx + r13], r15d
    jmp 2f
1:  cmp r13, EXT_identity_owner
    jne 11f
    mov rax, [rip + af_incoming]
    jmp 12f
11: cmp r13, EXT_metadata_owner
    jne 13f
    mov rax, [rip + af_incoming]
    jmp 12f
13: lea rax, [rip + af_other]
12: mov [rbx + r13], rax
2:  call af_running_snapshot
    call af_running_call
    cmp rax, -116
    jne .Laf_abort
    call af_graph_unchanged
    mov [rbx + r13], r14
    inc r12
    lea rax, [rip + af_running_fields]
    lea rcx, [r12 + r12*2]
    lea rax, [rax + rcx*8]
    lea rcx, [rip + af_running_fields_end]
    cmp rax, rcx
    jb .Lafr_field
    # Expected owner and keeper are exact external observations.
    call af_running_snapshot
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_incoming]
    mov edx, 123
    call ext_activation_host_running_check
    cmp rax, -116
    jne .Laf_abort
    call af_graph_unchanged
    mov r12, -1
.Lafr_keeper:
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    mov rdx, r12
    call ext_activation_host_running_check
    cmp rax, -116
    jne .Laf_abort
    call af_graph_unchanged
    inc r12
    cmp r12, 2
    jb .Lafr_keeper
    # Unrelated pending intent must stale START, while keeping this running session.
    call ext_activation_invalidate
    test rax, rax
    jz .Laf_abort
    call af_running_call
    test rax, rax
    jnz .Laf_abort
    call af_graph_unchanged
    lea rdi, [rip + af_host]
    call ext_activation_host_check
    cmp rax, -116
    jne .Laf_abort
    call af_graph_unchanged
    lea rdi, [rip + af_host]
    lea rsi, [rip + af_running_before]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, [rip + af_ea]
    call ext_activation_owner_release
    call af_consumed
    mov rdi, [rip + af_incoming]
    mov qword ptr [rip + af_incoming], 0
    call ext_activation_owner_release
    call af_consumed
    call af_drain
    EPILOGUE

af_running_call:
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    mov edx, 123
    jmp ext_activation_host_running_check

af_running_snapshot:
    PROLOGUE
    lea rdi, [rip + af_host_before]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memcpy
    xor r12d, r12d
1:  lea rax, [rip + af_graph_owners]
    mov rbx, [rax + r12*8]
    mov rdx, [rbx - AO_SIZE + AO_charge]
    cmp rdx, 65536
    ja .Laf_abort
    lea rdi, [rip + af_graph_po]
    mov rax, r12
    shl rax, 16
    add rdi, rax
    lea rsi, [rbx - RD_PO_BACK - 16]
    call memcpy
    lea rdi, [rip + af_graph_eo]
    mov rax, r12
    shl rax, 7
    add rdi, rax
    mov rsi, [rbx + PO_eo]
    sub rsi, RD_SIZE + 16
    mov edx, 128
    call memcpy
    inc r12
    cmp r12, 4
    jb 1b
    call af_graph_ledger_snapshot
    EPILOGUE
.section .rodata
.p2align 3
af_running_fields:
.quad EXT_activation_required,0,4
.quad EXT_activation_stale,1,4
.quad EXT_status,ES_STARTING,4
.quad EXT_status,ES_REMOVED,4
.quad EXT_disabled,1,4
.quad EXT_retiring,1,4
.quad EXT_startaccepted,0,4
.quad EXT_host_cleanup_mask,1,4
.quad EXT_host_cleanup_mask,256,4
.quad EXT_in,-1,4
.quad EXT_out,-1,4
.quad EXT_host_child_in,126,4
.quad EXT_host_child_out,127,4
.quad EXT_catalog_state,2,4
.quad EXT_keeper,0,8
.quad EXT_activation_owner,0,8
.quad EXT_activation_plan,0,8
.quad EXT_metadata_owner,0,8
.quad EXT_identity_owner,0,8
.quad EXT_owner,0,8
.quad EXT_name,0,8
.quad EXT_state,0,8
.quad EXT_dir,0,8
.quad EXT_prog,0,8
.quad EXT_script,0,8
.quad EXT_runs,0,8
.quad EXT_args,0,8
.quad EXT_needs,0x7fffffff,4
af_running_fields_end:

.text
# Capture every separate charged allocation, including allocator header and AO links.
# The last ledger node is the already-captured creation block, not an ordinary AO block.
af_graph_ledger_snapshot:
    PROLOGUE
    mov qword ptr [rip + af_ledger_count], 0
    xor r12d, r12d
.Lafl_owner:
    lea rax, [rip + af_graph_owners]
    mov rbx, [rax + r12*8]
    mov r13, [rbx + PO_allocs]
.Lafl_node:
    test r13, r13
    jz .Laf_abort
    lea rax, [rbx - AO_SIZE]
    cmp r13, rax
    je .Lafl_last
    mov r14, [rip + af_ledger_count]
    cmp r14, 64
    jae .Laf_abort
    mov r15, [r13 + AO_charge]
    test r15, r15
    jz .Laf_abort
    cmp r15, 65536
    ja .Laf_abort
    mov rax, r14
    shl rax, 4
    lea rcx, [rip + af_ledger_desc]
    add rcx, rax
    lea rsi, [r13 - 16]
    mov [rcx], rsi
    mov [rcx + 8], r15
    mov rax, r14
    shl rax, 16
    lea rdi, [rip + af_ledger_bytes]
    add rdi, rax
    mov rdx, r15
    call memcpy
    inc qword ptr [rip + af_ledger_count]
    mov r13, [r13 + AO_next]
    jmp .Lafl_node
.Lafl_last:
    cmp qword ptr [r13 + AO_next], 0
    jne .Laf_abort
    inc r12
    cmp r12, [rip + af_graph_count]
    jb .Lafl_owner
    EPILOGUE

af_graph_ledger_unchanged:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + af_ledger_count]
    jae 2f
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + af_ledger_desc]
    add rcx, rax
    mov rsi, [rcx]
    mov rdx, [rcx + 8]
    mov rax, r12
    shl rax, 16
    lea rdi, [rip + af_ledger_bytes]
    add rdi, rax
    call memeq
    test eax, eax
    jz .Laf_abort
    inc r12
    jmp 1b
2:  EPILOGUE
