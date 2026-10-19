# Bounded task ownership, restart serialization and output. No process is launched here.
# A supervisor adapter may mark lifetime completion only after all protected children are gone.
.include "rhun.inc"
.include "app/taskcore.inc"
.text

# task_core_init(fresh caller-owned context). Never reset an exposed context's ID counter.
FN task_core_init
    PROLOGUE
    mov rbx, rdi
    xor esi, esi
    mov edx, TC_SIZE
    call memset
    mov qword ptr [rbx + TC_project], 1
    EPILOGUE

# Strict visible UTF-8, including shortest encodings, scalar range and hidden-control policy.
# task_core_text(ptr, length) -> 1/0. The empty string is invalid.
FN task_core_text
    test rdi, rdi
    jz .Ltc_text_no
    test rsi, rsi
    jz .Ltc_text_no
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp edx, 1
    jne 2f
    cmp byte ptr [rbx + r13], 0x80
    jae .Ltc_text_bad
2:  cmp eax, 0x20
    jb .Ltc_text_bad
    cmp eax, 0x7f
    jb 3f
    cmp eax, 0xa0
    jb .Ltc_text_bad
3:  cmp eax, 0x10ffff
    ja .Ltc_text_bad
    cmp eax, 0xd800
    jb 4f
    cmp eax, 0xdfff
    jbe .Ltc_text_bad
4:  cmp eax, 0x200b
    jb 5f
    cmp eax, 0x200f
    jbe .Ltc_text_bad
5:  cmp eax, 0x202a
    jb 6f
    cmp eax, 0x202e
    jbe .Ltc_text_bad
6:  cmp eax, 0x2060
    je .Ltc_text_bad
    cmp eax, 0x2066
    jb 7f
    cmp eax, 0x2069
    jbe .Ltc_text_bad
7:  cmp eax, 0xfeff
    je .Ltc_text_bad
    add r13, rdx
    cmp r13, r12
    jb 1b
    mov eax, 1
    EPILOGUE
.Ltc_text_bad:
    xor eax, eax
    EPILOGUE
.Ltc_text_no:
    xor eax, eax
    ret

# Bounded internal C-string length. The caller supplies a readable terminated string.
tc_length:
    test rdi, rdi
    jz 3f
    xor eax, eax
1:  cmp rax, rsi
    ja 2f
    cmp byte ptr [rdi + rax], 0
    je 9f
    inc rax
    jmp 1b
2:  mov rax, -36
    ret
3:  mov rax, -22
9:  ret

# task_core_find(context, ID) -> private record or 0. Reaper use only, not an owner gate.
FN task_core_find
    test rsi, rsi
    jle 3f
    lea rax, [rdi + TC_records]
    mov ecx, TASK_RECORDS
1:  cmp [rax + TK_id], rsi
    je 9f
    add rax, TK_SIZE
    dec ecx
    jnz 1b
3:  xor eax, eax
9:  ret

# task_core_lookup(context, ownerToken, ID) -> record or 0. Owner zero is always invalid.
FN task_core_lookup
    test rsi, rsi
    jz 1f
    PROLOGUE
    mov rbx, rsi
    mov rsi, rdx
    call task_core_find
    test rax, rax
    jz 2f
    cmp [rax + TK_owner], rbx
    je 2f
    xor eax, eax
2:  EPILOGUE
1:  xor eax, eax
    ret

# The predecessor of a prepared/queued replacement cannot be recycled yet.
tc_referenced:
    lea rax, [rdi + TC_records]
    mov ecx, TASK_RECORDS
1:  cmp dword ptr [rax + TK_state], TASK_PREPARED
    je 2f
    cmp dword ptr [rax + TK_state], TASK_QUEUED
    jne 3f
2:  cmp [rax + TK_wait], rsi
    je 8f
3:  add rax, TK_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
    ret
8:  mov eax, 1
    ret

