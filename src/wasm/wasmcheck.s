# WebAssembly function bodies: validation (the spec's algorithm, appendix "Validation Algorithm")
# and compilation to threaded code in one pass. Code that validation proves unreachable is checked
# but not emitted. Branch targets are slot-relative offsets, so the code buffer may move while it
# grows; forward branches wait in a chain through their own slots until the label's end.
.include "rhun.inc"
.include "wasm/wasm.inc"

# a control frame
STRUCT
F CF_op, 4                          # 0 function, 2 block, 3 loop, 4 if, 5 else
F CF_unreach, 4
F CF_dead, 4                        # entered in unreachable code: nothing of it is emitted
F CF_pad, 4
F CF_height, 8                      # operand stack height at entry, parameters not counted
F CF_nparams, 8
F CF_params, 8
F CF_nresults, 8
F CF_results, 8
F CF_start, 8                       # a loop's first instruction (code offset)
F CF_fixups, 8                      # forward branch slots: offset + 1 of the last, 0 for none
F CF_elsefix, 8                     # an if's false branch slot: offset + 1, 0 for none
ENDSTRUCT CF_SIZE

.bss
.p2align 3
cs_vals: .quad 0                    # operand types
cs_vlen: .quad 0
cs_vcap: .quad 0
cs_vmax: .quad 0
cs_ctrls: .quad 0                   # control frames
cs_clen: .quad 0
cs_ccap: .quad 0
cs_ctop: .quad 0                    # the top frame
cs_locals: .quad 0                  # local types (parameters first)
cs_lcap: .quad 0
cs_nlocals: .quad 0
cs_fn: .quad 0
cs_tmp: .quad 0                     # br_table's popped types
cs_tcap: .quad 0
cs_on: .long 0                      # code is emitted (the current point is reachable)
cs_arity: .long 0

.text
# ---------------------------------------------------------------- emitting

# emit(value): appends a slot, unless the current point is unreachable
emit:
    cmp dword ptr [rip + cs_on], 0
    je 2f
emit_always:
    mov rax, [rbx + WI_codelen]
    lea rcx, [rax + 8]
    cmp rcx, [rbx + WI_codecap]
    jbe 1f
    push rdi
    push rax
    mov rsi, [rbx + WI_codecap]
    add rsi, rsi
    mov ecx, 4096
    cmp rsi, rcx
    cmovb rsi, rcx
    mov [rbx + WI_codecap], rsi
    mov rdi, [rbx + WI_code]
    call mem_realloc
    mov [rbx + WI_code], rax
    pop rax
    pop rdi
1:  mov rcx, [rbx + WI_code]
    mov [rcx + rax], rdi
    add rax, 8
    mov [rbx + WI_codelen], rax
2:  ret

# emit_rel(frame rcx): a branch's target slot. A loop's start is known; a block's end is not yet:
# the slot joins the frame's chain.
emit_rel:
    cmp dword ptr [rcx + CF_op], 3
    jne 1f
    mov rdi, [rcx + CF_start]
    sub rdi, [rbx + WI_codelen]
    jmp emit_always
1:  mov rdi, [rcx + CF_fixups]
    mov rax, [rbx + WI_codelen]
    inc rax
    mov [rcx + CF_fixups], rax
    jmp emit_always

# patch(chain head rdi): every slot of the chain branches to the current end of the code
patch:
    mov rdx, [rbx + WI_code]
1:  test rdi, rdi
    jz 2f
    dec rdi
    mov rax, [rdx + rdi]
    mov rcx, [rbx + WI_codelen]
    sub rcx, rdi
    mov [rdx + rdi], rcx
    mov rdi, rax
    jmp 1b
2:  ret

# ---------------------------------------------------------------- the operand and control stacks

# vpush(type edi)
vpush:
    mov rax, [rip + cs_vlen]
    cmp rax, [rip + cs_vcap]
    jb 1f
    push rdi
    push rax
    mov rsi, [rip + cs_vcap]
    add rsi, rsi
    mov ecx, 1024
    cmp rsi, rcx
    cmovb rsi, rcx
    mov [rip + cs_vcap], rsi
    mov rdi, [rip + cs_vals]
    call mem_realloc
    mov [rip + cs_vals], rax
    pop rax
    pop rdi
1:  mov rcx, [rip + cs_vals]
    mov [rcx + rax], dil
    inc rax
    mov [rip + cs_vlen], rax
    cmp rax, [rip + cs_vmax]
    jbe 2f
    mov [rip + cs_vmax], rax
2:  ret

# vpop -> eax the type on top (WV_UNKNOWN from the polymorphic stack of unreachable code)
vpop:
    mov rcx, [rip + cs_ctop]
    mov rax, [rip + cs_vlen]
    cmp rax, [rcx + CF_height]
    jne 1f
    cmp dword ptr [rcx + CF_unreach], 0
    je fail_mismatch
    xor eax, eax
    ret
1:  dec rax
    mov [rip + cs_vlen], rax
    mov rcx, [rip + cs_vals]
    movzx eax, byte ptr [rcx + rax]
    ret

