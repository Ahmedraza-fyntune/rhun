# rhun --wasm-spec SCRIPT: runs the WebAssembly specification's tests (tests/wasm-spec.py turns
# their .wast files, through wabt's wast2json, into SCRIPT). One command per line, one answer line
# each on standard output:
#   module NAME PATH            -> ok | error MESSAGE | trap MESSAGE     (NAME - for none)
#   register AS NAME            -> ok | error MESSAGE      (AS as FIELD; NAME - for the last module)
#   invoke NAME FIELD ARG...    -> ok VALUE... | trap MESSAGE | error MESSAGE
#   get NAME FIELD              -> ok VALUE | error MESSAGE
# FIELD is x and the name's bytes in hex. Values are TYPE:HEX (i32 i64 f32 f64: the bits), or
# funcref:null, externref:null, externref:HEX; a function reference prints as funcref:fn.
.include "rhun.inc"
.include "wasm/wasm.inc"

STRUCT
F SPN_name, 8
F SPN_len, 8
F SPN_inst, 8
ENDSTRUCT SPN_SIZE

.bss
.p2align 3
spec_mods: .zero VEC_SIZE           # modules by their script name
spec_regs: .zero VEC_SIZE           # instances registered for imports
spec_cur: .quad 0                   # the last module
spec_out: .zero SB_SIZE
spec_field: .zero 4096
spec_field_len: .quad 0
spec_args: .zero 8 * 1024
spec_results: .zero 8 * 1024

.text
# wasm_spec_main(argc, argv): never returns
FN wasm_spec_main
    PROLOGUE 32
    cmp rdi, 3
    jb .Lusage
    mov rax, [rsi + 16]
    mov [rsp], rax
    lea rax, [rip + spec_resolve]
    mov [rip + g_wasm_resolve], rax
    # the spectest module every script imports from
    lea rdi, [rip + spectest_wasm]
    mov esi, spectest_wasm_end - spectest_wasm
    call wasm_load
    test rax, rax
    jz .Lspectest_failed
    mov r14, rax
    lea rdi, [rip + spec_regs]
    mov esi, SPN_SIZE
    call vec_push
    lea rcx, [rip + .Ls_spectest]
    mov [rax + SPN_name], rcx
    mov qword ptr [rax + SPN_len], 8
    mov [rax + SPN_inst], r14
    mov rdi, [rsp]
    call file_read_all
    test rax, rax
    jz .Lusage
    mov r12, rax
    add rax, rdx
    mov [rip + spec_end], rax
.Lline:
    cmp r12, [rip + spec_end]
    jae .Ldone
    mov r13, r12
1:  cmp r13, [rip + spec_end]
    jae 2f
    cmp byte ptr [r13], 10
    je 2f
    inc r13
    jmp 1b
2:  mov [rsp + 8], r13
    call field
    call field_again
    lea rdx, [rip + .Ls_module]
    call str_eq_cstr
    test eax, eax
    jnz .Lmodule
    call field_again
    lea rdx, [rip + .Ls_register]
    call str_eq_cstr
    test eax, eax
    jnz .Lregister
    call field_again
    lea rdx, [rip + .Ls_invoke]
    call str_eq_cstr
    test eax, eax
    jnz .Linvoke
    call field_again
    lea rdx, [rip + .Ls_get]
    call str_eq_cstr
    test eax, eax
    jnz .Lget
    lea rdi, [rip + .Ls_unknown]
    call out_error
.Lnext:
    mov r12, [rsp + 8]
    inc r12
    jmp .Lline
.Ldone:
    xor edi, edi
    call sys_exit
.Lusage:
    lea rdi, [rip + .Ls_usage]
    call die
.Lspectest_failed:
    mov rdi, [rip + g_wasm_err]
    call die

.Lmodule:
    call field
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    call field
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call wasm_load
    test rax, rax
    jz 7f
    mov r14, rax
    mov [rip + spec_cur], rax
    mov rax, [rsp + 24]
    cmp rax, 1
    jne 3f
    mov rax, [rsp + 16]
    cmp byte ptr [rax], '-'
    je 4f
3:  lea rdi, [rip + spec_mods]
    mov esi, SPN_SIZE
    call vec_push
    mov rcx, [rsp + 16]
    mov [rax + SPN_name], rcx
    mov rcx, [rsp + 24]
    mov [rax + SPN_len], rcx
    mov [rax + SPN_inst], r14
4:  call out_ok
    call out_flush
    jmp .Lnext
7:  lea rdi, [rip + .Ls_error]
    cmp dword ptr [rip + g_wasm_trapped], 0
    je 71f
    lea rdi, [rip + .Ls_trap]
71: call out_cstr
    mov rdi, [rip + g_wasm_err]
    call out_cstr
    call out_flush
    jmp .Lnext
