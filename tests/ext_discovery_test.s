.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstore.inc"
.include "app/extdiscovery.inc"
.section .rodata
edt_owner: .asciz "Foo"
edt_active: .asciz "Bar"
edt_removed: .asciz "Removed"
edt_broken: .asciz "Broken"
edt_pending: .asciz "Pending"
edt_missing: .asciz "Missing"
edt_id: .ascii "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    .byte 0
edt_saved_id: .ascii "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    .byte 0
edt_mutation: .asciz ".discovery-mutation"
.text
edt_fail:
    mov edi, 73
    call sys_exit
edt_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne edt_fail
    EPILOGUE
edt_shadow:
    PROLOGUE
    mov r12, rcx
    call ext_discovery_shadow
    cmp rax, r12
    jne edt_fail
    EPILOGUE
FN main
    PROLOGUE 512
    cmp qword ptr [rip + g_argc], 3
    jne edt_fail
    mov r15, [rip + g_mem_live]
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    call edt_number
    mov [rsp + 320], rax
    cmp rax, 7
    jne 50f
    mov qword ptr [rip + edt_substituted], 1
50:
    mov qword ptr [rsp + 328], -1
    mov qword ptr [rsp + 384], 0
    mov qword ptr [rsp + 408], 0
    call edt_census
    mov [rsp + 400], rax
    mov rdi, [rbx + 8]
    mov esi, 1
    mov edx, 1
    cmp qword ptr [rsp + 320], 8
    jne 51f
    xor esi, esi
    xor edx, edx
51: xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz edt_fail
    mov r12, rax
    mov rdi, [r12 + ESG_root]
    xor esi, esi
    xor edx, edx
    call ext_store_snapshot_root_try
    test rax, rax
    jz edt_fail
    mov r13, rax
    lea rdi, [rsp + 128]
    lea rsi, [rax + ESS_tag]
    mov edx, EST_SIZE
    call memcpy
    mov rax, [r12 + ESG_epoch]
    mov [rsp + 128 + EST_epoch], rax
    mov qword ptr [rsp + 128 + EST_job], 7
    mov rdi, r13
    lea rsi, [rsp + 128]
    call ext_store_snapshot_pack_try
    test rax, rax
    jz edt_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rsp + 128]
    call ext_store_snapshot_unpack_try
    test rax, rax
    jz edt_fail
    mov r14, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r13
    call ext_store_snapshot_free
    mov rdi, r14
    mov rsi, r12
    mov rdx, [r12 + ESG_epoch]
    call ext_store_snapshot_bind
    test rax, rax
    jnz edt_fail
    mov rdi, r14
    mov rsi, r12
    call ext_discovery_begin
    test rax, rax
    jz edt_fail
    mov r13, rax
    mov qword ptr [rsp + 336], 0
1:  mov rbx, [r13 + ED_cursor]
    mov r14, [r13 + ED_count]
    mov rdi, r13
    call ext_discovery_step
    mov [rsp + 352], rax
    mov rcx, [r13 + ED_cursor]
    sub rcx, rbx
    cmp rcx, 16
    ja edt_fail
    mov rcx, [r13 + ED_count]
    sub rcx, r14
    cmp rcx, 1
    ja edt_fail
    inc qword ptr [rsp + 336]
    cmp qword ptr [rsp + 336], 5000
    ja edt_fail
    mov rax, [rsp + 352]
    test rax, rax
    js edt_fail
    jz 1b
    mov rdi, r13
    call ext_discovery_count
    mov [rsp + 368], rax
    cmp qword ptr [rsp + 320], 100
    jae .Ledt_pure
    cmp rax, 1
    jne edt_fail
    mov rdi, r13
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_active]
    mov ecx, 1
    call edt_shadow
    mov rdi, r13
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_removed]
    mov ecx, 1
    call edt_shadow
    mov rdi, r13
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_broken]
    mov ecx, 1
    call edt_shadow
    mov rdi, r13
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_pending]
    xor ecx, ecx
    call edt_shadow
    mov rdi, r13
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_missing]
    xor ecx, ecx
    call edt_shadow
    cmp qword ptr [rsp + 320], 2
    jne 2f
    mov rdi, r13
    call ext_discovery_detach
    test rax, rax
    jnz edt_fail
