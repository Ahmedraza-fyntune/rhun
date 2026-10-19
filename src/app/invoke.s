# command invocations with arguments (feature command-args, docs/extensions/v1.1.md): where a
# command was invoked from and with what body, and the command references other features carry
# (code lens, tree items, status items, notification buttons, menu items: "command NAME ARGS_LEN"
# and ARGS inside any body).
#
# For other parts of rhun:
#   cmd_invoke(cmd, from, body, len, doc)   run any command as invoked from INV_* with a body
#   cmdref_parse(ext, ptr, len)             a "command NAME ARGS_LEN" record -> owned CRF
#   cmdref_new(ext, name, nlen, args, alen) the same from its parts
#   cmdref_invoke(crf, doc)                 run it (INV_REF); toasts when the command is gone
#   cmdref_free(crf)
.include "rhun.inc"

.bss
.p2align 3
.globl g_invoke
g_invoke: .zero INV_SIZE        # the invocation being run: cmd_invoke sets it, ext_cmd_run takes it

.text

# FN cmd_invoke(cmd*, from, body, len, doc id): run the command as invoked from INV_* with that
# body (ARGS of a key binding, TARGET and args of a menu item, a reference's ARGS) about that
# document (0: the active one). Built-in commands ignore what they do not use.
FN cmd_invoke
    PROLOGUE
    mov rbx, rdi
    mov [rip + g_invoke + INV_from], esi
    mov [rip + g_invoke + INV_body], rdx
    mov [rip + g_invoke + INV_len], rcx
    mov [rip + g_invoke + INV_doc], r8
    mov rdi, rbx
    call [rbx + CMD_fn]
    call invoke_clear
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN invoke_take(dst INV*): the invocation being run, copied to dst, and cleared (the body
# stays the caller's: it is valid until the command returns)
FN invoke_take
    lea rsi, [rip + g_invoke]
    mov rax, [rsi]
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    mov [rdi + 24], rax
    jmp invoke_clear
FN invoke_clear
    xor eax, eax
    mov [rip + g_invoke], rax
    mov [rip + g_invoke + 8], rax
    mov [rip + g_invoke + 16], rax
    mov [rip + g_invoke + 24], rax
    ret

# FN cmd_name_ok(ptr, len) -> eax 1 for a local command name: 1 to 40 of [a-z0-9_]
FN cmd_name_ok
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, CMD_NAME_MAX
    ja 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    inc rcx
    cmp dl, '_'
    je 2f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 2f
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    ja 9f
2:  cmp rcx, rsi
    jb 1b
    mov eax, 1
9:  ret

# FN cmdref_new(ext, name, nlen, args, alen) -> rax an owned command reference (CRF), or 0 when
# the name is not a command name or ARGS are over CRF_ARGS_MAX
FN cmdref_new
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, r12
    mov rsi, r13
    call cmd_name_ok
    test eax, eax
    jz 8f
    cmp r15, CRF_ARGS_MAX
    ja 8f
    lea rdi, [r15 + CRF_SIZE + 1]
    call mem_alloc
    mov [rsp], rax
    mov [rax + CRF_ext], rbx
    mov [rax + CRF_len], r15
    lea rdi, [rax + CRF_name]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, [rsp]
    mov byte ptr [rax + CRF_name + r13], 0
    lea rdi, [rax + CRF_SIZE]
    mov rsi, r14
    mov rdx, r15
    call memcpy
    mov rax, [rsp]
    mov byte ptr [rax + CRF_SIZE + r15], 0     # ARGS are also a cstr for printing
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN cmdref_parse(ext, ptr, len) -> rax an owned CRF, rdx the record's bytes (its line, LF and
# ARGS), or rax 0 when the bytes at ptr are not a whole record "command NAME ARGS_LEN" LF ARGS
FN cmdref_parse
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]        # end
    # the line
    mov rax, r12
1:  cmp rax, r13
    jae 8f
    cmp byte ptr [rax], 10
    je 2f
    inc rax
    jmp 1b
2:  mov r14, rax                # its LF
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    lea rdx, [rip + .Lcommand_sp]
    mov ecx, 8
    call str_starts
    test eax, eax
    jz 8f
    lea r15, [r12 + 8]          # NAME
    mov rax, r15
3:  cmp rax, r14
    jae 8f
    cmp byte ptr [rax], ' '
    je 4f
    inc rax
    jmp 3b
4:  mov [rsp], rax              # NAME's end
    lea rdi, [rax + 1]
    mov rsi, r14
    sub rsi, rdi
    jz 8f
    cmp rsi, 4
    ja 8f                       # at most 8192: four digits
    mov [rsp + 8], rsi
    call parse_u64
    cmp rdx, [rsp + 8]
    jne 8f
    cmp rax, CRF_ARGS_MAX
    ja 8f
    lea rcx, [r14 + 1]
    mov rdx, r13
    sub rdx, rcx
    cmp rax, rdx
    ja 8f                       # ARGS cut short
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rsp]
    sub rdx, r15
    lea rcx, [r14 + 1]
    mov r8, rax
    call cmdref_new
    test rax, rax
    jz 8f
    lea rdx, [r14 + 1]
    add rdx, [rsp + 16]
    sub rdx, r12
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# FN cmdref_free(crf): mem_free (0 is fine)
FN cmdref_free
    test rdi, rdi
    jz 1f
    jmp mem_free
1:  ret

# FN cmdref_invoke(crf, doc id) -> eax 1 when it ran: the reference's extension command with
# FROM ref, ARGS as the body, about that document (0: the active one). A command that no longer
# exists shows a toast and sends nothing (eax 0).
FN cmdref_invoke
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz 8f
    mov rdi, [rbx + CRF_ext]
    test rdi, rdi
    jz 8f
    call ext_is_visible
    test eax, eax
    jz 8f
    lea rdi, [rbx + CRF_name]
    call strlen
    mov rdx, rax
    mov rdi, [rbx + CRF_ext]
    lea rsi, [rbx + CRF_name]
    call ext_cmd_local
    test rax, rax
    jz 8f
    mov rdi, rax
    mov esi, INV_REF
    lea rdx, [rbx + CRF_SIZE]
    mov rcx, [rbx + CRF_len]
    mov r8, r12
    call cmd_invoke
    mov eax, 1
    EPILOGUE
8:  lea rdi, [rip + .Lgone]
    call app_toast
    xor eax, eax
    EPILOGUE

# FN invoke_from_name(from) -> rax "palette", "key", "menu" or "ref"
FN invoke_from_name
    and edi, 3
    lea rax, [rip + from_names]
    mov rax, [rax + rdi*8]
    ret

.section .rodata
.p2align 3
from_names: .quad .Lf_palette, .Lf_key, .Lf_menu, .Lf_ref
.Lf_palette: .asciz "palette"
.Lf_key: .asciz "key"
.Lf_menu: .asciz "menu"
.Lf_ref: .asciz "ref"
.Lcommand_sp: .asciz "command "
.Lgone: .asciz "This command is no longer available"
