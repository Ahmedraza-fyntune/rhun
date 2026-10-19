.bss
.p2align 3
rch_saved_ext: .zero EXT_SIZE
rch_saved_slot: .zero RT_SLOT_SIZE
rch_expected: .quad 0
.text
rch_snapshot:
    PROLOGUE
    lea rdi, [rip + rch_saved_ext]
    mov rsi, r13
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + rch_saved_slot]
    mov rsi, r14
    mov edx, RT_SLOT_SIZE
    call memcpy
    EPILOGUE
rch_same:
    PROLOGUE
    lea rdi, [rip + rch_saved_ext]
    mov rsi, r13
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz rts_fail
    lea rdi, [rip + rch_saved_slot]
    mov rsi, r14
    mov edx, RT_SLOT_SIZE
    call memeq
    test eax, eax
    jz rts_fail
    EPILOGUE
# ExpectedAX, retained TABLE/EXT/slot in RBX/R13/R14. Predicate must not mutate any source.
rch_check:
    PROLOGUE
    mov [rip + rch_expected], rdi
    call rch_snapshot
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_session_channel_check
    cmp rax, [rip + rch_expected]
    jne rts_fail
    test rax, rax
    jnz 1f
    cmp rdx, r13
    jne rts_fail
    jmp 2f
1:  test rdx, rdx
    jnz rts_fail
2:  call rch_same
    EPILOGUE
rch_cases:
    PROLOGUE 16
    mov qword ptr [rip + rts_stage], 220
    test qword ptr [r14 + RTS_flags], RTSF_CHANNEL_BOUND
    jz rts_fail
    xor edi, edi
    call rch_check
    xor r12d, r12d
.Lrch_fields:
    lea r15, [rip + rch_fields]
    mov rax, r12
    shl rax, 5
    add r15, rax
    lea rax, [r12 + 221]
    mov [rip + rts_stage], rax
    mov rcx, [r15]
    mov rax, [r13 + rcx]
    mov [rsp], rax
    mov rax, [r15 + 8]
    cmp qword ptr [r15 + 24], 4
    jne 1f
    mov [r13 + rcx], eax
    jmp 2f
1:  mov [r13 + rcx], rax
2:  mov rdi, [r15 + 16]
    call rch_check
    mov rax, [rsp]
    mov rcx, [r15]
    cmp qword ptr [r15 + 24], 4
    jne 3f
    mov [r13 + rcx], eax
    jmp 4f
3:  mov [r13 + rcx], rax
4:  inc r12
    cmp r12, 21
    jb .Lrch_fields
    # Ownership survives logical session and TABLE revocation; no grant is restored.
    mov qword ptr [rip + rts_stage], 243
    mov r12, [r14 + RTS_grantSession]
    mov qword ptr [r14 + RTS_grantSession], 0
    call rts_check
    cmp rax, -116
    jne rts_fail
    xor edi, edi
    call rch_check
    mov [r14 + RTS_grantSession], r12
    mov r12, [rbx + RT_flags]
    or qword ptr [rbx + RT_flags], RTF_CLOSED
    call rts_check
    cmp rax, -116
    jne rts_fail
    mov qword ptr [r14 + RTS_state], RTS_DRAINING
    xor edi, edi
    call rch_check
    mov qword ptr [r14 + RTS_state], RTS_ACTIVE
    mov [rbx + RT_flags], r12
    mov r12, [r14 + RTS_flags]
    and qword ptr [r14 + RTS_flags], ~RTSF_CHANNEL_BOUND
    mov rdi, -116
    call rch_check
    mov [r14 + RTS_flags], r12
    # Exact tuple mismatch is never classified as proven channel closure.
    mov qword ptr [rip + rts_stage], 244
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    inc rdx
    call rt_session_channel_check
    cmp rax, -116
    jne rts_fail
    test rdx, rdx
    jnz rts_fail
    mov r12, [rbx + RT_stableExtBase]
    mov qword ptr [rbx + RT_stableExtBase], 0
    mov rdi, -116
    call rch_check
    mov [rbx + RT_stableExtBase], r12
    lea rax, [r12 + EXT_SIZE]
    mov [rbx + RT_stableExtBase], rax
    mov rdi, -116
    call rch_check
    mov [rbx + RT_stableExtBase], r12
    mov qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT - 1
    mov rdi, -116
    call rch_check
    mov qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    mov qword ptr [rbx + RT_stableExtBase], -32
    mov qword ptr [rip + g_exts + VEC_ptr], -32
    mov rdi, -116
    call rch_check
    mov [rbx + RT_stableExtBase], r12
    mov [rip + g_exts + VEC_ptr], r12
    call rch_transport
    EPILOGUE
.section .rodata
.p2align 3
rch_fields:
    .quad EXT_disabled,1,0,4
    .quad EXT_catalog_state,2,0,4
    .quad EXT_activation_stale,1,0,4
    .quad EXT_status,ES_STOPPING,0,4
    .quad EXT_status,ES_STOPPED,-11,4
    .quad EXT_retiring,1,-11,4
    .quad EXT_in,-1,-32,4
    .quad EXT_in_closed_at,42,-11,8
    .quad EXT_host_cleanup_mask,1,-11,4
    .quad EXT_host_cleanup_mask,256,-11,4
    .quad EXT_host_cleanup_mask,0x80000000,-11,4
    .quad EXT_out,-1,-11,4
    .quad EXT_host_child_in,0,-11,4
    .quad EXT_host_child_out,0,-11,4
    .quad EXT_activation_owner,0,-116,8
    .quad EXT_identity_owner,0,-116,8
    .quad EXT_keeper,444,-116,8
    .quad EXT_activation_plan,0,-116,8
    .quad EXT_startaccepted,0,-116,4
    .quad EXT_activation_required,0,-116,4
    .quad EXT_status,ES_REMOVED,-11,4
