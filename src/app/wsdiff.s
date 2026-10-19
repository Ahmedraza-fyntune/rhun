# unified line diffs of two texts, shown in read-only diff tabs drawn like the git changes view
# (diffview.s): the workspace-edit preview and the diff feature's tabs (v1.1.md, diff)
.include "rhun.inc"

.equ DU_CONTEXT, 3              # lines of context around a change

.bss
.p2align 3
du_seq: .quad 0                 # diff tabs' request numbers (diffview_answer checks DOC_gseq)

.text

# du_starts(text, len, n) -> rax an array of n + 1 offsets: where each of the n lines starts, and
# len (hash_text's lines: a final newline ends the last line)
du_starts:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [r13*8 + 8]
    call mem_alloc
    mov qword ptr [rax], 0
    mov ecx, 1
    xor edx, edx
1:  cmp rdx, r12
    jae 2f
    cmp rcx, r13
    jae 2f
    cmp byte ptr [rbx + rdx], 10
    jne 11f
    lea r8, [rdx + 1]
    mov [rax + rcx*8], r8
    inc rcx
11: inc rdx
    jmp 1b
2:  mov [rax + r13*8], r12
    EPILOGUE

# du_line(sb, sign, text, starts, k): "SIGN" and line k of text (without its newline), then LF
du_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, [rcx + r8*8]       # start
    mov r14, [rcx + r8*8 + 8]   # end
    call sb_push_byte
    cmp r14, r13
    jbe 1f
    cmp byte ptr [r12 + r14 - 1], 10
    jne 1f
    dec r14
1:  mov rdi, rbx
    lea rsi, [r12 + r13]
    mov rdx, r14
    sub rdx, r13
    call sb_push
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# FN diff_unified(sb, name cstr, a, alen, b, blen): the changes from text a to text b appended to sb
# as a unified diff: "diff --git a/NAME b/NAME", then hunks with three lines of context whose
# headers end in NAME; nothing when the texts have the same lines
FN diff_unified
    PROLOGUE 160
    mov [rsp], rdi              # sb
    mov [rsp + 8], rsi          # name
    mov [rsp + 16], rdx         # a
    mov [rsp + 24], rcx         # alen
    mov [rsp + 32], r8          # b
    mov [rsp + 40], r9          # blen
    mov rdi, rdx
    mov rsi, rcx
    lea rdx, [rsp + 48]         # na
    call hash_text
    mov [rsp + 56], rax         # ha
    mov rdi, [rsp + 32]
    mov rsi, [rsp + 40]
    lea rdx, [rsp + 64]         # nb
    call hash_text
    mov [rsp + 72], rax         # hb
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 48]
    call du_starts
    mov [rsp + 80], rax         # la
    mov rdi, [rsp + 32]
    mov rsi, [rsp + 40]
    mov rdx, [rsp + 64]
    call du_starts
    mov [rsp + 88], rax         # lb
    mov rdi, [rsp + 48]
    inc rdi
    call mem_alloc
    mov [rsp + 96], rax         # amark
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp + 48]
    inc rdx
    call memset
    mov rdi, [rsp + 64]
    inc rdi
    call mem_alloc
    mov [rsp + 104], rax        # bmark
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp + 64]
    inc rdx
    call memset
    # common start and end
    mov r12, [rsp + 56]
    mov r13, [rsp + 72]
    xor ebx, ebx                # prefix
1:  cmp rbx, [rsp + 48]
    jae 2f
    cmp rbx, [rsp + 64]
    jae 2f
    mov rax, [r12 + rbx*8]
    cmp rax, [r13 + rbx*8]
    jne 2f
    inc rbx
    jmp 1b
2:  mov r14, [rsp + 48]         # a's end of the middle
    mov r15, [rsp + 64]         # b's
3:  cmp r14, rbx
    jbe 4f
    cmp r15, rbx
    jbe 4f
    mov rax, [r12 + r14*8 - 8]
    cmp rax, [r13 + r15*8 - 8]
    jne 4f
    dec r14
    dec r15
    jmp 3b
4:  lea rdi, [r12 + rbx*8]
    mov rsi, r14
    sub rsi, rbx
    lea rdx, [r13 + rbx*8]
    mov rcx, r15
    sub rcx, rbx
    mov r8, [rsp + 96]
    add r8, rbx
    mov r9, [rsp + 104]
    add r9, rbx
    call diff_lines
    test eax, eax
    jnz 5f
    # too different: the whole middle went and came
    mov rdi, [rsp + 96]
    add rdi, rbx
    mov esi, 1
    mov rdx, r14
    sub rdx, rbx
    call memset
    mov rdi, [rsp + 104]
    add rdi, rbx
    mov esi, 1
    mov rdx, r15
    sub rdx, rbx
    call memset
