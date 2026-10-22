.include "rhun.inc"
.bss
.p2align 3
capture: .zero SB_SIZE
field: .zero TF_SIZE
out: .zero SB_SIZE
accept: .quad 0
calls: .quad 0
last_ptr: .quad 0
.text
stub:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    inc qword ptr [rip + calls]
    mov [rip + last_ptr], rdi
    lea rdi, [rip + capture]
    call sb_clear
    lea rdi, [rip + capture]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    mov rax, [rip + accept]
    EPILOGUE
prime:
    mov qword ptr [rip + accept], 1
    lea rdi, [rip + old_text]
    mov esi, 4
    mov edx, 1
    call ed_clip_set
    mov qword ptr [rip + calls], 0
    ret
FN main
    PROLOGUE 64
    mov rax, [rip + g_plat + P_clip_set]
    mov [rsp + 48], rax
    lea rax, [rip + stub]
    mov [rip + g_plat + P_clip_set], rax
    call prime
    cmp eax, 1
    jne failed
    mov r15, [rip + g_mem_live]
    lea r12, [rip + vectors]
    mov r13d, 1
.Lcase:
    cmp qword ptr [r12 + 8], -2
    je .Lcut_cases
    call prime
    mov rax, [r12 + 24]
    mov [rip + accept], rax
    mov rdi, [r12]
    cmp qword ptr [r12 + 48], 0
    je 1f
    mov rdi, [rip + last_ptr]
1:  mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    call ed_clip_set
    cmp rax, [r12 + 32]
    jne failed
    mov rax, [rip + calls]
    cmp rax, [r12 + 40]
    jne failed
    cmp qword ptr [r12 + 32], 0
    jne .Laccepted
    lea rdi, [rip + old_text]
    mov esi, 4
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    jmp .Lcase_free
.Laccepted:
    mov rdi, [r12]
    cmp qword ptr [r12 + 48], 0
    je 2f
    lea rdi, [rip + old_text]
2:  mov rsi, [r12 + 8]
    call ed_clip_linewise
    cmp rax, [r12 + 16]
    jne failed
    mov rax, [rip + capture + SB_len]
    cmp rax, [r12 + 8]
    jne failed
    mov rdi, [rip + capture + SB_ptr]
    mov rsi, [r12]
    cmp qword ptr [r12 + 48], 0
    je 3f
    lea rsi, [rip + old_text]
3:  mov rdx, [r12 + 8]
    call memeq
    test eax, eax
    jz failed
.Lcase_free:
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 56
    inc r13
    jmp .Lcase
.Lcut_cases:
    xor r12d, r12d
.Lcut_case:
    lea r13, [r12 + 100]
    call prime
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + source]
    mov ecx, 11
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 11
    lea rdx, [rip + extra]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + source]
    mov esi, 11
    call snippet_new
    mov r14, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 11
    xor r8d, r8d
    call snippet_add
    mov rdi, r14
    call snippet_validate
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call snippet_attach
    mov rdi, rbx
    lea rsi, [rip + selected]
    mov edx, 1
    cmp r12, 1
    jne 4f
    lea rsi, [rip + collapsed]
4:  cmp r12, 2
    jne 5f
    lea rsi, [rip + multiple]
    mov edx, 2
5:  call doc_selections_set
    cmp r12, 3
    jne 6f
    or dword ptr [rbx + DOC_flags], DF_READONLY
6:  cmp r12, 4
    jne 7f
    mov qword ptr [rbx + DOC_cap], DOC_MULTI_BYTES_MAX + 4096
    mov qword ptr [rbx + DOC_cur], DOC_MULTI_BYTES_MAX + 1
    mov qword ptr [rbx + DOC_anchor], 0
7:  mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp], rax
    mov rdi, r14
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 8], rax
    mov qword ptr [rip + accept], 0
    mov qword ptr [rip + calls], 0
    call cmd_cut
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, r14
    mov rsi, [rsp + 8]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    lea rdi, [rip + old_text]
    mov esi, 4
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    mov rax, [rip + calls]
    cmp r12, 3
    jae 8f
    cmp rax, 1
    jne failed
    jmp 9f
8:  test rax, rax
    jnz failed
