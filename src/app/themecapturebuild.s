# Isolated worker only. Build a complete counted response from a fully validated request.
.include "rhun.inc"
.include "app/themecapture.inc"
.text
# build(request,len,out{ownedBytes,len},deadline)->primary/cleanup.
# A complete response may contain per-source failures; fatal builder failure leaves out untouched.
FN tc_capture_build
    PROLOGUE 4800
    mov rbx, rdi
    mov r12, rdx
    mov r14, rcx
    mov r15, rsi
    mov rdi, rsp
    xor esi, esi
    mov edx, 4800
    call memset
    test r12, r12
    jz .Ltcb_bad
    test r14, r14
    jle .Ltcb_bad
    mov rdi, rbx
    mov rsi, r15
    call tc_request_validate
    test rax, rax
    js .Ltcb_return_error
    mov edi, TC_OUTPUT_CAP
    call tc_alloc_try
    test rax, rax
    jz .Ltcb_oom
    mov r13, rax
    mov [rsp + 528], rax
    mov rax, 0x0031534552544852
    mov [r13], rax
    mov dword ptr [r13 + 8], 1
    mov dword ptr [r13 + 12], TC_HEADER_SIZE
    mov eax, [rbx + 24]
    mov [r13 + 24], eax
    mov eax, [rbx + 28]
    mov [r13 + 28], eax
    lea rdi, [r13 + 32]
    lea rsi, [rbx + 32]
    mov edx, 64
    call memcpy
    mov dword ptr [r13 + 100], T_COUNT
    mov eax, [rbx + 96]
    mov [rsp + 544], rax
    test rax, rax
    jz .Ltcb_rows
    lea rdi, [rsp + 640]
    lea rsi, [rbx + 256]
    mov rdx, rax
    call memcpy
    mov rax, [rsp + 544]
    mov byte ptr [rsp + 640 + rax], 0
    mov eax, [rbx + 28]
    cmp eax, 3
    jne 1f
    mov eax, 2
1:  mov [rsp + 552], rax
    lea rdi, [rsp + 640]
    mov rsi, rax
    mov rdx, rsp
    mov rcx, r14
    call tc_omarchy_capture
    mov [rsp + 560], rax
    mov [rsp + 568], rdx
    or rax, rdx
    jnz .Ltcb_before_error
    mov qword ptr [rsp + 592], 1
    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 640]
    mov rcx, [rsp + 544]
    call tc_capture_expected
    test rax, rax
    jns .Ltcb_rows
    mov [rsp + 560], rax
    jmp .Ltcb_invalidate_before
.Ltcb_before_error:
    cmp dword ptr [rbx + 104], 0
    je .Ltcb_rows
.Ltcb_invalidate_before:
    mov qword ptr [rsp + 576], 1
.Ltcb_rows:
    mov eax, [rbx + 96]
    lea rax, [rbx + 256 + rax]
    mov [rsp + 608], rax
    lea rax, [r13 + 256 + TC_NAME_CAP]
    mov [rsp + 616], rax
.Ltcb_row_loop:
    mov eax, [rbx + 24]
    cmp [rsp + 624], rax
    jae .Ltcb_after
    mov r15, [rsp + 616]
    mov rax, [rsp + 608]
    mov ecx, [rax]
    mov [r15], ecx
    mov edx, [rax + 4]
    mov [rsp + 632], rdx
    lea rcx, [rax + 16 + rdx]
    mov [rsp + 608], rcx
    cmp qword ptr [rsp + 576], 0
    jne .Ltcb_row_changed
    lea rdi, [rsp + 640]
    lea rsi, [rax + 16]
    call memcpy
    jmp .Ltcb_path_ready
.Ltcb_row_changed:
    mov qword ptr [r15 + 8], -1008
    jmp .Ltcb_row_advance
