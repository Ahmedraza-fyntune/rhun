# Native Wayland clipboard source ownership and counted delivery.
.include "rhun.inc"
.include "plat/wayland.inc"
.section .rodata
wm_wire:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 2,5,0,3,4,1
    .ascii "a\nb\nc"
wm_text: .ascii "a\nb\nc"
wm_abc: .ascii "abc"
wm_line: .ascii "L\n"
wm_line_result: .ascii "L\nabc"
wm_raw_result: .ascii "aL\nbc"
wm_spread: .ascii "a\nb|c"
wm_bar: .ascii "|"
wm_pairs: .quad 0,0,1,1
wm_mime_native: .long 32
    .asciz "application/x-rhun-clipboard-v1"
wm_mime_plain: .long 11
    .asciz "text/plain"
    .byte 0
wm_offer_id: .long 0x500
wm_name: .asciz "rhun-wayland-metadata"
wm_ok: .ascii "ok Wayland native clipboard metadata\n"
.equ WM_OK_LEN, . - wm_ok
.bss
.p2align 3
wm_stage: .quad 0
wm_live: .quad 0
wm_doc: .quad 0
wm_old: .quad 0
wm_snapshot: .zero WCS_SIZE
wm_out: .zero 256
wm_pipe1: .zero 8
wm_pipe2: .zero 8
wm_job1: .quad 0
wm_job2: .quad 0
wm_socket: .zero 8
wm_message: .zero 56
wm_iov: .zero 16
wm_control: .zero 24
wm_packet: .zero 4096
wm_writer: .zero 4
wm_token: .quad 0
wm_generation: .quad 0
wm_old_fd: .quad 0
wm_large: .quad 0
wm_large_fd: .zero 4
.data
wm_signal: .quad 1,0,0,0
.text
wm_fail:
    mov edi, [rip + wm_stage]
    call sys_exit
wm_sources_clean:
    PROLOGUE
    lea rbx, [rip + wl_send_sources]
    mov r12d, WCS_COUNT
1:  mov edi, [rbx + WCS_id]
    call wl_source_deleted
    add rbx, WCS_SIZE
    dec r12d
    jnz 1b
    cmp qword ptr [rip + wl_send_charge], 0
    jne wm_fail
    mov dword ptr [rip + wl_paste_wire_output_len], 0
    EPILOGUE
wm_source:
    mov edi, [rip + wl_paste_source_id]
    jmp wl_source_find
wm_same:
    PROLOGUE
    call wm_source
    lea rdi, [rip + wm_snapshot]
    mov rsi, rax
    mov edx, WCS_SIZE
    call memeq
    test eax, eax
    jz wm_fail
    EPILOGUE
wm_publish:
    PROLOGUE
    call clip_wire_encode
    test rax, rax
    jz wm_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    call wl_clip_write
    cmp eax, 1
    jne wm_fail
    mov rdi, rbx
    call mem_free
    EPILOGUE
wm_document:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_new
    mov [rip + wm_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, rbx
    mov rcx, r12
    xor r8d, r8d
    call doc_insert
    EPILOGUE
wm_check:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rip + wm_doc]
    call doc_len
    cmp rax, r12
    jne wm_fail
    mov rdi, [rip + wm_doc]
    xor esi, esi
    mov rdx, r12
    lea rcx, [rip + wm_out]
    call doc_copy
    lea rdi, [rip + wm_out]
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz wm_fail
    EPILOGUE
wm_cleanup:
    PROLOGUE
    call app_clip_reset
    call wm_sources_clean
    mov rdi, [rip + wm_doc]
    test rdi, rdi
    jz 1f
    call doc_free
1:
    mov qword ptr [rip + wm_doc], 0
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + wm_live]
    cmp rax, [rip + g_mem_live]
    jne wm_fail
    EPILOGUE
wm_pipe:
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js wm_fail
    ret
