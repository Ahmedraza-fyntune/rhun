# Complete rooted metadata reads. Empty/corrupt/tombstone are distinct results.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extvalidate.inc"
.equ ESD_root, 0
.equ ESD_installed, 8
.equ ESD_owner, 16
.equ ESD_snapshot, 24
.equ ESD_cancel, 32
.equ ESD_user, 40
.equ ESD_owner_name, 48
.equ ESD_name, 152
.equ ESD_owner_row, 256
.equ ESD_secondary, 264
.equ ESD_primary, 272
.equ ESD_canceled, 280
.equ ESD_SIZE, 288
.section .rodata
.Lesd_installed: .asciz ".installed"
.text
.Lesd_cancel:
    mov rax, [rdi + ESD_canceled]
    test rax, rax
    jnz 3f
    mov rax, [rdi + ESD_cancel]
    test rax, rax
    jz 2f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rdi + ESD_user]
    call rax
    test rax, rax
    jle 1f
    mov rax, -22
1:  mov [rbx + ESD_canceled], rax
    EPILOGUE
2:  xor eax, eax
3:  ret
# Retain both errors if an already-failed operation has failing mandatory cleanup.
.Lesd_secondary:
    cmp qword ptr [rdi + ESD_secondary], 0
    jne 1f
    mov [rdi + ESD_secondary], rdx
    mov [rdi + ESD_primary], rsi
1:  ret
# Capture adapter mandatory cleanup without changing its primary return.
.Lesd_adapter:
    test rax, rax
    jns 1f
    test rdx, rdx
    jns 1f
    PROLOGUE
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call .Lesd_secondary
    mov rax, r12
    EPILOGUE
1:  ret
# scan(ctx,heldDirectory,callback,callbackCtx)->status,count. Fresh owned stream.
.Lesd_scan:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call .Lesd_cancel
    test rax, rax
    js 4f
    mov rdi, r12
    call ext_root_reopen_dir
    call .Lesd_adapter
    test rax, rax
    js 4f
    mov r15, rax
    mov rdi, rax
    mov esi, ES_LIMIT
    mov rdx, r13
    mov rcx, r14
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, r15
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rsp], 0
    jne 2f
    mov [rsp], rax
    jmp 3f
2:  mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, rax
    call .Lesd_secondary
3:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
4:  xor edx, edx
    EPILOGUE

# Generation callback context: parentCtx@0, greatest@8,second@16.
.Lesd_generation:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rbx]
    call .Lesd_cancel
    test rax, rax
    js 3f
    mov rdi, r12
    mov rsi, r13
    call ext_index_filename_parse
    test rax, rax
    jz 2f
    cmp rax, [rbx + 8]
    jbe 1f
    mov rcx, [rbx + 8]
    mov [rbx + 16], rcx
    mov [rbx + 8], rax
    jmp 2f
1:  cmp rax, [rbx + 16]
    jbe 2f
    mov [rbx + 16], rax
2:  xor eax, eax
3:  EPILOGUE

# read_identity(ctx,actualEncodedBasename,outESR). Output owns observed identity;
# on error index is zero, observed generation retained, exact legacy is shadowed.
.Lesd_read_identity:
    PROLOGUE 144
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, 3
    mov [rsp], rdi
.Lesd_identity_retry:
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 32], -1 # file
    mov qword ptr [rsp + 40], 0 # primary
    mov r15, -1                # directory
    lea rdi, [r13 + ESR_index]
    xor esi, esi
    mov edx, EXI_SIZE
    call memset
    mov qword ptr [r13 + ESR_generation], 0
    mov qword ptr [r13 + ESR_entries], 0
    mov rdi, rbx
    call .Lesd_cancel
    test rax, rax
    js .Lesd_identity_finish
    mov rdi, [rbx + ESD_owner]
    mov rsi, r12
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    call .Lesd_adapter
    test rax, rax
    js .Lesd_identity_finish
    mov r15, rax
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rip + .Lesd_generation]
    mov rcx, rsp
    call .Lesd_scan
    mov [r13 + ESR_entries], rdx
    cmp rax, -27
    jne 1f
    mov qword ptr [r13 + ESR_entries], ES_LIMIT + 1