.Ltcb_path_ready:
    mov rax, [rsp + 632]
    mov byte ptr [rsp + 640 + rax], 0
    lea rdi, [rsp + 640]
    mov esi, TC_THEME_CAP
    lea rdx, [rsp + 480]
    mov rcx, r14
    call tc_file_capture
    mov [r15 + 8], rax
    mov [r15 + 16], rdx
    or rax, rdx
    jnz .Ltcb_row_advance
    mov rax, [rsp + 480]
    mov [rsp + 4736], rax
    mov rax, [rsp + 488]
    mov [r15 + 24], rax
    lea rdi, [r15 + 32]
    lea rsi, [rsp + 496]
    mov edx, 32
    call memcpy
    mov dword ptr [r15 + 64], T_COUNT
    lea rdi, [r15 + TC_RESULT_ROW]
    lea rsi, [r15 + 72]
    lea rdx, [r15 + 68]
    mov rcx, [rsp + 4736]
    mov r8, [rsp + 488]
    xor r9d, r9d
    call theme_parse_into
    test rax, rax
    js .Ltcb_parse_error
    lea rdi, [r15 + TC_RESULT_ROW + TC_PALETTE_SIZE]
    mov rsi, [rsp + 4736]
    mov rdx, [rsp + 488]
    call memcpy
    jmp .Ltcb_row_release
.Ltcb_parse_error:
    mov [r15 + 8], rax
.Ltcb_row_release:
    lea rdi, [rsp + 4736]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 2f
    mov [r15 + 16], rax
2:  mov rax, [r15 + 8]
    or rax, [r15 + 16]
    jz .Ltcb_row_advance
    lea rdi, [r15 + 24]
    xor esi, esi
    mov edx, TC_RESULT_ROW + TC_PALETTE_SIZE - 24
    call memset
.Ltcb_row_advance:
    mov rax, [r15 + 24]
    lea rax, [r15 + TC_RESULT_ROW + TC_PALETTE_SIZE + rax]
    mov [rsp + 616], rax
    inc qword ptr [rsp + 624]
    jmp .Ltcb_row_loop
.Ltcb_after:
    cmp qword ptr [rsp + 552], 0
    je .Ltcb_compact
    mov rax, [rsp + 544]
    lea rdi, [rsp + 640]
    lea rsi, [rbx + 256]
    mov rdx, rax
    call memcpy
    mov rax, [rsp + 544]
    mov byte ptr [rsp + 640 + rax], 0
    lea rdi, [rsp + 640]
    mov rsi, [rsp + 552]
    lea rdx, [rsp + 240]
    mov rcx, r14
    call tc_omarchy_capture
    mov [rsp + 4744], rax
    mov [rsp + 4752], rdx
    test rax, rax
    jns 3f
    cmp qword ptr [rsp + 560], 0
    jne 3f
    mov [rsp + 560], rax
3:  test rdx, rdx
    jns 4f
    cmp qword ptr [rsp + 568], 0
    jne 4f
    mov [rsp + 568], rdx
4:  or rax, rdx
    jnz .Ltcb_after_error
    mov qword ptr [rsp + 600], 1
    mov rdi, rbx
    lea rsi, [rsp + 240]
    lea rdx, [rsp + 640]
    mov rcx, [rsp + 544]
    call tc_capture_expected
    test rax, rax
    jns 5f
    cmp qword ptr [rsp + 560], 0
    jne 40f
    mov [rsp + 560], rax
40: mov qword ptr [rsp + 576], 1
5:  cmp qword ptr [rsp + 592], 0
    je .Ltcb_compact
    lea rdi, [rsp + TOB_proof]
    lea rsi, [rsp + 240 + TOB_proof]
    mov edx, 32
    call memeq
    test eax, eax
    jnz .Ltcb_compact
    cmp qword ptr [rsp + 560], 0
    jne 6f
    mov qword ptr [rsp + 560], -1008
6:  mov qword ptr [rsp + 576], 1
    jmp .Ltcb_compact
.Ltcb_after_error:
    cmp dword ptr [rbx + 104], 0
    je .Ltcb_compact
    mov qword ptr [rsp + 576], 1
