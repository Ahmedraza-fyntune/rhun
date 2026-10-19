# headless control commands of the contributions and commands work (control.s's ctl_tables):
#   cmd-args NAME ARGS...     run a command as a command reference would (FROM ref, ARGS as body)
#   cmd-ref EXT NAME [ARGS]   parse "command NAME LEN" + ARGS for extension EXT and invoke it
#   when CLAUSE               "when=1", "when=0" or "when error at N: TEXT"
#   print-context [KEY]       the built-in context keys ("KEY=VALUE" lines), or one key
#   ctx-set KEY VALUE         a published built-in key's value ("-" clears it), as another part would
#   print-keys [EXT]          every binding (or an extension's): strokes, command, source, rank, state
#   print-chord               "chord=none" or "chord=STROKE fallback=COMMAND ms=N"
#   key-latin LATIN COMBO     a key press whose Latin-layout key is LATIN (a layout that is not Latin)
#   print-contrib-problems EXT  the extension's dropped contribution entries
#   print-status              the status items: side, priority, owner, text, command, where drawn
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
    .quad .Lc_print_keys, c_print_keys, .Lc_print_chord, c_print_chord, .Lc_key_latin, c_key_latin
    .quad .Lc_print_problems, c_print_problems, .Lc_print_status, c_print_status
    .quad 0, 0
.Lc_cmd_args: .asciz "cmd-args"
.Lc_cmd_ref: .asciz "cmd-ref"
.Lc_when: .asciz "when"
.Lc_print_context: .asciz "print-context"
.Lc_ctx_set: .asciz "ctx-set"
.Lc_print_keys: .asciz "print-keys"
.Lc_print_chord: .asciz "print-chord"
.Lc_key_latin: .asciz "key-latin"
.Lc_print_problems: .asciz "print-contrib-problems"
.Lc_print_status: .asciz "print-status"
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

# print-keys [EXT]
c_print_keys:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    xor r12d, r12d
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    mov r12, rax
    test rax, rax
    jz 8f
1:  mov rdi, rbx
    mov rsi, r12
    call keys_dump
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# print-chord
c_print_chord:
    jmp keys_chord_dump

# key-latin LATIN COMBO: COMBO's key, as a layout that is not Latin reports it, with LATIN as the
# key on the first layout (g_key_latin)
c_key_latin:
    PROLOGUE
    mov r13, rsi
    mov r14, rdx
    call cc_word
    mov rdi, rax
    mov rsi, rdx
    call parse_combo
    mov r15d, eax
    mov rdi, r13
    mov rsi, r14
    call trim
    mov rdi, rax
    mov rsi, rdx
    call parse_combo
    test eax, eax
    jz 9f
    mov r12d, eax
    mov ebx, edx
    mov [rip + g_key_latin], r15d
    mov edi, r12d
    call keysym_to_unicode
    mov esi, eax
    mov edi, r12d
    mov edx, ebx
    call app_on_key
    mov dword ptr [rip + g_key_latin], 0
9:  xor eax, eax
    EPILOGUE

# print-contrib-problems EXT
c_print_problems:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 8f
    mov rdi, rbx
    mov rsi, rax
    call contrib_problems_dump
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# print-status: after a frame, so the items' places are the ones on screen
c_print_status:
    push rdi
    push rdi
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  pop rdi
    pop rdi
    jmp status_dump
