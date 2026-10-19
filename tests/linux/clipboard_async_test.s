# A timeout callback starts a successor with the same descriptor/object identity.
.include "rhun.inc"
.include "plat/x11.inc"
.section .rodata
ca_base: .ascii "base"
ca_old: .ascii "old"
ca_new: .ascii "new"
ca_result: .ascii "newbase"
ca_name: .asciz "rhun-clipboard-async"
ca_ok: .ascii "ok clipboard timeout successor identity\n"
.bss
.p2align 3
ca_stage: .quad 0
ca_live: .quad 0
ca_doc: .quad 0
ca_snapshot: .quad 0
ca_calls: .quad 0
ca_mode: .quad 0
ca_generation: .quad 0
ca_old_identity: .quad 0
ca_new_buffer: .quad 0
ca_new_cap: .quad 0
ca_writers: .zero 8
ca_packet: .zero 64
ca_copy: .zero 16
.text
ca_fail:
    mov edi, [rip + ca_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  call sys_exit
ca_setup:
    PROLOGUE
    inc qword ptr [rip + ca_stage]
    mov qword ptr [rip + ca_calls], 0
    mov rax, [rip + g_mem_live]
    mov [rip + ca_live], rax
    call doc_new
    mov [rip + g_doc], rax
    mov [rip + ca_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + ca_base]
    mov ecx, 4
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + ca_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + ca_snapshot], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    EPILOGUE
ca_same:
    sub rsp, 8
    mov rdi, [rip + ca_doc]
    mov rsi, [rip + ca_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz ca_fail
    add rsp, 8
    ret
ca_cleanup:
    PROLOGUE
    call app_clip_reset
    mov rdi, [rip + ca_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, [rip + ca_snapshot]
    call mem_free
    mov rax, [rip + ca_live]
    cmp rax, [rip + g_mem_live]
    jne ca_fail
    EPILOGUE
ca_request:
    sub rsp, 8
    call app_clip_request
    cmp eax, 1
    jne ca_fail
    add rsp, 8
    ret
ca_wayland_get:
    PROLOGUE 16
    inc qword ptr [rip + ca_calls]
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js ca_fail
    mov rax, [rip + ca_calls]
    lea rdx, [rip + ca_writers]
    mov ecx, [rsp + 4]
    mov [rdx + rax*4 - 4], ecx
    mov edi, [rsp]
    cmp rax, 1
    je 1f
    cmp edi, [rip + ca_old_identity]
    jne ca_fail
1:  call wl_paste_receive_fd
    cmp eax, 1
    jne ca_fail
    cmp qword ptr [rip + ca_calls], 1
    je 2f
    lea rdi, [rip + wl_paste_buffer]
    lea rsi, [rip + ca_new]
    mov edx, 3
    call sb_push
    mov rax, [rip + wl_paste_buffer + SB_ptr]
    mov [rip + ca_new_buffer], rax
    mov rax, [rip + wl_paste_buffer + SB_cap]
    mov [rip + ca_new_cap], rax
2:  EPILOGUE

FN main
    PROLOGUE
    lea rax, [rip + ca_wayland_get]
    mov [rip + g_plat + P_clip_get], rax
    xor r15d, r15d
.Lca_wayland:
    call ca_setup
    call ca_request
    mov eax, [rip + wl_paste_fd]
    mov [rip + ca_old_identity], rax
    mov rax, [rip + wl_paste_generation]
    mov [rip + ca_generation], rax
    lea rdi, [rip + wl_paste_buffer]
    lea rsi, [rip + ca_old]
    mov edx, 3
    call sb_push
    call ca_request
    mov qword ptr [rip + wl_paste_deadline], 1
    cmp r15d, 1
    je .Lca_result
    cmp r15d, 2
    je .Lca_readable
    call wl_paste_complete
    jmp .Lca_check
.Lca_result:
    mov edi, [rip + ca_old_identity]
    mov esi, 1
    xor edx, edx
    call wl_paste_read_result
    jmp .Lca_check
.Lca_readable:
    mov edi, [rip + ca_old_identity]
    mov esi, POLLIN
    mov rdx, [rip + ca_generation]
    call on_paste_readable
.Lca_check:
    cmp qword ptr [rip + ca_calls], 2
    jne ca_fail
    mov eax, [rip + wl_paste_fd]
    cmp eax, [rip + ca_old_identity]
    jne ca_fail
    mov rax, [rip + wl_paste_generation]
    cmp rax, [rip + ca_generation]
    je ca_fail
    mov rax, [rip + wl_paste_token]
    cmp rax, [rip + app_clip_active_token]
    jne ca_fail
    test rax, rax
    jz ca_fail
    mov rax, [rip + ca_new_buffer]
    cmp rax, [rip + wl_paste_buffer + SB_ptr]
    jne ca_fail
    mov rax, [rip + ca_new_cap]
    cmp rax, [rip + wl_paste_buffer + SB_cap]
    jne ca_fail
    cmp qword ptr [rip + wl_paste_buffer + SB_len], 3
    jne ca_fail
    call ca_same
    mov edi, [rip + ca_writers + 4]
    SYS SYS_close
    mov edi, [rip + wl_paste_fd]
    xor esi, esi
    xor edx, edx
    call wl_paste_read_result
    cmp dword ptr [rip + wl_paste_fd], -1
    jne ca_fail
    mov rdi, [rip + ca_doc]
    call doc_len
    cmp rax, 7
    jne ca_fail
    mov rdi, [rip + ca_doc]
    xor esi, esi
    mov edx, 7
    lea rcx, [rip + ca_copy]
    call doc_copy
    lea rdi, [rip + ca_copy]
    lea rsi, [rip + ca_result]
    mov edx, 7
    call memeq
    test eax, eax
    jz ca_fail
    mov edi, [rip + ca_writers]
    SYS SYS_close
    call ca_cleanup
    inc r15d
    cmp r15d, 3
    jb .Lca_wayland
    call ca_x11
    mov edi, 1
    lea rsi, [rip + ca_ok]
    mov edx, 40
    call write_all
    xor edi, edi
    call sys_exit
ca_x11:
    PROLOGUE
    lea rdi, [rip + ca_name]
    mov esi, 1
    mov eax, 319
    XSYS
    test eax, eax
    js ca_fail
    mov [rip + x_wire_fd], eax
    mov dword ptr [rip + x_wire_max_request], 65535
    mov dword ptr [rip + x_paste_clipboard_atom], 0x101
    mov dword ptr [rip + x_wire_utf8_atom], 0x102
    mov dword ptr [rip + x_paste_property_atom], 0x103
    mov dword ptr [rip + x_paste_id_mask], 0x1fffffff
    mov dword ptr [rip + x_paste_id_next], 0x9000
    lea rax, [rip + ca_x11_get]
    mov [rip + g_plat + P_clip_get], rax
    mov qword ptr [rip + ca_mode], 0
.Lca_xloop:
    call ca_setup
    call ca_request
    mov eax, [rip + x_paste_record + XR_window]
    mov [rip + ca_old_identity], rax
    mov rax, [rip + x_paste_generation]
    mov [rip + ca_generation], rax
    call ca_request
    mov eax, [rip + ca_old_identity]
    mov [rip + x_paste_id_next], eax # force an ABA to exercise generation protection
    mov qword ptr [rip + x_paste_record + XR_deadline], 1
    lea rdi, [rip + ca_packet]
    xor esi, esi
    mov edx, 64
    call memset
    cmp qword ptr [rip + ca_mode], 0
    jne .Lca_xreply
    mov byte ptr [rip + ca_packet], 31
    mov eax, [rip + ca_old_identity]
    mov [rip + ca_packet + 8], eax
    mov dword ptr [rip + ca_packet + 12], 0x101
    mov dword ptr [rip + ca_packet + 16], 0x102
    mov dword ptr [rip + ca_packet + 20], 0x103
    lea rdi, [rip + ca_packet]
    call x_paste_notify
    mov r12d, XR_NOTIFY
    jmp .Lca_xcheck
.Lca_xreply:
    mov dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    mov dword ptr [rip + x_paste_record + XR_get_seq], 77
    mov byte ptr [rip + ca_packet], 1
    mov byte ptr [rip + ca_packet + 1], 8
    mov word ptr [rip + ca_packet + 2], 77
    mov dword ptr [rip + ca_packet + 8], 0x102
    lea rdi, [rip + ca_packet]
    mov esi, 32
    call x_paste_reply
    mov r12d, XR_PROPERTY
.Lca_xcheck:
    cmp qword ptr [rip + ca_calls], 2
    jne ca_fail
    cmp r12d, [rip + x_paste_record + XR_state]
    jne ca_fail
    mov eax, [rip + x_paste_record + XR_window]
    cmp eax, [rip + ca_old_identity]
    jne ca_fail
    mov rax, [rip + x_paste_generation]
    cmp rax, [rip + ca_generation]
    je ca_fail
    mov rax, [rip + x_paste_record + XR_token]
    test rax, rax
    jz ca_fail
    cmp rax, [rip + app_clip_active_token]
    jne ca_fail
    call ca_same
    call x_paste_cancel
    call ca_same
    cmp qword ptr [rip + app_clip_active_token], 0
    jne ca_fail
    call ca_cleanup
    inc qword ptr [rip + ca_mode]
    cmp qword ptr [rip + ca_mode], 2
    jb .Lca_xloop
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    EPILOGUE
ca_x11_get:
    PROLOGUE
    inc qword ptr [rip + ca_calls]
    call x_paste_begin
    cmp qword ptr [rip + ca_calls], 1
    je 1f
    cmp qword ptr [rip + ca_mode], 0
    je 1f
    mov dword ptr [rip + x_paste_record + XR_state], XR_PROPERTY
    mov dword ptr [rip + x_paste_record + XR_get_seq], 77
1:  EPILOGUE
