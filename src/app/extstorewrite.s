# Immutable selection preparation. The root guard stays owned by the caller.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extvalidate.inc"
.section .rodata
.Lesw_installed: .asciz ".installed"
.Lesw_pending_prefix: .ascii ".pending-"
.bss
.p2align 3
.Lesw_serial: .quad 0
.text
# Record first mandatory cleanup error without replacing a primary operation error.
.Lesw_cleanup:
    test rax, rax
    jns 1f
    cmp qword ptr [rbx + ESW_cleanup_error], 0
    jne 1f
    mov [rbx + ESW_cleanup_error], rax
1:  ret

# Pure check of a complete snapshot bound to this still-live exclusive guard.
# (ESW,ESS)->0/-errno. No IO, allocation, or mutation of snapshot.
.Lesw_snapshot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rdi + ESW_guard]
    cmp qword ptr [r13 + ESG_exclusive], 1
    jne 7f
    cmp [r12 + ESS_proof_guard], r13
    jne 8f
    mov rax, [r13 + ESG_epoch]
    cmp [r12 + ESS_proof_epoch], rax
    jne 8f
    mov rdi, r12
    lea rsi, [rbx + ESW_owner]
    lea rdx, [rbx + ESW_name]
    call ext_store_snapshot_find
    mov r14, rax
    test rax, rax
    jz 1f
    mov rax, [r14 + ESR_status]
    test rax, rax
    js 9f
    cmp qword ptr [rbx + ESW_expected_present], 0
    je 2f
    lea rdi, [r14 + ESR_index]
    lea rsi, [rbx + ESW_expected]
    mov edx, EXI_SIZE
    call memeq
    test eax, eax
    jz 8f
    jmp 3f
2:  cmp qword ptr [r14 + ESR_generation], 0
    jne 8f
    jmp 3f
1:  cmp qword ptr [rbx + ESW_expected_present], 0
    jne 8f
    cmp qword ptr [r12 + ESS_identity_count], ES_LIMIT
    jae 6f
    # New physical identity consumes one owner entry, and perhaps root entry.
    xor r15d, r15d
11: cmp r15, [r12 + ESS_owners + VEC_len]
    jae 12f
    mov rax, r15
    imul rax, ESO_SIZE
    add rax, [r12 + ESS_owners + VEC_ptr]
    mov r14, rax
    mov rdi, rax
    lea rsi, [rbx + ESW_owner]
    call ext_store_name_cmp
    test rax, rax
    jz 13f
    inc r15
    jmp 11b
12: cmp qword ptr [r12 + ESS_root_entries], ES_LIMIT
    jae 6f
    jmp 14f
13: cmp qword ptr [r14 + ESO_entries], ES_LIMIT
    jae 6f
14: xor r14d, r14d
3:  cmp dword ptr [rbx + ESW_next + EXI_flags], EXI_ACTIVE
    jne 5f
    test r14, r14
    jz 4f
    cmp qword ptr [r14 + ESR_generation], 0
    je 4f
    cmp dword ptr [r14 + ESR_index + EXI_flags], EXI_ACTIVE
    je 5f
4:  cmp qword ptr [r12 + ESS_live], ES_LIVE_LIMIT
    jae 6f
5:  xor eax, eax
9:  EPILOGUE
6:  mov rax, -27
    EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -116
    EPILOGUE

# Enumeration callback counts every native name in scanner and records valid generations.
.Lesw_generation:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rdi + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js 4f
    mov rdi, r12
    mov rsi, r13
    call ext_index_filename_parse
    test rax, rax
    jz 3f
    cmp qword ptr [rbx + ESW_scan_collect], 0
    je 1f
    mov rcx, [rbx + ESW_prune_count]
    cmp rcx, ES_LIMIT
    jae 5f
    mov [rbx + rcx*8 + ESW_plan], rax
    inc qword ptr [rbx + ESW_prune_count]
1:  cmp rax, [rbx + ESW_scan_max]
    jbe 2f
    mov rcx, [rbx + ESW_scan_max]
    mov [rbx + ESW_scan_second], rcx
    mov [rbx + ESW_scan_max], rax
    jmp 3f
2:  cmp rax, [rbx + ESW_scan_second]
    jbe 3f
    mov [rbx + ESW_scan_second], rax
3:  xor eax, eax
4:  EPILOGUE
5:  mov rax, -27
    EPILOGUE

