.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extchoicesdisk.inc"
.include "app/extchoices.inc"
.include "app/extstore.inc"
.section .rodata
cpt_section: .ascii "owner/tool"
.bss
.p2align 3
cpt_delta: .zero EC_SIZE
cpt_header: .zero 160
cpt_reconcile_snapshot: .quad 0
cpt_alloc_count: .quad 0
cpt_write_count: .quad 0
cpt_sync_count: .quad 0
cpt_cleanup_running: .quad 0
cpt_close_count: .quad 0
cpt_native_renames: .quad 0
cpt_native_unlinks: .quad 0
cpt_async_iosb: .quad 0
cpt_async_status: .quad 0
cpt_async_kind: .quad 0
cpt_async_polls: .quad 0
cpt_security_frees: .quad 0
cpt_delete_polls: .quad 0
cpt_delete_observed: .quad 0
cpt_wine: .quad 0
cpt_current: .quad 0
cpt_fault: .quad 0
cpt_poll_count: .quad 0
cpt_native_calls: .quad 0
cpt_late_cancel: .quad 0
cpt_replace_args: .zero 48
cpt_commit: .zero 72
cpt_trailer: .zero 24
cpt_live: .quad 0
cpt_hold: .quad 0
.text
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 5
    je 1f
    cmp qword ptr [rip + g_argc], 6
    je 2f
    cmp qword ptr [rip + g_argc], 7
    jne .Lcpt_fail
    mov qword ptr [rip + cpt_wine], 1
2:  mov rax, [rip + g_argv]
    mov rdi, [rax + 40]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 40]
    call parse_u64
    mov [rip + cpt_fault], rax
1:
    mov rax, [rip + g_mem_live]
    mov [rip + cpt_live], rax
    mov rbx, [rip + g_argv]
    xor r12d, r12d
    xor r13d, r13d
    lea rax, [rip + cpt_section]
    mov [rip + cpt_delta + EC_section], rax
    mov qword ptr [rip + cpt_delta + EC_seclen], 10
    mov rdi, [rbx + 16]
    mov [rip + cpt_delta + EC_key], rdi
    call strlen
    mov [rip + cpt_delta + EC_keylen], rax
    mov rdi, [rbx + 24]
    mov [rip + cpt_delta + EC_value], rdi
    call strlen
    mov [rip + cpt_delta + EC_vallen], rax
    mov rax, [rbx + 32]
    cmp byte ptr [rax], 'r'
    je .Lcpt_remove
    cmp byte ptr [rax], 'd'
    jne 1f
.Lcpt_remove:
    mov qword ptr [rip + cpt_delta + EC_remove], 1
1:  mov rdi, [rbx + 8]
    mov esi, 1
    mov edx, 1
    call ext_choices_guard_try
    mov r12, rax
    mov [rip + cpt_header], rdx
    mov [rip + cpt_header + 8], r8
    test rax, rax
    jz .Lcpt_output
    mov rdi, rax
    call ext_choices_begin_try
    mov r13, rax
    mov [rip + cpt_current], rax
    mov [rip + cpt_header], rdx
    mov [rip + cpt_header + 8], r8
    test rax, rax
    jz .Lcpt_output
    mov rdi, r12
    call ext_choices_guard_free
    cmp rax, -16
    jne .Lcpt_fail
    mov rdi, r13
    call ext_choices_free
    cmp rax, -16
    jne .Lcpt_fail
    mov rdi, r13
    lea rsi, [rip + cpt_delta]
    mov edx, 1
    call ext_choices_prepare_try
    mov [rip + cpt_header], rax
    mov [rip + cpt_header + 8], rdx
    mov r14, [r13 + ECP_old]
    test r14, r14
    jz 2f
    mov rax, [r14 + ECS_exists]
    mov [rip + cpt_header + 16], rax
    mov rax, [r14 + ECS_length]
    mov [rip + cpt_header + 24], rax
