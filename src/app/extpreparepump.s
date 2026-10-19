# Exclusive bounded FIFO cohorts keep newly failed cleanup off older retry deadlines.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
pump_remaining: .quad 0
pump_due: .quad 0
pump_halted: .quad 0
.data
.p2align 3
pump_delay: .quad 16
.text
FN ext_prepare_pump_tick
    PROLOGUE 32
    mov r12, rdi
    call ext_launch_scratch_tick
    cmp qword ptr [rip + pump_halted], 0
    jne .Lpp_retire
    cmp qword ptr [rip + pump_remaining], 0
    je .Lpp_retire
    cmp r12, [rip + pump_due]
    jb .Lpp_retire
    mov rdi, [rip + pump_remaining]
    mov eax, 16
    cmp rdi, rax
    cmova rdi, rax
    mov r13, rdi
    call ext_prepare_retire_retry_known
    test rdx, rdx
    jz .Lpp_invariant
    cmp rdx, r13
    ja .Lpp_invariant
    sub [rip + pump_remaining], rdx
    jnz .Lpp_retire
    mov rax, [rip + pump_delay]
    add rax, rax
    mov edx, 1000
    cmp rax, rdx
    cmova rax, rdx
    mov [rip + pump_delay], rax
    jmp .Lpp_retire
.Lpp_invariant:
    mov qword ptr [rip + pump_halted], 1
    cmp qword ptr [rip + prep_retire_first_diagnostic], 0
    jne .Lpp_retire
    mov qword ptr [rip + prep_retire_first_diagnostic], -5
.Lpp_retire:
    mov edi, 16
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp qword ptr [rip + pump_halted], 0
    jne .Lpp_done
    cmp qword ptr [rip + pump_remaining], 0
    jne .Lpp_done
    mov rax, [rsp + 16]
    test rax, rax
    jz .Lpp_empty
    mov [rip + pump_remaining], rax
    # The native cleanup pass may have taken time. Seal after its final failure.
    call time_ms
    add rax, [rip + pump_delay]
    mov [rip + pump_due], rax
    jmp .Lpp_done
.Lpp_empty:
    mov qword ptr [rip + pump_due], 0
    mov qword ptr [rip + pump_delay], 16
.Lpp_done:
    EPILOGUE

FN ext_prepare_pump_timeout
    PROLOGUE 32
    mov r12, rdi
    call ext_launch_scratch_timeout
    mov r13, rax
    mov rdi, rsp
    call ext_prepare_retire_status
    cmp qword ptr [rsp + 8], 0
    jne .Lpp_timeout_ready
    cmp qword ptr [rip + pump_halted], 0
    jne .Lpp_timeout_done
    cmp qword ptr [rsp + 16], 0
    je .Lpp_timeout_done
    cmp qword ptr [rip + pump_remaining], 0
    je .Lpp_timeout_ready
    mov rax, [rip + pump_due]
    sub rax, r12
    ja .Lpp_timeout_merge
.Lpp_timeout_ready:
    mov eax, 1
.Lpp_timeout_merge:
    cmp r13, -1
    je 1f
    cmp rax, r13
    jae .Lpp_timeout_done
1:  mov r13, rax
.Lpp_timeout_done:
    mov rax, r13
    EPILOGUE