9:  cmp r12, 3
    jne .Lcut_free
    # Readonly prevents Cut but permits Copy without changing the document.
    mov qword ptr [rip + accept], 1
    call cmd_copy
    cmp qword ptr [rip + calls], 1
    jne failed
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
.Lcut_free:
    mov rdi, [rsp]
    call mem_free
    mov rdi, [rsp + 8]
    call mem_free
    mov qword ptr [rbx + DOC_cap], 4096
    mov qword ptr [rbx + DOC_cur], 0
    mov qword ptr [rbx + DOC_anchor], 0
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r12
    cmp r12, 5
    jb .Lcut_case
    mov r13d, 120
    call prime
    lea rdi, [rip + field]
    lea rsi, [rip + field_source]
    mov edx, 6
    call tf_set
    mov qword ptr [rip + field + TF_cur], 5
    mov qword ptr [rip + field + TF_anchor], 1
    mov dword ptr [rip + field + TF_prefx], 9
    lea rdi, [rip + field]
    mov esi, TF_SIZE
    call mem_dup
    mov [rsp], rax
    mov qword ptr [rip + accept], 0
    mov qword ptr [rip + calls], 0
    lea rdi, [rip + field]
    mov esi, 'x'
    xor edx, edx
    mov ecx, MOD_CTRL
    call tf_key
    cmp eax, 1
    jne failed
    lea rdi, [rip + field]
    mov rsi, [rsp]
    mov edx, TF_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rip + field + TF_sb + SB_ptr]
    lea rsi, [rip + field_source]
    mov edx, 6
    call memeq
    test eax, eax
    jz failed
    cmp qword ptr [rip + calls], 1
    jne failed
    lea rdi, [rip + old_text]
    mov esi, 4
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    mov qword ptr [rip + accept], 1
    lea rdi, [rip + field]
    mov esi, 'x'
    xor edx, edx
    mov ecx, MOD_CTRL
    call tf_key
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + field + TF_sb + SB_len], 2
    jne failed
    cmp qword ptr [rip + field + TF_cur], 1
    jne failed
    cmp qword ptr [rip + field + TF_anchor], 1
    jne failed
    cmp dword ptr [rip + g_clip_line], 0
    jne failed
    mov rdi, [rip + field + TF_sb + SB_ptr]
    lea rsi, [rip + field_after]
    mov edx, 2
    call memeq
    test eax, eax
    jz failed
    cmp qword ptr [rip + capture + SB_len], 4
    jne failed
    mov rdi, [rip + capture + SB_ptr]
    lea rsi, [rip + field_copied]
    mov edx, 4
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp]
    call mem_free
    lea rdi, [rip + field + TF_sb]
    call sb_free
    cmp r15, [rip + g_mem_live]
    jne failed
    # Warm Vim's key and yank caches without accepting a destructive operation.
    call prime
    mov qword ptr [rip + accept], 0
    call vim_doc
    mov rbx, rax
    mov edi, 'x'
    mov esi, 'x'
    xor edx, edx
    call vim_key
    mov rdi, rbx
    call vim_forget
    mov rdi, rbx
    call doc_free
    mov r15, [rip + g_mem_live]
    xor r12d, r12d
.Lvim_case:
    lea r13, [r12 + 150]
    call prime
    mov qword ptr [rip + accept], 0
    call vim_doc
    mov rbx, rax
    cmp r12, 9
    jne .Lvim_writable
    or dword ptr [rbx + DOC_flags], DF_READONLY
.Lvim_writable:
    cmp r12, 10
    jb .Lvim_snapshot
    mov edi, 'v'
    cmp r12, 12
    jb .Lvim_enter
    mov edi, 'V'
.Lvim_enter:
    mov esi, edi
    xor edx, edx
    call vim_key
    cmp r12, 12
    jae .Lvim_snapshot
    mov edi, 'l'
    mov esi, 'l'
    xor edx, edx
    call vim_key
.Lvim_snapshot:
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp], rax
    mov rdi, [rbx + DOC_snippet]
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 8], rax
    mov qword ptr [rip + calls], 0
    lea rax, [rip + vim_commands]
    mov r14, [rax + r12*8]
.Lvim_key:
    movzx edi, byte ptr [r14]
    test edi, edi
    jz .Lvim_unchanged
    mov esi, edi
    xor edx, edx
    call vim_key
    cmp eax, 1
    jne failed
    inc r14
    jmp .Lvim_key
