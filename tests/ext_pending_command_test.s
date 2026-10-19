# Actual command invocation, retry tick, vector relocation and exact publisher identity.
.include "rhun.inc"
.include "app/taskproc.inc"
.bss
.p2align 3
pct_exts: .zero 2 * EXT_SIZE
pct_cmds: .zero 2 * CMD_SIZE
pct_owners: .zero 16
pct_block: .quad 0
pct_runs: .quad 0
pct_stage: .quad 0
pct_live: .quad 0
pct_doc: .quad 0
pct_tab: .zero TAB_SIZE
pct_opened: .quad 0
pct_polls: .quad 0
pct_waits: .quad 0
pct_fault: .quad 0
pct_pipes: .quad 0
pct_closes: .quad 0
pct_retries: .quad 0
pct_keeper_polls: .quad 0
pct_keeper_closes: .quad 0
.text
FN ext_pending_fixture_send
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rip + pct_stage], 8
    jne .Lpct_normal_send
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + pct_hello_wire]
    call str_eq_cstr
    test eax, eax
    jnz .Lpct_hello_run
    mov rdi, r12
    mov rsi, 9
    lea rdx, [rip + pct_open_prefix]
    mov ecx, 9
    cmp r13, 9
    jb .Lpct_other
    call str_eq
    test eax, eax
    jz .Lpct_other
    cmp qword ptr [rip + pct_block], 0
    jne .Lpct_refused
    inc qword ptr [rip + pct_opened]
.Lpct_other:
    xor eax, eax
    EPILOGUE
.Lpct_hello_run:
    cmp qword ptr [rip + pct_opened], 1
    jne pct_fail
    cmp qword ptr [rip + pct_block], 0
    jne pct_fail
    inc qword ptr [rip + pct_runs]
    xor eax, eax
    EPILOGUE
.Lpct_refused:
    mov rax, -11
    EPILOGUE
.Lpct_normal_send:
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + pct_wire]
    call str_eq_cstr
    test eax, eax
    jz pct_fail
    cmp qword ptr [rip + pct_block], 0
    jne 1f
    inc qword ptr [rip + pct_runs]
    xor eax, eax
    EPILOGUE
1:  mov rax, -11
    EPILOGUE
