# Drive production sender with synthetic server replies, inspecting exact bounded requests.
.include "rhun.inc"
.include "plat/x11.inc"
.section .rodata
y_name: .asciz "rhun-x11-send"
y_ok: .ascii "ok X11 bounded incremental sender\n"
.bss
.p2align 3
y_stage: .quad 0
y_source: .quad 0
y_live: .quad 0
y_event: .zero 32
y_reply: .zero 64
.text
y_fail:
    mov edi, [rip + y_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  SYS SYS_exit_group

y_empty:
    PROLOGUE
    cmp qword ptr [rip + x_send_budget], 0
    jne y_fail
    lea rbx, [rip + x_send_slots]
    lea r12, [rip + x_send_watchers]
    mov r13d, XS_COUNT
1:  cmp dword ptr [rbx + XS_state], 0
    jne y_fail
    cmp qword ptr [rbx + XS_ptr], 0
    jne y_fail
    cmp dword ptr [r12 + XW_state], 0
    jne y_fail
    cmp dword ptr [r12 + XW_refs], 0
    jne y_fail
    add rbx, XS_SIZE
    add r12, XW_SIZE
    dec r13d
    jnz 1b
    mov rax, [rip + y_live]
    cmp rax, [rip + g_mem_live]
    jne y_fail
    EPILOGUE

y_reset:
    PROLOGUE
    call y_empty
    inc qword ptr [rip + y_stage]
    mov dword ptr [rip + x_wire_output_len], 0
    mov dword ptr [rip + x_wire_sequence], 0
    mov dword ptr [rip + x_wire_max_request], 11
    mov dword ptr [rip + x_paste_owned], 1
    mov rax, [rip + y_source]
    mov [rip + x_wire_clipboard + SB_ptr], rax
    EPILOGUE

# request(length, requestor, property, target) with a common timestamp/selection tuple.
y_request:
    PROLOGUE 16
    mov [rip + x_wire_clipboard + SB_len], rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    lea rdi, [rip + y_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + y_event], 30
    mov dword ptr [rip + y_event + 4], 5
    mov dword ptr [rip + y_event + 8], 0x100
    mov eax, [rsp]
    mov [rip + y_event + 12], eax
    mov dword ptr [rip + y_event + 16], 0x101
    mov eax, [rsp + 8]
    mov [rip + y_event + 20], eax
    mov eax, [rsp + 4]
    mov [rip + y_event + 24], eax
    lea rdi, [rip + y_event]
    call x_serve_selection
    EPILOGUE
y_begin:
    mov esi, 0x200
    mov edx, 0x300
    mov ecx, 0x102
    jmp y_request

y_fence:
    sub rsp, 8
    call y_fence_raw
    add rsp, 8
    cmp eax, 1
    jne y_fail
    ret
y_fence_raw:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + y_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + y_reply], 1
    mov eax, [rbx + XS_fence_seq]
    mov [rip + y_reply + 2], ax
    lea rdi, [rip + y_reply]
    mov esi, 32
    call x_send_reply
    EPILOGUE

y_attributes:
    PROLOGUE
    mov ebx, [rdi + XS_watch]
    imul eax, ebx, XW_SIZE
    lea r12, [rip + x_send_watchers]
    add r12, rax
    cmp dword ptr [r12 + XW_state], XW_QUERY
    jne y_fail
    lea rdi, [rip + y_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + y_reply], 1
    mov eax, [r12 + XW_attributes_seq]
    mov [rip + y_reply + 2], ax
    mov dword ptr [rip + y_reply + 4], 3
    mov dword ptr [rip + y_reply + 36], 0x8000
    lea rdi, [rip + y_reply]
    mov esi, 44
    call x_send_reply
    cmp eax, 1
    jne y_fail
    EPILOGUE

y_delete:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + y_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + y_event], 28
    mov eax, [rbx + XS_window]
    mov [rip + y_event + 4], eax
    mov eax, [rbx + XS_property]
    mov [rip + y_event + 8], eax
    mov byte ptr [rip + y_event + 16], 1
    lea rdi, [rip + y_event]
    call x_send_property
    EPILOGUE

