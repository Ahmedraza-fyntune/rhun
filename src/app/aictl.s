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

# FN ai_control(name, len, rest, rest_len, out sb) -> rax 0 handled, -1 unknown
FN ai_control
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov [rip + args_p], rdx
    mov [rip + args_n], rcx
    mov [rip + outsb], r8
    lea rbx, [rip + ai_table]
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add rbx, 16
    jmp 1b
2:  call [rbx + 8]
    xor eax, eax
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

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
    call ai_arg
    mov rdi, rax
    mov rsi, rdx
    call agentext_toggle_named
    EPILOGUE

.section .rodata
.Lc_agents_source: .asciz "agents-source"
.p2align 3
ai_table:
    .quad .Lc_agents_source, c_agents_source
    .quad 0, 0
