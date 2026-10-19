# Fixed current-executable settings helper. No editor/extension initialization.
.include "rhun.inc"
.include "app/extsettingsworker.inc"
.text
FN ext_settings_worker_main
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov edi, SW_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lsw_no_context
    mov rbx, rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, rbx
    call ext_settings_worker_arguments
    test rax, rax
    js .Lsw_usage
    lea rdi, [rbx + SW_io]
    call ext_settings_worker_io_init
    test rax, rax
    js .Lsw_usage
    mov rdi, rbx
    call sw_deadline_set
    mov qword ptr [rbx + SW_state], SW_PRECOMMIT_FAILED
    mov rdi, rbx
    call sw_read_frame
    test rax, rax
    jnz .Lsw_usage
    cmp qword ptr [rbx + SW_kind], EW_REQUEST
    jne .Lsw_usage
    cmp qword ptr [rbx + SW_frame_round], 0
    jne .Lsw_usage
    mov rdi, [rbx + SW_body]
    mov rsi, [rbx + SW_length]
    lea rdx, [rbx + SW_request]
    call ext_settings_worker_request
    test rax, rax
    js .Lsw_usage
    mov rax, [rbx + SW_request + SWR_mode]
    mov [rbx + SW_mode], rax
    cmp rax, 2
    jne .Lsw_open_ready
    mov qword ptr [rbx + SW_round], 1
.Lsw_open_ready:
    mov rdi, rbx
    call sw_open
    test rax, rax
    js .Lsw_failed
    cmp qword ptr [rbx + SW_mode], 2
    je .Lsw_save
    mov rdi, rbx
    call sw_snapshot_take
    test rax, rax
    js .Lsw_failed
    mov rdi, rbx
    mov rsi, [rbx + SW_snapshot]
    call sw_baseline_check
    test rax, rax
    js .Lsw_failed
    cmp qword ptr [rbx + SW_mode], 1
    jne .Lsw_snapshot_ready
    # READ has no subsequent command. Refuse any already-buffered trailing input.
    mov rdi, rbx
    call sw_terminal_probe
    test rax, rax
    js .Lsw_failed
.Lsw_snapshot_ready:
    mov rdi, rbx
    mov rsi, [rbx + SW_snapshot]
    xor edx, edx
    call sw_emit_snapshot
    test rax, rax
    js .Lsw_failed
    mov rdi, rbx
    mov rsi, [rbx + SW_snapshot]
    call sw_announce
    mov rdi, rbx
    call sw_snapshot_free
    mov rdi, rbx
    call sw_body_free
    mov qword ptr [rbx + SW_state], SW_READ_OK
    cmp qword ptr [rbx + SW_mode], 1
    je .Lsw_finish
    jmp .Lsw_wait_next
.Lsw_save:
    mov rdi, rbx
    mov esi, 1
    call sw_prepare
    test rax, rax
    js .Lsw_failed
.Lsw_prepared:
    mov rdi, rbx
    call sw_read_frame
    cmp rax, 1
    je .Lsw_canceled
    test rax, rax
    js .Lsw_failed
    mov rax, [rbx + SW_frame_round]
    cmp [rbx + SW_round], rax
    jne .Lsw_bad_protocol
    cmp qword ptr [rbx + SW_kind], EW_RELEASE
    je .Lsw_prepared_release
    cmp qword ptr [rbx + SW_kind], EW_ABORT
    je .Lsw_abort
    cmp qword ptr [rbx + SW_kind], EW_COMMIT
    jne .Lsw_bad_protocol
    mov rdi, rbx
    call sw_commit
    test rax, rax
    js .Lsw_finish
    jmp .Lsw_wait_next
.Lsw_abort:
    mov rdi, rbx
    call sw_cleanup_candidate
    mov qword ptr [rbx + SW_state], SW_CANCELED
    mov qword ptr [rbx + SW_primary], -125
    mov rdi, rbx
    call sw_emit_discarded
    test rax, rax
    js .Lsw_finish
.Lsw_wait_next:
    # Full receipt granted retained config-guard authority. Never time out this idle hold.
    mov qword ptr [rbx + SW_idle_hold], 1
    mov rdi, rbx
    call sw_read_frame
    cmp rax, 1
    je .Lsw_finish
    test rax, rax
    js .Lsw_failed
    cmp qword ptr [rbx + SW_kind], EW_RELEASE
    je .Lsw_release
    cmp qword ptr [rbx + SW_kind], EW_DELTA
    jne .Lsw_bad_protocol
    mov rax, [rbx + SW_round]
    inc rax
    cmp rax, 3
    ja .Lsw_bad_protocol
    cmp [rbx + SW_frame_round], rax
    jne .Lsw_bad_protocol
    mov [rbx + SW_round], rax
    mov qword ptr [rbx + SW_state], SW_PRECOMMIT_FAILED
    mov qword ptr [rbx + SW_primary], 0
    mov r12, [rbx + SW_body]
    cmp dword ptr [r12 + 4], 0
    jne .Lsw_bad_protocol
    mov edx, [r12]
    mov [rbx + SW_request + SWR_count], rdx
    lea rdi, [r12 + 8]
    mov rsi, [rbx + SW_length]
    sub rsi, 8
    lea rcx, [rbx + SW_request + SWR_delta]
    call ext_settings_wire_deltas
    test rax, rax
    js .Lsw_failed
    mov rdi, rbx
    xor esi, esi
    call sw_prepare
    test rax, rax
    js .Lsw_failed
    jmp .Lsw_prepared
.Lsw_release:
    mov rax, [rbx + SW_frame_round]
    cmp [rbx + SW_round], rax
    jne .Lsw_bad_protocol
    mov rdi, rbx
    call sw_terminal_probe
    test rax, rax
    js .Lsw_failed
    jmp .Lsw_finish
.Lsw_prepared_release:
    mov rdi, rbx
    call sw_terminal_probe
    test rax, rax
    js .Lsw_failed
.Lsw_canceled:
    mov rax, -125
    jmp .Lsw_failed
.Lsw_bad_protocol:
    mov rax, -71
.Lsw_failed:
    cmp qword ptr [rbx + SW_state], SW_COMMITTED
    jne 1f
    mov rdi, rbx
    mov rsi, rax
    call sw_cleanup_latch
    jmp .Lsw_finish
1:  mov [rbx + SW_primary], rax
    mov qword ptr [rbx + SW_state], SW_PRECOMMIT_FAILED
.Lsw_finish:
    mov rdi, rbx
    call sw_cleanup_all
    cmp qword ptr [rbx + SW_transport_failed], 0
    jne .Lsw_output_failed
    mov qword ptr [rbx + SW_idle_hold], 0
    mov rdi, rbx
    call sw_deadline_set
    mov rdi, rbx
    mov esi, EW_RESULT
    mov edx, 32
    mov rcx, [rbx + SW_round]
    call sw_emit_header
    test rax, rax
    js .Lsw_output_failed
    mov rdi, rbx
    lea rsi, [rbx + SW_result]
    mov edx, 32
    call sw_emit_payload
    test rax, rax
    js .Lsw_output_failed
    xor r12d, r12d
    jmp .Lsw_dispose
.Lsw_usage:
    mov rdi, rbx
    call sw_cleanup_all
    mov r12d, 2
    jmp .Lsw_dispose
.Lsw_output_failed:
    mov r12d, 1
.Lsw_dispose:
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
.Lsw_no_context:
    mov eax, 1
    EPILOGUE
