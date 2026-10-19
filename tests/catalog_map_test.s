# Actual counted radix insertion, prefix splits, sibling rotations and tiny budgets.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/catalogregistrymap.inc"
.section .rodata
cmap_abc: .asciz "abc"
cmap_abd: .asciz "abd"
cmap_ab: .asciz "ab"
cmap_abce: .asciz "abce"
cmap_empty: .asciz ""
cmap_xyz: .asciz "xyz"
cmap_a: .asciz "a"
cmap_upper: .asciz "AB"
cmap_xy: .asciz "xy"
cmap_short:
    .quad cmap_abc,3,1,0
    .quad cmap_abd,3,2,0
    .quad cmap_ab,2,3,0
    .quad cmap_abce,4,4,0
    .quad cmap_empty,0,5,0
    .quad cmap_xyz,3,6,0
    .quad cmap_ab,2,3,1
    .quad cmap_abc,3,1,1
    .quad cmap_a,1,9,0
    .quad cmap_upper,2,10,0
    .quad cmap_abd,3,2,1
    .quad cmap_xy,2,12,0
cmap_rl: .byte 50,100,75
cmap_lr: .byte 100,50,75
.bss
.p2align 3
cmap_cursor: .zero RM_SIZE
cmap_nodes: .zero 1024*RM_NODE_SIZE
cmap_pairs: .zero 255*3
cmap_long1: .zero 2*1024*1024+1
cmap_long2: .zero 2*1024*1024+1
cmap_desc: .zero 32
cmap_stage: .quad 0
cmap_live: .quad 0
cmap_charge: .quad 0
cmap_last_bytes: .quad 0
.text
cmap_fail:
    mov rdi, [rip + cmap_stage]
    add rdi, 40
    call sys_exit
    ud2
cmap_reset:
    PROLOGUE
    mov r12, rdi
    lea rdi, [rip + cmap_nodes]
    xor esi, esi
    mov edx, 1024*RM_NODE_SIZE
    call memset
    lea rdi, [rip + cmap_cursor]
    lea rsi, [rip + cmap_nodes]
    mov rdx, r12
    call registry_map_init
    test rax, rax
    jnz cmap_fail
    EPILOGUE

# Every actual nonroot node obeys compressed-edge and sibling AVL invariants.
cmap_validate:
    PROLOGUE 32
    lea rbx, [rip + cmap_cursor]
    mov r12d, 2
1:  cmp r12, [rbx + RM_used]
    ja 9f
    mov rdi, rbx
    mov rsi, r12
    call registry_map_node
    test rax, rax
    jz cmap_fail
    mov r13, rax
    cmp qword ptr [r13 + RM_edgelen], 0
    je cmap_fail
    mov rax, [r13 + RM_keyoff]
    add rax, [r13 + RM_edgelen]
    cmp rax, 2*1024*1024
    ja cmap_fail
    mov rax, [r13 + RM_keyptr]
    mov rcx, [r13 + RM_keyoff]
    movzx eax, byte ptr [rax + rcx]
    test eax, eax
    jz cmap_fail
    cmp [r13 + RM_first], rax
    jne cmap_fail
    mov rsi, [r13 + RM_left]
    test rsi, rsi
    jz 2f
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz cmap_fail
    cmp [rax + RM_up], r12
    jne cmap_fail
    mov rcx, [rax + RM_first]
    cmp rcx, [r13 + RM_first]
    jae cmap_fail
    mov rcx, [rax + RM_keyoff]
    cmp rcx, [r13 + RM_keyoff]
    jne cmap_fail
2:  mov rsi, [r13 + RM_right]
    test rsi, rsi
    jz 3f
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz cmap_fail
    cmp [rax + RM_up], r12
    jne cmap_fail
    mov rcx, [rax + RM_first]
    cmp rcx, [r13 + RM_first]
    jbe cmap_fail
    mov rcx, [rax + RM_keyoff]
    cmp rcx, [r13 + RM_keyoff]
    jne cmap_fail
3:  mov rsi, [r13 + RM_children]
    test rsi, rsi
    jz 4f
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz cmap_fail
    cmp qword ptr [rax + RM_up], 0
    jne cmap_fail
    mov rcx, [r13 + RM_keyoff]
    add rcx, [r13 + RM_edgelen]
    cmp [rax + RM_keyoff], rcx
    jne cmap_fail
4:  mov rdi, rbx
    mov rsi, [r13 + RM_left]
    call registry_map_height
    test rax, rax
    js cmap_fail
    mov r14, rax
    mov rdi, rbx
    mov rsi, [r13 + RM_right]
    call registry_map_height
    test rax, rax
    js cmap_fail
    mov r15, rax
    sub rax, r14
    cmp rax, 1
    jg cmap_fail
    cmp rax, -1
    jl cmap_fail
    cmp r15, r14
    cmova r14, r15
    inc r14
    cmp [r13 + RM_height], r14
    jne cmap_fail
    inc r12
    jmp 1b