# Free slot preferred; otherwise oldest terminal record not held by a queued restart.
tc_slot:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + TC_records]
    xor r13d, r13d
    xor r14d, r14d
1:  cmp qword ptr [r12 + TK_id], 0
    je 7f
    cmp dword ptr [r12 + TK_state], TASK_EXITED
    jb 6f
    test r14, r14
    jz 2f
    mov rax, [r14 + TK_id]
    cmp [r12 + TK_id], rax
    jae 6f
2:  mov rdi, rbx
    mov rsi, [r12 + TK_id]
    call tc_referenced
    test eax, eax
    jnz 6f
    mov r14, r12
6:  add r12, TK_SIZE
    inc r13d
    cmp r13d, TASK_RECORDS
    jb 1b
    mov rax, r14
    EPILOGUE
7:  mov rax, r12
    EPILOGUE

tc_free:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + TK_cwd]
    call mem_free
    mov rdi, [rbx + TK_label]
    call mem_free
    mov rdi, [rbx + TK_command]
    call mem_free
    mov rdi, [rbx + TK_output]
    call mem_free
    mov rdi, rbx
    xor esi, esi
    mov edx, TK_SIZE
    call memset
    EPILOGUE

# task_core_prepare(ctx, ownerToken, nonce, cwd, label, command) -> ID/-errno, rdx record/0.
# All string/output ownership is prepared privately before a retained record is replaced.
FN task_core_prepare
    test rdx, rdx
    jle tc_nonce_invalid
    jmp tc_prepare
# Internal preparation accepts either namespace. Public wire entry remains positive-only.
tc_prepare:
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    test r12, r12
    jz .Ltc_prepare_invalid
    test r13, r13
    jz .Ltc_prepare_invalid
    cmp qword ptr [rbx + TC_project], 0
    je .Ltc_prepare_overflow
    mov rax, 0x7fffffffffffffff
    cmp [rbx + TC_next], rax
    jae .Ltc_prepare_overflow
    cmp qword ptr [rbx + TC_active], TASK_ACTIVE_MAX
    jae .Ltc_prepare_busy
    lea rax, [rbx + TC_records]
    mov ecx, TASK_RECORDS
1:  cmp [rax + TK_owner], r12
    jne 2f
    cmp [rax + TK_nonce], r13
    je .Ltc_prepare_exists
2:  add rax, TK_SIZE
    dec ecx
    jnz 1b
    mov rdi, r14
    mov esi, 4095
    call tc_length
    test rax, rax
    jle .Ltc_prepare_invalid
    mov [rsp + 8], rax
    mov rdi, r15
    mov esi, 128
    call tc_length
    test rax, rax
    jle .Ltc_prepare_invalid
    mov [rsp + 16], rax
    mov rdi, r15
    mov rsi, rax
    call task_core_text
    test eax, eax
    jz .Ltc_prepare_invalid
    mov rdi, [rsp]
    mov esi, 4096
    call tc_length
    test rax, rax
    jle .Ltc_prepare_invalid
    mov [rsp + 24], rax
    mov rdi, [rsp]
    mov rsi, rax
    call task_core_text
    test eax, eax
    jz .Ltc_prepare_invalid
    mov rdi, rbx
    call tc_slot
    test rax, rax
    jz .Ltc_prepare_busy
    mov [rsp + 64], rax
    mov rdi, r14
    mov rsi, [rsp + 8]
    call mem_dup_try
    mov [rsp + 32], rax
    test rax, rax
    jz .Ltc_prepare_nomem
    mov rdi, r15
    mov rsi, [rsp + 16]
    call mem_dup_try
    mov [rsp + 40], rax
    test rax, rax
    jz .Ltc_prepare_nomem
    mov rdi, [rsp]
    mov rsi, [rsp + 24]
    call mem_dup_try
    mov [rsp + 48], rax
    test rax, rax
    jz .Ltc_prepare_nomem
    mov edi, TASK_OUTPUT_MAX
    call mem_alloc_try
    mov [rsp + 56], rax
    test rax, rax
    jz .Ltc_prepare_nomem
    mov rdi, [rsp + 64]
    call tc_free
    mov rdx, [rsp + 64]
    inc qword ptr [rbx + TC_next]
    mov rax, [rbx + TC_next]
    mov [rdx + TK_id], rax
    mov [rdx + TK_family], rax
    mov [rdx + TK_owner], r12
    mov [rdx + TK_nonce], r13
    mov rcx, [rbx + TC_project]
    mov [rdx + TK_project], rcx
    mov dword ptr [rdx + TK_state], TASK_PREPARED
    mov dword ptr [rdx + TK_exit], -1
    mov rcx, [rsp + 32]
    mov [rdx + TK_cwd], rcx
    mov rcx, [rsp + 40]
    mov [rdx + TK_label], rcx
    mov rcx, [rsp + 48]
    mov [rdx + TK_command], rcx
    mov rcx, [rsp + 56]
    mov [rdx + TK_output], rcx
    inc qword ptr [rbx + TC_active]
    EPILOGUE
