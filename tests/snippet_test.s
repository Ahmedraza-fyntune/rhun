# Prepared fields must reject unsafe graphs before any document is changed.
.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    # doc_range retains its shared cross-gap scratch allocation across documents.
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + pair]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rip + lettera]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    xor esi, esi
    mov edx, 4
    call doc_range
    mov rdi, rbx
    call doc_free
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    lea r12, [rip + cases]
    xor r13d, r13d
.Lcase:
    cmp qword ptr [r12], 0
    je .Llimits
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    call snippet_new
    mov rbx, rax
    mov r14, [r12 + 16]
    xor r15d, r15d
1:  cmp r15, [r12 + 24]
    jae 2f
    mov rdi, rbx
    mov rsi, [r14]
    mov rdx, [r14 + 8]
    mov rcx, [r14 + 16]
    mov r8, [r14 + 24]
    call snippet_add
    add r14, 32
    inc r15
    jmp 1b
2:  mov rdi, rbx
    call snippet_validate
    cmp rax, [r12 + 32]
    jne .Lfail
    mov rdi, rbx
    call mem_free
    add r12, 40
    inc r13
    jmp .Lcase
.Llimits:
    # 512 empty occurrences can link; the 513th invalidates the whole candidate.
    lea rdi, [rip + empty]
    xor esi, esi
    call snippet_new
    mov rbx, rax
    xor r12d, r12d
3:  mov rdi, rbx
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    inc r12
    cmp r12, SN_FIELDS_MAX
    jb 3b
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    test eax, eax
    jnz .Lfail
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jnz .Lfail
    mov rdi, rbx
    call mem_free
    inc r13
    # Independent group bound.
    lea rdi, [rip + empty]
    xor esi, esi
    call snippet_new
    mov rbx, rax
    xor r12d, r12d
4:  mov rdi, rbx
    lea rsi, [r12 + 1]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    inc r12
    cmp r12, SN_GROUPS_MAX
    jb 4b
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    mov esi, SN_GROUPS_MAX + 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jnz .Lfail
    mov rdi, rbx
    call mem_free
    inc r13
    # Coextensive empty nesting is bounded separately from the group count.
    lea rdi, [rip + empty]
    xor esi, esi
    call snippet_new
    mov rbx, rax
    xor r12d, r12d
5:  mov rdi, rbx
    lea rsi, [r12 + 1]
    xor edx, edx
    xor ecx, ecx
    mov r8, r12
    call snippet_add
    inc r12
    cmp r12, SN_DEPTH_MAX
    jb 5b
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    mov esi, SN_DEPTH_MAX + 1
    xor edx, edx
    xor ecx, ecx
    mov r8d, SN_DEPTH_MAX
    call snippet_add
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jnz .Lfail
    mov rdi, rbx
    call mem_free
    inc r13
    call state_cases
    test eax, eax
    jz .Lfail
    inc r13
    call mapping_cases
    test eax, eax
    jz .Lfail
    inc r13
    call retirement_cases
    test eax, eax
    jz .Lfail
    inc r13
    call mirror_cases
    test eax, eax
    jz .Lfail
    inc r13
    call user_cases
    test eax, eax
    jz .Lfail
    inc r13
    call stack_cases
    test eax, eax
    jz .Lfail
    inc r13
    call nested_mirror_cases
    test eax, eax
    jz .Lfail
    inc r13
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lfail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    lea rdi, [rip + out]
    lea rsi, [rip + failure]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE

# Accepted sessions belong to their document, with numeric navigation and no tab activation.
state_cases:
    PROLOGUE
    mov r15d, 1
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + document]
    mov ecx, 7
    xor r8d, r8d
    call doc_insert
    call doc_new
    mov r12, rax
    mov [rip + g_doc], rax
    mov dword ptr [rip + g_focus], FOCUS_TERMINAL
    call state_candidate
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    call snippet_attach
    inc r15
    cmp [rip + g_doc], r12
    jne .Lstate_fail
    cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_anchor], 4
    jne .Lstate_fail
    mov rdi, rbx
    mov esi, -1
    call snippet_step
    inc r15
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    inc r15
    cmp qword ptr [rbx + DOC_cur], 3
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_anchor], 2
    jne .Lstate_fail
    mov rdi, rbx
    call snippet_check
    inc r15
    test rax, rax
    jz .Lstate_fail
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    inc r15
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_anchor], 5
    jne .Lstate_fail
    # A move outside the active field retires state without changing text.
    call state_candidate
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    call snippet_attach
    mov qword ptr [rbx + DOC_cur], 0
    mov rdi, rbx
    call snippet_check
    test rax, rax
    jnz .Lstate_fail
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    call state_candidate
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    call snippet_attach
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov rdi, rbx
    call snippet_check
    test rax, rax
    jnz .Lstate_fail
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    # Document disposal also releases a paused session.
    call state_candidate
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    call snippet_attach
    mov rdi, rbx
    call doc_free
    inc r15
    lea rdi, [rip + linepair]
    mov esi, 3
    lea rdx, [rip + linefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov [rip + g_doc], rax
    call cmd_duplicate_line
    cmp qword ptr [rbx + DOC_snippet], 0
    je .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + duplicatedpair]
    mov edx, 7
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, r12
    call doc_free
    mov eax, 1
    EPILOGUE
.Lstate_fail:
    lea rdi, [rip + out]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    lea rdi, [rip + out]
    call sb_clear
    xor eax, eax
    EPILOGUE

state_candidate:
    PROLOGUE
    lea rdi, [rip + sortedtext]
    mov esi, 3
    call snippet_new
    mov rbx, rax
    mov rdi, rax
    mov esi, 2
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call snippet_add
    mov rdi, rbx
    mov esi, 1
    mov edx, 2
    mov ecx, 3
    xor r8d, r8d
    call snippet_add
    mov rdi, rbx
    call snippet_validate
    test eax, eax
    jz 1f
    mov rax, rbx
    EPILOGUE
1:  mov edi, 1
    call sys_exit

# Endpoint comparisons include fields sharing a replacement boundary.
mapping_cases:
    PROLOGUE
    lea r12, [rip + mappings]
1:  cmp qword ptr [r12], 0
    je .Lmap_replacements
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    call mapping_candidate
    mov rbx, rax
    mov rdi, rax
    mov rsi, [r12 + 24]
    mov rdx, [r12 + 32]
    mov rcx, [r12 + 40]
    mov r8, [r12 + 48]
    call snippet_map
    mov rdi, rbx
    mov rsi, [r12 + 56]
    call mapping_equal
    test eax, eax
    jz .Lmapping_fail
    mov rdi, rbx
    call mem_free
    add r12, 64
    jmp 1b
.Lmap_replacements:
    lea r12, [rip + replacements]
2:  cmp qword ptr [r12], 0
    je .Lmapping_ok
    mov rdi, [r12]
    mov esi, 3
    mov edx, 3
    call mapping_candidate
    mov rbx, rax
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    xor ecx, ecx
    mov r8d, 1
    call snippet_map
    mov rdi, rbx
    mov esi, 3
    mov edx, 4
    call snippet_replace_mark
    mov rdi, rbx
    mov esi, 2
    mov edx, 3
    mov ecx, 1
    xor r8d, r8d
    call snippet_map
    mov rdi, rbx
    mov esi, 2
    mov edx, 3
    xor ecx, ecx
    mov r8d, 2
    call snippet_map
    mov rdi, rbx
    call snippet_replace_clear
    mov rdi, rbx
    mov rsi, [r12 + 8]
    call mapping_equal
    test eax, eax
    jz .Lmapping_fail
    cmp qword ptr [rbx + SN_final], 5
    jne .Lmapping_fail
    mov rdi, rbx
    call mem_free
    add r12, 16
    jmp 2b
.Lmapping_ok:
    mov eax, 1
    EPILOGUE
.Lmapping_fail:
    xor eax, eax
    EPILOGUE

