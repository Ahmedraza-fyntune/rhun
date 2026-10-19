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
#   cmd_options(cmd) -> CO*, cmd_enabled(cmd), cmd_in_palette(cmd)   [command-options]
#   ext_cmd_owner(cmd) -> EXT*
# and the requests run-command (an extension runs a built-in or another extension's callable
# command) and call (rhun asks that command's owner and relays the answer).
.include "rhun.inc"

# a pending call: run-command waiting for another extension's answer
.equ IP_caller, 0               # EXT* that asked
.equ IP_cid, 8                  # its request id
.equ IP_owner, 16               # EXT* whose command runs; 0: the slot is free
.equ IP_hid, 24                 # the id of the call sent to it, 0 until sent
.equ IP_deadline, 32            # time_ms when it is given up
.equ IP_cmd, 40                 # owned cstr: the command's full name (EXT.NAME)
.equ IP_args, 48                # owned copy of ARGS, or 0
.equ IP_alen, 56
.equ IP_SIZE, 64
.equ IP_MAX, 64
.equ IP_PER_CALLER, 8
.equ IP_WAIT_MS, 10000
.equ IP_RESULT_MAX, 1048576
.equ IP_ARGS_LINE_MAX, 1024     # ARGS of the built-ins that take them
# [command-options]: per extension, CO records in co_opts[extension index]
.equ CO_name, 0                 # owned cstr, the local command name
.equ CO_icon, 8                 # owned cstr, or 0
.equ CO_when, 16                # WC*, or 0
.equ CO_flags, 24
.equ CO_SIZE, 32
.equ CO_HIDDEN, 1               # palette = no
.equ CO_CALLABLE, 2             # callable = yes

.bss
.p2align 3
.globl g_invoke
g_invoke: .zero INV_SIZE        # the invocation being run: cmd_invoke sets it, ext_cmd_run takes it
ip_table: .zero IP_MAX * IP_SIZE
iv_out: .zero SB_SIZE
co_opts: .zero EXT_CAP * VEC_SIZE
iv_msg: .zero 256

.text

# FN cmd_invoke(cmd*, from, body, len, doc id): run the command as invoked from INV_* with that
# body (ARGS of a key binding, TARGET and args of a menu item, a reference's ARGS) about that
# document (0: the active one). Built-in commands ignore what they do not use.
FN cmd_invoke
    PROLOGUE
    cmp rcx, INV_BODY_MAX       # a body no extension may be given: nothing runs
    ja 9f
    mov rbx, rdi
    mov [rip + g_invoke + INV_from], esi
    mov [rip + g_invoke + INV_body], rdx
    mov [rip + g_invoke + INV_len], rcx
    mov [rip + g_invoke + INV_doc], r8
    mov rdi, rbx
    call [rbx + CMD_fn]
    call invoke_clear
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

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

# ---------------------------------------------------------------- [command-options]

