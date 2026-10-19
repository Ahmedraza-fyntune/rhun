# the extension side of the debugger (docs/extensions/v1.1.md "debug"): feature `debug`. An
# extension starts a session of one of its own debuggers with `ID debug-start NAME_LEN LEN` + NAME +
# a configuration body, within 10 s of one of its commands (a test run's debug profile counts too),
# after the user's one approval per extension and project; it hears `0 debug-ended SESSION CODE`
# when that session is over. dap.s makes the session (dap_start_ext) and calls the replies here.
.include "rhun.inc"

.equ DBGX_WINDOW_MS, 10000      # debug-start must follow one of the extension's commands this soon
.equ DBGX_SLOTS, 64             # extensions remembered with their last command's time
.equ DBGX_NAME_MAX, 256

.bss
.p2align 3
win_ext: .zero 8 * DBGX_SLOTS   # EXT*, 0 free
win_at: .zero 8 * DBGX_SLOTS    # time_ms of its last command
xmsg: .zero SB_SIZE             # a reply or event being built

.text

# dbgx_note_command(EXT*): rhun sent the extension one of its commands (extproto_send_invoke):
#   a debug-start may follow within 10 s, once. Keeps every register but rax, rcx, rdx, rsi, rdi,
#   r8-r11
FN dbgx_note_command
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call time_ms
    mov r12, rax
    lea rsi, [rip + win_ext]
    lea rdi, [rip + win_at]
    # its own slot, else a free one, else the oldest
    xor ecx, ecx
    mov r8d, -1                 # a free slot
    xor r9d, r9d                # the oldest
1:  cmp ecx, DBGX_SLOTS
    jae 3f
    mov rax, [rsi + rcx*8]
    cmp rax, rbx
    je 5f
    test rax, rax
    jnz 2f
    test r8d, r8d
    jns 2f
    mov r8d, ecx
2:  mov rax, [rdi + rcx*8]
    cmp rax, [rdi + r9*8]
    jae 21f
    mov r9d, ecx
21: inc ecx
    jmp 1b
3:  mov ecx, r8d
    test ecx, ecx
    jns 5f
    mov ecx, r9d
5:  mov [rsi + rcx*8], rbx
    mov [rdi + rcx*8], r12
    add rsp, 8
    pop r12
    pop rbx
    ret

# window_take(EXT*) -> eax 1 when one of its commands ran in the last 10 s (the window is used up)
window_take:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call time_ms
    mov r12, rax
    lea rsi, [rip + win_ext]
    lea rdi, [rip + win_at]
    xor ecx, ecx
1:  cmp ecx, DBGX_SLOTS
    jae 8f
    cmp [rsi + rcx*8], rbx
    je 2f
    inc ecx
    jmp 1b
2:  mov qword ptr [rsi + rcx*8], 0
    mov rax, r12
    sub rax, [rdi + rcx*8]
    cmp rax, DBGX_WINDOW_MS
    ja 8f
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# dbgx_test_window(EXT*) -> eax 1 while that extension has a queued or running debug-profile test
#   run. A stub until the testing group exports testproto_debug_window (testproto.s): then this
#   becomes `jmp testproto_debug_window`
dbgx_test_window:
    xor eax, eax
    ret

# dbgx_h_debug_start(): ID debug-start NAME_LEN LEN + NAME + configuration body (extproto.s's verb
#   table). ok ID SESSION comes from launch_now; errors here: unknown (feature not agreed), needs,
#   syntax, refused (no recent command of its own, or a type not its own), busy, toobig
FN dbgx_h_debug_start
    PROLOGUE 16
    call xp_cur
    mov rbx, rax
    call xp_cur_id
    mov r12, rax
    FEAT_TEST rbx, FEAT_DEBUG
    jnz 1f
    mov rdi, r12
    lea rsi, [rip + .Le_unknown]
    call xp_reply_error
    EPILOGUE
1:  mov edi, NEEDS_DEBUG
    call xp_need
    test eax, eax
    jz 9f
    call xp_nfields
    cmp rax, 4
    jne .Lds_syntax
    mov edi, 2
    call xp_field_u64
    test edx, edx
    jz .Lds_syntax
    mov r13, rax                # NAME_LEN
    test r13, r13
    jz .Lds_syntax
    cmp r13, DBGX_NAME_MAX
    ja .Lds_syntax
    call xp_body
    mov r14, rax
    mov r15, rdx
    cmp r15, r13
    jb .Lds_syntax
    # the configuration
    mov rdi, r14
    mov rsi, r13
    lea rdx, [r14 + r13]
    mov rcx, r15
    sub rcx, r13
    mov r8, rbx
    call dcfg_from_leaves
    test eax, eax
    jnz 2f
    cmp dword ptr [rip + g_dcfg_code], DCE_REFUSED
    jne .Lds_syntax
    mov rdi, r12
    lea rsi, [rip + .Le_type]
    call xp_reply_error
    EPILOGUE
