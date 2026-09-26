# remembers the open files of a project (~/.local/state/rhun/<project path>.session)
.include "rhun.inc"

.bss
.p2align 3
path_sb: .zero SB_SIZE
out: .zero SB_SIZE

.text

# session_file() -> cstr path for the current project, or 0
session_file:
    PROLOGUE
    lea rdi, [rip + path_sb]
    call sb_clear
    mov rbx, [rip + g_project]
    test rbx, rbx
    jz 8f
    lea rdi, [rip + .Lstate]
    call getenv
    test rax, rax
    jz 1f
    lea rdi, [rip + path_sb]
    mov rsi, rax
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 8f
    lea rdi, [rip + path_sb]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + path_sb]
    lea rsi, [rip + .Llocal_state]
    call sb_push_cstr
2:  lea rdi, [rip + path_sb]
    lea rsi, [rip + .Lrhun_dir]
    call sb_push_cstr
    mov rdi, [rip + path_sb + SB_ptr]
    call mkdir_p
    lea rdi, [rip + path_sb]
    mov esi, '/'
    call sb_push_byte
3:  movzx esi, byte ptr [rbx]
    test esi, esi
    jz 4f
    cmp esi, '/'
    jne 31f
    mov esi, '%'
31: lea rdi, [rip + path_sb]
    call sb_push_byte
    inc rbx
    jmp 3b
4:  lea rdi, [rip + path_sb]
    lea rsi, [rip + .Lext]
    call sb_push_cstr
    mov rax, [rip + path_sb + SB_ptr]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# session_save(): "path<TAB>cursor" per open file, "*" marks the active one
FN session_save
    PROLOGUE
    cmp dword ptr [rip + cfg_restore_session], 0
    je 9f
    call session_file
    test rax, rax
    jz 9f
    mov r13, rax
    lea rdi, [rip + out]
    call sb_clear
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 2f
    cmp qword ptr [r12 + DOC_path], 0
    je 2f
    cmp rbx, [rip + g_tab_cur]
    jne 11f
    lea rdi, [rip + out]
    mov esi, '*'
    call sb_push_byte
11: lea rdi, [rip + out]
    mov rsi, [r12 + DOC_path]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, 9
    call sb_push_byte
    lea rdi, [rip + out]
    mov rsi, [r12 + DOC_cur]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
2:  inc rbx
    jmp 1b
3:  mov rdi, r13
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    test rsi, rsi
    jnz 4f
    lea rsi, [rip + .Lempty]
4:  call file_write_all
9:  EPILOGUE

# session_restore(): reopen the files of the last session of this project
FN session_restore
    PROLOGUE 16
    cmp dword ptr [rip + cfg_restore_session], 0
    je 9f
    call session_file
    test rax, rax
    jz 9f
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    mov r13, rdx
    mov qword ptr [rsp], -1     # active tab
    xor r14d, r14d
1:  cmp r14, r13
    jae 8f
    mov r15, r14
2:  cmp r15, r13
    jae 3f
    cmp byte ptr [r12 + r15], 10
    je 3f
    inc r15
    jmp 2b
3:  mov byte ptr [r12 + r15], 0
    lea rbx, [r12 + r14]
    xor ecx, ecx
    cmp byte ptr [rbx], '*'
    jne 4f
    inc rbx
    mov ecx, 1
4:  mov [rsp + 8], ecx
    # split at the tab
    mov rdi, rbx
5:  mov al, [rdi]
    test al, al
    jz 6f
    cmp al, 9
    je 6f
    inc rdi
    jmp 5b
6:  mov byte ptr [rdi], 0
    lea rsi, [rdi + 1]
    push rsi
    push rsi
    mov rdi, rbx
    call file_mtime
    pop rsi
    pop rsi
    test rax, rax
    jz 7f
    push rsi
    push rsi
    mov rdi, rbx
    call app_open_file
    pop rsi
    pop rsi
    test rax, rax
    js 7f
    cmp dword ptr [rsp + 8], 0
    je 61f
    mov [rsp], rax
61: mov rdi, rsi
    call strlen
    mov rdi, rsi
    mov rsi, rax
    call parse_u64
    mov rcx, [rip + g_doc]
    test rcx, rcx
    jz 7f                       # an image
    push rax
    mov rdi, rcx
    call doc_len
    pop rcx
    cmp rcx, rax
    cmova rcx, rax
    mov rax, [rip + g_doc]
    mov [rax + DOC_cur], rcx
    mov [rax + DOC_anchor], rcx
7:  lea r14, [r15 + 1]
    jmp 1b
8:  mov rdi, r12
    call mem_free
    mov rdi, [rsp]
    test rdi, rdi
    js 9f
    call app_activate_tab
9:  EPILOGUE

.section .rodata
.Lstate: .asciz "XDG_STATE_HOME"
.Lhome: .asciz "HOME"
.Llocal_state: .asciz "/.local/state"
.Lrhun_dir: .asciz "/rhun"
.Lext: .asciz ".session"
.Lempty: .asciz ""
