# Checked keeper ownership. Native values remain in their slots until consumed.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/taskproc.inc"
.section .rodata
kp_close_offsets: .quad KX_control,KX_status,KX_output,KX_launchfd,KX_lease,KX_job,KX_helper
kh_close_offsets: .quad KH_gate,KH_setup,KH_process,KH_job,KH_lease,KH_scan
.text
FN keeper_cleanup_contract_version
    mov eax, 1
    ret

# slot, &unknownMask (knownMask follows), bit, kind(0FD/-1,1raw/-1,2raw/0).
# No retry of a retained disposition. Only keeper_retry_known explicitly clears known.
FN kp_close_owned
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, [rbx]
    test r14, r14
    jz 1f
    cmp r14, 1
    je 1f
    test rdi, rdi
    jz .Lkco_empty
    jmp 2f
1:  cmp rdi, -1
    je .Lkco_empty
2:  bt qword ptr [r12], r13
    jc .Lkco_unknown
    bt qword ptr [r12 + 8], r13
    jc .Lkco_known
    test r14, r14
    jnz 3f
    call ext_fd_close_checked
    jmp 4f
3:  call ext_root_close
4:  cmp rdx, 1
    je .Lkco_consumed
    mov [rsp], rax
    test rax, rax
    js 5f
    mov qword ptr [rsp], -5
5:  cmp rdx, 2
    jne 6f
    bts qword ptr [r12], r13
    mov edx, 2
    mov rax, [rsp]
    EPILOGUE
6:  bts qword ptr [r12 + 8], r13
    xor edx, edx
    mov rax, [rsp]
    EPILOGUE
.Lkco_consumed:
    mov qword ptr [rbx], -1
    cmp r14, 2
    jne 7f
    mov qword ptr [rbx], 0
7:  mov edx, 1
    EPILOGUE
.Lkco_empty:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lkco_unknown:
    mov rax, -5
    mov edx, 2
    EPILOGUE
.Lkco_known:
    mov rax, -16
    xor edx, edx
    EPILOGUE

# First cleanup is separate from operation primary. Never overwrite an earlier diagnostic.
FN kp_note_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + KX_cleanup], 0
    jne 1f
    mov [rdi + KX_cleanup], rsi
1:  ret
FN kh_note_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + KH_cleanup], 0
    jne 1f
    mov [rdi + KH_cleanup], rsi
1:  ret

FN kp_close_field
    PROLOGUE 16
    mov rbx, rdi
    cmp rsi, 6
    ja .Lkcf_invalid
.ifndef WINDOWS
    cmp rsi, 5
    jae .Lkcf_empty           # POSIX helper is a PID, never a closeable descriptor.
.endif
    mov r12, rsi
    lea rax, [rip + kp_close_offsets]
    mov rax, [rax + r12*8]
    lea rdi, [rbx + rax]
    lea rsi, [rbx + KX_close_unknown]
    mov rdx, r12
    xor ecx, ecx
    cmp r12, 4
    jb 1f
    mov ecx, 1
    je 1f
    mov ecx, 2
1:  call kp_close_owned
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov rsi, rax
    call kp_note_cleanup
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
.Lkcf_empty:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lkcf_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE

FN kp_native_init
    PROLOGUE
    mov rbx, rdi
    xor esi, esi
    mov edx, KB_SIZE
    call memset
    mov rdi, rbx
    mov esi, 255
    mov edx, 72
    call memset
    EPILOGUE

# One fixed pass: each untried close and each allocation at most once.
# rsi1 skips memory while caller's bounded retry delay is pending.
FN kp_native_cleanup
    PROLOGUE 112
    mov [rsp + 96], rsi
    mov rbx, rdi
.ifdef WINDOWS
    cmp qword ptr [rbx + KB_attr], 0
    je 1f
    mov qword ptr [rbx + KB_attr], 0
    mov rcx, [rbx + KB_mem + 32]
    API DeleteProcThreadAttributeList
1:
.endif
    xor r12d, r12d
2:  lea rdi, [rbx + r12*8]
    lea rsi, [rbx + KB_unknown]
    mov rdx, r12
    xor ecx, ecx
    call kp_close_owned
    test rax, rax
    jns 3f
    cmp qword ptr [rbx + KB_cleanup], 0
    jne 3f
    mov [rbx + KB_cleanup], rax
3:  inc r12
    cmp r12, 9
    jb 2b
    xor r12d, r12d
4:  lea rdi, [rbx + r12*8 + KB_raw]
    lea rsi, [rbx + KB_unknown]
    lea rdx, [r12 + 9]
    mov ecx, 2
    call kp_close_owned
    test rax, rax
    jns 5f
    cmp qword ptr [rbx + KB_cleanup], 0
    jne 5f
    mov [rbx + KB_cleanup], rax
5:  inc r12
    cmp r12, 10
    jb 4b
    xor r12d, r12d
    xor r13d, r13d
    cmp qword ptr [rsp + 96], 0
    jne 9f