# Complete fresh identity scan, with checked stream cleanup.
.Lesw_scan:
    PROLOGUE 16
    mov rbx, rdi
    mov qword ptr [rbx + ESW_scan_max], 0
    mov qword ptr [rbx + ESW_scan_second], 0
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js 4f
    mov rdi, [rbx + ESW_identity_dir]
    call ext_root_reopen_dir
    test rax, rax
    js 5f
    mov r12, rax
    mov rdi, rax
    mov esi, ES_LIMIT
    lea rdx, [rip + .Lesw_generation]
    mov rcx, rbx
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    mov [rsp], rax
    mov [rbx + ESW_native_count], rdx
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rsp], 0
    jne 2f
    mov [rsp], rax
    jmp 3f
2:  call .Lesw_cleanup
3:  mov rax, [rsp]
4:  EPILOGUE
5:  mov [rsp], rax
    mov rax, rdx
    call .Lesw_cleanup
    jmp 3b

# ext_store_prepare_begin_try(guard,owner,name,expectedOrNULL,next160,boundESS)
# ->owned ESW/0,rdx primary,rcx cleanup. No completed-record deletions here.
FN ext_store_prepare_begin_try
    test rdi, rdi
    jz .Lesw_invalid
    test r8, r8
    jz .Lesw_invalid
    test r9, r9
    jz .Lesw_invalid
    cmp qword ptr [rdi + ESG_exclusive], 1
    jne .Lesw_invalid
    cmp qword ptr [rdi + ESG_prepared], 0
    jne .Lesw_busy
    PROLOGUE 448
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    # Validate and own keys before any mutation or pointer publication.
    mov rdi, rsp
    call ext_store_record_init
    test rax, rax
    js .Lesw_begin_early
    xor r15d, r15d
    test r12, r12
    jz 1f
    mov rdi, r12
    mov esi, EXI_SIZE
    mov rdx, [r12 + EXI_generation]
    call ext_index_check
    test eax, eax
    jz .Lesw_begin_invalid
    mov r15, [r12 + EXI_generation]
1:  cmp r15, -1
    je .Lesw_begin_overflow
    inc r15
    mov rdi, r13
    mov esi, EXI_SIZE
    mov rdx, r15
    call ext_index_check
    test eax, eax
    jz .Lesw_begin_invalid
    mov edi, ESW_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lesw_begin_oom
    mov r15, rax
    mov [rax + ESW_guard], rbx
    mov qword ptr [rax + ESW_identity_dir], -1
    mov qword ptr [rax + ESW_owner_dir], -1
    mov qword ptr [rax + ESW_installed_dir], -1
    mov qword ptr [rax + ESW_source], -1
    mov [rbx + ESG_prepared], rax
    lea rdi, [rax + ESW_owner]
    mov rsi, rsp
    mov edx, 208
    call memcpy
    lea rdi, [r15 + ESW_next]
    mov rsi, r13
    mov edx, EXI_SIZE
    call memcpy
    test r12, r12
    jz 2f
    mov qword ptr [r15 + ESW_expected_present], 1
    lea rdi, [r15 + ESW_expected]
    mov rsi, r12
    mov edx, EXI_SIZE
    call memcpy
2:  mov rdi, r15
    mov rsi, r14
    call .Lesw_snapshot
    test rax, rax
    js .Lesw_begin_fail
    lea rdi, [r15 + ESW_final]
    mov rsi, [r15 + ESW_next + EXI_generation]
    call ext_index_filename_format
    test eax, eax
    jz .Lesw_begin_bad_owned
    lea rdi, [rsp + 208]
    lea rsi, [r15 + ESW_owner]
    call .Lesw_encode
    lea rdi, [rsp]
    lea rsi, [r15 + ESW_name]
    call .Lesw_encode
    mov rdi, rbx
    mov rsi, [rbx + ESG_root]
    lea rdx, [rip + .Lesw_installed]
    mov ecx, 1
    call ext_store_dir_try
    test rax, rax
    js .Lesw_begin_open_fail
    mov [r15 + ESW_installed_dir], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rsp + 208]
    mov ecx, 1
    call ext_store_dir_try
    test rax, rax
    js .Lesw_begin_open_fail
    mov [r15 + ESW_owner_dir], rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rsp
    mov ecx, 1
    call ext_store_dir_try
    test rax, rax
    js .Lesw_begin_open_fail
    mov [r15 + ESW_identity_dir], rax
    mov qword ptr [r15 + ESW_scan_collect], 1
    mov rdi, r15
    call .Lesw_scan
    test rax, rax
    js .Lesw_begin_fail
    mov rax, [r15 + ESW_scan_max]
    mov [r15 + ESW_old_max], rax
    mov rcx, [r15 + ESW_scan_second]
    mov [r15 + ESW_old_second], rcx
    xor ecx, ecx
    cmp qword ptr [r15 + ESW_expected_present], 0
    je 3f
    mov rcx, [r15 + ESW_expected + EXI_generation]