1:  mov rsi, [rsp + 8]
    mov [r13 + ESR_generation], rsi
    test rax, rax
    js .Lesd_identity_finish
    test rsi, rsi
    jz .Lesd_identity_finish
    lea rdi, [rsp + 48]
    call ext_index_filename_format
    mov rdi, rbx
    call .Lesd_cancel
    test rax, rax
    js .Lesd_identity_finish
    mov rdi, r15
    lea rsi, [rsp + 48]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    call .Lesd_adapter
    test rax, rax
    js .Lesd_identity_finish
    mov [rsp + 32], rax
    mov rdi, rbx
    call .Lesd_cancel
    test rax, rax
    js .Lesd_identity_finish
    mov rdi, [rsp + 32]
    lea rsi, [rsp + 80]
    call ext_root_stat
    test rax, rax
    js .Lesd_identity_finish
    cmp qword ptr [rsp + 80 + ER_kind], ER_FILE
    jne .Lesd_identity_bad
    cmp qword ptr [rsp + 80 + ER_size], EXI_SIZE
    jne .Lesd_identity_bad
    mov qword ptr [rsp + 112], 0
.Lesd_identity_read:
    mov rdi, rbx
    call .Lesd_cancel
    test rax, rax
    js .Lesd_identity_finish
    mov rcx, [rsp + 112]
    mov rdi, [rsp + 32]
    lea rsi, [r13 + rcx + ESR_index]
    mov edx, EXI_SIZE
    sub rdx, rcx
    mov [rsp + 128], rdx
    call ext_root_read
    cmp rax, -4
    je .Lesd_identity_read
    test rax, rax
    js .Lesd_identity_finish
    jz .Lesd_identity_bad
    cmp rax, [rsp + 128]
    ja .Lesd_identity_bad
    add [rsp + 112], rax
    cmp qword ptr [rsp + 112], EXI_SIZE
    jb .Lesd_identity_read
.Lesd_identity_eof:
    mov rdi, rbx
    call .Lesd_cancel
    test rax, rax
    js .Lesd_identity_finish
    mov rdi, [rsp + 32]
    lea rsi, [rsp + 120]
    mov edx, 1
    mov ecx, EXI_SIZE
    call ext_root_read
    cmp rax, -4
    je .Lesd_identity_eof
    test rax, rax
    js .Lesd_identity_finish
    jnz .Lesd_identity_bad
    lea rdi, [r13 + ESR_index]
    mov esi, EXI_SIZE
    mov rdx, [r13 + ESR_generation]
    call ext_index_check
    test eax, eax
    jz .Lesd_identity_bad
    xor eax, eax
    jmp .Lesd_identity_finish
.Lesd_identity_bad:
    mov rax, -5
.Lesd_identity_finish:
    mov [rsp + 40], rax
    mov rdi, [rsp + 32]
    cmp rdi, -1
    je 2f
    mov qword ptr [rsp + 32], -1
    call ext_root_close
    test rax, rax
    jns 2f
    cmp qword ptr [rsp + 40], 0
    jne 11f
    mov [rsp + 40], rax
    jmp 2f
11: mov rdi, rbx
    mov rsi, [rsp + 40]
    mov rdx, rax
    call .Lesd_secondary
2:  cmp r15, -1
    je 3f
    mov rdi, r15
    mov r15, -1
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rsp + 40], 0
    jne 21f
    mov [rsp + 40], rax
    jmp 3f
21: mov rdi, rbx
    mov rsi, [rsp + 40]
    mov rdx, rax
    call .Lesd_secondary
3:  mov rax, [rsp + 40]
    cmp rax, -2
    jne 5f
    dec r14
    jnz .Lesd_identity_retry
    mov rax, -11
