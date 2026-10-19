# WebAssembly execution: invoking a function, calls and returns, branches, locals and globals,
# memory and table instructions, traps. The numeric instructions are in wasmnum.s. Register use
# while wasm code runs is described in wasm.inc.
.include "rhun.inc"
.include "wasm/wasm.inc"

.bss
.p2align 3
.globl g_wasm_exit
g_wasm_vstack: .quad 0              # the value stack
g_wasm_vend: .quad 0
g_wasm_frames: .quad 0              # the call frame stack
g_wasm_fend: .quad 0
g_wasm_trap_rsp: .quad 0            # the running invocation's native stack and frame
g_wasm_trap_rbp: .quad 0
g_wasm_exit: .quad 0                # proc_exit's status (WT_EXIT)
dummy_inst: .zero WI_SIZE           # the bottom frame's instance

.data
.p2align 3
exit_code: .quad h_exit             # where the bottom frame returns to

.text
# wasm_invoke(function, args, results) -> eax 0 or a trap code. args and results are arrays of
# 8-byte values (i32 and f32 zero-extended); results may be 0 to drop them.
FN wasm_invoke
    PROLOGUE 48
    mov rax, [rip + g_wasm_trap_rsp]
    mov [rsp + 8], rax
    mov rax, [rip + g_wasm_trap_rbp]
    mov [rsp + 16], rax
    mov [rsp + 24], rdi
    mov [rsp + 32], rdx
    mov [rsp + 40], rsi
    cmp qword ptr [rip + g_wasm_vstack], 0
    jne 1f
    mov edi, WASM_STACK_BYTES
    call os_map
    mov [rip + g_wasm_vstack], rax
    add rax, WASM_STACK_BYTES - 64
    mov [rip + g_wasm_vend], rax
    mov edi, WASM_FRAMES * WFR_SIZE + 64
    call os_map
    mov [rip + g_wasm_frames], rax
    add rax, WASM_FRAMES * WFR_SIZE
    mov [rip + g_wasm_fend], rax
    lea rax, [rip + wasm_no_memory]
    mov [rip + dummy_inst + WI_mem], rax
1:  mov [rip + g_wasm_trap_rsp], rsp
    mov [rip + g_wasm_trap_rbp], rbp
    mov rdi, [rsp + 24]
    mov r12, [rip + g_wasm_vstack]
    mov rsi, [rsp + 40]
    mov ecx, [rdi + WFN_nparams]
2:  test ecx, ecx
    jz 3f
    mov rax, [rsi]
    mov [r12], rax
    add rsi, 8
    add r12, 8
    dec ecx
    jmp 2b
3:  mov rbp, [rip + g_wasm_frames]
    lea rbx, [rip + dummy_inst]
    mov r13, r12
    mov rax, [rbx + WI_mem]
    mov r14, [rax + WMEM_base]
    mov r15, [rax + WMEM_size]
    lea rsi, [rip + exit_code]
    jmp wasm_call_rdi
# the bottom frame returned: the results are the top values
h_exit:
    mov rsp, [rip + g_wasm_trap_rsp]
    mov rbp, [rip + g_wasm_trap_rbp]
    mov rdi, [rsp + 24]
    mov ecx, [rdi + WFN_nresults]
    mov rdx, [rsp + 32]
    test rdx, rdx
    jz 5f
    lea rax, [rcx*8]
    mov rsi, r12
    sub rsi, rax
4:  test ecx, ecx
    jz 5f
    mov rax, [rsi]
    mov [rdx], rax
    add rsi, 8
    add rdx, 8
    dec ecx
    jmp 4b
5:  xor eax, eax
.Linvoke_out:
    mov rcx, [rsp + 8]
    mov [rip + g_wasm_trap_rsp], rcx
    mov rcx, [rsp + 16]
    mov [rip + g_wasm_trap_rbp], rcx
    EPILOGUE

# wasm_trap(code eax): abandons the running invocation
FN wasm_trap
    mov rsp, [rip + g_wasm_trap_rsp]
    mov rbp, [rip + g_wasm_trap_rbp]
    jmp .Linvoke_out

FN wasm_trap_unreachable
    mov eax, WT_UNREACHABLE
    jmp wasm_trap
FN wasm_trap_div0
    mov eax, WT_DIV0
    jmp wasm_trap
FN wasm_trap_overflow
    mov eax, WT_OVERFLOW
    jmp wasm_trap
FN wasm_trap_conversion
    mov eax, WT_CONVERSION
    jmp wasm_trap
FN wasm_trap_oob
    mov eax, WT_OOB_MEMORY
    jmp wasm_trap
