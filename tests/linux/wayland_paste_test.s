# Production Wayland receiver with real pipes and strict counted transfer state.
.include "rhun.inc"
.section .rodata
wp_initial: .ascii "original"
wp_text: .byte 0xc3,0xa9,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80,0,0x7a
wp_name: .asciz "rhun-wayland-paste"
wp_ok: .ascii "ok Wayland bounded clipboard receiver\n"
.bss
.p2align 3
wp_stage: .quad 0
wp_doc: .quad 0
wp_sn: .quad 0
wp_doc_snapshot: .quad 0
wp_sn_snapshot: .quad 0
wp_live: .quad 0
wp_copy: .zero 64
wp_mime_packet: .zero 64
.text
wp_fail:
    mov edi, [rip + wp_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  SYS SYS_exit_group
wp_assert_same:
    PROLOGUE
    mov rdi, [rip + wp_doc]
    mov rsi, [rip + wp_doc_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz wp_fail
    mov rdi, [rip + wp_sn]
    mov rsi, [rip + wp_sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz wp_fail
    EPILOGUE

wp_setup:
    PROLOGUE
    inc qword ptr [rip + wp_stage]
    mov rax, [rip + g_mem_live]
    mov [rip + wp_live], rax
    call doc_new
    mov [rip + wp_doc], rax
    mov [rip + g_doc], rax
    mov rbx, rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + wp_initial]
    mov ecx, 8
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 8
    lea rdx, [rip + wp_initial]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + wp_initial]
    mov esi, 8
    call snippet_new
    mov [rip + wp_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 8
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + wp_sn]
    call snippet_validate
    cmp eax, 1
    jne wp_fail
    mov rdi, rbx
    mov rsi, [rip + wp_sn]
    xor edx, edx
    call snippet_attach
    mov qword ptr [rbx + DOC_cur], 8
    mov qword ptr [rbx + DOC_anchor], 0
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + wp_doc_snapshot], rax
    mov rdi, [rip + wp_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + wp_sn_snapshot], rax
    mov dword ptr [rip + g_dirty], 0
    mov dword ptr [rip + wl_paste_source_id], 0
    EPILOGUE

# Verify complete counted document contents, including NUL. No doc scratch allocation.
wp_text_check:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + wp_doc]
    call doc_len
    cmp rax, r13
    jne wp_fail
    mov rdi, [rip + wp_doc]
    xor esi, esi
    mov rdx, r13
    lea rcx, [rip + wp_copy]
    call doc_copy
    lea rdi, [rip + wp_copy]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jz wp_fail
    EPILOGUE

wp_cleanup:
    PROLOGUE
    cmp dword ptr [rip + wl_paste_fd], -1
    jne wp_fail
    cmp qword ptr [rip + wl_paste_deadline], 0
    jne wp_fail
    cmp qword ptr [rip + wl_paste_buffer + SB_ptr], 0
    jne wp_fail
    mov rdi, [rip + wp_doc_snapshot]
    call mem_free
    mov rdi, [rip + wp_sn_snapshot]
    call mem_free
    mov rdi, [rip + wp_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + wp_live]
    cmp rax, [rip + g_mem_live]
    jne wp_fail
    EPILOGUE

# Fresh pipe -> read fd eax, write fd edx; constructor consumes the read end.
wp_pipe:
    PROLOGUE 16
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js wp_fail
    mov edi, [rsp]
    call wl_paste_receive_fd
    cmp eax, 1
    jne wp_fail
    mov eax, [rsp]
    mov edx, [rsp + 4]
    EPILOGUE
wp_read:
    mov edi, [rip + wl_paste_fd]
    mov esi, POLLIN
    mov rdx, [rip + wl_paste_generation]
    jmp on_paste_readable
wp_close:
    SYS SYS_close
    test rax, rax
    js wp_fail
    ret

# Read a regular test file until EOF (also used for exact64MiB/probe boundary cases).
wp_drain:
    PROLOGUE
    mov ebx, 1100
1:  cmp dword ptr [rip + wl_paste_fd], -1
    je 2f
    call wp_read
    dec ebx
    jnz 1b
    jmp wp_fail
2:  EPILOGUE