wm_sender:
    PROLOGUE
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wl_clip_write
    cmp eax, 1
    jne wm_fail
    call wm_source
    mov [rip + wm_old], rax
    lea rdi, [rip + wm_pipe1]
    call wm_pipe
    mov rdi, [rip + wm_old]
    mov esi, [rip + wm_pipe1 + 4]
    mov edx, 4
    call wl_send_start
    cmp eax, 1
    jne wm_fail
    mov edi, [rip + wm_pipe1 + 4]
    call wl_send_find
    test rax, rax
    jz wm_fail
    mov [rip + wm_job1], rax
    cmp qword ptr [rax + WCJ_len], 69
    jne wm_fail
    lea rdi, [rip + wm_pipe2]
    call wm_pipe
    mov rdi, [rip + wm_old]
    mov esi, [rip + wm_pipe2 + 4]
    mov edx, 1
    call wl_send_start
    cmp eax, 1
    jne wm_fail
    mov edi, [rip + wm_pipe2 + 4]
    call wl_send_find
    mov [rip + wm_job2], rax
    cmp qword ptr [rax + WCJ_len], 5
    jne wm_fail
    # Both spans keep the old allocation after replacement and server deletion.
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wl_clip_set
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + wm_old]
    mov edi, [rax + WCS_id]
    call wl_source_deleted
    mov rax, [rip + wm_old]
    cmp dword ptr [rax + WCS_state], 3
    jne wm_fail
    cmp dword ptr [rax + WCS_refs], 2
    jne wm_fail
    mov rax, [rip + wm_job1]
    mov edi, [rax + WCJ_fd]
    mov rdx, [rax + WCJ_generation]
    mov esi, POLLOUT
    call on_clip_writable
    mov edi, [rip + wm_pipe1]
    lea rsi, [rip + wm_out]
    mov edx, 256
    SYS SYS_read
    cmp rax, 69
    jne wm_fail
    lea rdi, [rip + wm_out]
    lea rsi, [rip + wm_wire]
    mov edx, 69
    call memeq
    test eax, eax
    jz wm_fail
    mov edi, [rip + wm_pipe1]
    SYS SYS_close
    mov rax, [rip + wm_old]
    cmp dword ptr [rax + WCS_refs], 1
    jne wm_fail
    mov rax, [rip + wm_job2]
    mov edi, [rax + WCJ_fd]
    mov rdx, [rax + WCJ_generation]
    mov esi, POLLOUT
    call on_clip_writable
    mov edi, [rip + wm_pipe2]
    lea rsi, [rip + wm_out]
    mov edx, 256
    SYS SYS_read
    cmp rax, 5
    jne wm_fail
    lea rdi, [rip + wm_out]
    lea rsi, [rip + wm_text]
    mov edx, 5
    call memeq
    test eax, eax
    jz wm_fail
    mov edi, [rip + wm_pipe2]
    SYS SYS_close
    mov rax, [rip + wm_old]
    cmp qword ptr [rax + WCS_state], 0
    jne wm_fail
    cmp qword ptr [rip + wl_send_charge], 3
    jne wm_fail
    # Raw source never serves an unadvertised native representation.
    lea rdi, [rip + wm_pipe1]
    call wm_pipe
    call wm_source
    mov rdi, rax
    mov esi, [rip + wm_pipe1 + 4]
    mov edx, 4
    call wl_send_start
    test eax, eax
    jnz wm_fail
    mov edi, [rip + wm_pipe1]
    lea rsi, [rip + wm_out]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jnz wm_fail
    mov edi, [rip + wm_pipe1]
    SYS SYS_close
    call wm_sources_clean
    # Quota includes native header and segment table, before allocating.
    mov qword ptr [rip + wl_send_charge], WCS_BUDGET - 68
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wl_source_create_native
    test rax, rax
    jnz wm_fail
    mov qword ptr [rip + wl_send_charge], 0
    call wm_cleanup
    EPILOGUE
wm_hold:
    ret
wm_request:
    PROLOGUE
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + app_clip_active_token]
    test rax, rax
    jz wm_fail
    mov [rip + wm_token], rax
    cmp dword ptr [rip + wl_paste_format], 4
    jne wm_fail
    EPILOGUE
# The synthetic compositor receives the actual SCM_RIGHTS pipe writer.
wm_capture_writer:
    PROLOGUE
    lea rdi, [rip + wm_message]
    xor esi, esi
    mov edx, 56
    call memset
    lea rax, [rip + wm_packet]
    mov [rip + wm_iov], rax
    mov qword ptr [rip + wm_iov + 8], 4096
    lea rax, [rip + wm_iov]
    mov [rip + wm_message + 16], rax
    mov qword ptr [rip + wm_message + 24], 1
    lea rax, [rip + wm_control]
    mov [rip + wm_message + 32], rax
    mov qword ptr [rip + wm_message + 40], 24
    mov edi, [rip + wm_socket + 4]
    lea rsi, [rip + wm_message]
    xor edx, edx
    SYS SYS_recvmsg
    test rax, rax
    jle wm_fail
    cmp qword ptr [rip + wm_message + 40], 24
    jne wm_fail
    cmp qword ptr [rip + wm_control], 20
    jne wm_fail
    mov eax, [rip + wm_control + 16]
    mov [rip + wm_writer], eax
    EPILOGUE