# FN ext_cmd_owner(cmd*) -> rax the EXT of an extension command, or 0 (a built-in)
FN ext_cmd_owner
    mov rax, rdi
    sub rax, [rip + g_ext_cmds + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, CMD_SIZE
    div rcx
    test rdx, rdx
    jnz 8f
    cmp rax, [rip + g_ext_cmds + VEC_len]
    jae 8f
    cmp rax, [rip + g_ext_owner + VEC_len]
    jae 8f
    mov rcx, [rip + g_ext_owner + VEC_ptr]
    mov rax, [rcx + rax*8]
    cmp rax, [rip + g_exts + VEC_len]
    jae 8f
    imul rax, rax, EXT_SIZE
    add rax, [rip + g_exts + VEC_ptr]
    ret
8:  xor eax, eax
    ret

# co_vec(ext) -> rax its VEC of CO records, or 0
co_vec:
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    cmp rax, EXT_CAP
    jae 8f
    imul rax, rax, VEC_SIZE
    lea rcx, [rip + co_opts]
    add rax, rcx
    ret
8:  xor eax, eax
    ret

# FN cmdopt_find(ext, local, len) -> rax the command's CO record, or 0
FN cmdopt_find
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call co_vec
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 8f
    imul r15, r14, CO_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + CO_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN cmd_icon(cmd*) -> rax the [command-options] icon of an extension command (cstr), or 0
FN cmd_icon
    sub rsp, 8
    call cmd_options
    test rax, rax
    jz 1f
    mov rax, [rax + CO_icon]
1:  add rsp, 8
    ret

# FN cmd_options(cmd*) -> rax the CO record of an extension command, or 0
FN cmd_options
    PROLOGUE
    mov rbx, rdi
    call ext_cmd_owner
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, [rbx + CMD_name]
    call strlen
    mov r13, rax
    mov rdi, [rbx + CMD_name]
    mov rsi, rax
    lea rdx, [rip + .Ldot]
    mov ecx, 1
    call str_find
    test rax, rax
    js 8f
    mov rsi, [rbx + CMD_name]
    lea rsi, [rsi + rax + 1]
    mov rdx, r13
    sub rdx, rax
    dec rdx
    mov rdi, r12
    call cmdopt_find
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN cmd_enabled(cmd*) -> eax 0 when its [command-options] when clause is false, else 1
FN cmd_enabled
    PROLOGUE
    call cmd_options
    mov ecx, 1
    test rax, rax
    jz 9f
    mov rdi, [rax + CO_when]
    test rdi, rdi
    jz 9f
    call when_eval
    mov ecx, eax
9:  mov eax, ecx
    EPILOGUE

# FN cmd_in_palette(cmd*) -> eax 1 when the palette lists it: not palette = no, and enabled
FN cmd_in_palette
    PROLOGUE
    mov rbx, rdi
    call cmd_options
    test rax, rax
    jz 7f
    test dword ptr [rax + CO_flags], CO_HIDDEN
    jnz 8f
    mov rdi, [rax + CO_when]
    test rdi, rdi
    jz 7f
    call when_eval
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN cmdopt_parse(ext, ini): one [command-options] line, NAME.FIELD = VALUE; a bad line is a problem
# shown on the extension's page
FN cmdopt_parse
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + INI_key]
    mov r14, [r12 + INI_keylen]
    # NAME and FIELD: split at the last dot
    mov rcx, r14
1:  test rcx, rcx
    jz .Lco_bad
    dec rcx
    cmp byte ptr [r13 + rcx], '.'
    jne 1b
    mov r15, rcx                # NAME's length
    mov rdi, r13
    mov rsi, r15
    call cmd_name_ok
    test eax, eax
    jz .Lco_bad
    mov rdi, rbx
    call co_vec
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r15
    call cmdopt_find
    test rax, rax
    jnz 2f
    mov rdi, [rsp]
    mov esi, CO_SIZE
    call vec_push
    mov [rsp + 8], rax
    mov rdi, r13
    mov rsi, r15
    call mem_dup
    mov rcx, [rsp + 8]
    mov [rcx + CO_name], rax
    xor eax, eax
    mov [rcx + CO_icon], rax
    mov [rcx + CO_when], rax
    mov [rcx + CO_flags], rax
    mov rax, rcx
2:  mov [rsp + 8], rax
    lea r13, [r13 + r15 + 1]    # FIELD
    sub r14, r15
    dec r14
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lco_icon]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov rcx, [rsp + 8]
    mov rdi, [rcx + CO_icon]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call mem_dup
    mov rcx, [rsp + 8]
    mov [rcx + CO_icon], rax
    jmp 9f
3:  mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lco_when]
    call str_eq_cstr
    test eax, eax
    jz 4f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    mov rdx, rbx
    call when_compile
    test rax, rax
    jz .Lco_when_bad
    mov rcx, [rsp + 8]
    mov rdi, [rcx + CO_when]
    mov [rcx + CO_when], rax
    call when_free
    jmp 9f
4:  mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lco_palette]
    call str_eq_cstr
    test eax, eax
    jz 5f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call parse_bool
    mov rcx, [rsp + 8]
    or dword ptr [rcx + CO_flags], CO_HIDDEN
    test eax, eax
    jz 9f
    and dword ptr [rcx + CO_flags], ~CO_HIDDEN
    jmp 9f
5:  mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lco_callable]
    call str_eq_cstr
    test eax, eax
    jz .Lco_bad
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call parse_bool
    mov rcx, [rsp + 8]
    and dword ptr [rcx + CO_flags], ~CO_CALLABLE
    test eax, eax
    jz 9f
    or dword ptr [rcx + CO_flags], CO_CALLABLE
