.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extstorejob.inc"
.section .rodata
esjt_flag: .asciz "--extension-store-snapshot"
esjt_unc: .asciz "\\\\server\\share\\payload"
esjt_owner: .asciz "Foo"
esjt_name: .asciz "Bar"
esjt_poison_target: .asciz ".job-poison-target"
esjt_poison_meta: .asciz ".job-poison-meta"
esjt_wire: .asciz ".job-wire"
esjt_marker: .asciz ".job-test-mode"
esjt_bad: .ascii "!"
.data
esjt_poison_count: .quad 0
.text
esjt_fail:
    mov edi, 73
    call sys_exit
esjt_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne esjt_fail
    EPILOGUE
esjt_cancel:
    cmp qword ptr [rdi], 0
    je 1f
    dec qword ptr [rdi]
    xor eax, eax
    ret
1:  mov rax, [rdi + 8]
    ret
esjt_poison:
    inc qword ptr [rip + esjt_poison_count]
    xor eax, eax
    ret

# Native reexec of this fixture uses the same fixed production helper argument ABI.
esjt_child:
    PROLOGUE 16
    mov byte ptr [rsp], 0
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    call esjt_number
    mov r12, rax
    mov rdi, rax
    call esjt_inheritance
    mov rdi, r12
    lea rsi, [rip + esjt_marker]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js 1f
    mov r13, rax
    mov rdi, rax
    mov rsi, rsp
    mov edx, 1
    xor ecx, ecx
    call ext_root_read
    cmp rax, 1
    jne esjt_fail
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz esjt_fail
1:  cmp byte ptr [rsp], 'w'
    jne 11f
    mov rdi, r12
    call esjt_wire_child
    EPILOGUE
11: cmp byte ptr [rsp], 'q'
    jne 3f
    mov r13d, 150
2:  call ext_store_job_retire_wait
    dec r13
    jnz 2b
3:  cmp byte ptr [rsp], 's'
    jne 4f
    mov edi, 2
    lea rsi, [rip + esjt_bad]
    mov edx, 1
    call write_all
4:  mov rdi, [rip + g_argc]
    mov rsi, rbx
    call ext_store_snapshot_main
    test rax, rax
    jnz 8f
    cmp byte ptr [rsp], 'x'
    jne 5f
    mov eax, 7
    EPILOGUE
5:  cmp byte ptr [rsp], 'h'
    je 51f
    cmp byte ptr [rsp], 'z'
    jne 53f
51: mov edi, 1
    SYS SYS_close
    mov edi, 2
    SYS SYS_close
    mov r13d, 150
52: call ext_store_job_retire_wait
    dec r13
    jnz 52b
    xor eax, eax
    cmp byte ptr [rsp], 'z'
    jne 8f
    mov eax, 7
    EPILOGUE
53: cmp byte ptr [rsp], 'p'
    jne 8f
    mov edi, 1
    lea rsi, [rip + esjt_bad]
    mov edx, 1
    call write_all
8:  EPILOGUE

FN main
    PROLOGUE 256
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 10
    je esjt_validator_entry
    cmp qword ptr [rip + g_argc], 6
    je esjt_child_entry
    cmp qword ptr [rip + g_argc], 3
    jne esjt_fail
    mov r15, [rip + g_mem_live]
    mov rdi, [rbx + 16]
    call esjt_number
    mov r14, rax
    mov rdi, [rbx + 8]
    mov esi, 1
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz esjt_fail
    mov r12, rax
.ifdef WINDOWS
    mov rdi, [r12 + ESG_root]
    call esjt_poison_setup
    mov [rsp + 240], rax
.endif
    mov rdi, rsp
    xor esi, esi
    mov edx, ESJR_SIZE
    call memset
    mov qword ptr [rsp + ESJR_purpose], ESJ_SNAPSHOT
    mov rax, [r12 + ESG_root]
    mov [rsp + ESJR_anchor], rax
    mov [rsp + ESJR_guard], r12
    cmp r14, 10
    jb 92f
    cmp r14, 20
    jae 92f
    mov qword ptr [rsp + ESJR_purpose], ESJ_VALIDATOR
    mov rax, [rbx + 8]
    mov [rsp + ESJR_dir], rax
