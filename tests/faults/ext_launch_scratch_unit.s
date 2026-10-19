.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.globl lsu_fail_at,lsu_allocations,lsu_clock,lsu_dispose_mode,lsu_dispose_calls
.globl lsu_drop_mode,lsu_drop_calls,lsu_close_mode,lsu_close_calls,lsu_new_calls,lsu_advance
.globl lsu_fail_unmap,lsu_unmap_calls
.p2align 3
lsu_fail_at: .quad 0
lsu_allocations: .quad 0
lsu_clock: .quad 0
lsu_dispose_mode: .quad 0
lsu_dispose_calls: .quad 0
lsu_drop_mode: .quad 0
lsu_drop_calls: .quad 0
lsu_close_mode: .quad 0
lsu_close_calls: .quad 0
lsu_new_calls: .quad 0
lsu_advance: .quad 0
lsu_phase: .quad 0
lsu_fail_unmap: .quad 0
lsu_unmap_calls: .quad 0
lsu_map: .quad 0
lsu_map_charge: .quad 0
lsu_map_live: .quad 0
lsu_large_input: .zero 70000
lsu_baseline: .quad 0
lsu_borrowed_ptr: .quad 0
lsu_last_owner: .quad 0
lsu_argv: .zero VEC_SIZE
lsu_env: .zero VEC_SIZE
lsu_status: .zero 32
.text
lsu_bad:
    mov rdi, [rip + lsu_phase]
    add rdi, 100
    call sys_exit
    ud2
FN lsu_native_unmap
    inc qword ptr [rip + lsu_unmap_calls]
    cmp qword ptr [rip + lsu_fail_unmap], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN lsu_time
    mov rax, [rip + lsu_clock]
    ret
FN lsu_dispose
    inc qword ptr [rip + lsu_dispose_calls]
    cmp qword ptr [rip + lsu_dispose_mode], 0
    je prep_owned_dispose
    mov rax, -5
    xor edx, edx
    ret
FN lsu_drop
    inc qword ptr [rip + lsu_drop_calls]
    cmp qword ptr [rip + lsu_drop_mode], 0
    je ext_prepare_owner_release_deferred
    mov rax, -6
    xor edx, edx
    ret
FN lsu_close
    inc qword ptr [rip + lsu_close_calls]
    cmp rdi, 1001
    jne 1f
    inc qword ptr [rip + lsu_new_calls]
1:  mov rax, [rip + lsu_advance]
    add [rip + lsu_clock], rax
    mov rdx, [rip + lsu_close_mode]
    test rdx, rdx
    jz 2f
    cmp rdx, 2
    je 3f
    xor edx, edx
3:  mov rax, -5
    ret
2:  xor eax, eax
    mov edx, 1
    ret
lsu_begin:
    lea rdi, [rip + lsu_argv]
    lea rsi, [rip + lsu_env]
    jmp ext_launch_scratch_begin
lsu_pump:
    mov rdi, [rip + lsu_clock]
    jmp ext_prepare_pump_tick
lsu_timeout:
    mov rdi, [rip + lsu_clock]
    jmp ext_prepare_pump_timeout
lsu_drain:
    PROLOGUE
    mov r12d, 256
1:  call lsu_pump
    lea rdi, [rip + lsu_status]
    call ext_prepare_retire_status
    mov rax, [rip + lsu_status + 8]
    or rax, [rip + lsu_status + 16]
    jz 2f
    dec r12
    jnz 1b
    jmp lsu_bad
2:  call ext_prepare_retire_charge
    test rax, rax
    jnz lsu_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + lsu_baseline]
    jne lsu_bad
    EPILOGUE
lsu_make_block:
    PROLOGUE
    mov rbx, rdi
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz lsu_bad
    mov [rip + lsu_last_owner], rax
    mov [rax + EO_lease], rbx
    mov rdi, rax
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne lsu_bad
    EPILOGUE
lsu_retire:
    mov edi, 64
    lea rsi, [rip + lsu_status]
    jmp ext_prepare_retire_step
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + lsu_baseline], rax
    mov qword ptr [rip + lsu_clock], 100
    # Actual allocator failure at EO, PO, first vector, string and second vector.
    mov r14d, 1
.Lunit_alloc:
    mov [rip + lsu_phase], r14
    mov [rip + lsu_fail_at], r14
    mov qword ptr [rip + lsu_allocations], 0
    call lsu_begin
    cmp rdx, 1
    jne lsu_bad
    test rax, rax
    js .Lunit_failed
    lea rdi, [rip + lsu_argv]
    mov esi, 8
    call ext_launch_scratch_push
    test rax, rax
    jz .Lunit_failed
    lea rdi, [rip + lsu_borrowed]
    mov esi, 8
    call ext_launch_scratch_dup
    test rax, rax
    jz .Lunit_failed
    lea rdi, [rip + lsu_env]
    mov esi, 8
    call ext_launch_scratch_push
    test rax, rax
    jnz lsu_bad
