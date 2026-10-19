# No display connection. Native source ownership and the production clipboard paths.
.include "rhun.inc"
.include "plat/x11.inc"
.section .rodata
.p2align 3
xm_wire:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 2,5,0,3,4,1
    .ascii "a\nb\nc"
xm_text: .ascii "a\nb\nc"
xm_bar: .ascii "|"
xm_spread: .ascii "a\nb|c"
xm_abc: .ascii "abc"
xm_line: .ascii "L\n"
xm_line_result: .ascii "L\nabc"
xm_raw_result: .ascii "aL\nbc"
xm_unicode: .byte 0xc3,0xa9,0,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80
xm_bad: .byte 255
xm_copy_pairs: .quad 3,0,5,4
xm_dest_pairs: .quad 0,0,1,1
xm_caret: .quad 1,1
xm_name: .asciz "rhun-x11-metadata"
xm_ok: .ascii "ok X11 native clipboard metadata\n"
.bss
.p2align 3
xm_stage: .quad 0
xm_live: .quad 0
xm_doc: .quad 0
xm_snapshot: .quad 0
xm_source_before: .zero SB_SIZE + 16
xm_out: .zero 64
xm_event: .zero 32
xm_reply: .zero 64
xm_packet: .zero XR_PAGE + 32
xm_packet_size: .quad 0
xm_hint: .quad 0
xm_token: .quad 0
xm_old_window: .quad 0
xm_old_generation: .quad 0
xm_old_event: .zero 32
xm_old_packet: .zero 112
xm_corrupt: .zero 80
.text
xm_fail:
    mov edi, [rip + xm_stage]
    call sys_exit
xm_accept:
    mov eax, 1
    ret
xm_hold:
    ret
xm_clear_cache:
    PROLOGUE
    lea rax, [rip + xm_accept]
    mov [rip + g_plat + P_clip_write], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    cmp eax, 1
    jne xm_fail
    lea rax, [rip + x_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    EPILOGUE
xm_document:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call x_clip_reset
    call xm_clear_cache
    mov rax, [rip + g_mem_live]
    mov [rip + xm_live], rax
    call doc_new
    mov [rip + xm_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, rbx
    mov rcx, r12
    xor r8d, r8d
    call doc_insert
    EPILOGUE
xm_check:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rip + xm_doc]
    call doc_len
    cmp rax, r12
    jne xm_fail
    mov rdi, [rip + xm_doc]
    xor esi, esi
    mov rdx, r12
    lea rcx, [rip + xm_out]
    call doc_copy
    lea rdi, [rip + xm_out]
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz xm_fail
    EPILOGUE
xm_publish:
    PROLOGUE
    call clip_wire_encode
    test rax, rax
    jz xm_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    call x_clip_write
    cmp eax, 1
    jne xm_fail
    mov rdi, rbx
    call mem_free
    EPILOGUE
xm_request:
    PROLOGUE
    call app_clip_request
    cmp eax, 1
    jne xm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne xm_fail
    EPILOGUE
xm_cleanup:
    PROLOGUE
    call app_clip_reset
    call x_clip_reset
    call xm_clear_cache
    mov rdi, [rip + xm_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + xm_live]
    cmp rax, [rip + g_mem_live]
    jne xm_fail
    EPILOGUE
xm_source_capture:
    lea rdi, [rip + xm_source_before]
    lea rsi, [rip + x_wire_clipboard]
    mov edx, SB_SIZE + 16
    jmp memcpy
xm_source_same:
    PROLOGUE
    lea rdi, [rip + xm_source_before]
    lea rsi, [rip + x_wire_clipboard]
    mov edx, SB_SIZE + 16
    call memeq
    test eax, eax
    jz xm_fail
    cmp dword ptr [rip + x_paste_owned], 1
    jne xm_fail
    EPILOGUE
# One synthetic selection request. Internal args target, requestor.
xm_send_request:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov dword ptr [rip + x_wire_output_len], 0
    lea rdi, [rip + xm_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xm_event], 30
    mov dword ptr [rip + xm_event + 4], 5
    mov dword ptr [rip + xm_event + 8], 0x100
    mov [rip + xm_event + 12], r12d
    mov dword ptr [rip + xm_event + 16], 0x101
    mov [rip + xm_event + 20], ebx
    mov dword ptr [rip + xm_event + 24], 0x300
    lea rdi, [rip + xm_event]
    call x_serve_selection
    EPILOGUE
xm_fence:
    PROLOGUE
    mov ebx, [rdi + XS_fence_seq]
    lea rdi, [rip + xm_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + xm_reply], 1
    mov [rip + xm_reply + 2], bx
    lea rdi, [rip + xm_reply]
    mov esi, 32
    call x_send_reply
    cmp eax, 1
    jne xm_fail
    EPILOGUE
xm_attributes:
    PROLOGUE
    mov ebx, [rdi + XS_watch]
    imul eax, ebx, XW_SIZE
    lea rbx, [rip + x_send_watchers]
    add rbx, rax
    cmp dword ptr [rbx + XW_state], XW_QUERY
    jne xm_fail
    mov r12d, [rbx + XW_attributes_seq]
    lea rdi, [rip + xm_reply]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rip + xm_reply], 1
    mov [rip + xm_reply + 2], r12w
    mov dword ptr [rip + xm_reply + 4], 3
    mov dword ptr [rip + xm_reply + 36], 0x8000
    lea rdi, [rip + xm_reply]
    mov esi, 44
    call x_send_reply
    cmp eax, 1
    jne xm_fail
    EPILOGUE
