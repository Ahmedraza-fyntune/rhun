# Pure radix insertion. All key borrows and zeroed node storage are caller-owned.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/catalogregistrymap.inc"
.text
# map,nodes,capacity (including empty root). Caller supplies zeroed owned storage.
FN registry_map_init
    test rdi, rdi
    jz .Lrmi_bad
    test rsi, rsi
    jz .Lrmi_bad
    test rdx, rdx
    jz .Lrmi_bad
    cmp rdx, RM_NODE_CAP
    ja .Lrmi_bad
    imul rax, rdx, RM_NODE_SIZE
    add rax, rsi
    jc .Lrmi_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor esi, esi
    mov edx, RM_SIZE
    call memset
    mov [rbx + RM_nodes], r12
    mov [rbx + RM_capacity], r13
    mov qword ptr [rbx + RM_used], 1
    xor eax, eax
    EPILOGUE
.Lrmi_bad:
    mov rax, -22
    ret

# map,key,counted length,proposed ordinal+1. Every prior key remains borrowed.
FN registry_map_start
    test rdi, rdi
    jz .Lrms_bad
    test rsi, rsi
    jz .Lrms_bad
    cmp rdx, 2 * 1024 * 1024
    ja .Lrms_bad
    test rcx, rcx
    jz .Lrms_bad
    cmp rcx, 65536
    ja .Lrms_bad
    mov rax, rsi
    add rax, rdx
    jc .Lrms_bad
    mov rax, [rdi + RM_phase]
    test rax, rax
    jz 1f
    cmp rax, RM_DONE
    jne .Lrms_bad
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rdi, [rbx + RM_key]
    xor esi, esi
    mov edx, RM_limit_bytes - RM_key
    call memset
    mov [rbx + RM_key], r12
    mov [rbx + RM_length], r13
    mov [rbx + RM_proposed], r14
    mov qword ptr [rbx + RM_parent], 1
    mov qword ptr [rbx + RM_phase], RM_LOOKUP
    xor eax, eax
    EPILOGUE
.Lrms_bad:
    mov rax, -22
    ret

# Internal index validation. Index1 is root; index0 is the NULL sentinel.
FN registry_map_node
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, [rdi + RM_used]
    ja 9f
    mov rax, [rdi + RM_used]
    cmp rax, [rdi + RM_capacity]
    ja 8f
    imul rax, rsi, RM_NODE_SIZE
    sub rax, RM_NODE_SIZE
    add rax, [rdi + RM_nodes]
    ret
8:  xor eax, eax
9:  ret

# No native allocator. Each physical node is initialized once in zeroed storage.
FN registry_map_new_node
    mov rax, [rdi + RM_used]
    cmp rax, [rdi + RM_capacity]
    jae 8f
    inc rax
    mov [rdi + RM_used], rax
    imul rdx, rax, RM_NODE_SIZE
    sub rdx, RM_NODE_SIZE
    add rdx, [rdi + RM_nodes]
    mov qword ptr [rdx + RM_height], 1
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# Height of absent child0 is0; malformed links return negative.
FN registry_map_height
    test rsi, rsi
    jz 8f
    PROLOGUE
    call registry_map_node
    test rax, rax
    jz 7f
    mov rax, [rax + RM_height]
    test rax, rax
    jz 7f
    cmp rax, 12
    ja 7f
    EPILOGUE
7:  mov rax, -EV_BAD_PREPARE
    EPILOGUE
8:  xor eax, eax
    ret

FN registry_map_update_height
    PROLOGUE
    mov rbx, rdi
    call registry_map_node
    test rax, rax
    jz .Lrmuh_bad
    mov r12, rax
    mov rsi, [r12 + RM_left]
    call registry_map_height
    test rax, rax
    js .Lrmuh_return
    mov r13, rax
    mov rdi, rbx
    mov rsi, [r12 + RM_right]
    call registry_map_height
    test rax, rax
    js .Lrmuh_return
    cmp rax, r13
    cmovb rax, r13
    inc rax
    cmp rax, 12
    ja .Lrmuh_bad
    mov [r12 + RM_height], rax