2:  mov rax, [r13 + ECP_length]
    mov [rip + cpt_header + 32], rax
    mov rax, [r13 + ECP_noop]
    mov [rip + cpt_header + 40], rax
    lea rdi, [rip + cpt_header + 48]
    lea rsi, [r13 + ECP_identity]
    mov edx, 32
    call memcpy
    lea rdi, [rip + cpt_header + 80]
    lea rsi, [r13 + ECP_name]
    mov edx, 80
    call memcpy
    mov r14, [r13 + ECP_source]
    mov rdi, r13
    lea rsi, [rip + cpt_delta]
    mov edx, 1
    call ext_choices_prepare_try
    cmp rax, -22
    jne .Lcpt_fail
    cmp [r13 + ECP_source], r14
    jne .Lcpt_fail
.Lcpt_output:
    mov edi, 1
    lea rsi, [rip + cpt_header]
    mov edx, 160
    call write_all
    test rax, rax
    js .Lcpt_fail
    test r13, r13
    jz .Lcpt_guard_free
    mov edi, 1
    mov rsi, [r13 + ECP_bytes]
    mov rdx, [r13 + ECP_length]
    call write_all
    test rax, rax
    js .Lcpt_fail
    mov rax, [rbx + 32]
    cmp byte ptr [rax], 'h'
    jne 1f
    xor edi, edi
    lea rsi, [rip + cpt_hold]
    mov edx, 1
    SYS SYS_read
1:  mov rax, [rbx + 32]
    cmp byte ptr [rax], 'u'
    je .Lcpt_cleanup
    cmp byte ptr [rax], 'r'
    je .Lcpt_cleanup
    cmp qword ptr [r13 + ECP_state], ECP_PREPARED
    je 1f
    mov rax, [r13 + ECP_result]
    mov [rip + cpt_commit], rax
    mov rdx, [r13 + ECP_cleanup_error]
    jmp .Lcpt_committed
1:
.ifdef WINDOWS
    cmp qword ptr [r13 + ECP_noop], 1
    je 1f
    mov rdi, r13
    call cpt_security_check
1:
.endif
    mov rdi, r13
    lea rsi, [rip + cpt_fresh]
    mov rdx, [rbx + 32]
    call ext_choices_commit_try
    mov [rip + cpt_commit], rax
    mov r14d, 10000
.Lcpt_poll:
    cmp qword ptr [rip + cpt_commit], -115
    jne .Lcpt_committed
    mov rdi, r13
    call ext_choices_cleanup_step
    cmp rax, -115
    jne .Lcpt_fail
    mov rdi, r13
    call ext_choices_free
    cmp rax, -16
    jne .Lcpt_fail
    mov rdi, r13
    call ext_choices_commit_poll
    mov [rip + cpt_commit], rax
    dec r14d
    jnz .Lcpt_poll
    jmp .Lcpt_fail
.Lcpt_committed:
    cmp qword ptr [rip + cpt_fault], 4
    je 2f
    cmp qword ptr [rip + cpt_fault], 711
    jne 1f
2:  cmp qword ptr [rip + cpt_native_renames], 1
    jne .Lcpt_fail
1:  mov [rip + cpt_commit + 8], rdx
    mov rax, [r13 + ECP_state]
    mov [rip + cpt_commit + 16], rax
    mov rax, [r13 + ECP_consumed]
    mov [rip + cpt_commit + 24], rax
    mov rax, [r13 + ECP_native_error]
    mov [rip + cpt_commit + 32], rax
    mov rax, [r13 + ECP_guard]
    mov rax, [rax + ECG_uncertain]
    mov [rip + cpt_commit + 40], rax
    mov rax, [r13 + ECP_observation]
    mov [rip + cpt_commit + 48], rax
    mov rax, [r13 + ECP_reconcile_error]
    mov [rip + cpt_commit + 56], rax
    mov rax, [rip + cpt_native_calls]
    mov [rip + cpt_commit + 64], rax
    mov rdi, r13
    lea rsi, [rip + cpt_fresh_forbidden]
    xor edx, edx
    call ext_choices_commit_try
    cmp [rip + cpt_commit], rax
    jne .Lcpt_fail
    mov edi, 1
    lea rsi, [rip + cpt_commit]
    mov edx, 72
    call write_all
    test rax, rax
    js .Lcpt_fail