FN wasm_trap_oob_table
    mov eax, WT_OOB_TABLE
    jmp wasm_trap
FN wasm_trap_exhausted
    mov eax, WT_EXHAUSTED
    jmp wasm_trap

# wasm_trap_text(code) -> rax its message
FN wasm_trap_text
    cmp edi, WT_HOST
    ja 1f
    lea rax, [rip + .Ltrap_texts]
    mov rax, [rax + rdi*8]
    ret
1:  lea rax, [rip + .Lt_unknown]
    ret

# ---------------------------------------------------------------- calls

h_call:
    mov rdi, [rsi]
    add rsi, 8
# enter function rdi, returning to rsi
FN wasm_call_rdi
    cmp qword ptr [rdi + WFN_host], 0
    jne .Lcall_host
    cmp rbp, [rip + g_wasm_fend]
    jae wasm_trap_exhausted
    mov rax, r12
    add rax, [rdi + WFN_need]
    cmp rax, [rip + g_wasm_vend]
    ja wasm_trap_exhausted
    mov [rbp + WFR_ip], rsi
    mov [rbp + WFR_locals], r13
    mov [rbp + WFR_inst], rbx
    add rbp, WFR_SIZE
    mov eax, [rdi + WFN_nparams]
    shl rax, 3
    mov r13, r12
    sub r13, rax
    mov ecx, [rdi + WFN_nlocals]
    test ecx, ecx
    jz 2f
1:  mov qword ptr [r12], 0
    add r12, 8
    dec ecx
    jnz 1b
2:  mov rbx, [rdi + WFN_inst]
    mov rax, [rbx + WI_mem]
    mov r14, [rax + WMEM_base]
    mov r15, [rax + WMEM_size]
    mov rsi, [rdi + WFN_code]
    NEXT
.Lcall_host:
    # host(args, function) with the caller's instance in rbx; the results replace the arguments
    push rsi
    push rdi
    mov eax, [rdi + WFN_nparams]
    shl rax, 3
    sub r12, rax
    mov rsi, rdi
    mov rdi, r12
    call [rsi + WFN_host]
    pop rdi
    pop rsi
    test eax, eax
    jnz wasm_trap
    mov eax, [rdi + WFN_nresults]
    lea r12, [r12 + rax*8]
    mov rax, [rbx + WI_mem]
    mov r14, [rax + WMEM_base]
    mov r15, [rax + WMEM_size]
    NEXT

# [table][type id]
h_call_indirect:
    mov eax, [r12 - 8]
    sub r12, 8
    mov rdx, [rsi]
    cmp rax, [rdx + WTB_size]
    jae 1f
    mov rcx, [rdx + WTB_elems]
    mov rdi, [rcx + rax*8]
    test rdi, rdi
    jz 2f
    mov eax, [rsi + 8]
    cmp eax, [rdi + WFN_type]
    jne 3f
    add rsi, 16
    jmp wasm_call_rdi
1:  mov eax, WT_UNDEFINED
    jmp wasm_trap
2:  mov eax, WT_UNINIT
    jmp wasm_trap
3:  mov eax, WT_SIGNATURE
    jmp wasm_trap

h_return0:
    mov r12, r13
    jmp .Lret
h_return1:
    mov rax, [r12 - 8]
    mov [r13], rax
    lea r12, [r13 + 8]
    jmp .Lret
# [n]
h_return:
    mov rcx, [rsi]
    lea rax, [rcx*8]
    mov rdx, r12
    sub rdx, rax
    mov rdi, r13
1:  test rcx, rcx
    jz 2f
    mov rax, [rdx]
    mov [rdi], rax
    add rdx, 8
    add rdi, 8
    dec rcx
    jmp 1b
2:  mov r12, rdi
.Lret:
    sub rbp, WFR_SIZE
    mov rsi, [rbp + WFR_ip]
    mov r13, [rbp + WFR_locals]
    mov rbx, [rbp + WFR_inst]
    mov rax, [rbx + WI_mem]
    mov r14, [rax + WMEM_base]
    mov r15, [rax + WMEM_size]
    NEXT

# ---------------------------------------------------------------- branches
# A branch's target slot holds the target's offset from that slot. The drop variants lower the
# stack by a byte count; the move variants keep the top values (one, or n) above the lowered top.

h_unreachable:
    jmp wasm_trap_unreachable

# [target]
h_br:
    add rsi, [rsi]
    NEXT
# [target][drop]
h_br_drop:
    sub r12, [rsi + 8]
    add rsi, [rsi]
    NEXT
# [target][drop]
h_br_move1:
    mov rax, [r12 - 8]
    sub r12, [rsi + 8]
    mov [r12 - 8], rax
    add rsi, [rsi]
    NEXT