9:  EPILOGUE

# descriptor32(key,len,expectedRow,expectedExisting),proposedRow,budget.
cmap_insert:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    lea rbx, [rip + cmap_cursor]
    mov rdi, rbx
    mov rsi, [r12]
    mov rdx, [r12 + 8]
    mov rcx, r13
    call registry_map_start
    test rax, rax
    jnz cmap_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    mov ecx, 1
    call registry_map_start
    cmp rax, -22
    jne cmap_fail
    mov rax, [r12]
    cmp [rbx + RM_key], rax
    jne cmap_fail
    mov qword ptr [rip + cmap_last_bytes], 0
    mov r15d, 1000000
1:  mov rdi, rbx
    mov rsi, r14
    mov edx, 16
    call registry_map_step
    cmp r8, r14
    ja cmap_fail
    cmp r9, 16
    ja cmap_fail
    test r8, r8
    jz 2f
    test r9, r9
    jz cmap_fail
2:  add [rip + cmap_last_bytes], r8
    test rax, rax
    js cmap_fail
    jz 3f
    dec r15
    jnz 1b
    jmp cmap_fail
3:  cmp rdx, [r12 + 16]
    jne cmap_fail
    cmp rcx, [r12 + 24]
    jne cmap_fail
    mov qword ptr [rbx + RM_key], 1
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call registry_map_step
    test rax, rax
    jnz cmap_fail
    cmp rdx, [r12 + 16]
    jne cmap_fail
    cmp rcx, [r12 + 24]
    jne cmap_fail
    test r8, r8
    jnz cmap_fail
    test r9, r9
    jnz cmap_fail
    call cmap_validate
    EPILOGUE

# Byte selector1..255, proposed/expected row and existing flag.
cmap_byte_insert:
    PROLOGUE
    lea rax, [rip + cmap_pairs]
    lea rdi, [rdi + rdi*2 - 3]
    add rax, rdi
    mov [rip + cmap_desc], rax
    mov qword ptr [rip + cmap_desc + 8], 2
    mov [rip + cmap_desc + 16], rsi
    mov [rip + cmap_desc + 24], rdx
    lea rdi, [rip + cmap_desc]
    mov edx, 1
    call cmap_insert
    EPILOGUE
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + cmap_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + cmap_charge], rax
    mov qword ptr [rip + cmap_stage], 1
    mov edi, 1024
    call cmap_reset
    xor r12d, r12d
1:  lea rdi, [rip + cmap_short]
    mov rax, r12
    shl rax, 5
    add rdi, rax
    lea rsi, [r12 + 1]
    mov edx, 1
    call cmap_insert
    inc r12
    cmp r12, 12
    jb 1b
    mov qword ptr [rip + cmap_stage], 2
    lea r13, [rip + cmap_pairs]
    mov r12d, 1
2:  mov [r13], r12b
    mov byte ptr [r13 + 1], 'x'
    add r13, 3
    inc r12
    cmp r12, 255
    jbe 2b
    mov edi, 1024
    call cmap_reset
    mov r12d, 1
3:  mov rdi, r12
    lea rsi, [r12 + 1000]
    xor edx, edx
    call cmap_byte_insert
    inc r12
    cmp r12, 255
    jbe 3b
    mov r12d, 255
4:  mov rdi, r12
    lea rsi, [r12 + 1000]
    mov edx, 1
    call cmap_byte_insert
    dec r12
    jnz 4b
    mov qword ptr [rip + cmap_stage], 3
    mov edi, 1024
    call cmap_reset
    mov r12d, 255
5:  mov rdi, r12
    lea rsi, [r12 + 1000]
    xor edx, edx
    call cmap_byte_insert
    dec r12
    jnz 5b
    mov r12d, 1
6:  mov rdi, r12
    lea rsi, [r12 + 1000]
    mov edx, 1
    call cmap_byte_insert
    inc r12
    cmp r12, 255
    jbe 6b
    mov qword ptr [rip + cmap_stage], 4
    mov edi, 1024
    call cmap_reset
    xor r12d, r12d
7:  lea rax, [rip + cmap_rl]
    movzx edi, byte ptr [rax + r12]
    lea rsi, [rdi + 1000]
    xor edx, edx
    call cmap_byte_insert
    inc r12
    cmp r12, 3
    jb 7b
    mov edi, 1024
    call cmap_reset
    xor r12d, r12d