wm_write_close:
    PROLOGUE
    mov rdx, rsi
    mov rsi, rdi
    mov edi, [rip + wm_writer]
    call write_all
    mov edi, [rip + wm_writer]
    SYS SYS_close
    EPILOGUE
wm_read:
    mov edi, [rip + wl_paste_fd]
    mov esi, POLLIN
    mov rdx, [rip + wl_paste_generation]
    jmp on_paste_readable
wm_mimes:
    PROLOGUE
    inc qword ptr [rip + wm_stage]
    mov edi, 0x102
    xor esi, esi
    lea rdx, [rip + wm_offer_id]
    mov ecx, 4
    call wl_dispatch
    mov edi, 0x500
    xor esi, esi
    lea rdx, [rip + wm_mime_native]
    mov ecx, 36
    call wl_dispatch
    cmp dword ptr [rip + wl_paste_offer_new_native], 1
    jne wm_fail
    cmp dword ptr [rip + wl_paste_offer_new_mime], 0
    jne wm_fail
    mov edi, 0x500
    xor esi, esi
    lea rdx, [rip + wm_mime_plain]
    mov ecx, 16
    call wl_dispatch
    cmp dword ptr [rip + wl_paste_offer_new_native], 1
    jne wm_fail
    cmp dword ptr [rip + wl_paste_offer_new_mime], 2
    jne wm_fail
    mov edi, 0x102
    mov esi, 5
    lea rdx, [rip + wm_offer_id]
    mov ecx, 4
    call wl_dispatch
    cmp dword ptr [rip + wl_paste_offer_native], 1
    jne wm_fail
    cmp dword ptr [rip + wl_paste_mime], 2
    jne wm_fail
    lea rdi, [rip + wm_mime_native]
    mov esi, 36
    call wl_paste_decode_mime
    cmp eax, 4
    jne wm_fail
    lea rdi, [rip + wm_mime_native]
    mov esi, 40
    call wl_paste_decode_mime
    test eax, eax
    jnz wm_fail
    lea rdi, [rip + wm_packet]
    lea rsi, [rip + wm_mime_native]
    mov edx, 36
    call memcpy
    mov byte ptr [rip + wm_packet + 35], 1
    lea rdi, [rip + wm_packet]
    mov esi, 36
    call wl_paste_decode_mime
    test eax, eax
    jnz wm_fail
    mov dword ptr [rip + wl_paste_wire_output_len], 0
    EPILOGUE
