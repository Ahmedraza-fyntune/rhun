# Windows native envelopes: allocation bounds, ownership, and actual queued delivery.
.include "win.inc"
.section .rodata
.p2align 3
wm_mutations:
    .quad 0,8,0
    .quad 8,4,2
    .quad 12,4,2
    .quad 16,8,513
    .quad 24,8,-1
    .quad 40,8,6
    .quad 48,8,1
    .quad 64,1,255
    .quad -1,0,0
wm_golden:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 2,5,0,3,4,1
    .ascii "a\nb\nc"
wm_text: .ascii "a\nb\nc"
wm_meta: .quad 2,5,0,3,4,1
wm_pairs: .quad 0,0,1,1
wm_bar: .ascii "|"
wm_distributed: .ascii "a\nb|c"
wm_abc: .ascii "abc"
wm_line: .ascii "L\n"
wm_line_result: .ascii "L\nabc"
wm_raw_result: .ascii "aL\nbc"
wm_unicode: .byte 0xc3,0xa9,0,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80
wm_fallback: .short 'f','a','l','l','b','a','c','k',0
wm_fallback_text: .ascii "fallback"
wm_class: .short 'S','T','A','T','I','C',0
wm_ok: .ascii "ok Windows native clipboard metadata\n"
.bss
.p2align 3
wm_stage: .quad 0
wm_window: .quad 0
wm_live: .quad 0
wm_doc: .quad 0
wm_snapshot: .quad 0
wm_wire: .quad 0
wm_wirelen: .quad 0
wm_plain: .quad 0
wm_out: .zero 64
wm_header: .zero 80
.text
wm_fail:
    mov edi, [rip + wm_stage]
    call sys_exit
wm_accept:
    mov eax, 1
    ret
wm_hold:
    ret
wm_clear_cache:
    PROLOGUE
    lea rax, [rip + wm_accept]
    mov [rip + g_plat + P_clip_write], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    cmp eax, 1
    jne wm_fail
    lea rax, [rip + win_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    EPILOGUE
wm_encode:
    PROLOGUE
    call clip_wire_encode
    test rax, rax
    jz wm_fail
    mov [rip + wm_wire], rax
    mov [rip + wm_wirelen], rdx
    EPILOGUE
wm_free_wire:
    PROLOGUE
    mov rdi, [rip + wm_wire]
    call mem_free
    mov qword ptr [rip + wm_wire], 0
    EPILOGUE
# Fixture allocation deliberately adds padding and initializes all of it to nonzero.
wm_global:
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    lea rdx, [rsi + 7]
    mov ecx, 2
    API GlobalAlloc
    test rax, rax
    jz wm_fail
    mov r13, rax
    mov rcx, rax
    API GlobalSize
    mov r14, rax
    mov rcx, r13
    API GlobalLock
    test rax, rax
    jz wm_fail
    mov r15, rax
    mov rdi, rax
    mov esi, 0xcc
    mov rdx, r14
    call memset
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rcx, r13
    API GlobalUnlock
    mov rax, r13
    EPILOGUE
# Publish the fixture wire and optional fallback, independently of the product writer.
wm_seed:
    PROLOGUE 96
    mov rcx, [rip + wm_window]
    API OpenClipboard
    test eax, eax
    jz wm_fail
    API EmptyClipboard
    test eax, eax
    jz wm_fail
    cmp qword ptr [rip + wm_wire], 0
    je 1f
    mov rdi, [rip + wm_wire]
    mov rsi, [rip + wm_wirelen]
    call wm_global
    mov rbx, rax
    call win_clip_format
    mov ecx, eax
    mov rdx, rbx
    API SetClipboardData
    test rax, rax
    jz wm_fail
1:  cmp qword ptr [rip + wm_plain], 0
    je 2f
    lea rdi, [rip + wm_fallback]
    mov esi, 18
    call wm_global
    mov rdx, rax
    mov ecx, 13
    API SetClipboardData
    test rax, rax
    jz wm_fail
2:  API CloseClipboard
    EPILOGUE
wm_document:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call wm_clear_cache
    mov rax, [rip + g_mem_live]
    mov [rip + wm_live], rax
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
wm_request:
    PROLOGUE
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    cmp qword ptr [rip + win_clip_depth], 0
    jne wm_fail
    EPILOGUE
wm_cleanup:
    PROLOGUE
    call app_clip_reset
    call wm_clear_cache
    mov rdi, [rip + wm_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    call wm_free_wire
    mov rax, [rip + wm_live]
    cmp rax, [rip + g_mem_live]
    jne wm_fail
    EPILOGUE
FN main
    PROLOGUE 96
    mov qword ptr [rip + wm_stage], 1
    call win_clip_format
    cmp eax, 0xc000
    jb wm_fail
    cmp eax, 0xffff
    ja wm_fail
    mov rbx, rax
    call win_clip_format
    cmp rax, rbx
    jne wm_fail
    # Guard-page source: every short header must be rejected before a header load.
    xor ecx, ecx
    mov edx, 8192
    mov r8d, 0x2000
    mov r9d, 4
    API VirtualAlloc
    test rax, rax
    jz wm_fail
    mov rbx, rax
    mov rcx, rax
    mov edx, 4096
    mov r8d, 0x1000
    mov r9d, 4
    API VirtualAlloc
    cmp rax, rbx
    jne wm_fail
    xor r12d, r12d
1:  lea rdi, [rbx + 4096]
    sub rdi, r12
    mov rsi, r12
    call win_clip_wire_size
    test rax, rax
    jnz wm_fail
    inc r12
    cmp r12, 32
    jb 1b
    mov rcx, rbx
    xor edx, edx
    mov r8d, 0x8000
    API VirtualFree
    test eax, eax
    jz wm_fail
    mov qword ptr [rip + wm_stage], 2
    lea rdi, [rip + wm_golden]
    mov esi, 69
    call win_clip_wire_size
    cmp rax, 69
    jne wm_fail
    lea rdi, [rip + wm_golden]
    mov esi, 68
    call win_clip_wire_size
    test rax, rax
    jnz wm_fail
    lea rdi, [rip + wm_golden]
    mov rsi, -1
    call win_clip_wire_size
    cmp rax, 69
    jne wm_fail
    xor edi, edi
    mov esi, 69
    call win_clip_wire_size
    test rax, rax
    jnz wm_fail
    mov qword ptr [rip + wm_header + 16], 512
    mov qword ptr [rip + wm_header + 24], 67108864
    lea rdi, [rip + wm_header]
    mov esi, CLW_MAX
    call win_clip_wire_size
    cmp rax, CLW_MAX
    jne wm_fail
    mov qword ptr [rip + wm_header + 16], 0
    mov qword ptr [rip + wm_header + 24], -1
    lea rdi, [rip + wm_header]
    mov rsi, -1
    call win_clip_wire_size
    test rax, rax
    jnz wm_fail
    mov qword ptr [rip + wm_header + 16], -1
    lea rdi, [rip + wm_header]
    mov rsi, -1
    call win_clip_wire_size
    test rax, rax
    jnz wm_fail
    # Actual HGLOBAL, padding accepted, locks balanced and returned bytes detached.
    mov qword ptr [rip + wm_stage], 3
    mov r14, [rip + g_mem_live]
    lea rdi, [rip + wm_golden]
    mov esi, 69
    call wm_global
    mov rbx, rax
    mov rdi, rax
    call win_clip_read_native_handle
    test rax, rax
    jz wm_fail
    cmp rdx, 69
    jne wm_fail
    mov r12, rax
    mov rcx, rbx
    API GlobalLock
    test rax, rax
    jz wm_fail
    mov rcx, rbx
    API GlobalUnlock
    test eax, eax              # only the fixture's one lock remained
    jnz wm_fail
    mov rcx, rbx
    API GlobalFree
    test rax, rax
    jnz wm_fail
    mov rdi, r12
    lea rsi, [rip + wm_golden]
    mov edx, 69
    call memeq
    test eax, eax
    jz wm_fail
    cmp byte ptr [r12 + 69], 0
    jne wm_fail
    mov rdi, r12
    call mem_free
    cmp r14, [rip + g_mem_live]
    jne wm_fail
    # Malformed wire reaches the owned-handle reader, not just the shared codec.
    lea r12, [rip + wm_mutations]
4:  cmp qword ptr [r12], -1
    je 7f
    inc qword ptr [rip + wm_stage]
    lea rdi, [rip + wm_header]
    lea rsi, [rip + wm_golden]
    mov edx, 69
    call memcpy
    lea rdi, [rip + wm_header]
    add rdi, [r12]
    mov rax, [r12 + 16]
    cmp qword ptr [r12 + 8], 8
    jne 5f
    mov [rdi], rax
    jmp 6f
5:  cmp qword ptr [r12 + 8], 4
    jne 51f
    mov [rdi], eax
    jmp 6f
51: mov [rdi], al
6:  lea rdi, [rip + wm_header]
    mov esi, 69
    call wm_global
    mov rbx, rax
    mov rdi, rax
    call win_clip_read_native_handle
    test rax, rax
    jnz wm_fail
    test rdx, rdx
    jnz wm_fail
    mov rcx, rbx
    API GlobalFree
    test rax, rax
    jnz wm_fail
    cmp r14, [rip + g_mem_live]
    jne wm_fail
    add r12, 24
    jmp 4b
7:  mov qword ptr [rip + wm_stage], 20
    xor ecx, ecx
    lea rdx, [rip + wm_class]
    mov r8, rdx
    xor r9d, r9d
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 1
    mov qword ptr [rsp + 56], 1
    mov qword ptr [rsp + 64], 0
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
    mov qword ptr [rsp + 88], 0
    API CreateWindowExW
    test rax, rax
    jz wm_fail
    mov [rip + wm_window], rax
    mov [rip + win_hwnd], rax
    lea rax, [rip + win_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    mov dword ptr [rip + cfg_multi_cursor_paste], 0
    # Real multi-copy publishes wire before its prepared ECP/ECM is freed.
    lea rdi, [rip + wm_text]
    mov esi, 5
    call wm_document
    mov rdi, [rip + wm_doc]
    # Source selections are endpoints, distinct from the metadata offset/length table.
    lea rsi, [rip + wm_copy_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne wm_fail
    mov rdi, [rip + wm_doc]
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne wm_fail
    xor edi, edi
    mov esi, 1
    call win_clip_write
    test eax, eax
    jnz wm_fail
    mov rcx, [rip + wm_window]
    API OpenClipboard
    test eax, eax
    jz wm_fail
    mov ecx, 13
    API GetClipboardData
    mov rdi, rax
    mov esi, 64
    call win_clip_read_handle
    test rax, rax
    jz wm_fail
    cmp rdx, 5
    jne wm_fail
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + wm_text]
    mov edx, 5
    call memeq
    test eax, eax
    jz wm_fail
    mov rdi, r12
    call mem_free
    call win_clip_format
    mov ecx, eax
    API GetClipboardData
    mov rdi, rax
    call win_clip_read_native_handle
    test rax, rax
    jz wm_fail
    cmp rdx, 69
    jne wm_fail
    mov r12, rax
    API CloseClipboard
    mov rdi, r12
    lea rsi, [rip + wm_golden]
    mov edx, 69
    call memeq
    test eax, eax
    jz wm_fail
    mov rdi, r12
    call mem_free
    call wm_cleanup
    mov qword ptr [rip + wm_stage], 21
    lea rdi, [rip + wm_bar]
    mov esi, 1
    call wm_document
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wm_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne wm_fail
    call wm_request
    lea rdi, [rip + wm_distributed]
    mov esi, 5
    call wm_check
    mov rdi, [rip + wm_doc]
    call doc_undo
    lea rdi, [rip + wm_bar]
    mov esi, 1
    call wm_check
    call wm_cleanup
    # Line flag is foreign (cache cleared), then explicit raw replaces cached line semantics.
    mov qword ptr [rip + wm_stage], 22
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wm_caret]
    mov edx, 1
    call doc_selections_set
    lea rdi, [rip + wm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call wm_encode
    call wm_seed
    call wm_request
    lea rdi, [rip + wm_line_result]
    mov esi, 5
    call wm_check
    mov rdi, [rip + wm_doc]
    call doc_undo
    lea rdi, [rip + wm_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + wm_wire]
    mov dword ptr [rax + 12], 0
    call wm_seed
    call wm_request
    lea rdi, [rip + wm_raw_result]
    mov esi, 5
    call wm_check
    cmp dword ptr [rip + g_clip_line], 0
    jne wm_fail
    call wm_cleanup
    # Foreign binary counted Unicode is valid, though outgoing NUL copies are rejected.
    mov qword ptr [rip + wm_stage], 23
    xor edi, edi
    xor esi, esi
    call wm_document
    lea rdi, [rip + wm_unicode]
    mov esi, 10
    xor edx, edx
    xor ecx, ecx
    call wm_encode
    call wm_seed
    mov rdi, [rip + wm_wire]
    mov rsi, [rip + wm_wirelen]
    call win_clip_write
    test eax, eax
    jnz wm_fail
    call wm_request
    lea rdi, [rip + wm_unicode]
    mov esi, 10
    call wm_check
    call wm_cleanup
    # Unsupported version and malformed segment metadata fall back to real CF13 text.
    mov qword ptr [rip + wm_stage], 24
    mov qword ptr [rip + wm_plain], 1
    xor edi, edi
    xor esi, esi
    call wm_document
    lea rdi, [rip + wm_text]
    mov esi, 5
    xor edx, edx
    lea rcx, [rip + wm_meta]
    call wm_encode
    mov rax, [rip + wm_wire]
    mov dword ptr [rax + 8], 2
    call wm_seed
    call wm_request
    lea rdi, [rip + wm_fallback_text]
    mov esi, 8
    call wm_check
    call wm_cleanup
    # Empty native is authoritative even with nonempty fallback and a live redo branch.
    mov qword ptr [rip + wm_stage], 25
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    mov rdi, [rip + wm_doc]
    call doc_undo
    mov rdi, [rip + wm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + wm_snapshot], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call wm_encode
    call wm_seed
    call wm_request
    mov rdi, [rip + wm_doc]
    mov rsi, [rip + wm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz wm_fail
    mov rdi, [rip + wm_snapshot]
    call mem_free
    mov rdi, [rip + wm_doc]
    call doc_redo
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_check
    call wm_cleanup
    # Stale queued destination cannot fall back; next native request still works.
    mov qword ptr [rip + wm_stage], 26
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    lea rdi, [rip + wm_line]
    mov esi, 2
    xor edx, edx
    xor ecx, ecx
    call wm_encode
    call wm_seed
    lea rax, [rip + wm_hold]
    mov [rip + g_plat + P_clip_get], rax
    call app_clip_request
    cmp eax, 1
    jne wm_fail
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wm_caret]
    mov edx, 1
    call doc_selections_set
    call win_clip_get
    cmp qword ptr [rip + app_clip_active_token], 0
    jne wm_fail
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_check
    lea rax, [rip + win_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    call wm_request
    lea rdi, [rip + wm_raw_result]
    mov esi, 5
    call wm_check
    call wm_cleanup
    # A large native source remains detached after its HGLOBAL is freed.
    mov qword ptr [rip + wm_stage], 27
    mov r14, [rip + g_mem_live]
    mov edi, 1048576
    call mem_alloc
    mov r12, rax
    mov rdi, rax
    mov esi, 'z'
    mov edx, 1048576
    call memset
    mov rdi, r12
    mov esi, 1048576
    xor edx, edx
    xor ecx, ecx
    call wm_encode
    mov rdi, r12
    call mem_free
    mov rdi, [rip + wm_wire]
    mov rsi, [rip + wm_wirelen]
    call wm_global
    mov rbx, rax
    mov rdi, rax
    call win_clip_read_native_handle
    test rax, rax
    jz wm_fail
    cmp rdx, 1048608
    jne wm_fail
    mov r12, rax
    mov rcx, rbx
    API GlobalFree
    test rax, rax
    jnz wm_fail
    mov rdi, r12
    mov rsi, [rip + wm_wire]
    mov edx, 1048608
    call memeq
    test eax, eax
    jz wm_fail
    mov rdi, r12
    call mem_free
    call wm_free_wire
    cmp r14, [rip + g_mem_live]
    jne wm_fail
    mov rcx, [rip + wm_window]
    API DestroyWindow
    mov qword ptr [rip + win_hwnd], 0
    mov edi, 1
    lea rsi, [rip + wm_ok]
    mov edx, 37
    SYS SYS_write
    xor eax, eax
    EPILOGUE
.section .rodata
wm_copy_pairs: .quad 3,0,5,4
wm_caret: .quad 1,1