xm_delete:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rip + x_wire_output_len], 0
    lea rdi, [rip + xm_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xm_event], 28
    mov eax, [rbx + XS_window]
    mov [rip + xm_event + 4], eax
    mov eax, [rbx + XS_property]
    mov [rip + xm_event + 8], eax
    mov byte ptr [rip + xm_event + 16], 1
    lea rdi, [rip + xm_event]
    call x_send_property
    EPILOGUE
xm_sender_empty:
    cmp qword ptr [rip + x_send_budget], 0
    jne xm_fail
    lea rax, [rip + x_send_slots]
    lea rcx, [rip + x_send_watchers]
    mov edx, XS_COUNT
1:  cmp dword ptr [rax + XS_state], 0
    jne xm_fail
    cmp qword ptr [rax + XS_ptr], 0
    jne xm_fail
    cmp dword ptr [rcx + XW_refs], 0
    jne xm_fail
    cmp dword ptr [rcx + XW_state], 0
    jne xm_fail
    add rax, XS_SIZE
    add rcx, XW_SIZE
    dec edx
    jnz 1b
    ret
xm_sender_tests:
    PROLOGUE
    mov qword ptr [rip + xm_stage], 10
    mov rax, [rip + g_mem_live]
    mov [rip + xm_live], rax
    mov dword ptr [rip + x_wire_max_request], 64
    lea rdi, [rip + xm_wire]
    mov esi, 69
    call x_clip_write
    cmp eax, 1
    jne xm_fail
    mov edi, 0x105
    mov esi, 0x200
    call xm_send_request
    lea rbx, [rip + x_send_slots]
    cmp dword ptr [rbx + XS_state], XS_INITIAL
    jne xm_fail
    cmp qword ptr [rip + x_send_budget], 69
    jne xm_fail
    cmp dword ptr [rip + x_wire_output_len], 100
    jne xm_fail
    cmp dword ptr [rip + x_wire_output + 12], 0x105
    jne xm_fail
    cmp byte ptr [rip + x_wire_output + 16], 8
    jne xm_fail
    cmp dword ptr [rip + x_wire_output + 20], 69
    jne xm_fail
    lea rdi, [rip + x_wire_output + 24]
    lea rsi, [rip + xm_wire]
    mov edx, 69
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, rbx
    call xm_fence
    call xm_sender_empty
    # TARGETS includes native metadata and compatible Latin1 in a fixed order.
    mov qword ptr [rip + xm_stage], 11
    mov edi, 0x106
    mov esi, 0x200
    call xm_send_request
    cmp dword ptr [rip + x_wire_output + 12], 4
    jne xm_fail
    cmp byte ptr [rip + x_wire_output + 16], 32
    jne xm_fail
    cmp dword ptr [rip + x_wire_output + 20], 4
    jne xm_fail
    lea rdi, [rip + x_wire_output + 24]
    lea rsi, [rip + xm_targets]
    mov edx, 16
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, rbx
    call xm_fence
    call xm_sender_empty
    lea rdi, [rip + xm_unicode]
    mov esi, 10
    xor edx, edx
    xor ecx, ecx
    call xm_publish
    mov edi, 0x106
    mov esi, 0x200
    call xm_send_request
    cmp dword ptr [rip + x_wire_output + 20], 3
    jne xm_fail
    lea rdi, [rip + x_wire_output + 24]
    lea rsi, [rip + xm_targets]
    mov edx, 12
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, rbx
    call xm_fence
    call xm_sender_empty
    # Reject corrupted cached wire and over-limit counts before touching its payload.
    mov qword ptr [rip + xm_stage], 12
    mov rax, [rip + x_clip_native]
    mov dword ptr [rax + 8], 2
    mov edi, 0x105
    mov esi, 0x200
    call xm_send_request
    call xm_sender_empty
    cmp dword ptr [rip + x_wire_output_len], 44
    jne xm_fail
    cmp dword ptr [rip + x_wire_output + 32], 0
    jne xm_fail
    mov rax, [rip + x_clip_native]
    mov dword ptr [rax + 8], 1
    mov qword ptr [rip + x_clip_native + 8], CLW_MAX + 1
    mov edi, 0x105
    mov esi, 0x200
    call xm_send_request
    call xm_sender_empty
    mov qword ptr [rip + x_clip_native + 8], 42
    # Tiny request sizes split the header/table/text over several INCR chunks.
    mov qword ptr [rip + xm_stage], 13
    lea rdi, [rip + xm_wire]
    mov esi, 69
    call x_clip_write
    cmp eax, 1
    jne xm_fail
    mov dword ptr [rip + x_wire_max_request], 11
    mov edi, 0x105
    mov esi, 0x200
    call xm_send_request
    cmp dword ptr [rbx + XS_state], XS_ATTRIBUTES
    jne xm_fail
    cmp qword ptr [rbx + XS_chunk], 20
    jne xm_fail
    mov rdi, rbx
    call xm_attributes
    mov rdi, rbx
    call xm_fence
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne xm_fail
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call x_clip_set
    cmp eax, 1
    jne xm_fail
    mov dword ptr [rip + x_paste_owned], 0
    xor r14d, r14d
