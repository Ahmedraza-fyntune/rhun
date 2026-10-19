# Run normally, and with TEST_TASK_CLIPBOARD_FAULT plus a private editor cache-copy hook.
.include "rhun.inc"
.bss
.p2align 3
tcpt_calls: .quad 0
tcpt_fail_dup: .quad 0
.text
.ifdef TEST_TASK_CLIPBOARD_FAULT
FN tcpt_dup
    cmp qword ptr [rip + tcpt_fail_dup], 0
    je 1f
    xor eax, eax
    ret
1:  jmp mem_dup_try
.endif
tcpt_clip:
    inc qword ptr [rip + tcpt_calls]
    mov eax, 1
    ret
FN main
    PROLOGUE 32
    mov rax, [rip + g_plat + P_clip_set]
    mov [rsp], rax
    mov rax, [rip + g_plat + P_clip_write]
    mov [rsp + 8], rax
    lea rax, [rip + tcpt_clip]
    mov [rip + g_plat + P_clip_set], rax
    mov qword ptr [rip + g_plat + P_clip_write], 0
    lea rdi, [rip + tcpt_old]
    mov esi, 4
    xor edx, edx
    call ed_clip_set
    cmp eax, 1
    jne tcpt_bad
    mov r12, [rip + g_mem_live]
    # Successful conversion allocation followed by failed editor-cache duplication.
    lea rdi, [rip + tcpt_new]
    mov esi, 4
    call mem_dup_try
    test rax, rax
    jz tcpt_bad
    mov rbx, rax
    mov qword ptr [rip + tcpt_calls], 0
    mov qword ptr [rip + tcpt_fail_dup], 1
    mov rdi, rbx
    mov esi, 4
    xor edx, edx
    call ed_clip_set
.ifdef TEST_TASK_CLIPBOARD_FAULT
    test eax, eax
    jnz tcpt_bad
    cmp qword ptr [rip + tcpt_calls], 0
    jne tcpt_bad
.else
    cmp eax, 1
    jne tcpt_bad
    cmp qword ptr [rip + tcpt_calls], 1
    jne tcpt_bad
.endif
    mov rdi, rbx
    call mem_free
    cmp r12, [rip + g_mem_live]
    jne tcpt_bad
.ifdef TEST_TASK_CLIPBOARD_FAULT
    lea rdi, [rip + tcpt_old]
.else
    lea rdi, [rip + tcpt_new]
.endif
    mov esi, 4
    call ed_clip_matches
    cmp eax, 1
    jne tcpt_bad
    mov rax, [rsp]
    mov [rip + g_plat + P_clip_set], rax
    mov rax, [rsp + 8]
    mov [rip + g_plat + P_clip_write], rax
    lea rdi, [rip + tcpt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
tcpt_bad:
    mov edi, 1
    call sys_exit
.section .rodata
tcpt_old: .ascii "old!"
tcpt_new: .ascii "new!"
tcpt_ok: .asciz "ok managed task clipboard allocation failure\n"