3:  cmp rax, rcx
    jne .Lesw_begin_stale
    mov rax, r15
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesw_begin_open_fail:
    mov [rsp + 432], rax
    mov rbx, r15
    mov rax, rdx
    call .Lesw_cleanup
    mov rax, [rsp + 432]
.Lesw_begin_fail:
    mov r14, rax
    mov rdi, r15
    call ext_store_prepare_free
    mov rcx, rax
    mov rdx, r14
    xor eax, eax
    EPILOGUE
.Lesw_begin_stale:
    mov rax, -116
    jmp .Lesw_begin_fail
.Lesw_begin_bad_owned:
    mov rax, -22
    jmp .Lesw_begin_fail
.Lesw_begin_invalid:
    mov rax, -22
    jmp .Lesw_begin_early
.Lesw_begin_oom:
    mov rax, -12
    jmp .Lesw_begin_early
.Lesw_begin_overflow:
    mov rax, -75
.Lesw_begin_early:
    mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
.Lesw_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    ret
.Lesw_busy:
    xor eax, eax
    mov rdx, -16
    xor ecx, ecx
    ret
# encode(dst201,key): keys have already been validated.
.Lesw_encode:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call ext_store_identity_len
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call ext_store_identity_encode
    EPILOGUE

# Advance guard epoch before every shared namespace mutation.
.Lesw_mutate:
    mov rax, [rdi + ESW_guard]
    cmp qword ptr [rax + ESG_epoch], -1
    je 1f
    inc qword ptr [rax + ESG_epoch]
    xor eax, eax
    ret
1:  mov rax, -75
    ret

# unlink(ESW,basename): persistent native request. No pathname reopen on poll.
.Lesw_unlink:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + ESW_delete + ESU_pending], 0
    je 1f
    lea rdi, [rbx + ESW_delete]
    call ext_store_unlink_poll
    EPILOGUE
1:  mov rdi, [rbx + ESW_identity_dir]
    mov rsi, r12
    lea rdx, [rbx + ESW_delete]
    call ext_store_raw_unlink
    EPILOGUE

# ext_store_prepare_step(ESW,maxDeletes1..8)->1 PREPARED,0 more,negative failure.
FN ext_store_prepare_step
    test rdi, rdi
    jz .Lesw_scalar_invalid
    cmp rsi, 1
    jb .Lesw_scalar_invalid
    cmp rsi, 8
    ja .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_state], ESW_PREPARING
    jne .Lesw_scalar_invalid
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
.Lesw_prune_loop:
    mov r13, [rbx + ESW_prune_cursor]
    cmp r13, [rbx + ESW_prune_count]
    jae .Lesw_prune_done
    mov r14, [rbx + r13*8 + ESW_plan]
    test r14, r14
    jz .Lesw_prune_skip
    cmp r14, [rbx + ESW_old_max]
    je .Lesw_prune_skip
    cmp r14, [rbx + ESW_old_second]
    je .Lesw_prune_skip
    test r12, r12
    jz .Lesw_step_more
    cmp qword ptr [rbx + ESW_delete + ESU_pending], 0
    jne 91f
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_step_bad
91: mov rdi, rsp
    mov rsi, r14
    call ext_index_filename_format
    mov rdi, rbx
    call .Lesw_mutate
    test rax, rax
    js .Lesw_step_bad
    mov qword ptr [rbx + ESW_delete_kind], 1
    mov rdi, rbx
    mov rsi, rsp
    call .Lesw_unlink
    cmp rax, -115
    je .Lesw_step_more
    test rax, rax
    js .Lesw_step_open_bad
    mov qword ptr [rbx + r13*8 + ESW_plan], 0
    dec r12