.Lcpt_cleanup:
    cmp qword ptr [r13 + ECP_state], ECP_UNCERTAIN
    jne 1f
    mov rdi, r12
    call ext_choices_begin_try
    test rax, rax
    jnz .Lcpt_fail
    cmp rdx, -16
    jne .Lcpt_fail
    mov rdi, r12
    call ext_choices_snapshot_try
    test rax, rax
    jz .Lcpt_fail
    mov [rip + cpt_reconcile_snapshot], rax
    mov rdi, r12
    mov rsi, rax
    call ext_choices_reconcile_accept
    cmp rax, -116
    jne .Lcpt_fail
1:  mov qword ptr [rip + cpt_cleanup_running], 1
    mov r14d, 100
.Lcpt_cleanup_loop:
    mov rdi, r13
    call ext_choices_cleanup_step
    cmp rax, -115
    jne 3f
    cmp qword ptr [rip + cpt_fault], 707
    je 2f
    cmp qword ptr [rip + cpt_fault], 712
    jne 1f
2:  cmp rdx, -5
    jne 1f
    mov qword ptr [rip + cpt_delete_observed], 1
1:  mov rdi, r13
    call ext_choices_free
    cmp rax, -16
    jne .Lcpt_fail
    dec r14d
    jnz .Lcpt_cleanup_loop
    jmp .Lcpt_fail
3:  test rax, rax
    jnz .Lcpt_fail
    cmp qword ptr [rip + cpt_fault], 707
    je 2f
    cmp qword ptr [rip + cpt_fault], 712
    jne 1f
2:  cmp qword ptr [rip + cpt_delete_observed], 1
    jne .Lcpt_fail
    cmp qword ptr [rip + cpt_native_unlinks], 1
    jne .Lcpt_fail
1:  mov [rip + cpt_trailer], rdx
    cmp qword ptr [rip + cpt_fault], 708
    je 1f
    cmp qword ptr [rip + cpt_fault], 709
    jne 2f
    cmp qword ptr [r13 + ECP_delete + ESU_status], -9
    jne .Lcpt_fail
    cmp qword ptr [r13 + ECP_delete + ESU_secondary], 0
    jne .Lcpt_fail
    jmp 2f
1:  cmp qword ptr [r13 + ECP_delete + ESU_secondary], -9
    jne .Lcpt_fail
2:  mov rdi, r13
    call ext_choices_free
    mov [rip + cpt_trailer + 8], rax
    cmp qword ptr [rip + cpt_reconcile_snapshot], 0
    je .Lcpt_guard_free
    mov rdi, r12
    call ext_choices_begin_try
    test rax, rax
    jnz .Lcpt_fail
    cmp rdx, -117
    jne .Lcpt_fail
    mov rdi, r12
    mov rsi, [rip + cpt_reconcile_snapshot]
    call ext_choices_reconcile_accept
    cmp rax, -116
    jne .Lcpt_fail
    mov rdi, [rip + cpt_reconcile_snapshot]
    call ext_choices_snapshot_free
    mov rdi, r12
    call ext_choices_snapshot_try
    test rax, rax
    jz .Lcpt_fail
    mov r15, rax
    mov rdi, r12
    mov rsi, r15
    call ext_choices_reconcile_accept
    test rax, rax
    jnz .Lcpt_fail
    mov rdi, r15
    call ext_choices_snapshot_free
    mov rdi, r12
    call ext_choices_begin_try
    test rax, rax
    jz .Lcpt_fail
    mov r15, rax
    mov rdi, rax
    call ext_choices_cleanup_step
    test rax, rax
    jnz .Lcpt_fail
    mov rdi, r15
    call ext_choices_free
    test rax, rax
    jnz .Lcpt_fail
.Lcpt_guard_free:
    mov rdi, r12
    call ext_choices_guard_free
    mov [rip + cpt_trailer + 16], rax
    mov edi, 1
    lea rsi, [rip + cpt_trailer]
    mov edx, 24
    call write_all
    test rax, rax
    js .Lcpt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cpt_live]
    jne .Lcpt_fail
    xor edi, edi
    call sys_exit
.Lcpt_fail:
    mov edi, 124
    call sys_exit

cpt_fresh:
    cmp qword ptr [rip + cpt_late_cancel], 0
    jne 1f
    cmp byte ptr [rdi], 'x'
    je 1f
    cmp byte ptr [rdi], 'i'
    je 2f
    xor eax, eax
    ret
