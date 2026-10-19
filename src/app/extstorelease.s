# Stable package/legacy leases, rooted opens only. No source folder is lifetime authority.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extvalidate.inc"
.section .rodata
.Lesl_packages: .asciz ".packages"
.Lesl_leases: .asciz ".leases"
.Lesl_legacy: .asciz "legacy"
.Lesl_lease: .asciz "lease"
.text
# Internal directory open/create under guard. Creation invalidates prior READY proofs.
# ext_store_dir_try(guard,parent,basename,create0|1)->raw/-errno,secondaryrdx.
FN ext_store_dir_try
    cmp rcx, 1
    ja .Lesl_invalid
    test rcx, rcx
    jz 9f
    cmp qword ptr [rdi + ESG_exclusive], 1
    jne .Lesl_invalid
9:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call ext_store_cancel
    test rax, rax
    js 2f
    test r14, r14
    jz 1f
    cmp qword ptr [rbx + ESG_epoch], -1
    je 3f
    inc qword ptr [rbx + ESG_epoch]
1:  mov rdi, r12
    mov rsi, r13
    mov edx, ER_DIR
    lea rcx, [r14*2]
    mov r8d, 0700
    call ext_root_open_at
    EPILOGUE
2:  xor edx, edx
    EPILOGUE
3:  mov rax, -75
    xor edx, edx
    EPILOGUE

# ext_store_lease_try(guard,owner,name,id64OrNULL,exclusive,create)->raw/-errno,
# rdx secondary cleanup error. Creation requires an exclusive held root guard.
FN ext_store_lease_try
    test rdi, rdi
    jz .Lesl_invalid
    cmp r8, 1
    ja .Lesl_invalid
    cmp r9, 1
    ja .Lesl_invalid
    test r9, r9
    jz 1f
    cmp qword ptr [rdi + ESG_exclusive], 1
    jne .Lesl_invalid
1:  PROLOGUE 592
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp + 576], r8
    mov [rsp + 584], r9
    mov qword ptr [rsp + 520], -1
    mov qword ptr [rsp + 528], -1
    mov qword ptr [rsp + 536], -1
    mov qword ptr [rsp + 544], -1
    mov qword ptr [rsp + 552], -1
    mov qword ptr [rsp + 560], 0
    mov qword ptr [rsp + 568], 0
    mov rdi, r12
    call ext_store_identity_len
    test rax, rax
    jz .Lesl_bad
    lea rdi, [rsp + 32]
    mov rsi, r12
    mov rdx, rax
    call ext_store_identity_encode
    mov rdi, r13
    call ext_store_identity_len
    test rax, rax
    jz .Lesl_bad
    lea rdi, [rsp + 240]
    mov rsi, r13
    mov rdx, rax
    call ext_store_identity_encode
    test r14, r14
    jz .Lesl_legacy_branch
    mov rdi, r14
    call ext_store_id_check
    test eax, eax
    jz .Lesl_bad
    lea rdi, [rsp + 448]
    mov rsi, r14
    mov edx, 64
    call memcpy
    mov byte ptr [rsp + 512], 0
    # Managed package directories must already exist, even when creating lease.
    mov rdi, rbx
    mov rsi, [rbx + ESG_root]
    lea rdx, [rip + .Lesl_packages]
    xor ecx, ecx
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok1
    test rdx, rdx
    jns .Lesl_adapter_ok1
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok1:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 520], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rsp + 32]
    xor ecx, ecx
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok2
    test rdx, rdx
    jns .Lesl_adapter_ok2
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok2:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 528], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rsp + 240]
    xor ecx, ecx
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok3
    test rdx, rdx
    jns .Lesl_adapter_ok3
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok3:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 536], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rsp + 448]
    xor ecx, ecx
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok4
    test rdx, rdx
    jns .Lesl_adapter_ok4
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok4:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 544], rax
    mov r15, rax
    lea r14, [rip + .Lesl_lease]
    jmp .Lesl_open_file
