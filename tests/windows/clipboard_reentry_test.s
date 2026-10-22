# Sent window messages from another clipboard owner must wait until the edit transaction ends.
.include "win.inc"
.bss
.p2align 4
record: .zero WD_SIZE
rect: .zero 16
keyboard: .zero 256
saved_keyboard: .zero 256
target: .quad 0
owner: .quad 0
old_hwnd: .quad 0
old_clip_set: .quad 0
old_clip_get: .quad 0
old_clip_write: .quad 0
mode: .quad 0
notifications: .quad 0
callback_bad: .quad 0
snapshot: .quad 0
sn_snapshot: .quad 0
fixture_doc: .quad 0
fixture_sn: .quad 0
render_handle: .quad 0
.text
# A hidden window with the specified native callback and wide class name.
make_window:
    PROLOGUE 192
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, 80
    call memset
    xor ecx, ecx
    API GetModuleHandleW
    mov [rsp + 120], rax
    mov dword ptr [rsp + 96], 80
    mov [rsp + 104], rbx
    mov [rsp + 160], r12
    lea rcx, [rsp + 96]
    API RegisterClassExW
    test ax, ax
    jnz 2f
    API GetLastError            # why the class could not be registered: exit 131072 + the error
    lea ecx, [rax + 131072]
    mov edi, ecx
    SYS SYS_exit
2:
    xor ecx, ecx
    mov rdx, r12
    mov r8, r12
    xor r9d, r9d
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 1
    mov qword ptr [rsp + 56], 1
    mov qword ptr [rsp + 64], 0
    mov qword ptr [rsp + 72], 0
    mov rax, [rsp + 120]
    mov [rsp + 80], rax
    mov qword ptr [rsp + 88], 0
    API CreateWindowExW
    test rax, rax
    jnz 9f
    API GetLastError            # why the window could not be made: exit 65536 + the error
    lea ecx, [rax + 65536]
    mov edi, ecx
    SYS SYS_exit
9:  EPILOGUE

# Claim ownership with delayed text rendering. EmptyClipboard must notify this window next time.
seed_owner:
    PROLOGUE 96
    mov qword ptr [rip + mode], 0
    mov rcx, [rip + owner]
    API OpenClipboard
    test eax, eax
    jz failed
    API EmptyClipboard
    test eax, eax
    jz failed
    mov ecx, 13
    xor edx, edx
    API SetClipboardData
    API CloseClipboard
    mov qword ptr [rip + notifications], 0
    EPILOGUE

# Send a scalar event to the real rhun procedure.
# Internal args message, WPARAM, LPARAM.
send:
    PROLOGUE 96
    mov r9, rdx
    mov r8, rsi
    mov edx, edi
    mov rcx, [rip + target]
    API SendMessageW
    EPILOGUE

owner_proc:
    CALLBACK 96
    cmp edx, 0x305             # WM_RENDERFORMAT: GetClipboardData calls the owner synchronously
    je .Lowner_render
    cmp edx, 0x307             # WM_DESTROYCLIPBOARD
    jne .Lowner_default
    cmp qword ptr [rip + mode], 0
    je .Lowner_zero
.Lowner_notify:
    inc qword ptr [rip + notifications]
    mov r12, [rip + mode]
    mov ebx, 1
    cmp r12, 2
    je 0f
    cmp r12, 6
    je 0f
    cmp r12, 8
    jne 1f
0:
    mov ebx, WD_CAP + 1
1:  mov edi, 0x102
    mov esi, 'a'
    cmp r12, 4
    jne 2f
    mov esi, 'b'
2:  xor edx, edx
    call send
    dec ebx
    jnz 1b
    cmp r12, 1
    je 0f
    cmp r12, 5
    je 0f
    cmp r12, 7
    jne 3f
0:
    mov edi, 0x10
    xor esi, esi
    xor edx, edx
    call send