1:  mov rax, -125
    ret
2:  mov eax, 1
    ret
cpt_fresh_forbidden:
    mov edi, 123
    call sys_exit

FN cpt_replace
    inc qword ptr [rip + cpt_native_calls]
    cmp qword ptr [rip + cpt_fault], 1
    je .Lcpt_native_error
    cmp qword ptr [rip + cpt_fault], 2
    je .Lcpt_after_native
    cmp qword ptr [rip + cpt_fault], 3
    je .Lcpt_replace_pause
    cmp qword ptr [rip + cpt_fault], 5
    je .Lcpt_native_error
    jmp ext_choices_raw_replace
.Lcpt_after_native:
    PROLOGUE
    call ext_choices_raw_replace
    test rax, rax
    jnz .Lcpt_fail
    mov rax, -5
    xor edx, edx
    EPILOGUE
.Lcpt_replace_pause:
    PROLOGUE
    mov byte ptr [rip + cpt_hold], '!'
    mov edi, 1
    lea rsi, [rip + cpt_hold]
    mov edx, 1
    call write_all
    xor edi, edi
    lea rsi, [rip + cpt_hold]
    mov edx, 1
    SYS SYS_read
    mov rax, -5
    xor edx, edx
    EPILOGUE
.Lcpt_pending:
    mov [rip + cpt_replace_args], rdi
    mov [rip + cpt_replace_args + 8], rsi
    mov [rip + cpt_replace_args + 16], rdx
    mov [rip + cpt_replace_args + 24], rcx
    mov [rip + cpt_replace_args + 32], r8
    mov [rip + cpt_replace_args + 40], r9
    mov rax, -115
    xor edx, edx
    ret
.Lcpt_native_error:
    mov rax, -5
    xor edx, edx
    ret
FN cpt_replace_poll
    jmp ext_choices_raw_replace_poll
FN cpt_stage_check
    cmp qword ptr [rip + cpt_fault], 902
    jne 1f
    PROLOGUE 16
    call ext_choices_stage_check
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov qword ptr [rip + cpt_late_cancel], 1
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
1:  jmp ext_choices_stage_check

FN cpt_read_final
    cmp qword ptr [rip + cpt_fault], 901
    jne 9f
    PROLOGUE 16
    call ext_choices_read_final
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov qword ptr [rip + cpt_late_cancel], 1
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
9:
    cmp qword ptr [rip + cpt_fault], 5
    jne 1f
    cmp qword ptr [rip + cpt_native_calls], 0
    je 1f
    mov rax, -13
    xor edx, edx
    ret
1:  jmp ext_choices_read_final

FN cpt_alloc
    inc qword ptr [rip + cpt_alloc_count]
    mov rax, [rip + cpt_alloc_count]
    add rax, 100
    cmp rax, [rip + cpt_fault]
    jne 1f
    xor eax, eax
    ret
1:  jmp mem_alloc_try
FN cpt_write
    inc qword ptr [rip + cpt_write_count]
    cmp qword ptr [rip + cpt_fault], 201
    je .Lcpt_zero
    cmp qword ptr [rip + cpt_fault], 202
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 203
    jne 1f
    cmp qword ptr [rip + cpt_write_count], 1
    jne .Lcpt_ioerror
    mov edx, 1
    jmp ext_store_raw_write
1:  cmp qword ptr [rip + cpt_fault], 204
    jne 2f
    cmp qword ptr [rip + cpt_write_count], 1
    je .Lcpt_eintr
2:  jmp ext_store_raw_write
FN cpt_sync
    inc qword ptr [rip + cpt_sync_count]
    cmp qword ptr [rip + cpt_fault], 205
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 707
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 712
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 708
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 709
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 206
    jne 1f
    cmp qword ptr [rip + cpt_sync_count], 1
    je .Lcpt_eintr
1:  jmp ext_store_raw_sync
FN cpt_create
    cmp qword ptr [rip + cpt_fault], 207
    je .Lcpt_ioerror
    cmp qword ptr [rip + cpt_fault], 208
    jne 1f
    mov rax, -17
    xor edx, edx
    ret
