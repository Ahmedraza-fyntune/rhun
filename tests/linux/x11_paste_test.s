# No display connection. Drive production receiver states and inspect queued wire bytes.
.include "rhun.inc"
.include "plat/x11.inc"
.section .rodata
xp_initial: .ascii "original"
xp_text: .byte 0xc3,0xa9,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80,0,0x7a
xp_name: .asciz "rhun-x11-receiver"
xp_ok: .ascii "ok X11 bounded clipboard receiver\n"
.bss
.p2align 3
xp_stage: .quad 0
xp_doc: .quad 0
xp_sn: .quad 0
xp_doc_snapshot: .quad 0
xp_sn_snapshot: .quad 0
xp_live: .quad 0
xp_packet: .zero XR_PAGE + 32
xp_event: .zero 32
xp_copy: .zero XR_PAGE + 32
.text
xp_fail:
    mov edi, 2
    lea rsi, [rip + xp_name]
    mov edx, 17
    call write_all
    mov edi, [rip + xp_stage]
    SYS SYS_exit_group

xp_assert_same:
    PROLOGUE
    mov rdi, [rip + xp_doc]
    mov rsi, [rip + xp_doc_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz xp_fail
    mov rdi, [rip + xp_sn]
    mov rsi, [rip + xp_sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz xp_fail
    EPILOGUE

xp_setup:
    PROLOGUE
    inc qword ptr [rip + xp_stage]
    mov rax, [rip + g_mem_live]
    mov [rip + xp_live], rax
    call doc_new
    mov [rip + xp_doc], rax
    mov [rip + g_doc], rax
    mov rbx, rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + xp_initial]
    mov ecx, 8
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 8
    lea rdx, [rip + xp_initial]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + xp_initial]
    mov esi, 8
    call snippet_new
    mov [rip + xp_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 8
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + xp_sn]
    call snippet_validate
    cmp eax, 1
    jne xp_fail
    mov rdi, rbx
    mov rsi, [rip + xp_sn]
    xor edx, edx
    call snippet_attach
    mov qword ptr [rbx + DOC_cur], 8
    mov qword ptr [rbx + DOC_anchor], 0
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + xp_doc_snapshot], rax
    mov rdi, [rip + xp_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + xp_sn_snapshot], rax
    mov dword ptr [rip + x_wire_output_len], 0
    mov dword ptr [rip + x_paste_owned], 0
    call x_paste_begin
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xp_fail
    cmp qword ptr [rip + x_paste_record + XR_deadline], 30000
    jbe xp_fail
    call x_paste_tick
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xp_fail
    cmp dword ptr [rip + x_wire_output_len], 60
    jne xp_fail
    lea rbx, [rip + x_wire_output]
    cmp byte ptr [rbx], 1
    jne xp_fail
    cmp word ptr [rbx + 2], 9
    jne xp_fail
    cmp word ptr [rbx + 22], 2
    jne xp_fail
    cmp dword ptr [rbx + 32], 0x420000
    jne xp_fail
    cmp byte ptr [rbx + 36], 24
    jne xp_fail
    mov eax, [rip + x_paste_record + XR_window]
    cmp [rbx + 40], eax
    jne xp_fail
    EPILOGUE

xp_cleanup:
    PROLOGUE
    cmp dword ptr [rip + x_paste_record + XR_state], 0
    jne xp_fail
    cmp qword ptr [rip + x_paste_record + XR_buffer + SB_ptr], 0
    jne xp_fail
    mov rdi, [rip + xp_doc_snapshot]
    call mem_free
    mov rdi, [rip + xp_sn_snapshot]
    call mem_free
    mov rdi, [rip + xp_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + xp_live]
    cmp rax, [rip + g_mem_live]
    jne xp_fail
    EPILOGUE