3:  call win_messages          # even an explicit nested pump cannot dispatch the queue
    mov rdi, [rip + fixture_doc]
    mov rsi, [rip + snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz .Lowner_bad
    mov rdi, [rip + fixture_sn]
    mov rsi, [rip + sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz .Lowner_bad
    cmp dword ptr [rip + g_quit], 0
    je .Lowner_zero
.Lowner_bad:
    mov qword ptr [rip + callback_bad], 1
.Lowner_zero:
    xor eax, eax
    CALLBACK_END 96
.Lowner_render:
    cmp qword ptr [rip + mode], 7
    jb 4f
    cmp r8d, [rip + win_clip_format_id]
    jne .Lowner_zero
    mov ecx, r8d
    jmp 5f
4:
    cmp r8d, 13
    jne .Lowner_zero
    cmp qword ptr [rip + mode], 5
    jb .Lowner_zero
    mov ecx, 13
5:
    mov rdx, [rip + render_handle]
    API SetClipboardData      # delayed rendering must not reopen the clipboard
    test rax, rax
    jz .Lowner_bad
    mov qword ptr [rip + render_handle], 0
    jmp .Lowner_notify
.Lowner_default:
    API DefWindowProcW
    CALLBACK_END 96

# Snapshot the complete DOC and live snippet, including undo/redo and selection pointers.
take_snapshot:
    PROLOGUE 96
    mov rdi, [rip + snapshot]
    call mem_free
    mov rdi, [rip + sn_snapshot]
    call mem_free
    mov rdi, [rip + fixture_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + snapshot], rax
    mov rdi, [rip + fixture_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + sn_snapshot], rax
    EPILOGUE
same_snapshot:
    PROLOGUE 96
    mov rdi, [rip + fixture_doc]
    mov rsi, [rip + snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rip + fixture_sn]
    mov rsi, [rip + sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    cmp qword ptr [rip + callback_bad], 0
    jne failed
    cmp dword ptr [rip + g_quit], 0
    jne failed
    EPILOGUE

discard:
    PROLOGUE 96
1:  lea rdi, [rip + record]
    call win_deferred_pop
    test eax, eax
    jnz 1b
    EPILOGUE

# Assert exact current text; the caller supplies bytes and length.
check_text:
    PROLOGUE 128
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rip + fixture_doc]
    call doc_len
    cmp rax, r12
    jne failed
    mov rdi, [rip + fixture_doc]
    xor esi, esi
    mov rdx, r12
    lea rcx, [rsp + 96]
    call doc_copy
    lea rdi, [rsp + 96]
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz failed
    EPILOGUE

# A clipboard action replayed by the pump cannot recursively drain the following input.
replay_clip_set:
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    call win_messages
    call same_snapshot
    mov rdi, rbx
    mov rsi, r12
    call win_clip_set
    EPILOGUE

# Give each read a selected field and live redo branch, independent of previous input replay.
reset_read_doc:
    PROLOGUE 96
    mov rdi, [rip + fixture_doc]
    call doc_free
    mov qword ptr [rip + fixture_sn], 0
    call doc_new
    mov [rip + fixture_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + original]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + fixture_doc]
    mov esi, 1
    lea rdx, [rip + original]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + fixture_doc]
    call doc_undo
    lea rdi, [rip + original]
    mov esi, 1
    call snippet_new
    mov [rip + fixture_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + fixture_sn]
    call snippet_validate
    cmp eax, 1
    jne failed
    mov rdi, [rip + fixture_doc]
    mov rsi, [rip + fixture_sn]
    xor edx, edx
    call snippet_attach
    mov rax, [rip + fixture_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 0
    mov dword ptr [rip + g_quit], 0
    mov qword ptr [rip + callback_bad], 0
    call take_snapshot
    EPILOGUE

prepare_render:
    PROLOGUE 96
    call seed_owner
    mov ecx, 2
    mov edx, 8
    API GlobalAlloc
    test rax, rax
    jz failed
    mov [rip + render_handle], rax
    mov rcx, rax
    API GlobalLock
    test rax, rax
    jz failed
    mov dword ptr [rax], 'P'
    mov dword ptr [rax + 4], 0
    mov rcx, [rip + render_handle]
    API GlobalUnlock
    EPILOGUE

# Delayed private format invokes the same owner callback with a counted envelope.
prepare_native_render:
    PROLOGUE 96
    call seed_owner
    call win_clip_format
    mov ebx, eax
    mov rcx, [rip + owner]
    API OpenClipboard
    test eax, eax
    jz failed
    mov ecx, ebx
    xor edx, edx
    API SetClipboardData
    API CloseClipboard
    lea rdi, [rip + pasted]
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    call clip_wire_encode
    test rax, rax
    jz failed
    mov rbx, rax
    mov r12, rdx
    mov ecx, 2
    API GlobalAlloc
    test rax, rax
    jz failed
    mov [rip + render_handle], rax
    mov rcx, rax
    API GlobalLock
    test rax, rax
    jz failed
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rcx, [rip + render_handle]
    API GlobalUnlock
    mov rdi, rbx
    call mem_free
    EPILOGUE

# Install counted foreign UTF-16 storage. Fill actual rounded padding to expose missing NULs.
seed_read_bytes:
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [rip + mode], 0
    mov rcx, [rip + owner]
    API OpenClipboard
    test eax, eax
    jz failed
    API EmptyClipboard
    test eax, eax
    jz failed
    test r12, r12
    jz 1f
    mov ecx, 2
    mov rdx, r12
    API GlobalAlloc
    test rax, rax
    jz failed
    mov r13, rax
    mov rcx, rax
    API GlobalSize
    mov r14, rax
    mov rcx, r13
    API GlobalLock
    test rax, rax
    jz failed
    mov [rsp + 80], rax
    mov rdi, rax
    mov esi, 0x41
    mov rdx, r14
    call memset
    mov rdi, [rsp + 80]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rcx, r13
    API GlobalUnlock
    mov ecx, 13
    mov rdx, r13
    API SetClipboardData
    test rax, rax
    jz failed
1:  API CloseClipboard
    EPILOGUE

prime_line_cache:
    lea rdi, [rip + copied]
    mov esi, 6
    mov edx, 1
    jmp ed_clip_set

FN main
    PROLOGUE 96
    mov r15d, 10
    mov rax, [rip + win_hwnd]
    mov [rip + old_hwnd], rax
    mov rax, [rip + g_plat + P_clip_set]
    mov [rip + old_clip_set], rax
    mov rax, [rip + g_plat + P_clip_get]
    mov [rip + old_clip_get], rax
    mov rax, [rip + g_plat + P_clip_write]
    mov [rip + old_clip_write], rax
    mov qword ptr [rip + g_plat + P_clip_write], 0
    lea rcx, [rip + saved_keyboard]
    API GetKeyboardState
    test eax, eax
    mov r15d, 1001   # which check of stage 10
    jz failed
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    test eax, eax
    mov r15d, 1002   # which check of stage 10
    jz failed
    lea rdi, [rip + win_wndproc]
    lea rsi, [rip + target_class]
    call make_window
    test rax, rax
    mov r15d, 1003   # which check of stage 10
    jz failed
    mov [rip + target], rax
    mov [rip + win_hwnd], rax
    lea rdi, [rip + owner_proc]
    lea rsi, [rip + owner_class]
    call make_window
    test rax, rax
    mov r15d, 1004   # which check of stage 10
    jz failed
    mov [rip + owner], rax
    call keys_init
    lea rax, [rip + win_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    call doc_new
    mov [rip + fixture_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + original]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + fixture_doc]
    mov esi, 1
    lea rdx, [rip + original]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + fixture_doc]
    call doc_undo              # keep a live redo branch for rejected Cut
    lea rdi, [rip + original]
    mov esi, 1
    call snippet_new
    mov [rip + fixture_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + fixture_sn]
    call snippet_validate
    cmp eax, 1
    mov r15d, 1005   # which check of stage 10
    jne failed
    mov rdi, [rip + fixture_doc]
    mov rsi, [rip + fixture_sn]
    xor edx, edx
    call snippet_attach
    mov rax, [rip + fixture_doc]
    mov rdi, rax
    lea rsi, [rip + reentry_pairs]
    mov edx, 2
    call doc_selections_set
    call take_snapshot

    # Every app-callback message is deferred, including pointer-owning DPI/settings payloads.
    mov r15d, 20
    mov qword ptr [rip + win_clip_depth], 2
    lea r12, [rip + message_ids]
