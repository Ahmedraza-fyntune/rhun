# Native lifetime collection and raw output retain independent ownership.
.include "rhun.inc"
.text
# First negative cleanup status is independent of the process primary result.
FN ext_host_cleanup_note
    test rsi, rsi
    jns 1f
    cmp dword ptr [rdi + EXT_host_cleanup_error], 0
    jne 1f
    mov [rdi + EXT_host_cleanup_error], esi
1:  ret

# <=64KiB per slice, no protocol dispatch or allocations. A read error is not EOF.
FN ext_host_retire_drain
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + EXT_fbytes], 0
    mov eax, [rbx + EXT_host_cleanup_mask]
    test eax, (1 << 1) | (1 << 9)
    jnz .Lhrd_log
    cmp dword ptr [rbx + EXT_retiring], 3
    je .Lhrd_close
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je .Lhrd_close
    mov r12d, 4
.Lhrd_read:
    mov edi, [rbx + EXT_out]
    test edi, edi
    js .Lhrd_log
    lea rsi, [rip + host_retire_bytes]
    mov edx, 16384
    SYS SYS_read
    cmp rax, -EINTR
    je .Lhrd_next
    cmp rax, -EAGAIN
    je .Lhrd_log
    test rax, rax
    jg .Lhrd_next
    jz .Lhrd_eof
    mov rdi, rbx
    mov rsi, rax
    call ext_host_cleanup_note
    mov dword ptr [rbx + EXT_retiring], 3
    jmp .Lhrd_close
.Lhrd_eof:
    mov dword ptr [rbx + EXT_stdout_eof], 1
.Lhrd_close:
    mov rdi, rbx
    lea rsi, [rbx + EXT_out]
    mov edx, 1
    call ext_host_close_at
    jmp .Lhrd_log
.Lhrd_next:
    dec r12d
    jnz .Lhrd_read
    mov qword ptr [rbx + EXT_fbytes], 1
.Lhrd_log:
    mov eax, [rbx + EXT_host_cleanup_mask]
    test eax, (1 << 2) | (1 << 10)
    jnz .Lhrd_done
    mov edi, [rbx + EXT_log]
    test edi, edi
    js .Lhrd_done
    xor esi, esi
    mov edx, 2
    SYS SYS_lseek
    test rax, rax
    js .Lhrd_error
    cmp rax, EXT_LOG_MAX
    jbe .Lhrd_done
    mov edi, [rbx + EXT_log]
    xor esi, esi
    SYS SYS_ftruncate
    test rax, rax
    jns .Lhrd_done
.Lhrd_error:
    mov rdi, rbx
    mov rsi, rax
    call ext_host_cleanup_note
.Lhrd_done:
    EPILOGUE

# 1 and final result in RDX only on the sole finalization transition, otherwise0.
FN ext_host_keeper_collect
    PROLOGUE 64
    mov rbx, rdi
    mov eax, [rbx + EXT_retiring]
    cmp eax, 1
    je 1f
    cmp eax, 3
    jne .Lhkc_pending
1:  call keeper_cleanup_contract_version
    cmp eax, 1
    jne .Lhkc_contract
    mov rdi, [rbx + EXT_keeper]
    test rdi, rdi
    jz .Lhkc_drain_only
    call keeper_poll
    test rax, rax
    js .Lhkc_poll_error
    mov r12d, edx
    mov rdi, rbx
    call ext_host_retire_drain
    mov rdi, [rbx + EXT_keeper]
    lea rsi, [rsp]
    call keeper_cleanup_info
    test rax, rax
    js .Lhkc_poll_error
    # Poll R8 may contain cleanup fallback. Only info primary is authoritative.
    cmp qword ptr [rsp], 0
    jge 2f
    mov r12d, [rsp]
2:  mov [rbx + EXT_finish_code], r12d
    mov [rbx + EXT_host_native_result], r12d
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call ext_host_cleanup_note
    cmp qword ptr [rsp + 56], 1
    jne .Lhkc_pending
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je .Lhkc_close_keeper
    cmp dword ptr [rbx + EXT_retiring], 3
    je .Lhkc_close_keeper
    cmp qword ptr [rsp + 8], 0
    jl .Lhkc_close_keeper
    mov rax, [rsp + 16]
    or rax, [rsp + 24]
    jz .Lhkc_pending
.Lhkc_close_keeper:
    mov rdi, [rbx + EXT_keeper]
    call keeper_close_checked
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rax
    call ext_host_cleanup_note
    cmp r12, 1
    jne .Lhkc_pending
    mov qword ptr [rbx + EXT_keeper], 0
    mov dword ptr [rbx + EXT_pid], 0
    mov dword ptr [rbx + EXT_activation_stale], 1
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je 6f
    cmp dword ptr [rbx + EXT_retiring], 1
    jne 6f
    mov qword ptr [rbx + EXT_fbytes], 1