9:  EPILOGUE
.Lco_bad:
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lco_bad_text]
    call contrib_problem_line
    EPILOGUE
.Lco_when_bad:
    mov rdi, rbx                # rdx the byte, rcx the text
    mov rsi, r12
    call contrib_problem_when
    EPILOGUE

# cmdopt_clear(ext): its [command-options] go (the extension was removed)
FN cmdopt_clear
    PROLOGUE
    call co_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    imul r13, r12, CO_SIZE
    add r13, [rbx + VEC_ptr]
    inc r12
    mov rdi, [r13 + CO_name]
    call mem_free
    mov rdi, [r13 + CO_icon]
    call mem_free
    mov rdi, [r13 + CO_when]
    call when_free
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
9:  EPILOGUE

# ---------------------------------------------------------------- run-command and call

# iv_reply(ext, id, text cstr): "error ID TEXT" (text "ok" alone: "ok ID 0")
iv_error:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rip + iv_out]
    call sb_clear
    lea rdi, [rip + iv_out]
    lea rsi, [rip + .Lerror_sp]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + iv_out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + iv_out]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + iv_out + SB_ptr]
    mov rdx, [rip + iv_out + SB_len]
    call ext_send_checked
    EPILOGUE

# iv_ok(ext, id, body, len): "ok ID LEN" + body
iv_ok:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rdi, [rip + iv_out]
    call sb_clear
    lea rdi, [rip + iv_out]
    lea rsi, [rip + .Lok_sp]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + iv_out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + iv_out]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + iv_out]
    mov esi, 10
    call sb_push_byte
    test r14, r14
    jz 1f
    lea rdi, [rip + iv_out]
    mov rsi, r13
    mov rdx, r14
    call sb_push
1:  mov rdi, rbx
    mov rsi, [rip + iv_out + SB_ptr]
    mov rdx, [rip + iv_out + SB_len]
    call ext_send_checked
    EPILOGUE

# FN invoke_run(caller, id, name, nlen, args, alen) -> eax 0 answered or waiting, 1 for a syntax
# error the caller answers: "ID run-command NAME LEN" + ARGS (feature command-args)
FN invoke_run
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8               # ARGS
    mov [rsp + 8], r9
    # rhun.NAME and a plain NAME are built-ins
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lrhun_dot]
    mov ecx, 5
    call str_starts
    test eax, eax
    jz 1f
    add r13, 5
    sub r14, 5
    jmp .Lir_builtin
1:  mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Ldot]
    mov ecx, 1
    call str_find
    test rax, rax
    js .Lir_builtin
    # another extension's command: it must be callable
    mov rdi, r13
    mov rsi, r14
    call ext_cmd_find
    test rax, rax
    jz .Lir_no_command
    mov r15, rax
    mov rdi, rax
    call ext_cmd_owner
    test rax, rax
    jz .Lir_no_command
    mov [rsp + 16], rax         # the owner
    cmp rax, rbx
    je .Lir_own
    mov rdi, r15
    call cmd_options
    test rax, rax
    jz .Lir_not_callable
    test dword ptr [rax + CO_flags], CO_CALLABLE
    jz .Lir_not_callable
    # at most IP_PER_CALLER waiting, IP_MAX in all
    xor ecx, ecx
    xor edx, edx                # the caller's
    mov r8, -1                  # a free slot
    lea r9, [rip + ip_table]
2:  cmp ecx, IP_MAX
    jae 3f
    cmp qword ptr [r9 + IP_owner], 0
    jne 21f
    cmp r8, -1
    jne 22f
    mov r8, r9
    jmp 22f
21: cmp [r9 + IP_caller], rbx
    jne 22f
    inc edx
22: add r9, IP_SIZE
    inc ecx
    jmp 2b