5:  mov [r13 + ESR_status], rax
    test rax, rax
    jns 6f
    lea rdi, [r13 + ESR_index]
    xor esi, esi
    mov edx, EXI_SIZE
    call memset
6:  xor eax, eax
    EPILOGUE

.Lesd_identity:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call .Lesd_cancel
    test rax, rax
    js 9f
    cmp byte ptr [r12], '.'
    je 8f
    lea rdi, [rbx + ESD_name]
    xor esi, esi
    mov edx, 104
    call memset
    lea rdi, [rbx + ESD_name]
    mov rsi, r12
    mov rdx, r13
    call ext_store_identity_decode
    test rax, rax
    jz 7f
    mov r14, [rbx + ESD_snapshot]
    cmp qword ptr [r14 + ESS_identity_count], ES_LIMIT
    jae 6f
    lea rdi, [r14 + ESS_entries]
    mov esi, ESR_SIZE
    call vec_push_try
    test rax, rax
    jz 5f
    mov r15, rax
    inc qword ptr [r14 + ESS_identity_count]
    mov rdi, rax
    lea rsi, [rbx + ESD_owner_name]
    mov edx, 104
    call memcpy
    lea rdi, [r15 + ESR_name]
    lea rsi, [rbx + ESD_name]
    mov edx, 104
    call memcpy
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call .Lesd_read_identity
    mov rax, [rbx + ESD_canceled]
    test rax, rax
    jnz 9f
    mov rax, [r15 + ESR_status]
    cmp rax, -12
    je 9f
    test rax, rax
    jne 8f
    cmp qword ptr [r15 + ESR_generation], 0
    je 8f
    cmp dword ptr [r15 + ESR_index + EXI_flags], EXI_ACTIVE
    jne 8f
    inc qword ptr [r14 + ESS_live]
    cmp qword ptr [r14 + ESS_live], ES_LIVE_LIMIT
    ja 6f
8:  xor eax, eax
    jmp 9f
7:  mov rax, -5
    jmp 9f
6:  mov rax, -27
    jmp 9f
5:  mov rax, -12
9:  EPILOGUE

.Lesd_owner:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call .Lesd_cancel
    test rax, rax
    js 9f
    cmp byte ptr [r12], '.'
    je 8f
    # Clear all padding, because the previous owner may have a longer name.
    lea rdi, [rbx + ESD_owner_name]
    xor esi, esi
    mov edx, 104
    call memset
    lea rdi, [rbx + ESD_owner_name]
    mov rsi, r12
    mov rdx, r13
    call ext_store_identity_decode
    test rax, rax
    jz 7f
    mov rdi, [rbx + ESD_installed]
    mov rsi, r12
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    call .Lesd_adapter
    test rax, rax
    js 9f
    mov r15, rax
    mov [rbx + ESD_owner], rax
    mov r14, [rbx + ESD_snapshot]
    lea rdi, [r14 + ESS_owners]
    mov esi, ESO_SIZE
    call vec_push_try
    test rax, rax
    jz 6f
    mov [rbx + ESD_owner_row], rax
    mov rdi, rax
    lea rsi, [rbx + ESD_owner_name]
    mov edx, 104
    call memcpy
    mov rdi, rbx
    mov rsi, r15
    lea rdx, [rip + .Lesd_identity]
    mov rcx, rbx
    call .Lesd_scan
    mov rcx, [rbx + ESD_owner_row]
    mov [rcx + ESO_entries], rdx
    jmp 3f
6:  mov rax, -12
3:  mov [rsp], rax
    mov rdi, r15
    mov qword ptr [rbx + ESD_owner], -1
    call ext_root_close
    test rax, rax
    jns 4f
    cmp qword ptr [rsp], 0
    jne 31f
    mov [rsp], rax
    jmp 4f
31: mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, rax
    call .Lesd_secondary
4:  mov rax, [rsp]
    jmp 9f
8:  xor eax, eax
    jmp 9f
7:  mov rax, -5
9:  EPILOGUE

