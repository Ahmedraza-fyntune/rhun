# Faithful opaque capsule model. Every API and payload credit is charged at the boundary.
.include "app/extstorejob.inc"
.bss
.p2align 3
tcjm_capsule: .zero 16
tcjm_wire: .zero TC_OUTPUT_CAP + 1
tcjm_auth: .zero 8
tcjm_exit: .zero 8
tcjm_closed: .zero 8
tcjm_pending: .zero 8
tcjm_connect: .zero 8
tcjm_remaining: .zero 8
tcjm_rx: .zero 8
tcjm_limit: .zero 8
tcjm_killed: .zero 8
tcjm_polls: .zero 8
tcjm_after_kill: .zero 8
tcjm_after_eof: .zero 8
tcjm_free_count: .zero 8
tcjm_free_now: .zero 8
tcjm_free_delay: .zero 8
tcjm_freed: .zero 8
tcjm_poison: .zero 8
tcjm_begins: .zero 8
tcjm_instep: .zero 8
tcjm_now: .zero 8
tcjm_budget: .zero 8
.globl tcjm_bytes, tcjm_control
tcjm_bytes: .zero 8
tcjm_calls: .zero 8
tcjm_step_polls: .zero 8
tcjm_step_free: .zero 8
tcjm_control: .zero 8
.section .rodata
tcjm_raw: .ascii "kind=light\n"
.text
tcjm_api:
    cmp qword ptr [rip + tcjm_poison], 0
    jne tcjt_fail
    add [rip + tcjm_calls], rax
    ret
FN theme_capture_native_start
    PROLOGUE
    mov qword ptr [rip + tcjm_auth], ESJ_OWNED
    mov qword ptr [rip + tcjm_exit], -1
.if TCJM_MODE == 3 || TCJM_MODE == 14
    mov qword ptr [rip + tcjm_auth], ESJ_NONE
.endif
.if TCJM_MODE == 2
    mov qword ptr [rip + tcjm_auth], ESJ_LOST
.endif
.if TCJM_MODE == 1
    mov qword ptr [rip + tcjm_connect], 3
.endif
    mov qword ptr [rip + tcjm_limit], 667
.if TCJM_MODE == 10
    mov qword ptr [rip + tcjm_limit], TC_OUTPUT_CAP + 1
.endif
    lea rbx, [rip + tcjm_wire]
    mov rax, 0x0031534552544852
    mov [rbx], rax
    mov dword ptr [rbx + 8], 1
    mov dword ptr [rbx + 12], 256
    mov qword ptr [rbx + 16], 667
    mov dword ptr [rbx + 24], 1
    lea rdi, [rbx + 32]
    lea rsi, [rip + tcjt_request + 32]
    mov edx, 64
    call memcpy
    mov dword ptr [rbx + 100], T_COUNT
    mov qword ptr [rbx + 280], 11
    mov dword ptr [rbx + 320], T_COUNT
    lea rdi, [rbx + 656]
    lea rsi, [rip + tcjm_raw]
    mov edx, 11
    call memcpy
    lea rdi, [rip + tcjm_raw]
    mov esi, 11
    lea rdx, [rbx + 288]
    call sha256_hash
    test eax, eax
    jz tcjt_fail
.if TCJM_MODE == 14
    xor eax, eax
    mov rdx, -13
    mov rcx, -5
.else
    lea rax, [rip + tcjm_capsule]
    xor edx, edx
    xor ecx, ecx
.if TCJM_MODE == 3
    mov rdx, -13
.endif
.endif
    EPILOGUE
FN ext_settings_native_write_begin
    mov eax, 1
    call tcjm_api
    cmp qword ptr [rip + tcjm_closed], 0
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_pending], 0
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_connect], 0
    jne 1f
    mov [rip + tcjm_pending], rdx
    add [rip + tcjm_bytes], rdx
    inc qword ptr [rip + tcjm_begins]
    mov eax, 1
    ret
1:  xor eax, eax
    ret