# mapping_candidate(records, count, textlen) -> validated state with text from pair
mapping_candidate:
    mov rcx, rsi
    mov rsi, rdx
    mov rdx, rdi
    lea rdi, [rip + pair]
    jmp fields_candidate

# fields_candidate(text, length, records, count)
fields_candidate:
    PROLOGUE
    mov rbx, rdx
    mov r12, rcx
    call snippet_new
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r12
    jae 2f
    mov rdi, r13
    mov rsi, [rbx]
    mov rdx, [rbx + 8]
    mov rcx, [rbx + 16]
    mov r8, [rbx + 24]
    call snippet_add
    add rbx, 32
    inc r14
    jmp 1b
2:  mov rdi, r13
    call snippet_validate
    test eax, eax
    jz 3f
    mov rax, r13
    EPILOGUE
3:  mov edi, 1
    call sys_exit

mapping_equal:
    xor ecx, ecx
1:  cmp rcx, [rdi + SN_nfields]
    jae 9f
    imul rax, rcx, SF_SIZE
    lea rax, [rdi + rax + SN_fields]
    mov rdx, [rsi]
    cmp rdx, [rax + SF_start]
    jne 8f
    mov rdx, [rsi + 8]
    cmp rdx, [rax + SF_end]
    jne 8f
    add rsi, 16
    inc rcx
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

retirement_cases:
    PROLOGUE
    lea r12, [rip + retire_edits]
1:  cmp qword ptr [r12], -1
    je .Lretire_mirror
    lea rdi, [rip + parenttext]
    mov esi, 9
    lea rdx, [rip + parentfields]
    mov ecx, 6
    call fields_candidate
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r12]
    mov rcx, [r12 + 8]
    mov r8, [r12 + 16]
    call snippet_retire_touch
    test eax, eax
    jz .Lretire_fail
    cmp qword ptr [rbx + SN_ntopo], 1
    jne .Lretire_fail
    cmp qword ptr [rbx + SN_groups + SG_alive], 1
    jne .Lretire_fail
    cmp qword ptr [rbx + SN_groups + SG_SIZE + SG_alive], 0
    jne .Lretire_fail
    cmp qword ptr [rbx + SN_groups + 2*SG_SIZE + SG_alive], 0
    jne .Lretire_fail
    mov ecx, 1
2:  cmp ecx, 5
    jae 3f
    imul rax, rcx, SF_SIZE
    test qword ptr [rbx + rax + SN_fields + SF_flags], 1
    jnz .Lretire_fail
    inc ecx
    jmp 2b
3:  test qword ptr [rbx + SN_fields + 5*SF_SIZE + SF_flags], 1
    jz .Lretire_fail
    cmp qword ptr [rbx + SN_fields + 5*SF_SIZE + SF_parent], 1
    jne .Lretire_fail
    mov rdi, rbx
    call mem_free
    add r12, 24
    jmp 1b
.Lretire_mirror:
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + mirrorretire]
    mov ecx, 4
    call fields_candidate
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    mov r8d, 1
    call snippet_retire_touch
    test eax, eax
    jz .Lretire_fail
    cmp qword ptr [rbx + SN_ntopo], 2
    jne .Lretire_fail
    cmp qword ptr [rbx + SN_groups + SG_SIZE + SG_alive], 1
    jne .Lretire_fail
    test qword ptr [rbx + SN_fields + SF_SIZE + SF_flags], 1
    jz .Lretire_fail
    test qword ptr [rbx + SN_fields + 2*SF_SIZE + SF_flags], 1
    jnz .Lretire_fail
    cmp qword ptr [rbx + SN_topo], 0
    jne .Lretire_fail
    mov rdi, rbx
    call mem_free
    # Full parent replacement also removes empty children at its end.
    lea rdi, [rip + parenttext]
    mov esi, 4
    lea rdx, [rip + endchildren]
    mov ecx, 4
    call fields_candidate
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    mov ecx, 3
    xor r8d, r8d
    call snippet_retire_touch
    test eax, eax
    jz .Lretire_fail
    cmp qword ptr [rbx + SN_ntopo], 1
    jne .Lretire_fail
    cmp qword ptr [rbx + SN_fields + 3*SF_SIZE + SF_parent], 1
    jne .Lretire_fail
    mov rdi, rbx
    call mem_free
    mov eax, 1
    EPILOGUE