# vpop_expect(type edi) -> eax the type popped (WV_UNKNOWN stays unknown)
vpop_expect:
    call vpop
    cmp eax, edi
    je 1f
    test eax, eax
    jz 1f
    test edi, edi
    jz 1f
    jmp fail_mismatch
1:  ret

# vpop_types(ptr rsi, n rdx): pops them, the last first
vpop_types:
    push r14
    push r15
    mov r14, rsi
    mov r15, rdx
1:  test r15, r15
    jz 2f
    dec r15
    movzx edi, byte ptr [r14 + r15]
    call vpop_expect
    jmp 1b
2:  pop r15
    pop r14
    ret

# vpush_types(ptr rsi, n rdx)
vpush_types:
    push r14
    push r15
    mov r14, rsi
    mov r15, rdx
1:  test r15, r15
    jz 2f
    movzx edi, byte ptr [r14]
    call vpush
    inc r14
    dec r15
    jmp 1b
2:  pop r15
    pop r14
    ret

# cpush(op edi, params rsi, nparams rdx, results rcx, nresults r8): a new frame; the parameters
# were popped by the caller and are pushed again here
cpush:
    push r14
    push r15
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    mov rax, [rip + cs_clen]
    cmp rax, [rip + cs_ccap]
    jb 1f
    mov rsi, [rip + cs_ccap]
    add rsi, rsi
    mov ecx, 64
    cmp rsi, rcx
    cmovb rsi, rcx
    mov [rip + cs_ccap], rsi
    imul rsi, rsi, CF_SIZE
    mov rdi, [rip + cs_ctrls]
    call mem_realloc
    mov [rip + cs_ctrls], rax
1:  mov rax, [rip + cs_clen]
    imul r14, rax, CF_SIZE
    add r14, [rip + cs_ctrls]
    inc rax
    mov [rip + cs_clen], rax
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    mov [r14 + CF_op], edi
    mov dword ptr [r14 + CF_unreach], 0
    xor eax, eax
    cmp dword ptr [rip + cs_on], 0
    sete al
    mov [r14 + CF_dead], eax
    mov rax, [rip + cs_vlen]
    mov [r14 + CF_height], rax
    mov [r14 + CF_params], rsi
    mov [r14 + CF_nparams], rdx
    mov [r14 + CF_results], rcx
    mov [r14 + CF_nresults], r8
    mov rax, [rbx + WI_codelen]
    mov [r14 + CF_start], rax
    mov qword ptr [r14 + CF_fixups], 0
    mov qword ptr [r14 + CF_elsefix], 0
    mov [rip + cs_ctop], r14
    call vpush_types
    pop r15
    pop r14
    ret

# cpop -> rax the frame popped (valid until the next cpush): its results checked, the stack at
# its height
cpop:
    push r14
    mov r14, [rip + cs_ctop]
    mov rsi, [r14 + CF_results]
    mov rdx, [r14 + CF_nresults]
    call vpop_types
    mov rax, [rip + cs_vlen]
    cmp rax, [r14 + CF_height]
    jne fail_mismatch
    mov rax, [rip + cs_clen]
    dec rax
    mov [rip + cs_clen], rax
    xor ecx, ecx
    test rax, rax
    jz 1f
    dec rax
    imul rcx, rax, CF_SIZE
    add rcx, [rip + cs_ctrls]
1:  mov [rip + cs_ctop], rcx
    mov rax, r14
    pop r14
    ret

# unreachable(): the rest of the frame is unreachable
set_unreachable:
    mov rcx, [rip + cs_ctop]
    mov rax, [rcx + CF_height]
    mov [rip + cs_vlen], rax
    mov dword ptr [rcx + CF_unreach], 1
    mov dword ptr [rip + cs_on], 0
    ret

# refresh(): code is emitted when the top frame is reachable and was entered so
refresh:
    xor eax, eax
    mov rcx, [rip + cs_ctop]
    test rcx, rcx
    jz 1f
    mov edx, [rcx + CF_unreach]
    or edx, [rcx + CF_dead]
    sete al
1:  mov [rip + cs_on], eax
    ret

# label(depth edi) -> rcx the frame, rsi its label's types, rdx their count
label:
    mov eax, edi
    cmp rax, [rip + cs_clen]
    jae fail_label
    mov rcx, [rip + cs_clen]
    dec rcx
    sub rcx, rax
    imul rcx, rcx, CF_SIZE
    add rcx, [rip + cs_ctrls]
    cmp dword ptr [rcx + CF_op], 3
    je 1f
    mov rsi, [rcx + CF_results]
    mov rdx, [rcx + CF_nresults]
    ret
1:  mov rsi, [rcx + CF_params]
    mov rdx, [rcx + CF_nparams]
    ret

# blocktype -> rsi params, rdx nparams, rcx results, r8 nresults
blocktype:
    cmp r12, r13
    jae wasm_fail_eof
    movzx eax, byte ptr [r12]
    cmp eax, 0x40
    jne 1f
    inc r12
    xor edx, edx
    xor r8d, r8d
    lea rsi, [rip + vt_bytes]
    mov rcx, rsi
    ret
1:  lea rcx, [rip + vt_bytes]
    xor edx, edx
2:  cmp byte ptr [rcx + rdx], 0
    je 3f
    cmp [rcx + rdx], al
    je 4f
    inc edx
    jmp 2b
