# Immutable, reference-counted literal choices owned by native snippet sessions.
.include "rhun.inc"
.text

# Release one node, without following its owned parent chain.
FN snippet_free_node
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    mov rdi, [rbx + SN_choice]
    test rdi, rdi
    jz 1f
    dec qword ptr [rdi + SC_refs]
    jnz 1f
    call mem_free
1:  mov rdi, [rbx + SN_transform]
    test rdi, rdi
    jz 2f
    dec qword ptr [rdi + SC_refs]
    jnz 2f
    call mem_free
2:  mov rdi, [rbx + SN_indent]
    test rdi, rdi
    jz 3f
    dec qword ptr [rdi + SC_refs]
    jnz 3f
    call mem_free
3:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

# New activation identities prevent a previously shown A field reviving after A->B->A.
FN snippet_activate
    test rdi, rdi
    jz 9f
    inc qword ptr [rip + sn_activation]
    mov rax, [rip + sn_activation]
    mov [rdi + SN_activation], rax
    mov qword ptr [rdi + SN_choice_pending], 0
    mov rax, [rdi + SN_active]
    cmp rax, [rdi + SN_nfields]
    jae 9f
    imul rax, rax, SF_SIZE
    mov rax, [rdi + rax + SN_fields + SF_gindex]
    imul rax, rax, SG_SIZE
    cmp qword ptr [rdi + rax + SN_groups + SG_choice], 0
    je 9f
    mov qword ptr [rdi + SN_choice_pending], 1
9:  ret

# Read OPTION_LEN LF and exactly that many bytes without touching parser globals.
# (ptr, end) -> data in rax, length in rdx, next in rcx; rcx zero on failure.
FN snippet_choice_option
    xor r8d, r8d
    xor r9d, r9d
1:  cmp rdi, rsi
    jae 8f
    movzx eax, byte ptr [rdi]
    inc rdi
    cmp eax, 10
    je 2f
    sub eax, '0'
    cmp eax, 9
    ja 8f
    inc r9
    cmp r9, 10
    ja 8f
    imul r8, r8, 10
    add r8, rax
    cmp r8, SN_OPTION_MAX
    ja 8f
    jmp 1b
2:  test r9, r9
    jz 8f
    mov rcx, rsi
    sub rcx, rdi
    cmp r8, rcx
    ja 8f
    mov rax, rdi
    mov rdx, r8
    lea rcx, [rdi + r8]
    ret
8:  xor eax, eax
    xor edx, edx
    xor ecx, ecx
    ret

# Validate exactly count UTF-8 options, including empty ones. (ptr, len, count) -> 1.
FN snippet_choice_options
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov r13, rdx
    test r13, r13
    jz 8f
    cmp r13, SN_OPTIONS_MAX
    ja 8f
1:  mov rdi, rbx
    mov rsi, r12
    call snippet_choice_option
    test rcx, rcx
    jz 8f
    mov rbx, rcx
    mov rdi, rax
    mov rsi, rdx
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    dec r13
    jnz 1b
    cmp rbx, r12
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Freeze validated choice record bytes after ordinary field graph validation.
# (state, temporary bytes, length) -> 1. Caller owns/restores parser globals.
FN snippet_choices_freeze
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .Lscf_ok
    cmp r13, SN_BYTES_MAX
    ja .Lscf_bad
    mov rax, [rbx + SN_transformbytes]
    add rax, [rbx + SN_indentbytes]
    jc .Lscf_bad
    cmp rax, SN_BYTES_MAX
    ja .Lscf_bad
    mov ecx, SN_BYTES_MAX
    sub rcx, rax
    cmp r13, rcx
    ja .Lscf_bad
    mov [rip + ps_ptr], r12
    lea rax, [r12 + r13]
    mov [rip + ps_end], rax
.Lscf_record:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    je .Lscf_copy
    sub rax, r12
    inc rax
    mov [rsp], rax
    call ps_line
    test eax, eax
    jz .Lscf_bad
    call ps_word
    call ps_num
    test edx, edx
    jz .Lscf_bad
    xor r14d, r14d