wp_sparse:
    PROLOGUE
    mov r12, rdi
    lea rdi, [rip + wp_name]
    mov esi, 1
    mov eax, 319
    XSYS
    test eax, eax
    js wp_fail
    mov ebx, eax
    mov edi, eax
    mov rsi, r12
    SYS SYS_ftruncate
    test rax, rax
    js wp_fail
    mov edi, ebx
    call wl_paste_receive_fd
    cmp eax, 1
    jne wp_fail
    EPILOGUE

FN main
    PROLOGUE 64
    call wp_setup
    call wp_pipe
    mov r14d, eax
    mov ebx, edx
    # Only the read endpoint is nonblocking; the foreign owner retains a blocking pipe.
    mov edi, r14d
    mov esi, 3
    SYS SYS_fcntl
    test eax, O_NONBLOCK
    jz wp_fail
    mov edi, ebx
    mov esi, 3
    SYS SYS_fcntl
    test eax, O_NONBLOCK
    jnz wp_fail
    call wl_paste_tick
    cmp r14d, [rip + wl_paste_fd]
    jne wp_fail
    mov r15, [rip + wl_paste_deadline]
    call wp_read                  # Real EAGAIN must keep the empty transfer alive.
    cmp r14d, [rip + wl_paste_fd]
    jne wp_fail
    cmp r15, [rip + wl_paste_deadline]
    jne wp_fail
    call wp_assert_same
    mov edi, ebx
    lea rsi, [rip + wp_text]
    mov edx, 1
    call write_all
    call wp_read
    cmp qword ptr [rip + wl_paste_buffer + SB_len], 1
    jne wp_fail
    mov r15, [rip + wl_paste_deadline]
    mov edi, r14d
    mov rsi, -EINTR
    xor edx, edx
    call wl_paste_read_result
    cmp r15, [rip + wl_paste_deadline]
    jne wp_fail
    call wp_assert_same
    # Remaining bytes complete a codepoint split across reads, and preserve counted NUL.
    mov edi, ebx
    lea rsi, [rip + wp_text + 1]
    mov edx, 10
    call write_all
    call wp_read
    call wp_assert_same
    mov edi, ebx
    call wp_close
    call wp_read
    lea rdi, [rip + wp_text]
    mov esi, 11
    call wp_text_check
    mov rdi, [rip + wp_doc]
    call doc_undo
    lea rdi, [rip + wp_initial]
    mov esi, 8
    call wp_text_check
    mov rdi, [rip + wp_doc]
    call doc_redo
    lea rdi, [rip + wp_text]
    mov esi, 11
    call wp_text_check
    call wp_cleanup

    # Empty EOF is an actual delivery that cannot change document/snippet history.
    call wp_setup
    call wp_pipe
    mov edi, edx
    call wp_close
    call wp_read
    cmp dword ptr [rip + g_dirty], 1
    jne wp_fail
    call wp_assert_same
    call wp_cleanup

    # Invalid terminal UTF8 and permanent read errors reject a valid prefix atomically.
    xor r15d, r15d
.Lwp_reject:
    call wp_setup
    call wp_pipe
    mov ebx, edx
    mov edi, ebx
    lea rsi, [rip + wp_initial]
    mov edx, 8
    call write_all
    call wp_read
    test r15d, r15d
    jnz 1f
    mov edi, ebx
    lea rsi, [rip + wp_bad_utf8]
    mov edx, 1
    call write_all
    mov edi, ebx
    call wp_close
    call wp_read
    call wp_read
    jmp 2f
1:  cmp r15d, 1
    jne 3f
    mov edi, [rip + wl_paste_fd]
    call wp_close
    call wp_read                  # Real EBADF, not success EOF.
    jmp 4f
3:  mov edi, [rip + wl_paste_fd]
    mov rsi, -5                   # Permanent EIO result after already received bytes.
    xor edx, edx
    call wl_paste_read_result
4:  mov edi, ebx
    call wp_close
