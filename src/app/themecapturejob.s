# Caller-owned theme capture job. Registry is a nonowning shutdown/uniqueness index.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturejob.inc"
.include "app/extstorejob.inc"
.bss
.globl g_theme_capture_job
g_theme_capture_job: .zero 8
.text
# Internal sticky diagnostics. No destructor, callback or source IO.
FN tc_job_error
    test rsi, rsi
    jns 2f
    cmp qword ptr [rdi + TCJ_primary], 0
    jne 1f
    mov [rdi + TCJ_primary], rsi
1:  mov qword ptr [rdi + TCJ_closing], 1
    mov qword ptr [rdi + TCJ_state], TCJS_CLOSING
    cmp qword ptr [rdi + TCJ_native], 0
    jne 2f
    mov qword ptr [rdi + TCJ_state], TCJS_FAILED
2:  ret
FN tc_job_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + TCJ_cleanup], 0
    jne 1f
    mov [rdi + TCJ_cleanup], rsi
1:  ret

# start(ownedSealedRequest,now,currentContext)->job*/primary/cleanup.
# NULL leaves request with caller. Every nonNULL owner consumes it, including failures.
FN theme_capture_job_start
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .Ltcjs_bad
    test r12, r12
    js .Ltcjs_bad
    test r13, r13
    jle .Ltcjs_bad
    cmp qword ptr [rbx + TCQ_state], TCQ_SEALED
    jne .Ltcjs_bad
    cmp qword ptr [rbx + TCQ_cleanup], 0
    jne .Ltcjs_bad
    cmp qword ptr [rbx + TCQ_length], TC_HEADER_SIZE
    jb .Ltcjs_bad
    cmp qword ptr [rbx + TCQ_length], TC_INPUT_CAP
    ja .Ltcjs_bad
    mov rax, [rbx + TCQ_wire]
    test rax, rax
    jz .Ltcjs_bad
    cmp [rax + 40], r13
    jne .Ltcjs_stale
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne .Ltcjs_busy
    cmp qword ptr [rip + g_theme_capture_results], TC_SOURCE_MAX
    jae .Ltcjs_capacity
    lea r14, [r12 + 10000]
    test r14, r14
    js .Ltcjs_overflow
    cmp r14, r12
    jb .Ltcjs_overflow
    mov edi, TCJ_SIZE
    call tc_alloc_try
    test rax, rax
    jz .Ltcjs_oom
    mov r15, rax
    mov [r15 + TCJ_request], rbx
    mov [r15 + TCJ_fallback_request], rbx
    mov qword ptr [rbx + TCQ_state], TCQ_OWNED
    mov [rip + g_theme_capture_job], r15
    inc qword ptr [rip + g_theme_capture_results]
    mov qword ptr [r15 + TCJ_result_reservation], 1
    mov qword ptr [r15 + TCJ_exit], -1
    mov [r15 + TCJ_context], r13
    mov [r15 + TCJ_deadline], r14
    mov [r15 + TCJ_now], r12
    call tc_result_alloc
    test rax, rax
    jz .Ltcjs_owned_oom
    mov [r15 + TCJ_result], rax
    mov [rax + TCS_request], rbx
    mov qword ptr [r15 + TCJ_fallback_request], 0
    mov qword ptr [rax + TCS_reservation], 1
    mov qword ptr [r15 + TCJ_result_reservation], 0
    mov edi, TC_OUTPUT_CAP
    call tc_alloc_try
    test rax, rax
    jz .Ltcjs_owned_oom
    mov rcx, [r15 + TCJ_result]
    mov [rcx + TCS_wire], rax
    mov edi, TC_NATIVE_RESERVE
    call tc_charge_reserve
    test rax, rax
    js .Ltcjs_owned_error
    mov qword ptr [r15 + TCJ_reservation], TC_NATIVE_RESERVE
    mov rax, [rbx + TCQ_wire]
    mov rcx, [rax + 32]
    mov [rsp], rcx
    mov rcx, [rax + 40]
    mov [rsp + 8], rcx
    lea rdi, [rsp + 16]
    lea rsi, [rax + 48]
    mov edx, 16
    call memcpy
    mov rdi, rsp
    call theme_capture_native_start
    mov [r15 + TCJ_native], rax
    mov [r15 + TCJ_primary], rdx
    mov [r15 + TCJ_cleanup], rcx
    test rax, rax
    jz .Ltcjs_no_native
    or rdx, rcx
    jz .Ltcjs_return_owned
    mov qword ptr [r15 + TCJ_closing], 1
    mov qword ptr [r15 + TCJ_state], TCJS_CLOSING
    jmp .Ltcjs_return_owned
