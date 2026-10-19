# Exact selection-record codec. Publication and package validation are separate operations.
.include "rhun.inc"
.text

# Internal 64-byte lowercase hex ID check, without a NUL scan or allocation.
.Lexi_id:
    test rdi, rdi
    jz .Lexi_invalid
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    sub eax, '0'
    cmp eax, 9
    jbe 2f
    sub eax, 'a' - '0'
    cmp eax, 5
    ja .Lexi_invalid
2:  inc ecx
    cmp ecx, 64
    jb 1b
    mov eax, 1
    ret
.Lexi_invalid:
    xor eax, eax
    ret
.Lexi_zero_id:
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0
    jne .Lexi_invalid
    inc ecx
    cmp ecx, 64
    jb 1b
    mov eax, 1
    ret

# ext_index_check(record, length, expected_generation) -> 1/0. Read-only, exact spans.
FN ext_index_check
    test rdi, rdi
    jz .Lexi_invalid
    cmp rsi, EXI_SIZE
    jne .Lexi_invalid
    test rdx, rdx
    jz .Lexi_invalid
    PROLOGUE
    mov rbx, rdi
    mov rax, 0x0058444958454852 # RHEXIDX plus NUL
    cmp [rbx], rax
    jne .Lexi_check_bad
    cmp dword ptr [rbx + EXI_format], 1
    jne .Lexi_check_bad
    cmp [rbx + EXI_generation], rdx
    jne .Lexi_check_bad
    cmp qword ptr [rbx + EXI_reserved], 0
    jne .Lexi_check_bad
    mov eax, [rbx + EXI_flags]
    cmp eax, EXI_REMOVED
    je .Lexi_check_removed
    cmp eax, EXI_ACTIVE
    jne .Lexi_check_bad
    lea rdi, [rbx + EXI_active]
    call .Lexi_id
    test eax, eax
    jz .Lexi_check_bad
    lea rdi, [rbx + EXI_previous]
    call .Lexi_zero_id
    test eax, eax
    jnz .Lexi_check_ok
    lea rdi, [rbx + EXI_previous]
    call .Lexi_id
    test eax, eax
    jz .Lexi_check_bad
    jmp .Lexi_check_ok
.Lexi_check_removed:
    lea rdi, [rbx + EXI_active]
    call .Lexi_zero_id
    test eax, eax
    jz .Lexi_check_bad
    lea rdi, [rbx + EXI_previous]
    call .Lexi_zero_id
    test eax, eax
    jz .Lexi_check_bad
.Lexi_check_ok:
    mov eax, 1
    EPILOGUE
.Lexi_check_bad:
    xor eax, eax
    EPILOGUE

# ext_index_pack(dst160, generation, flags, active_id, previous_id) -> 1/0.
# ID sources are disjoint readable64-byte spans; NULL previous means absent.
# Removed records require both ID arguments NULL. Rejection leaves dst unchanged.
FN ext_index_pack
    test rdi, rdi
    jz .Lexi_invalid
    test rsi, rsi
    jz .Lexi_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    cmp r13d, EXI_REMOVED
    je .Lexi_pack_removed
    cmp r13d, EXI_ACTIVE
    jne .Lexi_pack_bad
    mov rdi, r14
    call .Lexi_id
    test eax, eax
    jz .Lexi_pack_bad
    test r15, r15
    jz .Lexi_pack_write
    mov rdi, r15
    call .Lexi_id
    test eax, eax
    jz .Lexi_pack_bad
    jmp .Lexi_pack_write
.Lexi_pack_removed:
    test r14, r14
    jnz .Lexi_pack_bad
    test r15, r15
    jnz .Lexi_pack_bad
.Lexi_pack_write:
    mov rdi, rbx
    xor esi, esi
    mov edx, EXI_SIZE
    call memset
    mov rax, 0x0058444958454852
    mov [rbx], rax
    mov dword ptr [rbx + EXI_format], 1
    mov [rbx + EXI_flags], r13d
    mov [rbx + EXI_generation], r12
    cmp r13d, EXI_REMOVED
    je .Lexi_pack_ok
    lea rdi, [rbx + EXI_active]
    mov rsi, r14
    mov edx, 64
    call memcpy
    test r15, r15
    jz .Lexi_pack_ok
    lea rdi, [rbx + EXI_previous]
    mov rsi, r15
    mov edx, 64
    call memcpy
.Lexi_pack_ok:
    mov eax, 1
    EPILOGUE
.Lexi_pack_bad:
    xor eax, eax
    EPILOGUE

# ext_index_filename_parse(ptr, len) -> positive generation or 0.
FN ext_index_filename_parse
    test rdi, rdi
    jz .Lexi_invalid
    cmp rsi, EXI_FILENAME_LEN
    jne .Lexi_invalid
    cmp dword ptr [rdi + 16], 0x7864692e # .idx
    jne .Lexi_invalid
    xor eax, eax
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    sub edx, '0'
    cmp edx, 9
    jbe 2f
    sub edx, 'a' - '0'
    cmp edx, 5
    ja .Lexi_invalid
    add edx, 10
2:  shl rax, 4
    or rax, rdx
    inc ecx
    cmp ecx, 16
    jb 1b
    ret

# ext_index_filename_format(dst21, positive_generation) -> 1/0.
FN ext_index_filename_format
    test rdi, rdi
    jz .Lexi_invalid
    test rsi, rsi
    jz .Lexi_invalid
    mov rax, rsi
    lea r8, [rip + hexdigits]
    mov ecx, 16
1:  dec ecx
    mov edx, eax
    and edx, 15
    mov r9b, [r8 + rdx]
    mov [rdi + rcx], r9b
    shr rax, 4
    test ecx, ecx
    jnz 1b
    mov dword ptr [rdi + 16], 0x7864692e
    mov byte ptr [rdi + 20], 0
    mov eax, 1
    ret