.Ltcb_compact:
    lea r15, [r13 + 256]
    mov rax, [rsp + 560]
    mov [r13 + 104], rax
    mov rdx, [rsp + 568]
    mov [r13 + 112], rdx
    or rax, rdx
    jnz 8f
    cmp qword ptr [rsp + 592], 0
    je 8f
    cmp qword ptr [rsp + 600], 0
    je 8f
    mov eax, [rsp + TOB_length]
    mov [r13 + 96], eax
    mov rdi, r15
    mov rsi, [rsp + TOB_name]
    mov rdx, rax
    call memcpy
    add r15, [rsp + TOB_length]
    mov eax, [rsp + TOB_light]
    mov [r13 + 120], eax
    mov eax, [rsp + TOB_presence]
    mov [r13 + 124], eax
    lea rdi, [r13 + 128]
    lea rsi, [rsp + TOB_proof]
    mov edx, 32
    call memcpy
8:  lea rax, [r13 + 256 + TC_NAME_CAP]
    mov [rsp + 608], rax
    mov qword ptr [rsp + 624], 0
.Ltcb_compact_row:
    mov eax, [rbx + 24]
    cmp [rsp + 624], rax
    jae .Ltcb_dispose
    mov rax, [rsp + 608]
    mov rcx, [rax + 24]
    lea rcx, [rax + TC_RESULT_ROW + TC_PALETTE_SIZE + rcx]
    mov [rsp + 616], rcx
    cmp qword ptr [rsp + 576], 0
    je 9f
    mov eax, [rax]
    mov [rsp + 4760], rax
    mov rax, [rsp + 608]
    mov rax, [rax + 16]
    mov [rsp + 4768], rax
    mov rdi, r15
    xor esi, esi
    mov edx, TC_RESULT_ROW + TC_PALETTE_SIZE
    call memset
    mov eax, [rsp + 4760]
    mov [r15], eax
    mov qword ptr [r15 + 8], -1008
    mov rax, [rsp + 4768]
    mov [r15 + 16], rax
    add r15, TC_RESULT_ROW + TC_PALETTE_SIZE
    jmp 10f
9:  mov rdi, r15
    mov rsi, rax
    mov rdx, [rax + 24]
    add rdx, TC_RESULT_ROW + TC_PALETTE_SIZE
    mov [rsp + 4760], rdx
    call memmove
    add r15, [rsp + 4760]
10: mov rax, [rsp + 616]
    mov [rsp + 608], rax
    inc qword ptr [rsp + 624]
    jmp .Ltcb_compact_row
.Ltcb_dispose:
    sub r15, r13
    mov [rsp + 536], r15
    lea rdi, [rsp + TOB_name]
    mov rsi, r14
    call tc_file_release
    mov [rsp + 584], rax
    lea rdi, [rsp + 240 + TOB_name]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 11f
    cmp qword ptr [rsp + 584], 0
    jne 11f
    mov [rsp + 584], rax
11: cmp qword ptr [rsp + 584], 0
    je 12f
    lea rdi, [r13 + 96]
    xor esi, esi
    mov edx, 80
    call memset
    mov dword ptr [r13 + 100], T_COUNT
    mov dword ptr [r13 + 24], 0
    mov rax, [rsp + 584]
    mov [r13 + 168], rax
    mov qword ptr [rsp + 536], 256
12: mov rax, [rsp + 536]
    mov [r13 + 16], rax
    mov [r12], r13
    mov [r12 + 8], rax
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Ltcb_oom:
    mov rax, -12
    jmp .Ltcb_return_error
.Ltcb_bad:
    mov rax, -22
.Ltcb_return_error:
    xor edx, edx
    EPILOGUE

# Expected proof is either the requested proof or the scope1 projection of this same vector.
FN tc_capture_expected
    cmp dword ptr [rdi + 104], 0
    je .Ltce_ok
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + 104]
    cmp rax, [r12 + TOB_scope]
    je 1f
    mov rdi, rdx
    mov rsi, rcx
    mov edx, TC_SCOPE_NAME
    lea rcx, [r12 + TOB_records]
    mov r8, rsp
    call tc_omarchy_proof
    test rax, rax
    js 3f
    mov rdi, rsp
    jmp 2f
1:  lea rdi, [r12 + TOB_proof]
2:  lea rsi, [rbx + 128]
    mov edx, 32
    call memeq
    test eax, eax
    jnz 4f
    mov rax, -1008
3:  EPILOGUE
4:  xor eax, eax
    EPILOGUE
.Ltce_ok:
    xor eax, eax
    ret
