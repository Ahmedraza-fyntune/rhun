# headless control commands of the notebooks (control.s's ctl_tables):
#   print-notebook            a line per cell of the active notebook, then its state (nb_dump)
#   print-nb-output I J       cell I's output J: kind, items, text, then <eoo>
#   nb-mode edit|command      as Enter and Esc
#   nb-select I               cell I selected, in command mode
#   nb-run I                  as cell I's run button
#   nb-output-tab I J         as cell I's output J's Open in Tab
#   print-nb-exec             the kernels started as the user (nbexec_dump)
#   print-nb-md I             cell I's rendered Markdown (nb_dump_md: where it was drawn, md_dump)
.include "rhun.inc"

.section .rodata
.p2align 3
.globl nb_ctl
nb_ctl:
    .quad .Lc_print_notebook, c_print_notebook, .Lc_print_nb_output, c_print_nb_output
    .quad .Lc_nb_mode, c_nb_mode, .Lc_nb_select, c_nb_select, .Lc_nb_run, c_nb_run
    .quad .Lc_nb_output_tab, c_nb_output_tab, .Lc_print_nb_exec, c_print_nb_exec
    .quad .Lc_print_nb_md, c_print_nb_md
    .quad 0, 0
.Lc_print_notebook: .asciz "print-notebook"
.Lc_print_nb_output: .asciz "print-nb-output"
.Lc_nb_mode: .asciz "nb-mode"
.Lc_nb_select: .asciz "nb-select"
.Lc_nb_run: .asciz "nb-run"
.Lc_nb_output_tab: .asciz "nb-output-tab"
.Lc_print_nb_exec: .asciz "print-nb-exec"
.Lc_print_nb_md: .asciz "print-nb-md"
.text

# each fn(out sb, rest, rest len) -> rax 0

# nc_int() -> rax the next number in (r13 rest, r14 len), moving past it
nc_int:
    mov rdi, r13
    mov rsi, r14
    call next_word
    add r13, rcx
    sub r14, rcx
    mov rdi, rax
    mov rsi, rdx
    jmp parse_u64

c_print_notebook:
    PROLOGUE
    call nb_dump
    xor eax, eax
    EPILOGUE

c_print_nb_output:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call nc_int
    mov rbx, rax
    call nc_int
    mov rdx, rax
    mov rsi, rbx
    mov rdi, r12
    call nb_dump_output
    xor eax, eax
    EPILOGUE

c_nb_mode:
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call nb_ctl_mode
    xor eax, eax
    EPILOGUE

c_nb_select:
    PROLOGUE
    mov r13, rsi
    mov r14, rdx
    call nc_int
    mov rdi, rax
    call nb_ctl_select
    xor eax, eax
    EPILOGUE

c_nb_run:
    PROLOGUE
    mov r13, rsi
    mov r14, rdx
    call nc_int
    mov rdi, rax
    call nb_ctl_run
    xor eax, eax
    EPILOGUE

c_nb_output_tab:
    PROLOGUE
    mov r13, rsi
    mov r14, rdx
    call nc_int
    mov rbx, rax
    call nc_int
    mov rsi, rax
    mov rdi, rbx
    call nb_ctl_output_tab
    xor eax, eax
    EPILOGUE

c_print_nb_exec:
    PROLOGUE
    call nbexec_dump
    xor eax, eax
    EPILOGUE

c_print_nb_md:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call nc_int
    mov rsi, rax
    mov rdi, r12
    call nb_dump_md
    xor eax, eax
    EPILOGUE