.Lesw_prune_skip:
    inc qword ptr [rbx + ESW_prune_cursor]
    jmp .Lesw_prune_loop
.Lesw_step_more:
    xor eax, eax
    EPILOGUE
.Lesw_prune_done:
    mov qword ptr [rbx + ESW_scan_collect], 0
    mov rdi, rbx
    call .Lesw_scan
    test rax, rax
    js .Lesw_step_bad
    mov rax, [rbx + ESW_scan_max]
    cmp rax, [rbx + ESW_old_max]
    jne .Lesw_step_stale
    mov rax, [rbx + ESW_scan_second]
    cmp rax, [rbx + ESW_old_second]
    jne .Lesw_step_stale
    cmp qword ptr [rbx + ESW_native_count], ES_LIMIT
    jae .Lesw_step_full
    # Refuse every preexisting destination, including native case aliases.
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_step_bad
    mov rdi, [rbx + ESW_identity_dir]
    lea rsi, [rbx + ESW_final]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    cmp rax, -2
    je 1f
    test rax, rax
    js .Lesw_step_open_bad
    mov rdi, rax
    call ext_root_close
    call .Lesw_cleanup
    mov rax, -17
    jmp .Lesw_step_bad
1:  test rdx, rdx
    js .Lesw_step_open_bad
    mov r15d, 8
.Lesw_pending_retry:
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_step_bad
    cmp qword ptr [rip + .Lesw_serial], -1
    je .Lesw_step_overflow
    inc qword ptr [rip + .Lesw_serial]
    lea rdi, [rbx + ESW_pending]
    lea rsi, [rip + .Lesw_pending_prefix]
    mov edx, 9
    call memcpy
    call ext_store_raw_pid
    test rax, rax
    jle .Lesw_step_bad
    mov rsi, rax
    mov rdi, rsp
    call ext_index_filename_format
    lea rdi, [rbx + ESW_pending + 9]
    mov rsi, rsp
    mov edx, 16
    call memcpy
    mov byte ptr [rbx + ESW_pending + 25], '-'
    mov rdi, rsp
    mov rsi, [rip + .Lesw_serial]
    call ext_index_filename_format
    lea rdi, [rbx + ESW_pending + 26]
    mov rsi, rsp
    mov edx, 16
    call memcpy
    mov byte ptr [rbx + ESW_pending + 42], 0
    mov rdi, rbx
    call .Lesw_mutate
    test rax, rax
    js .Lesw_step_bad
    mov rdi, [rbx + ESW_identity_dir]
    lea rsi, [rbx + ESW_pending]
    mov edx, ER_FILE
    mov ecx, ER_WRITE | ER_CREATE | ER_EXCL | ER_DELETE
    mov r8d, 0600
    call ext_root_open_at
    cmp rax, -17
    jne 2f
    test rdx, rdx
    js .Lesw_step_open_bad
    dec r15
    jnz .Lesw_pending_retry
    jmp .Lesw_step_bad
2:  test rax, rax
    js .Lesw_step_open_bad
    mov r14, rax
    mov qword ptr [rbx + ESW_pending_exists], 1
    mov [rbx + ESW_source], r14
    mov qword ptr [rbx + ESW_source_owned], 1
    mov rdi, r14
    lea rsi, [rbx + ESW_pending_id]
    call ext_root_identity
    test rax, rax
    js .Lesw_step_bad
    mov qword ptr [rbx + ESW_pending_id_set], 1
    xor r13d, r13d
.Lesw_write_loop:
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_write_close
    mov rdi, r14
    lea rsi, [rbx + r13 + ESW_next]
    mov edx, EXI_SIZE
    sub rdx, r13
    call ext_store_raw_write
    cmp rax, -4
    je .Lesw_write_loop
    test rax, rax
    js .Lesw_write_close
    jz .Lesw_write_zero
    add r13, rax
    cmp r13, EXI_SIZE
    jb .Lesw_write_loop
    ja .Lesw_write_zero
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_write_close
    mov rdi, r14
    call ext_store_raw_sync
.Lesw_write_close:
    mov r13, rax
    mov qword ptr [rbx + ESW_source], -1
    mov rdi, r14
    call ext_root_close
    test r13, r13
    jns 3f
    call .Lesw_cleanup
    mov rax, r13
3:  test rax, rax
    js .Lesw_step_bad