.Ltcjs_no_native:
    mov edi, TC_NATIVE_RESERVE
    call tc_charge_release
    test rax, rax
    js 1f
    mov qword ptr [r15 + TCJ_reservation], 0
    jmp 2f
1:  mov rdi, r15
    mov rsi, rax
    call tc_job_cleanup
2:  mov rax, [r15 + TCJ_primary]
    or rax, [r15 + TCJ_cleanup]
    jnz 3f
    mov qword ptr [r15 + TCJ_primary], -5
3:  mov qword ptr [r15 + TCJ_native_retired], 1
    mov qword ptr [r15 + TCJ_closing], 1
    mov qword ptr [r15 + TCJ_state], TCJS_FAILED
    jmp .Ltcjs_return_owned
.Ltcjs_owned_oom:
    mov rax, -12
.Ltcjs_owned_error:
    mov [r15 + TCJ_primary], rax
    mov qword ptr [r15 + TCJ_closing], 1
    mov qword ptr [r15 + TCJ_native_retired], 1
    mov qword ptr [r15 + TCJ_state], TCJS_FAILED
.Ltcjs_return_owned:
    mov rax, r15
    mov rdx, [r15 + TCJ_primary]
    mov rcx, [r15 + TCJ_cleanup]
    EPILOGUE
.Ltcjs_bad:
    mov rdx, -22
    jmp .Ltcjs_null
.Ltcjs_stale:
    mov rdx, -116
    jmp .Ltcjs_null
.Ltcjs_busy:
    mov rdx, -16
    jmp .Ltcjs_null
.Ltcjs_capacity:
    mov rdx, -7
    jmp .Ltcjs_null
.Ltcjs_overflow:
    mov rdx, -75
    jmp .Ltcjs_null
.Ltcjs_oom:
    mov rdx, -12
.Ltcjs_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

FN theme_capture_job_cancel
    test rdi, rdi
    jz .Ltcj_bad
    PROLOGUE
    cmp qword ptr [rdi + TCJ_state], TCJS_TAKEN
    je 1f
    cmp qword ptr [rdi + TCJ_state], TCJS_FAILED
    je 1f
    mov rsi, -125
    call tc_job_error
1:  xor eax, eax
    EPILOGUE
FN theme_capture_job_status
    test rdi, rdi
    jz .Ltcj_bad
    test rsi, rsi
    jz .Ltcj_bad
    mov rax, [rdi + TCJ_state]
    mov [rsi], rax
    mov rax, [rdi + TCJ_primary]
    mov [rsi + 8], rax
    mov rax, [rdi + TCJ_cleanup]
    mov [rsi + 16], rax
    mov rax, [rdi + TCJ_observation]
    mov [rsi + 24], rax
    mov rax, [rdi + TCJ_authority]
    mov [rsi + 32], rax
    mov rax, [rdi + TCJ_exit]
    mov [rsi + 40], rax
    xor eax, eax
    ret
FN theme_capture_job_take
    test rdi, rdi
    jz .Ltcjt_bad
    cmp [rdi + TCJ_context], rsi
    jne .Ltcjt_stale
    cmp qword ptr [rdi + TCJ_state], TCJS_READY
    jne .Ltcjt_unready
    cmp qword ptr [rdi + TCJ_native], 0
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_native_retired], 1
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_authority], ESJ_REAPED
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_exit], 0
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_eof], 7
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_input_closed], 1
    jne .Ltcjt_busy
    cmp qword ptr [rdi + TCJ_tx_pending], 0
    jne .Ltcjt_busy
    mov rdx, [rdi + TCJ_primary]
    mov rcx, [rdi + TCJ_cleanup]
    mov rax, rdx
    or rax, rcx
    jnz .Ltcjt_failed
    mov rax, [rdi + TCJ_result]
    test rax, rax
    jz .Ltcjt_bad
    cmp qword ptr [rax + TCS_validated], 1
    jne .Ltcjt_bad
    cmp qword ptr [rax + TCS_state], TCS_LIVE
    jne .Ltcjt_bad
    mov qword ptr [rdi + TCJ_result], 0
    mov qword ptr [rdi + TCJ_request], 0
    mov qword ptr [rdi + TCJ_state], TCJS_TAKEN
    xor edx, edx
    xor ecx, ecx
    ret