1:  jmp ext_choices_raw_create
FN cpt_stat
    cmp qword ptr [rip + cpt_fault], 209
    jne 2f
    mov rax, [rip + cpt_current]
    test rax, rax
    jz 2f
    cmp [rax + ECP_source], rdi
    je .Lcpt_ioerror
2:  jmp ext_root_stat
FN cpt_identity
    cmp qword ptr [rip + cpt_fault], 210
    jne 2f
    mov rax, [rip + cpt_current]
    test rax, rax
    jz 2f
    cmp [rax + ECP_source], rdi
    je .Lcpt_ioerror
2:  jmp ext_root_identity
FN cpt_close
    PROLOGUE
    call ext_root_close
    cmp qword ptr [rip + cpt_fault], 211
    jne 1f
    cmp qword ptr [rip + cpt_cleanup_running], 1
    jne 1f
    inc qword ptr [rip + cpt_close_count]
    cmp qword ptr [rip + cpt_close_count], 1
    jne 1f
    mov rax, -9
1:  EPILOGUE
.Lcpt_zero:
    xor eax, eax
    xor edx, edx
    ret
.Lcpt_ioerror:
    mov rax, -5
    xor edx, edx
    ret
.Lcpt_eintr:
    mov rax, -EINTR
    xor edx, edx
    ret

.ifdef WINDOWS
# Inspect the actual stage's native ACL, not only the descriptor supplied at creation.
cpt_security_check:
    PROLOGUE 160
    mov rbx, rdi
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 104], 0
    mov qword ptr [rsp + 112], 0
    mov rcx, [rbx + ECP_source]
    mov edx, 1
    mov r8d, 4
    xor r9d, r9d
    mov qword ptr [rsp + 32], 0
    lea rax, [rsp + 104]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    lea rax, [rsp + 96]
    mov [rsp + 56], rax
    API GetSecurityInfo
    test eax, eax
    jnz .Lcpt_security_fail1
    mov rcx, [rsp + 96]
    lea rdx, [rsp + 128]
    lea r8, [rsp + 132]
    API GetSecurityDescriptorControl
    test eax, eax
    jz .Lcpt_security_fail2
    test word ptr [rsp + 128], 0x1000
    jnz 1f
    cmp qword ptr [rip + cpt_wine], 1
    jne .Lcpt_security_fail3
1:  # Wine drops SE_DACL_PROTECTED on files; real Windows must prove this flag.
    mov rcx, [rbx + ECP_security]
    lea rdx, [rsp + 120]
    lea r8, [rsp + 112]
    lea r9, [rsp + 124]
    API GetSecurityDescriptorDacl
    test eax, eax
    jz .Lcpt_security_fail4
    cmp dword ptr [rsp + 120], 1
    jne .Lcpt_security_fail5
    mov rdi, [rsp + 104]
    mov rsi, [rsp + 112]
    test rdi, rdi
    jz .Lcpt_security_fail6
    test rsi, rsi
    jz .Lcpt_security_fail7
    cmp qword ptr [rip + cpt_wine], 1
    jne 2f
    call cpt_acl_subset
    test eax, eax
    jz .Lcpt_security_fail10
    jmp 3f
2:  cmp word ptr [rdi + 4], 3
    jne .Lcpt_security_fail8
    movzx edx, word ptr [rdi + 2]
    cmp dx, [rsi + 2]
    jne .Lcpt_security_fail9
    call memeq
    test eax, eax
    jz .Lcpt_security_fail10
3:  mov rcx, [rsp + 96]
    API LocalFree
    test rax, rax
    jnz .Lcpt_security_fail11
    EPILOGUE
.Lcpt_security_fail1:
    mov r14d, 151
    jmp .Lcpt_security_dump
.Lcpt_security_fail2:
    mov r14d, 152
    jmp .Lcpt_security_dump
.Lcpt_security_fail3:
    mov r14d, 153
    jmp .Lcpt_security_dump
.Lcpt_security_fail4:
    mov r14d, 154
    jmp .Lcpt_security_dump
.Lcpt_security_fail5:
    mov r14d, 155
    jmp .Lcpt_security_dump
.Lcpt_security_fail6:
    mov r14d, 156
    jmp .Lcpt_security_dump
.Lcpt_security_fail7:
    mov r14d, 157
    jmp .Lcpt_security_dump
