# Constructor-boundary audit only. No invented release refusal or product ABI change.
.bss
.p2align 3
eia_drop_calls: .quad 0
eia_admit_calls: .quad 0
eia_admit_fail_at: .quad 0
.text
FN prep_global_admit
    cmp qword ptr [rip + af_armed], 1
    jne eia_real_global_admit
    inc qword ptr [rip + eia_admit_calls]
    mov rax, [rip + eia_admit_calls]
    cmp rax, [rip + eia_admit_fail_at]
    jne eia_real_global_admit
    mov rax, -EV_RESOURCE
    ret
FN ext_prepare_owner_release_deferred
    cmp qword ptr [rip + af_armed], 1
    jne eia_real_eo_release
    PROLOGUE 32
    mov rbx, rdi
    mov rax, [rip + prep_retire_ready_count]
    mov [rsp], rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 8], rax
    mov rax, [rip + prep_total_charge]
    mov [rsp + 16], rax
    mov rax, [rbx + EO_used]
    mov [rsp + 24], rax
    inc qword ptr [rip + eia_drop_calls]
    cmp qword ptr [rbx - RD_SIZE + RD_object], rbx
    jne eia_bad
    cmp qword ptr [rbx - RD_SIZE + RD_kind], RD_EO
    jne eia_bad
    cmp qword ptr [rbx - RD_SIZE + RD_state], RD_ACTIVE
    jne eia_bad
    cmp qword ptr [rbx + EO_lease], -1
    jne eia_bad
    cmp qword ptr [rbx + EO_deferred], 1
    jne eia_bad
    cmp qword ptr [rbx + EO_cap], PREP_CAP
    jne eia_bad
    mov r12, [rbx + EO_refs]
    cmp r12, 1
    je 1f
    cmp r12, 2
    jne eia_bad
1:  call eia_real_eo_release
    test rax, rax
    jnz eia_bad
    cmp rdx, 1
    jne eia_bad
    mov r14, [rsp + 8]
    cmp [rip + g_mem_live], r14
    jne eia_bad
    mov r14, [rsp + 16]
    cmp [rip + prep_total_charge], r14
    jne eia_bad
    mov r14, [rsp + 24]
    cmp [rbx + EO_used], r14
    jne eia_bad
    cmp r12, 1
    je 2f
    cmp qword ptr [rbx + EO_refs], 1
    jne eia_bad
    cmp qword ptr [rbx - RD_SIZE + RD_state], RD_ACTIVE
    jne eia_bad
    mov r14, [rsp]
    cmp [rip + prep_retire_ready_count], r14
    jne eia_bad
    EPILOGUE
2:  # Last ref was transferred to READY, never physically freed in this call.
    cmp qword ptr [rbx + EO_refs], 0
    jne eia_bad
    cmp qword ptr [rbx - RD_SIZE + RD_state], RD_READY
    jne eia_bad
    mov r14, [rsp]
    inc r14
    cmp [rip + prep_retire_ready_count], r14
    jne eia_bad
    EPILOGUE
eia_bad:
    mov edi, 91
    jmp sys_exit
