# Incremental column measurement must agree with measuring from the row start,
# including tabs following wide characters and rows starting partway through a line.
.include "rhun.inc"
.text
FN main
    PROLOGUE 16
    mov dword ptr [rsp], 1
.Lwidth:
    mov eax, [rsp]
    mov [rip + cfg_tab_width], eax
    xor r12d, r12d              # row start
.Lrow:
    mov r13, r12                # previous end
    mov r14, r12                # next end
    xor r15d, r15d              # running column
.Lend:
    lea rdi, [rip + text]
    mov rsi, r13
    mov rdx, r14
    mov ecx, r15d
    call seg_cols_from
    mov r15d, eax
    lea rdi, [rip + text]
    mov rsi, r12
    mov rdx, r14
    call seg_cols
    cmp eax, r15d
    jne .Lfail
    cmp r14, text_end - text
    jae .Lnextrow
    mov r13, r14
    lea rdi, [rip + text]
    add rdi, r14
    mov esi, text_end - text
    sub rsi, r14
    call utf8_decode
    add r14, rdx
    jmp .Lend
.Lnextrow:
    cmp r12, text_end - text
    jae .Lnextwidth
    lea rdi, [rip + text]
    add rdi, r12
    mov esi, text_end - text
    sub rsi, r12
    call utf8_decode
    add r12, rdx
    jmp .Lrow
.Lnextwidth:
    inc dword ptr [rsp]
    cmp dword ptr [rsp], 8
    jbe .Lwidth
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
text: .ascii "a\tbc\t\344\270\255\t\303\251x\t\360\237\230\200\tend"
text_end:
ok: .asciz "ok\n"