8:  lea rdi, [rip + .Ls_nofile]
    call out_error
    jmp .Lnext

.Lregister:
    call field_name
    lea rdi, [rip + spec_field]
    mov rsi, [rip + spec_field_len]
    mov [rsp + 24], rsi
    call mem_dup
    mov [rsp + 16], rax
    call field
    mov rdi, rax
    mov rsi, rdx
    call instance
    test rax, rax
    jz 9f
    mov r14, rax
    lea rdi, [rip + spec_regs]
    mov esi, SPN_SIZE
    call vec_push
    mov rcx, [rsp + 16]
    mov [rax + SPN_name], rcx
    mov rcx, [rsp + 24]
    mov [rax + SPN_len], rcx
    mov [rax + SPN_inst], r14
    call out_ok
    call out_flush
    jmp .Lnext
9:  lea rdi, [rip + .Ls_nomodule]
    call out_error
    jmp .Lnext

.Linvoke:
    call field
    mov rdi, rax
    mov rsi, rdx
    call instance
    test rax, rax
    jz 9b
    mov r14, rax
    call field_name
    mov rdi, r14
    lea rsi, [rip + spec_field]
    mov rdx, [rip + spec_field_len]
    mov ecx, WK_FUNC
    call wasm_export_object
    test rax, rax
    jz .Lno_export
    mov r14, rax
    # the arguments
    xor ebx, ebx
1:  cmp r12, r13
    jae 2f
    call field
    test rdx, rdx
    jz 2f
    mov rdi, rax
    mov rsi, rdx
    call parse_value
    lea rcx, [rip + spec_args]
    mov [rcx + rbx*8], rax
    inc ebx
    cmp ebx, 1000
    jb 1b
2:  cmp ebx, [r14 + WFN_nparams]
    jne .Lbad_args
    mov rdi, r14
    lea rsi, [rip + spec_args]
    lea rdx, [rip + spec_results]
    call wasm_invoke
    test eax, eax
    jnz .Ltrapped
    call out_ok
    mov edi, [r14 + WFN_type]
    call wasm_type
    mov r15, rax
    xor ebx, ebx
3:  cmp ebx, [r15 + WTY_nresults]
    jae 4f
    mov rax, [r15 + WTY_types]
    mov ecx, [r15 + WTY_nparams]
    add rax, rcx
    movzx edi, byte ptr [rax + rbx]
    lea rcx, [rip + spec_results]
    mov rsi, [rcx + rbx*8]
    call out_value
    inc ebx
    jmp 3b
4:  call out_flush
    jmp .Lnext
.Ltrapped:
    mov edi, eax
    call wasm_trap_text
    push rax
    push rax
    lea rdi, [rip + .Ls_trap]
    call out_cstr
    pop rdi
    pop rdi
    call out_cstr
    call out_flush
    jmp .Lnext
.Lno_export:
    lea rdi, [rip + .Ls_noexport]
    call out_error
    jmp .Lnext
.Lbad_args:
    lea rdi, [rip + .Ls_args]
    call out_error
    jmp .Lnext

.Lget:
    call field
    mov rdi, rax
    mov rsi, rdx
    call instance
    test rax, rax
    jz 9b
    mov r14, rax
    call field_name
    mov rdi, r14
    lea rsi, [rip + spec_field]
    mov rdx, [rip + spec_field_len]
    mov ecx, WK_GLOBAL
    call wasm_export_object
    test rax, rax
    jz .Lno_export
    mov r14, rax
    call out_ok
    movzx edi, byte ptr [r14 + WGL_type]
    mov rsi, [r14 + WGL_value]
    call out_value
    call out_flush
    jmp .Lnext

# field -> rax, rdx: the next space-separated word of the line (r12 .. r13), r12 past it
field:
1:  cmp r12, r13
    jae 3f
    cmp byte ptr [r12], ' '
    jne 2f
    inc r12
    jmp 1b
2:
3:  mov rax, r12
4:  cmp r12, r13
    jae 5f
    cmp byte ptr [r12], ' '
    je 5f
    inc r12
    jmp 4b
5:  mov rdx, r12
    sub rdx, rax
    mov [rip + last_field], rax
    mov [rip + last_field + 8], rdx
    ret
# field_again -> rdi, rsi: the word field last returned
field_again:
    mov rdi, [rip + last_field]
    mov rsi, [rip + last_field + 8]
    ret

# field_name(): the next word, x and hex digits, decoded into spec_field
field_name:
    push rbx
    call field
    lea rbx, [rip + spec_field]
    xor ecx, ecx
    inc rax
    dec rdx
1:  cmp rdx, 2
    jb 2f
    push rcx
    push rax
    push rdx
    mov rdi, rax
    mov esi, 2
    call parse_hex
    mov r8, rax
    pop rdx
    pop rax
    pop rcx
    mov [rbx + rcx], r8b
    inc rcx
    add rax, 2
    sub rdx, 2
    cmp rcx, 4000
    jb 1b