.Ltc_prepare_invalid:
    mov r15, -22
    jmp .Ltc_prepare_cleanup
.Ltc_prepare_overflow:
    mov r15, -75
    jmp .Ltc_prepare_cleanup
.Ltc_prepare_busy:
    mov r15, -11
    jmp .Ltc_prepare_cleanup
.Ltc_prepare_exists:
    mov r15, -17
    jmp .Ltc_prepare_cleanup
.Ltc_prepare_nomem:
    mov r15, -12
.Ltc_prepare_cleanup:
    mov rdi, [rsp + 32]
    call mem_free
    mov rdi, [rsp + 40]
    call mem_free
    mov rdi, [rsp + 48]
    call mem_free
    mov rdi, [rsp + 56]
    call mem_free
    mov rax, r15
    xor edx, edx
    EPILOGUE

# task_core_restart(ctx, owner, oldID, nonce) -> prepared successor ID/-errno, rdx record.
# Any retained family member resolves to the newest member. One pending replacement per family.
FN task_core_restart
    test rcx, rcx
    jle tc_nonce_invalid
    jmp tc_restart

# Native UI restarts use negative, monotonically decreasing nonces, disjoint from the wire.
# task_core_restart_native(ctx, owner, oldID, negativeNonce) -> ID/-errno, rdx record/0.
FN task_core_restart_native
    test rcx, rcx
    jns tc_nonce_invalid
tc_restart:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    call task_core_lookup
    test rax, rax
    jz .Ltc_restart_missing
    mov rcx, [rbx + TC_project]
    cmp [rax + TK_project], rcx
    jne .Ltc_restart_stale
    mov r14, [rax + TK_family]
    mov r15, rax
    mov qword ptr [rsp], 0
    lea rax, [rbx + TC_records]
    mov ecx, TASK_RECORDS
1:  cmp [rax + TK_owner], r12
    jne 4f
    cmp [rax + TK_family], r14
    jne 4f
    cmp dword ptr [rax + TK_state], TASK_PREPARED
    je .Ltc_restart_busy
    cmp dword ptr [rax + TK_state], TASK_QUEUED
    je .Ltc_restart_busy
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je .Ltc_restart_live
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne .Ltc_restart_latest
.Ltc_restart_live:
    # A canceled successor may be newer than the process still stopping before it.
    cmp qword ptr [rsp], 0
    jne .Ltc_restart_busy
    mov rdx, [rax + TK_id]
    mov [rsp], rdx
.Ltc_restart_latest:
    mov rdx, [r15 + TK_id]
    cmp [rax + TK_id], rdx
    jbe 4f
    mov r15, rax
