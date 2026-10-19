# Failure at the actual OS unmap boundary. After consumed transfer, never read AP.
.bss
.p2align 3
.globl svaf_target, svaf_failed, svaf_charge, svaf_cleanup
svaf_target: .quad 0
svaf_failed: .quad 0
svaf_charge: .quad 0
svaf_cleanup: .quad 0
svaf_status: .zero 32
svaf_before: .quad 0
svaf_live: .quad 0
svaf_boundary_charge: .quad 0
.text
# Captures the real child-provider unmap result when SAP releases its old model.
.globl svaf_model_gc
svaf_model_gc:
    PROLOGUE
    cmp qword ptr [rip + svaf_failed], 0
    jne 8f
    mov edi, 1
8:  call ext_settings_model_gc
    mov r12, rax
    test rdx, rdx
    jns 1f
    cmp qword ptr [rip + svaf_failed], 1
    jne svw_fail
    mov [rip + svaf_cleanup], rdx
    call ext_settings_memory_total
    cmp [rip + svaf_boundary_charge], rax
    jne svw_fail
    call ext_settings_memory_pending
    cmp rax, 1
    jne svw_fail
1:  mov rax, r12
    xor edx, edx
    EPILOGUE
svaf_verify_retained:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 248
    cmp qword ptr [rip + svaf_failed], 1
    jne svw_fail
    mov qword ptr [rip + svw_stage], 253
    cmp qword ptr [rip + svaf_cleanup], 0
    jge svw_fail
    mov qword ptr [rip + svw_stage], 249
    lea rdi, [rip + svaf_status]
    call ext_settings_memory_status
    cmp qword ptr [rip + svaf_status + 8], 1
    jne svw_fail
    mov rax, [rip + svaf_charge]
    cmp [rip + svaf_status + 16], rax
    jne svw_fail
    cmp [rip + svaf_status], rax
    jb svw_fail
    mov rax, [rip + svaf_status]
    mov [rip + svaf_before], rax
    mov rax, [rip + g_mem_live]
    mov [rip + svaf_live], rax
    call ext_settings_adoption_pending
    test rax, rax
    jnz svw_fail
    mov qword ptr [rip + svw_stage], 250
    call ext_settings_memory_timeout
    cmp rax, 1
    jl svw_fail
    cmp rax, 1000
    ja svw_fail
    mov rdx, rax
    xor edi, edi
    xor esi, esi
    SYS SYS_poll
    mov qword ptr [rip + svw_stage], 251
    mov edi, 1
    call ext_settings_memory_gc
    cmp rax, 1
    jne svw_fail
    cmp rcx, 1
    jne svw_fail
    test rdx, rdx
    jnz svw_fail
    lea rdi, [rip + svaf_status]
    call ext_settings_memory_status
    cmp qword ptr [rip + svaf_status + 8], 0
    jne svw_fail
    cmp qword ptr [rip + svaf_status + 16], 0
    jne svw_fail
    mov qword ptr [rip + svw_stage], 252
    mov rax, [rip + svaf_before]
    sub rax, [rip + svaf_charge]
    cmp [rip + svaf_status], rax
    jne svw_fail
    mov rax, [rip + svaf_live]
    dec rax
    cmp [rip + g_mem_live], rax
    jne svw_fail
    call ext_settings_memory_ack_cleanup
    test rax, rax
    jnz svw_fail
    EPILOGUE

# A read-only charge capture at the exact native failure boundary.
svaf_boundary:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rcx
    mov [rsp + 24], rdx
    mov [rsp + 32], r8
    mov [rsp + 40], r9
    call ext_settings_memory_total
    mov [rip + svaf_boundary_charge], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rcx, [rsp + 16]
    mov rdx, [rsp + 24]
    mov r8, [rsp + 32]
    mov r9, [rsp + 40]
    EPILOGUE