wm_foreign:
    PROLOGUE
    inc qword ptr [rip + wm_stage]
    mov edi, [rip + wl_paste_wire_fd]
    SYS SYS_close
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | O_CLOEXEC
    xor edx, edx
    lea r10, [rip + wm_socket]
    SYS 53
    test rax, rax
    js wm_fail
    mov eax, [rip + wm_socket]
    mov [rip + wl_paste_wire_fd], eax
    mov dword ptr [rip + wl_paste_offer], 0x500
    mov dword ptr [rip + wl_paste_mime], 1
    mov dword ptr [rip + wl_paste_offer_native], 1
    inc qword ptr [rip + wl_paste_offer_generation]
    lea rdi, [rip + wm_bar]
    mov esi, 1
    call wm_document
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wm_pairs]
    mov edx, 2
    xor ecx, ecx
    call doc_selections_set
    cmp eax, 1
    jne wm_fail
    call wm_request
    call wm_capture_writer
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wm_write_close
    call wm_read
    call wm_read
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    lea rdi, [rip + wm_spread]
    mov esi, 5
    call wm_check
    call wm_cleanup
    # Invalid native data retries plain once on the same token and a fresh generation.
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    mov rax, [rip + wm_doc]
    mov qword ptr [rax + DOC_cur], 3
    mov qword ptr [rax + DOC_anchor], 0
    call wm_request
    mov rax, [rip + wl_paste_generation]
    mov [rip + wm_generation], rax
    mov eax, [rip + wl_paste_fd]
    mov [rip + wm_old_fd], rax
    call wm_capture_writer
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_write_close
    call wm_read
    call wm_read
    cmp dword ptr [rip + wl_paste_format], 1
    jne wm_fail
    mov rax, [rip + wm_token]
    cmp rax, [rip + app_clip_active_token]
    jne wm_fail
    cmp rax, [rip + wl_paste_token]
    jne wm_fail
    mov rax, [rip + wm_generation]
    cmp rax, [rip + wl_paste_generation]
    je wm_fail
    mov edi, [rip + wm_old_fd]
    mov rdx, rax
    mov esi, POLLIN
    call on_paste_readable
    call wm_capture_writer
    lea rdi, [rip + wm_line]
    mov esi, 2
    call wm_write_close
    call wm_read
    call wm_read
    lea rdi, [rip + wm_line]
    mov esi, 2
    call wm_check
    call wm_cleanup
    # Numeric offer ID reuse never grants fallback to a different selection.
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    call wm_request
    call wm_capture_writer
    inc qword ptr [rip + wl_paste_offer_generation]
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_write_close
    call wm_read
    call wm_read
    cmp dword ptr [rip + wl_paste_fd], -1
    jne wm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_check
    call wm_cleanup
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    call wm_request
    call wm_capture_writer
    mov qword ptr [rip + wl_paste_deadline], 0
    call wm_read
    cmp dword ptr [rip + wl_paste_fd], -1
    jne wm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    mov edi, [rip + wm_writer]
    SYS SYS_close
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_check
    call wm_cleanup
    # Format caps and focus invalidation are independent of payload headers.
    inc qword ptr [rip + wm_stage]
    mov dword ptr [rip + wl_paste_format], 4
    call wl_paste_limit
    cmp rax, CLW_MAX
    jne wm_fail
    mov dword ptr [rip + wl_paste_format], 1
    call wl_paste_limit
    cmp rax, 67108864
    jne wm_fail
    mov dword ptr [rip + wl_paste_format], 0
    mov rbx, [rip + wl_paste_offer_generation]
    call wl_paste_offer_clear
    cmp dword ptr [rip + wl_paste_offer], 0
    jne wm_fail
    cmp dword ptr [rip + wl_paste_mime], 0
    jne wm_fail
    cmp dword ptr [rip + wl_paste_offer_native], 0
    jne wm_fail
    inc rbx
    cmp rbx, [rip + wl_paste_offer_generation]
    jne wm_fail
    mov dword ptr [rip + wl_paste_wire_output_len], 0
    mov edi, [rip + wm_socket]
    SYS SYS_close
    mov edi, [rip + wm_socket + 4]
    SYS SYS_close
    EPILOGUE
# Exact native overhead is accepted; a following byte is rejected by the probe.
wm_limits:
    PROLOGUE
    inc qword ptr [rip + wm_stage]
    mov edi, CLW_MAX + 1
    call mem_alloc
    mov [rip + wm_large], rax
    mov rcx, CLW_MAGIC
    mov [rax], rcx
    mov dword ptr [rax + 8], 1
    mov qword ptr [rax + 16], DOC_SELECTIONS_MAX
    mov qword ptr [rax + 24], 67108864
    mov rdi, rax
    mov esi, CLW_MAX
    call wl_source_create_native
    test rax, rax
    jz wm_fail
    mov dword ptr [rax + WCS_id], 0x600
    cmp qword ptr [rip + wl_send_charge], CLW_MAX
    jne wm_fail
    mov rdi, [rip + wm_large]
    mov esi, CLW_MAX
    call wl_source_create_native
    test rax, rax
    jnz wm_fail
    call wm_sources_clean
    xor r15d, r15d