4:  add rax, TK_SIZE
    dec ecx
    jnz 1b
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [r15 + TK_cwd]
    mov r8, [r15 + TK_label]
    mov r9, [r15 + TK_command]
    call tc_prepare
    test rax, rax
    js 9f
    mov [rdx + TK_family], r14
    mov rcx, [rsp]
    mov [rdx + TK_wait], rcx
9:  EPILOGUE
.Ltc_restart_stale:
    mov rax, -116
    xor edx, edx
    EPILOGUE
.Ltc_restart_missing:
    mov rax, -2
    xor edx, edx
    EPILOGUE
.Ltc_restart_busy:
    mov rax, -11
    xor edx, edx
    EPILOGUE

tc_nonce_invalid:
    mov rax, -22
    xor edx, edx
    ret

# Internal cancellation: no process means immediately failed; running processes retain ownership.
# tc_stop(ctx, record) -> existing supervisor token or0. The adapter requests cancellation.
tc_stop:
    mov eax, [rsi + TK_state]
    cmp eax, TASK_PREPARED
    je 1f
    cmp eax, TASK_QUEUED
    je 1f
    cmp eax, TASK_RUNNING
    jne 2f
    mov dword ptr [rsi + TK_state], TASK_STOPPING
2:  mov rax, [rsi + TK_process]
    ret
1:  mov dword ptr [rsi + TK_state], TASK_FAILED
    mov dword ptr [rsi + TK_exit], -125
    mov dword ptr [rsi + TK_flags], TASK_LIFETIME_DONE | TASK_OUTPUT_EOF
    dec qword ptr [rdi + TC_active]
    xor eax, eax
    ret

# task_core_confirm(ctx, owner, ID, commandBytes, len) -> 0/-errno, rdx predecessor token to stop.
FN task_core_confirm
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    mov r14, r8
    call task_core_lookup
    test rax, rax
    jz .Ltc_confirm_missing
    mov r15, rax
    cmp dword ptr [rax + TK_state], TASK_PREPARED
    jne .Ltc_confirm_invalid
    mov rcx, [rbx + TC_project]
    cmp [rax + TK_project], rcx
    jne .Ltc_confirm_invalid
    test r14, r14
    jz .Ltc_confirm_invalid
    cmp r14, 4096
    ja .Ltc_confirm_invalid
    mov rdi, r13
    mov rsi, r14
    call task_core_text
    test eax, eax
    jz .Ltc_confirm_invalid
    mov rdi, r13
    mov rsi, r14
    call mem_dup_try
    test rax, rax
    jz .Ltc_confirm_nomem
    mov [rsp], rax
    mov rdi, [r15 + TK_command]
    call mem_free
    mov rax, [rsp]
    mov [r15 + TK_command], rax
    mov dword ptr [r15 + TK_state], TASK_QUEUED
    mov rsi, [r15 + TK_wait]
    test rsi, rsi
    jz 2f
    mov rdi, rbx
    call task_core_find
    test rax, rax
    jz .Ltc_confirm_predecessor_missing
    mov rsi, rax
    mov rdi, rbx
    call tc_stop
    mov rdx, rax
    xor eax, eax
    EPILOGUE
2:  xor edx, edx
    xor eax, eax
    EPILOGUE
.Ltc_confirm_predecessor_missing:
    mov rdi, rbx
    mov rsi, r15
    call tc_stop
.Ltc_confirm_missing:
    mov rax, -2
    xor edx, edx
    EPILOGUE
.Ltc_confirm_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Ltc_confirm_nomem:
    mov rax, -12
    xor edx, edx
    EPILOGUE