1:  mov edi, [r12]
    test edi, edi
    jz 2f
    mov esi, 96
    lea rdx, [rip + rect]
    call send
    add r12, 4
    jmp 1b
2:  cmp qword ptr [rip + win_deferred_count], 21
    jne failed
    call win_messages
    lea rdi, [rip + record]
    call win_deferred_pop
    test eax, eax
    jnz failed
    call same_snapshot
    mov qword ptr [rip + win_clip_depth], 0
    lea r12, [rip + message_ids]
3:  mov ebx, [r12]
    test ebx, ebx
    jz 6f
    lea rdi, [rip + record]
    call win_deferred_pop
    cmp eax, 1
    jne failed
    cmp ebx, [rip + record + WD_message]
    jne failed
    cmp ebx, 0x1a
    jne 4f
    cmp qword ptr [rip + record + WD_lparam], 0
    jne failed
4:  cmp ebx, 0x2e0
    jne 5f
    lea rax, [rip + record + WD_rect]
    cmp rax, [rip + record + WD_lparam]
    jne failed
5:  add r12, 4
    jmp 3b
6:  cmp qword ptr [rip + win_deferred_count], 0
    jne failed

    # RECT must be owned and survive its source changing before dequeue.
    mov r15d, 30
    mov dword ptr [rip + rect], 11
    mov dword ptr [rip + rect + 12], 44
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x2e0
    mov esi, 96
    lea rdx, [rip + rect]
    call send
    mov dword ptr [rip + rect], 99
    mov dword ptr [rip + rect + 12], 88
    mov qword ptr [rip + win_clip_depth], 0
    lea rdi, [rip + record]
    call win_deferred_pop
    cmp eax, 1
    jne failed
    cmp dword ptr [rip + record + WD_rect], 11
    jne failed
    cmp dword ptr [rip + record + WD_rect + 12], 44
    jne failed

    # Ring wrap and exact bounded capacity, without unbounded allocation.
    mov r15d, 40
    mov r14, [rip + win_deferred_overflow]
    mov qword ptr [rip + win_clip_depth], 1
    xor r12d, r12d