2:  mov rdi, r13
    xor esi, esi
    call ext_discovery_candidate_try
    mov r14, rax
    mov [rsp + 352], rdx
    mov [rsp + 360], rcx
    test r14, r14
    jz 52f
    mov rdi, r13
    mov rsi, r14
    call edt_candidate_tuple
52: mov rdi, r13
    call ext_discovery_free
    xor r13d, r13d
    cmp qword ptr [rsp + 320], 6
    jne 20f
    inc qword ptr [r12 + ESG_epoch]
    mov qword ptr [rsp + 320], 3
    mov qword ptr [rip + edt_direct], 1
20: test r14, r14
    jz .Ledt_finish
    call edt_lease_probe
    cmp rax, -11
    jne edt_fail
    cmp qword ptr [rsp + 320], 3
    jne 3f
    call edt_mutate
3:  cmp qword ptr [rsp + 320], 3
    jne 30f
    mov rdi, r14
    call ext_discovery_candidate_root
    cmp rax, -116
    jne edt_fail
    mov rdi, r14
    call edt_begin_stub
    cmp rax, -116
    jne edt_fail
    cmp qword ptr [rip + edt_accepted], 0
    jne edt_fail
30: mov rdi, rsp
    mov esi, 0xa5
    mov edx, EH_SIZE
    call memset
    mov rdi, r14
    mov rsi, rsp
    call ext_discovery_candidate_take
    mov [rsp + 352], rax
    cmp qword ptr [rsp + 320], 3
    jne 4f
    cmp rax, -116
    jne edt_fail
    mov rax, 0xa5a5a5a5a5a5a5a5
    xor ecx, ecx
31: cmp [rsp + rcx*8], rax
    jne edt_fail
    inc rcx
    cmp rcx, 5
    jb 31b
    cmp qword ptr [r14 + EDC_lease], -1
    je edt_fail
    jmp .Ledt_candidate_free
4:  test rax, rax
    jnz edt_fail
    mov rax, [r14 + EDC_payload]
    cmp [rsp + EH_root], rax
    jne edt_fail
    lea rax, [r14 + EDC_path]
    cmp [rsp + EH_dir], rax
    jne edt_fail
    lea rax, [r14 + EDC_owner]
    cmp [rsp + EH_owner], rax
    jne edt_fail
    lea rax, [r14 + EDC_name]
    cmp [rsp + EH_name], rax
    jne edt_fail
    mov rdi, [rsp + EH_root]
    lea rsi, [rsp + 256]
    call ext_root_identity
    test rax, rax
    jnz edt_fail
    lea rdi, [rsp + 256]
    lea rsi, [r14 + EDC_payloadid]
    mov edx, 32
    call memeq
    test eax, eax
    jz edt_fail
    mov rax, [rsp + EH_lease]
    mov [rsp + 328], rax
    cmp qword ptr [r14 + EDC_lease], -1
    jne edt_fail
    cmp qword ptr [rsp + 320], 4
    jne 5f
    call edt_mutate
5:  mov rdi, r14
    call ext_discovery_candidate_check
    mov [rsp + 352], rax
    cmp qword ptr [rsp + 320], 4
    jne 6f
    cmp rax, -116
    jne edt_fail
    mov rdi, r14
    call edt_begin_stub
    cmp rax, -116
    jne edt_fail
    cmp qword ptr [rip + edt_accepted], 0
    jne edt_fail
    jmp .Ledt_candidate_free