.Lunit_failed:
    mov rax, [rip + lsu_allocations]
    cmp rax, r14
    jne lsu_bad
    call ext_launch_scratch_error
    cmp rax, -12
    jne lsu_bad
    call lsu_begin
    cmp rax, -16
    jne lsu_bad
    test rdx, rdx
    jnz lsu_bad
    call ext_launch_scratch_end
    cmp rdx, 1
    jne lsu_bad
    mov qword ptr [rip + lsu_fail_at], 0
    call lsu_drain
    inc r14
    cmp r14, 5
    jbe .Lunit_alloc
    # Successful ownership, borrowed bytes and immediate descriptor withdrawal.
    mov qword ptr [rip + lsu_phase], 6
    lea rdi, [rip + lsu_borrowed]
    mov esi, 8
    call mem_dup
    mov [rip + lsu_borrowed_ptr], rax
    inc qword ptr [rip + lsu_baseline]
    call lsu_begin
    test rax, rax
    jnz lsu_bad
    lea rdi, [rip + lsu_argv]
    mov esi, 8
    call ext_launch_scratch_push
    test rax, rax
    jz lsu_bad
    mov rcx, [rip + lsu_borrowed_ptr]
    mov [rax], rcx
    call ext_launch_scratch_end
    cmp rdx, 1
    jne lsu_bad
    mov rax, [rip + lsu_argv]
    or rax, [rip + lsu_argv + 8]
    or rax, [rip + lsu_argv + 16]
    jnz lsu_bad
    call lsu_drain
    mov rdi, [rip + lsu_borrowed_ptr]
    lea rsi, [rip + lsu_expected]
    call strcmp_eq
    test eax, eax
    jz lsu_bad
    mov rdi, [rip + lsu_borrowed_ptr]
    call mem_free
    dec qword ptr [rip + lsu_baseline]
    # Checked PO transfer refusal and deadline-only retry. end never retries inactive refs.
    mov qword ptr [rip + lsu_phase], 7
    call lsu_begin
    test rax, rax
    jnz lsu_bad
    mov qword ptr [rip + lsu_dispose_mode], 1
    mov qword ptr [rip + lsu_dispose_calls], 0
    call ext_launch_scratch_end
    cmp rax, -5
    jne lsu_bad
    test rdx, rdx
    jnz lsu_bad
    call lsu_begin
    cmp rax, -16
    jne lsu_bad
    test rdx, rdx
    jnz lsu_bad
    mov qword ptr [rip + lsu_clock], 115
    call lsu_pump
    call ext_launch_scratch_end
    cmp qword ptr [rip + lsu_dispose_calls], 1
    jne lsu_bad
    call lsu_timeout
    cmp rax, 1
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 116
    call ext_launch_scratch_end
    cmp qword ptr [rip + lsu_dispose_calls], 1
    jne lsu_bad
    call lsu_pump
    cmp qword ptr [rip + lsu_dispose_calls], 2
    jne lsu_bad
    mov qword ptr [rip + lsu_dispose_mode], 0
    mov qword ptr [rip + lsu_clock], 147
    call lsu_pump
    cmp qword ptr [rip + lsu_dispose_calls], 2
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 148
    call lsu_drain
    cmp qword ptr [rip + lsu_dispose_calls], 3
    jne lsu_bad
    # Initial EO drop has its own retained identity after PO has been consumed.
    mov qword ptr [rip + lsu_phase], 8
    call lsu_begin
    test rax, rax
    jnz lsu_bad
    mov qword ptr [rip + lsu_drop_mode], 1
    mov qword ptr [rip + lsu_drop_calls], 0
    call ext_launch_scratch_end
    cmp rax, -6
    jne lsu_bad
    test rdx, rdx
    jnz lsu_bad
    cmp qword ptr [rip + lsu_drop_calls], 1
    jne lsu_bad
    mov qword ptr [rip + lsu_drop_mode], 0
    mov qword ptr [rip + lsu_clock], 163
    call lsu_pump
    cmp qword ptr [rip + lsu_drop_calls], 1
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 164
    call lsu_drain
    cmp qword ptr [rip + lsu_drop_calls], 2
    jne lsu_bad
    # Sealed 33-record cohort. A newly failed tail must not inherit its deadline.
    mov qword ptr [rip + lsu_phase], 9
    mov qword ptr [rip + lsu_clock], 200
    mov qword ptr [rip + lsu_close_mode], 1
    mov qword ptr [rip + lsu_close_calls], 0
    mov r14d, 33
