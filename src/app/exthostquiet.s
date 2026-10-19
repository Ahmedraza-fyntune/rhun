# Pure native ownership proof shared by prepared host reference transfers.
.include "rhun.inc"
.text
FN ext_host_native_quiet
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lehq_bad
    call keeper_cleanup_contract_version
    cmp eax, 1
    jne .Lehq_bad
    cmp qword ptr [rbx + EXT_keeper], 0
    jne .Lehq_busy
    cmp dword ptr [rbx + EXT_pid], 0
    jne .Lehq_busy
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lehq_busy
    xor r12d, r12d
1:  lea rax, [rip + ehq_fields]
    mov rax, [rax + r12*8]
    cmp dword ptr [rbx + rax], 0
    jns .Lehq_busy
    inc r12
    cmp r12, 5
    jb 1b
    mov eax, [rbx + EXT_status]
    cmp eax, ES_STARTING
    je .Lehq_busy
    cmp eax, ES_RUNNING
    je .Lehq_busy
    cmp eax, ES_STOPPING
    je .Lehq_busy
    mov eax, [rbx + EXT_retiring]
    test eax, eax
    jz .Lehq_ok
    cmp eax, 2
    je .Lehq_eof
    cmp eax, 4
    jne .Lehq_busy
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Lehq_busy
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jns .Lehq_busy
    jmp .Lehq_ok
.Lehq_eof:
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    jne .Lehq_busy
.Lehq_ok:
    xor eax, eax
    EPILOGUE
.Lehq_bad:
    mov rax, -22
    EPILOGUE
.Lehq_busy:
    mov rax, -16
    EPILOGUE
.section .rodata
.p2align 3
ehq_fields: .quad EXT_in,EXT_out,EXT_log,EXT_host_child_in,EXT_host_child_out