.Lretire_fail:
    xor eax, eax
    EPILOGUE

# Real propagation, including dependencies crossing primary branches and an atomic budget refusal.
mirror_cases:
    PROLOGUE 16
    mov r15d, 101
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + beforefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_user_begin
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + lettera]
    mov ecx, 1
    mov r8d, EK_TYPE
    call doc_insert
    mov qword ptr [rbx + DOC_cur], 4
    mov qword ptr [rbx + DOC_anchor], 4
    mov rdi, rbx
    call snippet_user_end
    mov rdi, rbx
    lea rsi, [rip + typedpair]
    mov edx, 5
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    mov rdi, rbx
    call snippet_forget
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + pair]
    mov edx, 3
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    # Deleting at an adjacent mirror's end must retain the primary-relative caret.
    lea rdi, [rip + boundarytext]
    mov esi, 8
    lea rdx, [rip + boundaryfields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_user_begin
    mov rdi, rbx
    mov esi, 4
    mov edx, 1
    mov ecx, EK_DEL
    call doc_delete
    mov qword ptr [rbx + DOC_cur], 4
    mov qword ptr [rbx + DOC_anchor], 4
    mov rdi, rbx
    call snippet_user_end
    mov rdi, rbx
    lea rsi, [rip + boundaryedited]
    mov edx, 6
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 3
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    # Group 1 mirrors into group 2's primary; group 2 must run afterwards.
    lea rdi, [rip + branchtext]
    mov esi, 9
    lea rdx, [rip + branchfields]
    mov ecx, 4
    call mirror_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_user_begin
    mov rdi, rbx
    mov esi, 9
    lea rdx, [rip + lettera]
    mov ecx, 1
    mov r8d, EK_TYPE
    call doc_insert
    mov qword ptr [rbx + DOC_cur], 10
    mov qword ptr [rbx + DOC_anchor], 10
    mov rdi, rbx
    call snippet_user_end
    mov rdi, rbx
    lea rsi, [rip + branchedited]
    mov edx, 12
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 12
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    # Two mirrors exceed the aggregate cap. Neither may change before cancellation.
    lea rdi, [rip + triple]
    mov esi, 5
    lea rdx, [rip + budgetfields]
    mov ecx, 3
    call mirror_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_user_begin
    mov edi, SN_BYTES_MAX / 2
    call mem_alloc
    mov r12, rax
    mov rdi, rax
    mov esi, 'a'
    mov edx, SN_BYTES_MAX / 2
    call memset
    mov rdi, rbx
    mov esi, 1
    mov rdx, r12
    mov ecx, SN_BYTES_MAX / 2
    mov r8d, EK_TYPE
    call doc_insert
    mov rdi, r12
    call mem_free
    mov qword ptr [rbx + DOC_cur], SN_BYTES_MAX / 2 + 1
    mov qword ptr [rbx + DOC_anchor], SN_BYTES_MAX / 2 + 1
    mov r12, [rbx + DOC_version]
    mov r13, [rbx + DOC_undo + VEC_len]
    mov rdi, rbx
    call snippet_user_end
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    cmp [rbx + DOC_version], r12
    jne .Lstate_fail
    cmp [rbx + DOC_undo + VEC_len], r13
    jne .Lstate_fail
    mov rdi, rbx
    mov esi, SN_BYTES_MAX / 2 + 1
    mov edx, 4
    call doc_range
    cmp dword ptr [rax], 0x78207820
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    mov eax, 1
    EPILOGUE

# Editor operations preserve grouping and final selection independently of physical mirror order.
user_cases:
    PROLOGUE 16
    mov r15d, 201
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + beforefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov [rip + g_doc], rax
    mov qword ptr [rbx + DOC_cur], 3
    mov qword ptr [rbx + DOC_anchor], 3
    mov rdi, rbx
    lea rsi, [rip + lettera]
    mov edx, 1
    mov ecx, EK_TYPE
    call ed_insert
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    # A no-op scope cannot rewrite an earlier tail's redo caret.
    mov qword ptr [rbx + DOC_cur], 4
    mov qword ptr [rbx + DOC_anchor], 4
    mov rdi, rbx
    call snippet_user_begin
    mov rdi, rbx
    call snippet_user_end
    mov rax, [rbx + DOC_undo + VEC_len]
    dec rax
    imul rax, rax, UR_SIZE
    add rax, [rbx + DOC_undo + VEC_ptr]
    cmp qword ptr [rax + UR_aftercur], 5
    jne .Lstate_fail
    mov qword ptr [rbx + DOC_cur], 5
    mov qword ptr [rbx + DOC_anchor], 5
    # Reallocation cannot invalidate the stable primary record index.
    mov rsi, [rbx + DOC_undo + VEC_cap]
    add rsi, 32
    mov [rbx + DOC_undo + VEC_cap], rsi
    imul rsi, rsi, UR_SIZE
    mov rdi, [rbx + DOC_undo + VEC_ptr]
    call mem_realloc
    mov [rbx + DOC_undo + VEC_ptr], rax
    mov rdi, rbx
    lea rsi, [rip + letterb]
    mov edx, 1
    mov ecx, EK_TYPE
    call ed_insert
    mov rdi, rbx
    lea rsi, [rip + twicepair]
    mov edx, 7
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 7
    jne .Lstate_fail
    mov rdi, rbx
    call doc_undo
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + pair]
    mov edx, 3
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 7
    jne .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + twicepair]
    mov edx, 7
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 7
    jne .Lstate_fail
    # An ordinary record later in this same group must reset the earlier override.
    or dword ptr [rbx + DOC_flags], 1
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + lettera]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    and dword ptr [rbx + DOC_flags], -2
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 1
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_anchor], 1
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    # Selection replacement is one logical replacement with one undo step.
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + beforefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    lea rsi, [rip + replacetext]
    mov edx, 2
    xor ecx, ecx
    call ed_insert
    mov rdi, rbx
    lea rsi, [rip + replacedpair]
    mov edx, 5
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + pair]
    mov edx, 3
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 5
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    lea rdi, [rip + boundarytext]
    mov esi, 8
    lea rdx, [rip + boundaryfields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov [rip + g_doc], rax
    mov qword ptr [rbx + DOC_cur], 4
    mov qword ptr [rbx + DOC_anchor], 4
    xor edi, edi
    call ed_delete_fwd
    cmp qword ptr [rbx + DOC_cur], 3
    jne .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + boundaryedited]
    mov edx, 6
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 3
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov eax, 1
    EPILOGUE