pct_fail:
    mov rdi, [rip + pct_stage]
    add rdi, 72
    call sys_exit
    ud2
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + pct_live], rax
    lea rbx, [rip + pct_exts]
    lea rax, [rip + pct_owner]
    mov [rbx + EXT_owner], rax
    mov [rbx + EXT_SIZE + EXT_owner], rax
    lea rax, [rip + pct_a]
    mov [rbx + EXT_name], rax
    lea rax, [rip + pct_ab]
    mov [rbx + EXT_SIZE + EXT_name], rax
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_SIZE + EXT_status], ES_IDLE
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_SIZE + EXT_in], -1
    mov dword ptr [rbx + EXT_SIZE + EXT_out], -1
    mov dword ptr [rbx + EXT_SIZE + EXT_log], -1
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 2
    mov qword ptr [rip + g_exts + VEC_cap], 2
    lea rax, [rip + pct_cmds]
    mov [rip + g_ext_cmds + VEC_ptr], rax
    mov qword ptr [rip + g_ext_cmds + VEC_len], 1
    lea rax, [rip + pct_owners]
    mov [rip + g_ext_owner + VEC_ptr], rax
    mov qword ptr [rip + g_ext_owner + VEC_len], 1
    lea rax, [rip + pct_command]
    mov [rip + pct_cmds + CMD_name], rax
    mov edi, 1
    call ext_pending_fixture_setup
    mov qword ptr [rip + pct_stage], 1
    mov qword ptr [rip + pct_block], 1
    lea rdi, [rip + pct_cmds]
    call ext_cmd_run
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    cmp qword ptr [rip + pct_runs], 0
    jne pct_fail
    call ext_timeout
    test rax, rax
    js pct_fail
    cmp rax, 16
    ja pct_fail
    # Relocate the original command behind another publisher's runtime/manifest row.
    mov qword ptr [rip + pct_stage], 2
    lea rax, [rip + pct_other]
    mov [rip + pct_cmds + CMD_name], rax
    lea rax, [rip + pct_command]
    mov [rip + pct_cmds + CMD_SIZE + CMD_name], rax
    mov qword ptr [rip + pct_owners], 1
    mov qword ptr [rip + pct_owners + 8], 0
    mov qword ptr [rip + g_ext_cmds + VEC_len], 2
    mov qword ptr [rip + g_ext_owner + VEC_len], 2
    mov edi, 2
    call ext_pending_fixture_setup
    mov qword ptr [rip + pct_block], 0
    call ext_tick
    cmp qword ptr [rip + pct_runs], 1
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    call ext_tick
    cmp qword ptr [rip + pct_runs], 1
    jne pct_fail
    # An identical public wire name belonging to o/a.b cannot receive o/a's request.
    mov qword ptr [rip + pct_stage], 3
    mov qword ptr [rip + pct_block], 1
    lea rdi, [rip + pct_cmds + CMD_SIZE]
    call ext_cmd_run
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    lea rax, [rip + pct_command]
    mov [rip + pct_cmds + CMD_name], rax
    mov qword ptr [rip + g_ext_cmds + VEC_len], 1
    mov qword ptr [rip + g_ext_owner + VEC_len], 1
    mov edi, 1
    call ext_pending_fixture_setup
    mov qword ptr [rip + pct_block], 0
    call ext_tick
    cmp qword ptr [rip + pct_runs], 1
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    # Stop a RUNNING process with owned pending input. Clear must preserve EXT argument ABI.
    mov qword ptr [rip + pct_stage], 4
    mov qword ptr [rip + pct_owners], 0
    mov qword ptr [rip + pct_block], 1
    lea rdi, [rip + pct_cmds]
    call ext_cmd_run
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    mov rdi, rbx
    call ext_stop_user
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    cmp dword ptr [rbx + EXT_status], ES_STOPPING
    jne pct_fail
    cmp dword ptr [rbx + EXT_restart], 0
    jne pct_fail
    # A synchronous legacy refusal cannot leave a command for a later manual recovery.
    mov qword ptr [rip + pct_stage], 5
    mov dword ptr [rbx + EXT_status], ES_IDLE
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov rdi, rbx
    call ext_legacy_start
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    # A stale verified activation is terminal until a separate fresh preparation.
    mov qword ptr [rip + pct_stage], 6
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov qword ptr [rbx + EXT_activation_plan], 1
    mov dword ptr [rbx + EXT_activation_stale], 1
    mov rdi, rbx
    call ext_supervised_start
    cmp dword ptr [rbx + EXT_status], ES_FAILED
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    mov qword ptr [rbx + EXT_activation_plan], 0
    # Real hello/catch-up cannot consume an owned request while opened output is refused.
    mov qword ptr [rip + pct_stage], 8
    mov dword ptr [rbx + EXT_status], ES_STARTING
    mov dword ptr [rbx + EXT_hello], 0
    mov qword ptr [rbx + EXT_active], -1
    lea rax, [rip + pct_star]
    mov [rbx + EXT_sub_opened], rax
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    call doc_new
    mov [rip + pct_doc], rax
    cmp qword ptr [rax + DOC_id], 1
    jne pct_fail
    mov [rip + pct_tab + TAB_doc], rax
    mov [rip + g_doc], rax
    mov qword ptr [rip + pct_tab + TAB_kind], TAB_DOC
    lea rax, [rip + pct_tab]
    mov [rip + g_tabs + VEC_ptr], rax
    mov qword ptr [rip + g_tabs + VEC_len], 1
    mov qword ptr [rip + g_tab_cur], 0
    mov qword ptr [rip + pct_block], 1
    lea rdi, [rbx + EXT_rbuf]
    lea rsi, [rip + pct_hello]
    call sb_push_cstr
    mov rdi, rbx
    call extproto_pump
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    cmp qword ptr [rip + pct_runs], 1
    jne pct_fail
    cmp qword ptr [rip + pct_opened], 0
    jne pct_fail
    mov qword ptr [rip + pct_block], 0
    call ext_tick
    cmp qword ptr [rip + pct_runs], 2
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    call ext_tick
    cmp qword ptr [rip + pct_runs], 2
    jne pct_fail
    mov qword ptr [rip + g_tabs + VEC_len], 0
    mov qword ptr [rip + g_tabs + VEC_ptr], 0
    mov qword ptr [rip + g_doc], 0
    mov qword ptr [rbx + EXT_sub_opened], 0
    mov rdi, [rip + pct_doc]
    call doc_free
    lea rdi, [rbx + EXT_known]
    call vec_free
    # Faults after real legacy initialization: first pipe, second pipe, and spawn.
    mov qword ptr [rip + pct_stage], 9
    mov qword ptr [rip + pct_fault], 1
