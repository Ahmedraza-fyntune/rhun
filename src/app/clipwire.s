# Counted native clipboard text and metadata, independent of platform ownership.
.include "rhun.inc"
.text

# validate(text,len,optional trusted ECM) -> bool. No allocation or mutation.
clip_wire_validate:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp rsi, DOC_MULTI_BYTES_MAX
    ja .Lcw_bad
    test rdi, rdi
    jnz 1f
    test rsi, rsi
    jnz .Lcw_bad
1:  call snippet_utf8_valid
    test eax, eax
    jz .Lcw_bad
    test r13, r13
    jz .Lcw_good
    mov rax, [r13 + ECM_count]
    test rax, rax
    jz .Lcw_bad
    cmp rax, DOC_SELECTIONS_MAX
    ja .Lcw_bad
    cmp r12, [r13 + ECM_total]
    jne .Lcw_bad
    xor r14d, r14d
    xor r15d, r15d
.Lcw_segment:
    cmp r14, [r13 + ECM_count]
    jae .Lcw_good
    mov rax, r14
    shl rax, 4
    lea rax, [r13 + rax + ECM_segments]
    mov rcx, [rax + ECS_offset]
    cmp rcx, r15
    jb .Lcw_bad
    cmp rcx, r12
    ja .Lcw_bad
    mov rdx, r12
    sub rdx, rcx
    mov r15, [rax + ECS_len]
    cmp r15, rdx
    ja .Lcw_bad
    add r15, rcx
    cmp rcx, r12
    je 2f
    movzx eax, byte ptr [rbx + rcx]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lcw_bad
2:  cmp r15, r12
    je 3f
    movzx eax, byte ptr [rbx + r15]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lcw_bad
3:  inc r14
    jmp .Lcw_segment
.Lcw_good:
    mov eax, 1
    EPILOGUE
.Lcw_bad:
    xor eax, eax
    EPILOGUE

# encode(text,len,line0/1,optional trusted ECM) -> owned wire, wirelen; or0,0.
FN clip_wire_encode
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    mov [rsp], rdx
    cmp rdx, 1
    ja .Lcwe_bad
    mov rdx, rcx
    call clip_wire_validate
    test eax, eax
    jz .Lcwe_bad
    mov r14d, CLW_HEADER
    test r13, r13
    jz 1f
    mov rax, [r13 + ECM_count]
    shl rax, 4
    add r14, rax
1:  lea rdi, [r14 + r12]
    mov [rsp + 8], rdi
    call mem_alloc_try
    test rax, rax
    jz .Lcwe_bad
    mov r15, rax
    mov rcx, CLW_MAGIC
    mov [rax], rcx
    mov dword ptr [rax + 8], CLW_VERSION
    mov ecx, [rsp]
    mov [rax + 12], ecx
    mov [rax + 24], r12
    test r13, r13
    jz 2f
    mov rcx, [r13 + ECM_count]
    mov [rax + 16], rcx
    lea rdi, [rax + CLW_HEADER]
    lea rsi, [r13 + ECM_segments]
    mov rdx, r14
    sub rdx, CLW_HEADER
    call memcpy
2:  lea rdi, [r15 + r14]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rax, r15
    mov rdx, [rsp + 8]
    EPILOGUE
.Lcwe_bad:
    xor eax, eax
    xor edx, edx
    EPILOGUE

# decode(wire,len,distinct writable CWB) -> bool. Views borrow the entire input lifetime.
# Caller guarantees the output does not overlap input. No allocation or callbacks.
FN clip_wire_decode
    test rdx, rdx
    jz .Lcwd_return_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    xor esi, esi
    mov edx, CWB_SIZE
    call memset
    cmp r12, CLW_HEADER
    jb .Lcwd_bad
    cmp r12, CLW_MAX
    ja .Lcwd_bad
    test rbx, rbx
    jz .Lcwd_bad
    mov rax, CLW_MAGIC
    cmp [rbx], rax
    jne .Lcwd_bad
    cmp dword ptr [rbx + 8], CLW_VERSION
    jne .Lcwd_bad
    cmp dword ptr [rbx + 12], 1
    ja .Lcwd_bad
    mov r14, [rbx + 16]
    cmp r14, DOC_SELECTIONS_MAX
    ja .Lcwd_bad
    shl r14, 4
    add r14, CLW_HEADER
    cmp r14, r12
    ja .Lcwd_bad
    sub r12, r14
    cmp r12, [rbx + 24]
    jne .Lcwd_bad
    lea r15, [rbx + r14]
    mov rdi, r15
    mov rsi, r12
    xor edx, edx
    cmp qword ptr [rbx + 16], 0
    je 1f
    lea rdx, [rbx + 16]
1:  call clip_wire_validate
    test eax, eax
    jz .Lcwd_bad
    mov [r13 + CWB_text], r15
    mov [r13 + CWB_len], r12
    mov eax, [rbx + 12]
    mov [r13 + CWB_line], rax
    cmp qword ptr [rbx + 16], 0
    je 2f
    lea rax, [rbx + 16]
    mov [r13 + CWB_metadata], rax
2:  mov eax, 1
    EPILOGUE
.Lcwd_bad:
    xor eax, eax
    EPILOGUE
.Lcwd_return_bad:
    xor eax, eax
    ret