.Lrmuh_return:
    EPILOGUE
.Lrmuh_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

# One sibling rotation. direction0 left,1 right. Link preflight precedes mutation.
FN registry_map_rotate
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call registry_map_node
    test rax, rax
    jz .Lrmrot_bad
    mov r14, rax
    mov [rsp], rax
    mov rsi, [rax + RM_right]
    test r13, r13
    jz 1f
    mov rsi, [rax + RM_left]
1:  mov [rsp + 8], rsi
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz .Lrmrot_bad
    mov r15, rax
    mov [rsp + 16], rax
    mov rsi, [rax + RM_left]
    test r13, r13
    jz 2f
    mov rsi, [rax + RM_right]
2:  mov [rsp + 24], rsi
    mov qword ptr [rsp + 32], 0
    test rsi, rsi
    jz 3f
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz .Lrmrot_bad
    mov [rsp + 32], rax
3:  mov rsi, [r14 + RM_up]
    mov [rsp + 40], rsi
    test rsi, rsi
    jz .Lrmrot_root
    mov rdi, rbx
    call registry_map_node
    test rax, rax
    jz .Lrmrot_bad
    lea rcx, [rax + RM_left]
    cmp [rcx], r12
    je 4f
    lea rcx, [rax + RM_right]
    cmp [rcx], r12
    jne .Lrmrot_bad
    jmp 4f
.Lrmrot_root:
    mov rdi, rbx
    mov rsi, [rbx + RM_parent]
    call registry_map_node
    test rax, rax
    jz .Lrmrot_bad
    lea rcx, [rax + RM_children]
    cmp [rcx], r12
    jne .Lrmrot_bad
4:  mov rax, [rsp + 8]
    mov [rcx], rax
    mov rdx, [rsp + 40]
    mov [r15 + RM_up], rdx
    mov [r14 + RM_up], rax
    mov rdx, [rsp + 24]
    test r13, r13
    jnz .Lrmrot_right
    mov [r14 + RM_right], rdx
    mov [r15 + RM_left], r12
    jmp 5f
.Lrmrot_right:
    mov [r14 + RM_left], rdx
    mov [r15 + RM_right], r12
5:  mov rax, [rsp + 32]
    test rax, rax
    jz 6f
    mov [rax + RM_up], r12
6:  mov rdi, rbx
    mov rsi, r12
    call registry_map_update_height
    test rax, rax
    js .Lrmrot_return
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call registry_map_update_height
    test rax, rax
    js .Lrmrot_return
    mov rax, [rsp + 8]
.Lrmrot_return:
    EPILOGUE
.Lrmrot_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

# At most one rotation/ancestor. A double rotation remains two distinct units.
FN registry_map_balance_one
    PROLOGUE 32
    mov rbx, rdi
    mov rsi, [rbx + RM_rebalance]
    test rsi, rsi
    jz .Lrmb_done
    mov [rsp], rsi
    call registry_map_node
    test rax, rax
    jz .Lrmb_bad
    mov r12, rax
    mov rdi, rbx
    mov rsi, [r12 + RM_left]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [r12 + RM_right]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    mov [rsp + 16], rax
    mov rcx, [rsp + 8]
    cmp rcx, rax
    cmova rax, rcx
    inc rax
    cmp rax, 12
    ja .Lrmb_bad
    mov [r12 + RM_height], rax
    mov rax, [rsp + 8]
    sub rax, [rsp + 16]
    cmp rax, 2
    je .Lrmb_left
    cmp rax, -2
    je .Lrmb_right
    cmp rax, 2
    jg .Lrmb_bad
    cmp rax, -2
    jl .Lrmb_bad
    mov rax, [r12 + RM_up]
    mov [rbx + RM_rebalance], rax
    xor eax, eax
    EPILOGUE
.Lrmb_left:
    mov r13, [r12 + RM_left]
    mov rdi, rbx
    mov rsi, r13
    call registry_map_node
    test rax, rax
    jz .Lrmb_bad
    mov r14, rax
    mov rdi, rbx
    mov rsi, [r14 + RM_left]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    mov r15, rax
    mov rdi, rbx
    mov rsi, [r14 + RM_right]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    cmp r15, rax
    jae .Lrmb_full_right
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    call registry_map_rotate
    test rax, rax
    js .Lrmb_return
    xor eax, eax
    EPILOGUE