1:  cmp r14, [rbx + SN_ngroups]
    jae .Lscf_bad
    imul r15, r14, SG_SIZE
    lea r15, [rbx + r15 + SN_groups]
    cmp rax, [r15 + SG_id]
    je 2f
    inc r14
    jmp 1b
2:  cmp qword ptr [r15 + SG_choice], 0
    jne .Lscf_bad
    mov rax, [rsp]
    mov [r15 + SG_choice], rax
    call ps_num                 # count was checked before copying temporary bytes
    test edx, edx
    jz .Lscf_bad
    call ps_num
    test edx, edx
    jz .Lscf_bad
    mov [rsp + 8], rax
    call ps_eol
    test eax, eax
    jz .Lscf_bad
    mov rdi, [rip + ps_ptr]
    mov rsi, [rsp + 8]         # bound the first option to this record body
    add rsi, rdi
    cmp rsi, [rip + ps_end]
    ja .Lscf_bad
    call snippet_choice_option
    test rcx, rcx
    jz .Lscf_bad
    mov rdi, rax
    mov rax, [r15 + SG_primary]
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov rcx, [rax + SF_end]
    sub rcx, [rax + SF_start]
    cmp rcx, rdx
    jne .Lscf_bad
    test rcx, rcx
    jz 3f
    mov rsi, [rbx + SN_text]
    add rsi, [rax + SF_start]
    repe cmpsb
    jne .Lscf_bad
3:  mov rax, [rsp + 8]
    add [rip + ps_ptr], rax
    jmp .Lscf_record
.Lscf_copy:
    lea rdi, [r13 + SC_DATA]
    call mem_alloc
    mov [rbx + SN_choice], rax
    mov [rbx + SN_choicebytes], r13
    mov qword ptr [rax + SC_refs], 1
    mov [rax + SC_bytes], r13
    lea rdi, [rax + SC_DATA]
    mov rsi, r12
    mov rdx, r13
    call memcpy
.Lscf_ok:
    mov eax, 1
    EPILOGUE
.Lscf_bad:
    xor eax, eax
    EPILOGUE

# Immutable options of the active primary: rax body, rdx body length, rcx count, or zero.
FN snippet_choice_get
    PROLOGUE 48
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    mov rax, [rip + ps_ptr]
    mov [rsp], rax
    mov rax, [rip + ps_end]
    mov [rsp + 8], rax
    mov rax, [rip + ps_lend]
    mov [rsp + 16], rax
    mov rax, [rbx + SN_choice]
    test rax, rax
    jz 9f
    mov rcx, [rbx + SN_active]
    cmp rcx, [rbx + SN_nfields]
    jae 9f
    imul rcx, rcx, SF_SIZE
    mov rcx, [rbx + rcx + SN_fields + SF_gindex]
    imul rcx, rcx, SG_SIZE
    mov rcx, [rbx + rcx + SN_groups + SG_choice]
    test rcx, rcx
    jz 9f
    lea rdx, [rax + SC_DATA]
    lea rcx, [rdx + rcx - 1]
    mov [rip + ps_ptr], rcx
    add rdx, [rax + SC_bytes]
    mov [rip + ps_end], rdx
    call ps_line
    call ps_word
    call ps_num
    call ps_num
    mov r14, rax
    call ps_num
    mov r13, rax
    call ps_eol
    mov r12, [rip + ps_ptr]
9:  mov rax, [rsp]
    mov [rip + ps_ptr], rax
    mov rax, [rsp + 8]
    mov [rip + ps_end], rax
    mov rax, [rsp + 16]
    mov [rip + ps_lend], rax
    mov rax, r12
    mov rdx, r13
    mov rcx, r14
    EPILOGUE

# Explicit completion may collapse an exact active-primary selection at its end.
FN snippet_complete_collapse
    PROLOGUE
    mov rbx, rdi
    call snippet_check
    test rax, rax
    jz 9f
    mov rcx, [rax + SN_active]
    imul rcx, rcx, SF_SIZE
    lea r12, [rax + rcx + SN_fields]
    mov rdi, rbx
    call ed_sel
    cmp rax, [r12 + SF_start]
    jne 9f
    cmp rdx, [r12 + SF_end]
    jne 9f
    mov [rbx + DOC_cur], rdx
    mov [rbx + DOC_anchor], rdx
9:  EPILOGUE
