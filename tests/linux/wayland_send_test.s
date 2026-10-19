# Production Wayland sender lifecycle with real pipes and wire descriptors.
.include "rhun.inc"
.include "plat/wayland.inc"
.section .rodata
ws_text: .byte 0xc3,0xa9,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80,0,0x7a
ws_other: .ascii "new copy"
ws_mime: .long 11
    .asciz "text/plain"
    .byte 0
ws_bad_mime: .long 10
    .asciz "image/png"
    .zero 2
ws_name: .asciz "rhun-wayland-send"
ws_ok: .ascii "ok Wayland bounded clipboard sender\n"
.equ ws_ok_len, . - ws_ok
.bss
.p2align 3
ws_stage: .quad 0
ws_live: .quad 0
ws_source: .quad 0
ws_job: .quad 0
ws_old: .quad 0
ws_input: .quad 0
ws_reader: .long 0
ws_writer: .long 0
ws_id: .long 0
ws_event: .zero 64
ws_buffer: .zero 65537
ws_control: .zero 1104
ws_fds: .zero 4 * 260
ws_message: .zero 56
ws_iov: .zero 16
ws_socket: .zero 8
ws_signal: .zero 32
ws_reuse_oldfd: .long 0
ws_reuse_read: .long 0
ws_reuse_write: .long 0
ws_trigger: .zero 8
.text
ws_fail:
    mov edi, [rip + ws_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  SYS SYS_exit_group

ws_new:
    sub rsp, 8
    call wl_source_create
    test rax, rax
    jz ws_fail
    inc dword ptr [rip + ws_id]
    mov ecx, [rip + ws_id]
    mov [rax + WCS_id], ecx
    mov [rip + ws_source], rax
    add rsp, 8
    ret
ws_small:
    lea rdi, [rip + ws_text]
    mov esi, 11
    jmp ws_new

ws_clean:
    PROLOGUE
    lea rbx, [rip + wl_send_jobs]
    mov r12d, WCJ_COUNT
1:  mov rdi, rbx
    call wl_send_cancel
    add rbx, WCJ_SIZE
    dec r12d
    jnz 1b
    lea rbx, [rip + wl_send_sources]
    mov r12d, WCS_COUNT
2:  mov edi, [rbx + WCS_id]
    call wl_source_deleted
    add rbx, WCS_SIZE
    dec r12d
    jnz 2b
    cmp qword ptr [rip + wl_send_charge], 0
    jne ws_fail
    mov rax, [rip + ws_live]
    cmp rax, [rip + g_mem_live]
    jne ws_fail
    mov dword ptr [rip + wl_paste_wire_output_len], 0
    inc qword ptr [rip + ws_stage]
    EPILOGUE

ws_pipe:
    PROLOGUE 16
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js ws_fail
    mov eax, [rsp]
    mov [rip + ws_reader], eax
    mov eax, [rsp + 4]
    mov [rip + ws_writer], eax
    EPILOGUE
ws_start:
    sub rsp, 8
    mov rdi, [rip + ws_source]
    mov esi, [rip + ws_writer]
    mov edx, 1
    call wl_send_start
    cmp eax, 1
    jne ws_fail
    mov edi, [rip + ws_writer]
    call wl_send_find
    mov [rip + ws_job], rax
    add rsp, 8
    ret
ws_write:
    mov rax, [rip + ws_job]
    mov edi, [rax + WCJ_fd]
    mov rdx, [rax + WCJ_generation]
    mov esi, POLLOUT
    jmp on_clip_writable
ws_close:
    SYS SYS_close
    test rax, rax
    js ws_fail
    ret
ws_closed:
    mov esi, 3
    SYS SYS_fcntl
    cmp rax, -9
    jne ws_fail
    ret
ws_reader_close:
    mov edi, [rip + ws_reader]
    jmp ws_close
ws_result:
    mov rax, [rip + ws_job]
    mov edi, [rax + WCJ_fd]
    mov rsi, [rax + WCJ_generation]
    jmp wl_send_write_result
ws_read_text:
    PROLOGUE
    mov edi, [rip + ws_reader]
    lea rsi, [rip + ws_buffer]
    mov edx, 32
    SYS SYS_read
    cmp rax, 11
    jne ws_fail
    lea rdi, [rip + ws_buffer]
    lea rsi, [rip + ws_text]
    mov edx, 11
    call memeq
    test eax, eax
    jz ws_fail
    mov edi, [rip + ws_reader]
    lea rsi, [rip + ws_buffer]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jnz ws_fail
    call ws_reader_close
    EPILOGUE

# One real SCM_RIGHTS message, used directly and over an actual socketpair.
ws_fd_packet:
    mov qword ptr [rip + ws_control], 20
    mov dword ptr [rip + ws_control + 8], SOL_SOCKET
    mov dword ptr [rip + ws_control + 12], SCM_RIGHTS
    mov [rip + ws_control + 16], edi
    ret
ws_collect:
    sub rsp, 8
    call ws_fd_packet
    lea rdi, [rip + ws_control]
    mov esi, 24
    xor edx, edx
    call wl_collect_fds
    cmp eax, 1
    jne ws_fail
    add rsp, 8
    ret

FN main
    PROLOGUE 64
    mov rax, [rip + g_mem_live]
    mov [rip + ws_live], rax
    mov dword ptr [rip + ws_id], 0x500
    mov dword ptr [rip + wl_wire_next_id], 0x800
    mov qword ptr [rip + ws_stage], 1
    mov qword ptr [rip + ws_signal], 1
    mov edi, 13
    lea rsi, [rip + ws_signal]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    test rax, rax
    js ws_fail
    # Owned counted bytes and endpoint flags, exact EOF, idempotent retirement.
    call ws_small
    call ws_pipe
    call ws_start
    mov edi, [rip + ws_reader]
    mov esi, 3
    SYS SYS_fcntl
    test eax, O_NONBLOCK
    jnz ws_fail
    mov edi, [rip + ws_writer]
    mov esi, 3
    SYS SYS_fcntl
    test eax, O_NONBLOCK
    jz ws_fail
    call ws_write
    mov rax, [rip + ws_source]
    cmp dword ptr [rax + WCS_refs], 0
    jne ws_fail
    call ws_read_text
    mov rdi, [rip + ws_job]
    call wl_send_cancel
    call ws_clean

    # Empty transfer is owned EOF without a watch/ref allocation.
    xor edi, edi
    xor esi, esi
    call ws_new
    call ws_pipe
    call ws_start
    cmp qword ptr [rip + ws_job], 0
    jne ws_fail
    mov edi, [rip + ws_writer]
    call ws_closed
    mov edi, [rip + ws_reader]
    lea rsi, [rip + ws_buffer]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jnz ws_fail
    call ws_reader_close
    call ws_clean

    # Full pipe: actual EAGAIN, injected EINTR/EAGAIN, no false progress/deadline.
    call ws_small
    call ws_pipe
    call ws_start
    mov rax, [rip + ws_job]
    mov r12, [rax + WCJ_deadline]
.Lws_fill:
    mov edi, [rip + ws_writer]
    lea rsi, [rip + ws_buffer]
    mov edx, 4096
    SYS SYS_write
    cmp rax, -EAGAIN
    je 1f
    test rax, rax
    jle ws_fail
    jmp .Lws_fill
1:  call ws_write
    mov rdx, -EINTR
    call ws_result
    mov rdx, -EAGAIN
    call ws_result
    mov rax, [rip + ws_job]
    cmp [rax + WCJ_deadline], r12
    jne ws_fail
    cmp qword ptr [rax + WCJ_offset], 0
    jne ws_fail
    cmp dword ptr [rax + WCJ_active], 1
    jne ws_fail
    mov rdi, rax
    call wl_send_cancel
    call ws_reader_close
    call ws_clean

    # Broken reader and ordinary permanent error release only the job.
    call ws_small
    call ws_pipe
    call ws_start
    call ws_reader_close
    call ws_write
    mov rax, [rip + ws_job]
    cmp dword ptr [rax + WCJ_active], 0
    jne ws_fail
    call ws_pipe
    call ws_start
    mov rdx, -EIO
    call ws_result
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    call ws_clean

    # Late callbacks/results cannot refresh expired jobs, including apparent EOF progress.
    call ws_small
    xor r15d, r15d
.Lws_expired:
    call ws_pipe
    call ws_start
    mov rax, [rip + ws_job]
    mov qword ptr [rax + WCJ_deadline], 1
    call wl_send_timeout
    test eax, eax
    jnz ws_fail
    test r15d, r15d
    jnz 1f
    call ws_write
    jmp 2f
1:  mov edx, 11
    call ws_result
2:  mov edi, [rip + ws_writer]
    call ws_closed
    mov edi, [rip + ws_reader]
    lea rsi, [rip + ws_buffer]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jnz ws_fail
    call ws_reader_close
    call wl_send_tick
    inc r15d
    cmp r15d, 2
    jb .Lws_expired
    call ws_clean

    # Two readers keep old bytes across retirement, delete_id and numeric ID reuse.
    call ws_small
    mov [rip + ws_old], rax
    call ws_pipe
    call ws_start
    mov r12, [rip + ws_job]
    mov r13d, [rip + ws_reader]
    call ws_pipe
    call ws_start
    mov r14, [rip + ws_job]
    mov r15d, [rip + ws_reader]
    mov rdi, [rip + ws_old]
    call wl_source_retire
    mov rax, [rip + ws_old]
    mov ebx, [rax + WCS_id]
    mov edi, ebx
    call wl_source_deleted
    mov rax, [rip + ws_old]
    cmp dword ptr [rax + WCS_state], 3
    jne ws_fail
    lea rdi, [rip + ws_other]
    mov esi, 8
    call ws_new
    mov [rax + WCS_id], ebx
    mov edi, ebx
    call wl_source_find
    cmp rax, [rip + ws_source]
    jne ws_fail
    mov [rip + ws_job], r12
    mov [rip + ws_reader], r13d
    call ws_write
    call ws_read_text
    mov [rip + ws_job], r14
    mov [rip + ws_reader], r15d
    call ws_write
    call ws_read_text
    mov rax, [rip + ws_old]
    cmp dword ptr [rax + WCS_state], 0
    jne ws_fail
    call ws_clean

    # Old generation does not operate on a replacement job in the same slot.
    call ws_small
    call ws_pipe
    call ws_start
    mov rax, [rip + ws_job]
    mov r12, [rax + WCJ_generation]
    mov rdi, rax
    call wl_send_cancel
    call ws_reader_close
    call ws_pipe
    call ws_start
    mov edi, [rip + ws_writer]
    mov esi, POLLERR
    mov rdx, r12
    call on_clip_writable
    mov rax, [rip + ws_job]
    cmp qword ptr [rax + WCJ_offset], 0
    jne ws_fail
    cmp dword ptr [rax + WCJ_active], 1
    jne ws_fail
    call ws_write
    call ws_read_text
    call ws_clean

    call ws_more
    call ws_clean
    mov edi, 1
    lea rsi, [rip + ws_ok]
    mov edx, ws_ok_len
    call write_all
    xor edi, edi
    SYS SYS_exit_group

ws_more:
    PROLOGUE
    # Every full-slot rejection closes its fresh FD and preserves existing jobs.
    call ws_small
    xor r12d, r12d
1:  call ws_pipe
    mov eax, [rip + ws_reader]
    lea rdx, [rip + ws_fds]
    mov [rdx + r12*4], eax
    call ws_start
    inc r12d
    cmp r12d, WCJ_COUNT
    jb 1b
    call ws_pipe
    mov rdi, [rip + ws_source]
    mov esi, [rip + ws_writer]
    mov edx, 1
    call wl_send_start
    test eax, eax
    jnz ws_fail
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    mov rax, [rip + ws_source]
    cmp dword ptr [rax + WCS_refs], WCJ_COUNT
    jne ws_fail
    xor r12d, r12d
2:  lea rax, [rip + ws_fds]
    mov edi, [rax + r12*4]
    call ws_close
    inc r12d
    cmp r12d, WCJ_COUNT
    jb 2b
    call ws_clean

    # Watch capacity refusal closes the incoming fd and rolls back its ref/job.
    call ws_small
    xor r12d, r12d
3:  lea edi, [r12 + 10000]
    mov esi, POLLIN
    lea rdx, [rip + ws_nop]
    xor ecx, ecx
    call watch_try_add
    cmp eax, 1
    jne ws_fail
    inc r12d
    cmp r12d, MAX_WATCH
    jb 3b
    call ws_pipe
    mov rdi, [rip + ws_source]
    mov esi, [rip + ws_writer]
    mov edx, 1
    call wl_send_start
    test eax, eax
    jnz ws_fail
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    mov rax, [rip + ws_source]
    cmp dword ptr [rax + WCS_refs], 0
    jne ws_fail
    xor r12d, r12d
4:  lea edi, [r12 + 10000]
    call watch_remove
    inc r12d
    cmp r12d, MAX_WATCH
    jb 4b
    call ws_clean

    # Aliasing Copy snapshots before replacement; failed Copy preserves current state.
    mov dword ptr [rip + wl_send_manager], 0x101
    mov dword ptr [rip + wl_paste_device], 0x102
    mov dword ptr [rip + wl_send_serial_known], 1
    lea rdi, [rip + ws_text]
    mov esi, 11
    call wl_clip_set
    cmp eax, 1
    jne ws_fail
    mov edi, [rip + wl_paste_source_id]
    call wl_source_find
    test rax, rax
    jz ws_fail
    cmp dword ptr [rax + WCS_state], 1
    jne ws_fail
    mov edi, [rip + wl_paste_source_id]
    call wl_source_find
    mov [rip + ws_old], rax
    mov rdi, [rip + wl_paste_source_buffer + SB_ptr]
    mov rsi, [rip + wl_paste_source_buffer + SB_len]
    call wl_clip_set
    cmp eax, 1
    jne ws_fail
    mov rax, [rip + ws_old]
    mov edi, [rax + WCS_id]
    call wl_source_deleted
    mov rdi, [rip + wl_paste_source_buffer + SB_ptr]
    lea rsi, [rip + ws_text]
    mov edx, 11
    call memeq
    test eax, eax
    jz ws_fail
    mov r12d, WCS_COUNT - 1
5:  call ws_small
    dec r12d
    jnz 5b
    mov r13, [rip + wl_paste_source_buffer + SB_ptr]
    mov r14d, [rip + wl_paste_source_id]
    lea rdi, [rip + ws_other]
    mov esi, 8
    call wl_clip_set
    test eax, eax
    jnz ws_fail
    cmp r13, [rip + wl_paste_source_buffer + SB_ptr]
    jne ws_fail
    cmp r14d, [rip + wl_paste_source_id]
    jne ws_fail
    call ws_clean

    # Source limit and aggregate budget are checked before reading/copying beyond input.
    mov edi, 67108864
    call mem_alloc
    mov [rip + ws_input], rax
    inc qword ptr [rip + ws_live]
    mov rdi, rax
    mov esi, 67108865
    call wl_source_create
    test rax, rax
    jnz ws_fail
    mov rdi, [rip + ws_input]
    mov esi, 67108864
    call wl_clip_set
    cmp eax, 1
    jne ws_fail
    mov rdi, [rip + ws_input]
    mov esi, 67108864
    call ws_new
    cmp qword ptr [rip + wl_send_charge], WCS_BUDGET
    jne ws_fail
    mov r12, [rip + wl_paste_source_buffer + SB_ptr]
    lea rdi, [rip + ws_other]
    mov esi, 1
    call wl_clip_set
    test eax, eax
    jnz ws_fail
    cmp r12, [rip + wl_paste_source_buffer + SB_ptr]
    jne ws_fail
    call ws_clean
    mov rdi, [rip + ws_input]
    call mem_free
    dec qword ptr [rip + ws_live]
    xor edi, edi
    mov esi, 1
    call wl_source_create
    test eax, eax
    jnz ws_fail
    mov byte ptr [rip + ws_buffer], 0xff
    lea rdi, [rip + ws_buffer]
    mov esi, 1
    call wl_source_create
    test eax, eax
    jnz ws_fail

    # Each callback writes at most64KiB, even to an always-writable regular file.
    mov edi, 262144
    call mem_alloc
    mov [rip + ws_input], rax
    inc qword ptr [rip + ws_live]
    mov rdi, rax
    lea rsi, [rip + ws_text]
    mov edx, 11
    call memcpy
    mov rdi, [rip + ws_input]
    mov esi, 262144
    call ws_new
    lea rdi, [rip + ws_name]
    mov esi, 1
    mov eax, 319
    XSYS
    test rax, rax
    js ws_fail
    mov [rip + ws_writer], eax
    mov edi, eax
    mov esi, 1030                # F_DUPFD_CLOEXEC
    xor edx, edx
    SYS SYS_fcntl
    test eax, eax
    js ws_fail
    mov [rip + ws_reader], eax
    call ws_start
    call ws_write
    mov rax, [rip + ws_job]
    cmp qword ptr [rax + WCJ_offset], 65536
    jne ws_fail
    mov r12d, 3
6:  call ws_write
    dec r12d
    jnz 6b
    mov edi, [rip + ws_writer]
    call ws_closed
    mov edi, [rip + ws_reader]
    xor esi, esi
    mov edx, 2
    SYS SYS_lseek
    cmp rax, 262144
    jne ws_fail
    mov edi, [rip + ws_reader]
    xor esi, esi
    xor edx, edx
    SYS SYS_lseek
    mov r12d, 4
    xor r13d, r13d
7:  mov edi, [rip + ws_reader]
    lea rsi, [rip + ws_buffer]
    mov edx, 65536
    SYS SYS_read
    cmp rax, 65536
    jne ws_fail
    lea rdi, [rip + ws_buffer]
    mov rsi, [rip + ws_input]
    add rsi, r13
    mov edx, 65536
    call memeq
    test eax, eax
    jz ws_fail
    add r13, 65536
    dec r12d
    jnz 7b
    call ws_reader_close
    call ws_clean
    mov rdi, [rip + ws_input]
    call mem_free
    dec qword ptr [rip + ws_live]
    # Rejected MIME and impossible outcomes close only the supplied job descriptor.
    call ws_small
    call ws_pipe
    mov rdi, [rip + ws_source]
    mov esi, [rip + ws_writer]
    xor edx, edx
    call wl_send_start
    test eax, eax
    jnz ws_fail
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    call ws_pipe
    call ws_start
    mov rdi, [rip + ws_source]
    mov esi, [rip + ws_writer]
    mov edx, 1
    call wl_send_start
    test eax, eax
    jnz ws_fail
    mov edi, [rip + ws_writer]
    mov esi, 3
    SYS SYS_fcntl
    test eax, eax
    js ws_fail
    mov edx, 12                  # greater than all remaining bytes
    call ws_result
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    call ws_pipe
    call ws_start
    xor edx, edx
    call ws_result
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    mov rdi, [rip + ws_source]
    mov esi, -1
    mov edx, 1
    call wl_send_start
    test eax, eax
    jnz ws_fail
    call ws_clean
    call ws_wire_tests
    EPILOGUE
ws_nop:
    ret
ws_wire_tests:
    PROLOGUE 16
    # A queued send for a retired source consumes its own FD and immutable bytes.
    call ws_small
    mov rdi, rax
    call wl_source_retire
    call ws_pipe
    mov edi, [rip + ws_writer]
    call ws_collect
    mov rax, [rip + ws_source]
    mov edi, [rax + WCS_id]
    mov esi, 1
    lea rdx, [rip + ws_mime]
    mov ecx, 16
    call wl_dispatch
    cmp dword ptr [rip + wl_wire_fdqueue_len], 0
    jne ws_fail
    mov edi, [rip + ws_writer]
    call wl_send_find
    test rax, rax
    jz ws_fail
    mov [rip + ws_job], rax
    call ws_write
    call ws_read_text
    call ws_clean

    # Invalid MIME/span closes its descriptor without stealing the next send's FD.
    call ws_small
    call ws_pipe
    mov r12d, [rip + ws_reader]
    mov r13d, [rip + ws_writer]
    mov edi, r13d
    call ws_collect
    call ws_pipe
    mov edi, [rip + ws_writer]
    call ws_collect
    mov rax, [rip + ws_source]
    mov edi, [rax + WCS_id]
    mov esi, 1
    lea rdx, [rip + ws_bad_mime]
    mov ecx, 16
    call wl_dispatch
    mov edi, r13d
    call ws_closed
    cmp dword ptr [rip + wl_wire_fdqueue_len], 1
    jne ws_fail
    mov edi, r12d
    call ws_close
    mov rax, [rip + ws_source]
    mov edi, [rax + WCS_id]
    mov esi, 1
    lea rdx, [rip + ws_mime]
    mov ecx, 12                  # truncated exact string span
    call wl_dispatch
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    cmp dword ptr [rip + wl_wire_fdqueue_len], 0
    jne ws_fail
    call ws_clean

    # SCM_RIGHTS overflow must close all257 delivered descriptors and empty the queue.
    lea rdi, [rip + ws_name]
    mov esi, 1
    mov eax, 319
    XSYS
    test eax, eax
    js ws_fail
    mov r12d, eax
    xor r13d, r13d
1:  mov edi, r12d
    mov esi, 1030
    xor edx, edx
    SYS SYS_fcntl
    test eax, eax
    js ws_fail
    lea rdx, [rip + ws_fds]
    mov [rdx + r13*4], eax
    lea rdx, [rip + ws_control + 16]
    mov [rdx + r13*4], eax
    inc r13d
    cmp r13d, WCF_COUNT + 1
    jb 1b
    mov qword ptr [rip + ws_control], 1044
    mov dword ptr [rip + ws_control + 8], SOL_SOCKET
    mov dword ptr [rip + ws_control + 12], SCM_RIGHTS
    lea rdi, [rip + ws_control]
    mov esi, 1048
    xor edx, edx
    call wl_collect_fds
    test eax, eax
    jnz ws_fail
    cmp dword ptr [rip + wl_wire_fdqueue_len], 0
    jne ws_fail
    xor r13d, r13d
2:  lea rax, [rip + ws_fds]
    mov edi, [rax + r13*4]
    call ws_closed
    inc r13d
    cmp r13d, WCF_COUNT + 1
    jb 2b
    mov edi, r12d
    call ws_close
    call ws_clean

    # Truncated control and an invalid payload length clean every safely installed FD.
    xor r12d, r12d
3:  call ws_pipe
    mov edi, [rip + ws_writer]
    call ws_fd_packet
    lea rdi, [rip + ws_control]
    mov esi, 24
    mov edx, 8                  # MSG_CTRUNC
    test r12d, r12d
    jz 4f
    xor edx, edx
    mov qword ptr [rip + ws_control], 21
4:  call wl_collect_fds
    test eax, eax
    jnz ws_fail
    mov edi, [rip + ws_writer]
    call ws_closed
    call ws_reader_close
    inc r12d
    cmp r12d, 2
    jb 3b
    call ws_clean

    # Seat capability loss retains an old keyboard's keymap FD identity.
    mov dword ptr [rip + wl_wire_keyboard], 0x700
    mov dword ptr [rip + wl_wire_seat], 0x701
    mov dword ptr [rip + wl_wire_seat_version], 3
    mov dword ptr [rip + ws_event], 0
    mov edi, 0x701
    xor esi, esi
    lea rdx, [rip + ws_event]
    mov ecx, 4
    call wl_dispatch
    cmp dword ptr [rip + wl_wire_keyboard], 0
    jne ws_fail
    mov edi, 0x700
    xor esi, esi
    call wl_message_needs_fd
    cmp eax, 1
    jne ws_fail
    call ws_pipe
    mov r12d, [rip + ws_reader]
    mov r13d, [rip + ws_writer]
    mov edi, r13d
    call ws_collect
    call ws_small
    call ws_pipe
    mov edi, [rip + ws_writer]
    call ws_collect
    mov edi, 0x700
    xor esi, esi
    lea rdx, [rip + ws_event]
    mov ecx, 8
    call wl_dispatch
    mov edi, r13d
    call ws_closed
    mov edi, r12d
    call ws_close
    mov rax, [rip + ws_source]
    mov edi, [rax + WCS_id]
    mov esi, 1
    lea rdx, [rip + ws_mime]
    mov ecx, 16
    call wl_dispatch
    mov edi, [rip + ws_writer]
    call wl_send_find
    test rax, rax
    jz ws_fail
    mov [rip + ws_job], rax
    call ws_write
    call ws_read_text
    mov dword ptr [rip + ws_event], 0x700
    mov edi, 1
    mov esi, 1
    lea rdx, [rip + ws_event]
    mov ecx, 4
    call wl_dispatch
    mov edi, 0x700
    xor esi, esi
    call wl_message_needs_fd
    test eax, eax
    jnz ws_fail
    call ws_clean
    call ws_socket_tests
    call ws_reuse_test
    EPILOGUE

# Send arbitrary bytes plus one descriptor over the fixture's client socket.
ws_socket_send:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov edi, edx
    call ws_fd_packet
    lea rdi, [rip + ws_message]
    xor esi, esi
    mov edx, 56
    call memset
    mov [rip + ws_iov], r12
    mov [rip + ws_iov + 8], r13
    lea rax, [rip + ws_iov]
    mov [rip + ws_message + 16], rax
    mov qword ptr [rip + ws_message + 24], 1
    lea rax, [rip + ws_control]
    mov [rip + ws_message + 32], rax
    mov qword ptr [rip + ws_message + 40], 24
    mov edi, [rip + ws_socket + 4]
    lea rsi, [rip + ws_message]
    xor edx, edx
    SYS SYS_sendmsg
    cmp rax, r13
    jne ws_fail
    EPILOGUE
ws_socket_read:
    mov edi, [rip + ws_socket]
    mov esi, POLLIN
    xor edx, edx
    jmp wl_on_readable

ws_socket_tests:
    PROLOGUE
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    lea r10, [rip + ws_socket]
    mov eax, 53                  # socketpair
    XSYS
    test rax, rax
    js ws_fail
    mov eax, [rip + ws_socket]
    mov [rip + wl_paste_wire_fd], eax
    call ws_small
    call ws_pipe
    mov rax, [rip + ws_source]
    mov eax, [rax + WCS_id]
    mov [rip + ws_event], eax
    mov dword ptr [rip + ws_event + 4], (24 << 16) | 1
    lea rdi, [rip + ws_event + 8]
    lea rsi, [rip + ws_mime]
    mov edx, 16
    call memcpy
    # Whole message, no FD yet: retain it without a failed/partial send.
    mov edi, [rip + ws_socket + 4]
    lea rsi, [rip + ws_event]
    mov edx, 24
    SYS SYS_write
    cmp rax, 24
    jne ws_fail
    call ws_socket_read
    cmp dword ptr [rip + wl_wire_input_len], 24
    jne ws_fail
    mov rax, [rip + ws_source]
    cmp dword ptr [rax + WCS_refs], 0
    jne ws_fail
    # The next message's first byte carries the previous message's FD.
    lea rdi, [rip + ws_event]
    mov esi, 1
    mov edx, [rip + ws_writer]
    call ws_socket_send
    mov edi, [rip + ws_writer]
    call ws_close
    call ws_socket_read
    cmp dword ptr [rip + wl_wire_input_len], 1
    jne ws_fail
    lea rax, [rip + wl_send_jobs]
    mov [rip + ws_job], rax
    cmp dword ptr [rax + WCJ_active], 1
    jne ws_fail
    call ws_write
    call ws_read_text
    # Early FD for the second packet arrives with its incomplete header tail.
    call ws_pipe
    lea rdi, [rip + ws_event + 1]
    mov esi, 3
    mov edx, [rip + ws_writer]
    call ws_socket_send
    mov edi, [rip + ws_writer]
    call ws_close
    call ws_socket_read
    cmp dword ptr [rip + wl_wire_input_len], 4
    jne ws_fail
    cmp dword ptr [rip + wl_wire_fdqueue_len], 1
    jne ws_fail
    mov edi, [rip + ws_socket + 4]
    lea rsi, [rip + ws_event + 4]
    mov edx, 20
    SYS SYS_write
    cmp rax, 20
    jne ws_fail
    call ws_socket_read
    cmp dword ptr [rip + wl_wire_input_len], 0
    jne ws_fail
    cmp dword ptr [rip + wl_wire_fdqueue_len], 0
    jne ws_fail
    lea rax, [rip + wl_send_jobs]
    mov [rip + ws_job], rax
    call ws_write
    call ws_read_text
    mov edi, [rip + ws_socket]
    call ws_close
    mov edi, [rip + ws_socket + 4]
    call ws_close
    call ws_clean
    EPILOGUE
ws_reuse_test:
    PROLOGUE
    # Real loop_poll stale POLLERR is delivered using the replacement's new context.
    call ws_small
    call ws_pipe
    call ws_start
    mov eax, [rip + ws_writer]
    mov [rip + ws_reuse_oldfd], eax
    call ws_reader_close         # old watch gets POLLERR
    call ws_pipe
    mov eax, [rip + ws_reader]
    mov [rip + ws_reuse_read], eax
    mov eax, [rip + ws_writer]
    mov [rip + ws_reuse_write], eax
    mov edi, eax
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test eax, eax
    js ws_fail
1:  mov edi, [rip + ws_reuse_write]
    lea rsi, [rip + ws_buffer]
    mov edx, 4096
    SYS SYS_write
    cmp rax, -EAGAIN
    je 2f
    test rax, rax
    jle ws_fail
    jmp 1b
2:  lea rdi, [rip + ws_trigger]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test eax, eax
    js ws_fail
    mov edi, [rip + ws_trigger]
    mov esi, POLLIN
    lea rdx, [rip + ws_reuse_handler]
    xor ecx, ecx
    call watch_try_add
    cmp eax, 1
    jne ws_fail
    mov edi, [rip + ws_trigger + 4]
    lea rsi, [rip + ws_text]
    mov edx, 1
    SYS SYS_write
    cmp rax, 1
    jne ws_fail
    xor edi, edi
    call loop_poll
    mov rax, [rip + ws_job]
    cmp dword ptr [rax + WCJ_active], 1
    jne ws_fail
    cmp qword ptr [rax + WCJ_offset], 0
    jne ws_fail
    mov edi, [rip + ws_trigger]
    call watch_remove
    mov edi, [rip + ws_trigger]
    call ws_close
    mov edi, [rip + ws_trigger + 4]
    call ws_close
    mov edi, [rip + ws_reuse_read]
    call ws_close
    call ws_clean
    EPILOGUE
ws_reuse_handler:
    PROLOGUE
    mov rdi, [rip + ws_job]
    call wl_send_cancel
    mov edi, [rip + ws_reuse_write]
    mov esi, [rip + ws_reuse_oldfd]
    SYS SYS_dup2
    cmp eax, [rip + ws_reuse_oldfd]
    jne ws_fail
    mov edi, [rip + ws_reuse_write]
    call ws_close
    mov eax, [rip + ws_reuse_oldfd]
    mov [rip + ws_writer], eax
    call ws_start
    EPILOGUE