# Stack ownership, clone isolation, aggregate limits and a final stop returning to its parent.
stack_cases:
    PROLOGUE 16
    mov r15d, 301
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + linefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    mov qword ptr [rsp], 1
1:  cmp qword ptr [rsp], SN_SESSIONS_MAX
    jae 2f
    lea rdi, [rip + pair]
    mov esi, 1
    lea rdx, [rip + firstonly]
    mov ecx, 1
    call fields_candidate
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call snippet_can_nest
    test rax, rax
    jz .Lstate_fail
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call snippet_push
    inc qword ptr [rsp]
    jmp 1b
2:  lea rdi, [rip + pair]
    mov esi, 1
    lea rdx, [rip + firstonly]
    mov ecx, 1
    call fields_candidate
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call snippet_can_nest
    test rax, rax
    jnz .Lstate_fail
    mov rdi, r12
    call mem_free
    # A non-field insertion consumes no stack slot at the depth limit.
    mov rdi, rbx
    xor esi, esi
    call snippet_can_nest
    test rax, rax
    jz .Lstate_fail
    mov rdi, [rbx + DOC_snippet]
    call snippet_clone_chain
    mov r12, rax
    mov rcx, [rbx + DOC_snippet]
    xor edx, edx
3:  test rax, rax
    jz 4f
    cmp rax, rcx
    je .Lstate_fail
    mov rsi, [rax + SN_parent]
    test rsi, rsi
    jz 31f
    cmp [rsi + SN_child], rax
    jne .Lstate_fail
