# A single work ledger is shared by schema scans, INI, comparisons and copies.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.text
# step(view,bytes1..65536)->0building/1ready/-errno,
# RDX scanned/copied/compared byte units, RCX phase actions, R8 allocation/free calls.
FN ext_settings_view_step
    test rdi, rdi
    jz .Lesvs_invalid
    test rsi, rsi
    jz .Lesvs_invalid
    cmp rsi, 65536
    ja .Lesvs_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call esv_check_epochs
    test rax, rax
    js .Lesvs_no_work_error
    cmp qword ptr [rbx + EV_phase], EVP_READY
    je .Lesvs_already_ready
    cmp qword ptr [rbx + EV_phase], EVP_FAILED
    jne 1f
    mov rax, [rbx + EV_error]
    jmp .Lesvs_no_work_error
1:  mov [rbx + EV_bytesleft], r12
    mov qword ptr [rbx + EV_phasesleft], 1024
    mov qword ptr [rbx + EV_allocsleft], 64
.Lesvs_loop:
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lesvs_pending
    cmp qword ptr [rbx + EV_phasesleft], 0
    je .Lesvs_pending
    cmp qword ptr [rbx + EV_allocsleft], 0
    je .Lesvs_pending
    mov rax, [rbx + EV_phase]
    cmp rax, EVP_READY
    je .Lesvs_ready
    cmp rax, EVP_FINISH
    je .Lesvs_finish
    dec qword ptr [rbx + EV_phasesleft]
    mov rdi, rbx
    cmp rax, EVP_BASE_COPY
    jbe .Lesvs_capture
    cmp rax, EVP_RAW_COMPARE
    jbe .Lesvs_raw
    cmp rax, EVP_NORM_INSTALL
    jbe .Lesvs_normalize
    cmp rax, EVP_DIRTY_KEY
    jbe .Lesvs_dirty
    mov rax, -22
    jmp .Lesvs_failed
.Lesvs_capture:
    call esv_capture_step
    jmp .Lesvs_after
.Lesvs_raw:
    call esv_raw_step
    jmp .Lesvs_after
.Lesvs_normalize:
    call esv_normalize_step
    jmp .Lesvs_after
.Lesvs_dirty:
    call esv_dirty_step
.Lesvs_after:
    test rax, rax
    js .Lesvs_failed
    jmp .Lesvs_loop
.Lesvs_finish:
    dec qword ptr [rbx + EV_phasesleft]
    mov rdi, rbx
    call esv_finish_step
    test rax, rax
    js .Lesvs_failed
    jmp .Lesvs_loop
.Lesvs_failed:
    mov [rbx + EV_error], rax
    mov qword ptr [rbx + EV_phase], EVP_FAILED
    jmp .Lesvs_return
.Lesvs_pending:
    xor eax, eax
    jmp .Lesvs_return
.Lesvs_ready:
    mov eax, 1
.Lesvs_return:
    mov rdx, r12
    sub rdx, [rbx + EV_bytesleft]
    mov ecx, 1024
    sub rcx, [rbx + EV_phasesleft]
    mov r8d, 64
    sub r8, [rbx + EV_allocsleft]
    EPILOGUE
.Lesvs_already_ready:
    mov eax, 1
.Lesvs_no_work_error:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
.Lesvs_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    ret