.Lxm_send_chunk:
    mov rdi, rbx
    call xm_delete
    mov r12, [rbx + XS_offset]
    sub r12, r14
    cmp r12, 20
    ja xm_fail
    cmp dword ptr [rip + x_wire_output + 12], 0x105
    jne xm_fail
    cmp byte ptr [rip + x_wire_output + 1], 2
    jne xm_fail
    cmp byte ptr [rip + x_wire_output + 16], 8
    jne xm_fail
    cmp [rip + x_wire_output + 20], r12d
    jne xm_fail
    lea rdi, [rip + x_wire_output + 24]
    lea rsi, [rip + xm_wire]
    add rsi, r14
    mov rdx, r12
    call memeq
    test eax, eax
    jz xm_fail
    add r14, r12
    mov rdi, rbx
    call xm_fence
    cmp dword ptr [rbx + XS_state], XS_FINAL_DELETE
    je 1f
    cmp dword ptr [rbx + XS_state], XS_DELETE
    jne xm_fail
    jmp .Lxm_send_chunk
1:  cmp r14, 69
    jne xm_fail
    mov rdi, rbx
    call xm_delete
    call xm_sender_empty
    call x_clip_reset
    # Maximum native envelope includes table overhead in the outstanding byte quota.
    mov qword ptr [rip + xm_stage], 14
    mov edi, CLW_MAX + 1
    call mem_alloc
    mov r12, rax
    mov rax, CLW_MAGIC
    mov [r12], rax
    mov dword ptr [r12 + 8], 1
    mov qword ptr [r12 + 16], 512
    mov qword ptr [r12 + 24], 67108864
    lea rdi, [r12 + 8224]
    mov esi, 'z'
    mov edx, 67108864
    call memset
    mov [rip + x_clip_native], r12
    mov qword ptr [rip + x_clip_native + 8], CLW_MAX
    lea rax, [r12 + 8224]
    mov [rip + x_wire_clipboard + SB_ptr], rax
    mov qword ptr [rip + x_wire_clipboard + SB_len], 67108864
    mov qword ptr [rip + x_wire_clipboard + SB_cap], 67108865
    mov dword ptr [rip + x_paste_owned], 1
    mov edi, 0x105
    mov esi, 0x200
    call xm_send_request
    cmp dword ptr [rbx + XS_state], XS_ATTRIBUTES
    jne xm_fail
    cmp qword ptr [rip + x_send_budget], CLW_MAX
    jne xm_fail
    cmp qword ptr [rbx + XS_len], CLW_MAX
    jne xm_fail
    mov r13, [rip + g_mem_live]
    mov edi, 0x105
    mov esi, 0x201
    call xm_send_request
    cmp r13, [rip + g_mem_live]
    jne xm_fail
    cmp qword ptr [rip + x_send_budget], CLW_MAX
    jne xm_fail
    cmp dword ptr [rbx + XS_state], XS_ATTRIBUTES
    jne xm_fail
    mov qword ptr [rbx + XS_deadline], 1
    call x_send_tick
    call xm_sender_empty
    call x_clip_reset
    mov rax, [rip + xm_live]
    cmp rax, [rip + g_mem_live]
    jne xm_fail
    EPILOGUE