.ifdef WINDOWS
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js .Lesw_step_bad
    mov rdi, [rbx + ESW_identity_dir]
    lea rsi, [rbx + ESW_pending]
    mov edx, ER_FILE
    mov ecx, ER_DELETE
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Lesw_step_open_bad
    mov [rbx + ESW_source], rax
    mov qword ptr [rbx + ESW_source_owned], 0
    mov rdi, rax
    lea rsi, [rbx + ESW_stat_buf]
    call ext_root_identity
    test rax, rax
    js .Lesw_step_bad
    lea rdi, [rbx + ESW_stat_buf]
    lea rsi, [rbx + ESW_pending_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lesw_step_stale
    mov qword ptr [rbx + ESW_source_owned], 1
    mov rax, [rbx + ESW_identity_dir]
    mov [rbx + ESW_rename_info + 8], rax
    mov dword ptr [rbx + ESW_rename_info + 16], EXI_FILENAME_LEN * 2
    xor ecx, ecx
4:  movzx eax, byte ptr [rbx + rcx + ESW_final]
    mov word ptr [rbx + rcx*2 + ESW_rename_info + 20], ax
    inc ecx
    cmp ecx, EXI_FILENAME_LEN
    jb 4b
.endif
    mov qword ptr [rbx + ESW_state], ESW_PREPARED
    mov eax, 1
    EPILOGUE
.Lesw_write_zero:
    mov rax, -5
    jmp .Lesw_write_close
.Lesw_step_open_bad:
    mov r13, rax
    mov rax, rdx
    call .Lesw_cleanup
    mov rax, r13
.Lesw_step_bad:
    mov qword ptr [rbx + ESW_state], ESW_FAILED
    EPILOGUE
.Lesw_step_stale:
    mov rax, -116
    jmp .Lesw_step_bad
.Lesw_step_full:
    mov rax, -27
    jmp .Lesw_step_bad
.Lesw_step_overflow:
    mov rax, -75
    jmp .Lesw_step_bad
.Lesw_scalar_invalid:
    mov rax, -22
    ret

# Off-editor convenience wrapper only. Editor uses bounded begin/step calls.
FN ext_store_prepare_try
    PROLOGUE
    call ext_store_prepare_begin_try
    test rax, rax
    jz 3f
    mov rbx, rax
1:  mov rdi, rbx
    mov esi, 8
    call ext_store_prepare_step
    test rax, rax
    jz 1b
    js 2f
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
3:  EPILOGUE
2:  mov r12, rax
21: mov rdi, rbx
    call ext_store_prepare_free
    cmp rax, -16
    je 21b
    mov rcx, rax
    mov rdx, r12
    xor eax, eax
    EPILOGUE

# ext_store_ready_try(ESW,newBoundESS)->0/-errno. Pure, no IO/allocation.
FN ext_store_ready_try
    test rdi, rdi
    jz .Lesw_scalar_invalid
    test rsi, rsi
    jz .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_state], ESW_PREPARED
    jne .Lesw_scalar_invalid
    PROLOGUE
    mov rbx, rdi
    call .Lesw_snapshot
    test rax, rax
    js 1f
    mov rcx, [rbx + ESW_guard]
    mov rcx, [rcx + ESG_epoch]
    mov [rbx + ESW_ready_epoch], rcx
    mov qword ptr [rbx + ESW_state], ESW_READY
1:  EPILOGUE

# ext_store_prepare_free(ESW)->first cleanup error. Caller still owns ESG.
# INDETERMINATE/BLOCKED preserve metadata for diagnosis; async IOSB stays owned.
FN ext_store_prepare_free
    test rdi, rdi
    jz 8f
    cmp qword ptr [rdi + ESW_async], 0
    jne 9f
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + ESW_delete + ESU_pending], 0
    je 1f
    lea rdi, [rbx + ESW_delete]
    call ext_store_unlink_poll
    cmp rax, -115
    je 10f
    call .Lesw_cleanup
    mov rax, rdx
    call .Lesw_cleanup
    cmp qword ptr [rbx + ESW_delete_kind], 2
    jne 1f
    mov qword ptr [rbx + ESW_pending_exists], 0
1:  cmp qword ptr [rbx + ESW_pending_exists], 0
    je 3f
    mov rax, [rbx + ESW_state]
    cmp rax, ESW_COMMITTED
    je 3f
    cmp rax, ESW_BLOCKED
    je 3f
    cmp rax, ESW_INDETERMINATE
    je 3f
    mov rdi, rbx
    call .Lesw_mutate
    test rax, rax
    js 2f
    mov qword ptr [rbx + ESW_delete_kind], 2