.Lrmb_full_right:
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, 1
    call registry_map_rotate
    jmp .Lrmb_rotated
.Lrmb_right:
    mov r13, [r12 + RM_right]
    mov rdi, rbx
    mov rsi, r13
    call registry_map_node
    test rax, rax
    jz .Lrmb_bad
    mov r14, rax
    mov rdi, rbx
    mov rsi, [r14 + RM_left]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    mov r15, rax
    mov rdi, rbx
    mov rsi, [r14 + RM_right]
    call registry_map_height
    test rax, rax
    js .Lrmb_return
    cmp r15, rax
    jbe .Lrmb_full_left
    mov rdi, rbx
    mov rsi, r13
    mov edx, 1
    call registry_map_rotate
    test rax, rax
    js .Lrmb_return
    xor eax, eax
    EPILOGUE
.Lrmb_full_left:
    mov rdi, rbx
    mov rsi, [rsp]
    xor edx, edx
    call registry_map_rotate
.Lrmb_rotated:
    test rax, rax
    js .Lrmb_return
    mov rdi, rbx
    mov rsi, rax
    call registry_map_node
    test rax, rax
    jz .Lrmb_bad
    mov rax, [rax + RM_up]
    mov [rbx + RM_rebalance], rax
.Lrmb_done:
    xor eax, eax
.Lrmb_return:
    EPILOGUE
.Lrmb_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

# map,byteBudget0..65536,unitBudget0..16. No allocator/parser/native calls.
# AX1pending/0done/-error, DXrowPlusOne,CXexisting,R8bytes,R9units.
FN registry_map_step
    PROLOGUE 64
    mov rbx, rdi
    test rbx, rbx
    jz .Lrm_invalid
    cmp rsi, 65536
    ja .Lrm_invalid
    cmp rdx, 16
    ja .Lrm_invalid
    mov rax, [rbx + RM_phase]
    cmp rax, RM_DONE
    je .Lrm_cached_done
    cmp rax, RM_FAILED
    je .Lrm_cached_failure
    mov [rbx + RM_limit_bytes], rsi
    mov [rbx + RM_limit_units], rdx
    mov qword ptr [rbx + RM_bytes], 0
    mov qword ptr [rbx + RM_units], 0
.Lrm_loop:
    mov rax, [rbx + RM_units]
    cmp rax, [rbx + RM_limit_units]
    jae .Lrm_pending
    mov rax, [rbx + RM_phase]
    cmp rax, RM_LOOKUP
    je .Lrm_lookup
    cmp rax, RM_COMPARE
    je .Lrm_compare
    cmp rax, RM_SPLIT
    je .Lrm_split
    cmp rax, RM_REBALANCE
    je .Lrm_rebalance
    jmp .Lrm_corrupt
.Lrm_lookup:
    mov rax, [rbx + RM_offset]
    cmp rax, [rbx + RM_length]
    je .Lrm_terminal
    ja .Lrm_corrupt
    cmp qword ptr [rbx + RM_search_have], 0
    jne .Lrm_search
    mov rcx, [rbx + RM_bytes]
    cmp rcx, [rbx + RM_limit_bytes]
    jae .Lrm_pending
    mov rcx, [rbx + RM_key]
    movzx eax, byte ptr [rcx + rax]
    inc qword ptr [rbx + RM_bytes]
    test eax, eax
    jnz 8f
    inc qword ptr [rbx + RM_units]
    jmp .Lrm_corrupt
8:  mov [rbx + RM_search_byte], rax
    mov qword ptr [rbx + RM_search_have], 1
.Lrm_search:
    inc qword ptr [rbx + RM_units]
    mov rdi, rbx
    mov rsi, [rbx + RM_parent]
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov r13, [rax + RM_children]
    xor r12d, r12d
    mov r15d, 12