xm_receive_begin:
    PROLOGUE
    mov dword ptr [rip + x_paste_owned], 0
    mov dword ptr [rip + x_wire_output_len], 0
    call app_clip_request
    cmp eax, 1
    jne xm_fail
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xm_fail
    cmp dword ptr [rip + x_paste_record + XR_type], 0x105
    jne xm_fail
    cmp dword ptr [rip + x_wire_output + 48], 0x105
    jne xm_fail
    mov rax, [rip + app_clip_active_token]
    test rax, rax
    jz xm_fail
    mov [rip + xm_token], rax
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xm_old_window], rax
    mov rax, [rip + x_paste_generation]
    mov [rip + xm_old_generation], rax
    EPILOGUE
xm_notify:
    PROLOGUE
    mov ebx, edi
    lea rdi, [rip + xm_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xm_event], 0x9f
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xm_event + 8], eax
    mov dword ptr [rip + xm_event + 12], 0x101
    mov eax, [rip + x_paste_record + XR_type]
    mov [rip + xm_event + 16], eax
    mov [rip + xm_event + 20], ebx
    lea rdi, [rip + xm_event]
    call x_paste_notify
    EPILOGUE
xm_packet_make:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, XR_PAGE
    ja xm_fail
    lea rdi, [rip + xm_packet]
    xor esi, esi
    mov edx, XR_PAGE + 32
    call memset
    mov byte ptr [rip + xm_packet], 1
    mov byte ptr [rip + xm_packet + 1], 8
    mov eax, [rip + x_paste_record + XR_get_seq]
    mov [rip + xm_packet + 2], ax
    lea rax, [r12 + 3]
    shr rax, 2
    mov [rip + xm_packet + 4], eax
    lea rax, [rax*4 + 32]
    mov [rip + xm_packet_size], rax
    mov eax, [rip + x_paste_record + XR_type]
    mov [rip + xm_packet + 8], eax
    mov [rip + xm_packet + 12], r13d
    mov [rip + xm_packet + 16], r12d
    lea rdi, [rip + xm_packet + 32]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    EPILOGUE
xm_packet_send:
    PROLOGUE
    lea rdi, [rip + xm_packet]
    mov rsi, [rip + xm_packet_size]
    call x_paste_reply
    cmp eax, 1
    jne xm_fail
    EPILOGUE
xm_body:
    PROLOGUE
    call xm_packet_make
    call xm_packet_send
    EPILOGUE
xm_marker:
    PROLOGUE
    mov [rip + xm_hint], rdi
    lea rdi, [rip + xm_hint]
    mov esi, 4
    xor edx, edx
    call xm_packet_make
    mov byte ptr [rip + xm_packet + 1], 32
    mov dword ptr [rip + xm_packet + 8], 0x104
    mov dword ptr [rip + xm_packet + 16], 1
    call xm_packet_send
    EPILOGUE
xm_newvalue:
    PROLOGUE
    lea rdi, [rip + xm_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xm_event], 28
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + xm_event + 4], eax
    mov dword ptr [rip + xm_event + 8], 0x103
    lea rdi, [rip + xm_event]
    call x_paste_property
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xm_fail
    EPILOGUE
xm_fell_back:
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xm_fail
    cmp dword ptr [rip + x_paste_record + XR_type], 0x102
    jne xm_fail
    mov rax, [rip + xm_token]
    cmp rax, [rip + app_clip_active_token]
    jne xm_fail
    cmp rax, [rip + x_paste_record + XR_token]
    jne xm_fail
    mov eax, [rip + x_paste_record + XR_window]
    cmp rax, [rip + xm_old_window]
    je xm_fail
    mov rax, [rip + x_paste_generation]
    cmp rax, [rip + xm_old_generation]
    jbe xm_fail
    ret