# ext_store_snapshot_root_try(borrowedRawRoot,cancelFn,user)->ESS,0,0 or0,primary,cleanup.
FN ext_store_snapshot_root_try
    PROLOGUE ESD_SIZE + 32
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rsp
    xor esi, esi
    mov edx, ESD_SIZE
    call memset
    mov [rsp + ESD_root], r12
    mov qword ptr [rsp + ESD_installed], -1
    mov qword ptr [rsp + ESD_owner], -1
    mov [rsp + ESD_cancel], r13
    mov [rsp + ESD_user], r14
    mov edi, ESS_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lesd_snapshot_oom
    mov rbx, rax
    mov [rsp + ESD_snapshot], rax
    mov rdi, rsp
    call .Lesd_cancel
    test rax, rax
    js .Lesd_snapshot_finish
    mov rdi, r12
    lea rsi, [rbx + ESS_tag + EST_root_id]
    call ext_root_identity
    test rax, rax
    js .Lesd_snapshot_finish
    mov rdi, rsp
    call .Lesd_cancel
    test rax, rax
    js .Lesd_snapshot_finish
    mov rdi, r12
    lea rsi, [rip + .Lesd_installed]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    jns 91f
    test rdx, rdx
    jns 91f
    mov [rsp + ESD_secondary], rdx
    mov [rsp + ESD_primary], rax
    jmp .Lesd_snapshot_finish
91: cmp rax, -2
    jne 1f
    xor eax, eax
    jmp .Lesd_snapshot_finish
1:  test rax, rax
    js .Lesd_snapshot_finish
    mov [rsp + ESD_installed], rax
    mov rdi, rsp
    mov rsi, rax
    lea rdx, [rip + .Lesd_owner]
    mov rcx, rsp
    call .Lesd_scan
    mov [rbx + ESS_root_entries], rdx
    jmp .Lesd_snapshot_finish
.Lesd_snapshot_oom:
    xor ebx, ebx
    mov rax, -12
.Lesd_snapshot_finish:
    mov r14, rax
    mov rdi, [rsp + ESD_installed]
    cmp rdi, -1
    je 2f
    call ext_root_close
    test rax, rax
    jns 2f
    test r14, r14
    jnz 11f
    mov r14, rax
    jmp 2f
11: mov rdi, rsp
    mov rsi, r14
    mov rdx, rax
    call .Lesd_secondary
2:  test r14, r14
    jnz 3f
    mov r14, [rsp + ESD_canceled]
    test r14, r14
    jnz 3f
    cmp qword ptr [rsp + ESD_secondary], 0
    je 4f
    mov r14, [rsp + ESD_primary]
3:  mov rdi, rbx
    call ext_store_snapshot_free
    xor eax, eax
    mov rdx, r14
    mov rcx, [rsp + ESD_secondary]
    EPILOGUE
4:  mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

# ext_store_snapshot_try(rootPath,cancelFn,user) owns only its root open.
FN ext_store_snapshot_try
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call dir_scan_path_check
    test rax, rax
    js 4f
    test r12, r12
    jz 1f
    mov rdi, r13
    call r12
    test rax, rax
    jz 1f
    js 4f
    mov rax, -22
    jmp 4f
1:  mov rdi, rbx
    call ext_root_open
    test rax, rax
    js 5f
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call ext_store_snapshot_root_try
    mov rbx, rax
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov rdi, r14
    call ext_root_close
    test rax, rax
    jns 3f
    cmp qword ptr [rsp], 0
    jne 1f
    mov [rsp], rax
    mov rdi, rbx
    call ext_store_snapshot_free
    xor ebx, ebx
    jmp 3f
1:  cmp qword ptr [rsp + 8], 0
    jne 3f
    mov [rsp + 8], rax
3:  mov rax, rbx
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    EPILOGUE
4:  xor edx, edx
5:  mov rcx, rdx
    mov rdx, rax
    xor eax, eax
    EPILOGUE