.ifdef WINDOWS
    mov rdi, [rbx + ESW_source]
    cmp rdi, -1
    je 15f
    cmp qword ptr [rbx + ESW_source_owned], 1
    je 11f
    mov qword ptr [rbx + ESW_source], -1
    call ext_root_close
    call .Lesw_cleanup
15: mov rdi, [rbx + ESW_identity_dir]
    lea rsi, [rbx + ESW_pending]
    mov edx, ER_FILE
    mov ecx, ER_DELETE
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js 12f
    mov [rbx + ESW_source], rax
    cmp qword ptr [rbx + ESW_pending_id_set], 1
    jne 13f
    mov rdi, rax
    lea rsi, [rbx + ESW_stat_buf]
    call ext_root_identity
    test rax, rax
    js 2f
    lea rdi, [rbx + ESW_stat_buf]
    lea rsi, [rbx + ESW_pending_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz 13f
    mov rdi, [rbx + ESW_source]
11: mov qword ptr [rbx + ESW_source], -1
    lea rsi, [rbx + ESW_delete]
    call ext_store_unlink_handle_try
    jmp 14f
13: mov rax, -116
    jmp 2f
12: mov r12, rdx
    call .Lesw_cleanup
    mov rax, r12
.else
    mov rdi, rbx
    lea rsi, [rbx + ESW_pending]
    call .Lesw_unlink
.endif
14: cmp rax, -115
    je 10f
    call .Lesw_cleanup
    mov rax, rdx
2:  call .Lesw_cleanup
3:  mov rdi, [rbx + ESW_source]
    cmp rdi, -1
    je 31f
    mov qword ptr [rbx + ESW_source], -1
    call ext_root_close
    call .Lesw_cleanup
31: mov rdi, [rbx + ESW_identity_dir]
    cmp rdi, -1
    je 4f
    call ext_root_close
    call .Lesw_cleanup
4:  mov rdi, [rbx + ESW_owner_dir]
    cmp rdi, -1
    je 5f
    call ext_root_close
    call .Lesw_cleanup
5:  mov rdi, [rbx + ESW_installed_dir]
    cmp rdi, -1
    je 6f
    call ext_root_close
    call .Lesw_cleanup
6:  mov r12, [rbx + ESW_cleanup_error]
    mov rax, [rbx + ESW_guard]
    mov qword ptr [rax + ESG_prepared], 0
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
10: mov rax, -16
    EPILOGUE
8:  xor eax, eax
    ret
9:  mov rax, -16
    ret

# ext_store_commit_try(READY ESW,purePrecommitFn,user)->0 only COMMITTED.
# After callback approves, success performs exactly one rooted native rename.
FN ext_store_commit_try
    test rdi, rdi
    jz .Lesw_scalar_invalid
    test rsi, rsi
    jz .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_state], ESW_READY
    jne .Lesw_scalar_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + ESW_guard]
    cmp qword ptr [r14 + ESG_exclusive], 1
    jne .Lesw_commit_invalid
    cmp [r14 + ESG_prepared], rbx
    jne .Lesw_commit_stale
    mov rax, [rbx + ESW_ready_epoch]
    cmp [r14 + ESG_epoch], rax
    jne .Lesw_commit_stale
    cmp rax, -1
    je .Lesw_commit_overflow
    mov rdi, r14
    call ext_store_cancel
    test rax, rax
    js .Lesw_commit_return
    mov rdi, r13
    mov rsi, rbx
    call r12
    test rax, rax
    js .Lesw_commit_return
    jnz .Lesw_commit_invalid
    # Pure freshness checks only. No filesystem/allocator work before rename.
    cmp qword ptr [rbx + ESW_state], ESW_READY
    jne .Lesw_commit_stale
    cmp qword ptr [r14 + ESG_exclusive], 1
    jne .Lesw_commit_stale
    cmp [r14 + ESG_prepared], rbx
    jne .Lesw_commit_stale
    mov rax, [rbx + ESW_ready_epoch]
    cmp [r14 + ESG_epoch], rax
    jne .Lesw_commit_stale
    inc qword ptr [r14 + ESG_epoch]
    mov qword ptr [rbx + ESW_state], ESW_FAILED
    mov rdi, [rbx + ESW_identity_dir]
    lea rsi, [rbx + ESW_pending]
    lea rdx, [rbx + ESW_final]
    mov rcx, [rbx + ESW_source]
    lea r8, [rbx + ESW_rename_info]
    lea r9, [rbx + ESW_iosb]
    call ext_store_raw_rename
    test rax, rax
    jz .Lesw_commit_done
    mov [rbx + ESW_publish_error], rax
    cmp rax, -115
    jne 1f
    mov qword ptr [rbx + ESW_async], 1
    mov qword ptr [rbx + ESW_state], ESW_INDETERMINATE
    mov rax, -5
    jmp .Lesw_commit_return
