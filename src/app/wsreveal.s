# feature reveal (v1.1.md): an extension scrolls a document's view to a place without moving the
# cursor or activating its tab
.include "rhun.inc"

.equ RV_TOP, 0
.equ RV_CENTER, 1
.equ RV_NEAREST, 2
.equ RV_CENTER_OUTSIDE, 3

.text

# rv_shown() -> rax the lines the editor shows (at least 1)
rv_shown:
    mov eax, [rip + g_ed_h]
    xor edx, edx
    mov ecx, [rip + g_lh]
    test ecx, ecx
    jz 1f
    div ecx
1:  test eax, eax
    jnz 2f
    mov eax, 1
2:  ret

# FN ws_reveal(doc, pos, where RV_*): its view so that the position shows: its line at the top, in
# the middle, as little a scroll as needed, or in the middle when it is not shown already. The
# cursor stays where it is; a tab that is not shown keeps the view for when it is
FN ws_reveal
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r14, rax                # its line
    and dword ptr [rbx + DOC_flags], ~(DF_REVEAL | DF_CENTER)   # no cursor reveal undoes it
    cmp r13d, RV_CENTER_OUTSIDE
    jne 1f
    # shown already? (whole lines of the view, unwrapped)
    mov rax, [rbx + DOC_scrolly]
    sar rax, 8
    cmp r14, rax
    jb 11f
    mov r15, rax
    call rv_shown
    add rax, r15
    cmp r14, rax
    jb 9f
11: mov r13d, RV_CENTER
1:  cmp dword ptr [rip + cfg_word_wrap], 0
    jne .Lrv_wrap
    cmp r13d, RV_TOP
    je .Lrv_top
    cmp r13d, RV_CENTER
    jne 2f
    call rv_shown
    shr rax, 1
    mov rcx, r14
    sub rcx, rax
    jns 12f
    xor ecx, ecx
12: shl rcx, 8
    mov [rbx + DOC_scrolly], rcx
    jmp 9f
2:  # nearest: up to it, or down until it is the last line shown
    mov rax, [rbx + DOC_scrolly]
    sar rax, 8
    cmp r14, rax
    jb .Lrv_top
    mov r15, rax
    call rv_shown
    lea rcx, [r15 + rax]
    cmp r14, rcx
    jb 9f
    mov rcx, r14
    sub rcx, rax
    inc rcx
    shl rcx, 8
    mov [rbx + DOC_scrolly], rcx
    jmp 9f
.Lrv_top:
    shl r14, 8
    mov [rbx + DOC_scrolly], r14
    jmp 9f
.Lrv_wrap:
    # wrapped rows: the wrap code places the cursor's row; the cursor stands there meanwhile
    mov rax, [rbx + DOC_cur]
    mov [rsp], rax
    mov [rbx + DOC_cur], r12
    cmp r13d, RV_TOP
    jne 3f
    mov [rbx + DOC_wtop], r14
    mov qword ptr [rbx + DOC_woff], 0
    shl r14, 8
    mov [rbx + DOC_scrolly], r14
    jmp 5f
3:  mov rdi, rbx
    cmp r13d, RV_CENTER
    jne 4f
    call center_wrap
    jmp 5f
4:  call reveal_wrap
5:  mov rax, [rsp]
    mov [rbx + DOC_cur], rax
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE
