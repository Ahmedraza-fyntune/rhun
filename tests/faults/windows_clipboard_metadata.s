# Appended to the native fixture only by windows-clipboard-faults.py.
.section .rodata
.p2align 3
wf_cases:
    .quad 1,1,0,0
    .quad 2,1,0,0
    .quad 2,2,1,0
    .quad 3,1,1,0
    .quad 3,2,2,0
    .quad 4,1,2,0
    .quad 5,1,2,0
    .quad 5,2,2,1
    .quad 0,0,0,0
wf_pairs: .quad 1,0,3,2
wf_redo: .ascii "abcL"
wf_cut_text: .ascii "a\nc"
wf_ok: .ascii "ok Windows clipboard failures\n"
.bss
.p2align 3
wf_kind: .quad 0
wf_nth: .quad 0
wf_calls: .quad 0
wf_bad: .quad 0
wf_locks: .quad 0
wf_count: .quad 0
wf_records: .zero 8*32
wf_cache: .zero SB_SIZE
wf_live: .quad 0
.text
# Internal helper. Match only the selected operation and invocation.
wf_should_fail:
    xor eax, eax
    cmp rdi, [rip + wf_kind]
    jne 1f
    inc qword ptr [rip + wf_calls]
    mov rcx, [rip + wf_calls]
    cmp rcx, [rip + wf_nth]
    sete al
1:  ret
wf_find:
    lea rax, [rip + wf_records]
    mov rcx, [rip + wf_count]
1:  test rcx, rcx
    jz 2f
    cmp [rax], rdi
    je 3f
    add rax, 32
    dec rcx
    jmp 1b
2:  xor eax, eax
3:  ret
wf_reset:
    PROLOGUE
    mov qword ptr [rip + wf_calls], 0
    mov qword ptr [rip + wf_bad], 0
    mov qword ptr [rip + wf_locks], 0
    mov qword ptr [rip + wf_count], 0
    lea rdi, [rip + wf_records]
    xor esi, esi
    mov edx, 8*32
    call memset
    EPILOGUE

# These entry points obey Win64, including rdi/rsi and vector preservation.
FN wf_RegisterClipboardFormatW
    CALLBACK 96
    mov r12, rcx
    mov edi, 1
    call wf_should_fail
    test eax, eax
    jnz 1f
    mov rcx, r12
    API RegisterClipboardFormatW
    jmp 2f
1:  xor eax, eax
2:  CALLBACK_END 96
FN wf_GlobalAlloc
    CALLBACK 96
    mov r12, rcx
    mov r13, rdx
    mov edi, 2
    call wf_should_fail
    test eax, eax
    jnz 2f
    mov rcx, r12
    mov rdx, r13
    API GlobalAlloc
    mov rbx, rax
    test rax, rax
    jz 3f
    mov rcx, [rip + wf_count]
    cmp rcx, 8
    jae 1f
    inc qword ptr [rip + wf_count]
    shl rcx, 5
    lea rax, [rip + wf_records]
    add rax, rcx
    mov [rax], rbx
    mov qword ptr [rax + 8], 1
    jmp 3f
1:  mov qword ptr [rip + wf_bad], 1
    jmp 3f
2:  xor ebx, ebx
3:  mov rax, rbx
    CALLBACK_END 96
FN wf_GlobalLock
    CALLBACK 96
    mov r12, rcx
    mov edi, 3
    call wf_should_fail
    test eax, eax
    jnz 2f
    mov rcx, r12
    API GlobalLock
    mov rbx, rax
    test rax, rax
    jz 3f
    inc qword ptr [rip + wf_locks]
    mov rdi, r12
    call wf_find
    test rax, rax
    jz 3f
    inc qword ptr [rax + 16]
    jmp 3f
2:  xor ebx, ebx
3:  mov rax, rbx
    CALLBACK_END 96
FN wf_GlobalUnlock
    CALLBACK 96
    mov r12, rcx
    dec qword ptr [rip + wf_locks]
    mov rdi, r12
    call wf_find
    test rax, rax
    jz 1f
    dec qword ptr [rax + 16]
1:  mov rcx, r12
    API GlobalUnlock
    CALLBACK_END 96
FN wf_GlobalFree
    CALLBACK 96
    mov r12, rcx
    mov rdi, rcx
    call wf_find
    test rax, rax
    jz 1f
    cmp qword ptr [rax + 8], 1
    jne 1f
    cmp qword ptr [rax + 16], 0
    jne 1f
    mov qword ptr [rax + 8], 3
    jmp 2f
1:  mov qword ptr [rip + wf_bad], 1
2:  mov rcx, r12
    API GlobalFree
    test rax, rax
    jz 3f
    mov qword ptr [rip + wf_bad], 1
3:  CALLBACK_END 96
FN wf_EmptyClipboard
    CALLBACK 96
    mov edi, 4
    call wf_should_fail
    test eax, eax
    jnz 1f
    API EmptyClipboard
    jmp 2f
1:  xor eax, eax
2:  CALLBACK_END 96
FN wf_SetClipboardData
    CALLBACK 96
    mov r12, rcx
    mov r13, rdx
    mov edi, 5
    call wf_should_fail
    test eax, eax
    jnz 3f
    mov rcx, r12
    mov rdx, r13
    API SetClipboardData
    mov rbx, rax
    test rax, rax
    jz 4f
    mov rdi, r13
    call wf_find
    test rax, rax
    jz 1f
    cmp qword ptr [rax + 8], 1
    jne 1f
    cmp qword ptr [rax + 16], 0
    jne 1f
    mov qword ptr [rax + 8], 2
    jmp 4f
1:  mov qword ptr [rip + wf_bad], 1
    jmp 4f
3:  xor ebx, ebx
4:  mov rax, rbx
    CALLBACK_END 96
FN mem_alloc_try
    PROLOGUE
    mov rbx, rdi
    mov edi, 6
    call wf_should_fail
    test eax, eax
    jnz 1f
    mov rdi, rbx
    call wf_real_mem_alloc_try
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

wf_balanced:
    cmp qword ptr [rip + win_clip_depth], 0
    jne wm_fail
    cmp qword ptr [rip + wf_locks], 0
    jne wm_fail
    cmp qword ptr [rip + wf_bad], 0
    jne wm_fail
    ret

# Check what another application can read after partial or rejected publication.
wf_check_os:
    PROLOGUE 96
    mov rcx, [rip + wm_window]
    API OpenClipboard
    test eax, eax
    jz wm_fail
    call win_clip_format
    mov ecx, eax
    API GetClipboardData
    cmp qword ptr [r15], 5
    jne 1f
    test rax, rax
    jnz wm_fail
    jmp 2f
1:  mov rdi, rax
    call win_clip_read_native_handle
    test rax, rax
    jz wm_fail
    cmp rdx, 34
    jne wm_fail
    cmp dword ptr [rax + 12], 1
    jne wm_fail
    cmp qword ptr [rax + 16], 0
    jne wm_fail
    cmp qword ptr [rax + 24], 2
    jne wm_fail
    cmp word ptr [rax + 32], 0x0a4c
    jne wm_fail
    mov rdi, rax
    call mem_free
2:  mov ecx, 13
    API GetClipboardData
    cmp qword ptr [r15], 5
    jne 3f
    cmp qword ptr [r15 + 8], 1
    jne 3f
    test rax, rax
    jnz wm_fail
    jmp 5f
3:  mov rdi, rax
    mov esi, 64
    call win_clip_read_handle
    test rax, rax
    jz wm_fail
    mov r12, rax
    lea rsi, [rip + wm_line]
    cmp qword ptr [r15], 5
    jne 4f
    cmp rdx, 3
    jne wm_fail
    lea rsi, [rip + wf_cut_text]
    jmp 41f
4:  cmp rdx, 2
    jne wm_fail
41: mov rdi, r12
    call memeq
    test eax, eax
    jz wm_fail
    mov rdi, r12
    call mem_free
5:  API CloseClipboard
    call wf_balanced
    EPILOGUE
FN main
    PROLOGUE 96
    mov qword ptr [rip + wm_stage], 100
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
    jnz 1f
    API GetLastError            # why the window could not be made: exit 65536 + the error
    lea ecx, [rax + 65536]
    mov edi, ecx
    call sys_exit
1:
    mov [rip + wm_window], rax
    mov [rip + win_hwnd], rax
    lea rax, [rip + win_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    lea r15, [rip + wf_cases]
.Lwf_case:
    inc qword ptr [rip + wm_stage]
    mov qword ptr [rip + wf_kind], 0
    call wf_reset
    lea rdi, [rip + wm_abc]
    mov esi, 3
    call wm_document
    # Preserve a redo branch and two selected pieces for the guarded Cut path.
    mov rdi, [rip + wm_doc]
    mov esi, 3
    lea rdx, [rip + wm_line]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + wm_doc]
    call doc_undo
    mov rdi, [rip + wm_doc]
    lea rsi, [rip + wf_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne wm_fail
    lea rdi, [rip + wm_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne wm_fail
    mov rdi, [rip + wm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + wm_snapshot], rax
    lea rdi, [rip + wf_cache]
    lea rsi, [rip + clip_sb]
    mov edx, SB_SIZE
    call memcpy
    mov rax, [rip + g_mem_live]
    mov [rip + wf_live], rax
    call wf_reset
    mov qword ptr [rip + win_clip_format_id], 0
    mov rax, [r15]
    mov [rip + wf_kind], rax
    mov rax, [r15 + 8]
    mov [rip + wf_nth], rax
    mov rdi, [rip + wm_doc]
    mov esi, 1
    call editor_multi_copy
    test eax, eax
    jnz wm_fail
    mov rax, [rip + wf_calls]
    cmp rax, [rip + wf_nth]
    jne wm_fail
    call wf_balanced
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + wf_live]
    jne wm_fail
    mov rdi, [rip + wm_doc]
    mov rsi, [rip + wm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz wm_fail
    lea rdi, [rip + clip_sb]
    lea rsi, [rip + wf_cache]
    mov edx, SB_SIZE
    call memeq
    test eax, eax
    jz wm_fail
    lea rdi, [rip + wm_line]
    mov esi, 2
    call ed_clip_linewise
    cmp eax, 1
    jne wm_fail
    mov rax, [rip + wf_count]
    cmp rax, [r15 + 16]
    jne wm_fail
    xor ebx, ebx
    xor r12d, r12d
    lea r13, [rip + wf_records]
.Lwf_records:
    cmp r12, [rip + wf_count]
    jae .Lwf_checked
    cmp qword ptr [r13 + 16], 0
    jne wm_fail
    cmp qword ptr [r13 + 8], 2
    jne 1f
    inc rbx
    jmp 2f
1:  cmp qword ptr [r13 + 8], 3
    jne wm_fail
2:  add r13, 32
    inc r12
    jmp .Lwf_records
.Lwf_checked:
    cmp rbx, [r15 + 24]
    jne wm_fail
    # Redo remains usable after each rejection, and a valid writer can immediately retry.
    mov qword ptr [rip + wf_kind], 0
    call wf_check_os
    call wf_reset
    mov rdi, [rip + wm_doc]
    call doc_redo
    lea rdi, [rip + wf_redo]
    mov esi, 4
    call wm_check
    lea rdi, [rip + wm_abc]
    mov esi, 3
    xor edx, edx
    call ed_clip_set
    cmp eax, 1
    jne wm_fail
    call wf_balanced
    mov rdi, [rip + wm_snapshot]
    call mem_free
    call wm_cleanup
    add r15, 32
    cmp qword ptr [r15], 0
    jne .Lwf_case
    # Detached-read OOM: plain fallback, native-only failure, registration fallback.
    mov r15d, 0
.Lwf_read:
    mov qword ptr [rip + wf_kind], 0
    call wf_reset
    inc qword ptr [rip + wm_stage]
    xor edi, edi
    xor esi, esi
    call wm_document
    lea rdi, [rip + wm_line]
    mov esi, 2
    xor edx, edx
    xor ecx, ecx
    call wm_encode
    mov qword ptr [rip + wm_plain], 1
    cmp r15, 1
    jne 1f
    mov qword ptr [rip + wm_plain], 0
1:  call wm_seed
    call wf_reset
    mov qword ptr [rip + wf_kind], 6
    cmp r15, 2
    jne 2f
    mov qword ptr [rip + wf_kind], 1
    mov qword ptr [rip + win_clip_format_id], 0
2:  mov qword ptr [rip + wf_nth], 1
    call wm_request
    call wf_balanced
    cmp qword ptr [rip + wf_calls], 1
    jne wm_fail
    cmp r15, 1
    je 3f
    lea rdi, [rip + wm_fallback_text]
    mov esi, 8
    call wm_check
    jmp 4f
3:  xor edi, edi
    xor esi, esi
    call wm_check
4:  mov qword ptr [rip + wf_kind], 0
    mov rdi, [rip + wm_doc]
    call doc_undo
    call wm_request
    lea rdi, [rip + wm_line]
    mov esi, 2
    call wm_check
    call wf_balanced
    call wm_cleanup
    inc r15
    cmp r15, 3
    jb .Lwf_read
    mov rcx, [rip + wm_window]
    API DestroyWindow
    lea rdi, [rip + wf_ok]
    mov esi, 30
    call log_write
    xor eax, eax
    EPILOGUE
