# Real legacy snapshot and proof share only the allowlisted native transport.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstore.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.section .rodata
elr_snapshot: .asciz "--snapshot-legacy-anchored"
elr_owner: .asciz "Foo"
elr_name: .asciz "Bar"
elr_source: .asciz ".job-source"
elr_parent_path: .asciz "PATH=/parent-path-mutated-after-start"
elr_parent_root: .asciz "/"
.ifdef WINDOWS
elr_native_path_key: .asciz "RHUN_TEST_LEGACY_NATIVE_PATH"
elr_parent_path_w: .short 'P','A','T','H',0
elr_parent_poison_w: .short 'C',':','/','n','o','n','e','x','i','s','t','e','n','t',0
.endif
.data
elr_parent_env: .quad elr_parent_path, 0
.bss
elf_child_closes: .zero 8
.text
.text
elr_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 4448
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 10
    je .Lelr_child
    cmp qword ptr [rip + g_argc], 3
    jne elr_fail
    # Wine does not map its Unix PATH to the Windows PATH. Set test context natively.
.ifdef WINDOWS
    lea rdi, [rip + elr_native_path_key]
    call getenv
    test rax, rax
    jz 71f
    cmp byte ptr [rax], '-'
    jne 72f
    lea rcx, [rip + elr_parent_path_w]
    xor edx, edx
    API SetEnvironmentVariableW
    test eax, eax
    jz elr_fail
    jmp 71f
72: cmp byte ptr [rax], '+'
    jne elr_fail
    lea rdi, [rax + 1]
    call win_wide
    test rax, rax
    jz elr_fail
    mov r12, rax
    lea rcx, [rip + elr_parent_path_w]
    mov rdx, rax
    API SetEnvironmentVariableW
    test eax, eax
    jz elr_fail
    mov rdi, r12
    call mem_free
71:
.endif
    call ext_store_job_legacy_cache_executable
    test rax, rax
    jnz elr_fail
    mov rax, [rip + g_mem_live]
    mov [rsp + 304], rax
    mov rdi, [rbx + 8]
    mov esi, 1
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz elr_fail
    mov r12, rax
    mov rdi, rsp
    xor esi, esi
    mov edx, ESJR_SIZE
    call memset
    mov qword ptr [rsp + ESJR_purpose], ESJ_LEGACY_SNAPSHOT
    mov rdi, [rbx + 16]
    cmp byte ptr [rdi], '4'
    jne 1f
    mov qword ptr [rsp + ESJR_purpose], ESJ_LEGACY_VALIDATOR
    mov rdi, [r12 + ESG_root]
    lea rsi, [rip + elr_source]
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js elr_fail
    mov r13, rax
    mov rdi, rax
    lea rsi, [rsp + 256]
    mov edx, 32
    xor ecx, ecx
    call ext_root_read
    cmp rax, 32
    jne elr_fail
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jnz elr_fail
    lea rax, [rsp + 256]
    mov [rsp + ESJR_source], rax
1:  mov rax, [r12 + ESG_root]
    mov [rsp + ESJR_anchor], rax
    mov [rsp + ESJR_guard], r12
    mov qword ptr [rsp + ESJR_tag], 1
    mov qword ptr [rsp + ESJR_tag + 8], 7
    mov rdi, [r12 + ESG_root]
    lea rsi, [rsp + ESJR_tag + 32]
    call ext_root_identity
    test rax, rax
    jnz elr_fail
    mov rax, [rbx + 8]
    mov [rsp + ESJR_dir], rax
    lea rax, [rip + elr_owner]
    mov [rsp + ESJR_owner], rax
    lea rax, [rip + elr_name]
    mov [rsp + ESJR_name], rax
    call time_ms
    mov [rsp + ESJR_now], rax
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jz elr_fail
    mov r13, rax
    # Challenge saved job context after the native child has been created.
.ifdef WINDOWS
    sub rsp, 96
    lea rcx, [rip + elr_parent_path_w]
    lea rdx, [rip + elr_parent_poison_w]
    API SetEnvironmentVariableW
    test eax, eax
    jz elr_fail
    lea rcx, [rsp + 416]
    mov edx, 2048
    API GetWindowsDirectoryW
    test eax, eax
    jz elr_fail
    lea rcx, [rsp + 416]
    API SetCurrentDirectoryW
    test eax, eax
    jz elr_fail
    add rsp, 96
.else
    lea rax, [rip + elr_parent_env]
    mov [rip + g_envp], rax
    lea rdi, [rip + elr_parent_root]
    SYS SYS_chdir
    test rax, rax
    jnz elr_fail
.endif
2:  call time_ms
    mov rdi, r13
    mov rsi, rax
    mov edx, 65536
    call ext_store_job_step
    test rax, rax
    jnz 3f
    call time_ms
    mov rdi, r13
    mov rsi, rax
    call ext_store_job_timeout
.ifdef WINDOWS
    mov rcx, rax
    call [rip + __imp_Sleep]
.else
    imul rax, rax, 1000000
    mov qword ptr [rsp + 288], 0
    mov [rsp + 296], rax
    lea rdi, [rsp + 288]
    xor esi, esi
    SYS 35
.endif
    jmp 2b
3:  mov rdi, r13
    cmp qword ptr [rsp + ESJR_purpose], ESJ_LEGACY_VALIDATOR
    je 4f
    call ext_store_job_take_legacy_snapshot
    jmp 5f
4:  call ext_store_job_take_legacy_receipt
5:  test rax, rax
    jz 9f
    mov r14, rax
    mov r15, rdx
    mov rdi, r13
    lea rsi, [rsp + 144]
    call ext_store_job_legacy_context
    test rax, rax
    jnz elr_fail
    mov rax, [rsp + 152]
    mov [rsp + 208], rax
    mov qword ptr [rsp + 216], 0
    mov rdi, [rsp + 144]
    test rdi, rdi
    jz 6f
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle elr_fail
    mov [rsp + 216], rax
    lea rdi, [rsp + 320]
    mov rsi, [rsp + 144]
    lea rdx, [rax + 1]
    call memcpy
6:  mov rdi, r13
    call ext_store_job_free
    test rax, rax
    jnz elr_fail
    cmp rdx, 1
    jne elr_fail
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz elr_fail
    mov edi, 1
    lea rsi, [rsp + 208]
    mov edx, 16
    call write_all
    test rax, rax
    jnz elr_fail
    mov rdx, [rsp + 216]
    test rdx, rdx
    jz 7f
    mov edi, 1
    lea rsi, [rsp + 320]
    call write_all
    test rax, rax
    jnz elr_fail
7:  mov edi, 1
    mov rsi, r14
    mov rdx, r15
    call write_all
    test rax, rax
    jnz elr_fail
    mov rdi, r14
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 304]
    jne elr_fail
    xor eax, eax
    EPILOGUE
9:
.ifdef ELR_EXPECT_FAILURE
    cmp qword ptr [r13 + ESJ_exit], ELR_EXPECT_FAILURE
    jne elr_fail
    cmp qword ptr [r13 + ESJ_error], 0
    jge elr_fail
    mov rdi, r13
    call ext_store_job_free
    test rax, rax
    jnz elr_fail
    cmp rdx, 1
    jne elr_fail
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz elr_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 304]
    jne elr_fail
    xor eax, eax
    EPILOGUE
.else
    mov rdi, r13
    call ext_store_job_free
    mov rdi, r12
    call ext_store_guard_free
    jmp elr_fail
.endif
.Lelr_child:
    mov rdi, [rbx + 8]
    lea rsi, [rip + elr_snapshot]
    call strcmp_eq
    mov rdi, [rip + g_argc]
    mov rsi, rbx
    test eax, eax
    jz 8f
    call ext_legacy_snapshot_anchored_main
    jmp .Lelf_child_done
8:  call ext_validate_legacy_anchored_main
.Lelf_child_done:
.ifdef ELR_EXPECT_FAILURE
.if ELR_EXPECT_FAILURE == 1
    cmp qword ptr [rip + elf_child_closes], 1
    jne elr_fail
.endif
.endif
    EPILOGUE
