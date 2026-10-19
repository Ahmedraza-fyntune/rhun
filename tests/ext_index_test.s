.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.equ EIT_GEN, 0x0123456789abcdef
.section .rodata
.p2align 3
eit_invalid_pack:
    .quad 0,1,eit_id,eit_previous
    .quad 1,0,eit_id,0
    .quad 1,3,eit_id,0
    .quad 1,-1,eit_id,0
    .quad 1,1,0,eit_previous
    .quad 1,1,eit_id,eit_zero
    .quad 1,2,eit_id,0
    .quad 1,2,0,eit_previous
    .quad 0,0,0,-1
eit_bad_lengths: .quad 0,159,161,-1
eit_bad_name_lengths: .quad 0,19,21,-1
eit_generations: .quad 1,EIT_GEN,-1
eit_bad_flags: .long 0,3,-1
eit_names: .ascii "0000000000000001.idx0123456789abcdef.idxffffffffffffffff.idx"
eit_bad_chars: .byte 0,'A','G','g','/',255
.p2align 3
eit_literal:
    .ascii "RHEXIDX\0"
    .long 1,1
    .quad EIT_GEN,0
eit_id:
    .ascii "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
eit_previous:
    .ascii "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
eit_absent:
    .ascii "RHEXIDX\0"
    .long 1,1
    .quad EIT_GEN,0
    .ascii "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    .zero 64
eit_removed:
    .ascii "RHEXIDX\0"
    .long 1,2
    .quad 7,0
    .zero 128
eit_zero: .zero 64
eit_ok: .asciz "ok managed extension selection records\n"
.bss
.p2align 3
eit_buf: .zero 176
eit_snapshot: .zero 176
eit_bad_id: .zero 64
eit_name: .zero 32
eit_name_snapshot: .zero 32
eit_stage: .quad 0
eit_live: .quad 0
eit_mapping: .quad 0
.text
eit_fail:
    mov rdi, [rip + eit_stage]
    inc edi
    call sys_exit
eit_ok_result:
    cmp eax, 1
    jne eit_fail
    ret
eit_no_result:
    test rax, rax
    jnz eit_fail
    ret
eit_snapshot_buf:
    lea rdi, [rip + eit_snapshot]
    lea rsi, [rip + eit_buf]
    mov edx, 176
    jmp memcpy
eit_buf_unchanged:
    call eit_no_result
    lea rdi, [rip + eit_snapshot]
    lea rsi, [rip + eit_buf]
    mov edx, 176
    call memeq
    test eax, eax
    jz eit_fail
    ret
eit_sentinel:
    lea rdi, [rip + eit_buf]
    mov esi, 0xa5
    mov edx, 176
    call memset
    jmp eit_snapshot_buf
eit_literal_buf:
    lea rdi, [rip + eit_buf + 8]
    lea rsi, [rip + eit_literal]
    mov edx, EXI_SIZE
    jmp memcpy
eit_check_buf:
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    mov rdx, EIT_GEN
    jmp ext_index_check
eit_canaries:
    mov rax, 0xa5a5a5a5a5a5a5a5
    cmp [rip + eit_buf], rax
    jne eit_fail
    cmp [rip + eit_buf + 168], rax
    jne eit_fail
    ret
eit_pack:
    lea rdi, [rip + eit_buf + 8]
    jmp ext_index_pack
eit_equal_literal:
    lea rdi, [rip + eit_buf + 8]
    mov edx, EXI_SIZE
    call memeq
    test eax, eax
    jz eit_fail
    jmp eit_canaries
eit_name_sentinel:
    lea rdi, [rip + eit_name]
    mov esi, 0xa5
    mov edx, 32
    call memset
    lea rdi, [rip + eit_name_snapshot]
    lea rsi, [rip + eit_name]
    mov edx, 32
    jmp memcpy
eit_name_unchanged:
    call eit_no_result
    lea rdi, [rip + eit_name_snapshot]
    lea rsi, [rip + eit_name]
    mov edx, 32
    call memeq
    test eax, eax
    jz eit_fail
    ret
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + eit_live], rax
    call eit_sentinel
    mov rsi, EIT_GEN
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_id]
    lea r8, [rip + eit_previous]
    call eit_pack
    call eit_ok_result
    lea rsi, [rip + eit_literal]
    call eit_equal_literal
    call eit_check_buf
    call eit_ok_result
    inc qword ptr [rip + eit_stage]
    mov rsi, EIT_GEN
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_id]
    xor r8d, r8d
    call eit_pack
    call eit_ok_result
    lea rsi, [rip + eit_absent]
    call eit_equal_literal
    call eit_check_buf
    call eit_ok_result
    inc qword ptr [rip + eit_stage]
    mov esi, 7
    mov edx, EXI_REMOVED
    xor ecx, ecx
    xor r8d, r8d
    call eit_pack
    call eit_ok_result
    lea rsi, [rip + eit_removed]
    call eit_equal_literal
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    mov edx, 7
    call ext_index_check
    call eit_ok_result
    # Any nonzero ID byte invalidates a removed record.
    xor r12d, r12d
1:  lea rdi, [rip + eit_buf + 8]
    lea rsi, [rip + eit_removed]
    mov edx, EXI_SIZE
    call memcpy
    lea rax, [rip + eit_buf + 8 + EXI_active]
    mov byte ptr [rax + r12], '0'
    call eit_snapshot_buf
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    mov edx, 7
    call ext_index_check
    call eit_buf_unchanged
    inc r12
    cmp r12, 128
    jb 1b

    # Every field byte is checked. Read-only failure includes input canaries.
    inc qword ptr [rip + eit_stage]
    xor r12d, r12d
1:  call eit_literal_buf
    lea rax, [rip + eit_buf + 8]
    xor byte ptr [rax + r12], 0x80
    call eit_snapshot_buf
    call eit_check_buf
    call eit_buf_unchanged
    inc r12
    cmp r12, EXI_SIZE
    jb 1b
    # Every active/previous ID position rejects NUL, uppercase and out-of-range bytes.
    inc qword ptr [rip + eit_stage]
    mov r12d, EXI_active
1:  xor r13d, r13d
2:  call eit_literal_buf
    lea rax, [rip + eit_bad_chars]
    mov cl, [rax + r13]
    lea rax, [rip + eit_buf + 8]
    mov [rax + r12], cl
    call eit_snapshot_buf
    call eit_check_buf
    call eit_buf_unchanged
    inc r13
    cmp r13, 6
    jb 2b
    inc r12
    cmp r12, EXI_SIZE
    jb 1b

    # Bad packing parameters never zero or partly replace an existing destination.
    inc qword ptr [rip + eit_stage]
    xor r12d, r12d
1:  call eit_literal_buf
    lea rax, [rip + eit_bad_flags]
    mov eax, [rax + r12*4]
    mov [rip + eit_buf + 8 + EXI_flags], eax
    call eit_snapshot_buf
    call eit_check_buf
    call eit_buf_unchanged
    inc r12
    cmp r12, 3
    jb 1b
    inc qword ptr [rip + eit_stage]
    lea r15, [rip + eit_invalid_pack]
1:  cmp qword ptr [r15 + 24], -1
    je 2f
    call eit_sentinel
    mov rsi, [r15]
    mov edx, [r15 + 8]
    mov rcx, [r15 + 16]
    mov r8, [r15 + 24]
    call eit_pack
    call eit_buf_unchanged
    add r15, 32
    jmp 1b
2:  xor edi, edi
    mov esi, 1
    mov edx, 1
    lea rcx, [rip + eit_id]
    xor r8d, r8d
    call ext_index_pack
    call eit_buf_unchanged
    xor r12d, r12d
3:  lea rdi, [rip + eit_bad_id]
    lea rsi, [rip + eit_id]
    mov edx, 64
    call memcpy
    lea rax, [rip + eit_bad_id]
    mov byte ptr [rax + r12], 'A'
    mov esi, 1
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_bad_id]
    lea r8, [rip + eit_previous]
    call eit_pack
    call eit_buf_unchanged
    mov esi, 1
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_id]
    lea r8, [rip + eit_bad_id]
    call eit_pack
    call eit_buf_unchanged
    inc r12
    cmp r12, 64
    jb 3b

    # Equal IDs are valid; maximum unsigned generation is represented exactly.
    inc qword ptr [rip + eit_stage]
    mov rsi, -1
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_id]
    mov r8, rcx
    call eit_pack
    call eit_ok_result
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    mov rdx, -1
    call ext_index_check
    call eit_ok_result
    cmp qword ptr [rip + eit_buf + 8 + EXI_generation], -1
    jne eit_fail
    lea rdi, [rip + eit_buf + 8 + EXI_active]
    lea rsi, [rip + eit_buf + 8 + EXI_previous]
    mov edx, 64
    call memeq
    test eax, eax
    jz eit_fail
    call eit_canaries
    call eit_literal_buf
    call eit_snapshot_buf
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    xor edx, edx
    call ext_index_check
    call eit_buf_unchanged
    lea rdi, [rip + eit_buf + 8]
    mov esi, EXI_SIZE
    mov edx, 1
    call ext_index_check
    call eit_buf_unchanged
    xor edi, edi
    mov esi, EXI_SIZE
    mov edx, 1
    call ext_index_check
    call eit_buf_unchanged

    inc qword ptr [rip + eit_stage]
    xor r12d, r12d
1:  call eit_name_sentinel
    lea rax, [rip + eit_generations]
    mov rsi, [rax + r12*8]
    lea rdi, [rip + eit_name + 4]
    call ext_index_filename_format
    call eit_ok_result
    imul r13, r12, 20
    lea rsi, [rip + eit_names]
    add rsi, r13
    lea rdi, [rip + eit_name + 4]
    mov edx, 20
    call memeq
    test eax, eax
    jz eit_fail
    cmp byte ptr [rip + eit_name + 24], 0
    jne eit_fail
    cmp dword ptr [rip + eit_name], 0xa5a5a5a5
    jne eit_fail
    cmp dword ptr [rip + eit_name + 25], 0xa5a5a5a5
    jne eit_fail
    lea rdi, [rip + eit_name + 4]
    mov esi, 20
    call ext_index_filename_parse
    lea rcx, [rip + eit_generations]
    cmp rax, [rcx + r12*8]
    jne eit_fail
    inc r12
    cmp r12, 3
    jb 1b
    call eit_name_sentinel
    lea rdi, [rip + eit_name + 4]
    xor esi, esi
    call ext_index_filename_format
    call eit_name_unchanged
    xor edi, edi
    mov esi, 1
    call ext_index_filename_format
    call eit_name_unchanged
    xor edi, edi
    mov esi, 20
    call ext_index_filename_parse
    call eit_name_unchanged
    # Invalid character at every filename position, and the all-zero generation.
    xor r12d, r12d
2:  lea rdi, [rip + eit_name]
    lea rsi, [rip + eit_names + 20]
    mov edx, 20
    call memcpy
    lea rax, [rip + eit_name]
    mov byte ptr [rax + r12], 'G'
    lea rdi, [rip + eit_name]
    mov esi, 20
    call ext_index_filename_parse
    call eit_no_result
    inc r12
    cmp r12, 20
    jb 2b
    lea rdi, [rip + eit_name]
    lea rsi, [rip + eit_names]
    mov edx, 20
    call memcpy
    mov byte ptr [rip + eit_name + 15], '0'
    lea rdi, [rip + eit_name]
    mov esi, 20
    call ext_index_filename_parse
    call eit_no_result

    inc qword ptr [rip + eit_stage]
    call eit_guarded
    mov rax, [rip + eit_live]
    cmp rax, [rip + g_mem_live]
    jne eit_fail
    lea rdi, [rip + eit_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE

# Exact spans at an unreadable boundary detect even read-only overruns.
eit_guarded:
    PROLOGUE 96
.ifdef WINDOWS
    xor ecx, ecx
    mov edx, 131072
    mov r8d, 0x2000             # MEM_RESERVE
    mov r9d, 1                 # PAGE_NOACCESS
    API VirtualAlloc
    test rax, rax
    jz eit_fail
    mov rbx, rax
    mov rcx, rax
    mov edx, 65536
    mov r8d, 0x1000             # MEM_COMMIT
    mov r9d, 4                 # PAGE_READWRITE
    API VirtualAlloc
    cmp rax, rbx
    jne eit_fail
.else
    mov edi, 131072
    call os_map
    mov rbx, rax
    lea rdi, [rax + 65536]
    mov esi, 65536
    SYS SYS_munmap
    test rax, rax
    jnz eit_fail
.endif
    mov [rip + eit_mapping], rbx
    add rbx, 65536
    lea rdi, [rbx - EXI_SIZE]
    lea rsi, [rip + eit_literal]
    mov edx, EXI_SIZE
    call memcpy
    lea rdi, [rbx - EXI_SIZE]
    mov esi, EXI_SIZE
    mov rdx, EIT_GEN
    call ext_index_check
    call eit_ok_result
    lea rdi, [rbx - EXI_SIZE]
    mov rsi, EIT_GEN
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eit_id]
    lea r8, [rip + eit_previous]
    call ext_index_pack
    call eit_ok_result
    lea rdi, [rbx - EXI_SIZE]
    mov esi, EXI_SIZE
    mov rdx, EIT_GEN
    call ext_index_check
    call eit_ok_result
    lea rdi, [rbx - EXI_SIZE]
    mov esi, 7
    mov edx, EXI_REMOVED
    xor ecx, ecx
    xor r8d, r8d
    call ext_index_pack
    call eit_ok_result
    lea rdi, [rbx - EXI_SIZE]
    mov esi, EXI_SIZE
    mov edx, 7
    call ext_index_check
    call eit_ok_result
    # A single valid ID spans exactly the last64 readable bytes, no terminator.
    lea rdi, [rbx - 64]
    lea rsi, [rip + eit_id]
    mov edx, 64
    call memcpy
    mov esi, 1
    mov edx, EXI_ACTIVE
    lea rcx, [rbx - 64]
    mov r8, rcx
    call eit_pack
    call eit_ok_result
    lea rdi, [rbx - 21]
    mov rsi, -1
    call ext_index_filename_format
    call eit_ok_result
    cmp byte ptr [rbx - 1], 0
    jne eit_fail
    lea rdi, [rbx - 20]
    lea rsi, [rip + eit_names + 40]
    mov edx, 20
    call memcpy
    lea rdi, [rbx - 20]
    mov esi, 20
    call ext_index_filename_parse
    cmp rax, -1
    jne eit_fail
    # Invalid lengths must be checked before the first byte is read.
    xor r12d, r12d
1:  mov rdi, rbx
    lea rax, [rip + eit_bad_lengths]
    mov rsi, [rax + r12*8]
    mov edx, 1
    call ext_index_check
    call eit_no_result
    mov rdi, rbx
    lea rax, [rip + eit_bad_name_lengths]
    mov rsi, [rax + r12*8]
    call ext_index_filename_parse
    call eit_no_result
    inc r12
    cmp r12, 4
    jb 1b
    mov rdi, [rip + eit_mapping]
    mov esi, 65536
    SYS SYS_munmap
    test rax, rax
    jnz eit_fail
    EPILOGUE