# task_core_can_start(ctx, ID) ->1/0. Caller must not launch on0.
FN task_core_can_start
    PROLOGUE
    mov rbx, rdi
    call task_core_find
    test rax, rax
    jz 8f
    mov r12, rax
    cmp dword ptr [rax + TK_state], TASK_QUEUED
    jne 8f
    cmp qword ptr [rax + TK_owner], 0
    je 7f
    mov rcx, [rbx + TC_project]
    cmp [rax + TK_project], rcx
    jne 7f
    mov rsi, [rax + TK_wait]
    test rsi, rsi
    jz 9f
    mov rdi, rbx
    call task_core_find
    test rax, rax
    jz 7f
    cmp dword ptr [rax + TK_state], TASK_EXITED
    jb 8f
9:  mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov rsi, r12
    call tc_stop
8:  xor eax, eax
    EPILOGUE

# task_core_started(ctx, ID, supervisorToken) ->1/0, after can_start with no event dispatch between.
FN task_core_started
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jle 8f
    call task_core_can_start
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call task_core_find
    mov [rax + TK_process], r13
    mov dword ptr [rax + TK_state], TASK_RUNNING
    mov qword ptr [rax + TK_wait], 0
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# task_core_stop(ctx, ID) -> supervisorToken/0, or -ENOENT. Repeating stop is harmless.
FN task_core_stop
    PROLOGUE
    mov rbx, rdi
    call task_core_find
    test rax, rax
    jz 1f
    mov rsi, rax
    mov rdi, rbx
    call tc_stop
    EPILOGUE
1:  mov rax, -2
    EPILOGUE

# task_core_output(ctx, ID, bytes, length) ->0/-errno. Raw data, at most one read budget.
FN task_core_output
    PROLOGUE 16
    mov rbx, rdx
    mov r12, rcx
    call task_core_find
    test rax, rax
    jz .Ltc_output_missing
    mov r13, rax
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je 1f
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne .Ltc_output_stale
1:  test dword ptr [rax + TK_flags], TASK_OUTPUT_EOF | TASK_OUTPUT_ERROR
    jnz .Ltc_output_stale
    cmp r12, TASK_READ_MAX
    ja .Ltc_output_invalid
    test r12, r12
    jz 9f
    test rbx, rbx
    jz .Ltc_output_invalid
    mov rax, [r13 + TK_total]
    add rax, r12
    jc .Ltc_output_overflow
    mov [rsp], rax
    mov r14, [r13 + TK_length]
    lea r15, [r14 + r12]
    cmp r15, TASK_OUTPUT_MAX
    jbe 3f
    sub r15, TASK_OUTPUT_MAX
    mov rdi, [r13 + TK_output]
    lea rsi, [rdi + r15]
    sub r14, r15
    mov rdx, r14
    call memmove
3:  mov rdi, [r13 + TK_output]
    add rdi, r14
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    add r14, r12
    mov [r13 + TK_length], r14
    mov rax, [rsp]
    mov [r13 + TK_total], rax
9:  xor eax, eax
    EPILOGUE
.Ltc_output_missing:
    mov rax, -2
    EPILOGUE
.Ltc_output_stale:
    mov rax, -116
    EPILOGUE
.Ltc_output_invalid:
    mov rax, -22
    EPILOGUE
.Ltc_output_overflow:
    mov rax, -75
    EPILOGUE

# Complete only after lifetime confirmation and EOF or permanent read failure.
# Returns supervisor token for adapter cleanup exactly once, else0.
tc_maybe_finish:
    test dword ptr [rsi + TK_flags], TASK_LIFETIME_DONE
    jz 8f
    test dword ptr [rsi + TK_flags], TASK_OUTPUT_EOF | TASK_OUTPUT_ERROR
    jz 8f
    mov dword ptr [rsi + TK_state], TASK_EXITED
    mov eax, [rsi + TK_result]
    mov [rsi + TK_exit], eax
    cmp dword ptr [rsi + TK_error], 0
    je 1f
    mov dword ptr [rsi + TK_state], TASK_FAILED
    mov eax, [rsi + TK_error]
    mov [rsi + TK_exit], eax
1:  dec qword ptr [rdi + TC_active]
    mov rax, [rsi + TK_process]
    mov qword ptr [rsi + TK_process], 0
    ret