3:  cmp edx, IP_PER_CALLER
    jae .Lir_busy
    cmp r8, -1
    je .Lir_busy
    mov [rsp + 24], r8
    # the owner must be able to run
    mov rax, [rsp + 16]
    mov ecx, [rax + EXT_status]
    cmp ecx, ES_FAILED
    jae .Lir_off
    cmp ecx, ES_STOPPED
    je .Lir_off
    cmp dword ptr [rax + EXT_disabled], 0
    jne .Lir_off
    mov r8, [rsp + 24]
    mov [r8 + IP_caller], rbx
    mov [r8 + IP_cid], r12
    mov rax, [rsp + 16]
    mov [r8 + IP_owner], rax
    mov qword ptr [r8 + IP_hid], 0
    call time_ms
    add rax, IP_WAIT_MS
    mov r8, [rsp + 24]
    mov [r8 + IP_deadline], rax
    mov rdi, [r15 + CMD_name]
    call dup_cstr
    mov r8, [rsp + 24]
    mov [r8 + IP_cmd], rax
    mov qword ptr [r8 + IP_args], 0
    mov rax, [rsp + 8]
    mov [r8 + IP_alen], rax
    test rax, rax
    jz 4f
    mov rdi, [rsp]
    mov rsi, rax
    call mem_dup
    mov r8, [rsp + 24]
    mov [r8 + IP_args], rax
4:  # running: ask now; idle or crashed: start it (the tick asks once it is ready)
    mov rdi, [rsp + 16]
    mov eax, [rdi + EXT_status]
    cmp eax, ES_RUNNING
    jne 5f
    mov rdi, [rsp + 24]
    call ip_send
    jmp .Lir_done
5:  cmp eax, ES_IDLE
    je 6f
    cmp eax, ES_CRASHED
    jne .Lir_done               # starting or stopping: the tick sees it through
6:  call ext_start
.Lir_done:
    xor eax, eax
    EPILOGUE
.Lir_builtin:
    # v1 section 8a's list, with its needs
    lea r15, [rip + cmd_allow]
7:  mov rdx, [r15]
    test rdx, rdx
    jz .Lir_refused_builtin
    mov rdi, r13
    mov rsi, r14
    call str_eq_cstr
    test eax, eax
    jnz 8f
    add r15, 16
    jmp 7b
8:  mov eax, [r15 + 8]
    test eax, eax
    jz 81f
    mov ecx, [rbx + EXT_needs]
    and ecx, eax
    cmp ecx, eax
    jne .Lir_needs
81: # ARGS: the built-ins that take them, one line of text
    mov qword ptr [rsp + 32], -1    # its index among them
    cmp qword ptr [rsp + 8], 0
    je 84f
    cmp qword ptr [rsp + 8], IP_ARGS_LINE_MAX
    ja .Lir_syntax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call iv_line_ok
    test eax, eax
    jz .Lir_syntax
84: xor ecx, ecx
    lea r8, [rip + args_cmds]
82: mov rdx, [r8 + rcx*8]
    test rdx, rdx
    jz 83f
    push rcx
    push r8
    mov rdi, r13
    mov rsi, r14
    call str_eq_cstr
    pop r8
    pop rcx
    test eax, eax
    jnz 85f
    inc ecx
    jmp 82b
85: mov [rsp + 32], rcx
83: cmp qword ptr [rsp + 8], 0
    je 86f
    cmp qword ptr [rsp + 32], -1
    je .Lir_syntax
86: # the palette's built-ins wait for an open palette or prompt to close
    mov rcx, [rsp + 32]
    cmp rcx, -1
    je 87f
    cmp rcx, 2                  # find_in_files, quick_open, command_palette, goto_line
    jb 87f
    cmp dword ptr [rip + g_focus], FOCUS_PALETTE
    je .Lir_busy_prompt
    cmp dword ptr [rip + g_focus], FOCUS_PROMPT
    je .Lir_busy_prompt
87: mov rdi, r13
    mov rsi, r14
    call cmd_find
    test rax, rax
    jz .Lir_refused_builtin
    mov r15, rax
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    call iv_ok
    # goto_line LINE [COL] moves the cursor without the palette
    cmp qword ptr [rsp + 32], 5
    jne 88f
    cmp qword ptr [rsp + 8], 0
    je 88f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call iv_goto
    jmp .Lir_done
88: mov rdi, r15
    mov esi, INV_REF
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    xor r8d, r8d
    call cmd_invoke
    cmp qword ptr [rsp + 8], 0
    je .Lir_done
    mov rax, [rsp + 32]
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    cmp rax, 2
    jb 89f
    cmp dword ptr [rip + g_focus], FOCUS_PALETTE
    jne .Lir_done
    call palette_set_query
    jmp .Lir_done
89: cmp dword ptr [rip + g_focus], FOCUS_FIND
    jne .Lir_done
    call find_set_query
    jmp .Lir_done