1:  mov edi, 0x102
    mov esi, r12d
    xor edx, edx
    call send
    inc r12d
    cmp r12d, WD_CAP + 1
    jb 1b
    cmp qword ptr [rip + win_deferred_count], WD_CAP
    jne failed
    inc r14
    cmp r14, [rip + win_deferred_overflow]
    jne failed
    mov qword ptr [rip + win_clip_depth], 0
    xor r12d, r12d
2:  lea rdi, [rip + record]
    call win_deferred_pop
    cmp eax, 1
    jne failed
    cmp r12, [rip + record + WD_wparam]
    jne failed
    inc r12d
    cmp r12d, WD_CAP
    jb 2b
    call same_snapshot

    # Capture Ctrl+Shift at enqueue; a later keyboard change cannot alter queued events.
    mov r15d, 50
    mov byte ptr [rip + keyboard + 16], 128
    mov byte ptr [rip + keyboard + 17], 128
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x102
    mov esi, 'z'
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    mov byte ptr [rip + keyboard + 16], 0
    mov byte ptr [rip + keyboard + 17], 0
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    lea rdi, [rip + record]
    call win_deferred_pop
    cmp dword ptr [rip + record + WD_mods], MOD_CTRL | MOD_SHIFT
    jne failed
    # Repeat without manually popping: Ctrl suppresses character even though live Ctrl is clear.
    mov byte ptr [rip + keyboard + 17], 128
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x102
    mov esi, 'z'
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    mov byte ptr [rip + keyboard + 17], 0
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    call win_messages
    call same_snapshot

    # Real ownership notification: characters/close cannot touch DOC, snippet, redo, or quit.
    mov r15d, 60
    call seed_owner
    mov qword ptr [rip + mode], 1
    lea rdi, [rip + copied]
    mov esi, 6
    call win_clip_set
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + win_deferred_count], 2
    jne failed
    call same_snapshot
    call discard

    # Overflow after OS transfer still rejects Cut, preserving the entire editor transaction.
    mov r15d, 70
    lea rdi, [rip + copied]
    mov esi, 6
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne failed
    call seed_owner
    mov qword ptr [rip + mode], 2
    call cmd_cut
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_deferred_count], WD_CAP
    jne failed
    call same_snapshot
    lea rdi, [rip + copied]
    mov esi, 6
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    call discard

    # A synchronous b arriving after the setter must wait behind a from its notification.
    mov r15d, 80
    call seed_owner
    mov qword ptr [rip + mode], 3
    lea rdi, [rip + copied]
    mov esi, 6
    call win_clip_set
    cmp eax, 1
    jne failed
    mov edi, 0x102
    mov esi, 'b'
    xor edx, edx
    call send
    call same_snapshot
    call win_messages
    lea rdi, [rip + ab]
    mov esi, 2
    call check_text
    cmp qword ptr [rip + win_deferred_count], 0
    jne failed
    call win_messages
    lea rdi, [rip + ab]
    mov esi, 2
    call check_text

    # Reset to original selection and live snippet for replay-induced clipboard recursion.
    mov r15d, 90
    # The previous session may have ended while typing. Do not reuse its saved pointer.
    mov qword ptr [rip + fixture_sn], 0
    mov rdi, [rip + sn_snapshot]
    call mem_free
    mov qword ptr [rip + sn_snapshot], 0
    mov rdi, [rip + fixture_doc]
    call doc_len
    mov rdx, rax
    xor esi, esi
    mov ecx, 1
    call doc_delete
    mov rdi, [rip + fixture_doc]
    xor esi, esi
    lea rdx, [rip + original]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rax, [rip + fixture_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 0
    lea rdi, [rip + original]
    mov esi, 1
    call snippet_new
    mov [rip + fixture_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + fixture_sn]
    call snippet_validate
    mov rdi, [rip + fixture_doc]
    mov rsi, [rip + fixture_sn]
    xor edx, edx
    call snippet_attach
    call take_snapshot
    call seed_owner
    mov qword ptr [rip + mode], 4
    mov byte ptr [rip + keyboard + 17], 128
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x100
    mov esi, 'C'
    xor edx, edx
    call send
    mov byte ptr [rip + keyboard + 17], 0
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    mov edi, 0x102
    mov esi, 'a'
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    call same_snapshot
    lea rax, [rip + replay_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    call win_messages
    lea rax, [rip + win_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + callback_bad], 0
    jne failed
    lea rdi, [rip + ab]
    mov esi, 2
    call check_text

    # A queued keydown must not be translated into an extra WM_CHAR on replay.
    mov r15d, 100
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x100
    mov esi, 'Z'
    mov edx, 0x2c0001
    call send
    mov edi, 0x102
    mov esi, 'z'
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    call win_messages
    lea rdi, [rip + abz]
    mov esi, 3
    call check_text

    # Ignore a deferred event whose original window no longer exists as the active HWND.
    mov r15d, 110
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x102
    mov esi, '!'
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    mov qword ptr [rip + win_hwnd], 0
    call win_messages
    mov rax, [rip + target]
    mov [rip + win_hwnd], rax
    lea rdi, [rip + abz]
    mov esi, 3
    call check_text

    # Shift selection uses its enqueue-time modifier after live keyboard state clears.
    mov r15d, 120
    mov byte ptr [rip + keyboard + 16], 128
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    mov qword ptr [rip + win_clip_depth], 1
    mov edi, 0x100
    mov esi, 0x25              # VK_LEFT
    xor edx, edx
    call send
    mov qword ptr [rip + win_clip_depth], 0
    mov byte ptr [rip + keyboard + 16], 0
    lea rcx, [rip + keyboard]
    API SetKeyboardState
    call win_messages
    mov rax, [rip + fixture_doc]
    cmp qword ptr [rax + DOC_cur], 2
    jne failed
    cmp qword ptr [rax + DOC_anchor], 3
    jne failed

    # The owner may send input/close while rendering a read. Paste precedes their replay.
    mov r15d, 130
    call reset_read_doc
    call prepare_render
    mov qword ptr [rip + mode], 5
    call win_clip_get
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + callback_bad], 0
    jne failed
    cmp dword ptr [rip + g_quit], 0
    jne failed
    lea rdi, [rip + pasted]
    mov esi, 1
    call check_text
    cmp qword ptr [rip + win_deferred_count], 2
    jne failed
    call win_messages
    lea rdi, [rip + pasted_input]
    mov esi, 2
    call check_text
    cmp dword ptr [rip + g_quit], 1
    jne failed
    cmp qword ptr [rip + win_deferred_count], 0
    jne failed

    # Overflow during a delayed read rejects Paste without changing DOC/snippet/redo.
    mov r15d, 140
    call reset_read_doc
    call prepare_render
    mov qword ptr [rip + mode], 6
    call win_clip_get
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_deferred_count], WD_CAP
    jne failed
    call same_snapshot
    call discard

    mov r15d, 150
    call reset_read_doc
    lea rdi, [rip + pasted_unicode_wide]
    mov esi, 12
    call seed_read_bytes
    call win_clip_get
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    lea rdi, [rip + pasted_unicode]
    mov esi, 10
    call check_text
    mov rdi, [rip + fixture_doc]
    call doc_undo
    lea rdi, [rip + original]
    mov esi, 1
    call check_text
    mov rdi, [rip + fixture_doc]
    call doc_redo
    lea rdi, [rip + pasted_unicode]
    mov esi, 10
    call check_text

    # Missing and malformed clipboard contents preserve the full DOC, live snippet and cache.
    mov r15d, 160
    call reset_read_doc
    call prime_line_cache
    test eax, eax
    jz failed
    xor edi, edi
    xor esi, esi
    call seed_read_bytes
    call win_clip_get
    call same_snapshot
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp dword ptr [rip + g_clip_line], 1
    jne failed
    mov r15d, 170
    lea rdi, [rip + pasted_invalid_wide]
    mov esi, 4
    call seed_read_bytes
    call win_clip_get
    call same_snapshot
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp dword ptr [rip + g_clip_line], 1
    jne failed
    # Unterminated allocations are checked directly by clipboard_read_test: the OS may
    # normalize standard text formats when transferring them through the system clipboard.
    # Valid empty text reaches observation without an edit or snippet cancellation.
    mov r15d, 190
    lea rdi, [rip + pasted_empty_wide]
    mov esi, 2
    call seed_read_bytes
    call win_clip_get
    call same_snapshot
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp dword ptr [rip + g_clip_line], 0
    jne failed
    # The real queued getter snapshots its token before delayed rendering reentry.
    mov r15d, 191
    lea rax, [rip + win_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    call reset_read_doc
    call prepare_render
    mov qword ptr [rip + mode], 5
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    lea rdi, [rip + pasted]
    mov esi, 1
    call check_text
    cmp qword ptr [rip + win_deferred_count], 2
    jne failed
    call discard
    # Overflow completes failure and frees its queued context without editing.
    mov r15d, 192
    call reset_read_doc
    call prepare_render
    mov qword ptr [rip + mode], 6
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    call same_snapshot
    call discard
    # A later valid request can follow the failed retrieval.
    mov r15d, 193
    lea rdi, [rip + pasted_unicode_wide]
    mov esi, 12
    call seed_read_bytes
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    lea rdi, [rip + pasted_unicode]
    mov esi, 10
    call check_text
    call app_clip_timeout
    cmp eax, -1
    jne failed
    # Native writer ownership changes defer input and close until after the transaction.
    mov r15d, 194
    call reset_read_doc
    lea rax, [rip + win_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    call seed_owner
    mov qword ptr [rip + mode], 1
    lea rdi, [rip + copied]
    mov esi, 6
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + win_deferred_count], 2
    jne failed
    call same_snapshot
    call discard
    # Native publication can complete while overflow still rejects Cut and cache changes.
    mov r15d, 195
    call seed_owner
    mov qword ptr [rip + mode], 2
    call cmd_cut
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + win_deferred_count], WD_CAP
    jne failed
    call same_snapshot
    lea rdi, [rip + copied]
    mov esi, 6
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    call discard
    # Native setter notifications retain order relative to subsequent synchronous messages.
    mov r15d, 196
    call seed_owner
    mov qword ptr [rip + mode], 3
    lea rdi, [rip + copied]
    mov esi, 6
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne failed
    mov edi, 0x102
    mov esi, 'b'
    xor edx, edx
    call send
    call same_snapshot
    call win_messages
    lea rdi, [rip + ab]
    mov esi, 2
    call check_text
    cmp qword ptr [rip + win_deferred_count], 0
    jne failed
    # Private-format delayed rendering also defers editor input and close.
    mov r15d, 200
    call reset_read_doc
    call prepare_native_render
    mov qword ptr [rip + mode], 7
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + callback_bad], 0
    jne failed
    cmp qword ptr [rip + win_deferred_count], 2
    jne failed
    lea rdi, [rip + pasted]
    mov esi, 1
    call check_text
    call win_messages
    lea rdi, [rip + pasted_input]
    mov esi, 2
    call check_text
    cmp dword ptr [rip + g_quit], 1
    jne failed
    mov r15d, 201
    call reset_read_doc
    call prepare_native_render
    mov qword ptr [rip + mode], 8
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    cmp qword ptr [rip + win_clip_depth], 0
    jne failed
    cmp qword ptr [rip + notifications], 1
    jne failed
    cmp qword ptr [rip + win_deferred_count], WD_CAP
    jne failed
    call same_snapshot
    call discard
    mov r15d, 202
    mov qword ptr [rip + mode], 0
    call app_clip_request
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    lea rdi, [rip + pasted]
    mov esi, 1
    call check_text
    xor r15d, r15d
    jmp cleanup