4:  inc r12
    add rcx, rdx
    mov r8d, 1
    xor edx, edx
    mov rsi, rcx
    ret
3:  cmp eax, WV_V128
    je fail_simd
    call wasm_s33
    test rax, rax
    js fail_type
    cmp rax, [rbx + WI_ntypes]
    jae fail_type
    mov rcx, [rbx + WI_types]
    mov edi, [rcx + rax*4]
    call wasm_type
    mov edx, [rax + WTY_nparams]
    mov r8d, [rax + WTY_nresults]
    mov rsi, [rax + WTY_types]
    lea rcx, [rsi + rdx]
    ret

# ---------------------------------------------------------------- branches

# br_slots(frame rcx, arity edx): emits a branch's operands for handler family rdi (the plain,
# drop, move1 and moven handlers follow each other in the family's table); the height drops from
# the current one to the frame's plus the arity
br_emit:
    push r14
    push r15
    mov r14, rcx
    mov r15d, edx
    mov rax, [rip + cs_vlen]
    sub rax, [r14 + CF_height]
    sub rax, r15
    shl rax, 3                      # bytes to drop
    mov [rip + br_drop_bytes], rax
    mov r8, rdi
    test rax, rax
    jnz 1f
    mov rdi, [r8]
    call emit_always
    mov rcx, r14
    call emit_rel
    jmp 9f
1:  test r15, r15
    jnz 2f
    mov rdi, [r8 + 8]
    jmp 3f
2:  cmp r15, 1
    jne 4f
    mov rdi, [r8 + 16]
3:  call emit_always
    mov rcx, r14
    call emit_rel
    mov rdi, [rip + br_drop_bytes]
    call emit_always
    jmp 9f
4:  mov rdi, [r8 + 24]
    call emit_always
    mov rcx, r14
    call emit_rel
    mov rdi, r15
    call emit_always
    mov rdi, [rip + br_drop_bytes]
    call emit_always
9:  pop r15
    pop r14
    ret

# return_emit(): the function's results go back to the caller
return_emit:
    mov rax, [rip + cs_fn]
    mov eax, [rax + WFN_nresults]
    cmp eax, 1
    ja 2f
    je 1f
    lea rdi, [rip + h_return0]
    jmp emit
1:  lea rdi, [rip + h_return1]
    jmp emit
2:  push rax
    lea rdi, [rip + h_return]
    call emit
    pop rdi
    jmp emit

# ---------------------------------------------------------------- compiling a function

# wasm_compile(instance, defined function index): validates the body and appends its code;
# the function's WFN_code holds the code's offset until wasm_load turns it into an address
FN wasm_compile
    PROLOGUE 32
    mov rbx, rdi
    mov rax, rsi
    shl rax, 4
    add rax, [rbx + WI_bodies]
    mov r12, [rax + WBO_start]
    mov r13, [rax + WBO_end]
    imul r15, rsi, WFN_SIZE
    add r15, [rbx + WI_fnmem]
    mov [rip + cs_fn], r15
    mov rax, [rbx + WI_codelen]
    mov [r15 + WFN_code], rax
    # locals: the parameters, then the declared ones
    mov edi, [r15 + WFN_type]
    call wasm_type
    mov r14, rax
    mov ecx, [r14 + WTY_nparams]
    mov [rip + cs_nlocals], rcx
    mov rdi, rcx
    call locals_room
    mov rdi, [rip + cs_locals]
    mov rsi, [r14 + WTY_types]
    mov edx, [r14 + WTY_nparams]
    call memcpy
    call wasm_u32
    mov [rsp], eax                  # local declarations
    xor ecx, ecx
    mov [rsp + 8], rcx
1:  mov ecx, [rsp + 8]
    cmp ecx, [rsp]
    jae 3f
    call wasm_u32
    mov eax, eax
    mov rcx, [rip + cs_nlocals]
    add rcx, rax
    cmp rcx, WASM_MAX_LOCALS
    ja fail_locals
    mov [rsp + 16], rax
    mov rdi, rcx
    call locals_room
    call wasm_valtype
    mov rdi, [rip + cs_locals]
    add rdi, [rip + cs_nlocals]
    mov esi, eax
    mov rdx, [rsp + 16]
    add [rip + cs_nlocals], rdx
    call memset
    inc dword ptr [rsp + 8]
    jmp 1b
3:  mov rax, [rip + cs_nlocals]
    mov ecx, [r14 + WTY_nparams]
    sub rax, rcx
    mov [r15 + WFN_nlocals], eax
    # the function's frame: its label is the function's results
    mov qword ptr [rip + cs_vlen], 0
    mov qword ptr [rip + cs_vmax], 0
    mov qword ptr [rip + cs_clen], 0
    mov dword ptr [rip + cs_on], 1
    xor edi, edi
    xor esi, esi
    xor edx, edx
    mov rcx, [r14 + WTY_types]
    mov eax, [r14 + WTY_nparams]
    add rcx, rax
    mov r8d, [r14 + WTY_nresults]
    call cpush
.Lop:
    cmp qword ptr [rip + cs_clen], 0
    je .Lbody_done
    call wasm_byte
    lea rcx, [rip + .Lop_table]
    jmp [rcx + rax*8]