.Lpct_start_fault:
    mov dword ptr [rbx + EXT_status], ES_IDLE
    mov dword ptr [rbx + EXT_manifest_ok], 1
    mov dword ptr [rbx + EXT_noconfine], 1
    lea rax, [rip + pct_state]
    mov [rbx + EXT_state], rax
    mov qword ptr [rip + pct_pipes], 0
    mov qword ptr [rip + pct_closes], 0
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov rdi, rbx
    call ext_legacy_start
    cmp dword ptr [rbx + EXT_status], ES_FAILED
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    mov rax, [rip + pct_fault]
    dec rax
    shl rax, 1
    cmp rax, [rip + pct_closes]
    jne pct_fail
    inc qword ptr [rip + pct_fault]
    cmp qword ptr [rip + pct_fault], 4
    jb .Lpct_start_fault
    # The actual confinement fallback keeps the same owned request through its restart callback.
    mov qword ptr [rip + pct_stage], 10
    mov dword ptr [rbx + EXT_status], ES_STARTING
    mov dword ptr [rbx + EXT_noconfine], 0
    mov qword ptr [rbx + EXT_reason], 0
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov rdi, rbx
    xor esi, esi
    call ext_legacy_exited
    cmp qword ptr [rip + pct_retries], 1
    jne pct_fail
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    mov rdi, rbx
    call ext_stop_user
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    # Actual keeper retirement retains authorized restart while pending, then cancels stale activation.
    mov qword ptr [rip + pct_stage], 11
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_retiring], 0
    mov dword ptr [rbx + EXT_restart], 1
    mov qword ptr [rbx + EXT_keeper], 1
    mov qword ptr [rbx + EXT_reason], 0
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov rdi, rbx
    xor esi, esi
    call ext_supervised_exited
    cmp qword ptr [rbx + EXT_pending], 0
    je pct_fail
    cmp qword ptr [rbx + EXT_keeper], 1
    jne pct_fail
    cmp qword ptr [rip + pct_keeper_closes], 0
    jne pct_fail
    mov rdi, rbx
    xor esi, esi
    call ext_supervised_exited
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    cmp qword ptr [rbx + EXT_keeper], 0
    jne pct_fail
    cmp qword ptr [rip + pct_keeper_closes], 1
    jne pct_fail
    cmp dword ptr [rbx + EXT_status], ES_CRASHED
    jne pct_fail
    mov rdi, [rbx + EXT_reason]
    call mem_free
    mov qword ptr [rbx + EXT_reason], 0
    # Shutdown invalidates every owned request and restart before any polling callback.
    mov qword ptr [rip + pct_stage], 7
    mov dword ptr [rbx + EXT_status], ES_IDLE
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    test rax, rax
    jnz pct_fail
    mov dword ptr [rbx + EXT_restart], 1
    mov dword ptr [rbx + EXT_wait_slot], 1
    mov dword ptr [rbx + EXT_status], ES_STARTING
    lea rdi, [rbx + EXT_SIZE]
    lea rsi, [rip + pct_other]
    call ext_pending_new
    test rax, rax
    jz pct_fail
    mov [rbx + EXT_SIZE + EXT_pending], rax
    mov dword ptr [rbx + EXT_SIZE + EXT_restart], 1
    mov dword ptr [rbx + EXT_SIZE + EXT_wait_slot], 1
    call ext_shutdown
    cmp qword ptr [rip + pct_polls], 1
    jne pct_fail
    cmp qword ptr [rip + ext_pending_shutting_down], 1
    jne pct_fail
    cmp qword ptr [rbx + EXT_pending], 0
    jne pct_fail
    cmp dword ptr [rbx + EXT_restart], 0
    jne pct_fail
    cmp dword ptr [rbx + EXT_wait_slot], 0
    jne pct_fail
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    cmp rax, -32
    jne pct_fail
    mov dword ptr [rbx + EXT_manifest_ok], 1
    mov rdi, rbx
    call ext_legacy_start
    cmp rax, -32
    jne pct_fail
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_ext_cmds + VEC_len], 0
    mov qword ptr [rip + g_ext_cmds + VEC_ptr], 0
    mov qword ptr [rip + g_ext_owner + VEC_len], 0
    mov qword ptr [rip + g_ext_owner + VEC_ptr], 0
    lea rdi, [rbx + EXT_wq]
    call sb_free
    lea rdi, [rbx + EXT_rbuf]
    call sb_free
    call ext_pending_fixture_cleanup
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + pct_live]
    jne pct_fail
    mov edi, 1
    lea rsi, [rip + pct_ok]
    mov edx, 20
    call write_all
    xor eax, eax
    EPILOGUE