.Lir_syntax:
    mov eax, 1
    EPILOGUE
.Lir_no_command:
    lea rdx, [rip + .Le_no_command]
    jmp .Lir_error
.Lir_own:
    lea rdx, [rip + .Le_own]
    jmp .Lir_error
.Lir_not_callable:
    lea rdx, [rip + .Le_not_callable]
    jmp .Lir_error
.Lir_off:
    lea rdx, [rip + .Le_off]
    jmp .Lir_error
.Lir_busy:
    lea rdx, [rip + .Le_busy_calls]
    jmp .Lir_error
.Lir_busy_prompt:
    lea rdx, [rip + .Le_busy_prompt]
    jmp .Lir_error
.Lir_refused_builtin:
    lea rdx, [rip + .Le_refused_builtin]
    jmp .Lir_error
.Lir_needs:
    lea rdx, [rip + .Le_needs_write]
    test eax, NEEDS_DOC_WRITE
    jnz .Lir_error
    lea rdx, [rip + .Le_needs_terminal]
.Lir_error:
    mov rdi, rbx
    mov rsi, r12
    call iv_error
    xor eax, eax
    EPILOGUE

# iv_line_ok(ptr, len) -> eax 1 for one line of UTF-8 without control characters
iv_line_ok:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp eax, 0x20
    jb 8f
    cmp eax, 0x7f
    je 8f
    jmp 1b
2:  jmp snippet_utf8_valid
8:  xor eax, eax
    ret

# iv_goto(ptr, len): "LINE" or "LINE COL" (one-based; past the end goes to the end)
iv_goto:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    mov rdi, rax
    mov rsi, rdx
    mov [rsp], rdx
    call parse_u64
    cmp rdx, [rsp]
    jne 9f
    test rax, rax
    jz 9f
    dec rax
    cmp rax, [rbx + DOC_nlines]
    jb 1f
    mov rax, [rbx + DOC_nlines]
    dec rax
1:  mov r14, rax                # the line, 0-based
    mov r15d, 1                 # the column
    mov rdi, r12
    mov rsi, r13
    call next_word
    test rdx, rdx
    jz 2f
    mov rdi, rax
    mov rsi, rdx
    mov [rsp], rdx
    call parse_u64
    cmp rdx, [rsp]
    jne 2f
    test rax, rax
    jz 2f
    mov r15, rax
2:  mov rdi, rbx
    mov rsi, r14
    call doc_line_end
    mov r12, rax
    mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    lea rsi, [rax + r15 - 1]
    cmp rsi, r12
    jbe 3f
    mov rsi, r12
3:  mov rdi, rbx
    xor edx, edx
    call ed_set_cursor
    or dword ptr [rbx + DOC_flags], DF_REVEAL | DF_CENTER
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ip_free(slot)
ip_free:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + IP_cmd]
    call mem_free
    mov rdi, [rbx + IP_args]
    call mem_free
    xor eax, eax
    mov [rbx + IP_owner], rax
    mov [rbx + IP_cmd], rax
    mov [rbx + IP_args], rax
    mov [rbx + IP_hid], rax
    pop rbx
    ret