5:  # the edit script: per step (i | kind << 62, j); kinds 0 kept, 1 went, 2 came
    mov rdi, [rsp + 48]
    add rdi, [rsp + 64]
    inc rdi
    shl rdi, 4
    call mem_alloc
    mov [rsp + 112], rax        # ops
    xor r12d, r12d              # i
    xor r13d, r13d              # j
    xor r14d, r14d              # steps
    mov r8, [rsp + 96]
    mov r9, [rsp + 104]
6:  cmp r12, [rsp + 48]
    jb 61f
    cmp r13, [rsp + 64]
    jae 7f
61: mov rax, [rsp + 112]
    mov rcx, r14
    shl rcx, 4
    add rax, rcx
    mov [rax + 8], r13
    cmp r12, [rsp + 48]
    jae 62f
    cmp byte ptr [r8 + r12], 0
    je 62f
    mov rcx, 1
    shl rcx, 62
    or rcx, r12
    mov [rax], rcx
    inc r12
    inc r14
    jmp 6b
62: cmp r13, [rsp + 64]
    jae 63f
    cmp byte ptr [r9 + r13], 0
    je 63f
    mov rcx, 2
    shl rcx, 62
    or rcx, r12
    mov [rax], rcx
    inc r13
    inc r14
    jmp 6b
63: mov [rax], r12
    inc r12
    inc r13
    inc r14
    jmp 6b
7:  mov [rsp + 120], r14        # the steps
    # the hunks
    mov qword ptr [rsp + 128], 0    # where the last hunk ended
    mov qword ptr [rsp + 136], 0    # the header is written
    xor ebx, ebx                # k
.Lu_find:
    cmp rbx, [rsp + 120]
    jae .Lu_done
    mov rax, [rsp + 112]
    mov rcx, rbx
    shl rcx, 4
    mov rax, [rax + rcx]
    shr rax, 62
    jnz .Lu_hunk
    inc rbx
    jmp .Lu_find
.Lu_hunk:
    # start: three steps of context before, not into the hunk before
    mov r12, rbx
    sub r12, DU_CONTEXT
    jns 1f
    xor r12d, r12d
1:  cmp r12, [rsp + 128]
    jae 2f
    mov r12, [rsp + 128]
2:  # end: past the last change whose next one is more than two contexts away
    mov r13, rbx                # the last change
    mov r14, rbx
3:  inc r14
    cmp r14, [rsp + 120]
    jae 5f
    mov rax, [rsp + 112]
    mov rcx, r14
    shl rcx, 4
    mov rax, [rax + rcx]
    shr rax, 62
    jz 4f
    mov r13, r14
    jmp 3b
4:  mov rax, r14
    sub rax, r13
    cmp rax, 2 * DU_CONTEXT
    jbe 3b
5:  lea r15, [r13 + 1 + DU_CONTEXT]
    cmp r15, [rsp + 120]
    jbe 6f
    mov r15, [rsp + 120]
6:  # the header once, then "@@ -AS,AC +BS,BC @@ NAME"
    cmp qword ptr [rsp + 136], 0
    jne 61f
    mov qword ptr [rsp + 136], 1
    mov rdi, [rsp]
    lea rsi, [rip + .Ldiff_git]
    call sb_push_cstr
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call sb_push_cstr
    mov rdi, [rsp]
    lea rsi, [rip + .Lb]
    call sb_push_cstr
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call sb_push_cstr
    mov rdi, [rsp]
    mov esi, 10
    call sb_push_byte
61: xor ecx, ecx                # a lines, b lines
    xor edx, edx
    mov r8, r12
62: cmp r8, r15
    jae 63f
    mov rax, [rsp + 112]
    mov r9, r8
    shl r9, 4
    mov rax, [rax + r9]
    shr rax, 62
    cmp eax, 2
    je 621f
    inc rcx
621:cmp eax, 1
    je 622f
    inc rdx
622:inc r8
    jmp 62b
63: mov [rsp + 144], rcx
    mov [rsp + 152], rdx
    mov rdi, [rsp]
    lea rsi, [rip + .Lat_minus]
    call sb_push_cstr
    mov rax, [rsp + 112]
    mov rcx, r12
    shl rcx, 4
    mov rsi, [rax + rcx]
    shl rsi, 2
    shr rsi, 2                  # i at the hunk's start
    cmp qword ptr [rsp + 144], 0
    je 64f
    inc rsi