6:  mov rdi, [rbx + r12*8 + KB_mem]
    test rdi, rdi
    jz 8f
    call prep_cleanup_free
    cmp rdx, 1
    jne 7f
    mov qword ptr [rbx + r12*8 + KB_mem], 0
    jmp 8f
7:  inc r13
    test rax, rax
    js 71f
    mov rax, -5
71: cmp qword ptr [rbx + KB_cleanup], 0
    jne 8f
    mov [rbx + KB_cleanup], rax
8:  inc r12
    cmp r12, 8
    jb 6b
9:  xor ecx, ecx
91: or r13, [rbx + rcx*8 + KB_mem]
    inc ecx
    cmp ecx, 8
    jb 91b
    mov rax, [rbx + KB_unknown]
    or rax, [rbx + KB_known]
    or r13, rax
    xor edx, edx
    test r13, r13
    setz dl
    mov rax, [rbx + KB_cleanup]
    EPILOGUE

# Pure diagnostic/ownership accessor. No filesystem, wait or allocator calls.
FN keeper_cleanup_info
    PROLOGUE
    mov r12, rsi
    test r12, r12
    jz .Lkci_invalid
    call kp_find
    test rax, rax
    jz .Lkci_missing
    mov rbx, rax
    movsxd rax, dword ptr [rbx + KX_error]
    mov [r12], rax
    mov rax, [rbx + KX_cleanup]
    mov [r12 + 8], rax
    mov rax, [rbx + KX_native + KB_unknown]
    shl rax, 7
    or rax, [rbx + KX_close_unknown]
    mov [r12 + 16], rax
    mov rax, [rbx + KX_native + KB_known]
    shl rax, 7
    or rax, [rbx + KX_close_known]
    mov [r12 + 24], rax
    mov rax, [rbx + KX_native_state]
    mov [r12 + 32], rax
    mov rax, [rbx + KX_retry_due]
    mov [r12 + 40], rax
    xor edx, edx
    xor ecx, ecx
1:  cmp qword ptr [rbx + rcx*8 + KX_native + KB_mem], 0
    je 2f
    lea rax, [rcx + 26]
    bts rdx, rax
2:  inc ecx
    cmp ecx, 8
    jb 1b
    cmp qword ptr [rbx + KX_frame], 0
    je 3f
    bts rdx, 34
3:  mov [r12 + 48], rdx
    mov rax, [rbx + KX_lifetime_ready]
    mov [r12 + 56], rax
    xor eax, eax
    EPILOGUE
.Lkci_invalid:
    mov rax, -22
    EPILOGUE
.Lkci_missing:
    mov rax, -2
    EPILOGUE

# Explicit one-shot retry is available ONLY for known retained closes.
FN keeper_retry_known
    PROLOGUE
    mov r12, rsi
    cmp r12, 25
    ja .Lkkr_invalid
    call kp_find
    test rax, rax
    jz .Lkkr_missing
    mov rbx, rax
    cmp r12, 7
    jae 2f
    bt qword ptr [rbx + KX_close_known], r12
    jnc .Lkkr_invalid
    btr qword ptr [rbx + KX_close_known], r12
    mov rdi, rbx
    mov rsi, r12
    call kp_close_field
    EPILOGUE
2:  sub r12, 7
    bt qword ptr [rbx + KX_native + KB_known], r12
    jnc .Lkkr_invalid
    btr qword ptr [rbx + KX_native + KB_known], r12
    lea rdi, [rbx + r12*8 + KX_native + KB_fds]
    xor ecx, ecx
    cmp r12, 9
    jb 3f
    mov ecx, 2
3:  lea rsi, [rbx + KX_native + KB_unknown]
    mov rdx, r12
    call kp_close_owned
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, rax
    call kp_note_cleanup
    mov rax, r12
    mov rdx, r13
    EPILOGUE
.Lkkr_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lkkr_missing:
    mov rax, -2
    xor edx, edx
    EPILOGUE

# Helper native fields and explicit inherited virtual descriptors. Private helper only.
FN kh_close_field
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 5
    jbe 1f
    cmp r12, 7
    jb .Lkhcf_invalid
    cmp r12, 11
    ja .Lkhcf_invalid
    lea rax, [r12 - 7]
    lea rdi, [rbx + rax*8 + KH_stdio]
    xor ecx, ecx
    jmp 3f
1:
.ifndef WINDOWS
    cmp r12, 2
    je .Lkhcf_empty
    cmp r12, 3
    je .Lkhcf_empty
.endif
    lea rax, [rip + kh_close_offsets]
    mov rax, [rax + r12*8]
    lea rdi, [rbx + rax]
    xor ecx, ecx
    cmp r12, 4
    jne 2f
    mov ecx, 1
2:
.ifdef WINDOWS
    test r12, r12
    jnz 21f
    mov ecx, 1
21: cmp r12, 2
    jb 3f
    cmp r12, 3
    ja 3f
    mov ecx, 2