6:  test rax, rax
    jnz edt_fail
    mov rdi, r14
    call edt_begin_stub
    test rax, rax
    jnz edt_fail
    cmp qword ptr [rip + edt_accepted], 1
    jne edt_fail
    mov rdi, r14
    call ext_discovery_candidate_root
    cmp rax, [rsp + EH_root]
    jne edt_fail
    mov rdi, r14
    mov rsi, rsp
    call ext_discovery_candidate_take
    cmp rax, -2
    jne edt_fail
    cmp qword ptr [rsp + 320], 9
    jb .Ledt_candidate_free
    cmp qword ptr [rsp + 320], 10
    ja .Ledt_candidate_free
    mov rdi, r14
    call ext_discovery_candidate_check
    test rax, rax
    jnz edt_fail
    mov rdi, [rsp + EH_root]
    mov rsi, [rsp + EH_dir]
    mov rdx, [rsp + EH_owner]
    mov rcx, [rsp + EH_name]
    mov r8, [rsp + EH_lease]
    call ext_prepare_begin
    cmp qword ptr [rsp + 320], 9
    jne 53f
    test rax, rax
    jnz edt_fail
    test rdx, rdx
    jns edt_fail
    test rcx, rcx
    jnz edt_fail
    call edt_lease_probe
    cmp rax, -11
    jne edt_fail
    jmp .Ledt_candidate_free
53: test rax, rax
    jz edt_fail
    mov [rsp + 408], rax
    mov qword ptr [rsp + 328], -1
.Ledt_candidate_free:
    mov rdi, r14
    call ext_discovery_candidate_free
    test rax, rax
    jnz edt_fail
    test rdx, rdx
    jnz edt_fail
.Ledt_finish:
    cmp qword ptr [rsp + 408], 0
    je 56f
54: mov rdi, [rsp + 408]
    call ext_prepare_step
    cmp rax, 1
    je 54b
    test rax, rax
    jnz edt_fail
    test rdx, rdx
    jnz edt_fail
    call edt_lease_probe
    cmp rax, -11
    jne edt_fail
    mov rdi, [rsp + 408]
    call ext_prepare_release
    test rax, rax
    jnz edt_fail
    call edt_lease_probe
    test rax, rax
    js edt_fail
    mov rdi, rax
    call ext_root_close
    test rax, rax
    jnz edt_fail
    jmp 57f
56: cmp qword ptr [rsp + 328], 0
    jl 40f
    call edt_lease_probe
    cmp rax, -11
    jne edt_fail
40: mov rdi, [rsp + 328]
    test rdi, rdi
    js 7f
    lea rsi, [rsp + 256]
    call ext_root_identity
    test rax, rax
    jnz edt_fail
    mov rdi, [rsp + 328]
    call ext_root_close
    test rax, rax
    jnz edt_fail
    call edt_lease_probe
    test rax, rax
    js edt_fail
    mov rdi, rax
    call ext_root_close
    test rax, rax
    jnz edt_fail
7:  cmp qword ptr [rsp + 320], 3
    jne 57f
    call edt_lease_probe
    test rax, rax
    js edt_fail
    mov rdi, rax
    call ext_root_close
    test rax, rax
    jnz edt_fail
57: mov rdi, [r12 + ESG_root]
    lea rsi, [rsp + 256]
    call ext_root_identity
    test rax, rax
    jnz edt_fail
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz edt_fail
    cmp [rip + g_mem_live], r15
    jne edt_fail
    call edt_census
    cmp rax, [rsp + 400]
    jne edt_fail
    mov rax, [rsp + 336]
    mov [rsp + 376], rax
    mov edi, 1
    lea rsi, [rsp + 352]
    mov edx, 32
    call write_all
    test rax, rax
    jnz edt_fail
    xor eax, eax
    EPILOGUE
# EX metadata mutation invalidates completed candidates independently of ED lifetime.
edt_mutate:
    PROLOGUE
    cmp qword ptr [rip + edt_direct], 1
    je 1f
    mov rdi, r12
    mov rsi, [r12 + ESG_root]
    lea rdx, [rip + edt_mutation]
    mov ecx, 1
    call ext_store_dir_try
    test rax, rax
    js edt_fail
    test rdx, rdx
    jnz edt_fail
    mov rdi, rax
    call ext_root_close
    test rax, rax
    jnz edt_fail