.Lbody_done:
    cmp r12, r13
    jne fail_end
    mov r15, [rip + cs_fn]
    # what the body needs above its parameters: its locals and deepest operands, plus a slot
    mov rax, [rip + cs_vmax]
    mov ecx, [r15 + WFN_nlocals]
    add rax, rcx
    lea rax, [rax*8 + 16]
    mov [r15 + WFN_need], rax
    EPILOGUE

# locals_room(count): the local types array holds count
locals_room:
    cmp rdi, [rip + cs_lcap]
    jbe 1f
    lea rsi, [rdi + 64]
    mov [rip + cs_lcap], rsi
    mov rdi, [rip + cs_locals]
    call mem_realloc
    mov [rip + cs_locals], rax
1:  ret

# ---------------------------------------------------------------- opcodes

op_illegal:
    lea rdi, [rip + .Lm_illegal]
    jmp wasm_fail

op_unreachable:
    lea rdi, [rip + h_unreachable]
    call emit
    call set_unreachable
    jmp .Lop

op_nop:
    jmp .Lop

op_block:
    mov edi, 2
    jmp .Lblock_common
op_loop:
    mov edi, 3
.Lblock_common:
    push rdi
    call blocktype
    push rsi
    push rdx
    push rcx
    push r8
    call vpop_types
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    call cpush
    jmp .Lop

op_if:
    call blocktype
    push rsi
    push rdx
    push rcx
    push r8
    mov edi, WV_I32
    call vpop_expect
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 16]
    call vpop_types
    pop r8
    pop rcx
    pop rdx
    pop rsi
    mov edi, 4
    call cpush
    # the false branch's jump, when the if is reached
    cmp dword ptr [rip + cs_on], 0
    je .Lop
    lea rdi, [rip + h_if]
    call emit_always
    mov rax, [rbx + WI_codelen]
    inc rax
    mov rcx, [rip + cs_ctop]
    mov [rcx + CF_elsefix], rax
    xor edi, edi
    call emit_always
    jmp .Lop

op_else:
    mov rcx, [rip + cs_ctop]
    cmp dword ptr [rcx + CF_op], 4
    jne fail_else
    # the true branch ends: its results checked, then a jump over the false branch
    cmp dword ptr [rip + cs_on], 0
    je 1f
    lea rdi, [rip + h_br]
    call emit_always
    mov rcx, [rip + cs_ctop]
    call emit_rel
1:  call cpop
    mov r14, rax                    # the frame stays where it was: push it back as an else
    inc qword ptr [rip + cs_clen]
    mov [rip + cs_ctop], r14
    mov dword ptr [r14 + CF_op], 5
    mov dword ptr [r14 + CF_unreach], 0
    mov rdi, [r14 + CF_elsefix]
    mov qword ptr [r14 + CF_elsefix], 0
    test rdi, rdi
    jz 2f
    call patch
2:  mov rsi, [r14 + CF_params]
    mov rdx, [r14 + CF_nparams]
    call vpush_types
    call refresh
    jmp .Lop

op_end:
    mov r14, [rip + cs_ctop]
    cmp dword ptr [r14 + CF_op], 4
    jne 1f
    # an if without else passes its parameters through: they must be its results
    mov rax, [r14 + CF_nparams]
    cmp rax, [r14 + CF_nresults]
    jne fail_mismatch
    mov rdi, [r14 + CF_params]
    mov rsi, [r14 + CF_results]
    mov rdx, rax
    call memeq
    test eax, eax
    jz fail_mismatch
1:  cmp qword ptr [rip + cs_clen], 1
    je .Lend_function
    call cpop
    mov r14, rax
    mov rdi, [r14 + CF_elsefix]
    call patch
    mov rdi, [r14 + CF_fixups]
    cmp dword ptr [r14 + CF_op], 3
    je 2f
    call patch
2:  mov rsi, [r14 + CF_results]
    mov rdx, [r14 + CF_nresults]
    call vpush_types
    call refresh
    jmp .Lop
.Lend_function:
    # the final end: a return, which branches to the function's label reach as well
    mov eax, [rip + cs_on]
    or rax, [r14 + CF_fixups]
    push r14
    push rax
    call cpop
    pop rax
    pop r14
    test rax, rax
    jz 3f
    mov rdi, [r14 + CF_fixups]
    call patch
    mov dword ptr [rip + cs_on], 1
    call return_emit
3:  mov dword ptr [rip + cs_on], 0
    jmp .Lop

op_br:
    call wasm_u32
    mov edi, eax
    call label
    push rsi
    push rdx
    cmp dword ptr [rip + cs_on], 0
    je 2f
    cmp dword ptr [rcx + CF_op], 0
    jne 1f
    call return_emit
    jmp 2f
1:  lea rdi, [rip + br_family]
    call br_emit
2:  pop rdx
    pop rsi
    call vpop_types
    call set_unreachable
    jmp .Lop

op_br_if:
    call wasm_u32
    push rax
    push rax
    mov edi, WV_I32
    call vpop_expect
    pop rdi
    pop rdi
    call label
    push rsi
    push rdx
    cmp dword ptr [rip + cs_on], 0
    je 1f
    lea rdi, [rip + br_if_family]
    call br_emit
