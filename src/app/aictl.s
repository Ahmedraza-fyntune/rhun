# headless commands for the AI features (wider-parity D), reached from control.s for names its
# table does not have: they drive the agents panel's extension sessions, the Review tab and tools,
# and print their state for tests
.include "rhun.inc"

.bss
.p2align 3
args_p: .quad 0
args_n: .quad 0
outsb: .quad 0

.text

# ai_set(out, rest, len): the arguments the command's handler reads (every handler calls it first)
ai_set:
    mov [rip + outsb], rdi
    mov [rip + args_p], rsi
    mov [rip + args_n], rdx
    ret

# FN ai_arg() -> rax ptr, rdx len: the next space-separated argument
FN ai_arg
    mov rdi, [rip + args_p]
    mov rsi, [rip + args_n]
    push rbx
    call next_word
    add [rip + args_p], rcx
    sub [rip + args_n], rcx
    pop rbx
    ret

# FN ai_arg_rest() -> rax ptr, rdx len: what is left of the line
FN ai_arg_rest
    mov rax, [rip + args_p]
    mov rdx, [rip + args_n]
    ret

# FN ai_out() -> rax the output buffer (SB*)
FN ai_out
    mov rax, [rip + outsb]
    ret

# agents-source OWNER/NAME: its switch in Settings > Agents, flipped
c_agents_source:
    PROLOGUE
    call ai_set
    call ai_arg
    mov rdi, rax
    mov rsi, rdx
    call agentext_toggle_named
    xor eax, eax
    EPILOGUE

# print-review: the proposals, their files and hunks
c_print_review:
    PROLOGUE
    call ai_set
    call ai_out
    mov rdi, rax
    call review_dump
    xor eax, eax
    EPILOGUE

# review accept|reject FILE|all [HUNK]: decide in the active Review tab (else the newest one); FILE and
#   HUNK count from 1
c_review:
    PROLOGUE 16
    call ai_set
    call review_current
    test rax, rax
    jz 9f
    mov rbx, rax
    call ai_arg
    mov r12d, 1
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lw_accept]
    push rdi
    push rsi
    call str_eq_cstr
    pop rsi
    pop rdi
    test eax, eax
    jnz 1f
    xor r12d, r12d
    lea rdx, [rip + .Lw_reject]
    call str_eq_cstr
    test eax, eax
    jz 9f
1:  call ai_arg
    mov r13, -1                 # all
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lw_all]
    push rdi
    push rsi
    call str_eq_cstr
    pop rsi
    pop rdi
    test eax, eax
    jnz 2f
    call parse_u64
    lea r13, [rax - 1]
2:  mov r14, -1
    call ai_arg
    test rdx, rdx
    jz 3f
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    lea r14, [rax - 1]
3:  mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov ecx, r12d
    call review_decide
9:  xor eax, eax
    EPILOGUE

# agent-new OWNER/NAME: the agents panel writes a new session of that extension (D4)
c_agent_new:
    PROLOGUE
    call ai_set
    call ai_arg
    mov rdi, rax
    mov rsi, rdx
    call agentext_named
    test rax, rax
    jz 9f
    mov rbx, rax
    call cmd_focus_agents
    mov rdi, rbx
    call agentext_new
9:  xor eax, eax
    EPILOGUE

# agent-prompt TEXT: TEXT in the prompt box, sent as Enter sends it
c_agent_prompt:
    PROLOGUE
    call ai_set
    call ai_arg_rest
    mov rbx, rax
    mov r12, rdx
    call agentext_field
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call tf_set
    call agentext_send
    xor eax, eax
    EPILOGUE

# agent-stop: Stop in the open extension session
c_agent_stop:
    PROLOGUE
    call ai_set
    call agents_ext_open
    test rax, rax
    jz 9f
    mov rdi, rax
    call agentext_stop
9:  xor eax, eax
    EPILOGUE

# agent-card N: option N (from 1) of the open session's card
c_agent_card:
    PROLOGUE
    call ai_set
    call ai_arg
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    lea rbx, [rax - 1]
    call agents_ext_open
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rbx
    call agentext_pick
9:  xor eax, eax
    EPILOGUE

# print-agent-input: the prompt box, the new session, the prompt in flight and the open card
c_print_agent_input:
    PROLOGUE
    call ai_set
    call ai_out
    mov rdi, rax
    call agentext_input_dump
    xor eax, eax
    EPILOGUE

# print-tools: the tools a tools request lists, then the calls in flight
c_print_tools:
    PROLOGUE
    call ai_set
    call ai_out
    mov rdi, rax
    call tools_dump
    xor eax, eax
    EPILOGUE

# tool-confirm once|session|deny: the answer to the tool dialog
c_tool_confirm:
    PROLOGUE
    call ai_set
    call tools_asking
    test rax, rax
    jz 9f
    call ai_arg
    mov rbx, rax
    mov r12, rdx
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lw_once]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov edi, 2                  # Allow once, the dialog's own button
    call app_dialog_button
    jmp 9f
1:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lw_session]
    call str_eq_cstr
    test eax, eax
    jz 2f
    mov edi, 1                  # Allow for this session, between
    call app_dialog_button
    jmp 9f
2:  xor edi, edi
    call app_dialog_button
9:  xor eax, eax
    EPILOGUE

.section .rodata
.Lc_agents_source: .asciz "agents-source"
.Lc_agent_new: .asciz "agent-new"
.Lc_agent_prompt: .asciz "agent-prompt"
.Lc_agent_stop: .asciz "agent-stop"
.Lc_agent_card: .asciz "agent-card"
.Lc_print_agent_input: .asciz "print-agent-input"
.Lc_print_tools: .asciz "print-tools"
.Lc_tool_confirm: .asciz "tool-confirm"
.Lw_once: .asciz "once"
.Lw_session: .asciz "session"
.Lc_print_review: .asciz "print-review"
.Lc_review: .asciz "review"
.Lw_accept: .asciz "accept"
.Lw_reject: .asciz "reject"
.Lw_all: .asciz "all"
.p2align 3
.globl ai_ctl
ai_ctl:
    .quad .Lc_agents_source, c_agents_source
    .quad .Lc_print_review, c_print_review, .Lc_review, c_review
    .quad .Lc_print_tools, c_print_tools, .Lc_tool_confirm, c_tool_confirm
    .quad .Lc_agent_new, c_agent_new, .Lc_agent_prompt, c_agent_prompt
    .quad .Lc_agent_stop, c_agent_stop, .Lc_agent_card, c_agent_card
    .quad .Lc_print_agent_input, c_print_agent_input
    .quad 0, 0