6:  # Raw service continues next slice if closing a retained writer made EOF possible.
    jmp .Lhkc_finish_check
.Lhkc_drain_only:
    mov rdi, rbx
    call ext_host_retire_drain
.Lhkc_finish_check:
    cmp qword ptr [rbx + EXT_keeper], 0
    jne .Lhkc_pending
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je 3f
    cmp dword ptr [rbx + EXT_retiring], 3
    jne .Lhkc_pending
3:  mov rdi, rbx
    lea rsi, [rbx + EXT_in]
    xor edx, edx
    call ext_host_close_at
    mov rdi, rbx
    lea rsi, [rbx + EXT_log]
    mov edx, 2
    call ext_host_close_at
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lhkc_pending
    cmp dword ptr [rbx + EXT_in], 0
    jns .Lhkc_pending
    cmp dword ptr [rbx + EXT_out], 0
    jns .Lhkc_pending
    cmp dword ptr [rbx + EXT_log], 0
    jns .Lhkc_pending
    mov rdi, rbx
    call ext_host_prepared_finish_result
    mov edx, eax
    mov [rbx + EXT_finish_code], edx
    mov eax, 2
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je 5f
    mov eax, 4
5:  mov [rbx + EXT_retiring], eax
    mov eax, 1
    EPILOGUE
.Lhkc_poll_error:
    mov rdi, rbx
    mov rsi, rax
    call ext_host_cleanup_note
.Lhkc_pending:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lhkc_contract:
    mov rsi, -22
    mov rdi, rbx
    call ext_host_cleanup_note
    jmp .Lhkc_pending

# Pending keeper0 output needs a bounded timer after its old watcher was removed.
FN ext_host_retire_due
    xor eax, eax
    cmp dword ptr [rdi + EXT_retiring], 1
    jne 1f
    cmp dword ptr [rdi + EXT_out], 0
    js 1f
    cmp qword ptr [rdi + EXT_fbytes], 0
    je 1f
    mov ecx, [rdi + EXT_host_cleanup_mask]
    test ecx, (1 << 1) | (1 << 9)
    jnz 1f
    mov eax, 1
1:  ret
.bss
.p2align 3
host_retire_bytes: .zero 16384

.text
# A new lifetime cannot overwrite retained ownership or erase pending diagnostics.
FN ext_host_start_admit
    mov rax, -16
    cmp qword ptr [rdi + EXT_keeper], 0
    jne 9f
    cmp dword ptr [rdi + EXT_pid], 0
    jne 9f
    cmp dword ptr [rdi + EXT_in], 0
    jns 9f
    cmp dword ptr [rdi + EXT_out], 0
    jns 9f
    cmp dword ptr [rdi + EXT_log], 0
    jns 9f
    cmp dword ptr [rdi + EXT_host_cleanup_mask], 0
    jne 9f
    cmp dword ptr [rdi + EXT_retiring], 1
    je 9f
    cmp dword ptr [rdi + EXT_retiring], 3
    je 9f
    mov dword ptr [rdi + EXT_host_cleanup_error], 0
    xor eax, eax
9:  ret

.text
# EXT, captured monotonic now -> relative eligible native/raw deadline or-1.
FN ext_host_keeper_timeout
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, -1
    call ext_host_retire_due
    test eax, eax
    jz 1f
    mov r13d, 16
1:  mov rdi, [rbx + EXT_keeper]
    test rdi, rdi
    jz .Lhkt_return
    lea rsi, [rsp]
    call keeper_cleanup_info
    test rax, rax
    js .Lhkt_return
    cmp qword ptr [rsp + 56], 1
    jne .Lhkt_normal
    cmp qword ptr [rsp + 48], 0
    jne .Lhkt_memory
    mov rax, [rsp + 16]
    or rax, [rsp + 24]
    jnz .Lhkt_return
.Lhkt_normal:
    mov eax, 20
    jmp .Lhkt_choose
.Lhkt_memory:
    mov rax, [rsp + 40]
    test rax, rax
    jz .Lhkt_choose
    cmp rax, r12
    jbe .Lhkt_due
    sub rax, r12
    jmp .Lhkt_choose
.Lhkt_due:
    xor eax, eax
.Lhkt_choose:
    cmp r13, -1
    je 2f
    cmp rax, r13
    jae .Lhkt_return
2:  mov r13, rax
.Lhkt_return:
    mov rax, r13
    EPILOGUE