1:  mov rdi, rbx
    call ext_store_reconcile_try
    jmp .Lesw_commit_return
.Lesw_commit_done:
    mov qword ptr [rbx + ESW_pending_exists], 0
    mov qword ptr [rbx + ESW_state], ESW_COMMITTED
    xor eax, eax
.Lesw_commit_return:
    EPILOGUE
.Lesw_commit_invalid:
    mov rax, -22
    EPILOGUE
.Lesw_commit_stale:
    mov rax, -116
    EPILOGUE
.Lesw_commit_overflow:
    mov rax, -75
    EPILOGUE

# Allocation-free direct prepared-name reconciliation. Never enumerates directories.
# A native ambiguous error is committed only for exact own next160 with exact EOF.
FN ext_store_reconcile_try
    test rdi, rdi
    jz .Lesw_scalar_invalid
    PROLOGUE 16
    mov rbx, rdi
    mov r12, -1
    cmp qword ptr [rbx + ESW_publish_error], 0
    je .Lesw_reconcile_invalid
    cmp qword ptr [rbx + ESW_state], ESW_COMMITTED
    je .Lesw_reconcile_committed
    cmp qword ptr [rbx + ESW_async], 0
    je 1f
    mov rdi, [rbx + ESW_source]
    lea rsi, [rbx + ESW_iosb]
    call ext_store_raw_rename_poll
    cmp rax, -115
    jne 91f
    test rdx, rdx
    jns .Lesw_reconcile_pending
    mov [rbx + ESW_reconcile_error], rdx
    jmp .Lesw_reconcile_pending
91: mov qword ptr [rbx + ESW_async], 0
    test rax, rax
    jz .Lesw_reconcile_committed
    mov [rbx + ESW_publish_error], rax
1:  mov rdi, [rbx + ESW_identity_dir]
.ifdef WINDOWS
    lea rsi, [rbx + ESW_rename_info + 20]
    mov edx, EXI_FILENAME_LEN * 2
    mov ecx, ER_FILE
    xor r8d, r8d
    call win_ext_root_open_prepared_at
.else
    lea rsi, [rbx + ESW_final]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
.endif
    test rax, rax
    jns 2f
    mov [rbx + ESW_reconcile_error], rax
    test rdx, rdx
    js .Lesw_reconcile_open_cleanup
    cmp rax, -2
    je .Lesw_reconcile_absent
    jmp .Lesw_reconcile_indeterminate
.Lesw_reconcile_open_cleanup:
    mov rax, rdx
    call .Lesw_cleanup
    jmp .Lesw_reconcile_indeterminate
2:  mov r12, rax
    mov rdi, rax
    lea rsi, [rbx + ESW_stat_buf]
    call ext_root_stat
    test rax, rax
    js .Lesw_reconcile_unknown_close
    cmp qword ptr [rbx + ESW_stat_buf + ER_kind], ER_FILE
    jne .Lesw_reconcile_bad_close
    cmp qword ptr [rbx + ESW_stat_buf + ER_size], EXI_SIZE
    jne .Lesw_reconcile_bad_close
    xor r13d, r13d
3:  mov rdi, r12
    lea rsi, [rbx + r13 + ESW_record_buf]
    mov edx, EXI_SIZE
    sub rdx, r13
    mov rcx, r13
    call ext_root_read
    cmp rax, -4
    je 3b
    test rax, rax
    js .Lesw_reconcile_unknown_close
    jz .Lesw_reconcile_short_close
    add r13, rax
    cmp r13, EXI_SIZE
    jb 3b
    ja .Lesw_reconcile_bad_close