31: mov rax, rsi
    mov rcx, [rcx + SN_parent]
    inc rdx
    jmp 3b
4:  cmp rdx, SN_SESSIONS_MAX
    jne .Lstate_fail
    test rcx, rcx
    jnz .Lstate_fail
    mov rdi, r12
    call snippet_free_chain
    mov r12, [rbx + DOC_snippet]
    mov r12, [r12 + SN_parent]
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    cmp [rbx + DOC_snippet], r12
    jne .Lstate_fail
    cmp qword ptr [r12 + SN_child], 0
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 1
    jne .Lstate_fail
    mov rdi, rbx
    call snippet_forget
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    inc r15
    # Each candidate is valid alone; total occurrences/groups constrain nesting separately.
    lea rdi, [rip + pair]
    mov esi, 3
    lea rdx, [rip + linefields]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    lea rdi, [rip + empty]
    xor esi, esi
    call snippet_new
    mov r12, rax
    xor r13d, r13d
5:  mov rdi, r12
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    inc r13
    cmp r13, SN_FIELDS_MAX
    jb 5b
    mov rdi, r12
    call snippet_validate
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    mov rsi, r12
    call snippet_can_nest
    test rax, rax
    jnz .Lstate_fail
    mov rdi, r12
    call mem_free
    lea rdi, [rip + empty]
    xor esi, esi
    call snippet_new
    mov r12, rax
    xor r13d, r13d
6:  mov rdi, r12
    lea rsi, [r13 + 1]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    inc r13
    cmp r13, SN_GROUPS_MAX
    jb 6b
    mov rdi, r12
    call snippet_validate
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    mov rsi, r12
    call snippet_can_nest
    test rax, rax
    jnz .Lstate_fail
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call doc_free
    mov eax, 1
    EPILOGUE

# Propagation spans child then parent with one preflight budget and a stable primary caret.
nested_mirror_cases:
    PROLOGUE 16
    mov r15d, 401
    call nested_mirror_doc
    mov rbx, rax
    mov [rip + g_doc], rax
    mov qword ptr [rbx + DOC_cur], 4
    mov qword ptr [rbx + DOC_anchor], 4
    mov rdi, rbx
    lea rsi, [rip + lettera]
    mov edx, 1
    mov ecx, EK_TYPE
    call ed_insert
    mov rdi, rbx
    lea rsi, [rip + nestededited]
    mov edx, 9
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 7
    jne .Lstate_fail
    mov rax, [rbx + DOC_snippet]
    cmp qword ptr [rax + SN_fields + SF_start], 5
    jne .Lstate_fail
    cmp qword ptr [rax + SN_fields + SF_end], 7
    jne .Lstate_fail
    mov r12, [rax + SN_parent]
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    cmp [rbx + DOC_snippet], r12
    jne .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 9
    jne .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + letterb]
    mov edx, 1
    mov ecx, EK_TYPE
    call ed_insert
    mov rdi, rbx
    lea rsi, [rip + resumededited]
    mov edx, 11
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    cmp qword ptr [rbx + DOC_cur], 11
    jne .Lstate_fail
    # Resuming the parent starts a fresh typing group.
    mov rdi, rbx
    call doc_undo
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    mov rdi, rbx
    lea rsi, [rip + nestededited]
    mov edx, 9
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + nestedtext]
    mov edx, 5
    call mirror_equal
    test eax, eax
    jz .Lstate_fail
    mov rdi, rbx
    call doc_redo
    cmp qword ptr [rbx + DOC_cur], 7
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    inc r15
    call nested_mirror_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_user_begin
    mov edi, SN_BYTES_MAX / 3 + 1
    call mem_alloc
    mov r12, rax
    mov rdi, rax
    mov esi, 'a'
    mov edx, SN_BYTES_MAX / 3 + 1
    call memset
    mov rdi, rbx
    mov esi, 4
    mov rdx, r12
    mov ecx, SN_BYTES_MAX / 3 + 1
    mov r8d, EK_TYPE
    call doc_insert
    mov rdi, r12
    call mem_free
    mov qword ptr [rbx + DOC_cur], SN_BYTES_MAX / 3 + 5
    mov qword ptr [rbx + DOC_anchor], SN_BYTES_MAX / 3 + 5
    mov r12, [rbx + DOC_version]
    mov r13, [rbx + DOC_undo + VEC_len]
    mov rdi, rbx
    call snippet_user_end
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Lstate_fail
    cmp [rbx + DOC_version], r12
    jne .Lstate_fail
    cmp [rbx + DOC_undo + VEC_len], r13
    jne .Lstate_fail
    mov rdi, rbx
    xor esi, esi
    mov edx, 4
    call doc_range
    cmp dword ptr [rax], 0x78207878
    jne .Lstate_fail
    mov rdi, rbx
    mov esi, SN_BYTES_MAX / 3 + 5
    call doc_byte
    cmp eax, 'x'
    jne .Lstate_fail
    mov rdi, rbx
    call doc_free
    mov eax, 1
    EPILOGUE

nested_mirror_doc:
    PROLOGUE
    lea rdi, [rip + nestedtext]
    mov esi, 5
    lea rdx, [rip + nestedouter]
    mov ecx, 2
    call mirror_doc
    mov rbx, rax
    lea rdi, [rip + nestedtext]
    mov esi, 2
    lea rdx, [rip + nestedinner]
    mov ecx, 2
    call fields_candidate
    mov rdi, rbx
    mov rsi, rax
    mov edx, 3
    call snippet_push
    mov rax, rbx
    EPILOGUE

# mirror_doc(text, len, fields, count) -> owned document with an accepted session
mirror_doc:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    xor r8d, r8d
    call doc_insert
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    call fields_candidate
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call snippet_attach
    mov rax, rbx
    EPILOGUE

mirror_equal:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_len
    cmp rax, r13
    jne 1f
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    call doc_range
    mov rdi, rax
    mov rsi, r12
    mov rcx, r13
    cmp rcx, rcx
    repe cmpsb
    sete al
    movzx eax, al
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

.section .rodata
ok: .asciz "ok snippet validation\n"
failure: .asciz "failed snippet case "
empty: .byte 0
document: .ascii "__x y__"
sortedtext: .ascii "x y"
parenttext: .ascii "abc abc b"
pair: .ascii "x x"
lettera: .ascii "a"
letterb: .ascii "b"
twicepair: .ascii "xab xab"
replacetext: .ascii "yo"
replacedpair: .ascii "yo yo"
typedpair: .ascii "xa xa"
boundarytext: .ascii "abcdabcd"
boundaryedited: .ascii "bcdbcd"
branchtext: .ascii "[x] [x] x"
branchedited: .ascii "[xa] [xa] xa"
triple: .ascii "x x x"
linepair: .ascii "x\nx"
duplicatedpair: .ascii "x\nx\nx\nx"
nestedtext: .ascii "xx xx"
nestededited: .ascii "xaxa xaxa"
resumededited: .ascii "xaxab xaxab"
different: .ascii "x y"
unicode: .byte 0xf0, 0x9f, 0x98, 0x80
surrogate: .byte 0xed, 0xa0, 0x80
above: .byte 0xf4, 0x90, 0x80, 0x80
replacement: .byte 0xef, 0xbf, 0xbd
overlong: .byte 0xc0, 0x80
.p2align 3
linked: .quad 1,0,1,0, 1,2,3,0, 0,3,3,0
beforefields: .quad 1,2,3,0, 1,0,1,0
linefields: .quad 1,0,1,0, 1,2,3,0
firstonly: .quad 1,0,1,0
nestedouter: .quad 1,3,5,0, 1,0,2,0
nestedinner: .quad 1,0,1,0, 1,1,2,0
boundaryfields: .quad 1,4,8,0, 1,0,4,0
branchfields: .quad 1,8,9,0, 2,0,3,0, 1,1,2,2, 2,4,7,0
budgetfields: .quad 1,0,1,0, 1,2,3,0, 1,4,5,0
nested: .quad 1,0,1,0, 2,0,1,1, 2,2,3,0, 0,3,3,0
cycle: .quad 1,0,1,0, 2,2,3,0, 2,0,1,1, 1,2,3,2
outside: .quad 1,0,1,0, 2,2,3,1
future: .quad 1,0,1,2, 2,2,3,0
mirrorparent: .quad 1,0,1,0, 1,2,3,0, 2,2,3,2
interior: .quad 1,0,3,0, 2,1,1,0
unrelated: .quad 1,0,3,0, 2,0,3,0
badboundary: .quad 1,1,4,0
goodboundary: .quad 1,0,4,0, 2,0,4,1, 0,4,4,2
doublefinal: .quad 0,0,0,0, 0,0,0,0
nonemptyfinal: .quad 0,0,1,0
emptyfields: .quad 1,0,0,0, 2,0,0,1, 3,0,0,0, 0,0,0,1
rightstop: .quad 2,3,3,0, 1,0,1,0, 1,2,3,0
leftstop: .quad 2,2,2,0, 1,0,1,0, 1,2,3,0
adjacent: .quad 1,0,1,0, 2,1,2,0
coincident: .quad 1,0,0,0, 2,0,0,0, 0,0,0,0
nestedempty: .quad 1,0,0,0, 2,0,0,1, 0,0,0,0
deletion: .quad 1,0,3,0, 2,3,3,0
adjacentleft: .quad 0,2,2,3
adjacentright: .quad 0,1,1,3
emptyfirst: .quad 0,1,1,1,1,1
emptysecond: .quad 0,0,0,1,1,1
nestedgrown: .quad 0,1,0,1,1,1
deleted: .quad 0,2,2,2
rightgrown: .quad 5,5,0,2,3,5
leftgrown: .quad 3,3,0,2,3,5
mappings:
    .quad adjacent,2,3,0,1,0,1,adjacentleft
    .quad adjacent,2,3,1,1,0,1,adjacentright
    .quad coincident,3,0,0,0,0,1,emptyfirst
    .quad coincident,3,0,1,0,0,1,emptysecond
    .quad nestedempty,3,0,1,0,0,1,nestedgrown
    .quad deletion,2,3,0,1,1,0,deleted
    .quad 0,0,0,0,0,0,0,0
replacements:
    .quad rightstop,rightgrown,leftstop,leftgrown,0,0
parentfields:
    .quad 1,0,3,0, 2,0,3,1, 3,1,2,2, 2,4,7,0, 3,8,9,0, 0,3,3,2
mirrorretire:
    .quad 1,0,1,0, 2,2,3,0, 2,0,1,1, 0,3,3,0
endchildren:
    .quad 1,0,3,0, 2,3,3,1, 2,4,4,0, 0,3,3,2
retire_edits:
    .quad 1,1,0, 0,2,0, 2,1,0, 1,0,1, 0,0,1, 3,0,1, -1,0,0
cases:
    .quad empty,0,0,0,1
    .quad pair,3,linked,3,1
    .quad pair,3,nested,4,1
    .quad pair,3,cycle,4,0
    .quad pair,3,outside,2,0
    .quad pair,3,future,2,0
    .quad pair,3,mirrorparent,3,0
    .quad pair,3,interior,2,0
    .quad pair,3,unrelated,2,0
    .quad different,3,linked,3,0
    .quad unicode,4,badboundary,1,0
    .quad unicode,4,goodboundary,3,1
    .quad surrogate,3,0,0,0
    .quad above,4,0,0,0
    .quad replacement,3,0,0,1
    .quad overlong,2,0,0,0
    .quad empty,0,doublefinal,2,0
    .quad pair,3,nonemptyfinal,1,1
    .quad empty,0,emptyfields,4,1
    .quad pair,3,rightstop,3,1
    .quad pair,SN_BYTES_MAX+1,0,0,0
    .quad 0,0,0,0,0
