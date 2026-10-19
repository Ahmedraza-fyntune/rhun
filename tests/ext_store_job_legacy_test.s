.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstore.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.section .rodata
esjt_flag: .asciz "--snapshot-legacy-anchored"
esjlt_unc_cwd: .asciz "//server/share/work Ω"
esjt_unc: .asciz "\\\\server\\share\\payload"
esjt_owner: .asciz "Foo"
esjt_name: .asciz "Bar"
esjt_poison_target: .asciz ".job-poison-target"
esjt_poison_meta: .asciz ".job-poison-meta"
esjt_wire: .asciz ".job-wire"
esjt_marker: .asciz ".job-test-mode"
esjt_bad: .ascii "!"
.bss
.globl esjlt_forbid_io, esjlt_forbidden_count
esjlt_forbid_io: .zero 8
esjlt_forbidden_count: .zero 8
esjlt_census_before: .zero 8
esjlt_expected_windows_directory: .zero 1024
esjlt_owned_job: .zero 8
esjlt_seen_reaped: .zero 8
esjlt_repeat_count: .zero 8
esjlt_flood: .zero 4096
.data
esjt_poison_count: .quad 0
esjlt_child_mode: .quad 0
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
    PROLOGUE 384
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 10
    je esjt_validator_entry
    cmp qword ptr [rip + g_argc], 6
    je esjt_child_entry
    cmp qword ptr [rip + g_argc], 3
    jne esjt_fail
    mov rdi, [rbx + 16]
    call esjt_number
    mov r14, rax
    cmp r14, 34
    je 91f
    call ext_store_job_legacy_cache_executable
    test rax, rax
    jnz esjt_fail
91:
.ifdef WINDOWS
    lea rcx, [rip + esjlt_expected_windows_directory]
    mov edx, 512
    API GetWindowsDirectoryW
    test eax, eax
    jz esjt_fail
.endif
    mov r15, [rip + g_mem_live]
    call esjlt_census
    mov [rip + esjlt_census_before], rax
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
    mov [rsp + 248], rdx
.endif
    mov rdi, rsp
    xor esi, esi
    mov edx, ESJR_SIZE
    call memset
    mov qword ptr [rsp + ESJR_purpose], ESJ_LEGACY_SNAPSHOT
    mov rax, [r12 + ESG_root]
    mov [rsp + ESJR_anchor], rax
    mov [rsp + ESJR_guard], r12
    mov rax, [rbx + 8]
    mov [rsp + ESJR_dir], rax
    lea rax, [rip + esjt_owner]
    mov [rsp + ESJR_owner], rax
    lea rax, [rip + esjt_name]
    mov [rsp + ESJR_name], rax
    cmp r14, 10
    jb 92f
    cmp r14, 20
    jae 92f
    mov qword ptr [rsp + ESJR_purpose], ESJ_LEGACY_VALIDATOR
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
    cmp r14, 12
    jne 84f
    mov qword ptr [rsp + ESJR_source], 0
84: mov qword ptr [rip + esjlt_forbid_io], 1
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jnz 83f
    cmp r14, 30
    je 92f
    cmp r14, 34
    jne esjt_fail
92: mov [rsp + 208], rdx
    mov [rsp + 216], rcx
    mov qword ptr [rsp + 224], 0
    mov qword ptr [rsp + 192], 1
    xor r13d, r13d
    jmp 10f
83: mov r13, rax
    mov [rip + esjlt_owned_job], rax
    cmp r14, 30
    je esjt_fail
    cmp r14, 34
    je esjt_fail
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
    mov rdi, r13
    mov rsi, rsp
    call esjlt_busy_after_cancel
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
    cmp qword ptr [r13 + ESJ_authority], ESJ_REAPED
    jne 85f
    cmp qword ptr [r13 + ESJ_eof], 7
    je 85f
    mov qword ptr [rip + esjlt_seen_reaped], 1