64: mov rdi, [rsp]
    call sb_push_u64
    mov rdi, [rsp]
    mov esi, ','
    call sb_push_byte
    mov rdi, [rsp]
    mov rsi, [rsp + 144]
    call sb_push_u64
    mov rdi, [rsp]
    lea rsi, [rip + .Lplus]
    call sb_push_cstr
    mov rax, [rsp + 112]
    mov rcx, r12
    shl rcx, 4
    mov rsi, [rax + rcx + 8]    # j at the hunk's start
    cmp qword ptr [rsp + 152], 0
    je 65f
    inc rsi
65: mov rdi, [rsp]
    call sb_push_u64
    mov rdi, [rsp]
    mov esi, ','
    call sb_push_byte
    mov rdi, [rsp]
    mov rsi, [rsp + 152]
    call sb_push_u64
    mov rdi, [rsp]
    lea rsi, [rip + .Lat_end]
    call sb_push_cstr
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call sb_push_cstr
    mov rdi, [rsp]
    mov esi, 10
    call sb_push_byte
    # its lines
7:  cmp r12, r15
    jae 8f
    mov rax, [rsp + 112]
    mov rcx, r12
    shl rcx, 4
    mov r8, [rax + rcx]
    mov rdx, r8
    shr rdx, 62
    shl r8, 2
    shr r8, 2                   # i
    cmp edx, 2
    je 72f
    mov rdi, [rsp]
    mov esi, ' '
    cmp edx, 1
    jne 71f
    mov esi, '-'
71: mov rdx, [rsp + 16]
    mov rcx, [rsp + 80]
    call du_line
    jmp 73f
72: mov rax, [rsp + 112]
    mov rcx, r12
    shl rcx, 4
    mov r8, [rax + rcx + 8]     # j
    mov rdi, [rsp]
    mov esi, '+'
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 88]
    call du_line
73: inc r12
    jmp 7b
8:  mov [rsp + 128], r15
    mov rbx, r15
    jmp .Lu_find
.Lu_done:
    mov rdi, [rsp + 56]
    call mem_free
    mov rdi, [rsp + 72]
    call mem_free
    mov rdi, [rsp + 80]
    call mem_free
    mov rdi, [rsp + 88]
    call mem_free
    mov rdi, [rsp + 96]
    call mem_free
    mov rdi, [rsp + 104]
    call mem_free
    mov rdi, [rsp + 112]
    call mem_free
    EPILOGUE

# FN wsdiff_tab(title cstr, text, len, show) -> rax a new read-only diff tab's document showing
# the unified diff text (activated when show is 1, else the active tab stays)
FN wsdiff_tab
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], ecx
    mov rax, [rip + g_tab_cur]
    mov [rsp + 32], rax
    call doc_new
    mov rbx, rax
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov edi, DV_SIZE
    call mem_alloc
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    mov edx, DV_SIZE
    call memset
    mov dword ptr [r12 + DV_flags], DVF_OWN
    mov [rbx + DOC_diff], r12
    mov rdi, [rsp]
    call strlen
    mov rsi, rax
    mov rdi, [rsp]
    call mem_dup
    mov [r12 + DV_name], rax
    mov [rbx + DOC_name], rax
    lea rdi, [rip + .Lempty]
    xor esi, esi
    call mem_dup
    mov [r12 + DV_path], rax
    mov rdi, rbx
    call doc_language_refresh
    mov rdi, rbx
    mov esi, TAB_DOC
    call app_add_tab
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    call wsdiff_show
    cmp dword ptr [rsp + 24], 0
    jne 1f
    # in the background: the tab that was active is again (it moved one place right when the new
    # tab went in before it; app_add_tab puts it after the active one, so the index holds)
    mov rdi, [rsp + 32]
    test rdi, rdi
    js 1f
    call app_activate_tab
1:  mov rax, rbx
    EPILOGUE

# FN wsdiff_show(doc, text, len): a diff tab shows this unified diff (replacing what it showed)
FN wsdiff_show
    PROLOGUE 32
    inc qword ptr [rip + du_seq]
    mov rax, [rip + du_seq]
    mov [rdi + DOC_gseq], eax
    mov qword ptr [rsp], 1
    mov qword ptr [rsp + 8], 0
    mov [rsp + 16], rdi
    mov [rsp + 24], rax
    mov rdi, rsp
    xor ecx, ecx
    call diffview_answer
    EPILOGUE

.section .rodata
.Ldiff_git: .asciz "diff --git a/"
.Lb: .asciz " b/"
.Lat_minus: .asciz "@@ -"
.Lplus: .asciz " +"
.Lat_end: .asciz " @@ "
.Lempty: .asciz ""