# [target][n][drop]
h_br_moven:
    mov rdx, [rsi + 8]
    mov rcx, [rsi + 16]
    mov rax, rsi
    add rax, [rsi]
# move rdx values down by rcx bytes, then continue at rax
.Lmove:
    lea r8, [rdx*8]
    mov r9, r12
    sub r9, r8
    mov r10, r9
    sub r10, rcx
1:  test rdx, rdx
    jz 2f
    mov r11, [r9]
    mov [r10], r11
    add r9, 8
    add r10, 8
    dec rdx
    jmp 1b
2:  sub r12, rcx
    mov rsi, rax
    NEXT

h_br_if:
    mov eax, [r12 - 8]
    sub r12, 8
    test eax, eax
    jz 1f
    add rsi, [rsi]
    NEXT
1:  add rsi, 8
    NEXT
h_br_if_drop:
    mov eax, [r12 - 8]
    sub r12, 8
    test eax, eax
    jz 1f
    sub r12, [rsi + 8]
    add rsi, [rsi]
    NEXT
1:  add rsi, 16
    NEXT
h_br_if_move1:
    mov eax, [r12 - 8]
    sub r12, 8
    test eax, eax
    jz 1f
    mov rax, [r12 - 8]
    sub r12, [rsi + 8]
    mov [r12 - 8], rax
    add rsi, [rsi]
    NEXT
1:  add rsi, 16
    NEXT
h_br_if_moven:
    mov eax, [r12 - 8]
    sub r12, 8
    test eax, eax
    jz 1f
    mov rdx, [rsi + 8]
    mov rcx, [rsi + 16]
    mov rax, rsi
    add rax, [rsi]
    jmp .Lmove
1:  add rsi, 24
    NEXT

# [false target]
h_if:
    mov eax, [r12 - 8]
    sub r12, 8
    test eax, eax
    jnz 1f
    add rsi, [rsi]
    NEXT
1:  add rsi, 8
    NEXT

# [count] then count + 1 entries [target][n][drop], the last the default
h_br_table:
    mov eax, [r12 - 8]
    sub r12, 8
    mov rcx, [rsi]
    cmp rax, rcx
    cmova rax, rcx
    lea rax, [rax + rax*2]
    lea rdi, [rsi + rax*8 + 8]
    mov rdx, [rdi + 8]
    mov rcx, [rdi + 16]
    mov rax, rdi
    add rax, [rdi]
    test rcx, rcx
    jnz .Lmove
    mov rsi, rax
    NEXT

# ---------------------------------------------------------------- operands, locals, globals

h_drop:
    sub r12, 8
    NEXT

h_select:
    mov eax, [r12 - 8]
    sub r12, 16
    test eax, eax
    jnz 1f
    mov rax, [r12]
    mov [r12 - 8], rax
1:  NEXT

# [value]
h_const:
    mov rax, [rsi]
    add rsi, 8
    mov [r12], rax
    add r12, 8
    NEXT

# [byte offset]
h_local_get:
    mov rax, [rsi]
    add rsi, 8
    mov rax, [r13 + rax]
    mov [r12], rax
    add r12, 8
    NEXT
h_local_set:
    mov rax, [rsi]
    add rsi, 8
    mov rcx, [r12 - 8]
    sub r12, 8
    mov [r13 + rax], rcx
    NEXT
h_local_tee:
    mov rax, [rsi]
    add rsi, 8
    mov rcx, [r12 - 8]
    mov [r13 + rax], rcx
    NEXT

# [WGL]
h_global_get:
    mov rax, [rsi]
    add rsi, 8
    mov rax, [rax]
    mov [r12], rax
    add r12, 8
    NEXT
h_global_set:
    mov rax, [rsi]
    add rsi, 8
    mov rcx, [r12 - 8]
    sub r12, 8
    mov [rax], rcx
    NEXT

h_ref_is_null:
    xor eax, eax
    cmp qword ptr [r12 - 8], 0
    sete al
    mov [r12 - 8], rax
    NEXT

# ---------------------------------------------------------------- memory

# loads [offset]: the address on top (offset added, bounds checked), the value replaces it
.macro LOADADDR size
    mov eax, [r12 - 8]
    add rax, [rsi]
    add rsi, 8
    lea rcx, [rax + \size]
    cmp rcx, r15
    ja wasm_trap_oob