.ifdef WINDOWS
    cmp r14, 11
    jne 921f
    lea rax, [rip + esjt_unc]
    mov [rsp + ESJR_dir], rax
921:
.endif
    lea rax, [rip + esjt_owner]
    mov [rsp + ESJR_owner], rax
    lea rax, [rip + esjt_name]
    mov [rsp + ESJR_name], rax
    lea rdi, [rsp + 144]
    mov esi, 0xbb
    mov edx, 32
    call memset
    lea rax, [rsp + 144]
    mov [rsp + ESJR_source], rax
92:     mov rax, [r12 + ESG_epoch]
    mov [rsp + ESJR_tag + EST_epoch], rax
    mov qword ptr [rsp + ESJR_tag + EST_job], 7
    mov rax, 0x0706050403020100
    mov [rsp + ESJR_tag + EST_nonce], rax
    mov rax, 0x0f0e0d0c0b0a0908
    mov [rsp + ESJR_tag + EST_nonce + 8], rax
    mov rdi, [r12 + ESG_root]
    lea rsi, [rsp + ESJR_tag + EST_root_id]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
    cmp r14, 7
    jb 94f
    cmp r14, 8
    ja 94f
    lea rax, [rip + esjt_cancel]
    mov [rsp + ESJR_cancel], rax
    lea rax, [rsp + 200]
    mov [rsp + ESJR_user], rax
    mov qword ptr [rsp + 200], 3
    mov qword ptr [rsp + 208], -125
    cmp r14, 8
    jne 94f
    mov qword ptr [rsp + 208], 1
94:     call time_ms
    mov [rsp + ESJR_now], rax
    mov [rsp + 184], rax
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jz esjt_fail
    mov r13, rax
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jnz esjt_fail
    cmp rdx, -16
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_free
    cmp rax, -16
    jne esjt_fail
    test rdx, rdx
    jnz esjt_fail
    cmp r14, 1
    jne 1f
    mov rdi, r13
    call ext_store_job_cancel
1:  cmp r14, 3
    jne 2f
    inc qword ptr [r12 + ESG_epoch]
2:  cmp r14, 4
    jne 3f
.ifdef MACOS
    lea rax, [rip + esjt_poison]
    mov [rip + g_poll_hook], rax
.endif
    call ext_store_jobs_shutdown_begin
3:  mov qword ptr [rsp + 192], 0
.Lesjt_loop:
    call time_ms
    mov rbx, rax
    cmp r14, 2
    jne 4f
    add rax, 10000
4:  mov rsi, rax
    mov rdi, r13
    call ext_store_job_timeout
    test rax, rax
    js esjt_fail
    cmp rax, 16
    ja esjt_fail
    mov rdi, r13
    mov rsi, rbx
    cmp r14, 2
    jne 5f
    add rsi, 10000
5:  mov edx, 17
    cmp r14, 20
    jne 97f
    mov edx, 65536
97:     cmp r14, 4
    jne 95f
    mov rdi, rsi
    call ext_store_jobs_shutdown_step
    jmp 96f
95: call ext_store_job_step
96:
    inc qword ptr [rsp + 192]
    test rax, rax
    jnz .Lesjt_done
    cmp qword ptr [rsp + 192], 2000
    ja esjt_fail
    call ext_store_job_retire_wait
    jmp .Lesjt_loop
.Lesjt_done:
.ifdef MACOS
    mov qword ptr [rip + g_poll_hook], 0
.endif
    cmp qword ptr [rip + esjt_poison_count], 0
    jne esjt_fail
    mov rdi, r13
    mov rsi, rbx
    call ext_store_job_timeout
    cmp rax, -1
    jne esjt_fail
    cmp r14, 6
    jne 6f
    mov rdi, r13
    call ext_store_job_take_receipt
    test rax, rax
    jnz esjt_fail
    cmp rdx, -22
    jne esjt_fail
6:  mov rdi, r13
    cmp r14, 10
    jb 98f
    cmp r14, 20
    jb .Lesjt_receipt_take
98:
    cmp r14, 5
    jne 7f
    call ext_store_job_take_snapshot_bound
    jmp 8f