1:  EPILOGUE

# Caller-side private preparation gate. No acceptance is possible after stale handoff.
edt_begin_stub:
    PROLOGUE
    call ext_discovery_candidate_check
    test rax, rax
    js 1f
    inc qword ptr [rip + edt_accepted]
1:  EPILOGUE
edt_lease_probe:
    mov rdi, r12
    lea rsi, [rip + edt_owner]
    lea rdx, [rip + edt_active]
    lea rcx, [rip + edt_id]
    cmp qword ptr [rip + edt_substituted], 0
    je 1f
    lea rcx, [rip + edt_saved_id]
1:  mov r8d, 1
    xor r9d, r9d
    jmp ext_store_lease_try
.Ledt_pure:
    mov rcx, [rsp + 320]
    sub rcx, 100
    cmp rax, rcx
    jne edt_fail
    mov rdi, r13
    call ext_discovery_snapshot
    test rax, rax
    jz edt_fail
    mov [rsp + 392], rax
    xor ebx, ebx
41: cmp rbx, [rsp + 368]
    jae 42f
    mov rdi, r13
    mov rsi, rbx
    call ext_discovery_row
    test rax, rax
    jz edt_fail
    mov r14, [rax + EDR_record]
    mov rdi, r13
    lea rsi, [r14 + ESR_owner]
    lea rdx, [r14 + ESR_name]
    call ext_discovery_find
    cmp rax, r14
    jne edt_fail
    test rdx, rdx
    jnz edt_fail
    mov rdi, r13
    lea rsi, [r14 + ESR_owner]
    lea rdx, [r14 + ESR_name]
    call ext_discovery_shadow
    cmp rax, 1
    jne edt_fail
    inc rbx
    jmp 41b
42: mov rdi, r13
    call ext_discovery_detach
    test rax, rax
    jnz edt_fail
    mov rdi, r13
    call ext_discovery_count
    cmp rax, [rsp + 368]
    jne edt_fail
    mov rdi, r13
    call ext_discovery_snapshot
    cmp rax, [rsp + 392]
    jne edt_fail
    cmp qword ptr [rax + ESS_proof_guard], 0
    jne edt_fail
    cmp qword ptr [rax + ESS_proof_epoch], 0
    jne edt_fail
    mov rdi, r13
    call ext_discovery_free
    mov qword ptr [rsp + 352], 0
    mov qword ptr [rsp + 360], 0
    jmp .Ledt_finish
.data
edt_accepted: .quad 0
edt_direct: .quad 0

edt_substituted: .quad 0

.text
# Actual process handle count, including stale/untaken and injected close paths.
edt_census:
    PROLOGUE 112
.ifdef WINDOWS
    mov rcx, -1
    lea rdx, [rsp + 96]
    API GetProcessHandleCount
    test eax, eax
    jz edt_fail
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
edt_candidate_tuple:
    PROLOGUE
    mov rbx, rsi
    xor esi, esi
    call ext_discovery_row
    test rax, rax
    jz edt_fail
    mov r12, rax
    mov r13, [rax + EDR_record]
    lea rdi, [rbx + EDC_owner]
    lea rsi, [r13 + ESR_owner]
    mov edx, 208
    call memeq
    test eax, eax
    jz edt_fail
    lea rdi, [rbx + EDC_expected]
    lea rsi, [r13 + ESR_index]
    mov edx, 160
    call memeq
    test eax, eax
    jz edt_fail
    mov rdi, [r12 + EDR_path]
    call strlen
    lea rdx, [rax + 1]
    mov rsi, [r12 + EDR_path]
    lea rdi, [rbx + EDC_path]
    call memeq
    test eax, eax
    jz edt_fail
    EPILOGUE