xm_received:
    cmp qword ptr [rip + app_clip_active_token], 0
    jne xm_fail
    cmp dword ptr [rip + x_paste_record + XR_state], 0
    jne xm_fail
    ret
xm_receiver_tests:
    PROLOGUE
    mov qword ptr [rip + xm_stage], 20
    lea rdi, [rip + xm_bar]
    mov esi, 1
    call xm_document
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_dest_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne xm_fail
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_wire]
    mov esi, 69
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_spread]
    mov esi, 5
    call xm_check
    mov rdi, [rip + xm_doc]
    call doc_undo
    lea rdi, [rip + xm_bar]
    mov esi, 1
    call xm_check
    call xm_cleanup
    # A paged native property splits the binary header from Unicode/NUL text.
    mov qword ptr [rip + xm_stage], 21
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_unicode_wire]
    mov esi, 32
    mov edx, 10
    call xm_body
    cmp qword ptr [rip + x_paste_record + XR_offset], 8
    jne xm_fail
    lea rdi, [rip + xm_unicode_wire + 32]
    mov esi, 10
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_unicode]
    mov esi, 10
    call xm_check
    call xm_cleanup
    # INCR splits even the fixed header across binary properties.
    mov qword ptr [rip + xm_stage], 22
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    mov edi, 69
    call xm_marker
    call xm_newvalue
    lea rdi, [rip + xm_wire]
    mov esi, 1
    xor edx, edx
    call xm_body
    call xm_newvalue
    lea rdi, [rip + xm_wire + 1]
    mov esi, 2
    xor edx, edx
    call xm_body
    call xm_newvalue
    lea rdi, [rip + xm_wire + 3]
    mov esi, 66
    xor edx, edx
    call xm_body
    call xm_newvalue
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_text]
    mov esi, 5
    call xm_check
    call xm_cleanup
    # Unsupported wire falls back with the same token but a fresh requestor window.
    mov qword ptr [rip + xm_stage], 23
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_caret]
    mov edx, 1
    call doc_selections_set
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_old_event]
    lea rsi, [rip + xm_event]
    mov edx, 32
    call memcpy
    lea rdi, [rip + xm_wire]
    mov esi, 69
    xor edx, edx
    call xm_packet_make
    mov dword ptr [rip + xm_packet + 32 + 8], 2
    lea rdi, [rip + xm_old_packet]
    lea rsi, [rip + xm_packet]
    mov edx, 104
    call memcpy
    call xm_packet_send
    call xm_fell_back
    # Old notify, reply, property, error and destroy cannot affect the UTF8 attempt.
    lea rdi, [rip + xm_old_event]
    call x_paste_notify
    lea rdi, [rip + xm_old_packet]
    mov esi, 104
    call x_paste_reply
    test eax, eax
    jnz xm_fail
    lea rdi, [rip + xm_old_packet]
    call x_paste_error
    mov byte ptr [rip + xm_old_event], 28
    mov eax, [rip + xm_old_window]
    mov [rip + xm_old_event + 4], eax
    mov dword ptr [rip + xm_old_event + 8], 0x103
    mov byte ptr [rip + xm_old_event + 16], 0
    lea rdi, [rip + xm_old_event]
    call x_paste_property
    mov byte ptr [rip + xm_old_event], 17
    mov eax, [rip + xm_old_window]
    mov [rip + xm_old_event + 8], eax
    lea rdi, [rip + xm_old_event]
    call x_paste_destroy
    call xm_fell_back
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_line]
    mov esi, 2
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_raw_result]
    mov esi, 5
    call xm_check
    call xm_cleanup
    # Refusal is a matching native SelectionNotify propertyNone, then one UTF8 attempt.
    mov qword ptr [rip + xm_stage], 24
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    xor edi, edi
    call xm_notify
    call xm_fell_back
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_abc]
    mov esi, 3
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 25
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    mov rdi, [rip + xm_doc]
    call doc_undo
    mov rdi, [rip + xm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + xm_snapshot], rax
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_empty_wire]
    mov esi, 32
    xor edx, edx
    call xm_body
    call xm_received
    mov rdi, [rip + xm_doc]
    mov rsi, [rip + xm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, [rip + xm_snapshot]
    call mem_free
    mov rdi, [rip + xm_doc]
    call doc_redo
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_cleanup
    # A valid native response at a stale destination retires without a plain retry.
    mov qword ptr [rip + xm_stage], 26
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    call xm_receive_begin
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_caret]
    mov edx, 1
    call doc_selections_set
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_line_wire]
    mov esi, 34
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_line_wire]
    mov esi, 34
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_line_result]
    mov esi, 5
    call xm_check
    call xm_cleanup
    # Invalid fallback finishes failure before starting a queued native successor.
    mov qword ptr [rip + xm_stage], 27
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    call app_clip_request
    cmp eax, 1
    jne xm_fail
    xor edi, edi
    call xm_notify
    call xm_fell_back
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_bad]
    mov esi, 1
    xor edx, edx
    call xm_body
    cmp dword ptr [rip + x_paste_record + XR_type], 0x105
    jne xm_fail
    cmp dword ptr [rip + x_paste_record + XR_state], XR_NOTIFY
    jne xm_fail
    mov rax, [rip + app_clip_active_token]
    test rax, rax
    jz xm_fail
    cmp rax, [rip + xm_token]
    je xm_fail
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_wire]
    mov esi, 69
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_text]
    mov esi, 5
    call xm_check
    call xm_cleanup
    # Invalid complete envelopes release their buffer and preserve DOC and redo.
    lea r15, [rip + xm_mutations]
    mov qword ptr [rip + xm_stage], 30
