.data
edtf_stage: .quad 0
edtf_guard: .quad 0
edtf_cancels: .quad 0
edtf_allocs: .quad 0
edtf_opens: .quad 0
edtf_closes: .quad 0
.text
FN mem_alloc_try
    cmp qword ptr [rip + edtf_stage], 1
    jne 1f
.if EDTF_MODE >= 1 && EDTF_MODE <= 3
    inc qword ptr [rip + edtf_allocs]
    cmp qword ptr [rip + edtf_allocs], EDTF_MODE
    jne 1f
    xor eax, eax
    ret
.endif
1:  cmp qword ptr [rip + edtf_stage], 2
    jne 2f
.if EDTF_MODE == 4
    xor eax, eax
    ret
.endif
2:  cmp qword ptr [rip + edtf_stage], 2
    jne 20f
.if EDTF_MODE == 42
    inc qword ptr [rip + edtf_allocs]
    cmp qword ptr [rip + edtf_allocs], 2
    jne 20f
    xor eax, eax
    ret
.endif
20: cmp qword ptr [rip + edtf_stage], 3
    jne 3f
.if EDTF_MODE == 5
    xor eax, eax
    ret
.endif
3:  jmp edtf_real_alloc

FN ext_root_open_at
    cmp qword ptr [rip + edtf_stage], 5
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 1
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 2
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 3
    jne 9f
    inc qword ptr [rip + edtf_opens]
.if EDTF_MODE == 35
    cmp qword ptr [rip + edtf_opens], 6
    je edtf_substitution
.endif
.if EDTF_MODE >= 10 && EDTF_MODE <= 15
    cmp qword ptr [rip + edtf_opens], EDTF_MODE - 9
    jne 9f
    mov rax, -5
    xor edx, edx
    ret
.endif
.if EDTF_MODE == 16
    cmp qword ptr [rip + edtf_opens], 1
    jne 9f
    mov rax, -2
    mov rdx, -5
    ret
.endif
.if EDTF_MODE == 0
    cmp qword ptr [rip + edtf_opens], 6
    jne 9f
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    lea rsi, [rip + edtf_lease]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call edtf_real_open
    test rax, rax
    js 8f
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call edtf_real_lock
    mov r12, rax
    mov rdi, rbx
    call edtf_real_close
    cmp r12, -11
    jne 8f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8, [rsp + 32]
    call edtf_real_open
    EPILOGUE
8:  mov rax, -33
    xor edx, edx
    EPILOGUE
.endif
9:  jmp edtf_real_open

FN ext_root_identity
    cmp qword ptr [rip + edtf_stage], 1
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 2
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 5
    je edt_fail
.if EDTF_MODE == 41
    cmp qword ptr [rip + edtf_stage], 3
    jne 40f
    mov rax, -5
    ret
40:
.endif
.if EDTF_MODE == 17
    cmp qword ptr [rip + edtf_stage], 3
    jne 1f
    mov rax, -5
    ret
.endif
1:
.if EDTF_MODE == 29
    cmp qword ptr [rip + edtf_stage], 3
    jne 2f
    PROLOGUE
    call edtf_real_identity
    mov rcx, [rip + edtf_guard]
    inc qword ptr [rcx + ESG_epoch]
    EPILOGUE
.endif
2:  jmp edtf_real_identity
FN ext_root_close
    cmp qword ptr [rip + edtf_stage], 1
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 2
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 5
    je edt_fail
    PROLOGUE
    call edtf_real_close
    test rax, rax
    js 9f
    cmp qword ptr [rip + edtf_stage], 3
    jne 1f
.if EDTF_MODE >= 36 && EDTF_MODE <= 41
    inc qword ptr [rip + edtf_closes]
.if EDTF_MODE <= 39
    cmp qword ptr [rip + edtf_closes], EDTF_MODE - 35
    jne 9f
    mov rax, -5
.else
.if EDTF_MODE == 40
    cmp qword ptr [rip + edtf_closes], 5
    jne 9f
    mov rax, -5
.else
    cmp qword ptr [rip + edtf_closes], 5
    jne 3f
    mov rax, -16
    jmp 9f
3:  cmp qword ptr [rip + edtf_closes], 6
    jne 9f
    mov rax, -13
.endif
.endif
    jmp 9f
.endif
.if EDTF_MODE == 18 || EDTF_MODE == 19
    inc qword ptr [rip + edtf_closes]
    cmp qword ptr [rip + edtf_closes], 1
    jne 2f
    mov rax, -5
    jmp 9f
2:
.if EDTF_MODE == 19
    cmp qword ptr [rip + edtf_closes], 2
    jne 9f
    mov rax, -13
.endif
.endif
1:  cmp qword ptr [rip + edtf_stage], 4
    jne 9f
.if EDTF_MODE == 21
    inc qword ptr [rip + edtf_closes]
    mov rax, -16
    cmp qword ptr [rip + edtf_closes], 1
    je 9f
    mov rax, -5
.endif
9:  EPILOGUE
FN ext_store_raw_lock
    cmp qword ptr [rip + edtf_stage], 1
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 2
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 5
    je edt_fail
.if EDTF_MODE == 20 || EDTF_MODE == 40
    cmp qword ptr [rip + edtf_stage], 3
    jne 1f
    mov rax, -11
    ret
.endif
1:  jmp edtf_real_lock
.section .rodata
edtf_lease: .asciz "lease"

FN edtf_cancel
    inc qword ptr [rip + edtf_cancels]
    cmp qword ptr [rip + edtf_cancels], EDTF_MODE - 21
    jne 1f
    mov rax, -125
    ret
1:  xor eax, eax
    ret
# Pause after the actual ID container is held, then compare the pre/post payload object.
FN edtf_substitution
    PROLOGUE 144
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    call edtf_real_open
    test rax, rax
    js edt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rsp + 64]
    call edtf_real_identity
    test rax, rax
    jnz edt_fail
    mov rdi, rbx
    call edtf_real_close
    test rax, rax
    jnz edt_fail
    mov byte ptr [rsp + 128], 'R'
    mov edi, 1
    lea rsi, [rsp + 128]
    mov edx, 1
    call write_all
    test rax, rax
    jnz edt_fail
    xor edi, edi
    lea rsi, [rsp + 128]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne edt_fail
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8, [rsp + 32]
    call edtf_real_open
    test rax, rax
    js edt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rsp + 96]
    call edtf_real_identity
    test rax, rax
    jnz edt_fail
    lea rdi, [rsp + 64]
    lea rsi, [rsp + 96]
    mov edx, 32
    call memeq
    test eax, eax
    jz edt_fail
    mov rax, rbx
    xor edx, edx
    EPILOGUE

.macro EDTF_PURE_FORWARD name, target
FN \name
    cmp qword ptr [rip + edtf_stage], 1
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 2
    je edt_fail
    cmp qword ptr [rip + edtf_stage], 5
    je edt_fail
    jmp \target
.endm
EDTF_PURE_FORWARD ext_root_open, edtf_real_rootopen
EDTF_PURE_FORWARD ext_root_reopen_dir, edtf_real_reopen
EDTF_PURE_FORWARD ext_root_stat, edtf_real_stat
EDTF_PURE_FORWARD ext_root_read, edtf_real_read