xp_notify:
    PROLOGUE
    lea rdi, [rip + xp_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xp_event], 0x9f
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xp_event + 8], eax
    mov dword ptr [rip + xp_event + 12], 0x101
    mov dword ptr [rip + xp_event + 16], 0x102
    mov dword ptr [rip + xp_event + 20], 0x103
    lea rdi, [rip + xp_event]
    call x_paste_notify
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xp_fail
    mov eax, [rip + x_wire_output_len]
    lea rbx, [rip + x_wire_output]
    lea rbx, [rbx + rax - 24]
    cmp word ptr [rbx], 0x114
    jne xp_fail
    cmp word ptr [rbx + 2], 6
    jne xp_fail
    cmp dword ptr [rbx + 12], 0
    jne xp_fail
    cmp dword ptr [rbx + 20], XR_PAGE / 4
    jne xp_fail
    EPILOGUE

# Make a padded UTF8 property reply with count rdi and bytesAfter rsi.
xp_reply_make:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + xp_packet]
    xor esi, esi
    mov edx, XR_PAGE + 32
    call memset
    mov byte ptr [rip + xp_packet], 1
    mov byte ptr [rip + xp_packet + 1], 8
    mov eax, [rip + x_paste_record + XR_get_seq]
    mov [rip + xp_packet + 2], ax
    lea rax, [r12 + 3]
    shr rax, 2
    mov [rip + xp_packet + 4], eax
    mov dword ptr [rip + xp_packet + 8], 0x102
    mov [rip + xp_packet + 12], r13d
    mov [rip + xp_packet + 16], r12d
    EPILOGUE
xp_reply_send:
    lea rdi, [rip + xp_packet]
    mov esi, [rip + xp_packet + 4]
    shl rsi, 2
    add rsi, 32
    jmp x_paste_reply
xp_property:
    PROLOGUE
    lea rdi, [rip + xp_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xp_event], 28
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xp_event + 4], eax
    mov dword ptr [rip + xp_event + 8], 0x103
    lea rdi, [rip + xp_event]
    call x_paste_property
    EPILOGUE
xp_marker:
    PROLOGUE
    mov edi, 4
    xor esi, esi
    call xp_reply_make
    mov byte ptr [rip + xp_packet + 1], 32
    mov dword ptr [rip + xp_packet + 8], 0x104
    mov dword ptr [rip + xp_packet + 16], 1
    mov dword ptr [rip + xp_packet + 32], 11
    call xp_reply_send
    cmp eax, 1
    jne xp_fail
    cmp dword ptr [rip + x_paste_record + XR_state], XR_CHUNK
    jne xp_fail
    EPILOGUE

# Verify complete counted document contents, including NUL. No doc scratch allocation.
xp_text_check:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + xp_doc]
    call doc_len
    cmp rax, r13
    jne xp_fail
    mov rdi, [rip + xp_doc]
    xor esi, esi
    mov rdx, r13
    lea rcx, [rip + xp_copy]
    call doc_copy
    lea rdi, [rip + xp_copy]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jz xp_fail
    EPILOGUE

