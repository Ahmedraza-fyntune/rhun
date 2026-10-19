# Repeated failed job construction must retain request ownership/capacity until consumed.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturejob.inc"
.ifndef TCJO_MODE
.equ TCJO_MODE, 2
.endif
.section .rodata
tcjo_path:
.ifdef WINDOWS
    .asciz "C:/not-opened.theme"
.else
    .asciz "/not-opened.theme"
.endif
.bss
.p2align 3
tcjo_armed: .zero 8
tcjo_allocs: .zero 8
tcjo_wire: .zero 8
tcjo_free_failed: .zero 8
.text
tcjo_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 112
    mov r15, [rip + g_mem_live]
    mov rdi, rsp
    xor esi, esi
    mov edx, 112
    call memset
    mov qword ptr [rsp + TCFG_job], 1
    mov qword ptr [rsp + TCFG_context], 2
    mov qword ptr [rsp + TCFG_nonce], 1
    mov qword ptr [rsp + 80], 12
.Ltcjo_again:
    mov qword ptr [rip + tcjo_armed], 0
    mov qword ptr [rip + tcjo_allocs], 0
    mov qword ptr [rip + tcjo_free_failed], 0
    mov rdi, rsp
    xor esi, esi
    call theme_capture_request_begin
    test rax, rax
    jz tcjo_fail
    mov r14, rax
    mov rdi, r14
    xor esi, esi
    lea rdx, [rip + tcjo_path]
    call theme_capture_request_add
    test rax, rax
    jnz tcjo_fail
    mov rdi, r14
    call theme_capture_request_seal
    test rax, rax
    jnz tcjo_fail
    mov rax, [r14 + TCQ_wire]
    mov [rip + tcjo_wire], rax
.if TCJO_MODE == 6
    mov qword ptr [rip + g_theme_capture_results], TC_SOURCE_MAX
.endif
.if TCJO_MODE == 7
    mov qword ptr [rip + g_theme_capture_job], 1
.endif
.if TCJO_MODE == 9
    mov rax, [rip + g_theme_capture_charge]
    mov [rip + g_theme_capture_limit], rax
.endif
    mov qword ptr [rip + tcjo_armed], 1
    mov rdi, r14
    mov esi, 1000
    mov edx, 2
.if TCJO_MODE == 8
    mov edx, 3
.endif
    call theme_capture_job_start
    mov r12, rax
    mov qword ptr [rip + tcjo_armed], 0
.if TCJO_MODE == 6
    cmp qword ptr [rip + g_theme_capture_results], TC_SOURCE_MAX
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne tcjo_fail
.endif
.if TCJO_MODE == 7
    cmp qword ptr [rip + g_theme_capture_job], 1
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcjo_fail
.endif
    mov qword ptr [rip + g_theme_capture_limit], TC_MEMORY_CAP
.if TCJO_MODE == 6
    cmp rdx, -7
.else
.if TCJO_MODE == 7
    cmp rdx, -16
.else
.if TCJO_MODE == 8
    cmp rdx, -116
.else
    cmp rdx, -12
.endif
.endif
.endif
    jne tcjo_fail
    test rcx, rcx
    jnz tcjo_fail
.if TCJO_MODE == 1 || TCJO_MODE >= 6
    mov qword ptr [rip + g_theme_capture_results], 0
    mov qword ptr [rip + g_theme_capture_job], 0
    test r12, r12
    jnz tcjo_fail
    cmp qword ptr [r14 + TCQ_state], TCQ_SEALED
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcjo_fail
.Ltcjo_request_free:
    mov rdi, r14
    call theme_capture_request_free
    test rdx, rdx
    jz .Ltcjo_request_free
.else
    test r12, r12
    jz tcjo_fail
    cmp [rip + g_theme_capture_job], r12
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_results], 1
    jne tcjo_fail
    cmp qword ptr [r14 + TCQ_state], TCQ_OWNED
    jne tcjo_fail
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 88], rax
    mov rdi, r12
    call theme_capture_job_free
    cmp rax, -5
    jne tcjo_fail
    test rdx, rdx
    jnz tcjo_fail
    cmp [rip + g_theme_capture_job], r12
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_results], 1
    jne tcjo_fail
    mov rax, [rip + g_theme_capture_charge]
    cmp rax, [rsp + 88]
    jne tcjo_fail
    mov rax, [r14 + TCQ_wire]
    cmp rax, [rip + tcjo_wire]
    jne tcjo_fail
.if TCJO_MODE == 2
    cmp [r12 + TCJ_fallback_request], r14
    jne tcjo_fail
    cmp qword ptr [r12 + TCJ_result_reservation], 1
    jne tcjo_fail
.endif
.Ltcjo_free:
    mov rdi, r12
    call theme_capture_job_free
    cmp rax, -5
    jne tcjo_fail
    test rdx, rdx
    jz .Ltcjo_free
.endif
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcjo_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcjo_fail
    cmp r15, [rip + g_mem_live]
    jne tcjo_fail
    dec qword ptr [rsp + 80]
    jnz .Ltcjo_again
    xor eax, eax
    EPILOGUE
FN tc_alloc_try
    cmp qword ptr [rip + tcjo_armed], 0
    je tcjo_real_alloc
    inc qword ptr [rip + tcjo_allocs]
.if TCJO_MODE <= 3
    cmp qword ptr [rip + tcjo_allocs], TCJO_MODE
    jne tcjo_real_alloc
    xor eax, eax
    ret
.else
    jmp tcjo_real_alloc
.endif
FN tc_charge_reserve
    cmp qword ptr [rip + tcjo_armed], 0
    je tcjo_real_reserve
    cmp rdi, TC_NATIVE_RESERVE
    jne tcjo_real_reserve
    mov rax, -12
    ret
FN tc_free
.if TCJO_MODE != 1 && TCJO_MODE < 6
    cmp rdi, [rip + tcjo_wire]
    jne tcjo_real_free
    cmp qword ptr [rip + tcjo_free_failed], 0
    jne tcjo_real_free
    mov qword ptr [rip + tcjo_free_failed], 1
    mov rax, -5
    xor edx, edx
    ret
.endif
    jmp tcjo_real_free
FN theme_capture_native_start
    jmp tcjo_fail