.endm
h_i32_load:
    LOADADDR 4
    mov eax, dword ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i64_load:
    LOADADDR 8
    mov rax, qword ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i32_load8_s:
    LOADADDR 1
    movsx eax, byte ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i32_load8_u:
    LOADADDR 1
    movzx eax, byte ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i32_load16_s:
    LOADADDR 2
    movsx eax, word ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i32_load16_u:
    LOADADDR 2
    movzx eax, word ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i64_load8_s:
    LOADADDR 1
    movsx rax, byte ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i64_load16_s:
    LOADADDR 2
    movsx rax, word ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT
h_i64_load32_s:
    LOADADDR 4
    movsxd rax, dword ptr [r14 + rax]
    mov [r12 - 8], rax
    NEXT

# stores [offset]: the address, then the value
.macro STOREADDR size
    mov eax, [r12 - 16]
    add rax, [rsi]
    add rsi, 8
    lea rcx, [rax + \size]
    cmp rcx, r15
    ja wasm_trap_oob
    mov rcx, [r12 - 8]
.endm
h_i32_store:
    STOREADDR 4
    mov dword ptr [r14 + rax], ecx
    sub r12, 16
    NEXT
h_i64_store:
    STOREADDR 8
    mov qword ptr [r14 + rax], rcx
    sub r12, 16
    NEXT
h_store8:
    STOREADDR 1
    mov byte ptr [r14 + rax], cl
    sub r12, 16
    NEXT
h_store16:
    STOREADDR 2
    mov word ptr [r14 + rax], cx
    sub r12, 16
    NEXT

h_memory_size:
    mov rax, r15
    shr rax, 16
    mov [r12], rax
    add r12, 8
    NEXT

h_memory_grow:
    mov eax, [r12 - 8]
    push rsi
    mov rdi, [rbx + WI_mem]
    mov rsi, rax
    call wasm_mem_grow
    pop rsi
    mov eax, eax
    mov [r12 - 8], rax
    mov rax, [rbx + WI_mem]
    mov r14, [rax + WMEM_base]
    mov r15, [rax + WMEM_size]
    NEXT

# memory.copy: destination, source, length
h_memory_copy:
    mov eax, [r12 - 24]
    mov ecx, [r12 - 16]
    mov edx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rdx]
    cmp r8, r15
    ja wasm_trap_oob
    lea r8, [rcx + rdx]
    cmp r8, r15
    ja wasm_trap_oob
    push rsi
    lea rdi, [r14 + rax]
    lea rsi, [r14 + rcx]
    call memmove
    pop rsi
    NEXT

# memory.fill: destination, byte, length
h_memory_fill:
    mov eax, [r12 - 24]
    mov ecx, [r12 - 16]
    mov edx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rdx]
    cmp r8, r15
    ja wasm_trap_oob
    push rsi
    lea rdi, [r14 + rax]
    mov esi, ecx
    call memset
    pop rsi
    NEXT

# memory.init [WDA]: destination, offset in the segment, length
h_memory_init:
    mov rdi, [rsi]
    add rsi, 8
    mov eax, [r12 - 24]
    mov ecx, [r12 - 16]
    mov edx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rdx]
    cmp r8, r15
    ja wasm_trap_oob
    lea r8, [rcx + rdx]
    cmp r8, [rdi + WDA_len]
    ja wasm_trap_oob
    push rsi
    mov rsi, [rdi + WDA_ptr]
    add rsi, rcx
    lea rdi, [r14 + rax]
    call memmove
    pop rsi
    NEXT

# data.drop [WDA]
h_data_drop:
    mov rax, [rsi]
    add rsi, 8
    mov qword ptr [rax + WDA_len], 0
    NEXT

# ---------------------------------------------------------------- tables

# [WTB]: the index on top, the reference replaces it
h_table_get:
    mov rdx, [rsi]
    add rsi, 8
    mov eax, [r12 - 8]
    cmp rax, [rdx + WTB_size]
    jae wasm_trap_oob_table
    mov rcx, [rdx + WTB_elems]
    mov rax, [rcx + rax*8]
    mov [r12 - 8], rax
    NEXT

# [WTB]: the index, then the reference
h_table_set:
    mov rdx, [rsi]
    add rsi, 8
    mov eax, [r12 - 16]
    cmp rax, [rdx + WTB_size]
    jae wasm_trap_oob_table
    mov rcx, [rdx + WTB_elems]
    mov rdi, [r12 - 8]
    mov [rcx + rax*8], rdi
    sub r12, 16
    NEXT

h_table_size:
    mov rdx, [rsi]
    add rsi, 8
    mov rax, [rdx + WTB_size]
    mov [r12], rax
    add r12, 8
    NEXT

