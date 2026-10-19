# Resumable candidate cleanup. Pending native storage is never retired speculatively.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extchoicesdisk.inc"
.text

# Latch the first negative cleanup result, preferring primary over secondary.
FN ext_choices_record_cleanup
    cmp qword ptr [rdi + ECP_cleanup_error], 0
    jne 2f
    test rsi, rsi
    js 1f
    mov rsi, rdx
    test rsi, rsi
    jns 2f
1:  mov [rdi + ECP_cleanup_error], rsi
2:  ret

# cleanup_step(ECP)->0 complete/-115 retained, RDX first cleanup/observation failure.
FN ext_choices_cleanup_step
    test rdi, rdi
    jz .Lecc_invalid
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + ECP_state], ECP_PENDING
    je .Lecc_publish_pending
    cmp qword ptr [rbx + ECP_cleanup_done], 1
    je .Lecc_done
    cmp qword ptr [rbx + ECP_state], ECP_PREPARED
    ja 1f
    mov qword ptr [rbx + ECP_state], ECP_FAILED
    mov qword ptr [rbx + ECP_result], -125 # cleanup withdraws publication authority.
1:  cmp qword ptr [rbx + ECP_delete + ESU_pending], 1
    je .Lecc_poll
    cmp qword ptr [rbx + ECP_cleanup_phase], 0
    jne .Lecc_close
    mov qword ptr [rbx + ECP_cleanup_phase], 1
    cmp qword ptr [rbx + ECP_source], -1
    je .Lecc_security
    cmp qword ptr [rbx + ECP_consumed], 1
    je .Lecc_close
    cmp qword ptr [rbx + ECP_state], ECP_UNCERTAIN
    je .Lecc_close
    cmp qword ptr [rbx + ECP_identity_known], 1
    jne .Lecc_unidentified
    mov rdi, rbx
    call ext_choices_stage_identity
    cmp rax, 1
    je .Lecc_close             # a clean missing name is not permission to delete another.
    test rax, rax
    js .Lecc_record_close
.ifdef WINDOWS
    mov rdi, [rbx + ECP_source]
    mov qword ptr [rbx + ECP_source], -1
    lea rsi, [rbx + ECP_delete]
    call ext_store_unlink_handle_try
.else
    mov rax, [rbx + ECP_guard]
    mov rdi, [rax + ECG_root]
    lea rsi, [rbx + ECP_name]
    lea rdx, [rbx + ECP_delete]
    call ext_store_raw_unlink
.endif
    cmp rax, -115
    je .Lecc_delete_pending
    jmp .Lecc_record_close
.Lecc_poll:
    lea rdi, [rbx + ECP_delete]
    call ext_store_unlink_poll
    cmp rax, -115
    je .Lecc_delete_pending
    jmp .Lecc_record_close
.Lecc_unidentified:
    mov rax, -116              # preserve an unclassifiable exclusively-created name.
    xor edx, edx
.Lecc_record_close:
    mov rdi, rbx
    mov rsi, rax
    call ext_choices_record_cleanup
.Lecc_close:
    mov rdi, [rbx + ECP_source]
    cmp rdi, -1
    je .Lecc_security
    mov qword ptr [rbx + ECP_source], -1
    call ext_root_close
    mov rsi, rax
    xor edx, edx
    mov rdi, rbx
    call ext_choices_record_cleanup
.Lecc_security:
    mov rdi, rbx
    call ext_choices_security_free
    mov rsi, rax
    xor edx, edx
    mov rdi, rbx
    call ext_choices_record_cleanup
    cmp qword ptr [rbx + ECP_security], 0
    jne .Lecc_retained
    cmp qword ptr [rbx + ECP_sid], 0
    jne .Lecc_retained
    mov qword ptr [rbx + ECP_cleanup_done], 1
.Lecc_done:
    xor eax, eax
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_delete_pending:
    mov rdx, [rbx + ECP_delete + ESU_observation]
    test rdx, rdx
    js 1f
    mov rdx, [rbx + ECP_cleanup_error]
1:  mov rax, -115
    EPILOGUE
.Lecc_publish_pending:
    mov rdx, [rbx + ECP_observation]
    mov rax, -115
    EPILOGUE
.Lecc_retained:
    mov rax, -115
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_invalid:
    mov rax, -22
    xor edx, edx
    ret

# free(ECP)->0/first cleanup error after release, -EBUSY retains ALL ownership.
FN ext_choices_free
    test rdi, rdi
    jz .Lecc_free_empty
    cmp qword ptr [rdi + ECP_cleanup_done], 1
    jne .Lecc_free_busy
    cmp qword ptr [rdi + ECP_state], ECP_PENDING
    je .Lecc_free_busy
    cmp qword ptr [rdi + ECP_delete + ESU_pending], 0
    jne .Lecc_free_busy
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + ECP_cleanup_error]
    mov rdi, [rbx + ECP_old]
    call ext_choices_snapshot_free
    mov rdi, [rbx + ECP_bytes]
    call mem_free
    mov rdi, [rbx + ECP_scratch]
    call mem_free
    mov r13, [rbx + ECP_guard]
    cmp [r13 + ECG_active], rbx
    jne 1f
    mov qword ptr [r13 + ECG_active], 0
    cmp qword ptr [r13 + ECG_epoch], -1
    je 1f
    inc qword ptr [r13 + ECG_epoch]
    jmp 2f
1:  test r12, r12
    jnz 2f
    mov r12, -116
2:  mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
.Lecc_free_empty:
    xor eax, eax
    ret
.Lecc_free_busy:
    mov rax, -16
    ret