# ip_send(slot): "HID call EXT.NAME DOC CALLER LEN" + ARGS to the owner; an owner that did not
# agree command-args, or a send that fails, answers the caller at once
ip_send:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + IP_owner]
    FEAT_TEST r12, FEAT_COMMAND_ARGS
    jz .Lips_not_callable
    cmp qword ptr [r12 + EXT_hreq], 2147483647
    jae .Lips_cancelled
    call extproto_cur
    mov r14, rax
    mov rdi, r12
    call extproto_events        # every document event first
    mov r15, rax
    mov rdi, r14
    call extproto_set_cur       # the extension being served stays the one it was
    test r15, r15
    js .Lips_cancelled
    inc qword ptr [r12 + EXT_hreq]
    mov r13, [r12 + EXT_hreq]
    lea rdi, [rip + iv_out]
    call sb_clear
    lea rdi, [rip + iv_out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + iv_out]
    lea rsi, [rip + .Lcall_sp]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov rsi, [rbx + IP_cmd]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov esi, ' '
    call sb_push_byte
    call iv_active_doc
    lea rdi, [rip + iv_out]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + iv_out]
    mov esi, ' '
    call sb_push_byte
    mov rax, [rbx + IP_caller]
    lea rdi, [rip + iv_out]
    mov rsi, [rax + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov esi, '/'
    call sb_push_byte
    mov rax, [rbx + IP_caller]
    lea rdi, [rip + iv_out]
    mov rsi, [rax + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + iv_out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + iv_out]
    mov rsi, [rbx + IP_alen]
    call sb_push_u64
    lea rdi, [rip + iv_out]
    mov esi, 10
    call sb_push_byte
    mov rdx, [rbx + IP_alen]
    test rdx, rdx
    jz 1f
    lea rdi, [rip + iv_out]
    mov rsi, [rbx + IP_args]
    call sb_push
1:  mov rdi, r12
    mov rsi, [rip + iv_out + SB_ptr]
    mov rdx, [rip + iv_out + SB_len]
    call ext_send_checked
    test rax, rax
    js .Lips_cancelled
    mov [rbx + IP_hid], r13
    EPILOGUE
.Lips_not_callable:
    lea rdx, [rip + .Le_not_callable]
    jmp 8f
.Lips_cancelled:
    lea rdx, [rip + .Le_cancelled]
8:  mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    call iv_error
    mov rdi, rbx
    call ip_free
    EPILOGUE

# FN invoke_active_doc() -> rax the active document's id, or 0
FN invoke_active_doc
iv_active_doc:
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rdi, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    mov rax, [rax + DOC_id]
    ret
8:  xor eax, eax
    ret

# FN invoke_reply(ext, id, ok, body, len) -> eax 1 when it answered a call rhun relays: "ok ID
# LEN" + RESULT goes to the caller as it is (RESULT over 1 MiB: toobig), "error ID CODE TEXT" with
# its code and text (body, len: the text after the id)
FN invoke_reply
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    lea rax, [rip + ip_table]
    xor ecx, ecx
1:  cmp ecx, IP_MAX
    jae 8f
    cmp [rax + IP_owner], rbx
    jne 2f
    cmp [rax + IP_hid], r12
    je 3f
2:  add rax, IP_SIZE
    inc ecx
    jmp 1b
3:  mov rbx, rax                # the slot
    test r13d, r13d
    jz 5f
    cmp r15, IP_RESULT_MAX
    ja 4f
    mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    mov rdx, r14
    mov rcx, r15
    call iv_ok
    jmp 7f
4:  mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    lea rdx, [rip + .Le_toobig_result]
    call iv_error
    jmp 7f
5:  # the error's code and text, at most a line of 200 bytes
    cmp r15, 200
    jbe 6f
    mov r15d, 200
6:  lea rdi, [rip + iv_msg]
    mov rsi, r14
    mov rdx, r15
    call memcpy
    lea rax, [rip + iv_msg]
    mov byte ptr [rax + r15], 0
    mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    lea rdx, [rip + iv_msg]
    test r15, r15
    jnz 61f
    lea rdx, [rip + .Le_cancelled]
61: call iv_error
7:  mov rdi, rbx
    call ip_free
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN invoke_tick(): calls whose owner became ready are sent; late ones are given up
FN invoke_tick
    PROLOGUE
    call time_ms
    mov r13, rax
    lea rbx, [rip + ip_table]
    xor r12d, r12d
1:  cmp r12d, IP_MAX
    jae 9f
    mov r14, [rbx + IP_owner]
    test r14, r14
    jz 5f
    cmp qword ptr [rbx + IP_hid], 0
    jne 3f
    # not sent yet: the owner is ready, or will not be
    mov eax, [r14 + EXT_status]
    cmp eax, ES_RUNNING
    jne 2f
    cmp dword ptr [r14 + EXT_hello], 0
    je 3f
    mov rdi, rbx
    call ip_send
    jmp 5f
2:  cmp eax, ES_IDLE
    je 21f
    cmp eax, ES_STARTING
    je 3f
    cmp eax, ES_STOPPING
    je 3f
    jmp 4f                      # failed, stopped, disabled, removed, crashed
21: cmp dword ptr [r14 + EXT_wait_slot], 0
    je 4f
3:  cmp r13, [rbx + IP_deadline]
    jb 5f
    mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    lea rdx, [rip + .Le_timeout]
    call iv_error
    mov rsi, [rbx + IP_hid]
    test rsi, rsi
    jz 31f
    mov rdi, [rbx + IP_owner]
    call extproto_send_cancel
31: mov rdi, rbx
    call ip_free
    jmp 5f
4:  mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    lea rdx, [rip + .Le_cancelled]
    call iv_error
    mov rdi, rbx
    call ip_free
5:  add rbx, IP_SIZE
    inc r12d
    jmp 1b
9:  EPILOGUE

# FN invoke_timeout() -> rax milliseconds until a call needs the tick, or -1
FN invoke_timeout
    PROLOGUE
    mov r12, -1
    call time_ms
    mov r13, rax
    lea rbx, [rip + ip_table]
    xor ecx, ecx
1:  cmp ecx, IP_MAX
    jae 9f
    cmp qword ptr [rbx + IP_owner], 0
    je 3f
    mov eax, 16                 # waiting for its owner to be ready
    cmp qword ptr [rbx + IP_hid], 0
    je 2f
    mov rax, [rbx + IP_deadline]
    sub rax, r13
    jns 2f
    xor eax, eax
2:  cmp r12, -1
    je 21f
    cmp rax, r12
    jae 3f
21: mov r12, rax
3:  add rbx, IP_SIZE
    inc ecx
    jmp 1b
9:  mov rax, r12
    EPILOGUE

# FN invoke_ext_stopped(ext): its calls end: as owner, its callers get cancelled; as caller, the
# owner gets 0 cancel
FN invoke_ext_stopped
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + ip_table]
    xor r13d, r13d