.Lrm_search_loop:
    test r13, r13
    jz .Lrm_new_leaf
    mov rdi, rbx
    mov rsi, r13
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov r14, rax
    mov rax, [rbx + RM_search_byte]
    cmp rax, [r14 + RM_first]
    je .Lrm_found_edge
    mov r12, r13
    mov r13, [r14 + RM_left]
    jb 1f
    mov r13, [r14 + RM_right]
1:  dec r15
    jnz .Lrm_search_loop
    test r13, r13
    jnz .Lrm_corrupt
.Lrm_new_leaf:
    mov rdi, rbx
    call registry_map_new_node
    test rax, rax
    jz .Lrm_resource
    mov r13, rax
    mov r14, rdx
    mov rcx, [rbx + RM_key]
    mov [r14 + RM_keyptr], rcx
    mov rcx, [rbx + RM_offset]
    mov [r14 + RM_keyoff], rcx
    mov rax, [rbx + RM_length]
    sub rax, rcx
    mov [r14 + RM_edgelen], rax
    mov rax, [rbx + RM_search_byte]
    mov [r14 + RM_first], rax
    mov rax, [rbx + RM_proposed]
    mov [r14 + RM_value], rax
    mov [rbx + RM_result], rax
    mov qword ptr [rbx + RM_existing], 0
    mov [r14 + RM_up], r12
    test r12, r12
    jz .Lrm_link_root
    mov rdi, rbx
    mov rsi, r12
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov rcx, [rbx + RM_search_byte]
    cmp rcx, [rax + RM_first]
    ja .Lrm_link_right
    mov [rax + RM_left], r13
    jmp .Lrm_linked
.Lrm_link_right:
    mov [rax + RM_right], r13
    jmp .Lrm_linked
.Lrm_link_root:
    mov rdi, rbx
    mov rsi, [rbx + RM_parent]
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov [rax + RM_children], r13
.Lrm_linked:
    mov [rbx + RM_rebalance], r12
    mov qword ptr [rbx + RM_phase], RM_REBALANCE
    jmp .Lrm_loop
.Lrm_found_edge:
    mov [rbx + RM_node], r13
    mov qword ptr [rbx + RM_edge_offset], 1
    inc qword ptr [rbx + RM_offset]
    mov qword ptr [rbx + RM_search_have], 0
    mov qword ptr [rbx + RM_phase], RM_COMPARE
    jmp .Lrm_loop
.Lrm_terminal:
    inc qword ptr [rbx + RM_units]
    mov rdi, rbx
    mov rsi, [rbx + RM_parent]
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov rcx, [rax + RM_value]
    test rcx, rcx
    jz .Lrm_new_terminal
    mov [rbx + RM_result], rcx
    mov qword ptr [rbx + RM_existing], 1
    jmp .Lrm_mark_done
.Lrm_new_terminal:
    mov rcx, [rbx + RM_proposed]
    mov [rax + RM_value], rcx
    mov [rbx + RM_result], rcx
    mov qword ptr [rbx + RM_existing], 0
    jmp .Lrm_mark_done
.Lrm_compare:
    mov rdi, rbx
    mov rsi, [rbx + RM_node]
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov rdi, [rax + RM_keyptr]
    add rdi, [rax + RM_keyoff]
    jc .Lrm_corrupt
    mov r10, [rax + RM_edgelen]
    mov rsi, [rbx + RM_key]
    mov rcx, [rbx + RM_length]
    mov r12, [rbx + RM_offset]
    mov r13, [rbx + RM_edge_offset]
    cmp r12, rcx
    ja .Lrm_corrupt
    cmp r13, r10
    ja .Lrm_corrupt
    mov r14, [rbx + RM_limit_bytes]
    sub r14, [rbx + RM_bytes]
    cmp r12, rcx
    je .Lrm_compare_boundary
    cmp r13, r10
    je .Lrm_compare_boundary
    test r14, r14
    jz .Lrm_pending
    cmp r14, 4096
    jbe 2f
    mov r14d, 4096
2:  mov r8, [rbx + RM_have_held]
    mov r9, [rbx + RM_held]
    xor r15d, r15d