1:  mov rsi, [rsp + 8]
    mov rdx, [rsp]
    call vpop_types
    pop rdx
    pop rsi
    call vpush_types
    jmp .Lop

op_br_table:
    mov edi, 1
    call wasm_count
    mov r14d, eax                   # labels before the default
    mov edi, WV_I32
    call vpop_expect
    lea rdi, [rip + h_br_table]
    call emit
    mov rdi, r14
    call emit
    # the default's arity is every label's: read ahead to it
    push r12
    push r12
    mov r15d, r14d
1:  test r15d, r15d
    jz 2f
    call wasm_u32
    dec r15d
    jmp 1b
2:  call wasm_u32
    mov edi, eax
    call label
    mov [rip + cs_arity], edx
    pop r12
    pop r12
    xor r15d, r15d
3:  call wasm_u32
    mov edi, eax
    call label
    call .Lbt_entry
    inc r15d
    cmp r15d, r14d
    jbe 3b
    call set_unreachable
    jmp .Lop
# one label (frame rcx, types rsi, count rdx): its arity, its types popped and pushed back as
# they were, then its slots: the target, the arity, the bytes to drop
.Lbt_entry:
    cmp edx, [rip + cs_arity]
    jne fail_arity
    push rcx
    push rdx
    push rsi
    push rdx
    mov rdi, rdx
    call tmp_room
    pop rdx
    pop rsi
    push r14
    push r15
    mov r14, rsi
    mov r15, rdx
4:  test r15, r15
    jz 5f
    dec r15
    movzx edi, byte ptr [r14 + r15]
    call vpop_expect
    mov rcx, [rip + cs_tmp]
    mov [rcx + r15], al
    jmp 4b
5:  mov rsi, [rip + cs_tmp]
    mov rdx, [rsp + 16]
    call vpush_types
    pop r15
    pop r14
    pop rdx
    pop rcx
    cmp dword ptr [rip + cs_on], 0
    je 7f
    push rcx
    push rdx
    call emit_rel
    mov rdi, [rsp]
    call emit_always
    pop rdx
    pop rcx
    mov rax, [rip + cs_vlen]
    sub rax, [rcx + CF_height]
    sub rax, rdx
    lea rdi, [rax*8]
    call emit_always
7:  ret

# tmp_room(n)
tmp_room:
    cmp rdi, [rip + cs_tcap]
    jbe 1f
    lea rsi, [rdi + 64]
    mov [rip + cs_tcap], rsi
    mov rdi, [rip + cs_tmp]
    call mem_realloc
    mov [rip + cs_tmp], rax
1:  ret

op_return:
    mov rax, [rip + cs_fn]
    mov edi, [rax + WFN_type]
    call wasm_type
    mov rsi, [rax + WTY_types]
    mov ecx, [rax + WTY_nparams]
    add rsi, rcx
    mov edx, [rax + WTY_nresults]
    call vpop_types
    call return_emit
    call set_unreachable
    jmp .Lop

op_call:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nfuncs]
    jae fail_func
    mov rcx, [rbx + WI_funcs]
    mov r14, [rcx + rax*8]
    mov edi, [r14 + WFN_type]
    call call_types
    lea rdi, [rip + h_call]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

# call_types(type id edi): pops the parameters, pushes the results
call_types:
    call wasm_type
    push rax
    push rax
    mov rsi, [rax + WTY_types]
    mov edx, [rax + WTY_nparams]
    call vpop_types
    pop rax
    pop rax
    mov rsi, [rax + WTY_types]
    mov ecx, [rax + WTY_nparams]
    add rsi, rcx
    mov edx, [rax + WTY_nresults]
    jmp vpush_types

op_call_indirect:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_ntypes]
    jae fail_type
    mov rcx, [rbx + WI_types]
    mov r14d, [rcx + rax*4]         # type id
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_ntables]
    jae fail_table
    mov rcx, [rbx + WI_tables]
    mov r15, [rcx + rax*8]
    cmp qword ptr [r15 + WTB_type], WV_FUNCREF
    jne fail_mismatch
    mov edi, WV_I32
    call vpop_expect
    mov edi, r14d
    call call_types
    lea rdi, [rip + h_call_indirect]
    call emit
    mov rdi, r15
    call emit
    mov rdi, r14
    call emit
    mov r15, [rip + cs_fn]
    jmp .Lop

op_drop:
    call vpop
    lea rdi, [rip + h_drop]
    call emit
    jmp .Lop

op_select:
    mov edi, WV_I32
    call vpop_expect
    call vpop
    mov r14d, eax
    call vpop
    # numeric (or unknown) operands of one type
    cmp eax, WV_FUNCREF
    je fail_mismatch
    cmp eax, WV_EXTERNREF
    je fail_mismatch
    cmp r14d, WV_FUNCREF
    je fail_mismatch
    cmp r14d, WV_EXTERNREF
    je fail_mismatch
    test eax, eax
    jz 1f
    test r14d, r14d
    jz 2f
    cmp eax, r14d
    jne fail_mismatch
2:  mov edi, eax
    jmp 3f