.Lcpt_security_fail8:
    mov r14d, 158
    jmp .Lcpt_security_dump
.Lcpt_security_fail9:
    mov r14d, 159
    jmp .Lcpt_security_dump
.Lcpt_security_fail10:
    mov r14d, 160
    jmp .Lcpt_security_dump
.Lcpt_security_fail11:
    mov r14d, 161
    jmp .Lcpt_security_dump

.Lcpt_security_dump:
    mov edi, 2
    lea rsi, [rsp + 128]
    mov edx, 8
    call write_all
    mov rsi, [rsp + 104]
    test rsi, rsi
    jz 1f
    mov edi, 2
    mov edx, 8
    call write_all
1:  mov rsi, [rsp + 112]
    test rsi, rsi
    jz 2f
    mov edi, 2
    mov edx, 8
    call write_all
2:  mov edi, r14d
    call sys_exit

# Wine may round-trip a restrictive subset through Unix permissions. Require every
# returned ACE to equal a requested ACE and retain the requested current-user ACE.
# Real Windows above requires exact complete ACL and SE_DACL_PROTECTED.
cpt_acl_subset:
    PROLOGUE 32
    movzx eax, word ptr [rdi + 4]
    cmp eax, 1
    jb .Lcpt_acl_no
    cmp eax, 3
    ja .Lcpt_acl_no
    mov [rsp + 16], rax
    mov qword ptr [rsp + 24], 0
    movzx eax, word ptr [rdi + 2]
    lea rbx, [rdi + rax]
    lea r12, [rdi + 8]
    mov [rsp], rsi
    movzx eax, word ptr [rsi + 2]
    add rax, rsi
    mov [rsp + 8], rax
    xor r13d, r13d
.Lcpt_acl_actual:
    cmp qword ptr [rsp + 16], 0
    je .Lcpt_acl_done
    lea rax, [r12 + 8]
    cmp rax, rbx
    ja .Lcpt_acl_no
    movzx edx, word ptr [r12 + 2]
    cmp edx, 8
    jb .Lcpt_acl_no
    lea rax, [r12 + rdx]
    cmp rax, rbx
    ja .Lcpt_acl_no
    mov r14, [rsp]
    add r14, 8
    xor r15d, r15d
.Lcpt_acl_expected:
    cmp r15, 3
    jae .Lcpt_acl_no
    lea rax, [r14 + 8]
    cmp rax, [rsp + 8]
    ja .Lcpt_acl_no
    movzx eax, word ptr [r14 + 2]
    cmp eax, 8
    jb .Lcpt_acl_no
    lea rcx, [r14 + rax]
    cmp rcx, [rsp + 8]
    ja .Lcpt_acl_no
    cmp ax, [r12 + 2]
    jne .Lcpt_acl_next
    mov rdi, r12
    mov rsi, r14
    mov rdx, rax
    call memeq
    test eax, eax
    jnz .Lcpt_acl_found
.Lcpt_acl_next:
    movzx eax, word ptr [r14 + 2]
    add r14, rax
    inc r15
    jmp .Lcpt_acl_expected
.Lcpt_acl_found:
    bts r13, r15
    movzx eax, word ptr [r12 + 2]
    add r12, rax
    dec qword ptr [rsp + 16]
    jmp .Lcpt_acl_actual
.Lcpt_acl_done:
    xor eax, eax
    test r13d, 4
    setnz al
    EPILOGUE
.Lcpt_acl_no:
    xor eax, eax
    EPILOGUE

FN cpt_security_local_free
    inc qword ptr [rip + cpt_security_frees]
    cmp qword ptr [rip + cpt_fault], 701
    jne 1f
    cmp qword ptr [rip + cpt_security_frees], 1
    jne 1f
    PROLOGUE 96
    mov r12, rcx
    mov ecx, 5
    API SetLastError
    mov rax, r12
    EPILOGUE
1:  jmp [rip + __imp_LocalFree]
FN cpt_security_open_token
    cmp qword ptr [rip + cpt_fault], 702
    je cpt_security_api_fail
    jmp [rip + __imp_OpenProcessToken]