.Lrm_compare_loop:
    test r8, r8
    jnz .Lrm_compare_right
    movzx r9d, byte ptr [rsi + r12]
    inc r15
    dec r14
    test r9d, r9d
    jz .Lrm_compare_bad
    mov r8d, 1
    test r14, r14
    jz .Lrm_compare_pause
.Lrm_compare_right:
    movzx eax, byte ptr [rdi + r13]
    inc r15
    dec r14
    test eax, eax
    jz .Lrm_compare_bad
    cmp eax, r9d
    jne .Lrm_compare_mismatch
    inc r12
    inc r13
    xor r8d, r8d
    cmp r12, rcx
    je .Lrm_compare_save_boundary
    cmp r13, r10
    je .Lrm_compare_save_boundary
    test r14, r14
    jnz .Lrm_compare_loop
.Lrm_compare_pause:
    mov [rbx + RM_offset], r12
    mov [rbx + RM_edge_offset], r13
    mov [rbx + RM_have_held], r8
    mov [rbx + RM_held], r9
    add [rbx + RM_bytes], r15
    inc qword ptr [rbx + RM_units]
    jmp .Lrm_loop
.Lrm_compare_mismatch:
    mov [rbx + RM_old_byte], rax
    mov [rbx + RM_new_byte], r9
    mov qword ptr [rbx + RM_have_old], 1
    mov qword ptr [rbx + RM_have_new], 1
    mov qword ptr [rbx + RM_have_held], 0
    mov [rbx + RM_offset], r12
    mov [rbx + RM_edge_offset], r13
    add [rbx + RM_bytes], r15
    inc qword ptr [rbx + RM_units]
    mov qword ptr [rbx + RM_phase], RM_SPLIT
    jmp .Lrm_loop
.Lrm_compare_save_boundary:
    mov [rbx + RM_offset], r12
    mov [rbx + RM_edge_offset], r13
    mov qword ptr [rbx + RM_have_held], 0
    add [rbx + RM_bytes], r15
.Lrm_compare_boundary:
    inc qword ptr [rbx + RM_units]
    cmp r13, r10
    je .Lrm_advance_edge
    mov qword ptr [rbx + RM_have_old], 0
    mov qword ptr [rbx + RM_have_new], 0
    mov qword ptr [rbx + RM_phase], RM_SPLIT
    jmp .Lrm_loop
.Lrm_advance_edge:
    mov rax, [rbx + RM_node]
    mov [rbx + RM_parent], rax
    mov qword ptr [rbx + RM_search_have], 0
    mov qword ptr [rbx + RM_phase], RM_LOOKUP
    jmp .Lrm_loop
.Lrm_compare_bad:
    add [rbx + RM_bytes], r15
    inc qword ptr [rbx + RM_units]
    jmp .Lrm_corrupt
.Lrm_split:
    mov rdi, rbx
    mov rsi, [rbx + RM_node]
    call registry_map_node
    test rax, rax
    jz .Lrm_corrupt
    mov [rsp], rax
    mov r12, [rbx + RM_edge_offset]
    test r12, r12
    jz .Lrm_corrupt
    cmp r12, [rax + RM_edgelen]
    jae .Lrm_corrupt
    cmp qword ptr [rbx + RM_have_old], 0
    jne .Lrm_split_capacity
    mov rcx, [rbx + RM_bytes]
    cmp rcx, [rbx + RM_limit_bytes]
    jae .Lrm_pending
    mov rcx, [rax + RM_keyptr]
    add rcx, [rax + RM_keyoff]
    jc .Lrm_corrupt
    movzx eax, byte ptr [rcx + r12]
    inc qword ptr [rbx + RM_bytes]
    test eax, eax
    jnz 9f
    inc qword ptr [rbx + RM_units]
    jmp .Lrm_corrupt
9:  mov [rbx + RM_old_byte], rax
    mov qword ptr [rbx + RM_have_old], 1
.Lrm_split_capacity:
    inc qword ptr [rbx + RM_units]
    mov r13d, 1
    mov rax, [rbx + RM_offset]
    cmp rax, [rbx + RM_length]
    je 3f
    ja .Lrm_corrupt
    cmp qword ptr [rbx + RM_have_new], 1
    jne .Lrm_corrupt
    inc r13
