# Early isolated snapshot helper. Only complete wire plus successful exit is accepted.
.include "rhun.inc"
.include "app/extstore.inc"
.text
# ext_store_snapshot_emit_root(borrowedRawRoot,tag64,outputFD)->0/-errno,secondaryRDX.
# Caller tags supply epoch/job/nonce. Actual borrowed-root identity is computed here.
FN ext_store_snapshot_emit_root
    xor r8d, r8d
    jmp .Lesc_emit
# Child helper owns its inherited COPY, closes it before success output.
FN ext_store_snapshot_emit_owned
    mov r8d, 1
.Lesc_emit:
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rdx
    mov [rsp + 96], r8
    mov [rsp + 104], rdi
    mov qword ptr [rsp + 64], 0
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
    mov qword ptr [rsp + 88], 0
    mov rdi, rsp
    mov edx, EST_SIZE
    call memcpy
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call ext_store_snapshot_root_try
    test rax, rax
    jz 3f
    mov r13, rax
    lea rdi, [rsp + EST_root_id]
    lea rsi, [rax + ESS_tag + EST_root_id]
    mov edx, 32
    call memcpy
    mov rdi, r13
    mov rsi, rsp
    call ext_store_snapshot_pack_try
    test rax, rax
    jz 2f
    mov [rsp + 64], rax
    mov [rsp + 72], rdx
    jmp 21f
2:  mov [rsp + 80], rdx
    mov [rsp + 88], rcx
21: mov rdi, r13
    call ext_store_snapshot_free
    jmp 4f
3:  mov [rsp + 80], rdx
    mov [rsp + 88], rcx
4:  cmp qword ptr [rsp + 96], 0
    je 6f
    mov rdi, [rsp + 104]
    call ext_root_close
    test rax, rax
    jns 6f
    cmp qword ptr [rsp + 80], 0
    jne 5f
    mov [rsp + 80], rax
    jmp 6f
5:  cmp qword ptr [rsp + 88], 0
    jne 6f
    mov [rsp + 88], rax
6:  cmp qword ptr [rsp + 80], 0
    jne 7f
    mov rdi, r12
    mov rsi, [rsp + 64]
    mov rdx, [rsp + 72]
    call write_all
    mov [rsp + 80], rax
7:  mov rdi, [rsp + 64]
    call mem_free
    mov rax, [rsp + 80]
    mov rdx, [rsp + 88]
    EPILOGUE

# Strict counted decimal argument. RAX=u64 or0, RDX=negative error or0.
.Lesc_number:
    PROLOGUE
    mov rbx, rdi
    mov esi, 20
    call ext_root_length
    test rax, rax
    jle 2f
    mov r12, rax
    xor eax, eax
    xor ecx, ecx
1:  movzx edx, byte ptr [rbx + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 2f
    mov r8, 1844674407370955161
    cmp rax, r8
    ja 2f
    jb 3f
    cmp edx, 5
    ja 2f
3:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    cmp rcx, r12
    jb 1b
    xor edx, edx
    EPILOGUE
2:  xor eax, eax
    mov rdx, -22
    EPILOGUE

# ext_store_snapshot_main(argc,argv)->exit status0/1. Dispatch before app_init.
# rhun --extension-store-snapshot RAW_ANCHOR EPOCH JOB NONCE32lowerhex
# The explicitly inherited anchor is borrowed. No lock descriptor enters this helper.
FN ext_store_snapshot_main
    PROLOGUE 80
    cmp rdi, 6
    jne .Lesc_usage
    mov rbx, rsi
    mov rdi, [rsi + 8]
    lea rsi, [rip + .Lesc_option]
    call strcmp_eq
    test eax, eax
    jz .Lesc_usage
    mov rdi, rsp
    xor esi, esi
    mov edx, EST_SIZE
    call memset
    mov rdi, [rbx + 16]
    call .Lesc_number
    test rdx, rdx
    js .Lesc_usage
    test rax, rax
    js .Lesc_usage
.ifndef WINDOWS
    cmp rax, 2147483647
    ja .Lesc_usage
.endif
    mov r12, rax
    mov rdi, [rbx + 24]
    call .Lesc_number
    test rdx, rdx
    js .Lesc_usage
    test rax, rax
    jz .Lesc_usage
    mov [rsp + EST_epoch], rax
    mov rdi, [rbx + 32]
    call .Lesc_number
    test rdx, rdx
    js .Lesc_usage
    test rax, rax
    jz .Lesc_usage
    mov [rsp + EST_job], rax
    mov r13, [rbx + 40]
    mov rdi, r13
    mov esi, 32
    call ext_root_length
    cmp rax, 32
    jne .Lesc_usage
    xor r14d, r14d
1:  movzx eax, byte ptr [r13 + r14]
    call .Lesc_nibble
    test eax, eax
    js .Lesc_usage
    mov r15d, eax
    inc r14
    movzx eax, byte ptr [r13 + r14]
    call .Lesc_nibble
    test eax, eax
    js .Lesc_usage
    shl r15d, 4
    or eax, r15d
    mov rcx, r14
    shr rcx, 1
    mov [rsp + rcx + EST_nonce], al
    inc r14
    cmp r14, 32
    jb 1b
    mov rdi, r12
    mov rsi, rsp
    mov edx, 1
    call ext_store_snapshot_emit_owned
    test rax, rax
    jnz .Lesc_usage
    test rdx, rdx
    jnz .Lesc_usage
    xor eax, eax
    EPILOGUE
.Lesc_usage:
    mov eax, 1
    EPILOGUE
.Lesc_nibble:
    sub eax, '0'
    cmp eax, 9
    jbe 1f
    sub eax, 'a' - '0'
    cmp eax, 5
    ja 2f
    add eax, 10
1:  ret
2:  mov eax, -1
    ret
.section .rodata
.Lesc_option: .asciz "--extension-store-snapshot"