# Native boundary substitutes observe the actual lifecycle policy and own no OS resource.
FN pct_native_noop
    xor eax, eax
    ret
FN pct_native_open
    mov rax, -2
    ret
FN pct_native_close
    inc qword ptr [rip + pct_closes]
    xor eax, eax
    ret
FN pct_native_pipe
    inc qword ptr [rip + pct_pipes]
    mov rax, [rip + pct_pipes]
    cmp rax, [rip + pct_fault]
    je 1f
    mov dword ptr [rdi], 100
    mov dword ptr [rdi + 4], 101
    xor eax, eax
    ret
1:  mov rax, -24
    ret
FN pct_native_spawn
    mov rax, -12
    ret
FN pct_confine_failed
    mov eax, 1
    ret
FN pct_confine_reason
    lea rax, [rip + pct_state]
    ret
FN pct_retry_start
    cmp qword ptr [rdi + EXT_pending], 0
    je pct_fail
    cmp dword ptr [rdi + EXT_noconfine], 1
    jne pct_fail
    mov dword ptr [rdi + EXT_status], ES_STARTING
    inc qword ptr [rip + pct_retries]
    ret
FN pct_keeper_stop
    cmp rdi, 1
    jne pct_fail
    xor eax, eax
    ret
FN pct_keeper_poll
    inc qword ptr [rip + pct_keeper_polls]
    xor eax, eax
    cmp qword ptr [rip + pct_keeper_polls], 1
    je 1f
    mov eax, KP_DONE
1:  xor edx, edx
    xor r8d, r8d
    ret
FN pct_keeper_close
    inc qword ptr [rip + pct_keeper_closes]
    xor eax, eax
    ret
pct_shutdown_observe:
    cmp qword ptr [rip + ext_pending_shutting_down], 1
    jne pct_fail
    lea rax, [rip + pct_exts]
    mov ecx, 2
1:  cmp qword ptr [rax + EXT_pending], 0
    jne pct_fail
    cmp dword ptr [rax + EXT_restart], 0
    jne pct_fail
    cmp dword ptr [rax + EXT_wait_slot], 0
    jne pct_fail
    add rax, EXT_SIZE
    dec ecx
    jnz 1b
    ret
FN pct_shutdown_wait
    PROLOGUE
    call pct_shutdown_observe
    inc qword ptr [rip + pct_waits]
    xor eax, eax
    cmp qword ptr [rip + pct_waits], 1
    jne 1f
    mov rax, -1
1:  EPILOGUE
FN pct_shutdown_poll
    PROLOGUE
    call pct_shutdown_observe
    inc qword ptr [rip + pct_polls]
    lea rdi, [rip + pct_exts]
    xor esi, esi
    call ext_pending_set
    cmp rax, -32
    jne pct_fail
    EPILOGUE
# Replaced solely in the exact-inventory private test link.
FN ext_pending_fixture_setup
    ret
FN ext_pending_fixture_cleanup
    ret
.section .rodata
pct_owner: .asciz "o"
pct_a: .asciz "a"
pct_ab: .asciz "a.b"
pct_command: .asciz "a.b.c"
pct_other: .asciz "a.b.other"
pct_wire: .asciz "0 run a.b.c 0\n"
pct_ok: .ascii "ok pending commands\n"

.section .rodata
pct_star: .asciz "*"
pct_state: .asciz "pending-fixture"
pct_hello: .asciz "hello 1\n"
pct_open_prefix: .ascii "0 opened "
pct_hello_wire: .asciz "0 run a.b.c 1\n"