3:  mov rax, [rbx + RM_used]
    add rax, r13
    cmp rax, [rbx + RM_capacity]
    ja .Lrm_resource
    mov rdi, rbx
    call registry_map_new_node
    test rax, rax
    jz .Lrm_resource
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov r14, [rsp]
    mov rcx, [r14 + RM_keyptr]
    mov [rdx + RM_keyptr], rcx
    mov rcx, [r14 + RM_keyoff]
    add rcx, r12
    mov [rdx + RM_keyoff], rcx
    mov rcx, [r14 + RM_edgelen]
    sub rcx, r12
    mov [rdx + RM_edgelen], rcx
    mov rcx, [r14 + RM_children]
    mov [rdx + RM_children], rcx
    mov rcx, [r14 + RM_value]
    mov [rdx + RM_value], rcx
    mov rcx, [rbx + RM_old_byte]
    mov [rdx + RM_first], rcx
    cmp r13, 2
    je .Lrm_split_new_suffix
    mov rcx, [rbx + RM_proposed]
    mov [r14 + RM_value], rcx
    jmp .Lrm_split_commit
.Lrm_split_new_suffix:
    mov rdi, rbx
    call registry_map_new_node
    test rax, rax
    jz .Lrm_resource
    mov r15, [rsp + 16]
    mov rcx, [rbx + RM_key]
    mov [rdx + RM_keyptr], rcx
    mov rcx, [rbx + RM_offset]
    mov [rdx + RM_keyoff], rcx
    mov rsi, [rbx + RM_length]
    sub rsi, rcx
    mov [rdx + RM_edgelen], rsi
    mov rcx, [rbx + RM_proposed]
    mov [rdx + RM_value], rcx
    mov rcx, [rsp + 8]
    mov [rdx + RM_up], rcx
    mov rcx, [rbx + RM_new_byte]
    mov [rdx + RM_first], rcx
    cmp rcx, [r15 + RM_first]
    je .Lrm_corrupt
    jb 4f
    mov [r15 + RM_right], rax
    jmp 5f
4:  mov [r15 + RM_left], rax
5:  mov qword ptr [r15 + RM_height], 2
    mov qword ptr [r14 + RM_value], 0
.Lrm_split_commit:
    mov [r14 + RM_edgelen], r12
    mov rax, [rsp + 8]
    mov [r14 + RM_children], rax
    mov rax, [rbx + RM_proposed]
    mov [rbx + RM_result], rax
    mov qword ptr [rbx + RM_existing], 0
    jmp .Lrm_mark_done
.Lrm_rebalance:
    inc qword ptr [rbx + RM_units]
    cmp qword ptr [rbx + RM_rebalance], 0
    je .Lrm_mark_done
    mov rdi, rbx
    call registry_map_balance_one
    test rax, rax
    js .Lrm_fail
    jmp .Lrm_loop
.Lrm_mark_done:
    mov qword ptr [rbx + RM_phase], RM_DONE
    xor eax, eax
    jmp .Lrm_return
.Lrm_resource:
    mov rax, -EV_RESOURCE
    jmp .Lrm_fail
.Lrm_corrupt:
    mov rax, -EV_BAD_PREPARE
.Lrm_fail:
    cmp qword ptr [rbx + RM_error], 0
    jne 6f
    mov [rbx + RM_error], rax
6:  mov qword ptr [rbx + RM_phase], RM_FAILED
    mov rax, [rbx + RM_error]
    jmp .Lrm_return
.Lrm_pending:
    mov eax, 1
.Lrm_return:
    xor edx, edx
    xor ecx, ecx
    test rax, rax
    jnz 7f
    mov rdx, [rbx + RM_result]
    mov rcx, [rbx + RM_existing]
7:  mov r8, [rbx + RM_bytes]
    mov r9, [rbx + RM_units]
    EPILOGUE
.Lrm_cached_done:
    xor eax, eax
    mov rdx, [rbx + RM_result]
    mov rcx, [rbx + RM_existing]
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
.Lrm_cached_failure:
    mov rax, [rbx + RM_error]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
.Lrm_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