.Lesl_legacy_branch:
    mov dword ptr [rsp + rax + 240], 0x636f6c2e
    mov byte ptr [rsp + rax + 244], 'k'
    mov byte ptr [rsp + rax + 245], 0
    mov rdi, rbx
    mov rsi, [rbx + ESG_root]
    lea rdx, [rip + .Lesl_leases]
    mov rcx, [rsp + 584]
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok5
    test rdx, rdx
    jns .Lesl_adapter_ok5
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok5:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 520], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rip + .Lesl_legacy]
    mov rcx, [rsp + 584]
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok6
    test rdx, rdx
    jns .Lesl_adapter_ok6
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok6:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 528], rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rsp + 32]
    mov rcx, [rsp + 584]
    call ext_store_dir_try
    test rax, rax
    jns .Lesl_adapter_ok7
    test rdx, rdx
    jns .Lesl_adapter_ok7
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok7:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 536], rax
    mov r15, rax
    lea r14, [rsp + 240]
.Lesl_open_file:
    mov rdi, rbx
    call ext_store_cancel
    test rax, rax
    js .Lesl_finish
    mov rdi, r15
    mov rsi, r14
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    jns .Lesl_adapter_ok8
    test rdx, rdx
    jns .Lesl_adapter_ok8
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok8:
    cmp rax, -2
    jne .Lesl_file_opened
    cmp qword ptr [rsp + 584], 0
    je .Lesl_finish
    cmp qword ptr [rbx + ESG_epoch], -1
    je .Lesl_overflow
    inc qword ptr [rbx + ESG_epoch]
    mov rdi, rbx
    call ext_store_cancel
    test rax, rax
    js .Lesl_finish
    mov rdi, r15
    mov rsi, r14
    mov edx, ER_FILE
    mov ecx, ER_WRITE | ER_CREATE | ER_EXCL
    mov r8d, 0600
    call ext_root_open_at
    test rax, rax
    jns .Lesl_adapter_ok9
    test rdx, rdx
    jns .Lesl_adapter_ok9
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok9:
    cmp rax, -17
    jne .Lesl_file_opened
    # A creator that won the race must leave a regular nofollow file.
    mov rdi, r15
    mov rsi, r14
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    jns .Lesl_adapter_ok10
    test rdx, rdx
    jns .Lesl_adapter_ok10
    mov [rsp + 568], rdx
    jmp .Lesl_finish
.Lesl_adapter_ok10:
.Lesl_file_opened:
    test rax, rax
    js .Lesl_finish
    mov [rsp + 552], rax
    mov rdi, rbx
    call ext_store_cancel
    test rax, rax
    js .Lesl_finish
    mov rdi, [rsp + 552]
    mov rsi, [rsp + 576]
    call ext_store_raw_lock
    jmp .Lesl_finish
.Lesl_overflow:
    mov rax, -75
    jmp .Lesl_finish
.Lesl_bad:
    mov rax, -22
.Lesl_finish:
    mov [rsp + 560], rax
    mov r12, 4
1:  dec r12
    mov rdi, [rsp + r12*8 + 520]
    cmp rdi, -1
    je 3f
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rsp + 560], 0
    jne 2f
    mov [rsp + 560], rax
    jmp 3f
2:  cmp qword ptr [rsp + 568], 0
    jne 3f
    mov [rsp + 568], rax
3:  test r12, r12
    jnz 1b
    cmp qword ptr [rsp + 560], 0
    jne 4f
    mov rax, [rsp + 552]
    xor edx, edx
    EPILOGUE
4:  mov rdi, [rsp + 552]
    cmp rdi, -1
    je 5f
    call ext_root_close
    test rax, rax
    jns 5f
    cmp qword ptr [rsp + 568], 0
    jne 5f
    mov [rsp + 568], rax
5:  mov rax, [rsp + 560]
    mov rdx, [rsp + 568]
    EPILOGUE
.Lesl_invalid:
    mov rax, -22
    xor edx, edx
    ret