.Ltcjt_stale:
    PROLOGUE
    mov rbx, rdi
    mov rsi, -116
    call tc_job_error
    mov rdx, [rbx + TCJ_primary]
    mov rcx, [rbx + TCJ_cleanup]
    xor eax, eax
    EPILOGUE
.Ltcjt_unready:
    mov rdx, [rdi + TCJ_primary]
    mov rcx, [rdi + TCJ_cleanup]
    mov rax, rdx
    or rax, rcx
    jnz .Ltcjt_failed
.Ltcjt_busy:
    xor eax, eax
    mov rdx, -16
    xor ecx, ecx
    ret
.Ltcjt_bad:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    ret
.Ltcjt_failed:
    xor eax, eax
    ret

FN theme_capture_job_free
    test rdi, rdi
    jz .Ltcjf_empty
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + TCJ_cleanup]
    cmp qword ptr [rbx + TCJ_state], TCJS_READY
    jb .Ltcjf_busy
    cmp qword ptr [rbx + TCJ_native], 0
    jne .Ltcjf_busy
    cmp qword ptr [rbx + TCJ_reservation], 0
    je 1f
    mov rdi, [rbx + TCJ_reservation]
    call tc_charge_release
    test rax, rax
    js .Ltcjf_note
    mov qword ptr [rbx + TCJ_reservation], 0
1:  mov rdi, [rbx + TCJ_result]
    test rdi, rdi
    jz 3f
    call theme_capture_result_release
    mov r13, rdx
    mov rdi, rbx
    mov rsi, rax
    call tc_job_cleanup
    test r13, r13
    jz .Ltcjf_retained
    mov qword ptr [rbx + TCJ_result], 0
    mov qword ptr [rbx + TCJ_request], 0
    jmp .Ltcjf_retained
3:  mov rdi, [rbx + TCJ_fallback_request]
    test rdi, rdi
    jz .Ltcjf_self
    call tc_request_dispose
    mov r13, rdx
    mov rdi, rbx
    mov rsi, rax
    call tc_job_cleanup
    test r13, r13
    jz .Ltcjf_retained
    mov qword ptr [rbx + TCJ_fallback_request], 0
    mov qword ptr [rbx + TCJ_request], 0
    jmp .Ltcjf_retained
.Ltcjf_self:
    mov r12, [rbx + TCJ_cleanup]
    mov r13, [rbx + TCJ_result_reservation]
    mov rdi, rbx
    call tc_free
    test rdx, rdx
    jz .Ltcjf_note
    test r13, r13
    jz 4f
    dec qword ptr [rip + g_theme_capture_results]
4:  cmp [rip + g_theme_capture_job], rbx
    jne 5f
    mov qword ptr [rip + g_theme_capture_job], 0
5:  test r12, r12
    jz 6f
    mov rax, r12
6:  mov edx, 1
    EPILOGUE
.Ltcjf_note:
    mov rdi, rbx
    mov rsi, rax
    call tc_job_cleanup
.Ltcjf_retained:
    mov rax, [rbx + TCJ_cleanup]
    xor edx, edx
    EPILOGUE
.Ltcjf_busy:
    mov rax, -16
    xor edx, edx
    EPILOGUE
.Ltcjf_empty:
    xor eax, eax
    mov edx, 1
    ret
.Ltcj_bad:
    mov rax, -22
    ret

# Pure scheduler hint. Terminal=-1; active=1ms; native cleanup-only uses its exact retry due.
# This is never collection/free proof. Caller still owns every nonconsumed job/resource.
FN theme_capture_job_timeout
    test rdi, rdi
    jz .Ltcjtmo_terminal
    test rsi, rsi
    js .Ltcjtmo_bad
    mov rax, [rdi + TCJ_state]
    cmp rax, TCJS_TAKEN
    ja .Ltcjtmo_bad
    cmp rax, TCJS_READY
    jae .Ltcjtmo_terminal
    cmp qword ptr [rdi + TCJ_cleanup_only], 1
    jne .Ltcjtmo_active
    mov rax, [rdi + TCJ_retry_due]
    sub rax, rsi
    jle .Ltcjtmo_due
    ret
.Ltcjtmo_active:
    mov eax, 1
    ret
.Ltcjtmo_due:
    xor eax, eax
    ret
.Ltcjtmo_terminal:
    mov rax, -1
    ret
.Ltcjtmo_bad:
    mov rax, -22
    ret