85: cmp r14, 23
    jne 86f
    mov rax, [r13 + ESJ_used]
    cmp rax, 512
    jb 86f
    mov rdi, r13
    call ext_store_job_cancel
    mov rdi, r13
    mov rsi, rsp
    call esjlt_busy_after_cancel
86: cmp r14, 21
    jne 81f
    cmp qword ptr [r13 + ESJ_used], 65536
    jb 81f
    mov rdi, r13
    call ext_store_job_cancel
81: call time_ms
    mov rbx, rax
    cmp r14, 2
    jne 4f
    add rax, 10000
4:  mov rsi, rax
    mov rdi, r13
    call ext_store_job_timeout
    test rax, rax
    js esjt_fail
    test rax, rax
    jle esjt_fail
    cmp rax, 16
    ja esjt_fail
    cmp qword ptr [r13 + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    jne 87f
    cmp r14, 31
    je 87f
    cmp rax, 1
    jne esjt_fail
87: mov [rsp + 176], rax
    mov rdi, r13
    mov rsi, rbx
    cmp r14, 2
    je 82f
    cmp r14, 24
    jne 88f
    cmp qword ptr [r13 + ESJ_used], 512
    jb 5f
    jmp 82f
88: cmp r14, 22
    jne 5f
    cmp qword ptr [r13 + ESJ_used], 65536
    jb 5f
82: add rsi, 10000
5:  mov edx, 17
    cmp r14, 20
    jb 97f
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
    cmp qword ptr [rsp + 192], 20000
    ja esjt_fail
    mov rdi, [rsp + 176]
    call esjlt_wait
    jmp .Lesjt_loop
.Lesjt_done:
.ifdef ESJLF_KILL_SPY
.if ESJF_MODE == 20
    cmp qword ptr [rip + esjlf_kill_count], 1
    jne esjt_fail
.endif
.endif
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
    cmp r14, 13
    je 72f
    cmp r14, 35
    jne 73f
72: inc qword ptr [r12 + ESG_epoch]
    mov qword ptr [rsp + 144], 0x12345678
    mov qword ptr [rsp + 152], 0x12345678
    mov rdi, r13
    lea rsi, [rsp + 144]
    call ext_store_job_legacy_context
    cmp rax, -116
    jne esjt_fail
    cmp qword ptr [rsp + 144], 0x12345678
    jne esjt_fail
    cmp qword ptr [rsp + 152], 0x12345678
    jne esjt_fail
73: cmp r14, 6
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
98: call ext_store_job_take_legacy_receipt
    test rax, rax
    jnz esjt_fail
    cmp rdx, -22
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_take_legacy_snapshot
    mov [rsp + 208], rdx
    mov [rsp + 216], rcx
    mov qword ptr [rsp + 224], 0
    test rax, rax
    jz 10f
    mov rbx, rax
    mov [rsp + 224], rdx
    cmp rdx, 65536
    jbe 74f
.ifdef ELF_BODY_CORRUPT
    xor byte ptr [rbx + 65536], 1
.endif
    mov rdi, rbx
    mov rsi, rdx
    mov rdx, [r12 + ESG_root]
    mov rcx, r13
    call esjlt_compare_wire
74:
    mov rdi, r13
    lea rsi, [rsp + 144]
    call ext_store_job_legacy_context
    test rax, rax
    jnz esjt_fail
.ifdef WINDOWS
    mov rdi, [rsp + 144]
    test rdi, rdi
    jz esjt_fail
    mov rax, [rip + g_argv]
    mov rsi, [rax + 8]
    cmp r14, 32
    jne 89f
    lea rsi, [rip + esjlt_unc_cwd]
89: call strcmp_eq
    test eax, eax
    jz esjt_fail
    xor eax, eax
    cmp r14, 32
    je 90f
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    movzx eax, byte ptr [rax]
    and eax, -33
90: cmp rax, [rsp + 152]
    jne esjt_fail
.else
    cmp qword ptr [rsp + 144], 0
    jne esjt_fail
    cmp qword ptr [rsp + 152], 0
    jne esjt_fail
.endif
    mov rdi, rbx
    call mem_free
    mov qword ptr [rsp + 208], 0
    mov rdi, r13
    call ext_store_job_take_legacy_snapshot
    test rax, rax
    jnz esjt_fail
    cmp rdx, -2
    jne esjt_fail
10: mov rdi, r13
    call ext_store_job_free
    test rax, rax
    jnz esjt_fail
    cmp rdx, 1
    jne esjt_fail
    mov qword ptr [rip + esjlt_forbid_io], 0
    cmp qword ptr [rip + esjlt_forbidden_count], 0
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
    mov edi, [rsp + 248]
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
    call esjlt_census
    cmp rax, [rip + esjlt_census_before]
    jne esjt_fail
    cmp r14, 33
    jne 92f
    inc qword ptr [rip + esjlt_repeat_count]
    cmp qword ptr [rip + esjlt_repeat_count], 3
    jae 92f
    call main
    EPILOGUE
92: mov rax, [rsp + 192]
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
    call ext_store_job_take_legacy_snapshot
    test rax, rax
    jnz esjt_fail
    cmp rdx, -22
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_take_receipt
    test rax, rax
    jnz esjt_fail
    cmp rdx, -22
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_take_legacy_receipt
    mov qword ptr [rsp + 224], 0
    test rax, rax
    jz 93f
    cmp rdx, 192
    jne esjt_fail
    cmp byte ptr [rax + 80], 0
    jne esjt_fail
    cmp byte ptr [rax + 112], 0xbb
    jne esjt_fail
    mov rdi, rax
    call mem_free
    mov rdi, r13
    call ext_store_job_take_legacy_receipt
    test rax, rax
    jnz esjt_fail
    cmp rdx, -2
    jne esjt_fail
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
    mov byte ptr [rsp + 200], 0
    mov rbx, [rip + g_argv]
    call ext_store_job_legacy_child_context
    test rax, rax
    jnz esjt_fail
    mov rdi, [rbx + 8]
    lea rsi, [rip + esjt_flag]
    call strcmp_eq
    test eax, eax
    jnz esjlt_snapshot_child
    mov rdi, rsp
    xor esi, esi
    mov edx, 240
    call memset
    mov rax, 0x00314347454c4852
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
6:  cmp byte ptr [rsp + 200], 'T'
    jne 61f
    mov byte ptr [rsp + 80], 1
61: cmp byte ptr [rsp + 200], 'S'
    jne 62f
    lea rdi, [rsp + 112]
    xor esi, esi
    mov edx, 32
    call memset
62: cmp byte ptr [rsp + 200], 'P'
    jne 63f
    mov qword ptr [rsp + 144], -5
63: cmp byte ptr [rsp + 200], 'C'
    jne 64f
    mov qword ptr [rsp + 152], -5
64: cmp byte ptr [rsp + 200], 'M'
    jne 65f
    mov rax, 0x00314c4156454852
    mov [rsp], rax
65: mov edi, 1
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
    cmp r13, ESJL_CAP + 1
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
    cmp r13, 192
    jb 2f
    mov qword ptr [r14 + 32], 1
    mov qword ptr [r14 + 40], 7
    mov rax, 0x0706050403020100
    mov [r14 + 48], rax
    mov rax, 0x0f0e0d0c0b0a0908
    mov [r14 + 56], rax
    mov rdi, rbx
    lea rsi, [r14 + 64]
    call ext_root_identity
    test rax, rax
    jnz esjt_fail
2:
    cmp qword ptr [rip + esjlt_child_mode], 'T'
    jne 22f
    cmp r13, 192
    jb 22f
    inc byte ptr [r14 + 32]
22: cmp qword ptr [rip + esjlt_child_mode], 'N'
    jne 23f
    inc byte ptr [r14 + 48]
23: cmp qword ptr [rip + esjlt_child_mode], 'R'
    jne 24f
    inc byte ptr [r14 + 64]
24: cmp qword ptr [rip + esjlt_child_mode], 'B'
    jne 25f
    inc dword ptr [r14 + 8]
25:
.ifdef WINDOWS
    cmp r13, 192
    jb 21f
    cmp dword ptr [r14 + 152], -1
    jne 21f
    mov edi, ELC_SIZE
    call mem_alloc_try
    test rax, rax
    jz esjt_fail
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, ELC_SIZE
    call memset
    mov rdi, r15
    call win_ext_store_job_legacy_capture
    test rax, rax
    jnz esjt_fail
    mov eax, [r15 + ELC_drive]
    mov [r14 + 152], eax
    mov rdi, r15
    call mem_free
21:
.endif
    mov rdi, rbx
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov edi, 1
    mov rsi, r14
    mov rdx, r13
    cmp qword ptr [rip + esjlt_child_mode], 'B'
    jne 26f
    mov edx, 192
26: cmp qword ptr [rip + esjlt_child_mode], 'D'
    jne 27f
    dec rdx
    call write_all
    test rax, rax
    jnz esjt_fail
    mov r15d, 70
28: call ext_store_job_retire_wait
    dec r15
    jnz 28b
    mov edi, 1
    lea rsi, [r14 + r13 - 1]
    mov edx, 1
    call write_all
    jmp 29f
27: call write_all
29: mov r12, rax
    mov rdi, r14
    call mem_free
    mov rax, r12
    EPILOGUE

# Check known inherited sentinels. A native runtime may open its own descriptors after exec.
esjt_inheritance:
    PROLOGUE 144
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
    mov edx, 48
    xor ecx, ecx
    call ext_root_read
    cmp rax, 48
    jne esjt_fail
    mov rdi, rbx
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov rdi, [rsp]
    lea rsi, [rsp + 48]
    call ext_root_identity
    test rax, rax
    js 2f
    lea rdi, [rsp + 8]
    lea rsi, [rsp + 48]
    mov edx, 32
    call memeq
    test eax, eax
    jnz esjt_fail
2:  mov ecx, [rsp + 40]
    API GetProcessId
    cmp eax, [rsp + 44]
    je esjt_fail
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
    mov rcx, -1
    mov rdx, -1
    mov r8, -1
    lea r9, [rsp + 144]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 1
    mov qword ptr [rsp + 48], 2
    API DuplicateHandle
    test eax, eax
    jz esjt_fail
    API GetCurrentProcessId
    shl rax, 32
    or rax, [rsp + 144]
    mov [rsp + 136], rax
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
    mov edx, 48
    call ext_store_raw_write
    cmp rax, 48
    jne esjt_fail
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    mov rax, r12
    mov rdx, [rsp + 136]
    EPILOGUE
.endif

esjlt_snapshot_child:
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
    lea rsi, [rsp + 200]
    mov edx, 1
    xor ecx, ecx
    call ext_root_read
    mov rdi, r13
    call ext_root_close
1:  movzx eax, byte ptr [rsp + 200]
    mov [rip + esjlt_child_mode], rax
    cmp byte ptr [rsp + 200], 'q'
    jne 3f
    mov r13d, 150
2:  call ext_store_job_retire_wait
    dec r13
    jnz 2b
3:  cmp byte ptr [rsp + 200], 's'
    jne 4f
    mov edi, 2
    lea rsi, [rip + esjt_bad]
    mov edx, 1
    call write_all
4:  cmp byte ptr [rsp + 200], 'F'
    jne 43f
    mov r13d, 256
44: mov edi, 2
    lea rsi, [rip + esjlt_flood]
    mov edx, 4096
    call write_all
    test rax, rax
    jnz esjt_fail
    dec r13
    jnz 44b
43: mov rdi, r12
    call esjt_wire_child
    test rax, rax
    jnz esjt_fail
    cmp byte ptr [rsp + 200], 'B'
    jne 41f
    mov r13d, 150
42: call ext_store_job_retire_wait
    dec r13
    jnz 42b
41: cmp byte ptr [rsp + 200], 'x'
    jne 5f
    mov eax, 7
    EPILOGUE
5:  cmp byte ptr [rsp + 200], 'h'
    je 51f
    cmp byte ptr [rsp + 200], 'z'
    jne 53f
51: mov edi, 1
    SYS SYS_close
    mov edi, 2
    SYS SYS_close
    mov r13d, 70
52: call ext_store_job_retire_wait
    dec r13
    jnz 52b
    cmp byte ptr [rsp + 200], 'z'
    jne 6f
    mov eax, 7
    EPILOGUE
53: cmp byte ptr [rsp + 200], 'p'
    jne 6f
    mov edi, 1
    lea rsi, [rip + esjt_bad]
    mov edx, 1
    call write_all
6:  xor eax, eax
    EPILOGUE

# Normal job cadence follows its public timeout, separate from final16ms retirement.
esjlt_wait:
    PROLOGUE 96
.ifdef WINDOWS
    mov rcx, rdi
    call [rip + __imp_Sleep]
.else
    imul rdi, rdi, 1000000
    mov qword ptr [rsp + 64], 0
    mov [rsp + 72], rdi
    lea rdi, [rsp + 64]
    xor esi, esi
    SYS 35
.endif
    EPILOGUE

esjlt_busy_after_cancel:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_store_job_free
    cmp rax, -16
    jne esjt_fail
    test rdx, rdx
    jnz esjt_fail
    mov rdi, r12
    call ext_store_job_start
    test rax, rax
    jnz esjt_fail
    cmp rdx, -16
    jne esjt_fail
    EPILOGUE

esjlt_census:
    PROLOGUE 112
.ifdef WINDOWS
    mov rcx, -1
    lea rdx, [rsp + 96]
    API GetProcessHandleCount
    test eax, eax
    jz esjt_fail
    mov eax, [rsp + 96]
.else
    xor ebx, ebx
    xor r12d, r12d
1:  mov rdi, rbx
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 2f
    inc r12
2:  inc rbx
    cmp rbx, 256
    jb 1b
    mov rax, r12
.endif
    EPILOGUE


# Test oracle runs after the timed transport step and compares every transferred byte.
esjlt_compare_wire:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, rcx
    mov rax, [rip + esjlt_forbid_io]
    mov [rsp], rax
    mov qword ptr [rip + esjlt_forbid_io], 0
    mov rdi, r12
    call mem_alloc_try
    test rax, rax
    jz esjt_fail
    mov r14, rax
    mov rdi, r13
    lea rsi, [rip + esjt_wire]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js esjt_fail
    test rdx, rdx
    jnz esjt_fail
    mov r13, rax
    xor eax, eax
    mov [rsp + 8], rax
1:  mov rdi, r13
    mov rcx, [rsp + 8]
    lea rsi, [r14 + rcx]
    mov rdx, r12
    sub rdx, rcx
    call ext_root_read
    test rax, rax
    jle esjt_fail
    add [rsp + 8], rax
    cmp [rsp + 8], r12
    jb 1b
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz esjt_fail
    lea rdi, [r14 + 32]
    lea rsi, [r15 + ESJ_tag]
    mov edx, 64
    call memcpy
.ifdef WINDOWS
    cmp dword ptr [r14 + 152], -1
    jne 2f
    mov rax, [r15 + ESJ_legacy]
    mov eax, [rax + ELC_drive]
    mov [r14 + 152], eax
2:
.endif
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call memeq
    test eax, eax
    jz esjt_fail
    mov rdi, r14
    call mem_free
    mov rax, [rsp]
    mov [rip + esjlt_forbid_io], rax
    EPILOGUE
