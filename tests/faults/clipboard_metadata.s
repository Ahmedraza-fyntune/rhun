# Linked only by clipboard-faults.py against a temporary renamed allocator object.
.include "rhun.inc"
.include "plat/wayland.inc"
.section .rodata
ff_payload: .zero 65537,120
ff_old: .ascii "old"
ff_base: .ascii "base"
ff_after_old: .ascii "oldbase"
ff_ok: .ascii "ok clipboard allocation failures\n"
.equ FF_OK_SIZE, . - ff_ok
.bss
.p2align 3
ff_mask: .quad 0
ff_stage: .quad 0
ff_live: .quad 0
ff_wire: .quad 0
ff_wirelen: .quad 0
ff_doc: .quad 0
ff_snapshot: .quad 0
ff_calls: .quad 0
ff_backend: .quad 0
ff_before: .zero SB_SIZE * 2
ff_x_before: .zero SB_SIZE + 16
ff_w_before: .zero WCS_SIZE
ff_w_source: .quad 0
ff_send_event: .zero 32
ff_output: .zero 65541
.text
FN mem_alloc_try
    mov rax, [rip + ff_mask]
    shr rax, 1
    mov [rip + ff_mask], rax
    jc 1f
    jmp fault_real_mem_alloc_try
1:  xor eax, eax
    ret
ff_fail:
    mov edi, [rip + ff_stage]
    inc edi
    call sys_exit
ff_get:
    PROLOGUE
    inc qword ptr [rip + ff_calls]
    cmp qword ptr [rip + ff_calls], 2
    jne 1f
    mov rdi, [rip + ff_doc]
    mov rsi, [rip + ff_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz ff_fail
    mov qword ptr [rip + ff_mask], 0
    cmp qword ptr [rip + ff_backend], 0
    jne 2f
    call headless_clip_get
    jmp 1f
2:  cmp qword ptr [rip + ff_backend], 2
    je 3f
    call x_paste_begin
    jmp 1f
3:  call wl_clip_get
1:  EPILOGUE
ff_setup:
    PROLOGUE
    inc qword ptr [rip + ff_stage]
    mov rax, [rip + g_mem_live]
    mov [rip + ff_live], rax
    mov qword ptr [rip + ff_mask], 0
    mov qword ptr [rip + ff_calls], 0
    mov qword ptr [rip + ff_backend], 0
    lea rax, [rip + ff_get]
    mov [rip + g_plat + P_clip_get], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call doc_new
    mov [rip + ff_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + ff_base]
    mov ecx, 4
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + ff_doc]
    mov esi, 4
    lea rdx, [rip + ff_old]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + ff_doc]
    call doc_undo
    mov rdi, [rip + ff_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + ff_snapshot], rax
    EPILOGUE
ff_cleanup:
    PROLOGUE
    mov qword ptr [rip + ff_mask], 0
    call app_clip_reset
    call headless_clip_reset
    call x_clip_reset
    call ff_w_reset
    mov rdi, [rip + ff_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, [rip + ff_snapshot]
    call mem_free
    mov rax, [rip + ff_live]
    cmp rax, [rip + g_mem_live]
    jne ff_fail
    EPILOGUE
ff_write:
    PROLOGUE
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call headless_clip_write
    cmp eax, 1
    jne ff_fail
    EPILOGUE
ff_request:
    PROLOGUE
    call app_clip_request
    cmp eax, 1
    jne ff_fail
    EPILOGUE
ff_source_before:
    PROLOGUE
    lea rdi, [rip + ff_before]
    lea rsi, [rip + headless_clip_plain]
    mov edx, SB_SIZE
    call memcpy
    lea rdi, [rip + ff_before + SB_SIZE]
    lea rsi, [rip + headless_clip_native]
    mov edx, SB_SIZE
    call memcpy
    EPILOGUE
ff_source_same:
    PROLOGUE
    lea rdi, [rip + ff_before]
    lea rsi, [rip + headless_clip_plain]
    mov edx, SB_SIZE
    call memeq
    test eax, eax
    jz ff_fail
    lea rdi, [rip + ff_before + SB_SIZE]
    lea rsi, [rip + headless_clip_native]
    mov edx, SB_SIZE
    call memeq
    test eax, eax
    jz ff_fail
    EPILOGUE
ff_x_source_before:
    lea rdi, [rip + ff_x_before]
    lea rsi, [rip + x_wire_clipboard]
    mov edx, SB_SIZE + 16
    jmp memcpy
ff_x_source_same:
    PROLOGUE
    lea rdi, [rip + ff_x_before]
    lea rsi, [rip + x_wire_clipboard]
    mov edx, SB_SIZE + 16
    call memeq
    test eax, eax
    jz ff_fail
    EPILOGUE
ff_x_write:
    PROLOGUE
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call x_clip_write
    cmp eax, 1
    jne ff_fail
    EPILOGUE
ff_w_reset:
    PROLOGUE
    lea rbx, [rip + wl_send_sources]
    mov r12d, WCS_COUNT
1:  mov edi, [rbx + WCS_id]
    call wl_source_deleted
    add rbx, WCS_SIZE
    dec r12d
    jnz 1b
    cmp qword ptr [rip + wl_send_charge], 0
    jne ff_fail
    mov dword ptr [rip + wl_paste_wire_output_len], 0
    EPILOGUE
ff_w_write:
    PROLOGUE
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call wl_clip_write
    cmp eax, 1
    jne ff_fail
    EPILOGUE
ff_w_source_before:
    PROLOGUE
    mov edi, [rip + wl_paste_source_id]
    call wl_source_find
    test rax, rax
    jz ff_fail
    mov [rip + ff_w_source], rax
    lea rdi, [rip + ff_w_before]
    mov rsi, rax
    mov edx, WCS_SIZE
    call memcpy
    EPILOGUE
ff_w_source_same:
    PROLOGUE
    mov edi, [rip + wl_paste_source_id]
    call wl_source_find
    cmp rax, [rip + ff_w_source]
    jne ff_fail
    lea rdi, [rip + ff_w_before]
    mov rsi, rax
    mov edx, WCS_SIZE
    call memeq
    test eax, eax
    jz ff_fail
    EPILOGUE
ff_large_result:
    PROLOGUE
    cmp qword ptr [rip + app_clip_active_token], 0
    jne ff_fail
    mov rdi, [rip + ff_doc]
    call doc_len
    cmp rax, 65541
    jne ff_fail
    mov rdi, [rip + ff_doc]
    xor esi, esi
    mov edx, 65541
    lea rcx, [rip + ff_output]
    call doc_copy
    lea rdi, [rip + ff_output]
    lea rsi, [rip + ff_payload]
    mov edx, 65537
    call memeq
    test eax, eax
    jz ff_fail
    lea rdi, [rip + ff_output + 65537]
    lea rsi, [rip + ff_base]
    mov edx, 4
    call memeq
    test eax, eax
    jz ff_fail
    mov rdi, [rip + ff_doc]
    call doc_undo
    mov rdi, [rip + ff_doc]
    call doc_len
    cmp rax, 4
    jne ff_fail
    EPILOGUE
FN main
    PROLOGUE
    lea rdi, [rip + ff_payload]
    mov esi, 65537
    xor edx, edx
    xor ecx, ecx
    call clip_wire_encode
    test rax, rax
    jz ff_fail
    mov [rip + ff_wire], rax
    mov [rip + ff_wirelen], rdx
    # Both recoverable rich setter allocations preserve the complete old source.
    mov r15d, 1
.Lff_write_fail:
    call ff_setup
    lea rdi, [rip + ff_old]
    mov esi, 3
    call headless_clip_set
    cmp eax, 1
    jne ff_fail
    call ff_source_before
    mov r14, [rip + g_mem_live]
    mov [rip + ff_mask], r15
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call headless_clip_write
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call headless_clip_get
    mov rdi, [rip + ff_doc]
    call doc_len
    cmp rax, 7
    jne ff_fail
    mov rdi, [rip + ff_doc]
    xor esi, esi
    mov edx, 7
    lea rcx, [rip + ff_output]
    call doc_copy
    lea rdi, [rip + ff_output]
    lea rsi, [rip + ff_after_old]
    mov edx, 7
    call memeq
    test eax, eax
    jz ff_fail
    call ff_cleanup
    inc r15
    cmp r15d, 2
    jbe .Lff_write_fail
    # Plain setter failure also keeps an old native source intact.
    call ff_setup
    call ff_write
    call ff_source_before
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ff_mask], 1
    lea rdi, [rip + ff_payload]
    mov esi, 65537
    call headless_clip_set
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call headless_clip_get
    call ff_large_result
    call ff_cleanup
    # Failed native snapshot falls back to an independent valid plain snapshot.
    call ff_setup
    call ff_write
    call ff_request
    mov qword ptr [rip + ff_mask], 1
    call headless_clip_get
    call ff_large_result
    call ff_cleanup
    # Failed native+plain or sole plain snapshot releases exactly one queued request.
    xor r15d, r15d
.Lff_read_fail:
    call ff_setup
    test r15d, r15d
    jnz 2f
    call ff_write
    jmp 3f
2:  lea rdi, [rip + ff_payload]
    mov esi, 65537
    call headless_clip_set
    cmp eax, 1
    jne ff_fail
3:  call ff_request
    call ff_request
    mov eax, 3
    test r15d, r15d
    jz 4f
    mov eax, 1
4:  mov [rip + ff_mask], rax
    call headless_clip_get
    cmp qword ptr [rip + ff_calls], 2
    jne ff_fail
    call ff_large_result
    call ff_cleanup
    inc r15d
    cmp r15d, 2
    jb .Lff_read_fail
    # X11 has one native owner allocation and a borrowed plain text view.
    mov dword ptr [rip + x_send_main_window], 0x100
    mov dword ptr [rip + x_paste_clipboard_atom], 0x101
    mov dword ptr [rip + x_wire_native_atom], 0x105
    call ff_setup
    mov qword ptr [rip + ff_backend], 1
    lea rdi, [rip + ff_old]
    mov esi, 3
    call x_clip_set
    cmp eax, 1
    jne ff_fail
    call ff_x_source_before
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ff_mask], 1
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call x_clip_write
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_x_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call x_paste_begin
    mov rdi, [rip + ff_doc]
    call doc_len
    cmp rax, 7
    jne ff_fail
    mov rdi, [rip + ff_doc]
    xor esi, esi
    mov edx, 7
    lea rcx, [rip + ff_output]
    call doc_copy
    lea rdi, [rip + ff_output]
    lea rsi, [rip + ff_after_old]
    mov edx, 7
    call memeq
    test eax, eax
    jz ff_fail
    call ff_cleanup
    # A failed raw replacement must never free the native base or its borrowed text.
    call ff_setup
    mov qword ptr [rip + ff_backend], 1
    call ff_x_write
    call ff_x_source_before
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ff_mask], 1
    lea rdi, [rip + ff_payload]
    mov esi, 65537
    call x_clip_set
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_x_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call x_paste_begin
    call ff_large_result
    call ff_cleanup
    call ff_setup
    mov qword ptr [rip + ff_backend], 1
    call ff_x_write
    call ff_request
    mov qword ptr [rip + ff_mask], 1
    call x_paste_begin
    call ff_large_result
    call ff_cleanup
    xor r15d, r15d
.Lff_x_read_fail:
    call ff_setup
    mov qword ptr [rip + ff_backend], 1
    test r15d, r15d
    jnz 5f
    call ff_x_write
    jmp 6f
5:  lea rdi, [rip + ff_payload]
    mov esi, 65537
    call x_clip_set
    cmp eax, 1
    jne ff_fail
6:  call ff_request
    call ff_request
    mov eax, 3
    test r15d, r15d
    jz 7f
    mov eax, 1