FN ext_settings_native_write_poll
    mov eax, 1
    call tcjm_api
    xor edx, edx
    mov ecx, 1  # submitted HISTORY, deliberately remains1 after settlement
    cmp qword ptr [rip + tcjm_connect], 0
    je 1f
    dec qword ptr [rip + tcjm_connect]
    xor eax, eax
    ret
1:
.if TCJM_MODE == 6
    cmp qword ptr [rip + tcjm_pending], 0
    je 2f
    cmp qword ptr [rip + tcjm_remaining], 0
    jne 3f
    mov qword ptr [rip + tcjm_remaining], 10
    mov qword ptr [rip + tcjm_pending], 0
3:  dec qword ptr [rip + tcjm_remaining]
    mov rax, -5
    ret
2:  cmp qword ptr [rip + tcjm_remaining], 0
    je 4f
    dec qword ptr [rip + tcjm_remaining]
    mov rax, -5
    ret
4:
.endif
.if TCJM_MODE == 13
    cmp qword ptr [rip + tcjm_remaining], 0
    je 5f
    dec qword ptr [rip + tcjm_remaining]
    xor eax, eax
    ret
5:
.endif
    cmp qword ptr [rip + tcjm_closed], 0
    jne 8f
    mov rdx, [rip + tcjm_pending]
    cmp rdx, rsi
    cmova rdx, rsi
    sub [rip + tcjm_pending], rdx
    add [rip + tcjm_bytes], rdx
    cmp qword ptr [rip + tcjm_pending], 0
    jne 9f
8:  mov eax, 1
    ret
9:  xor eax, eax
    ret
FN ext_settings_native_close_input
    mov eax, 1
    call tcjm_api
    cmp qword ptr [rip + tcjm_closed], 0
    jne tcjt_fail
    mov qword ptr [rip + tcjm_closed], 1
.if TCJM_MODE == 13
    mov qword ptr [rip + tcjm_remaining], 10
    mov rax, -115
    ret
.else
.if TCJM_MODE == 4
    mov rax, -5
    ret
.else
    xor eax, eax
    ret
.endif
.endif
FN ext_settings_native_kill
    mov eax, 1
    call tcjm_api
    cmp qword ptr [rip + tcjm_auth], ESJ_OWNED
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_killed], 0
    jne tcjt_fail
    mov qword ptr [rip + tcjm_killed], 1
    xor eax, eax
    ret
FN ext_settings_native_poll
    mov eax, 1
    call tcjm_api
    inc qword ptr [rip + tcjm_step_polls]
    inc qword ptr [rip + tcjm_polls]
    cmp qword ptr [rip + tcjm_auth], ESJ_OWNED
    jne 8f
    cmp qword ptr [rip + tcjm_killed], 0
    je 2f
    inc qword ptr [rip + tcjm_after_kill]
    cmp qword ptr [rip + tcjm_after_kill], 3
    jb 8f
    mov qword ptr [rip + tcjm_auth], ESJ_REAPED
    mov qword ptr [rip + tcjm_exit], 137
    jmp 8f
2:  cmp qword ptr [rip + tcjm_closed], 0
    je 8f
    mov rax, [rip + tcjm_rx]
    cmp rax, [rip + tcjm_limit]
    jb 8f
.if TCJM_MODE == 12
    inc qword ptr [rip + tcjm_after_eof]
    cmp qword ptr [rip + tcjm_after_eof], 10
    jb 8f
.endif
    mov qword ptr [rip + tcjm_auth], ESJ_REAPED
    mov qword ptr [rip + tcjm_exit], 0
8:  mov rax, [rip + tcjm_auth]
    mov rdx, [rip + tcjm_exit]
    xor ecx, ecx
.if TCJM_MODE == 7
    cmp qword ptr [rip + tcjm_polls], 1
    jne 9f
    mov rcx, -5
9:
.endif
    ret
FN ext_settings_native_read
    PROLOGUE
    mov eax, 2
    call tcjm_api
    mov rbx, rdx
    mov r12, rcx
    cmp rsi, 0
    je 2f
