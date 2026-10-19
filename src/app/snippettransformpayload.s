# Private canonical transform bindings. Field identity is checked when freezing.
.include "rhun.inc"
.text
# validate(ptr, len) -> bool, edx error byte offset. No allocation or retention.
FN snippet_transforms_validate
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov rdx, rsi
    cmp rsi, STP_HEADER
    jb .Ltp_bad
    mov edx, 16
    cmp rsi, SN_BYTES_MAX
    ja .Ltp_bad
    xor edx, edx
    cmp dword ptr [rbx], STP_MAGIC
    jne .Ltp_bad
    mov edx, 4
    cmp dword ptr [rbx + 4], 1
    jne .Ltp_bad
    mov edx, 8
    cmp dword ptr [rbx + 8], 0x00100000
    jne .Ltp_bad
    mov edx, 20
    cmp dword ptr [rbx + 20], 0
    jne .Ltp_bad
    mov edx, 24
    cmp dword ptr [rbx + 24], 0
    jne .Ltp_bad
    mov edx, 28
    cmp dword ptr [rbx + 28], 0
    jne .Ltp_bad
    mov edx, 12
    mov r13d, [rbx + 12]
    cmp r13, SN_FIELDS_MAX
    ja .Ltp_bad
    mov edx, 16
    cmp r12d, [rbx + 16]
    jne .Ltp_bad
    imul r14, r13, STP_RECORD
    add r14, STP_HEADER
    cmp r14, r12
    ja .Ltp_bad
    lea r15, [rbx + STP_HEADER]
    mov qword ptr [rsp], 0
.Ltp_record:
    test r13, r13
    jz .Ltp_tail
    mov rdx, r15
    sub rdx, rbx
    mov eax, [r15]
    cmp rax, [rsp]
    jbe .Ltp_bad
    cmp rax, SN_FIELDS_MAX
    ja .Ltp_bad
    mov [rsp], rax
    add edx, 20
    cmp dword ptr [r15 + 20], 0
    jne .Ltp_bad
    sub edx, 16
    cmp r14d, [r15 + 4]
    jne .Ltp_bad
    mov [rsp + 8], r14
    add edx, 4
    mov eax, [r15 + 8]
    mov rcx, r12
    sub rcx, r14
    cmp rax, rcx
    ja .Ltp_bad
    mov [rsp + 16], rax
    add r14, rax
    add edx, 4
    cmp r14d, [r15 + 12]
    jne .Ltp_bad
    mov [rsp + 24], r14
    add edx, 4
    mov eax, [r15 + 16]
    mov rcx, r12
    sub rcx, r14
    cmp rax, rcx
    ja .Ltp_bad
    mov [rsp + 32], rax
    add r14, rax
    mov rdi, [rsp + 8]
    add rdi, rbx
    mov rsi, [rsp + 16]
    call snippet_regex_validate
    test eax, eax
    jnz 1f
    add rdx, [rsp + 8]
    jmp .Ltp_bad
1:  mov rdi, [rsp + 24]
    add rdi, rbx
    mov rsi, [rsp + 32]
    call snippet_replacement_validate
    test eax, eax
    jnz 2f
    add rdx, [rsp + 24]
    jmp .Ltp_bad
2:  add r15, STP_RECORD
    dec r13
    jmp .Ltp_record
.Ltp_tail:
    mov edx, 16
    cmp r14, r12
    jne .Ltp_bad
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Ltp_bad:
    xor eax, eax
    EPILOGUE
# copy(raw, bytes) -> ref-counted owned block or 0. Production lengths validated.
FN snippet_transforms_copy
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsi
    add rdi, SC_DATA
    jc 8f
    cmp rdi, 65536
    jae 1f
    mov edi, 65536
1:  call mem_alloc_try
    test rax, rax
    jz 8f
    mov rbx, rax
    mov qword ptr [rax + SC_refs], 1
    mov [rax + SC_bytes], r13
    lea rdi, [rax + SC_DATA]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# freeze(validated SN*, raw, len) -> bool. All failures leave old bindings intact.
FN snippet_transforms_freeze
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    mov rsi, rdx
    call snippet_transforms_validate
    test eax, eax
    jz .Ltfz_bad
    mov r14d, [r12 + 12]
    lea r15, [r12 + STP_HEADER]
    xor ecx, ecx
1:  cmp rcx, r14
    jae .Ltfz_copy
    mov edx, [r15]
    dec rdx
    cmp rdx, [rbx + SN_nfields]
    jae .Ltfz_bad
    imul rax, rdx, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jz .Ltfz_bad
    cmp qword ptr [rax + SF_group], 0
    je .Ltfz_bad
    add r15, STP_RECORD
    inc rcx
    jmp 1b
.Ltfz_copy:
    test r14, r14
    jz .Ltfz_clear
    mov rax, [rbx + SN_choicebytes]
    add rax, [rbx + SN_indentbytes]
    jc .Ltfz_bad
    cmp rax, SN_BYTES_MAX
    ja .Ltfz_bad
    mov ecx, SN_BYTES_MAX
    sub rcx, rax
    cmp r13, rcx
    ja .Ltfz_bad
    mov rdi, r12
    mov rsi, r13
    call snippet_transforms_copy
    test rax, rax
    jz .Ltfz_bad
    mov r12, rax
    jmp .Ltfz_swap
.Ltfz_clear:
    xor r12d, r12d
    xor r13d, r13d
.Ltfz_swap:
    mov r15, [rbx + SN_transform]
    mov [rbx + SN_transform], r12
    mov [rbx + SN_transformbytes], r13
    xor ecx, ecx
1:  cmp rcx, [rbx + SN_nfields]
    jae 2f
    imul rax, rcx, SF_SIZE
    mov qword ptr [rbx + rax + SN_fields + SF_transform], 0
    inc rcx
    jmp 1b
2:  test r12, r12
    jz .Ltfz_release
    lea rdx, [r12 + SC_DATA + STP_HEADER]
    mov ecx, STP_HEADER + 1
3:  test r14, r14
    jz .Ltfz_release
    mov eax, [rdx]
    dec rax
    imul rax, rax, SF_SIZE
    mov [rbx + rax + SN_fields + SF_transform], rcx
    add rdx, STP_RECORD
    add rcx, STP_RECORD
    dec r14
    jmp 3b
.Ltfz_release:
    test r15, r15
    jz 4f
    dec qword ptr [r15 + SC_refs]
    jnz 4f
    mov rdi, r15
    call mem_free
4:  mov eax, 1
    EPILOGUE
.Ltfz_bad:
    xor eax, eax
    EPILOGUE