7:  call ext_store_job_take_snapshot
8:  mov [rsp + 208], rdx
    mov [rsp + 216], rcx
    mov qword ptr [rsp + 224], 0
    test rax, rax
    jz 10f
    mov rbx, rax
    cmp r14, 5
    jne 9f
    cmp [rax + ESS_proof_guard], r12
    jne esjt_fail
    jmp 91f
9:  cmp qword ptr [rax + ESS_proof_guard], 0
    jne esjt_fail
    cmp qword ptr [rax + ESS_proof_epoch], 0
    jne esjt_fail
91: mov rax, [rbx + ESS_entries + VEC_len]
    mov [rsp + 224], rax
    mov rdi, rbx
    call ext_store_snapshot_free
10: mov rdi, r13
    call ext_store_job_free
    test rax, rax
    jnz esjt_fail
    cmp rdx, 1
    jne esjt_fail
    mov rdi, [r12 + ESG_root]
    lea rsi, [rsp + 144]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
.ifdef WINDOWS
    mov rdi, [rsp + 240]
    call ext_root_close
    test rax, rax
    jnz esjt_fail
.endif
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esjt_fail
    cmp [rip + g_mem_live], r15
    jne esjt_fail
    mov rax, [rsp + 192]
    mov [rsp + 232], rax
    mov edi, 1
    lea rsi, [rsp + 208]
    mov edx, 32
    call write_all
    test rax, rax
    jnz esjt_fail
    xor eax, eax
    EPILOGUE
 .Lesjt_receipt_take:
    call ext_store_job_take_receipt
    mov qword ptr [rsp + 224], 0
    test rax, rax
    jz 93f
    cmp rdx, 192
    jne esjt_fail
    cmp byte ptr [rax + 80], 0xaa
    jne esjt_fail
    cmp byte ptr [rax + 112], 0xbb
    jne esjt_fail
    mov rdi, rax
    call mem_free
    xor edx, edx
    xor ecx, ecx
93: mov [rsp + 208], rdx
    mov [rsp + 216], rcx
    jmp 10b
esjt_validator_entry:
    call esjt_validator_child
    EPILOGUE
esjt_child_entry:
    call esjt_child
    EPILOGUE

# Fixed-wire validator stand-in tests transport only, not package acceptance.
esjt_validator_child:
    PROLOGUE 240
    mov rbx, [rip + g_argv]
    mov rdi, rsp
    xor esi, esi
    mov edx, 240
    call memset
    mov rax, 0x00314c4156454852
    mov [rsp], rax
    mov dword ptr [rsp + 8], 1
    mov dword ptr [rsp + 12], 192
    mov rdi, [rbx + 16]
    call esjt_number
    mov r12, rax
    mov rdi, rax
    call esjt_inheritance
    mov rdi, [rbx + 48]
    call esjt_number
    mov [rsp + 16], rax
    mov rdi, [rbx + 56]
    call esjt_number
    mov [rsp + 24], rax
    mov r14, [rbx + 64]
    xor r13d, r13d
1:  lea rdi, [r14 + r13*2]
    mov esi, 2
    call parse_hex
    cmp rdx, 2
    jne esjt_fail
    mov [rsp + 32 + r13], al
    inc r13
    cmp r13, 16
    jb 1b
    mov rdi, r12
    lea rsi, [rsp + 48]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
    lea rdi, [rsp + 80]
    mov esi, 0xaa
    mov edx, 32
    call memset
    lea rdi, [rsp + 112]
    mov esi, 0xbb
    mov edx, 32
    call memset
    mov rdi, r12
    lea rsi, [rip + esjt_marker]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js 2f
    mov r13, rax
    mov rdi, rax
    lea rsi, [rsp + 200]
    mov edx, 1
    xor ecx, ecx
    call ext_root_read
    cmp rax, 1
    jne esjt_fail
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz esjt_fail
2:  mov rdi, r12
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    cmp byte ptr [rsp + 200], 'm'
    jne 3f
    inc byte ptr [rsp]
3:  cmp byte ptr [rsp + 200], 'r'
    jne 4f
    inc byte ptr [rsp + 160]
4:  cmp byte ptr [rsp + 200], 'g'
    jne 5f
    inc byte ptr [rsp + 32]