.if TCJM_MODE == 11
    cmp rsi, 1
    jne 1f
    cmp qword ptr [rip + tcjm_killed], 0
    jne 1f
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    call memset
    add [rip + tcjm_bytes], r12
    mov rax, r12
    EPILOGUE
.endif
1:  xor eax, eax
    EPILOGUE
2:  cmp qword ptr [rip + tcjm_auth], ESJ_NONE
    je 1b
    cmp qword ptr [rip + tcjm_auth], ESJ_LOST
    je 1b
    cmp qword ptr [rip + tcjm_killed], 0
    jne 1b
    cmp qword ptr [rip + tcjm_closed], 0
    je 7f
    mov r13, [rip + tcjm_limit]
    sub r13, [rip + tcjm_rx]
    jz 1b
    cmp r13, r12
    cmova r13, r12
    mov rdi, rbx
    lea rsi, [rip + tcjm_wire]
    add rsi, [rip + tcjm_rx]
    mov rdx, r13
    call memcpy
    add [rip + tcjm_rx], r13
    add [rip + tcjm_bytes], r13
    mov rax, r13
    EPILOGUE
7:  mov rax, -11
    EPILOGUE
FN ext_settings_native_free
    inc qword ptr [rip + tcjm_calls]
    inc qword ptr [rip + tcjm_step_free]
    inc qword ptr [rip + tcjm_free_count]
    cmp qword ptr [rip + tcjm_auth], ESJ_OWNED
    je tcjt_fail
    cmp qword ptr [rip + tcjm_remaining], 0
    je 1f
    mov rax, -16
    xor edx, edx
    xor ecx, ecx
    ret
1:
.if TCJM_MODE == 5
    cmp qword ptr [rip + tcjm_free_count], 1
    je 3f
    mov rax, [rip + tcjm_free_now]
    add rax, [rip + tcjm_free_delay]
    cmp [rip + tcjm_now], rax
    jb tcjt_fail
3:  cmp qword ptr [rip + tcjm_free_count], 4
    jae 5f
    mov qword ptr [rip + tcjm_poison], 1
    mov rax, [rip + tcjm_now]
    mov [rip + tcjm_free_now], rax
    mov rax, [rip + tcjm_free_delay]
    test rax, rax
    jnz 4f
    mov eax, 8
4:  add rax, rax
    mov [rip + tcjm_free_delay], rax
    mov rax, -5
    xor edx, edx
    mov ecx, 1
    ret
5:
.endif
    mov qword ptr [rip + tcjm_freed], 1
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    ret
FN tc_result_decode_step
    cmp qword ptr [rip + tcjm_auth], ESJ_REAPED
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_freed], 1
    jne tcjt_fail
    PROLOGUE 32
    mov rax, [rip + tcjm_bytes]
    mov [rsp], rax
    call tcjm_real_decode
    mov r8, [rip + tcjm_bytes]
    sub r8, [rsp]
    cmp r8, rdx
    jne tcjt_fail
    EPILOGUE
FN theme_capture_job_step
    PROLOGUE 32
    mov [rip + tcjm_now], rsi
    mov [rip + tcjm_budget], rdx
    mov qword ptr [rip + tcjm_bytes], 0
    mov qword ptr [rip + tcjm_control], 0
    mov qword ptr [rip + tcjm_calls], 0
    mov qword ptr [rip + tcjm_step_polls], 0
    mov qword ptr [rip + tcjm_step_free], 0
    call tcjm_real_step
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov rax, [rip + tcjm_bytes]
    cmp rax, [rip + tcjm_budget]
    ja tcjt_fail
    cmp qword ptr [rip + tcjm_control], 256
    ja tcjt_fail
    cmp qword ptr [rip + tcjm_calls], 16
    ja tcjt_fail
    cmp qword ptr [rip + tcjm_step_polls], 1
    ja tcjt_fail
    cmp qword ptr [rip + tcjm_step_free], 0
    je 1f
    cmp qword ptr [rip + tcjm_calls], 1
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_bytes], 0
    jne tcjt_fail
    cmp qword ptr [rip + tcjm_step_polls], 0
    jne tcjt_fail
1:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE
