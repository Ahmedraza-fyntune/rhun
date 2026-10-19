.include "rhun.inc"
.section .rodata
.p2align 3
mht_sizes:
    .quad 0,1,14,15,16,17,30,31,32,33,62,63,64,65,126,127,128,129
    .quad 254,255,256,257,510,511,512,513,1022,1023,1024,1025
    .quad 2046,2047,2048,2049,4094,4095,4096,4097,8190,8191,8192,8193
    .quad 16382,16383,16384,16385,32766,32767,32768,32769
    .quad 65518,65519,65520,65521,65535,65536,65537,1048576,-1
mht_items: .quad 1,3,8,32,65521,0
# len, cap, minimum, item size, all with NULL buffer
mht_bad_vectors:
    .quad 1,0,0,1
    .quad 0,1,0,1
    .quad -1,-1,1,1
    .quad 0,-1,1,8
    .quad 0,0,-1,3
    .quad 0,0,1,0
    .quad 0,0,1,-1
    .quad 0,0,1,1<<40
    .quad 0,0,1<<39,3
    .quad 0,0,2,(1<<40)-1
    .quad -1,0,0,0
mht_binary: .byte 0,'a',255,'z',0
mht_ok: .asciz "ok fallible copies and vectors\n"
.bss
.p2align 3
mht_guard: .zero 8
mht_vec: .zero VEC_SIZE
mht_guard_end: .zero 8
mht_meta: .zero VEC_SIZE + 16
mht_payload: .zero 512
mht_source: .zero 1048576
mht_source_end: .zero 8
mht_stage: .quad 0
mht_live: .quad 0
mht_snapshot_live: .quad 0
mht_snapshot_calls: .quad 0
mht_payload_len: .quad 0
.ifdef TEST_MEM_HELPERS_FAULT
mht_calls: .quad 0
mht_fail_at: .quad 0
mht_failure_seen: .quad 0
.endif
.text
.ifdef TEST_MEM_HELPERS_FAULT
FN mht_alloc
    inc qword ptr [rip + mht_calls]
    mov rax, [rip + mht_calls]
    cmp rax, [rip + mht_fail_at]
    je 1f
    jmp mem_alloc_try
1:  xor eax, eax
    ret
.endif
mht_fail:
    mov rdi, [rip + mht_stage]
    inc edi
    call sys_exit
mht_ok_result:
    cmp eax, 1
    jne mht_fail
    ret
mht_no_result:
    test rax, rax
    jnz mht_fail
    ret
mht_balanced:
    mov rax, [rip + mht_live]
    cmp rax, [rip + g_mem_live]
    jne mht_fail
    ret
# bytes(ptr, len, expected_byte)
mht_bytes:
    test rsi, rsi
    jz 2f
1:  cmp [rdi], dl
    jne mht_fail
    inc rdi
    dec rsi
    jnz 1b
2:  ret
mht_clear:
    PROLOGUE
    lea rdi, [rip + mht_guard]
    mov esi, 0xa5
    mov edx, VEC_SIZE + 16
    call memset
    lea rdi, [rip + mht_vec]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    EPILOGUE
mht_canaries:
    mov rax, 0xa5a5a5a5a5a5a5a5
    cmp [rip + mht_guard], rax
    jne mht_fail
    cmp [rip + mht_guard_end], rax
    jne mht_fail
    ret
mht_reserve:
    lea rdi, [rip + mht_vec]
    jmp vec_reserve_try
mht_push:
    lea rdi, [rip + mht_vec]
    jmp vec_push_try
mht_free:
    PROLOGUE
    lea rdi, [rip + mht_vec]
    call vec_free
    call mht_canaries
    call mht_balanced
    EPILOGUE

# Snapshot metadata and a small owned payload for invalid/failure cases.
mht_capture:
    PROLOGUE
    lea rdi, [rip + mht_meta]
    lea rsi, [rip + mht_guard]
    mov edx, VEC_SIZE + 16
    call memcpy
    mov rax, [rip + g_mem_live]
    mov [rip + mht_snapshot_live], rax
.ifdef TEST_MEM_HELPERS_FAULT
    mov rax, [rip + mht_calls]
    mov [rip + mht_snapshot_calls], rax
.endif
    mov qword ptr [rip + mht_payload_len], 0
    mov rdi, [rip + mht_vec + VEC_ptr]
    test rdi, rdi
    jz 1f
    call mem_capacity
    cmp rax, 512
    ja mht_fail
    mov [rip + mht_payload_len], rax
    lea rdi, [rip + mht_payload]
    mov rsi, [rip + mht_vec + VEC_ptr]
    mov rdx, rax
    call memcpy
1:  EPILOGUE
mht_unchanged:
    PROLOGUE
    call mht_no_result
    lea rdi, [rip + mht_meta]
    lea rsi, [rip + mht_guard]
    mov edx, VEC_SIZE + 16
    call memeq
    test eax, eax
    jz mht_fail
    lea rdi, [rip + mht_payload]
    mov rsi, [rip + mht_vec + VEC_ptr]
    mov rdx, [rip + mht_payload_len]
    call memeq
    test eax, eax
    jz mht_fail
    mov rax, [rip + mht_snapshot_live]
    cmp rax, [rip + g_mem_live]
    jne mht_fail
    EPILOGUE
mht_no_allocation:
.ifdef TEST_MEM_HELPERS_FAULT
    mov rax, [rip + mht_snapshot_calls]
    cmp rax, [rip + mht_calls]
    jne mht_fail
.endif
    ret

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + mht_live], rax
    lea rbx, [rip + mht_source]
    xor ecx, ecx
1:  mov [rbx + rcx], cl
    inc ecx
    cmp ecx, 1048576
    jb 1b
    mov rax, 0xa5a5a5a5a5a5a5a5
    mov [rip + mht_source_end], rax
    lea r15, [rip + mht_sizes]
2:  mov r12, [r15]
    cmp r12, -1
    je 3f
    mov rdi, rbx
    mov rsi, r12
    call mem_dup_try
    test rax, rax
    jz mht_fail
    mov r13, rax
    cmp byte ptr [rax + r12], 0
    jne mht_fail
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz mht_fail
    mov rdi, r13
    call mem_free
    call mht_balanced
    add r15, 8
    jmp 2b
3:  xor edi, edi
    xor esi, esi
    call mem_dup_try
    test rax, rax
    jz mht_fail
    cmp byte ptr [rax], 0
    jne mht_fail
    mov rdi, rax
    call mem_free
    call mht_balanced
    # Source pattern and its end canary remain intact, including embedded NULs.
    xor ecx, ecx
4:  cmp [rbx + rcx], cl
    jne mht_fail
    inc ecx
    cmp ecx, 1048576
    jb 4b
    mov rax, 0xa5a5a5a5a5a5a5a5
    cmp [rip + mht_source_end], rax
    jne mht_fail

    inc qword ptr [rip + mht_stage]
    call mht_clear
    call mht_capture
    xor edi, edi
    mov esi, 1
    call mem_dup_try
    call mht_unchanged
    call mht_no_allocation
    mov rdi, -1
    mov rsi, -1
    call mem_dup_try
    call mht_unchanged
    call mht_no_allocation
    mov rdi, -1
    mov rsi, (1 << 40) - 1
    call mem_dup_try
    call mht_unchanged
    call mht_no_allocation

    inc qword ptr [rip + mht_stage]
    lea r15, [rip + mht_items]
.Lmht_vectors:
    mov r12, [r15]
    test r12, r12
    jz .Lmht_invalid
    call mht_clear
    call mht_capture
    xor esi, esi
    mov rdx, r12
    call mht_reserve
    call mht_ok_result
    call mht_no_allocation
    cmp qword ptr [rip + mht_vec + VEC_ptr], 0
    jne mht_fail
    mov esi, 1
    mov rdx, r12
    call mht_reserve
    call mht_ok_result
    cmp qword ptr [rip + mht_vec + VEC_cap], 8
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_len], 0
    jne mht_fail
    mov rdi, [rip + mht_vec + VEC_ptr]
    mov rdx, r12
    shl rdx, 3
    mov esi, 0x5a
    call memset
    mov qword ptr [rip + mht_vec + VEC_len], 3
    mov rbx, [rip + mht_vec + VEC_ptr]
.ifdef TEST_MEM_HELPERS_FAULT
    mov rax, [rip + mht_calls]
    mov [rip + mht_snapshot_calls], rax
.endif
    mov esi, 5
    mov rdx, r12
    call mht_reserve
    call mht_ok_result
    call mht_no_allocation
    cmp rbx, [rip + mht_vec + VEC_ptr]
    jne mht_fail
    mov esi, 9
    mov rdx, r12
    call mht_reserve
    call mht_ok_result
    cmp qword ptr [rip + mht_vec + VEC_cap], 16
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_len], 3
    jne mht_fail
    mov rbx, [rip + mht_vec + VEC_ptr]
    mov rdi, rbx
    mov rsi, r12
    shl rsi, 3
    mov edx, 0x5a
    call mht_bytes
    mov rax, r12
    shl rax, 3
    lea rdi, [rbx + rax]
    mov rsi, rax
    xor edx, edx
    call mht_bytes
    mov rsi, r12
    call mht_push
    mov r13, r12
    imul r13, 3
    add r13, rbx
    cmp rax, r13
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_len], 4
    jne mht_fail
    mov rdi, rax
    mov rsi, r12
    xor edx, edx
    call mht_bytes
    cmp byte ptr [r13 - 1], 0x5a
    jne mht_fail
    cmp byte ptr [r13 + r12], 0x5a
    jne mht_fail
    cmp r12, 32
    ja 1f
    mov esi, 1000
    mov rdx, r12
    call mht_reserve
    call mht_ok_result
    cmp qword ptr [rip + mht_vec + VEC_cap], 1000
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_len], 4
    jne mht_fail
    mov rax, r12
    shl rax, 4
    mov rdi, [rip + mht_vec + VEC_ptr]
    add rdi, rax
    mov rsi, r12
    imul rsi, 984
    xor edx, edx
    call mht_bytes
1:  call mht_free
    add r15, 8
    jmp .Lmht_vectors

.Lmht_invalid:
    inc qword ptr [rip + mht_stage]
    lea r15, [rip + mht_bad_vectors]
1:  cmp qword ptr [r15 + 8], 0
    jne 2f
    cmp qword ptr [r15], -1
    je 3f
2:  call mht_clear
    mov rax, [r15]
    mov [rip + mht_vec + VEC_len], rax
    mov rax, [r15 + 8]
    mov [rip + mht_vec + VEC_cap], rax
    call mht_capture
    mov rsi, [r15 + 16]
    mov rdx, [r15 + 24]
    call mht_reserve
    call mht_unchanged
    call mht_no_allocation
    add r15, 32
    jmp 1b
3:  call mht_clear
    call mht_capture
    xor edi, edi
    mov esi, 1
    call vec_push_try
    call mht_unchanged
    call mht_no_allocation
    xor edi, edi
    mov esi, 1
    mov edx, 1
    call vec_reserve_try
    call mht_unchanged
    call mht_no_allocation
    mov qword ptr [rip + mht_vec + VEC_len], -1
    call mht_capture
    mov esi, 1
    call mht_push
    call mht_unchanged
    call mht_no_allocation
    call mht_clear
    mov edi, 24
    call mem_alloc
    mov rbx, rax
    mov [rip + mht_vec + VEC_ptr], rax
    mov rdi, rax
    call mem_capacity
    mov r12, rax
    mov rdi, rbx
    mov esi, 0x5a
    mov rdx, rax
    call memset
    mov rax, r12
    inc rax
    mov [rip + mht_vec + VEC_cap], rax
    call mht_capture
    xor esi, esi
    mov edx, 1
    call mht_reserve
    call mht_unchanged
    call mht_no_allocation
    mov qword ptr [rip + mht_vec + VEC_cap], 0
    call mht_capture
    mov esi, 1
    call mht_push
    call mht_unchanged
    call mht_no_allocation
    mov rdi, rbx
    call mem_free
    call mht_clear
    call mht_balanced
.ifdef TEST_MEM_HELPERS_FAULT
    inc qword ptr [rip + mht_stage]
    mov rax, [rip + mht_calls]
    inc rax
    mov [rip + mht_fail_at], rax
    call mht_capture
    lea rdi, [rip + mht_binary]
    mov esi, 5
    call mem_dup_try
    call mht_unchanged
    mov qword ptr [rip + mht_fail_at], 0
    lea rdi, [rip + mht_binary]
    mov esi, 5
    call mem_dup_try
    test rax, rax
    jz mht_fail
    mov rdi, rax
    call mem_free
    call mht_balanced
    # Fail each of the four allocations in forty pushes, then retry the failed push.
    mov r15d, 1
.Lmht_scenario:
    call mht_clear
    mov qword ptr [rip + mht_calls], 0
    mov [rip + mht_fail_at], r15
    mov qword ptr [rip + mht_failure_seen], 0
    xor r12d, r12d
1:  call mht_capture
    mov esi, 3
    call mht_push
    test rax, rax
    jnz 2f
    call mht_unchanged
    mov rax, [rip + mht_calls]
    cmp rax, r15
    jne mht_fail
    cmp qword ptr [rip + mht_failure_seen], 0
    jne mht_fail
    mov qword ptr [rip + mht_failure_seen], 1
    mov qword ptr [rip + mht_fail_at], 0
    mov esi, 3
    call mht_push
    test rax, rax
    jz mht_fail
2:  mov rdi, rax
    lea rsi, [r12 + 1]
    mov edx, 3
    call memset
    inc r12
    cmp r12, 40
    jb 1b
    cmp qword ptr [rip + mht_failure_seen], 1
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_len], 40
    jne mht_fail
    cmp qword ptr [rip + mht_vec + VEC_cap], 64
    jne mht_fail
    xor r12d, r12d
3:  imul rdi, r12, 3
    add rdi, [rip + mht_vec + VEC_ptr]
    mov esi, 3
    lea rdx, [r12 + 1]
    call mht_bytes
    inc r12
    cmp r12, 40
    jb 3b
    call mht_free
    inc r15
    cmp r15, 4
    jbe .Lmht_scenario
.endif
    call mht_balanced
    lea rdi, [rip + mht_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