8:  xor eax, eax
    ret

# task_core_lifetime(ctx, ID, exitStatus) -> token to close or0/-ENOENT/-EINVAL.
FN task_core_lifetime
    PROLOGUE
    mov rbx, rdi
    mov r12d, edx
    cmp r12d, 255
    ja 7f
    call task_core_find
    test rax, rax
    jz 8f
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je 1f
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne 9f
1:  test dword ptr [rax + TK_flags], TASK_LIFETIME_DONE
    jnz 9f
    mov [rax + TK_result], r12d
    or dword ptr [rax + TK_flags], TASK_LIFETIME_DONE
    mov rdi, rbx
    mov rsi, rax
    call tc_maybe_finish
    EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# task_core_output_end(ctx, ID, error0/negative_errno) -> token for cancellation/cleanup, or0/-errno.
# On read error token may be returned again for idempotent stop until lifetime confirms completion.
FN task_core_output_end
    PROLOGUE
    mov rbx, rdi
    mov r12d, edx
    cmp r12d, 0
    jg 7f
    cmp r12d, -4095
    jl 7f
    call task_core_find
    test rax, rax
    jz 8f
    mov r13, rax
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je 1f
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne 9f
1:  test dword ptr [rax + TK_flags], TASK_OUTPUT_EOF | TASK_OUTPUT_ERROR
    jnz 9f
    test r12d, r12d
    jnz 2f
    or dword ptr [rax + TK_flags], TASK_OUTPUT_EOF
    jmp 3f
2:  cmp dword ptr [rax + TK_error], 0
    jne 21f
    mov [rax + TK_error], r12d
21: or dword ptr [rax + TK_flags], TASK_OUTPUT_ERROR
    mov dword ptr [rax + TK_state], TASK_STOPPING
3:  mov rdi, rbx
    mov rsi, r13
    call tc_maybe_finish
    test rax, rax
    jnz 6f
    test r12d, r12d
    jz 6f
    mov rax, [r13 + TK_process]
6:  EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# task_core_process_failed(ctx, ID, negative_errno) -> token for idempotent stop/final cleanup.
# A service failure may arrive after output EOF. Preserve the first failure and all live ownership.
FN task_core_process_failed
    PROLOGUE
    mov rbx, rdi
    mov r12d, edx
    cmp r12d, -1
    jg 7f
    cmp r12d, -4095
    jl 7f
    call task_core_find
    test rax, rax
    jz 8f
    mov r13, rax
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je 1f
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne 9f
1:  cmp dword ptr [rax + TK_error], 0
    jne 2f
    mov [rax + TK_error], r12d
2:  mov dword ptr [rax + TK_state], TASK_STOPPING
    mov rdi, rbx
    mov rsi, r13
    call tc_maybe_finish
    test rax, rax
    jnz 6f
    mov rax, [r13 + TK_process]
6:  EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# task_core_launch_failed(ctx, ID, negative_errno) ->0/-errno. No supervisor may be attached.
FN task_core_launch_failed
    PROLOGUE
    mov rbx, rdi
    mov r12d, edx
    cmp r12d, -1
    jg 7f
    cmp r12d, -4095
    jl 7f
    call task_core_find
    test rax, rax
    jz 8f
    cmp dword ptr [rax + TK_state], TASK_QUEUED
    jne 7f
    cmp qword ptr [rax + TK_process], 0
    jne 7f
    mov dword ptr [rax + TK_state], TASK_FAILED
    mov [rax + TK_exit], r12d
    mov dword ptr [rax + TK_flags], TASK_LIFETIME_DONE | TASK_OUTPUT_EOF
    dec qword ptr [rbx + TC_active]
    xor eax, eax
    EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# task_core_retire(ctx, owner) invalidates ownership before requesting cancellation.