FN main
    PROLOGUE
    lea rdi, [rip + xp_name]
    xor esi, esi
    mov eax, 319
    XSYS
    test eax, eax
    js xp_fail
    mov [rip + x_wire_fd], eax
    mov dword ptr [rip + x_paste_root], 0x999
    mov dword ptr [rip + x_paste_clipboard_atom], 0x101
    mov dword ptr [rip + x_wire_utf8_atom], 0x102
    mov dword ptr [rip + x_paste_property_atom], 0x103
    mov dword ptr [rip + x_paste_incr_atom], 0x104
    mov dword ptr [rip + x_paste_id_mask], 0xffff
    mov dword ptr [rip + x_paste_id_next], 1
    mov dword ptr [rip + x_wire_sequence], 65534
    call xp_setup
    cmp dword ptr [rip + x_paste_record + XR_create_seq], 65535
    jne xp_fail
    cmp dword ptr [rip + x_paste_record + XR_convert_seq], 0
    jne xp_fail
    call xp_notify
    cmp dword ptr [rip + x_paste_record + XR_get_seq], 1
    jne xp_fail
    mov edi, 11
    xor esi, esi
    call xp_reply_make
    lea rdi, [rip + xp_packet + 32]
    lea rsi, [rip + xp_text]
    mov edx, 11
    call memcpy
    call xp_reply_send
    cmp eax, 1
    jne xp_fail
    lea rdi, [rip + xp_text]
    mov esi, 11
    call xp_text_check
    mov rdi, [rip + xp_doc]
    call doc_undo
    lea rdi, [rip + xp_initial]
    mov esi, 8
    call xp_text_check
    mov rdi, [rip + xp_doc]
    call doc_redo
    lea rdi, [rip + xp_text]
    mov esi, 11
    call xp_text_check
    call xp_cleanup

    # A reply arriving after Quit cannot deliver a paste while a native query finishes.
    call xp_setup
    call xp_notify
    mov edi, 11
    xor esi, esi
    call xp_reply_make
    lea rdi, [rip + xp_packet + 32]
    lea rsi, [rip + xp_text]
    mov edx, 11
    call memcpy
    mov dword ptr [rip + g_quit], 1
    lea rdi, [rip + xp_packet]
    mov esi, 44
    call x_wire_message
    call xp_assert_same
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xp_fail
    mov dword ptr [rip + g_quit], 0
    call x_paste_cancel
    call xp_cleanup

    # Late native errors must not complete or advance a pending paste either.
    call xp_setup
    call xp_notify
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    mov byte ptr [rip + xp_packet], 0
    mov byte ptr [rip + xp_packet + 1], 3
    mov dword ptr [rip + g_quit], 1
    lea rdi, [rip + xp_packet]
    mov esi, 32
    call x_wire_message
    call xp_assert_same
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xp_fail
    mov dword ptr [rip + g_quit], 0
    call x_paste_cancel
    call xp_cleanup

    # An accepted empty direct reply is observable but cannot touch document state.
    call xp_setup
    call xp_notify
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup

    # Header/body disagreement, wrong types, bad progress and limits all reject atomically.
    lea r14, [rip + xp_bad_vectors]
.Lxp_bad_loop:
    cmp qword ptr [r14], -1
    je .Lxp_bad_done
    call xp_setup
    call xp_notify
    mov rdi, [r14]
    mov rsi, [r14 + 8]
    call xp_reply_make
    mov rax, [r14 + 16]
    lea rcx, [rip + xp_packet]
    mov edx, [r14 + 24]
    cmp rax, 1
    jne 1f
    mov [rcx + rax], dl
    jmp 2f
1:
    mov [rcx + rax], edx
2:
    lea rdi, [rip + xp_packet]
    mov rsi, [r14 + 32]
    call x_paste_reply
    cmp eax, 1
    jne xp_fail
    call xp_assert_same
    call xp_cleanup
    add r14, 40
    jmp .Lxp_bad_loop
.Lxp_bad_done:
    # INCR format, item count, trailing body, bytesAfter and lower bound are strict.
    lea r14, [rip + xp_marker_bad]
.Lxp_marker_bad_loop:
    cmp qword ptr [r14], -1
    je .Lxp_marker_bad_done
    call xp_setup
    call xp_notify
    mov edi, 4
    xor esi, esi
    call xp_reply_make
    mov byte ptr [rip + xp_packet + 1], 32
    mov dword ptr [rip + xp_packet + 8], 0x104
    mov dword ptr [rip + xp_packet + 16], 1
    mov dword ptr [rip + xp_packet + 32], 11
    mov rax, [r14]
    lea rcx, [rip + xp_packet]
    mov edx, [r14 + 8]
    cmp eax, 1
    jne 1f
    mov [rcx + rax], dl
    jmp 2f