2:  mov [rip + spec_field_len], rcx
    pop rbx
    ret

# instance(name ptr, len) -> rax the module named so, the last one for -, or 0
instance:
    push rbx
    push r14
    push r15
    cmp rsi, 1
    jne 1f
    cmp byte ptr [rdi], '-'
    jne 1f
    mov rax, [rip + spec_cur]
    jmp 9f
1:  mov r14, rdi
    mov r15, rsi
    lea rdi, [rip + spec_mods]
    call names_find
9:  pop r15
    pop r14
    pop rbx
    ret

# names_find(vec rdi; name r14, len r15) -> rax the instance, or 0 (the latest entry wins)
names_find:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [r12 + VEC_len]
1:  test rbx, rbx
    jz 8f
    dec rbx
    imul rax, rbx, SPN_SIZE
    add rax, [r12 + VEC_ptr]
    cmp [rax + SPN_len], r15
    jne 1b
    push rax
    push rax
    mov rdi, [rax + SPN_name]
    mov rsi, r14
    mov rdx, r15
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jz 1b
    mov rax, [rcx + SPN_inst]
    pop r12
    pop rbx
    ret
8:  xor eax, eax
    pop r12
    pop rbx
    ret

# spec_resolve(module ptr, len, field ptr, len, kind r8, type r9) -> the export, or 0
spec_resolve:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdx
    mov r13, rcx
    mov rbx, r8
    mov r14, rdi
    mov r15, rsi
    lea rdi, [rip + spec_regs]
    call names_find
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    mov rcx, rbx
    call wasm_export_object
9:  pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# parse_value(ptr, len) -> rax: TYPE:HEX or TYPE:null (an extern value N is stored as N + 1)
parse_value:
    push rbx
    mov rbx, rdi
    add rsi, rdi
1:  cmp rdi, rsi
    jae 8f
    cmp byte ptr [rdi], ':'
    je 2f
    inc rdi
    jmp 1b
2:  inc rdi
    cmp byte ptr [rdi], 'n'
    je 8f
    push rsi
    sub rsi, rdi
    call parse_hex
    pop rsi
    cmp byte ptr [rbx], 'e'
    jne 9f
    inc rax
    jmp 9f
8:  xor eax, eax
9:  pop rbx
    ret

# out_value(type, value)
out_value:
    push rbx
    push r12
    mov ebx, edi
    mov r12, rsi
    mov edi, ' '
    call out_byte
    cmp ebx, WV_I32
    jne 1f
    lea rdi, [rip + .Ls_i32]
    jmp 5f
1:  cmp ebx, WV_I64
    jne 2f
    lea rdi, [rip + .Ls_i64]
    jmp 5f
2:  cmp ebx, WV_F32
    jne 3f
    lea rdi, [rip + .Ls_f32]
    jmp 5f
3:  cmp ebx, WV_F64
    jne 4f
    lea rdi, [rip + .Ls_f64]
    jmp 5f
4:  cmp ebx, WV_FUNCREF
    jne 6f
    lea rdi, [rip + .Ls_funcnull]
    test r12, r12
    jz 7f
    lea rdi, [rip + .Ls_funcfn]
    jmp 7f
6:  lea rdi, [rip + .Ls_externnull]
    test r12, r12
    jz 7f
    lea rdi, [rip + .Ls_extern]
    call out_cstr
    lea rsi, [r12 - 1]
    jmp 51f
5:  call out_cstr
    mov rsi, r12
51: sub rsp, 32
    mov rdi, rsp
    call fmt_hex
    mov rdi, rsp
    mov rsi, rax
    call out_bytes
    add rsp, 32
    pop r12
    pop rbx
    ret
7:  call out_cstr
    pop r12
    pop rbx
    ret

out_ok:
    lea rdi, [rip + .Ls_ok]
    jmp out_cstr
# out_error(message): an error line
out_error:
    push rdi
    lea rdi, [rip + .Ls_error]
    call out_cstr
    pop rdi
    call out_cstr
    jmp out_flush
out_cstr:
    mov rsi, rdi
    lea rdi, [rip + spec_out]
    jmp sb_push_cstr
out_bytes:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + spec_out]
    jmp sb_push
out_byte:
    mov esi, edi
    lea rdi, [rip + spec_out]
    jmp sb_push_byte
# out_flush(): ends the line and writes it
out_flush:
    mov edi, 10
    call out_byte
    mov edi, 1
    mov rsi, [rip + spec_out + SB_ptr]
    mov rdx, [rip + spec_out + SB_len]
    call write_all
    lea rdi, [rip + spec_out]
    jmp sb_clear

.bss
.p2align 3
last_field: .quad 0, 0
spec_end: .quad 0