4:  mov rdi, r12
    lea rsi, [rbx + ESW_eof]
    mov edx, 1
    mov ecx, EXI_SIZE
    call ext_root_read
    cmp rax, -4
    je 4b
    test rax, rax
    js .Lesw_reconcile_unknown_close
    jnz .Lesw_reconcile_bad_close
    lea rdi, [rbx + ESW_record_buf]
    lea rsi, [rbx + ESW_next]
    mov edx, EXI_SIZE
    call memeq
    test eax, eax
    jz .Lesw_reconcile_bad_close
    mov r14d, ESW_COMMITTED
    xor r15d, r15d
    jmp .Lesw_reconcile_close
.Lesw_reconcile_bad_close:
    mov r14d, ESW_BLOCKED
    mov r15, -5
    jmp .Lesw_reconcile_close
.Lesw_reconcile_short_close:
    mov rax, -5
.Lesw_reconcile_unknown_close:
    mov r14d, ESW_INDETERMINATE
    mov r15, rax
.Lesw_reconcile_close:
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jns 5f
    cmp r14, ESW_COMMITTED
    je 6f
    call .Lesw_cleanup
    jmp 5f
6:  mov r15, rax
    mov r14d, ESW_INDETERMINATE
5:  mov [rbx + ESW_reconcile_error], r15
    mov [rbx + ESW_state], r14
    cmp r14, ESW_COMMITTED
    je .Lesw_reconcile_committed
    mov rax, -5
    EPILOGUE
.Lesw_reconcile_absent:
    mov qword ptr [rbx + ESW_state], ESW_FAILED
    mov rax, [rbx + ESW_publish_error]
    EPILOGUE
.Lesw_reconcile_indeterminate:
    mov qword ptr [rbx + ESW_state], ESW_INDETERMINATE
.Lesw_reconcile_pending:
    mov rax, -5
    EPILOGUE
.Lesw_reconcile_committed:
    mov qword ptr [rbx + ESW_state], ESW_COMMITTED
    mov qword ptr [rbx + ESW_pending_exists], 0
    xor eax, eax
    EPILOGUE
.Lesw_reconcile_invalid:
    mov rax, -22
    EPILOGUE

# Pure coordinator marker. Call only after the immediate committed catalog swap.
FN ext_store_visible
    test rdi, rdi
    jz .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_state], ESW_COMMITTED
    jne .Lesw_scalar_invalid
    mov qword ptr [rdi + ESW_visible], 1
    xor eax, eax
    ret

# ext_store_cleanup_step(ESW,maxDeletes1..8)->0 done,1 more,negative cleanup failure.
# Only committed, explicitly visible transactions may retire old completed records.
FN ext_store_cleanup_step
    test rdi, rdi
    jz .Lesw_scalar_invalid
    cmp rsi, 1
    jb .Lesw_scalar_invalid
    cmp rsi, 8
    ja .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_state], ESW_COMMITTED
    jne .Lesw_scalar_invalid
    cmp qword ptr [rdi + ESW_visible], 1
    jne .Lesw_scalar_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
1:  mov r13, [rbx + ESW_cleanup_cursor]
    cmp r13, [rbx + ESW_prune_count]
    jae 5f
    mov r14, [rbx + r13*8 + ESW_plan]
    test r14, r14
    jz 4f
    cmp r14, [rbx + ESW_old_max]
    je 4f
    test r12, r12
    jz 6f
    cmp qword ptr [rbx + ESW_delete + ESU_pending], 0
    jne 92f
    mov rdi, [rbx + ESW_guard]
    call ext_store_cancel
    test rax, rax
    js 7f
92: mov rdi, rsp
    mov rsi, r14
    call ext_index_filename_format
    mov rdi, rbx
    call .Lesw_mutate
    test rax, rax
    js 7f
    mov qword ptr [rbx + ESW_delete_kind], 1
    mov rdi, rbx
    mov rsi, rsp
    call .Lesw_unlink
    cmp rax, -115
    je 6f
    test rax, rax
    js 8f
    mov qword ptr [rbx + r13*8 + ESW_plan], 0
    dec r12
4:  inc qword ptr [rbx + ESW_cleanup_cursor]
    jmp 1b
5:  xor eax, eax
    EPILOGUE
6:  mov eax, 1
    EPILOGUE
8:  mov r12, rax
    mov rax, rdx
    call .Lesw_cleanup
    mov rax, r12
7:  call .Lesw_cleanup
    EPILOGUE