1:  cmp r13d, IP_MAX
    jae 9f
    cmp qword ptr [rbx + IP_owner], 0
    je 5f
    cmp [rbx + IP_owner], r12
    jne 2f
    mov rdi, [rbx + IP_caller]
    mov rsi, [rbx + IP_cid]
    lea rdx, [rip + .Le_cancelled]
    call iv_error
    mov rdi, rbx
    call ip_free
    jmp 5f
2:  cmp [rbx + IP_caller], r12
    jne 5f
    mov rsi, [rbx + IP_hid]
    test rsi, rsi
    jz 3f
    call extproto_cur
    mov r14, rax
    mov rdi, [rbx + IP_owner]
    mov rsi, [rbx + IP_hid]
    call extproto_send_cancel
    mov rdi, r14
    call extproto_set_cur
3:  mov rdi, rbx
    call ip_free
5:  add rbx, IP_SIZE
    inc r13d
    jmp 1b
9:  EPILOGUE

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
.Ldot: .asciz "."
.Lrhun_dot: .asciz "rhun."
.Lok_sp: .asciz "ok "
.Lerror_sp: .asciz "error "
.Lcall_sp: .asciz " call "
.Lco_icon: .asciz "icon"
.Lco_when: .asciz "when"
.Lco_palette: .asciz "palette"
.Lco_callable: .asciz "callable"
.Lco_bad_text: .asciz "[command-options]: not NAME.icon, .when, .palette or .callable"
.Le_no_command: .asciz "refused no such command"
.Le_own: .asciz "refused its own command"
.Le_not_callable: .asciz "refused not callable"
.Le_off: .asciz "refused the extension is turned off"
.Le_busy_calls: .asciz "busy 8 calls outstanding"
.Le_busy_prompt: .asciz "busy a prompt is open"
.Le_refused_builtin: .asciz "refused not a command an extension may run"
.Le_needs_write: .asciz "needs documents=write"
.Le_needs_terminal: .asciz "needs terminal=yes"
.Le_cancelled: .asciz "cancelled"
.Le_timeout: .asciz "cancelled timeout"
.Le_toobig_result: .asciz "toobig the result exceeds 1 MiB"
.p2align 3
# the built-ins that take ARGS: the find bar's (0, 1), the palette's (2-4), goto_line (5)
args_cmds: .quad .La_find, .La_replace, .La_find_in_files, .La_quick_open, .La_command_palette
    .quad .La_goto_line, 0
.La_find: .asciz "find"
.La_replace: .asciz "replace"
.La_find_in_files: .asciz "find_in_files"
.La_quick_open: .asciz "quick_open"
.La_command_palette: .asciz "command_palette"
.La_goto_line: .asciz "goto_line"