5:  cmp byte ptr [rsp + 200], 'b'
    jne 6f
    inc byte ptr [rsp + 112]
6:  mov edi, 1
    mov rsi, rsp
    mov edx, 192
    cmp byte ptr [rsp + 200], 'l'
    jne 7f
    dec rdx
7:  cmp byte ptr [rsp + 200], 'e'
    jne 8f
    inc rdx
8:  call write_all
    test rax, rax
    jnz esjt_fail
    xor eax, eax
    EPILOGUE

# Emit caller-provided framed test bytes, binding the tag to the actual inherited root.
esjt_wire_child:
    PROLOGUE 64
    mov rbx, rdi
    lea rsi, [rip + esjt_wire]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js esjt_fail
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    jnz esjt_fail
    mov r13, [rsp + 8]
    cmp r13, ESW_WIRE_MAX + 1
    ja esjt_fail
    mov rdi, r13
    call mem_alloc_try
    test rax, rax
    jz esjt_fail
    mov r14, rax
    xor r15d, r15d
1:  mov rdi, r12
    lea rsi, [r14 + r15]
    mov rdx, r13
    sub rdx, r15
    mov rcx, r15
    call ext_root_read
    test rax, rax
    jle esjt_fail
    add r15, rax
    cmp r15, r13
    jb 1b
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    cmp r13, 112
    jb 2f
    mov qword ptr [r14 + 48], 1
    mov qword ptr [r14 + 56], 7
    mov rax, 0x0706050403020100
    mov [r14 + 64], rax
    mov rax, 0x0f0e0d0c0b0a0908
    mov [r14 + 72], rax
    mov rdi, rbx
    lea rsi, [r14 + 80]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
2:  mov rdi, rbx
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov edi, 1
    mov rsi, r14
    mov rdx, r13
    call write_all
    mov r12, rax
    mov rdi, r14
    call mem_free
    mov rax, r12
    EPILOGUE

# Check known inherited sentinels. A native runtime may open its own descriptors after exec.
esjt_inheritance:
    PROLOGUE 80
.ifdef WINDOWS
    lea rsi, [rip + esjt_poison_meta]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js esjt_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, rsp
    mov edx, 40
    xor ecx, ecx
    call ext_root_read
    cmp rax, 40
    jne esjt_fail
    mov rdi, rbx
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov rdi, [rsp]
    lea rsi, [rsp + 40]
    call ext_root_identity
    test rax, rax
    js 2f
    lea rdi, [rsp + 8]
    lea rsi, [rsp + 40]
    mov edx, 32
    call memeq
    test eax, eax
    jnz esjt_fail
2:
.else
    # FD150 existed before the parent lowered its limit to32. It cannot be newly opened here.
    mov ebx, 150
1:  mov rdi, rbx
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    cmp rax, -9
    jne esjt_fail
    inc rbx
    cmp rbx, 151
    jb 1b
.endif
    xor eax, eax
    EPILOGUE
.ifdef WINDOWS
# Parent prepares an intentionally inheritable unlisted raw file handle and exact identity.
esjt_poison_setup:
    PROLOGUE 160
    mov rbx, rdi
    lea rsi, [rip + esjt_poison_target]
    mov edx, 1
    mov ecx, 3
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js esjt_fail
    test rdx, rdx
    jnz esjt_fail
    mov r12, rax
    mov [rsp + 96], rax
    mov rdi, rax
    lea rsi, [rsp + 104]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
    mov rcx, -1
    mov rdx, r12
    mov r8, -1
    lea r9, [rsp + 144]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 1
    mov qword ptr [rsp + 48], 2
    call [rip + __imp_DuplicateHandle]
    test eax, eax
    jz esjt_fail
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov r12, [rsp + 144]
    mov [rsp + 96], r12
    mov rdi, rbx
    lea rsi, [rip + esjt_poison_meta]
    mov edx, 1
    mov ecx, 3
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js esjt_fail
    test rdx, rdx
    jnz esjt_fail
    mov r13, rax
    mov rdi, rax
    lea rsi, [rsp + 96]
    mov edx, 40
    call ext_store_raw_write
    cmp rax, 40
    jne esjt_fail
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov rax, r12
    EPILOGUE
.endif