7:  mov [rip + ff_mask], rax
    call x_paste_begin
    cmp qword ptr [rip + ff_calls], 2
    jne ff_fail
    call ff_large_result
    call ff_cleanup
    inc r15
    cmp r15d, 2
    jb .Lff_x_read_fail
    # A failed native sender snapshot releases its charge and leaves the source usable.
    call ff_setup
    mov qword ptr [rip + ff_backend], 1
    call ff_x_write
    call ff_x_source_before
    mov r14, [rip + g_mem_live]
    mov dword ptr [rip + x_wire_max_request], 64
    mov byte ptr [rip + ff_send_event], 30
    mov dword ptr [rip + ff_send_event + 8], 0x100
    mov dword ptr [rip + ff_send_event + 12], 0x200
    mov dword ptr [rip + ff_send_event + 16], 0x101
    mov dword ptr [rip + ff_send_event + 20], 0x105
    mov dword ptr [rip + ff_send_event + 24], 0x300
    mov qword ptr [rip + ff_mask], 1
    lea rdi, [rip + ff_send_event]
    call x_serve_selection
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    cmp qword ptr [rip + x_send_budget], 0
    jne ff_fail
    cmp dword ptr [rip + x_send_slots], 0
    jne ff_fail
    call ff_x_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call x_paste_begin
    call ff_large_result
    call ff_cleanup
    # Wayland owns one envelope and keeps immutable sources through delete_id.
    mov dword ptr [rip + wl_send_manager], 0x401
    mov dword ptr [rip + wl_paste_device], 0x402
    mov dword ptr [rip + wl_send_serial_known], 1
    mov dword ptr [rip + wl_wire_next_id], 0x500
    call ff_setup
    mov qword ptr [rip + ff_backend], 2
    lea rdi, [rip + ff_old]
    mov esi, 3
    call wl_clip_set
    cmp eax, 1
    jne ff_fail
    call ff_w_source_before
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ff_mask], 1
    mov rdi, [rip + ff_wire]
    mov rsi, [rip + ff_wirelen]
    call wl_clip_write
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_w_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call wl_clip_get
    mov rdi, [rip + ff_doc]
    call doc_len
    cmp rax, 7
    jne ff_fail
    mov rdi, [rip + ff_doc]
    xor esi, esi
    mov edx, 7
    lea rcx, [rip + ff_output]
    call doc_copy
    lea rdi, [rip + ff_output]
    lea rsi, [rip + ff_after_old]
    mov edx, 7
    call memeq
    test eax, eax
    jz ff_fail
    call ff_cleanup
    call ff_setup
    mov qword ptr [rip + ff_backend], 2
    call ff_w_write
    call ff_w_source_before
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ff_mask], 1
    lea rdi, [rip + ff_payload]
    mov esi, 65537
    call wl_clip_set
    test eax, eax
    jnz ff_fail
    cmp r14, [rip + g_mem_live]
    jne ff_fail
    call ff_w_source_same
    mov qword ptr [rip + ff_mask], 0
    call ff_request
    call wl_clip_get
    call ff_large_result
    call ff_cleanup
    call ff_setup
    mov qword ptr [rip + ff_backend], 2
    call ff_w_write
    call ff_request
    mov qword ptr [rip + ff_mask], 1
    call wl_clip_get
    call ff_large_result
    call ff_cleanup
    xor r15d, r15d
.Lff_w_read_fail:
    call ff_setup
    mov qword ptr [rip + ff_backend], 2
    test r15d, r15d
    jnz 8f
    call ff_w_write
    jmp 9f
8:  lea rdi, [rip + ff_payload]
    mov esi, 65537
    call wl_clip_set
    cmp eax, 1
    jne ff_fail
9:  call ff_request
    call ff_request
    mov eax, 3
    test r15d, r15d
    jz 10f
    mov eax, 1
10: mov [rip + ff_mask], rax
    call wl_clip_get
    cmp qword ptr [rip + ff_calls], 2
    jne ff_fail
    call ff_large_result
    call ff_cleanup
    inc r15
    cmp r15d, 2
    jb .Lff_w_read_fail
    mov rdi, [rip + ff_wire]
    call mem_free
    mov edi, 1
    lea rsi, [rip + ff_ok]
    mov edx, FF_OK_SIZE
    call write_all
    xor edi, edi
    call sys_exit
