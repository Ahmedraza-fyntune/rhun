.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE
    lea r12, [rip + cases]
    xor r13d, r13d
.Lcase:
    mov r14, [r12]
    cmp r14, -1
    je .Lok
    mov edi, [r12 + 8]
    cmp r14, 0
    jne 1f
    call snippet_unicode_fold
    jmp .Lscalar
1:  cmp r14, 1
    jne 2f
    call snippet_unicode_upper
    jmp .Lmapped
2:  cmp r14, 2
    jne 3f
    call snippet_unicode_lower
    jmp .Lmapped
3:  cmp r14, 3
    jne 4f
    call snippet_unicode_cased
    jmp .Lscalar
4:  cmp r14, 4
    jne 5f
    call snippet_unicode_case_ignorable
    jmp .Lscalar
5:  cmp r14, 5
    jne 6f
    call snippet_unicode_letter
    jmp .Lscalar
6:  cmp r14, 6
    jne 7f
    call snippet_unicode_upper_letter
    jmp .Lscalar
7:  call snippet_unicode_lower_letter
.Lscalar:
    cmp rax, [r12 + 16]
    jne .Lfail
    jmp .Lnext
.Lmapped:
    cmp rdx, [r12 + 24]
    jne .Lfail
    test rdx, rdx
    jnz 1f
    test rax, rax
    jnz .Lfail
    jmp .Lnext
1:  test rax, rax
    jz .Lfail
    mov rdi, rax
    mov rsi, [r12 + 16]
    call memeq
    test eax, eax
    jz .Lfail
.Lnext:
    inc r13
    add r12, 32
    jmp .Lcase
.Lok:
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    lea rdi, [rip + failed]
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
.section .rodata
ok: .asciz "ok snippet Unicode\n"
failed: .asciz "failed snippet Unicode case "
uppera: .ascii "A"
lowera: .ascii "a"
upper_ss: .ascii "SS"
sharp: .ascii "ß"
idot: .ascii "i\xcc\x87"
ffi: .ascii "FFI"
sigma: .ascii "σ"
tje: .ascii "ᲊ"
garay: .byte 0xf0,0x90,0xb5,0xb0
.p2align 3
cases:
.quad 0,65,97,0
.quad 0,97,97,0
.quad 0,0x212a,107,0
.quad 0,0x17f,115,0
.quad 0,0x3a3,0x3c3,0
.quad 0,0x3c2,0x3c3,0
.quad 0,0x130,0x130,0
.quad 0,0x131,0x131,0
.quad 0,0x1e9e,0xdf,0
.quad 0,0x1c89,0x1c8a,0
.quad 0,0x10d50,0x10d70,0
.quad 0,0x10400,0x10428,0
.quad 0,0xd800,0xd800,0
.quad 0,0x10ffff,0x10ffff,0
.quad 0,0x110000,0x110000,0
.quad 0,0xffffffff,0xffffffff,0
.quad 1,97,uppera,1
.quad 2,65,lowera,1
.quad 1,0xdf,upper_ss,2
.quad 2,0x1e9e,sharp,2
.quad 2,0x130,idot,3
.quad 1,0xfb03,ffi,3
.quad 2,0x3a3,sigma,2
.quad 2,0x1c89,tje,3
.quad 2,0x10d50,garay,4
.quad 1,65,0,0
.quad 2,97,0,0
.quad 1,0xd800,0,0
.quad 2,0x110000,0,0
.quad 2,0xffffffff,0,0
.quad 3,65,1,0
.quad 3,64,0,0
.quad 3,91,0,0
.quad 3,0x1c89,1,0
.quad 3,0x10d70,1,0
.quad 3,0xd800,0,0
.quad 3,0x10ffff,0,0
.quad 3,0xffffffff,0,0
.quad 4,0x301,1,0
.quad 4,65,0,0
.quad 4,32,0,0
.quad 4,0xd800,0,0
.quad 4,0x10ffff,0,0
.quad 4,0xffffffff,0,0
.quad 5,65,1,0
.quad 5,97,1,0
.quad 5,453,1,0
.quad 5,19968,1,0
.quad 5,66600,1,0
.quad 5,68944,1,0
.quad 5,48,0,0
.quad 5,837,0,0
.quad 5,55296,0,0
.quad 5,1114112,0,0
.quad 5,4294967295,0,0
.quad 6,65,1,0
.quad 6,66560,1,0
.quad 6,68944,1,0
.quad 6,97,0,0
.quad 6,453,0,0
.quad 6,19968,0,0
.quad 6,837,0,0
.quad 6,55296,0,0
.quad 6,1114112,0,0
.quad 6,4294967295,0,0
.quad 7,97,1,0
.quad 7,66600,1,0
.quad 7,68976,1,0
.quad 7,65,0,0
.quad 7,453,0,0
.quad 7,19968,0,0
.quad 7,837,0,0
.quad 7,55296,0,0
.quad 7,1114112,0,0
.quad 7,4294967295,0,0
.quad -1,0,0,0