.endif
3:  lea rsi, [rbx + KH_unknown]
    mov rdx, r12
    call kp_close_owned
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    cmp qword ptr [rsp], 0
    jns 4f
    or dword ptr [rbx + KH_flags], KP_FAILED | KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
    cmp dword ptr [rbx + KH_error], 0
    jne 4f
    mov eax, [rsp]
    mov [rbx + KH_error], eax
4:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
.Lkhcf_empty:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lkhcf_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# Acquired store guards remain helper-owned until each raw close consumes.
# Guard root/lock use helper disposition bits12/13; no generic guard destructor change.
.include "app/extstore.inc"
FN kh_guard_release
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + KH_guard]
    test r12, r12
    jz 5f
    lea rdi, [r12 + ESG_lock]
    lea rsi, [rbx + KH_unknown]
    mov edx, 13
    mov ecx, 1
    call kp_close_owned
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    lea rdi, [r12 + ESG_root]
    lea rsi, [rbx + KH_unknown]
    mov edx, 12
    mov ecx, 1
    call kp_close_owned
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    cmp qword ptr [r12 + ESG_root], -1
    jne 5f
    cmp qword ptr [r12 + ESG_lock], -1
    jne 5f
    mov rdi, [r12 + ESG_path]
    call prep_cleanup_free
    cmp rdx, 1
    jne 4f
    mov qword ptr [r12 + ESG_path], 0
    mov rdi, r12
    call prep_cleanup_free
    cmp rdx, 1
    jne 4f
    mov qword ptr [rbx + KH_guard], 0
    jmp 5f
4:  mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
5:  mov rax, [rbx + KH_cleanup]
    EPILOGUE

# Called once only after the existing native whole-target lifetime proof.
# Retained helper resources stay owned by the process until collected nonzero exit.
FN kh_final_cleanup
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + KH_cleanup_attempted], 0
    jne 9f
    mov qword ptr [rbx + KH_cleanup_attempted], 1
    mov rdi, rbx
    call kp_extension_cleanup
    xor r12d, r12d
1:  cmp r12, 6
    je 2f
    cmp r12, 8
    je 2f                  # final status writer must remain live until terminal flush
    mov rdi, rbx
    mov rsi, r12
    call kh_close_field
2:  inc r12
    cmp r12, 12
    jb 1b
    lea rdi, [rbx + KH_native]
    xor esi, esi
    cmp qword ptr [rbx + KH_native + KB_cleanup], 0
    je 21f
    # Existing failed scratch belongs to this process through collected exit111.
    mov esi, 1
21: call kp_native_cleanup
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    mov rdi, [rbx + KH_frame]
    call prep_cleanup_free
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    cmp r12, 1
    jne 3f
    mov qword ptr [rbx + KH_frame], 0
3:  cmp qword ptr [rbx + KH_cleanup], 0
    je 9f
    or dword ptr [rbx + KH_flags], KP_FAILED | KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
    cmp dword ptr [rbx + KH_error], 0
    jne 9f
    mov eax, [rbx + KH_cleanup]
    mov [rbx + KH_error], eax
9:  mov rax, [rbx + KH_cleanup]
    EPILOGUE

# Merge a primary operation status with mandatory cleanup, retaining both diagnostics.
FN kh_merge_status
    mov rax, rsi
    test rdx, rdx
    jns 2f
    cmp qword ptr [rdi + KH_cleanup], 0
    jne 1f
    mov [rdi + KH_cleanup], rdx
1:  test rax, rax
    js 2f
    mov rax, rdx
2:  ret

# Canonical terminal proof. Parent cleanup diagnostics do not invalidate verified completion.
# A collected cleanup111 is distinct from early exec111.
# Every field here was validated by kp_status and actual native collection.
FN kp_cleanup_terminal
    cmp qword ptr [rdi + KX_native_state], KN_REAPED
    jne 1f
    cmp dword ptr [rdi + KX_reaped], 1
    jne 1f
    cmp qword ptr [rdi + KX_status_eof], 1
    jne 1f
    cmp qword ptr [rdi + KX_protocol_bad], 0
    jne 1f
    cmp dword ptr [rdi + KX_helper_exit], 0
    je 2f
    cmp dword ptr [rdi + KX_helper_exit], 111
    jne 1f
    mov eax, [rdi + KX_wireflags]
    and eax, KP_DONE | KP_FAILED | KP_DEFERRED
    cmp eax, KP_DONE | KP_FAILED | KP_DEFERRED
    jne 1f
    movsxd rax, dword ptr [rdi + KX_lastframe + 20]
    cmp rax, -1
    jg 1f
    cmp rax, -4095
    jl 1f
2:  test dword ptr [rdi + KX_wireflags], KP_DONE
    jz 1f
    mov eax, 1
    ret
1:  xor eax, eax
    ret

# Preserve operation primary before entering any helper cleanup pass.
FN kh_note_primary
    test rsi, rsi
    jns 1f
    cmp dword ptr [rdi + KH_error], 0
    jne 1f
    mov [rdi + KH_error], esi
1:  ret