1:  mov [rcx + rax], edx
2:  lea rdi, [rip + xp_packet]
    mov rsi, [r14 + 16]
    call x_paste_reply
    cmp eax, 1
    jne xp_fail
    call xp_assert_same
    call xp_cleanup
    add r14, 24
    jmp .Lxp_marker_bad_loop
.Lxp_marker_bad_done:
    # Refusal and mismatched target/property cancel; unrelated windows/selections do not.
    xor r14d, r14d
.Lxp_notify_cases:
    call xp_setup
    lea rdi, [rip + xp_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xp_event + 8], eax
    mov dword ptr [rip + xp_event + 12], 0x101
    mov dword ptr [rip + xp_event + 16], 0x102
    mov dword ptr [rip + xp_event + 20], 0x103
    cmp r14d, 3
    jae 1f
    mov qword ptr [rip + xp_event + 20], 0
    test r14d, r14d
    jz 2f
    mov dword ptr [rip + xp_event + 20], 0x777
    cmp r14d, 1
    je 2f
    mov dword ptr [rip + xp_event + 16], 0x777
    jmp 2f
1:  cmp r14d, 3
    jne 3f
    inc dword ptr [rip + xp_event + 8]
    jmp 2f
3:  inc dword ptr [rip + xp_event + 12]
2:  lea rdi, [rip + xp_event]
    call x_paste_notify
    cmp r14d, 3
    jb 4f
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xp_fail
    call x_paste_cancel
4:  call xp_assert_same
    call xp_cleanup
    inc r14d
    cmp r14d, 5
    jne .Lxp_notify_cases

    # A valid empty incremental stream is a successful empty delivery.
    call xp_setup
    call xp_notify
    call xp_marker
    mov qword ptr [rip + x_paste_record + XR_lower], 0
    call xp_property
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup

    # Valid INCR marker with split UTF8 and counted NUL, never deliver an early chunk.
    call xp_setup
    call xp_notify
    call xp_marker
    call xp_assert_same
    call xp_property
    mov edi, 1
    xor esi, esi
    call xp_reply_make
    mov byte ptr [rip + xp_packet + 32], 0xc3
    call xp_reply_send
    call xp_assert_same
    call xp_property
    mov edi, 10
    xor esi, esi
    call xp_reply_make
    lea rdi, [rip + xp_packet + 32]
    lea rsi, [rip + xp_text + 1]
    mov edx, 10
    call memcpy
    call xp_reply_send
    call xp_assert_same
    call xp_property
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    lea rdi, [rip + xp_text]
    mov esi, 11
    call xp_text_check
    call xp_cleanup

    # INCR cannot finish below its advertised lower bound or contain another INCR marker.
    call xp_setup
    call xp_notify
    call xp_marker
    call xp_property
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup
    call xp_setup
    call xp_notify
    call xp_marker
    call xp_property
    mov edi, 4
    xor esi, esi
    call xp_reply_make
    mov byte ptr [rip + xp_packet + 1], 32
    mov dword ptr [rip + xp_packet + 8], 0x104
    mov dword ptr [rip + xp_packet + 16], 1
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup

    # Two pages: delete remains set, offset advances in 4-byte units; wrap the next request.
    call xp_setup
    call xp_notify
    mov dword ptr [rip + x_wire_sequence], 65535
    mov edi, 4
    mov esi, 4
    call xp_reply_make
    mov dword ptr [rip + xp_packet + 32], 0x64636261
    call xp_reply_send
    cmp qword ptr [rip + x_paste_record + XR_offset], 1
    jne xp_fail
    cmp qword ptr [rip + x_paste_record + XR_remaining], 4
    jne xp_fail
    cmp dword ptr [rip + x_paste_record + XR_get_seq], 0
    jne xp_fail
    mov eax, [rip + x_wire_output_len]
    lea rcx, [rip + x_wire_output]
    cmp dword ptr [rcx + rax - 8], 1
    jne xp_fail
    call xp_assert_same
    mov edi, 4
    xor esi, esi
    call xp_reply_make
    mov dword ptr [rip + xp_packet + 32], 0x68676665
    call xp_reply_send
    lea rdi, [rip + xp_pages]
    mov esi, 8
    call xp_text_check
    call xp_cleanup

    # A page with a changed remaining length cancels without partial delivery.
    call xp_setup
    call xp_notify
    mov edi, 4
    mov esi, 4
    call xp_reply_make
    call xp_reply_send
    mov edi, 3
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup

    # Busy, unrelated replies/events and duplicate notifications preserve the active transfer.
    call xp_setup
    mov r15, [rip + x_paste_record + XR_deadline]
    mov r12d, [rip + x_paste_record + XR_window]
    call x_paste_begin
    cmp dword ptr [rip + x_wire_output_len], 60
    jne xp_fail
    call x_paste_timeout
    test eax, eax
    js xp_fail
    cmp eax, XR_MILLISECONDS
    ja xp_fail
    call xp_notify
    lea rdi, [rip + xp_event]
    call x_paste_notify
    cmp dword ptr [rip + x_wire_output_len], 84
    jne xp_fail
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    inc word ptr [rip + xp_packet + 2]
    call xp_reply_send
    test eax, eax
    jnz xp_fail
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xp_fail
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call x_paste_timeout
    test eax, eax
    jnz xp_fail
    call x_paste_tick
    call xp_assert_same
    call xp_cleanup

    # Silent owner starts with a valid deadline; expiry frees it once.
    call xp_setup
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call x_paste_tick
    mov r12d, [rip + x_wire_output_len]
    call x_paste_tick
    cmp r12d, [rip + x_wire_output_len]
    jne xp_fail
    call xp_assert_same
    call xp_cleanup

    # Phase-specific errors. Obsolete ConvertSelection errors cannot cancel GetProperty.
    xor r14d, r14d