1:  mov edi, 123
    call lsu_make_block
    dec r14
    jnz 1b
    call lsu_retire
    cmp qword ptr [rip + lsu_status + 16], 33
    jne lsu_bad
    call lsu_pump
    call lsu_timeout
    cmp rax, 16
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 215
    mov edi, 1001
    call lsu_make_block
    call lsu_retire
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 34
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 216
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 50
    jne lsu_bad
    call lsu_timeout
    cmp rax, 1
    jne lsu_bad
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 66
    jne lsu_bad
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 67
    jne lsu_bad
    cmp qword ptr [rip + lsu_new_calls], 1
    jne lsu_bad
    call lsu_timeout
    cmp rax, 32
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 247
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 67
    jne lsu_bad
    mov qword ptr [rip + lsu_close_mode], 0
    mov qword ptr [rip + lsu_clock], 248
    call lsu_drain
    cmp qword ptr [rip + lsu_new_calls], 2
    jne lsu_bad
    # A slow native failure advances time. Its cohort starts after that failure.
    mov qword ptr [rip + lsu_phase], 10
    mov qword ptr [rip + lsu_clock], 300
    mov qword ptr [rip + lsu_advance], 100
    mov qword ptr [rip + lsu_close_mode], 1
    mov edi, 123
    call lsu_make_block
    call lsu_pump
    cmp qword ptr [rip + lsu_clock], 400
    jne lsu_bad
    call lsu_timeout
    cmp rax, 16
    jne lsu_bad
    mov qword ptr [rip + lsu_advance], 0
    mov qword ptr [rip + lsu_close_mode], 0
    mov qword ptr [rip + lsu_clock], 416
    call lsu_drain
    # Actual large allocation remains mapped and charged through native unmap refusal.
    mov qword ptr [rip + lsu_phase], 12
    mov qword ptr [rip + lsu_clock], 450
    call lsu_begin
    test rax, rax
    jnz lsu_bad
    lea rdi, [rip + lsu_large_input]
    mov esi, 70000
    call ext_launch_scratch_dup
    test rax, rax
    jz lsu_bad
    mov [rip + lsu_map], rax
    mov byte ptr [rax + 69999], 85
    call ext_launch_scratch_end
    cmp rdx, 1
    jne lsu_bad
    call ext_prepare_retire_charge
    mov [rip + lsu_map_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + lsu_map_live], rax
    mov qword ptr [rip + lsu_fail_unmap], 1
    call lsu_pump
    cmp qword ptr [rip + lsu_unmap_calls], 1
    jne lsu_bad
    call ext_prepare_retire_charge
    cmp rax, [rip + lsu_map_charge]
    jne lsu_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + lsu_map_live]
    jne lsu_bad
    mov rax, [rip + lsu_map]
    cmp byte ptr [rax + 69999], 85
    jne lsu_bad
    call lsu_timeout
    cmp rax, 16
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 465
    call lsu_pump
    cmp qword ptr [rip + lsu_unmap_calls], 1
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 466
    call lsu_pump
    cmp qword ptr [rip + lsu_unmap_calls], 2
    jne lsu_bad
    call lsu_timeout
    cmp rax, 32
    jne lsu_bad
    mov qword ptr [rip + lsu_fail_unmap], 0
    mov qword ptr [rip + lsu_clock], 497
    call lsu_pump
    cmp qword ptr [rip + lsu_unmap_calls], 2
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 498
    call lsu_drain
    cmp qword ptr [rip + lsu_unmap_calls], 3
    jne lsu_bad
    # Unknown-only queue rotates at deadlines and never calls its native close again.
    mov qword ptr [rip + lsu_phase], 11
    mov qword ptr [rip + lsu_clock], 500
    mov qword ptr [rip + lsu_close_mode], 2
    mov qword ptr [rip + lsu_close_calls], 0
    mov edi, 123
    call lsu_make_block
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 1
    jne lsu_bad
    call lsu_timeout
    cmp rax, 16
    jne lsu_bad
    mov qword ptr [rip + lsu_clock], 516
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 1
    jne lsu_bad
    call lsu_timeout
    cmp rax, 32
    jne lsu_bad
    lea r14, [rip + lsu_backoff]
    mov r15d, 6
1:  mov rax, [r14]
    mov [rip + lsu_clock], rax
    call lsu_pump
    cmp qword ptr [rip + lsu_close_calls], 1
    jne lsu_bad
    call lsu_timeout
    cmp rax, [r14 + 8]
    jne lsu_bad
    add r14, 16
    dec r15
    jnz 1b
    lea rdi, [rip + lsu_status]
    call ext_prepare_retire_status
    cmp qword ptr [rip + lsu_status + 8], 0
    jne lsu_bad
    cmp qword ptr [rip + lsu_status + 16], 1
    jne lsu_bad
    call ext_prepare_retire_charge
    cmp rax, 128
    jne lsu_bad
    mov rax, [rip + lsu_last_owner]
    cmp qword ptr [rax + EO_lease], 123
    jne lsu_bad
    mov rax, [rip + g_mem_live]
    dec rax
    cmp rax, [rip + lsu_baseline]
    jne lsu_bad
    xor eax, eax
    EPILOGUE
.section .rodata
lsu_borrowed: .asciz "borrowed"
lsu_expected: .asciz "borrowed"

.p2align 3
lsu_backoff: .quad 548,64,612,128,740,256,996,512,1508,1000,2508,1000