.section .rodata
.Ls_usage: .asciz "usage: rhun --wasm-spec SCRIPT"
.Ls_spectest: .ascii "spectest"
.Ls_module: .asciz "module"
.Ls_register: .asciz "register"
.Ls_invoke: .asciz "invoke"
.Ls_get: .asciz "get"
.Ls_unknown: .asciz "unknown command"
.Ls_nofile: .asciz "cannot read the module"
.Ls_nomodule: .asciz "unknown module"
.Ls_noexport: .asciz "unknown export"
.Ls_args: .asciz "wrong number of arguments"
.Ls_ok: .asciz "ok"
.Ls_error: .asciz "error "
.Ls_trap: .asciz "trap "
.Ls_i32: .asciz "i32:"
.Ls_i64: .asciz "i64:"
.Ls_f32: .asciz "f32:"
.Ls_f64: .asciz "f64:"
.Ls_funcnull: .asciz "funcref:null"
.Ls_funcfn: .asciz "funcref:fn"
.Ls_externnull: .asciz "externref:null"
.Ls_extern: .asciz "externref:"
# the spectest module (spectest.wat in tests/wasm): print functions, globals, a table, a memory
.p2align 3
spectest_wasm:
    .byte 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x1e, 0x07, 0x60, 0x00, 0x00, 0x60, 0x01
    .byte 0x7f, 0x00, 0x60, 0x01, 0x7e, 0x00, 0x60, 0x01, 0x7d, 0x00, 0x60, 0x01, 0x7c, 0x00, 0x60, 0x02
    .byte 0x7f, 0x7d, 0x00, 0x60, 0x02, 0x7c, 0x7c, 0x00, 0x03, 0x08, 0x07, 0x00, 0x01, 0x02, 0x03, 0x04
    .byte 0x05, 0x06, 0x04, 0x05, 0x01, 0x70, 0x01, 0x0a, 0x14, 0x05, 0x04, 0x01, 0x01, 0x01, 0x02, 0x06
    .byte 0x21, 0x04, 0x7f, 0x00, 0x41, 0x9a, 0x05, 0x0b, 0x7e, 0x00, 0x42, 0x9a, 0x05, 0x0b, 0x7d, 0x00
    .byte 0x43, 0x66, 0xa6, 0x26, 0x44, 0x0b, 0x7c, 0x00, 0x44, 0xcd, 0xcc, 0xcc, 0xcc, 0xcc, 0xd4, 0x84
    .byte 0x40, 0x0b, 0x07, 0x9e, 0x01, 0x0d, 0x0a, 0x67, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x5f, 0x69, 0x33
    .byte 0x32, 0x03, 0x00, 0x0a, 0x67, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x5f, 0x69, 0x36, 0x34, 0x03, 0x01
    .byte 0x0a, 0x67, 0x6c, 0x6f, 0x62, 0x61, 0x6c, 0x5f, 0x66, 0x33, 0x32, 0x03, 0x02, 0x0a, 0x67, 0x6c
    .byte 0x6f, 0x62, 0x61, 0x6c, 0x5f, 0x66, 0x36, 0x34, 0x03, 0x03, 0x05, 0x74, 0x61, 0x62, 0x6c, 0x65
    .byte 0x01, 0x00, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00, 0x05, 0x70, 0x72, 0x69, 0x6e
    .byte 0x74, 0x00, 0x00, 0x09, 0x70, 0x72, 0x69, 0x6e, 0x74, 0x5f, 0x69, 0x33, 0x32, 0x00, 0x01, 0x09
    .byte 0x70, 0x72, 0x69, 0x6e, 0x74, 0x5f, 0x69, 0x36, 0x34, 0x00, 0x02, 0x09, 0x70, 0x72, 0x69, 0x6e
    .byte 0x74, 0x5f, 0x66, 0x33, 0x32, 0x00, 0x03, 0x09, 0x70, 0x72, 0x69, 0x6e, 0x74, 0x5f, 0x66, 0x36
    .byte 0x34, 0x00, 0x04, 0x0d, 0x70, 0x72, 0x69, 0x6e, 0x74, 0x5f, 0x69, 0x33, 0x32, 0x5f, 0x66, 0x33
    .byte 0x32, 0x00, 0x05, 0x0d, 0x70, 0x72, 0x69, 0x6e, 0x74, 0x5f, 0x66, 0x36, 0x34, 0x5f, 0x66, 0x36
    .byte 0x34, 0x00, 0x06, 0x0a, 0x16, 0x07, 0x02, 0x00, 0x0b, 0x02, 0x00, 0x0b, 0x02, 0x00, 0x0b, 0x02
    .byte 0x00, 0x0b, 0x02, 0x00, 0x0b, 0x02, 0x00, 0x0b, 0x02, 0x00, 0x0b
spectest_wasm_end:
