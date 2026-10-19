# A nested session's edits also belong to every paused enclosing active field.
.include "rhun.inc"
.text

# Accept a contained insertion as a user edit of its enclosing active field.
# snippet_insertion_begin(doc, candidate or 0, minimum edit start, maximum edit end)
FN snippet_insertion_begin
    PROLOGUE
    mov rbx, rdi
    mov r13, rdx
    mov r14, rcx
    call snippet_can_nest
    mov r12, rax
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call snippet_range_inside
    test eax, eax
    jz 8f
    mov rdi, rbx
    call snippet_user_begin
    mov rax, r12
    EPILOGUE
8:  mov rdi, rbx
    call snippet_forget
    xor eax, eax
    EPILOGUE

# Resolve the new inserted start after enclosing mirrors move its active primary.
# No top has been pushed yet. A failed preflight freed the old chain before any mirrors wrote.
FN snippet_insertion_finish
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + DOC_snippet]
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_user], 0
    je 9f
    mov rcx, [rax + SN_active]
    imul rcx, rcx, SF_SIZE
    mov r13, r12
    sub r13, [rax + rcx + SN_fields + SF_start]
    call snippet_user_end
    mov rax, [rbx + DOC_snippet]
    test rax, rax
    jz 9f
    mov rcx, [rax + SN_active]
    imul rcx, rcx, SF_SIZE
    mov r12, [rax + rcx + SN_fields + SF_start]
    add r12, r13
9:  mov rax, r12
    EPILOGUE

# Logical replacement affinity belongs to the exact range, including additional edits.
FN snippet_replace_range
    mov rdi, [rdi + DOC_snippet]
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi + SN_user], 0
    je 9f
    jmp snippet_chain_replace_mark
9:  ret

FN snippet_replace_done
    mov rdi, [rdi + DOC_snippet]
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi + SN_user], 0
    je 9f
    jmp snippet_chain_replace_clear
9:  ret

FN snippet_chain_replace_mark
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  test rbx, rbx
    jz 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call snippet_replace_mark
    mov rbx, [rbx + SN_parent]
    jmp 1b
9:  EPILOGUE

FN snippet_chain_replace_clear
    PROLOGUE
    mov rbx, rdi
1:  test rbx, rbx
    jz 9f
    mov rdi, rbx
    call snippet_replace_clear
    mov rbx, [rbx + SN_parent]
    jmp 1b
9:  EPILOGUE

# snippet_shift(state, signed delta): descendants lie wholly in the moved enclosing primary.
FN snippet_shift
    add [rdi + SN_final], rsi
    add [rdi + SN_finalend], rsi
    cmp qword ptr [rdi + SN_lastrecord], -1
    je 1f
    add [rdi + SN_lastpos], rsi
1:  xor ecx, ecx
2:  cmp rcx, [rdi + SN_nfields]
    jae 9f
    imul rax, rcx, SF_SIZE
    lea rax, [rdi + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jz 3f
    add [rax + SF_start], rsi
    add [rax + SF_end], rsi
3:  inc rcx
    jmp 2b
9:  ret

# snippet_map_chain(state, designated occurrence, pos, deleted, inserted)
# Acyclic group dependencies exclude dirty mirrors inside this state's active primary.
# Its descendant sessions therefore move uniformly when that primary's start moves.
FN snippet_map_chain
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rax, [rbx + SN_active]
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov [rsp], rax
    mov rax, [rax + SF_start]
    mov [rsp + 8], rax
    call snippet_map
    mov rax, [rsp]
    mov r12, [rax + SF_start]
    sub r12, [rsp + 8]
    mov rax, [rbx + SN_child]
1:  test rax, rax
    jz 2f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, r12
    call snippet_shift
    mov rax, [rsp]
    mov rax, [rax + SN_child]
    jmp 1b
2:  mov rbx, [rbx + SN_parent]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    mov rsi, [rbx + SN_active]
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    call snippet_map
    jmp 2b
9:  EPILOGUE

# snippet_propagate_chain(top, doc or 0): one aggregate budget for all enclosing groups.
FN snippet_propagate_chain
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [rsp], 0
1:  test rbx, rbx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp]
    xor ecx, ecx
    call snippet_propagate
    test eax, eax
    jz 9f
    mov rbx, [rbx + SN_parent]
    jmp 1b
8:  mov eax, 1
9:  EPILOGUE