2:  cmp dword ptr [rip + g_dirty], 0
    jne wp_fail
    call wp_assert_same
    call wp_cleanup
    inc r15d
    cmp r15d, 3
    jne .Lwp_reject

    # Busy new descriptors close, while aliasing the active descriptor cannot close it.
    call wp_setup
    call wp_pipe
    mov r14d, eax
    mov ebx, edx
    mov edi, r14d
    call wl_paste_receive_fd
    test eax, eax
    jnz wp_fail
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js wp_fail
    mov edi, [rsp]
    call wl_paste_receive_fd
    test eax, eax
    jnz wp_fail
    mov edi, [rsp]
    mov esi, 3
    SYS SYS_fcntl
    cmp rax, -9
    jne wp_fail
    mov edi, [rsp + 4]
    call wp_close
    cmp r14d, [rip + wl_paste_fd]
    jne wp_fail
    mov edi, r14d
    mov esi, 3
    SYS SYS_fcntl
    test rax, rax
    js wp_fail
    call wl_paste_cancel
    mov edi, ebx
    call wp_close
    call wp_assert_same
    call wp_cleanup

    # Stale watcher generation cannot read or finish the active transfer.
    call wp_setup
    call wp_pipe
    mov ebx, edx
    mov edi, [rip + wl_paste_fd]
    mov esi, POLLIN
    mov rdx, [rip + wl_paste_generation]
    dec rdx
    call on_paste_readable
    cmp qword ptr [rip + wl_paste_buffer + SB_ptr], 0
    jne wp_fail
    call wl_paste_cancel
    mov edi, ebx
    call wp_close
    call wp_cleanup

    # Ready positive data and EOF after expiry must not revive a transfer before tick.
    xor r15d, r15d
.Lwp_expired:
    call wp_setup
    call wp_pipe
    mov ebx, edx
    test r15d, r15d
    jnz 1f
    mov edi, ebx
    lea rsi, [rip + wp_initial]
    mov edx, 8
    call write_all
    jmp 2f
1:  mov edi, ebx
    call wp_close
2:  mov qword ptr [rip + wl_paste_deadline], 1
    call wp_read
    cmp dword ptr [rip + g_dirty], 0
    jne wp_fail
    test r15d, r15d
    jnz 3f
    mov edi, ebx
    call wp_close
3:  call wp_assert_same
    call wp_cleanup
    inc r15d
    cmp r15d, 2
    jne .Lwp_expired

    call wp_setup
    call wp_pipe
    mov ebx, edx
    mov qword ptr [rip + wl_paste_deadline], 1
    call wl_paste_timeout
    test eax, eax
    jnz wp_fail
    call wl_paste_tick
    call wl_paste_tick
    mov edi, ebx
    call wp_close
    call wp_assert_same
    call wp_cleanup

    # Exact budget succeeds, a single extra byte is rejected by the probe.
    xor r15d, r15d
.Lwp_limit:
    call wp_setup
    lea rdi, [r15 + 67108864]
    call wp_sparse
    call wp_drain
    test r15d, r15d
    jnz .Lwp_limit_rejected
    mov rdi, [rip + wp_doc]
    call doc_len
    cmp rax, 67108864
    jne wp_fail
    mov rdi, [rip + wp_doc]
    xor esi, esi
    mov edx, 32
    lea rcx, [rip + wp_copy]
    call doc_copy
    lea rdi, [rip + wp_copy]
    xor r12d, r12d
1:  cmp byte ptr [rdi + r12], 0
    jne wp_fail
    inc r12d
    cmp r12d, 32
    jb 1b
    mov rdi, [rip + wp_doc]
    call doc_undo
    lea rdi, [rip + wp_initial]
    mov esi, 8
    call wp_text_check
    mov rdi, [rip + wp_doc]
    call doc_redo
    mov rdi, [rip + wp_doc]
    call doc_len
    cmp rax, 67108864
    jne wp_fail
    jmp .Lwp_limit_clean
.Lwp_limit_rejected:
    cmp dword ptr [rip + g_dirty], 0
    jne wp_fail
    call wp_assert_same
.Lwp_limit_clean:
    call wp_cleanup
    inc r15d
    cmp r15d, 2
    jne .Lwp_limit

    # Checked registration rejects at capacity and closes only the newly supplied pipe.
    call wp_setup
    xor r12d, r12d
.Lwp_fill_watches:
    lea edi, [r12 + 10000]
    mov esi, POLLIN
    lea rdx, [rip + wp_nop]
    xor ecx, ecx
    call watch_try_add
    cmp eax, 1
    jne wp_fail
    inc r12d
    cmp r12d, MAX_WATCH
    jb .Lwp_fill_watches
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js wp_fail
    mov edi, [rsp]
    call wl_paste_receive_fd
    test eax, eax
    jnz wp_fail
    mov edi, [rsp]
    mov esi, 3
    SYS SYS_fcntl
    cmp rax, -9
    jne wp_fail
    mov edi, [rsp + 4]
    call wp_close
    call wp_assert_same
    call wp_cleanup
    xor r12d, r12d
