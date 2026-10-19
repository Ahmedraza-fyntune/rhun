# Pure Windows cwd-volume parsing, shared by helper capture and editor import.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Ordinary absolute cwd cstr ->root-prefix byte length/RDX uppercase drive or0UNC.
# Errors are negative primary/RDX0. No allocation, filesystem call or API lookup.
FN prep_legacy_cwd_volume
    PROLOGUE
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    cmp rax, 3
    jl .Leplcv_bad
    mov r12, rax
    mov rsi, rax
    mov rdi, rbx
    call ext_validate_text
    test eax, eax
    jz .Leplcv_bad
    cmp byte ptr [rbx + 1], ':'
    jne .Leplcv_unc
    movzx edx, byte ptr [rbx]
    and edx, -33
    lea ecx, [rdx - 'A']
    cmp ecx, 25
    ja .Leplcv_bad
    mov al, [rbx + 2]
    cmp al, '/'
    je .Leplcv_drive
    cmp al, 92
    jne .Leplcv_bad
.Leplcv_drive:
    mov eax, 2
    EPILOGUE
.Leplcv_unc:
    cmp r12, 5
    jb .Leplcv_bad
    mov al, [rbx]
    cmp al, '/'
    je 1f
    cmp al, 92
    jne .Leplcv_bad
1:  mov al, [rbx + 1]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne .Leplcv_bad
2:  mov r13d, 2
.Leplcv_server:
    cmp r13, r12
    jae .Leplcv_bad
    mov al, [rbx + r13]
    cmp al, '/'
    je 3f
    cmp al, 92
    je 3f
    inc r13
    jmp .Leplcv_server
3:  cmp r13, 2
    je .Leplcv_bad
    cmp r13, 3
    jne 4f
    mov al, [rbx + 2]
    cmp al, '.'
    je .Leplcv_bad
    cmp al, '?'
    je .Leplcv_bad
4:  cmp r13, 4
    jne 5f
    cmp word ptr [rbx + 2], 0x2e2e
    je .Leplcv_bad
5:  lea r14, [r13 + 1]
    mov r15, r14
.Leplcv_share:
    cmp r15, r12
    jae 6f
    mov al, [rbx + r15]
    cmp al, '/'
    je 6f
    cmp al, 92
    je 6f
    inc r15
    jmp .Leplcv_share
6:  mov rax, r15
    sub rax, r14
    jz .Leplcv_bad
    cmp rax, 1
    jne 7f
    cmp byte ptr [rbx + r14], '.'
    je .Leplcv_bad
7:  cmp rax, 2
    jne 8f
    cmp word ptr [rbx + r14], 0x2e2e
    je .Leplcv_bad
8:  mov rax, r15
    xor edx, edx
    EPILOGUE
.Leplcv_bad:
    mov rax, -EV_BAD_PATH
    xor edx, edx
    EPILOGUE

# Set exactly once before parsing. The context is copied and normalized in owned memory.
FN prep_legacy_set_context
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rbx + EP_kind], 2
    jne .Leplctx_bad
    cmp qword ptr [rbx + PO_ready], 0
    jne .Leplctx_bad
    cmp qword ptr [rbx + EP_legacy_cwd], 0
    jne .Leplctx_bad
    mov rdi, r12
    call prep_legacy_cwd_volume
    test rax, rax
    js .Leplctx_done
    cmp rdx, r13
    jne .Leplctx_path
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    call prep_owned_dup
    test rax, rax
    jz .Leplctx_po
    mov r12, rax
    xor ecx, ecx
1:  mov al, [r12 + rcx]
    test al, al
    jz 3f
    cmp al, 92
    jne 2f
    mov byte ptr [r12 + rcx], '/'
2:  inc rcx
    jmp 1b
3:  test r15, r15
    jz 4f
    mov [r12], r15b
4:  mov [rbx + EP_legacy_cwd], r12
    mov [rbx + EP_legacy_rootlen], r14
    mov [rbx + EP_legacy_drive], r15
    xor eax, eax
.Leplctx_done:
    EPILOGUE
.Leplctx_po:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Leplctx_path:
    mov rax, -EV_BAD_PATH
    EPILOGUE
.Leplctx_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

# Helper-only capture. Pure import always supplies already captured owned caller context.
FN prep_legacy_capture_context
.ifdef WINDOWS
    PROLOGUE 4112
    mov rbx, rdi
    mov rdi, rsp
    mov esi, 4096
    call win_prep_legacy_cwd
    test rax, rax
    js 9f
    mov rdi, rsp
    call prep_legacy_cwd_volume
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, rsp
    call prep_legacy_set_context
9:  EPILOGUE
.else
    xor eax, eax
    ret
.endif