1:  mov edi, r14d
3:  call vpush
    lea rdi, [rip + h_select]
    call emit
    jmp .Lop

op_select_t:
    call wasm_u32
    cmp eax, 1
    jne fail_arity
    call wasm_valtype
    mov r14d, eax
    mov edi, WV_I32
    call vpop_expect
    mov edi, r14d
    call vpop_expect
    mov edi, r14d
    call vpop_expect
    mov edi, r14d
    call vpush
    lea rdi, [rip + h_select]
    call emit
    jmp .Lop

# local_index -> rax the index (checked), ecx its type
local_index:
    call wasm_u32
    mov eax, eax
    cmp rax, [rip + cs_nlocals]
    jae fail_local
    mov rcx, [rip + cs_locals]
    movzx ecx, byte ptr [rcx + rax]
    ret

op_local_get:
    call local_index
    push rax
    mov edi, ecx
    call vpush
    lea rdi, [rip + h_local_get]
    call emit
    pop rdi
    shl rdi, 3
    call emit
    jmp .Lop

op_local_set:
    call local_index
    push rax
    mov edi, ecx
    call vpop_expect
    lea rdi, [rip + h_local_set]
    call emit
    pop rdi
    shl rdi, 3
    call emit
    jmp .Lop

op_local_tee:
    call local_index
    push rax
    push rcx
    mov edi, ecx
    call vpop_expect
    pop rdi
    call vpush
    lea rdi, [rip + h_local_tee]
    call emit
    pop rdi
    shl rdi, 3
    call emit
    jmp .Lop

# global_index -> rax the WGL (checked)
global_index:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nglobals]
    jae fail_global
    mov rcx, [rbx + WI_globals]
    mov rax, [rcx + rax*8]
    ret

op_global_get:
    call global_index
    push rax
    movzx edi, byte ptr [rax + WGL_type]
    call vpush
    lea rdi, [rip + h_global_get]
    call emit
    pop rdi
    call emit
    jmp .Lop

op_global_set:
    call global_index
    cmp byte ptr [rax + WGL_mut], 0
    je fail_immutable
    push rax
    movzx edi, byte ptr [rax + WGL_type]
    call vpop_expect
    lea rdi, [rip + h_global_set]
    call emit
    pop rdi
    call emit
    jmp .Lop

# table_index -> rax the WTB (checked)
table_index:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_ntables]
    jae fail_table
    mov rcx, [rbx + WI_tables]
    mov rax, [rcx + rax*8]
    ret

op_table_get:
    call table_index
    mov r14, rax
    mov edi, WV_I32
    call vpop_expect
    mov rdi, [r14 + WTB_type]
    call vpush
    lea rdi, [rip + h_table_get]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

op_table_set:
    call table_index
    mov r14, rax
    mov rdi, [r14 + WTB_type]
    call vpop_expect
    mov edi, WV_I32
    call vpop_expect
    lea rdi, [rip + h_table_set]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

# the memory instructions 0x28-0x3e: memarg, then types and handler from mem_ops
op_memory:
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    sub eax, 0x28
    lea r14, [rip + mem_ops]
    shl rax, 4
    add r14, rax                    # handler, value type, natural alignment, store flag
    call wasm_u32
    movzx ecx, byte ptr [r14 + 9]
    cmp eax, ecx
    ja fail_align
    call wasm_u32
    mov r15d, eax                   # offset
    movzx edi, byte ptr [r14 + 8]
    cmp byte ptr [r14 + 10], 0
    jne 1f
    mov edi, WV_I32
    call vpop_expect
    movzx edi, byte ptr [r14 + 8]
    call vpush
    jmp 2f
1:  call vpop_expect
    mov edi, WV_I32
    call vpop_expect
2:  mov rdi, [r14]
    call emit
    mov rdi, r15
    call emit
    mov r15, [rip + cs_fn]
    jmp .Lop

op_memory_size:
    call wasm_byte
    test eax, eax
    jnz fail_zero
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    mov edi, WV_I32
    call vpush
    lea rdi, [rip + h_memory_size]
    call emit
    jmp .Lop

op_memory_grow:
    call wasm_byte
    test eax, eax
    jnz fail_zero
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    mov edi, WV_I32
    call vpop_expect
    mov edi, WV_I32
    call vpush
    lea rdi, [rip + h_memory_grow]
    call emit
    jmp .Lop

op_i32_const:
    call wasm_s32
    mov r14d, eax
    mov edi, WV_I32
    jmp .Lconst
op_i64_const:
    call wasm_s64
    mov r14, rax
    mov edi, WV_I64
    jmp .Lconst
op_f32_const:
    mov edi, 4
    call wasm_bytes
    mov r14d, [rax]
    mov edi, WV_F32
    jmp .Lconst
op_f64_const:
    mov edi, 8
    call wasm_bytes
    mov r14, [rax]
    mov edi, WV_F64
.Lconst:
    call vpush
    lea rdi, [rip + h_const]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

# the numeric instructions 0x45-0xc4: operand and result types and handler from num_types and
# num_handlers; a missing handler is a no-op (reinterpretations, i64.extend_i32_u)
op_numeric:
    sub eax, 0x45
    mov r14d, eax