8:  lea rax, [rip + cmap_lr]
    movzx edi, byte ptr [rax + r12]
    lea rsi, [rdi + 1000]
    xor edx, edx
    call cmap_byte_insert
    inc r12
    cmp r12, 3
    jb 8b
    mov qword ptr [rip + cmap_stage], 5
    mov edi, 1024
    call cmap_reset
    lea rdi, [rip + cmap_long1]
    mov esi, 'a'
    mov edx, 2*1024*1024
    call memset
    lea rdi, [rip + cmap_long2]
    mov esi, 'a'
    mov edx, 2*1024*1024
    call memset
    mov byte ptr [rip + cmap_long2 + 2*1024*1024-1], 'b'
    lea rax, [rip + cmap_long1]
    mov [rip + cmap_desc], rax
    mov qword ptr [rip + cmap_desc + 8], 2*1024*1024
    mov qword ptr [rip + cmap_desc + 16], 1
    mov qword ptr [rip + cmap_desc + 24], 0
    lea rdi, [rip + cmap_desc]
    mov esi, 1
    mov edx, 65536
    call cmap_insert
    lea rax, [rip + cmap_long2]
    mov [rip + cmap_desc], rax
    mov qword ptr [rip + cmap_desc + 16], 2
    lea rdi, [rip + cmap_desc]
    mov esi, 2
    mov edx, 65536
    call cmap_insert
    cmp qword ptr [rip + cmap_last_bytes], 4*1024*1024-1
    jne cmap_fail
    lea rax, [rip + cmap_long1]
    mov [rip + cmap_desc], rax
    mov qword ptr [rip + cmap_desc + 16], 1
    mov qword ptr [rip + cmap_desc + 24], 1
    lea rdi, [rip + cmap_desc]
    mov esi, 3
    mov edx, 65536
    call cmap_insert
    # A single-unit call must never hide a larger comparison chunk.
    lea rdi, [rip + cmap_cursor]
    lea rsi, [rip + cmap_long1]
    mov edx, 2*1024*1024
    mov ecx, 4
    call registry_map_start
    test rax, rax
    jnz cmap_fail
    mov r12d, 100000
11: lea rdi, [rip + cmap_cursor]
    mov esi, 65536
    mov edx, 1
    call registry_map_step
    cmp r8, 4096
    ja cmap_fail
    cmp r9, 1
    ja cmap_fail
    test rax, rax
    js cmap_fail
    jz 12f
    dec r12
    jnz 11b
    jmp cmap_fail
12: cmp rdx, 1
    jne cmap_fail
    cmp rcx, 1
    jne cmap_fail
    mov qword ptr [rip + cmap_stage], 6
    mov edi, 3
    call cmap_reset
    lea rax, [rip + cmap_abc]
    mov [rip + cmap_desc], rax
    mov qword ptr [rip + cmap_desc + 8], 3
    mov qword ptr [rip + cmap_desc + 16], 1
    mov qword ptr [rip + cmap_desc + 24], 0
    lea rdi, [rip + cmap_desc]
    mov esi, 1
    mov edx, 1
    call cmap_insert
    mov byte ptr [rip + cmap_nodes + 2*RM_NODE_SIZE], 0x5a
    lea rdi, [rip + cmap_cursor]
    lea rsi, [rip + cmap_abd]
    mov edx, 3
    mov ecx, 2
    call registry_map_start
    test rax, rax
    jnz cmap_fail
    mov r12d, 100
9:  lea rdi, [rip + cmap_cursor]
    mov esi, 1
    mov edx, 16
    call registry_map_step
    cmp r8, 1
    ja cmap_fail
    cmp r9, 16
    ja cmap_fail
    test rax, rax
    js 10f
    dec r12
    jnz 9b
    jmp cmap_fail
10: cmp rax, -EV_RESOURCE
    jne cmap_fail
    cmp byte ptr [rip + cmap_nodes + 2*RM_NODE_SIZE], 0x5a
    jne cmap_fail
    cmp qword ptr [rip + cmap_cursor + RM_used], 2
    jne cmap_fail
    cmp qword ptr [rip + cmap_nodes + RM_NODE_SIZE + RM_edgelen], 3
    jne cmap_fail
    cmp qword ptr [rip + cmap_nodes + RM_NODE_SIZE + RM_value], 1
    jne cmap_fail
    mov qword ptr [rip + cmap_cursor + RM_key], 1
    lea rdi, [rip + cmap_cursor]
    mov esi, 1
    mov edx, 16
    call registry_map_step
    cmp rax, -EV_RESOURCE
    jne cmap_fail
    test r8, r8
    jnz cmap_fail
    test r9, r9
    jnz cmap_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cmap_live]
    jne cmap_fail
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + cmap_charge]
    jne cmap_fail
    xor eax, eax
    EPILOGUE