2:  # one session per command it ran in the last 10 s (or per debug-profile test run)
    mov rdi, rbx
    call window_take
    test eax, eax
    jnz 3f
    mov rdi, rbx
    call dbgx_test_window
    test eax, eax
    jnz 3f
    mov rdi, r12
    lea rsi, [rip + .Le_window]
    call xp_reply_error
    EPILOGUE
3:  call dap_live_count
    cmp eax, DS_MAX
    jb 4f
    mov rdi, r12
    lea rsi, [rip + .Le_toobig]
    call xp_reply_error
    EPILOGUE
4:  mov qword ptr [rip + g_dstart_msg], 0
    mov rdi, rbx
    mov rsi, r12
    call dap_start_ext
    test eax, eax
    jnz 9f                      # answered by launch_now or ds_end
    mov rsi, [rip + g_dstart_msg]
    test rsi, rsi
    jz 9f                       # a session was made and ended at once: ds_end answered
    mov rdi, rbx
    mov rdx, rsi
    mov rsi, r12
    call dbgx_reply_failed
9:  EPILOGUE
.Lds_syntax:
    mov rdi, r12
    call xp_reply_syntax
    EPILOGUE

# dbgx_reply_ok(EXT*, request id, session): ok ID SESSION
FN dbgx_reply_ok
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call live
    test eax, eax
    jz 9f
    lea rdi, [rip + xmsg]
    lea rsi, [rip + .Lw_ok]
    call sb_set_cstr_x
    lea rdi, [rip + xmsg]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + xmsg]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + xmsg]
    mov esi, r13d
    call sb_push_u64
    call send_line
9:  EPILOGUE

# dbgx_reply_failed(EXT*, request id, reason cstr): error ID cancelled | busy | toobig | refused TEXT
FN dbgx_reply_failed
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call live
    test eax, eax
    jz 9f
    lea rdi, [rip + xmsg]
    lea rsi, [rip + .Lw_error]
    call sb_set_cstr_x
    lea rdi, [rip + xmsg]
    mov rsi, r12
    call sb_push_u64
    lea rsi, [rip + .Le_cancelled]
    lea rax, [rip + dap_m_cancelled]
    cmp r13, rax
    je 1f
    lea rsi, [rip + .Le_busy]
    lea rax, [rip + dap_m_busy]
    cmp r13, rax
    je 1f
    lea rsi, [rip + .Le_toobig_sp]
    lea rax, [rip + dap_m_full]
    cmp r13, rax
    je 1f
    # refused and the reason, on one line
    lea rdi, [rip + xmsg]
    lea rsi, [rip + .Le_refused]
    call sb_push_cstr
    mov r14, r13
2:  movzx esi, byte ptr [r14]
    test esi, esi
    jz 3f
    cmp esi, 10
    jne 21f
    mov esi, ' '
21: lea rdi, [rip + xmsg]
    call sb_push_byte
    inc r14
    jmp 2b
1:  lea rdi, [rip + xmsg]
    call sb_push_cstr
3:  call send_line
9:  EPILOGUE

# dbgx_ended(EXT*, session, exit code or -1): 0 debug-ended SESSION CODE (- when unknown)
FN dbgx_ended
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    call live
    test eax, eax
    jz 9f
    FEAT_TEST rbx, FEAT_DEBUG
    jz 9f
    lea rdi, [rip + xmsg]
    lea rsi, [rip + .Lev_ended]
    call sb_set_cstr_x
    lea rdi, [rip + xmsg]
    mov esi, r12d
    call sb_push_u64
    lea rdi, [rip + xmsg]
    mov esi, ' '
    call sb_push_byte
    test r13d, r13d
    js 1f
    lea rdi, [rip + xmsg]
    mov esi, r13d
    call sb_push_u64
    jmp 2f
1:  lea rdi, [rip + xmsg]
    mov esi, '-'
    call sb_push_byte
2:  call send_line
9:  EPILOGUE

# live() -> eax 1 when rbx's extension still runs (a reply to a stopped one is dropped)
live:
    xor eax, eax
    test rbx, rbx
    jz 1f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1f
    mov eax, 1
1:  ret

# send_line(): xmsg and a newline to rbx's extension
send_line:
    sub rsp, 8
    lea rdi, [rip + xmsg]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + xmsg + SB_ptr]
    mov rdx, [rip + xmsg + SB_len]
    call xp_send
    add rsp, 8
    ret

# sb_set_cstr_x(sb, cstr)
sb_set_cstr_x:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
    add rsp, 8
    pop r12
    pop rbx
    ret

.section .rodata
.globl dbgx_v_debug_start
dbgx_v_debug_start: .asciz "debug-start"
.Lw_ok: .asciz "ok "
.Lw_error: .asciz "error "
.Lev_ended: .asciz "0 debug-ended "
.Le_unknown: .asciz "unknown debug-start needs the debug feature"
.Le_type: .asciz "refused the configuration's type is not one of your debuggers"
.Le_window: .asciz "refused not within 10 s of one of your commands"
.Le_toobig: .asciz "toobig 8 sessions"
.Le_toobig_sp: .asciz " toobig 8 sessions"
.Le_cancelled: .asciz " cancelled"
.Le_busy: .asciz " busy"
.Le_refused: .asciz " refused "