.Lnumeric:
    lea rcx, [rip + num_types]
    movzx edi, byte ptr [rcx + r14*4 + 1]
    test edi, edi
    jz 1f
    call vpop_expect
1:  lea rcx, [rip + num_types]
    movzx edi, byte ptr [rcx + r14*4]
    call vpop_expect
    lea rcx, [rip + num_types]
    movzx edi, byte ptr [rcx + r14*4 + 2]
    call vpush
    lea rcx, [rip + num_handlers]
    mov rdi, [rcx + r14*8]
    test rdi, rdi
    jz .Lop
    call emit
    jmp .Lop

op_ref_null:
    call wasm_reftype
    mov edi, eax
    call vpush
    lea rdi, [rip + h_const]
    call emit
    xor edi, edi
    call emit
    jmp .Lop

op_ref_is_null:
    call vpop
    test eax, eax
    jz 1f
    cmp eax, WV_FUNCREF
    je 1f
    cmp eax, WV_EXTERNREF
    jne fail_mismatch
1:  mov edi, WV_I32
    call vpush
    lea rdi, [rip + h_ref_is_null]
    call emit
    jmp .Lop

op_ref_func:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nfuncs]
    jae fail_func
    mov rcx, [rbx + WI_refs]
    test rcx, rcx
    jz fail_undeclared
    cmp byte ptr [rcx + rax], 0
    je fail_undeclared
    mov rcx, [rbx + WI_funcs]
    mov r14, [rcx + rax*8]
    mov edi, WV_FUNCREF
    call vpush
    lea rdi, [rip + h_const]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

op_prefix_fc:
    call wasm_u32
    cmp eax, 7
    jbe .Lsat
    cmp eax, 17
    ja op_illegal
    lea rcx, [rip + .Lfc_table]
    jmp [rcx + rax*8 - 64]
.Lsat:
    # the saturating truncations take the table's slots after 0xc4
    lea r14d, [rax + 0xc5 - 0x45]
    jmp .Lnumeric

# data_index -> rax the WDA (needs the data count section)
data_index:
    call wasm_u32
    mov eax, eax
    mov rcx, [rbx + WI_datacount]
    test rcx, rcx
    js fail_datacount
    cmp rax, rcx
    jae fail_data
    imul rax, rax, WDA_SIZE
    add rax, [rbx + WI_datas]
    ret

# elem_index -> rax the WEL
elem_index:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nelems]
    jae fail_elem
    imul rax, rax, WEL_SIZE
    add rax, [rbx + WI_elems]
    ret

# pop3_i32(): three i32 operands
pop3_i32:
    mov edi, WV_I32
    call vpop_expect
    mov edi, WV_I32
    call vpop_expect
    mov edi, WV_I32
    jmp vpop_expect

fc_memory_init:
    call data_index
    mov r14, rax
    call wasm_byte
    test eax, eax
    jnz fail_zero
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    call pop3_i32
    lea rdi, [rip + h_memory_init]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

fc_data_drop:
    call data_index
    mov r14, rax
    lea rdi, [rip + h_data_drop]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

fc_memory_copy:
    call wasm_byte
    test eax, eax
    jnz fail_zero
    call wasm_byte
    test eax, eax
    jnz fail_zero
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    call pop3_i32
    lea rdi, [rip + h_memory_copy]
    call emit
    jmp .Lop

fc_memory_fill:
    call wasm_byte
    test eax, eax
    jnz fail_zero
    cmp qword ptr [rbx + WI_nmems], 0
    je fail_memory
    call pop3_i32
    lea rdi, [rip + h_memory_fill]
    call emit
    jmp .Lop

fc_table_init:
    call elem_index
    mov r14, rax
    call table_index
    mov r15, rax
    mov rax, [r14 + WEL_type]
    cmp rax, [r15 + WTB_type]
    jne fail_mismatch
    call pop3_i32
    lea rdi, [rip + h_table_init]
    call emit
    mov rdi, r15
    call emit
    mov rdi, r14
    call emit
    mov r15, [rip + cs_fn]
    jmp .Lop

fc_elem_drop:
    call elem_index
    mov r14, rax
    lea rdi, [rip + h_elem_drop]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

fc_table_copy:
    call table_index
    mov r14, rax                    # destination
    call table_index
    mov r15, rax                    # source
    mov rax, [r14 + WTB_type]
    cmp rax, [r15 + WTB_type]
    jne fail_mismatch
    call pop3_i32
    lea rdi, [rip + h_table_copy]
    call emit
    mov rdi, r14
    call emit
    mov rdi, r15
    call emit
    mov r15, [rip + cs_fn]
    jmp .Lop

fc_table_grow:
    call table_index
    mov r14, rax
    mov edi, WV_I32
    call vpop_expect
    mov rdi, [r14 + WTB_type]
    call vpop_expect
    mov edi, WV_I32
    call vpush
    lea rdi, [rip + h_table_grow]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

fc_table_size:
    call table_index
    mov r14, rax
    mov edi, WV_I32
    call vpush
    lea rdi, [rip + h_table_size]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