y_error:
    PROLOGUE
    mov ebx, edi
    lea rdi, [rip + y_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + y_event + 1], 11
    mov [rip + y_event + 2], bx
    lea rdi, [rip + y_event]
    call x_send_error
    EPILOGUE

y_expire_all:
    PROLOGUE
    lea rbx, [rip + x_send_slots]
    mov r12d, XS_COUNT
1:  cmp dword ptr [rbx + XS_state], 0
    je 2f
    mov qword ptr [rbx + XS_deadline], 1
2:  add rbx, XS_SIZE
    dec r12d
    jnz 1b
    call x_send_tick
    call y_empty
    EPILOGUE

FN main
    PROLOGUE 64
    mov qword ptr [rip + y_stage], 1
    lea rdi, [rip + y_name]
    xor esi, esi
    mov eax, 319
    XSYS
    test eax, eax
    js y_fail
    mov [rip + x_wire_fd], eax
    mov dword ptr [rip + x_send_main_window], 0x100
    mov dword ptr [rip + x_paste_clipboard_atom], 0x101
    mov dword ptr [rip + x_wire_utf8_atom], 0x102
    mov dword ptr [rip + x_paste_incr_atom], 0x103
    mov dword ptr [rip + x_wire_targets_atom], 0x104
    mov edi, 65536
    call mem_alloc
    mov [rip + y_source], rax
    mov rdi, rax
    mov esi, 0x41
    mov edx, 65536
    call memset
    mov rax, [rip + g_mem_live]
    mov [rip + y_live], rax

    # A direct result is not announced until server storage is confirmed.
    call y_reset
    mov edi, 3
    call y_begin
    lea rbx, [rip + x_send_slots]
    cmp dword ptr [rbx + XS_state], XS_INITIAL
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 32
    jne y_fail
    cmp dword ptr [rip + x_wire_sequence], 2
    jne y_fail
    lea r12, [rip + x_wire_output]
    cmp byte ptr [r12], 18
    jne y_fail
    cmp dword ptr [r12 + 20], 3
    jne y_fail
    cmp dword ptr [r12 + 28], 0x0001002b
    jne y_fail
    cmp word ptr [r12 + 24], 0x4141
    jne y_fail
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rip + x_wire_output_len], 76
    jne y_fail
    cmp dword ptr [r12 + 64], 0x300
    jne y_fail
    call y_empty

    # An Alloc error is remembered; the confirming fence produces a refusal.
    call y_reset
    mov edi, 3
    call y_begin
    mov edi, [rbx + XS_property_seq]
    call y_error
    cmp dword ptr [rip + x_wire_output_len], 32
    jne y_fail
    mov rdi, rbx
    call y_fence
    cmp dword ptr [r12 + 64], 0
    jne y_fail
    call y_empty

    # INCR header waits for attributes and server confirmation before the first byte.
    call y_reset
    mov edi, 30
    call y_begin
    cmp dword ptr [rbx + XS_state], XS_ATTRIBUTES
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 8
    jne y_fail
    cmp qword ptr [rbx + XS_len], 30
    jne y_fail
    cmp qword ptr [rip + x_send_budget], 30
    jne y_fail
    mov rdi, rbx
    call y_attributes
    cmp dword ptr [rip + x_wire_output_len], 56
    jne y_fail
    cmp dword ptr [r12 + 20], 0x428000
    jne y_fail
    cmp dword ptr [r12 + 36], 0x103
    jne y_fail
    cmp dword ptr [r12 + 48], 30
    jne y_fail
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 100
    jne y_fail
    # Later clipboard source mutation cannot alter accepted snapshot bytes.
    mov rdi, [rip + y_source]
    mov esi, 0x42
    mov edx, 30
    call memset
    mov rdi, rbx
    call y_delete
    cmp dword ptr [rbx + XS_state], XS_CHUNK
    jne y_fail
    cmp qword ptr [rbx + XS_offset], 20
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 148
    jne y_fail
    cmp byte ptr [r12 + 101], 2
    jne y_fail
    cmp dword ptr [r12 + 120], 20
    jne y_fail
    cmp dword ptr [r12 + 124], 0x41414141
    jne y_fail
    # Early deletion is remembered, but no next chunk precedes its fence.
    mov rdi, rbx
    call y_delete
    cmp dword ptr [rbx + XS_early_delete], 1
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 148
    jne y_fail
    mov rdi, rbx
    call y_fence
    cmp qword ptr [rbx + XS_offset], 30
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 188
    jne y_fail
    cmp dword ptr [r12 + 168], 10
    jne y_fail
    mov rdi, rbx
    call y_fence
    mov rdi, rbx
    call y_delete
    cmp dword ptr [rbx + XS_state], XS_FINAL
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 216
    jne y_fail
    cmp dword ptr [r12 + 208], 0
    jne y_fail
    # Final acknowledgement may also precede the fence; mask restores once.
    mov rdi, rbx
    call y_delete
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rip + x_wire_output_len], 232
    jne y_fail
    cmp dword ptr [r12 + 228], 0x8000
    jne y_fail
    call y_empty

    # Shared requestor: one attributes query, ordered initial decisions, separate properties.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 3
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    lea r13, [rip + x_send_slots + XS_SIZE]
    cmp dword ptr [r13 + XS_state], XS_INITIAL
    jne y_fail
    mov rdi, r13
    call y_fence
    cmp dword ptr [r13 + XS_state], XS_READY
    jne y_fail
    cmp dword ptr [r13 + XS_notified], 0
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 40
    jne y_fail
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rbx + XS_notified], 1
    jne y_fail
    cmp dword ptr [r13 + XS_state], 0
    jne y_fail
    # Both notifications appear in request arrival order despite reversed fence readiness.
    cmp dword ptr [rip + x_wire_output_len], 176
    jne y_fail
    cmp dword ptr [r12 + 120], 0x300
    jne y_fail
    cmp dword ptr [r12 + 164], 0x301
    jne y_fail
    call y_expire_all

    # Two INCR properties on the same requestor share and restore one mask.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 31
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    cmp dword ptr [rip + x_wire_output_len], 8
    jne y_fail
    cmp dword ptr [rip + x_send_watchers + XW_refs], 2
    jne y_fail
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov rdi, r13
    call y_fence
    mov rdi, rbx
    call y_finish
    cmp dword ptr [rip + x_send_watchers + XW_refs], 1
    jne y_fail
    mov rdi, r13
    call y_finish
    call y_empty

    # Mask changes racing the attributes query become the restoration baseline.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 0x200
    mov esi, 0x1234
    call x_send_window_mask
    mov rdi, rbx
    call y_attributes
    cmp dword ptr [rip + x_send_watchers + XW_mask], 0x1234
    jne y_fail
    mov rdi, rbx
    call y_fence
    mov edi, 0x200
    mov esi, 0x5678
    call x_send_window_mask
    cmp dword ptr [rip + x_send_watchers + XW_mask], 0x5678
    jne y_fail
    call y_expire_all
    mov eax, [rip + x_wire_output_len]
    cmp dword ptr [r12 + rax - 4], 0x5678
    jne y_fail

    # Attribute/select errors fail every dependant without any successful notification.
    xor r14d, r14d