# Caller then visits every stopping record and sends idempotent stop to its supervisor.
FN task_core_retire
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 9f
    lea r13, [rbx + TC_records]
    mov r14d, TASK_RECORDS
1:  cmp [r13 + TK_owner], r12
    jne 2f
    mov qword ptr [r13 + TK_owner], 0
    mov rdi, rbx
    mov rsi, r13
    call tc_stop
2:  add r13, TK_SIZE
    dec r14d
    jnz 1b
9:  EPILOGUE

# task_core_project_changed(ctx) invalidates all old-workspace starts and requests stop.
FN task_core_project_changed
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + TC_project], 0
    je 2f
    mov rax, 0x7fffffffffffffff
    cmp [rbx + TC_project], rax
    jae 1f
    inc qword ptr [rbx + TC_project]
    jmp 2f
1:  mov qword ptr [rbx + TC_project], 0
2:  lea r12, [rbx + TC_records]
    mov r13d, TASK_RECORDS
3:  cmp qword ptr [r12 + TK_id], 0
    je 4f
    mov rdi, rbx
    mov rsi, r12
    call tc_stop
4:  add r12, TK_SIZE
    dec r13d
    jnz 3b
    EPILOGUE

# task_core_dispose(ctx) ->0/-EBUSY. Never drops records still protecting a process.
FN task_core_dispose
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + TC_active], 0
    jne 8f
    lea r12, [rbx + TC_records]
    mov r13d, TASK_RECORDS
1:  mov rdi, r12
    call tc_free
    add r12, TK_SIZE
    dec r13d
    jnz 1b
    xor eax, eax
    EPILOGUE
8:  mov rax, -16
    EPILOGUE

# task_core_abort(ctx, ID) ->0/-errno. User dismissed a not-yet-confirmed prompt.
FN task_core_abort
    PROLOGUE
    mov rbx, rdi
    call task_core_find
    test rax, rax
    jz 8f
    cmp dword ptr [rax + TK_state], TASK_PREPARED
    jne 7f
    mov rdi, rax
    call tc_free
    dec qword ptr [rbx + TC_active]
    xor eax, eax
    EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# task_core_cancel(ctx, owner, nonce) -> supervisorToken/0. Missing/repeated cancel is harmless.
FN task_core_cancel
    PROLOGUE
    mov rbx, rdi
    test rsi, rsi
    jz 8f
    test rdx, rdx
    jle 8f
    lea r12, [rdi + TC_records]
    mov ecx, TASK_RECORDS
1:  cmp [r12 + TK_owner], rsi
    jne 3f
    cmp [r12 + TK_nonce], rdx
    je 4f
3:  add r12, TK_SIZE
    dec ecx
    jnz 1b
8:  xor eax, eax
    EPILOGUE
4:  cmp dword ptr [r12 + TK_state], TASK_PREPARED
    jne 5f
    mov rdi, r12
    call tc_free
    dec qword ptr [rbx + TC_active]
    xor eax, eax
    EPILOGUE
5:  mov rdi, rbx
    mov rsi, r12
    call tc_stop
    EPILOGUE

# task_core_next_output(ctx) -> next readable active record or0; rotates between bounded ticks.
FN task_core_next_output
    mov r8, [rdi + TC_cursor]
    and r8d, TASK_RECORDS-1
    mov ecx, TASK_RECORDS
1:  mov rax, r8
    shl rax, 7
    lea rax, [rdi + rax + TC_records]
    inc r8d
    and r8d, TASK_RECORDS-1
    mov [rdi + TC_cursor], r8
    cmp dword ptr [rax + TK_state], TASK_RUNNING
    je 2f
    cmp dword ptr [rax + TK_state], TASK_STOPPING
    jne 3f
2:  test dword ptr [rax + TK_flags], TASK_OUTPUT_EOF | TASK_OUTPUT_ERROR
    jz 9f
3:  dec ecx
    jnz 1b
    xor eax, eax
9:  ret