.Lxm_bad_native:
    inc qword ptr [rip + xm_stage]
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    mov rdi, [rip + xm_doc]
    call doc_undo
    mov rdi, [rip + xm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + xm_snapshot], rax
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_corrupt]
    lea rsi, [rip + xm_wire]
    mov edx, 69
    call memcpy
    lea rdi, [rip + xm_corrupt]
    add rdi, [r15]
    mov rax, [r15 + 16]
    cmp qword ptr [r15 + 8], 8
    jne 1f
    mov [rdi], rax
    jmp 3f
1:  cmp qword ptr [r15 + 8], 4
    jne 2f
    mov [rdi], eax
    jmp 3f
2:  mov [rdi], al
3:  lea rdi, [rip + xm_corrupt]
    mov esi, 69
    xor edx, edx
    call xm_body
    call xm_fell_back
    cmp qword ptr [rip + x_paste_record + XR_buffer + SB_ptr], 0
    jne xm_fail
    cmp qword ptr [rip + x_paste_record + XR_buffer + SB_len], 0
    jne xm_fail
    call x_paste_cancel
    call xm_received
    mov rdi, [rip + xm_doc]
    mov rsi, [rip + xm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, [rip + xm_snapshot]
    call mem_free
    mov rdi, [rip + xm_doc]
    call doc_redo
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_cleanup
    add r15, 24
    cmp qword ptr [r15], -1
    jne .Lxm_bad_native
    # Native table overhead is allowed at the INCR boundary, plain text stays at64MiB.
    mov qword ptr [rip + xm_stage], 40
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    mov edi, CLW_MAX
    call xm_marker
    cmp dword ptr [rip + x_paste_record + XR_state], XR_CHUNK
    jne xm_fail
    cmp qword ptr [rip + x_paste_record + XR_lower], CLW_MAX
    jne xm_fail
    call x_paste_cancel
    call xm_received
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 41
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    mov edi, CLW_MAX + 1
    call xm_marker
    call xm_fell_back
    mov edi, 0x103
    call xm_notify
    mov edi, XR_LIMIT + 1
    call xm_marker
    call xm_received
    call xm_cleanup
    # Combined bytes-after arithmetic applies the limit before buffering the body.
    mov qword ptr [rip + xm_stage], 42
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_wire]
    mov esi, 4
    mov edx, CLW_MAX - 4
    call xm_body
    cmp dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    jne xm_fail
    cmp qword ptr [rip + x_paste_record + XR_buffer + SB_len], 4
    jne xm_fail
    call x_paste_cancel
    call xm_received
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 43
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_wire]
    mov esi, 4
    mov edx, CLW_MAX - 3
    call xm_body
    call xm_fell_back
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_wire]
    mov esi, 4
    mov edx, XR_LIMIT - 3
    call xm_body
    call xm_received
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 44
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov edi, 0x103
    call xm_notify
    mov edi, 70
    call xm_marker
    call xm_newvalue
    lea rdi, [rip + xm_wire]
    mov esi, 69
    xor edx, edx
    call xm_body
    call xm_newvalue
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call xm_body
    call xm_fell_back
    cmp dword ptr [rip + x_paste_record + XR_incr], 0
    jne xm_fail
    mov edi, 0x103
    call xm_notify
    lea rdi, [rip + xm_abc]
    mov esi, 3
    xor edx, edx
    call xm_body
    call xm_received
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_cleanup
    # Native expiry is a hard failure. It cannot start another30-second attempt.
    mov qword ptr [rip + xm_stage], 45
    xor edi, edi
    xor esi, esi
    call xm_document
    call xm_receive_begin
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    call x_paste_tick
    call xm_received
    call xm_cleanup
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + xm_stage], 1
    lea rdi, [rip + xm_name]
    xor esi, esi
    SYS SYS_memfd_create
    test eax, eax
    js xm_fail
    mov [rip + x_wire_fd], eax
    mov dword ptr [rip + x_send_main_window], 0x100
    mov dword ptr [rip + x_paste_clipboard_atom], 0x101
    mov dword ptr [rip + x_wire_utf8_atom], 0x102
    mov dword ptr [rip + x_paste_property_atom], 0x103
    mov dword ptr [rip + x_paste_incr_atom], 0x104
    mov dword ptr [rip + x_wire_native_atom], 0x105
    mov dword ptr [rip + x_wire_targets_atom], 0x106
    mov dword ptr [rip + x_paste_root], 0x999
    mov dword ptr [rip + x_paste_id_mask], 0xffff
    mov dword ptr [rip + x_paste_id_next], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    mov dword ptr [rip + cfg_multi_cursor_paste], 0
    lea rax, [rip + x_paste_begin]
    mov [rip + g_plat + P_clip_get], rax
    # Native source has a single allocation and a text view at its exact table end.
    lea rdi, [rip + xm_wire]
    mov esi, 69
    call x_clip_write
    cmp eax, 1
    jne xm_fail
    cmp qword ptr [rip + g_mem_live], 1
    jne xm_fail
    mov rdi, [rip + x_clip_native]
    test rdi, rdi
    jz xm_fail
    lea rsi, [rip + xm_wire]
    mov edx, 69
    call memeq
    test eax, eax
    jz xm_fail
    mov rax, [rip + x_clip_native]
    add rax, 64
    cmp rax, [rip + x_wire_clipboard + SB_ptr]
    jne xm_fail
    cmp qword ptr [rip + x_wire_clipboard + SB_len], 5
    jne xm_fail
    # Wire self-aliasing copies before freeing the old owner.
    mov rdi, [rip + x_clip_native]
    mov rsi, [rip + x_clip_native + 8]
    call x_clip_write
    cmp eax, 1
    jne xm_fail
    cmp qword ptr [rip + g_mem_live], 1
    jne xm_fail
    # Raw input may also borrow the old native text interior.
    mov rdi, [rip + x_wire_clipboard + SB_ptr]
    mov rsi, [rip + x_wire_clipboard + SB_len]
    call x_clip_set
    cmp eax, 1
    jne xm_fail
    cmp qword ptr [rip + x_clip_native], 0
    jne xm_fail
    mov rdi, [rip + x_wire_clipboard + SB_ptr]
    lea rsi, [rip + xm_text]
    mov edx, 5
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, [rip + x_wire_clipboard + SB_ptr]
    mov esi, 5
    call x_clip_set
    cmp eax, 1
    jne xm_fail
    cmp qword ptr [rip + g_mem_live], 1
    jne xm_fail
    call xm_source_capture
    xor edi, edi
    mov esi, 1
    call x_clip_write
    test eax, eax
    jnz xm_fail
    lea rdi, [rip + xm_bad]
    mov esi, 1
    call x_clip_set
    test eax, eax
    jnz xm_fail
    call xm_source_same
    mov dword ptr [rip + x_send_main_window], 0
    lea rdi, [rip + xm_wire]
    mov esi, 69
    call x_clip_write
    test eax, eax
    jnz xm_fail
    lea rdi, [rip + xm_text]
    mov esi, 5
    call x_clip_set
    test eax, eax
    jnz xm_fail
    call xm_source_same
    mov dword ptr [rip + x_send_main_window], 0x100
    mov dword ptr [rip + x_wire_native_atom], 0
    lea rdi, [rip + xm_wire]
    mov esi, 69
    call x_clip_write
    test eax, eax
    jnz xm_fail
    call xm_source_same
    mov dword ptr [rip + x_wire_native_atom], 0x105
    call x_clip_reset
    cmp qword ptr [rip + g_mem_live], 0
    jne xm_fail
    # A real prepared multi-copy survives its plan, cache and source DOC content changing.
    mov qword ptr [rip + xm_stage], 2
    lea rdi, [rip + xm_text]
    mov esi, 5
    call xm_document
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_copy_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne xm_fail
    mov rdi, [rip + xm_doc]
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne xm_fail
    mov rdi, [rip + x_clip_native]
    lea rsi, [rip + xm_wire]
    mov edx, 69
    call memeq
    test eax, eax
    jz xm_fail
    call xm_clear_cache
    mov rdi, [rip + xm_doc]
    xor esi, esi
    mov edx, 5
    xor ecx, ecx
    call doc_delete
    mov rdi, [rip + xm_doc]
    xor esi, esi
    lea rdx, [rip + xm_bar]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_dest_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne xm_fail
    call xm_request
    lea rdi, [rip + xm_spread]
    mov esi, 5
    call xm_check
    mov rdi, [rip + xm_doc]
    call doc_undo
    lea rdi, [rip + xm_bar]
    mov esi, 1
    call xm_check
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 3
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_caret]
    mov edx, 1
    call doc_selections_set
    lea rdi, [rip + xm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call xm_publish
    call xm_request
    lea rdi, [rip + xm_line_result]
    mov esi, 5
    call xm_check
    mov rdi, [rip + xm_doc]
    call doc_undo
    lea rdi, [rip + xm_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne xm_fail
    lea rdi, [rip + xm_line]
    mov esi, 2
    xor edx, edx
    xor ecx, ecx
    call xm_publish
    call xm_request
    lea rdi, [rip + xm_raw_result]
    mov esi, 5
    call xm_check
    cmp dword ptr [rip + g_clip_line], 0
    jne xm_fail
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 4
    xor edi, edi
    xor esi, esi
    call xm_document
    lea rdi, [rip + xm_unicode]
    mov esi, 10
    xor edx, edx
    xor ecx, ecx
    call xm_publish
    call xm_request
    lea rdi, [rip + xm_unicode]
    mov esi, 10
    call xm_check
    call xm_cleanup
    # Empty source preserves all DOC state and redo, including the selected range.
    mov qword ptr [rip + xm_stage], 5
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    mov rdi, [rip + xm_doc]
    call doc_undo
    mov rdi, [rip + xm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + xm_snapshot], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call xm_publish
    call xm_request
    mov rdi, [rip + xm_doc]
    mov rsi, [rip + xm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz xm_fail
    mov rdi, [rip + xm_snapshot]
    call mem_free
    mov rdi, [rip + xm_doc]
    call doc_redo
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    call xm_cleanup
    mov qword ptr [rip + xm_stage], 6
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_document
    lea rdi, [rip + xm_line]
    mov esi, 2
    xor edx, edx
    xor ecx, ecx
    call xm_publish
    lea rax, [rip + xm_hold]
    mov [rip + g_plat + P_clip_get], rax
    call app_clip_request
    cmp eax, 1
    jne xm_fail
    mov rdi, [rip + xm_doc]
    lea rsi, [rip + xm_caret]
    mov edx, 1
    call doc_selections_set
    call x_paste_begin
    cmp qword ptr [rip + app_clip_active_token], 0
    jne xm_fail
    lea rdi, [rip + xm_abc]
    mov esi, 3
    call xm_check
    lea rax, [rip + x_paste_begin]
    mov [rip + g_plat + P_clip_get], rax
    call xm_request
    lea rdi, [rip + xm_raw_result]
    mov esi, 5
    call xm_check
    call xm_cleanup
    call xm_sender_tests
    call xm_receiver_tests
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    mov edi, 1
    lea rsi, [rip + xm_ok]
    mov edx, 33
    call write_all
    xor edi, edi
    call sys_exit
.section .rodata
xm_targets: .long 0x106,0x102,0x105,31
xm_empty_wire:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 0,0
xm_line_wire:
    .ascii "RHUNCLP\0"
    .long 1,1
    .quad 0,2
    .ascii "L\n"
xm_unicode_wire:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 0,10
    .byte 0xc3,0xa9,0,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80
xm_mutations:
    .quad 0,8,0
    .quad 8,4,2
    .quad 12,4,2
    .quad 16,8,513
    .quad 24,8,6
    .quad 40,8,6
    .quad 48,8,1
    .quad 64,1,255
    .quad -1,0,0