FN cpt_security_token_info
    cmp qword ptr [rip + cpt_fault], 703
    je cpt_security_api_fail
    jmp [rip + __imp_GetTokenInformation]
FN cpt_security_sid
    cmp qword ptr [rip + cpt_fault], 704
    je cpt_security_api_fail
    jmp [rip + __imp_ConvertSidToStringSidW]
FN cpt_security_descriptor
    cmp qword ptr [rip + cpt_fault], 705
    je cpt_security_api_fail
    jmp [rip + __imp_ConvertStringSecurityDescriptorToSecurityDescriptorW]
FN cpt_security_close_token
    PROLOGUE 96
    API CloseHandle
    cmp qword ptr [rip + cpt_fault], 706
    jne 1f
    mov ecx, 6
    API SetLastError
    xor eax, eax
1:  EPILOGUE
cpt_security_api_fail:
    PROLOGUE 96
    mov ecx, 5
    API SetLastError
    xor eax, eax
    EPILOGUE

.endif

FN cpt_snapshot
    cmp qword ptr [rip + cpt_fault], 710
    jne 1f
    xor eax, eax
    mov rdx, -5
    mov r8, -9
    ret
1:  jmp ext_choices_snapshot_try
.ifdef WINDOWS
# Delay observation of one genuinely issued native operation. Never resend after pending.
FN cpt_native_set_info
    mov r10, [rsp + 40]
    PROLOGUE 96
    mov r12, rdx
    mov r13, r10
    cmp r13d, 10
    jne 8f
    inc qword ptr [rip + cpt_native_renames]
8:  cmp r13d, 13
    jne 8f
    inc qword ptr [rip + cpt_native_unlinks]
8:  cmp qword ptr [rip + cpt_fault], 708
    jne 1f
    cmp r13d, 13
    jne 1f
    mov eax, 0xc0000022
    EPILOGUE
1:  mov [rsp + 32], r13
    API NtSetInformationFile
    cmp qword ptr [rip + cpt_fault], 711
    jne 7f
    cmp r13d, 10
    je 6f
7:  cmp qword ptr [rip + cpt_fault], 712
    jne 7f
    cmp r13d, 13
    je 6f
7:  cmp qword ptr [rip + cpt_fault], 4
    jne 2f
    cmp r13d, 10
    je 3f
2:  cmp qword ptr [rip + cpt_fault], 707
    jne 9f
    cmp r13d, 13
    jne 9f
3:  mov [rip + cpt_async_iosb], r12
    cmp eax, 0x103
    jne 4f
    mov qword ptr [rip + cpt_async_kind], 2 # real native pending, use actual native wait.
    EPILOGUE
6:  mov [rip + cpt_async_iosb], r12
    mov qword ptr [rip + cpt_async_kind], 2
    mov eax, 0x103             # completion may precede first wait; leave real IOSB intact.
    EPILOGUE
4:  mov dword ptr [rip + cpt_async_status], eax
    mov qword ptr [rip + cpt_async_kind], 1
    mov qword ptr [r12], 0x103
    mov eax, 0x103
9:  EPILOGUE
FN cpt_native_wait
    cmp qword ptr [rip + cpt_async_kind], 0
    je 9f
    inc qword ptr [rip + cpt_async_polls]
    cmp qword ptr [rip + cpt_async_polls], 1
    je 1f
    cmp qword ptr [rip + cpt_async_polls], 2
    je 2f
    cmp qword ptr [rip + cpt_async_kind], 2
    je 9f
    mov rax, [rip + cpt_async_iosb]
    cmp qword ptr [rax], 0x103
    jne .Lcpt_fail
    mov edx, [rip + cpt_async_status]
    mov [rax], edx
    mov qword ptr [rip + cpt_async_kind], 0
    xor eax, eax
    ret
1:  PROLOGUE 96
    mov ecx, 5
    API SetLastError
    mov eax, -1
    EPILOGUE
2:  mov eax, 258
    ret
9:  jmp [rip + __imp_WaitForSingleObject]
FN cpt_store_close
    PROLOGUE
    call ext_root_close
    cmp qword ptr [rip + cpt_fault], 708
    je 1f
    cmp qword ptr [rip + cpt_fault], 709
    jne 2f
1:  mov rax, -9
2:  EPILOGUE
.endif