.Lvim_unchanged:
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 8]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov eax, VM_NORMAL
    cmp r12, 10
    jb .Lvim_mode_check
    mov eax, VM_VISUAL
    cmp r12, 12
    jb .Lvim_mode_check
    mov eax, VM_VLINE
.Lvim_mode_check:
    cmp [rip + g_vim_mode], eax
    jne failed
    xor eax, eax
    cmp r12, 9
    sete al
    xor eax, 1
    cmp [rip + calls], rax
    jne failed
    lea rdi, [rip + old_text]
    mov esi, 4
    call ed_clip_linewise
    cmp eax, 1
    jne failed
    mov rdi, [rsp]
    call mem_free
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, rbx
    call vim_forget
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r12
    cmp r12, 14
    jb .Lvim_case
.ifdef MACOS
    mov r13d, 180
    # Exercise the real Cocoa callback's translated return ABI without changing pasteboard.
    mov eax, 1
    lea rdi, [rip + bad_utf8]
    mov esi, 1
    call mac_clip_set
    test eax, eax
    jnz failed
.endif
.ifdef WINDOWS
    mov r13d, 130
    lea rdi, [rip + embedded_nul]
    mov esi, 3
    call win_clip_set
    test eax, eax
    jnz failed
    lea rdi, [rip + old_text]
    mov esi, 4
    call win_clip_set
    test eax, eax
    jnz failed
    cmp r15, [rip + g_mem_live]
    jne failed
.endif
    mov rax, [rsp + 48]
    mov [rip + g_plat + P_clip_set], rax
    lea rdi, [rip + capture]
    call sb_free
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
failed:
    lea rdi, [rip + fail]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE

vim_doc:
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + source]
    mov ecx, 11
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 11
    lea rdx, [rip + extra]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + source]
    mov esi, 11
    call snippet_new
    mov r12, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 11
    xor r8d, r8d
    call snippet_add
    mov rdi, r12
    call snippet_validate
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call snippet_attach
    mov qword ptr [rbx + DOC_cur], 2
    mov qword ptr [rbx + DOC_anchor], 2
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_NORMAL
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov edi, KEY_ESCAPE
    xor esi, esi
    xor edx, edx
    call vim_key
    mov qword ptr [rbx + DOC_lastkind], EK_TYPE
    mov rax, rbx
    EPILOGUE
.section .rodata
ok: .asciz "ok clipboard writes\n"
fail: .asciz "failed clipboard writes case "
old_text: .ascii "old\n"
unicode_text: .ascii "Ω😀\n"
bad_utf8: .byte 0xc0
truncated: .byte 0xf0,0x90,0x80
embedded_nul: .byte 65,0,66
source: .ascii "alpha\nbeta\n"
selected: .quad 5,2
collapsed: .quad 1,1
multiple: .quad 2,0,10,6
extra: .byte 88
field_source: .ascii "rename"
field_copied: .ascii "enam"
field_after: .ascii "re"
vim_commands: .quad vx,vdw,vcw,vdd,vcc,vD,vC,vS,vX,vdd,vd,vc,vd,vc
vd: .asciz "d"
vc: .asciz "c"
vx: .asciz "x"
vdw: .asciz "dw"
vcw: .asciz "cw"
vdd: .asciz "dd"
vcc: .asciz "cc"
vD: .asciz "D"
vC: .asciz "C"
vS: .asciz "S"
vX: .asciz "X"
# source,len,linewise,platform acceptance,expected bool,expected calls,alias old cache
vectors:
    .quad unicode_text,7,1,1,1,1,0
    .quad 0,0,1,1,1,1,0
    .quad embedded_nul,3,0,1,1,1,0
    .quad bad_utf8,1,0,1,0,0,0
    .quad truncated,3,0,1,0,0,0
    .quad 0,1,0,1,0,0,0
    .quad old_text,DOC_MULTI_BYTES_MAX+1,0,1,0,0,0
    .quad old_text,4,2,1,0,0,0
    .quad old_text,4,-1,1,0,0,0
    .quad old_text,-1,0,1,0,0,0
    .quad old_text,4,0,0,0,1,0
    .quad 0,4,1,1,1,1,1
    .quad 0,4,0,0,0,1,1
    .quad 0,-2,0,0,0,0,0