.Ly_watch_errors:
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 31
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    test r14d, r14d
    jz 1f
    mov rdi, rbx
    call y_attributes
    mov edi, [rip + x_send_watchers + XW_select_seq]
    jmp 2f
1:  mov edi, [rip + x_send_watchers + XW_attributes_seq]
2:  call y_error
    call y_empty
    inc r14d
    cmp r14d, 2
    jne .Ly_watch_errors

    # Malformed attributes and fences refuse, foreign reply sequences remain pending.
    call y_reset
    mov edi, 30
    call y_begin
    lea rdi, [rip + y_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + y_reply], 1
    mov eax, [rip + x_send_watchers + XW_attributes_seq]
    mov [rip + y_reply + 2], ax
    lea rdi, [rip + y_reply]
    mov esi, 32
    call x_send_reply
    cmp eax, 1
    jne y_fail
    call y_empty
    call y_reset
    mov edi, 3
    call y_begin
    lea rdi, [rip + y_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + y_reply], 1
    mov eax, [rbx + XS_fence_seq]
    inc eax
    mov [rip + y_reply + 2], ax
    lea rdi, [rip + y_reply]
    mov esi, 32
    call x_send_reply
    test eax, eax
    jnz y_fail
    dec word ptr [rip + y_reply + 2]
    mov dword ptr [rip + y_reply + 4], 1
    lea rdi, [rip + y_reply]
    mov esi, 36
    call x_send_reply
    cmp eax, 1
    jne y_fail
    call y_empty

    # Full slot pressure preserves already-notified streams and bounds pending refusals.
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov r14d, 1
.Ly_fill:
    mov edi, 3
    mov esi, 0x200
    lea edx, [r14 + 0x300]
    mov ecx, 0x102
    call y_request
    inc r14d
    cmp r14d, XS_COUNT
    jb .Ly_fill
    mov edi, 3
    mov esi, 0x200
    mov edx, 0x400
    mov ecx, 0x102
    call y_request
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    cmp qword ptr [rip + x_send_budget], 30
    jne y_fail
    cmp dword ptr [r13 + XS_state], 0
    jne y_fail
    call y_expire_all

    # Source bytes, rather than the shorter Latin1 result, are charged before allocation.
    call y_reset
    mov rax, [rip + y_source]
    mov dword ptr [rax], 0xa9c3a9c3
    mov word ptr [rax + 4], 0xa9c3
    mov qword ptr [rip + x_send_budget], XS_BUDGET - 3
    mov edi, 6
    mov esi, 0x200
    mov edx, 0x300
    mov ecx, 31
    call y_request
    cmp qword ptr [rip + x_send_budget], XS_BUDGET - 3
    jne y_fail
    cmp dword ptr [rbx + XS_state], 0
    jne y_fail
    cmp dword ptr [rip + x_wire_output_len], 44
    jne y_fail
    mov qword ptr [rip + x_send_budget], 0
    call y_empty
    mov rdi, [rip + y_source]
    mov esi, 0x41
    mov edx, 65536
    call memset

    # Expired later ReadyNotify cannot spin behind a refreshed earlier conversion.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 3
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    mov rdi, r13
    call y_fence
    mov qword ptr [r13 + XS_deadline], 1
    call x_send_timeout
    test eax, eax
    jnz y_fail
    call x_send_tick
    call y_empty
    call x_send_timeout
    cmp eax, -1
    jne y_fail

    # A duplicate property is refused in tuple order and never overwrites the first transfer.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 3
    call y_begin
    cmp dword ptr [rip + x_wire_output_len], 8
    jne y_fail
    cmp dword ptr [r13 + XS_state], XS_READY
    jne y_fail
    cmp dword ptr [r13 + XS_failed], 1
    jne y_fail
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    cmp dword ptr [r13 + XS_state], 0
    jne y_fail
    call y_expire_all

    # Synthetic events, foreign properties and ownership loss cannot modify accepted streams.
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    lea rdi, [rip + y_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + y_event], 0x9c
    mov dword ptr [rip + y_event + 4], 0x200
    mov dword ptr [rip + y_event + 8], 0x300
    mov byte ptr [rip + y_event + 16], 1
    lea rdi, [rip + y_event]
    call x_send_property
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    mov byte ptr [rip + y_event], 28
    inc dword ptr [rip + y_event + 8]
    lea rdi, [rip + y_event]
    call x_send_property
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    mov dword ptr [rip + x_paste_owned], 0
    mov rdi, rbx
    call y_finish
    call y_empty

    # After notification a failed data write stops without a success terminator or second Notify.
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov rdi, rbx
    call y_delete
    mov edi, [rbx + XS_property_seq]
    call y_error
    mov rdi, rbx
    call y_fence
    cmp dword ptr [rip + x_wire_output_len], 164  # chunk + mask restore only
    jne y_fail
    call y_empty

    # External destruction drops subscriptions without trying to restore the destroyed window.
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    lea rdi, [rip + y_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + y_event], 0x91
    mov dword ptr [rip + y_event + 8], 0x200
    lea rdi, [rip + y_event]
    call x_send_destroy
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne y_fail
    mov byte ptr [rip + y_event], 17
    lea rdi, [rip + y_event]
    call x_send_destroy
    cmp dword ptr [rip + x_wire_output_len], 100
    jne y_fail
    call y_empty

    # Low16 wrap covers property65535/fence0; no signed or full32 comparison.
    call y_reset
    mov dword ptr [rip + x_wire_sequence], 65534
    mov edi, 3
    call y_begin
    cmp dword ptr [rbx + XS_property_seq], 65535
    jne y_fail
    cmp dword ptr [rbx + XS_fence_seq], 0
    jne y_fail
    mov rdi, rbx
    call y_fence
    call y_empty

    # Late replies and deletes cannot refresh an expired transfer before tick.
    call y_reset
    mov edi, 3
    call y_begin
    mov qword ptr [rbx + XS_deadline], 1
    mov rdi, rbx
    call y_fence_raw
    cmp dword ptr [r12 + 64], 0
    jne y_fail
    call y_empty
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov qword ptr [rbx + XS_deadline], 1
    mov rdi, rbx
    call y_delete
    call y_empty
    call y_reset
    mov edi, 30
    call y_begin
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov rdi, rbx
    call y_delete
    mov qword ptr [rbx + XS_deadline], 1
    mov rdi, rbx
    call y_fence_raw
    call y_empty

    # Expiry/error of a predecessor cannot drain an expired ready successor as success.
    xor r14d, r14d
.Ly_expired_ready:
    call y_reset
    mov edi, 3
    call y_begin
    mov edi, 30
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    mov rdi, r13
    call y_attributes
    mov rdi, r13
    call y_fence
    cmp dword ptr [r13 + XS_state], XS_READY
    jne y_fail
    mov qword ptr [r13 + XS_deadline], 1
    test r14d, r14d
    jnz 1f
    mov qword ptr [rbx + XS_deadline], 1
    call x_send_tick
    jmp 2f
1:  mov edi, [rbx + XS_fence_seq]
    call y_error
2:  call y_empty
    inc r14d
    cmp r14d, 2
    jne .Ly_expired_ready

    # Entry expiry preserves a fresh attributes waiter sharing the same requestor watch.
    call y_reset
    mov edi, 30
    call y_begin
    mov edi, 31
    mov esi, 0x200
    mov edx, 0x301
    mov ecx, 0x102
    call y_request
    mov qword ptr [rbx + XS_deadline], 1
    mov rdi, r13
    call y_attributes
    cmp dword ptr [rbx + XS_state], 0
    jne y_fail
    cmp dword ptr [r13 + XS_state], XS_INITIAL
    jne y_fail
    cmp dword ptr [rip + x_send_watchers + XW_refs], 1
    jne y_fail
    mov rdi, r13
    call y_fence
    mov rdi, r13
    call y_finish
    call y_empty

    # Cannot frame even a failure notification below11units. No unbounded/invalid requests.
    call y_reset
    mov dword ptr [rip + x_wire_max_request], 10
    mov edi, 3
    call y_begin
    cmp dword ptr [rip + x_wire_output_len], 0
    jne y_fail
    call y_empty
    # Large snapshots use bounded 16KiB chunks independent of BIG-REQUESTS availability.
    call y_reset
    mov dword ptr [rip + x_wire_max_request], 65535
    mov edi, 65536
    call y_begin
    cmp qword ptr [rbx + XS_chunk], 16384
    jne y_fail
    mov rdi, rbx
    call y_attributes
    mov rdi, rbx
    call y_fence
    mov rdi, rbx
    call y_finish
    call y_empty
    mov qword ptr [rip + x_wire_clipboard + SB_ptr], 0
    mov qword ptr [rip + x_wire_clipboard + SB_len], 0
    mov rdi, [rip + y_source]
    call mem_free
    cmp qword ptr [rip + g_mem_live], 0
    jne y_fail
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    mov edi, 1
    lea rsi, [rip + y_ok]
    mov edx, 34
    call write_all
    xor edi, edi
    SYS SYS_exit_group

# Complete a confirmed stream with normal ordered acknowledgements.
y_finish:
    PROLOGUE
    mov rbx, rdi
1:  mov rdi, rbx
    mov eax, [rbx + XS_state]
    test eax, eax
    jz 4f
    cmp eax, XS_FINAL_DELETE
    je 3f
    cmp eax, XS_DELETE
    jne y_fail
    call y_delete
    mov rdi, rbx
    call y_fence
    jmp 1b
3:  call y_delete
    jmp 1b
4:  EPILOGUE