.Lwp_remove_watches:
    lea edi, [r12 + 10000]
    call watch_remove
    inc r12d
    cmp r12d, MAX_WATCH
    jb .Lwp_remove_watches

    # MIME selection retains the best actually offered type independent of order.
    call wp_setup
    mov dword ptr [rip + wl_paste_device], 0x400
    mov dword ptr [rip + wp_mime_packet], 0x500
    mov edi, 0x400
    xor esi, esi
    lea rdx, [rip + wp_mime_packet]
    mov ecx, 4
    call wl_dispatch
    lea rdi, [rip + wp_plain]
    mov esi, 11
    call wp_offer
    cmp dword ptr [rip + wl_paste_offer_new_mime], 2
    jne wp_fail
    lea rdi, [rip + wp_string]
    mov esi, 12
    call wp_offer
    cmp dword ptr [rip + wl_paste_offer_new_mime], 2
    jne wp_fail
    lea rdi, [rip + wp_utf8]
    mov esi, 25
    call wp_offer
    cmp dword ptr [rip + wl_paste_offer_new_mime], 1
    jne wp_fail
    mov dword ptr [rip + wp_mime_packet], 0x500
    mov edi, 0x400
    mov esi, 5
    lea rdx, [rip + wp_mime_packet]
    mov ecx, 4
    call wl_dispatch
    cmp dword ptr [rip + wl_paste_mime], 1
    jne wp_fail
    # Malformed lengths, absent NUL and unsupported strings never read out of their span.
    mov dword ptr [rip + wp_mime_packet], 0xffffffff
    lea rdi, [rip + wp_mime_packet]
    mov esi, 8
    call wl_paste_decode_mime
    test eax, eax
    jnz wp_fail
    mov dword ptr [rip + wp_mime_packet], 1
    mov byte ptr [rip + wp_mime_packet + 4], 0x41
    lea rdi, [rip + wp_mime_packet]
    mov esi, 8
    call wl_paste_decode_mime
    test eax, eax
    jnz wp_fail
    mov dword ptr [rip + wl_paste_offer_new_mime], 0
    lea rdi, [rip + wp_unsupported]
    mov esi, 10
    call wp_offer
    cmp dword ptr [rip + wl_paste_offer_new_mime], 0
    jne wp_fail
    call wp_assert_same
    call wp_cleanup

    # Local paste is counted, and cannot override a busy incoming transfer.
    call wp_setup
    lea rdi, [rip + wl_paste_source_buffer]
    lea rsi, [rip + wp_text]
    mov edx, 11
    call sb_push
    mov dword ptr [rip + wl_paste_source_id], 1
    call wl_clip_get
    lea rdi, [rip + wl_paste_source_buffer]
    call sb_free
    lea rdi, [rip + wp_text]
    mov esi, 11
    call wp_text_check
    call wp_cleanup
    call wp_setup
    call wp_pipe
    mov ebx, edx
    mov dword ptr [rip + wl_paste_source_id], 1
    call wl_clip_get
    call wp_assert_same
    cmp dword ptr [rip + g_dirty], 0
    jne wp_fail
    call wl_paste_cancel
    mov edi, ebx
    call wp_close
    call wp_cleanup
    mov edi, 1
    lea rsi, [rip + wp_ok]
    mov edx, 38
    call write_all
    xor edi, edi
    SYS SYS_exit_group
wp_nop:
    ret

# Encode and dispatch one real counted/padded offer event.
wp_offer:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + wp_mime_packet]
    xor esi, esi
    mov edx, 64
    call memset
    mov [rip + wp_mime_packet], r12d
    lea rdi, [rip + wp_mime_packet + 4]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov edi, 0x500
    xor esi, esi
    lea rdx, [rip + wp_mime_packet]
    lea rcx, [r12 + 3]
    and rcx, -4
    add rcx, 4
    call wl_dispatch
    EPILOGUE
.section .rodata
wp_bad_utf8: .byte 0xff
wp_plain: .asciz "text/plain"
wp_string: .asciz "UTF8_STRING"
wp_utf8: .asciz "text/plain;charset=utf-8"
wp_unsupported: .asciz "image/png"