.Lxp_errors:
    call xp_setup
    cmp r14d, 2
    jb 1f
    call xp_notify
1:  mov eax, [rip + x_paste_record + XR_create_seq]
    test r14d, r14d
    jz 2f
    mov eax, [rip + x_paste_record + XR_convert_seq]
2:  mov [rip + xp_event + 2], ax
    lea rdi, [rip + xp_event]
    call x_paste_error
    cmp r14d, 2
    jne 3f
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xp_fail
    mov eax, [rip + x_paste_record + XR_get_seq]
    mov [rip + xp_event + 2], ax
    lea rdi, [rip + xp_event]
    call x_paste_error
3:  call xp_assert_same
    call xp_cleanup
    inc r14d
    cmp r14d, 3
    jne .Lxp_errors

    # Synthetic/foreign property events cannot trigger or cancel a transfer.
    call xp_setup
    call xp_notify
    call xp_marker
    mov byte ptr [rip + xp_event], 0x9c
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xp_event + 4], eax
    mov dword ptr [rip + xp_event + 8], 0x103
    mov byte ptr [rip + xp_event + 16], 0
    lea rdi, [rip + xp_event]
    call x_paste_property
    cmp dword ptr [rip + x_paste_record + XR_state], XR_CHUNK
    jne xp_fail
    inc dword ptr [rip + xp_event + 4]
    mov byte ptr [rip + xp_event], 28
    lea rdi, [rip + xp_event]
    call x_paste_property
    cmp dword ptr [rip + x_paste_record + XR_state], XR_CHUNK
    jne xp_fail
    call xp_property
    call xp_property
    call xp_assert_same
    call xp_cleanup

    # External destruction retires state without sending a second DestroyWindow.
    call xp_setup
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xp_event + 8], eax
    mov byte ptr [rip + xp_event], 0x91
    lea rdi, [rip + xp_event]
    call x_paste_destroy
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xp_fail
    mov byte ptr [rip + xp_event], 17
    lea rdi, [rip + xp_event]
    call x_paste_destroy
    cmp dword ptr [rip + x_wire_output_len], 60
    jne xp_fail
    call xp_assert_same
    call xp_cleanup

    # Late protocol data must not revive a deadline before the platform tick runs.
    call xp_setup
    call xp_notify
    mov edi, 11
    xor esi, esi
    call xp_reply_make
    lea rdi, [rip + xp_packet + 32]
    lea rsi, [rip + xp_text]
    mov edx, 11
    call memcpy
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup
    call xp_setup
    call xp_notify
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    mov dword ptr [rip + g_dirty], 0
    call xp_reply_send
    cmp dword ptr [rip + g_dirty], 0
    jne xp_fail
    call xp_assert_same
    call xp_cleanup
    # A stale reply can be replayed after cleanup without affecting a fresh receive.
    call xp_reply_send
    call xp_setup
    call xp_notify
    mov edi, 4
    mov esi, 4
    call xp_reply_make
    call xp_reply_send
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    mov edi, 4
    xor esi, esi
    call xp_reply_make
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup
    call xp_setup
    call xp_notify
    call xp_marker
    call xp_property
    mov edi, 11
    xor esi, esi
    call xp_reply_make
    lea rdi, [rip + xp_packet + 32]
    lea rsi, [rip + xp_text]
    mov edx, 11
    call memcpy
    call xp_reply_send
    call xp_property
    xor edi, edi
    xor esi, esi
    call xp_reply_make
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call xp_reply_send
    call xp_assert_same
    call xp_cleanup
    call xp_setup
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    # The event envelope still names the old private requestor after its retirement.
    lea rdi, [rip + xp_event]
    mov byte ptr [rdi], 0x9f
    mov eax, [rip + x_paste_record + XR_window]
    mov [rdi + 8], eax
    mov dword ptr [rdi + 12], 0x101
    mov dword ptr [rdi + 16], 0x102
    mov dword ptr [rdi + 20], 0x103
    call x_paste_notify
    call xp_assert_same
    call xp_cleanup
    call xp_setup
    call xp_notify
    call xp_marker
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call xp_property
    call xp_assert_same
    call xp_cleanup

    # Local ownership uses the same counted delivery and leaves source storage intact.
    call xp_setup
    call x_paste_cancel
    lea rdi, [rip + x_wire_clipboard]
    lea rsi, [rip + xp_text]
    mov edx, 11
    call sb_push
    mov r12, [rip + x_wire_clipboard + SB_ptr]
    mov dword ptr [rip + x_paste_owned], 1
    call x_paste_begin
    cmp r12, [rip + x_wire_clipboard + SB_ptr]
    jne xp_fail
    lea rdi, [rip + xp_text]
    mov esi, 11
    call xp_text_check
    lea rdi, [rip + x_wire_clipboard]
    call sb_free
    call xp_cleanup
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    mov edi, 1
    lea rsi, [rip + xp_ok]
    mov edx, 34
    call write_all
    xor edi, edi
    SYS SYS_exit_group
.section .rodata
xp_pages: .ascii "abcdefgh"
# count, bytesAfter, 32-bit field offset/value, supplied complete packet size.
xp_bad_vectors:
    .quad 4,0,1,16,36
    .quad 4,0,8,0x777,36
    .quad 4,0,8,0x104,36
    .quad 4,0,16,8,36
    .quad 4,0,4,2,36
    .quad 4,0,4,0xffffffff,36
    .quad 4,0,32,0xff,36
    .quad 4,67108864,8,0x102,36
    .quad 3,4,8,0x102,36
    .quad 0,4,8,0x102,32
    .quad 16385,0,8,0x102,16420
    .quad 4,0,8,0x102,35
    .quad 4,0,8,0x102,31
    .quad 4,0,8,0x102,33
    .quad -1

xp_marker_bad:
    .quad 1,16,36
    .quad 16,0,36
    .quad 16,2,36
    .quad 12,4,36
    .quad 32,67108865,36
    .quad 4,2,40
    .quad -1
