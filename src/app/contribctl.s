# headless control commands of the contributions and commands work (control.s's ctl_tables):
#   cmd-args NAME ARGS...     run a command as a command reference would (FROM ref, ARGS as body)
#   cmd-ref EXT NAME [ARGS]   parse "command NAME LEN" + ARGS for extension EXT and invoke it
#   when CLAUSE               "when=1", "when=0" or "when error at N: TEXT"
#   print-context [KEY]       the built-in context keys ("KEY=VALUE" lines), or one key
#   ctx-set KEY VALUE         a published built-in key's value ("-" clears it), as another part would
.include "rhun.inc"

.bss
.p2align 3
cc_buf: .zero SB_SIZE

.text

# each fn(out sb, rest, rest len) -> rax 0
.section .rodata
.p2align 3
.globl contrib_ctl
contrib_ctl:
    .quad .Lc_cmd_args, c_cmd_args, .Lc_cmd_ref, c_cmd_ref
    .quad .Lc_when, c_when, .Lc_print_context, c_print_context, .Lc_ctx_set, c_ctx_set
    .quad 0, 0
.Lc_cmd_args: .asciz "cmd-args"
.Lc_cmd_ref: .asciz "cmd-ref"
.Lc_when: .asciz "when"
.Lc_print_context: .asciz "print-context"
.Lc_ctx_set: .asciz "ctx-set"
.Lcommand_sp: .asciz "command "
.Lbad_ref: .asciz "cmdref=bad\n"
.Lno_ext: .asciz "no such extension\n"
.Lno_cmd: .asciz "no such command\n"
.text

# next_word in (r13 rest, r14 len) -> rax ptr, rdx len, moving past it
cc_word:
    mov rdi, r13
    mov rsi, r14
    call next_word
    add r13, rcx
    sub r14, rcx
    ret

# cmd-args NAME ARGS...: cmd_invoke(NAME, INV_REF, ARGS)
c_cmd_args:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call cc_word
    mov rdi, rax
    mov rsi, rdx
    call cmd_find
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, r13
    mov rsi, r14
    call trim
    mov rcx, rdx
    mov rdx, rax
    mov rdi, rbx
    mov esi, INV_REF
    xor r8d, r8d
    call cmd_invoke
    xor eax, eax
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Lno_cmd]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# cmd-ref EXT NAME [ARGS]: the record "command NAME LEN" LF ARGS through cmdref_parse
c_cmd_ref:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call cc_word
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 7f
    mov [rsp], rax
    call cc_word
    mov r15, rax                # NAME
    mov rbx, rdx
    mov rdi, r13
    mov rsi, r14
    call trim
    mov r13, rax                # ARGS
    mov r14, rdx
    lea rdi, [rip + cc_buf]
    call sb_clear
    lea rdi, [rip + cc_buf]
    lea rsi, [rip + .Lcommand_sp]
    call sb_push_cstr
    lea rdi, [rip + cc_buf]
    mov rsi, r15
    mov rdx, rbx
    call sb_push
    lea rdi, [rip + cc_buf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cc_buf]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + cc_buf]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cc_buf]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    mov rdi, [rsp]
    mov rsi, [rip + cc_buf + SB_ptr]
    mov rdx, [rip + cc_buf + SB_len]
    call cmdref_parse
    test rax, rax
    jz 8f
    cmp rdx, [rip + cc_buf + SB_len]
    jne 8f
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    call cmdref_invoke
    mov rdi, rbx
    call cmdref_free
    xor eax, eax
    EPILOGUE
7:  mov rdi, r12
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Lbad_ref]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# when CLAUSE: compiled with no extension of its own, evaluated now
c_when:
    jmp when_ctl

# print-context [KEY]
c_print_context:
    jmp ctx_dump

# ctx-set KEY VALUE
c_ctx_set:
    jmp ctx_ctl_set