failed:
    # Helpers may fail with their own frames. Exit with the current verification stage.
    mov edi, r15d
    SYS SYS_exit
cleanup:
    mov qword ptr [rip + mode], 0
    mov rcx, [rip + owner]
    API DestroyWindow
    mov rcx, [rip + target]
    API DestroyWindow
    mov rax, [rip + old_hwnd]
    mov [rip + win_hwnd], rax
    mov rax, [rip + old_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    mov rax, [rip + old_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    mov rax, [rip + old_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    lea rcx, [rip + saved_keyboard]
    API SetKeyboardState
    mov rdi, [rip + fixture_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, [rip + snapshot]
    call mem_free
    mov rdi, [rip + sn_snapshot]
    call mem_free
    xor eax, eax
    EPILOGUE
.section .rodata
.p2align 2
message_ids:
    .long 0x10,5,6,0x1a,0x2e0,0x200,0x201,0x202,0x203,0x204,0x205,0x206
    .long 0x207,0x208,0x209,0x20a,0x20e,0x102,0x106,0x100,0x104,0
reentry_pairs: .quad 1,0,1,1
original: .ascii "x"
copied: .ascii "copied"
pasted: .ascii "P"
pasted_input: .ascii "Pa"
pasted_unicode_wide: .short 'a',0xe9,0x6c34,0xd83d,0xde00,0
pasted_unicode: .ascii "a\303\251\346\260\264\360\237\230\200"
pasted_invalid_wide: .short 0xd800,0
pasted_empty_wide: .short 0
ab: .ascii "ab"
abz: .ascii "abz"
target_class: .short 'r','h','u','n','-','r','e','e','n','t','r','y','-','t',0
owner_class: .short 'r','h','u','n','-','r','e','e','n','t','r','y','-','o',0