# [WTB]: the initial reference, then the count; the old size or -1
h_table_grow:
    push rsi
    mov rdi, [rsi]
    mov esi, [r12 - 8]
    mov rdx, [r12 - 16]
    call wasm_table_grow
    pop rsi
    add rsi, 8
    mov eax, eax
    sub r12, 8
    mov [r12 - 8], rax
    NEXT

# [WTB]: the index, the reference, the count
h_table_fill:
    mov rdx, [rsi]
    add rsi, 8
    mov eax, [r12 - 24]
    mov rdi, [r12 - 16]
    mov ecx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rcx]
    cmp r8, [rdx + WTB_size]
    ja wasm_trap_oob_table
    mov rdx, [rdx + WTB_elems]
    lea rdx, [rdx + rax*8]
1:  test rcx, rcx
    jz 2f
    mov [rdx], rdi
    add rdx, 8
    dec rcx
    jmp 1b
2:  NEXT

# [destination WTB][source WTB]: destination index, source index, count
h_table_copy:
    mov r9, [rsi]
    mov r10, [rsi + 8]
    add rsi, 16
    mov eax, [r12 - 24]
    mov ecx, [r12 - 16]
    mov edx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rdx]
    cmp r8, [r9 + WTB_size]
    ja wasm_trap_oob_table
    lea r8, [rcx + rdx]
    cmp r8, [r10 + WTB_size]
    ja wasm_trap_oob_table
    push rsi
    mov rdi, [r9 + WTB_elems]
    lea rdi, [rdi + rax*8]
    mov rsi, [r10 + WTB_elems]
    lea rsi, [rsi + rcx*8]
    shl rdx, 3
    call memmove
    pop rsi
    NEXT

# [WTB][WEL]: table index, segment index, count
h_table_init:
    mov r9, [rsi]
    mov r10, [rsi + 8]
    add rsi, 16
    mov eax, [r12 - 24]
    mov ecx, [r12 - 16]
    mov edx, [r12 - 8]
    sub r12, 24
    lea r8, [rax + rdx]
    cmp r8, [r9 + WTB_size]
    ja wasm_trap_oob_table
    lea r8, [rcx + rdx]
    cmp r8, [r10 + WEL_count]
    ja wasm_trap_oob_table
    push rsi
    mov rdi, [r9 + WTB_elems]
    lea rdi, [rdi + rax*8]
    mov rsi, [r10 + WEL_items]
    lea rsi, [rsi + rcx*8]
    shl rdx, 3
    call memmove
    pop rsi
    NEXT

# [WEL]
h_elem_drop:
    mov rax, [rsi]
    add rsi, 8
    mov qword ptr [rax + WEL_count], 0
    NEXT

.globl h_exit, h_call, h_call_indirect, h_return0, h_return1, h_return, h_unreachable
.globl h_br, h_br_drop, h_br_move1, h_br_moven, h_br_if, h_br_if_drop, h_br_if_move1
.globl h_br_if_moven, h_if, h_br_table, h_drop, h_select, h_const, h_local_get, h_local_set
.globl h_local_tee, h_global_get, h_global_set, h_ref_is_null, h_memory_size, h_memory_grow
.globl h_memory_copy, h_memory_fill, h_memory_init, h_data_drop, h_table_get, h_table_set
.globl h_table_size, h_table_grow, h_table_fill, h_table_copy, h_table_init, h_elem_drop
.globl h_i32_load, h_i64_load, h_i32_load8_s, h_i32_load8_u, h_i32_load16_s, h_i32_load16_u
.globl h_i64_load8_s, h_i64_load16_s, h_i64_load32_s, h_i32_store, h_i64_store, h_store8, h_store16

.section .rodata
.p2align 3
.Ltrap_texts:
    .quad .Lt_ok, .Lt_unreachable, .Lt_div0, .Lt_overflow, .Lt_conversion, .Lt_oob_memory
    .quad .Lt_oob_table, .Lt_undefined, .Lt_uninit, .Lt_signature, .Lt_exhausted, .Lt_exit, .Lt_host
.Lt_ok: .asciz "ok"
.Lt_unreachable: .asciz "unreachable"
.Lt_div0: .asciz "integer divide by zero"
.Lt_overflow: .asciz "integer overflow"
.Lt_conversion: .asciz "invalid conversion to integer"
.Lt_oob_memory: .asciz "out of bounds memory access"
.Lt_oob_table: .asciz "out of bounds table access"
.Lt_undefined: .asciz "undefined element"
.Lt_uninit: .asciz "uninitialized element"
.Lt_signature: .asciz "indirect call type mismatch"
.Lt_exhausted: .asciz "call stack exhausted"
.Lt_exit: .asciz "exit"
.Lt_host: .asciz "host function failed"
.Lt_unknown: .asciz "trap"