fc_table_fill:
    call table_index
    mov r14, rax
    mov edi, WV_I32
    call vpop_expect
    mov rdi, [r14 + WTB_type]
    call vpop_expect
    mov edi, WV_I32
    call vpop_expect
    lea rdi, [rip + h_table_fill]
    call emit
    mov rdi, r14
    call emit
    jmp .Lop

# ---------------------------------------------------------------- failures

fail_mismatch:
    lea rdi, [rip + wasm_m_type_mismatch]
    jmp wasm_fail
fail_label:
    lea rdi, [rip + .Lm_label]
    jmp wasm_fail
fail_type:
    lea rdi, [rip + .Lm_type]
    jmp wasm_fail
fail_simd:
    lea rdi, [rip + .Lm_simd]
    jmp wasm_fail
fail_locals:
    lea rdi, [rip + .Lm_locals]
    jmp wasm_fail
fail_end:
    lea rdi, [rip + .Lm_end]
    jmp wasm_fail
fail_else:
    lea rdi, [rip + .Lm_else]
    jmp wasm_fail
fail_arity:
    lea rdi, [rip + .Lm_arity]
    jmp wasm_fail
fail_func:
    lea rdi, [rip + .Lm_func]
    jmp wasm_fail
fail_table:
    lea rdi, [rip + .Lm_table]
    jmp wasm_fail
fail_local:
    lea rdi, [rip + .Lm_local]
    jmp wasm_fail
fail_global:
    lea rdi, [rip + .Lm_global]
    jmp wasm_fail
fail_immutable:
    lea rdi, [rip + .Lm_immutable]
    jmp wasm_fail
fail_memory:
    lea rdi, [rip + .Lm_memory]
    jmp wasm_fail
fail_align:
    lea rdi, [rip + .Lm_align]
    jmp wasm_fail
fail_zero:
    lea rdi, [rip + .Lm_zero]
    jmp wasm_fail
fail_undeclared:
    lea rdi, [rip + .Lm_undeclared]
    jmp wasm_fail
fail_datacount:
    lea rdi, [rip + .Lm_datacount]
    jmp wasm_fail
fail_data:
    lea rdi, [rip + .Lm_data]
    jmp wasm_fail
fail_elem:
    lea rdi, [rip + .Lm_elem]
    jmp wasm_fail

.bss
.p2align 3
br_drop_bytes: .quad 0

.section .rodata
.p2align 3
# branch handler families: plain, drop, move one value, move n values
br_family: .quad h_br, h_br_drop, h_br_move1, h_br_moven
br_if_family: .quad h_br_if, h_br_if_drop, h_br_if_move1, h_br_if_moven
# value type bytes, for block types of one result (0 ends the list)
vt_bytes: .byte WV_I32, WV_I64, WV_F32, WV_F64, WV_FUNCREF, WV_EXTERNREF, 0, 0

.p2align 3
.Lop_table:
    .quad op_unreachable, op_nop, op_block, op_loop
    .quad op_if, op_else, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_end
    .quad op_br, op_br_if, op_br_table, op_return
    .quad op_call, op_call_indirect, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_drop, op_select
    .quad op_select_t, op_illegal, op_illegal, op_illegal
    .quad op_local_get, op_local_set, op_local_tee, op_global_get
    .quad op_global_set, op_table_get, op_table_set, op_illegal
    .quad op_memory, op_memory, op_memory, op_memory
    .quad op_memory, op_memory, op_memory, op_memory
    .quad op_memory, op_memory, op_memory, op_memory
    .quad op_memory, op_memory, op_memory, op_memory
    .quad op_memory, op_memory, op_memory, op_memory
    .quad op_memory, op_memory, op_memory, op_memory_size
    .quad op_memory_grow, op_i32_const, op_i64_const, op_f32_const
    .quad op_f64_const, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_numeric, op_numeric, op_numeric
    .quad op_numeric, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_ref_null, op_ref_is_null, op_ref_func, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_illegal, op_illegal, op_illegal, op_illegal
    .quad op_prefix_fc, op_illegal, op_illegal, op_illegal

.p2align 3
.Lfc_table:
    .quad fc_memory_init, fc_data_drop, fc_memory_copy, fc_memory_fill, fc_table_init
    .quad fc_elem_drop, fc_table_copy, fc_table_grow, fc_table_size, fc_table_fill

.Lm_illegal: .asciz "illegal opcode"
.Lm_label: .asciz "unknown label"
.Lm_type: .asciz "unknown type"
.Lm_simd: .asciz "SIMD is not supported"
.Lm_locals: .asciz "too many locals"
.Lm_end: .asciz "END opcode expected"
.Lm_else: .asciz "else without if"
.Lm_arity: .asciz "type mismatch (arity)"
.Lm_func: .asciz "unknown function"
.Lm_table: .asciz "unknown table"
.Lm_local: .asciz "unknown local"
.Lm_global: .asciz "unknown global"
.Lm_immutable: .asciz "global is immutable"
.Lm_memory: .asciz "unknown memory"
.Lm_align: .asciz "alignment must not be larger than natural"
.Lm_zero: .asciz "zero byte expected"
.Lm_undeclared: .asciz "undeclared function reference"
.Lm_datacount: .asciz "data count section required"
.Lm_data: .asciz "unknown data segment"
.Lm_elem: .asciz "unknown elem segment"