1:  lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    lea rax, [rip + wm_hold]
    mov [rip + g_plat + P_clip_get], rax
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    # Change the destination after capture so a valid maximum transfer is consumed as stale.
    mov rax, [rip + wm_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    lea rdi, [rip + wm_name]
    xor esi, esi
    SYS SYS_memfd_create
    test eax, eax
    js wm_fail
    mov [rip + wm_large_fd], eax
    mov edi, eax
    mov rsi, [rip + wm_large]
    mov edx, CLW_MAX
    add rdx, r15
    call write_all
    mov edi, [rip + wm_large_fd]
    xor esi, esi
    xor edx, edx
    SYS SYS_lseek
    mov edi, [rip + wm_large_fd]
    call wl_paste_receive_fd
    cmp eax, 1
    jne wm_fail
    mov dword ptr [rip + wl_paste_format], 4
    mov r14d, 1100
2:  call wm_read
    dec r14d
    jz wm_fail
    cmp dword ptr [rip + wl_paste_fd], -1
    jne 2b
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_check
    # This input allocation spans both cases and is deliberately still live.
    inc qword ptr [rip + wm_live]
    call wm_cleanup
    dec qword ptr [rip + wm_live]
    inc r15
    cmp r15, 2
    jb 1b
    mov rdi, [rip + wm_large]
    call mem_free
    mov rax, [rip + wm_live]
    cmp rax, [rip + g_mem_live]
    jne wm_fail
    lea rax, [rip + wl_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + wm_stage], 1
    mov edi, 13
    lea rsi, [rip + wm_signal]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    lea rdi, [rip + wm_name]
    xor esi, esi
    SYS SYS_memfd_create
    test eax, eax
    js wm_fail
    mov [rip + wl_paste_wire_fd], eax
    mov dword ptr [rip + wl_send_manager], 0x101
    mov dword ptr [rip + wl_paste_device], 0x102
    mov dword ptr [rip + wl_send_serial_known], 1
    mov dword ptr [rip + wl_wire_next_id], 0x200
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    lea rax, [rip + wl_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    mov rax, [rip + g_mem_live]
    mov [rip + wm_live], rax
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wl_clip_write
    cmp eax, 1
    jne wm_fail
    call wm_source
    test rax, rax
    jz wm_fail
    mov [rip + wm_old], rax
    mov rdi, [rax + WCS_wire]
    test rdi, rdi
    jz wm_fail
    lea rcx, [rdi + 64]
    cmp rcx, [rax + WCS_ptr]
    jne wm_fail
    cmp qword ptr [rax + WCS_len], 5
    jne wm_fail
    cmp qword ptr [rax + WCS_wirelen], 69
    jne wm_fail
    cmp qword ptr [rax + WCS_charge], 69
    jne wm_fail
    cmp qword ptr [rip + wl_send_charge], 69
    jne wm_fail
    lea rsi, [rip + wm_wire]
    mov edx, 69
    call memeq
    test eax, eax
    jz wm_fail
    call wm_source
    lea rdi, [rip + wm_snapshot]
    mov rsi, rax
    mov edx, WCS_SIZE
    call memcpy
    # Invalid input and unavailable publication preserve every source field.
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_wire]
    mov esi, 68
    call wl_clip_write
    test eax, eax
    jnz wm_fail
    call wm_same
    mov dword ptr [rip + wl_send_serial_known], 0
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wl_clip_write
    test eax, eax
    jnz wm_fail
    call wm_same
    mov dword ptr [rip + wl_send_serial_known], 1
    # Native and raw aliases are copied before retiring their source.
    inc qword ptr [rip + wm_stage]
    call wm_source
    mov rdi, [rax + WCS_wire]
    mov rsi, [rax + WCS_wirelen]
    call wl_clip_write
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + wm_old]
    mov edi, [rax + WCS_id]
    call wl_source_deleted
    call wm_source
    mov [rip + wm_old], rax
    mov rdi, [rax + WCS_ptr]
    mov rsi, [rax + WCS_len]
    call wl_clip_set
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + wm_old]
    mov edi, [rax + WCS_id]
    call wl_source_deleted
    call wm_source
    cmp qword ptr [rax + WCS_wire], 0
    jne wm_fail
    cmp qword ptr [rip + wl_send_charge], 5
    jne wm_fail
    mov rdi, [rax + WCS_ptr]
    lea rsi, [rip + wm_text]
    mov edx, 5
    call memeq
    test eax, eax
    jz wm_fail
    call wm_cleanup
    # A foreign native line flag is authoritative over local raw cache.
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    mov rax, [rip + wm_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    lea rdi, [rip + wm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call wm_publish
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    lea rdi, [rip + wm_line_result]
    mov esi, 5
    call wm_check
    call wm_cleanup
    # Multiple pieces distribute through the real self-read and shared delivery.
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_bar]
    mov esi, 1
    call wm_document
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wm_pairs]
    mov edx, 2
    xor ecx, ecx
    call doc_selections_set
    cmp eax, 1
    jne wm_fail
    lea rdi, [rip + wm_wire]
    mov esi, 69
    call wl_clip_write
    cmp eax, 1
    jne wm_fail
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    lea rdi, [rip + wm_spread]
    mov esi, 5
    call wm_check
    call wm_cleanup
    call wm_sender
    call wm_mimes
    call wm_foreign
    call wm_limits
    mov edi, 1
    lea rsi, [rip + wm_ok]
    mov edx, WM_OK_LEN
    call write_all
    xor edi, edi
    call sys_exit
