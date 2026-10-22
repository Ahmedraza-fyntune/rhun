# Globs of find-files and search-text (feature files, docs/extensions/v1.1.md; filesearch.s). A
# glob is relative to its folder's root with / between segments: * any run within a segment, **
# any number of segments (or, not followed by /, any run across them), ? one character, [abc]
# [a-z] [!a-z] one byte of a set, {a,b} alternatives (32 at most for a line, no nesting). A glob
# without / matches the base name at any depth (*.rs, Makefile). macOS and Windows ignore ASCII
# case, Linux does not. An exclude matches a path when it matches the path or one of the folders on
# its way, so -node_modules and -target/** leave out everything under them.
#
#   fglob_set(body, len) -> rax the compiled set (mem_free it), or -22 for a line that is not
#     +GLOB or -GLOB or a glob that does not parse, -27 past 64 lines, 1024 bytes a glob or 32
#     alternatives; empty lines are skipped
#   fglob_listed(set, path, len) -> eax 1 when an include (or none) and no exclude matches; set 0
#     lists everything
#   fglob_pruned(set, path, len) -> eax 1 when an exclude matches the folder path: a walk skips it
.include "rhun.inc"

.equ FG_LINES, 64
.equ FG_LINE_MAX, 1024
.equ FG_ALTS, 32
.equ FG_GROUPS, 16
.equ FG_STEPS, 100000           # per match: backtracking past this is no match
.equ FG_INCLUDE, 1
.equ FG_EXCLUDE, 2
# a set: a header (FGS_n entries, FGS_inc of them includes), then the entries: kind byte, a byte
# that is 1 when the glob has a /, its length (2 bytes), its bytes
.equ FGS_n, 0
.equ FGS_inc, 4
.equ FGS_HEAD, 8
.ifdef WINDOWS
.equ FG_ICASE, 1
.else
.ifdef MACOS
.equ FG_ICASE, 1
.else
.equ FG_ICASE, 0
.endif
.endif

.bss
.p2align 3
fg_out: .zero SB_SIZE
fg_steps: .quad 0
fg_ngroups: .quad 0
fg_gstart: .zero 8 * FG_GROUPS   # the byte after a group's {
fg_gend: .zero 8 * FG_GROUPS     # its }
fg_gcount: .zero 8 * FG_GROUPS   # its alternatives
fg_line: .zero FG_LINE_MAX + 8

.text

# FN fglob_set(body, len) -> rax the set or -22 / -27
FN fglob_set
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + rsi]
    lea rdi, [rip + fg_out]
    call sb_clear
    lea rdi, [rip + fg_out]
    mov esi, FGS_HEAD
    call sb_reserve
    mov qword ptr [rax], 0
    add qword ptr [rip + fg_out + SB_len], FGS_HEAD
    xor r15d, r15d              # lines
.Lfs_line:
    cmp rbx, r12
    jae .Lfs_done
    mov r13, rbx
1:  cmp r13, r12
    jae 2f
    cmp byte ptr [r13], 10
    je 2f
    inc r13
    jmp 1b
2:  mov r14, r13                # the line's end without a CR
    cmp r14, rbx
    jbe 3f
    cmp byte ptr [r14 - 1], 13
    jne 3f
    dec r14
3:  cmp r14, rbx
    je .Lfs_skip
    inc r15d
    cmp r15d, FG_LINES
    ja .Lfs_big
    mov rdx, r14
    sub rdx, rbx
    dec rdx                     # the glob after + or -
    jz .Lfs_syntax
    cmp rdx, FG_LINE_MAX
    ja .Lfs_big
    movzx eax, byte ptr [rbx]
    mov edi, FG_INCLUDE
    cmp eax, '+'
    je 4f
    mov edi, FG_EXCLUDE
    cmp eax, '-'
    jne .Lfs_syntax
4:  lea rsi, [rbx + 1]
    call fg_add_line
    test rax, rax
    js 9f
.Lfs_skip:
    lea rbx, [r13 + 1]
    jmp .Lfs_line
.Lfs_done:
    mov rdi, [rip + fg_out + SB_ptr]
    mov rsi, [rip + fg_out + SB_len]
    call mem_dup
    EPILOGUE
.Lfs_syntax:
    mov rax, -22
    EPILOGUE
.Lfs_big:
    mov rax, -27
9:  EPILOGUE

# fg_add_line(kind, glob, len) -> rax 0, or -22 / -27: the glob's alternatives join fg_out
fg_add_line:
    PROLOGUE 16
    mov [rsp], rdi
    mov r12, rsi
    mov r13, rdx
    # brackets closed, groups found
    mov qword ptr [rip + fg_ngroups], 0
    xor ebx, ebx                # index
    xor r14d, r14d              # 1 inside a group
    mov r15d, 1                 # the product of the groups' alternatives
1:  cmp rbx, r13
    jae 6f
    movzx eax, byte ptr [r12 + rbx]
    cmp eax, '['
    jne 2f
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    call fg_class_end
    test rax, rax
    js .Lal_syntax
    mov rbx, rax
    jmp 1b
2:  cmp eax, '{'
    jne 3f
    test r14d, r14d
    jnz .Lal_syntax             # no nesting
    mov rcx, [rip + fg_ngroups]
    cmp rcx, FG_GROUPS
    jae .Lal_big
    lea rdx, [rip + fg_gstart]
    lea rax, [rbx + 1]
    mov [rdx + rcx*8], rax
    lea rdx, [rip + fg_gcount]
    mov qword ptr [rdx + rcx*8], 1
    mov r14d, 1
    inc rbx
    jmp 1b
3:  cmp eax, '}'
    jne 4f
    test r14d, r14d
    jz .Lal_syntax
    mov rcx, [rip + fg_ngroups]
    lea rdx, [rip + fg_gend]
    mov [rdx + rcx*8], rbx
    lea rdx, [rip + fg_gcount]
    mov rax, [rdx + rcx*8]
    imul r15, rax
    cmp r15, FG_ALTS
    ja .Lal_big
    inc qword ptr [rip + fg_ngroups]
    xor r14d, r14d
    inc rbx
    jmp 1b
4:  cmp eax, ','
    jne 5f
    test r14d, r14d
    jz 5f
    mov rcx, [rip + fg_ngroups]
    lea rdx, [rip + fg_gcount]
    inc qword ptr [rdx + rcx*8]
5:  inc rbx
    jmp 1b
6:  test r14d, r14d
    jnz .Lal_syntax
    # each combination of alternatives is an entry
    mov [rsp + 8], r15
    xor r14d, r14d              # the combination
.Lal_combo:
    cmp r14, [rsp + 8]
    jae .Lal_ok
    mov rdi, r14
    call fg_expand              # -> rax its length in fg_line
    mov r15, rax
    # kind, slash, length, bytes
    lea rdi, [rip + fg_out]
    lea rsi, [r15 + 4]
    call sb_reserve
    mov rcx, [rsp]
    mov [rax], cl
    mov byte ptr [rax + 1], 0
    mov [rax + 2], r15w
    xor ecx, ecx
7:  cmp rcx, r15
    jae 8f
    lea rdx, [rip + fg_line]
    movzx edx, byte ptr [rdx + rcx]
    mov [rax + rcx + 4], dl
    cmp edx, '/'
    jne 71f
    mov byte ptr [rax + 1], 1
71: inc rcx
    jmp 7b
8:  lea rcx, [r15 + 4]
    add [rip + fg_out + SB_len], rcx
    mov rax, [rip + fg_out + SB_ptr]
    inc dword ptr [rax + FGS_n]
    cmp qword ptr [rsp], FG_INCLUDE
    jne 81f
    inc dword ptr [rax + FGS_inc]
81: inc r14
    jmp .Lal_combo
.Lal_ok:
    xor eax, eax
    EPILOGUE
.Lal_syntax:
    mov rax, -22
    EPILOGUE
.Lal_big:
    mov rax, -27
    EPILOGUE

# fg_class_end(glob, at, len) -> rax the index after the ] of the class at [, or -1 when unclosed
fg_class_end:
    lea rax, [rsi + 1]
    cmp rax, rdx
    jae 8f
    movzx ecx, byte ptr [rdi + rax]
    cmp ecx, '!'
    je 1f
    cmp ecx, '^'
    jne 2f
1:  inc rax
2:  cmp rax, rdx                # a ] first is one of the set
    jae 8f
    cmp byte ptr [rdi + rax], ']'
    jne 3f
    inc rax
3:  cmp rax, rdx
    jae 8f
    cmp byte ptr [rdi + rax], ']'
    je 4f
    inc rax
    jmp 3b
4:  inc rax
    ret
8:  mov rax, -1
    ret

# fg_expand(combination) -> rax the length of that alternative of the glob (r12, r13) in fg_line
fg_expand:
    PROLOGUE
    mov rbx, rdi
    xor r14d, r14d              # read position in the glob
    xor r15d, r15d              # write position in fg_line
    xor ecx, ecx                # group
1:  cmp rcx, [rip + fg_ngroups]
    jae 5f
    push rcx
    push rcx
    # the text before the group's {
    lea rdx, [rip + fg_gstart]
    mov rdx, [rdx + rcx*8]
    dec rdx
    mov rdi, r14
    mov rsi, rdx
    call fg_copy
    # alternative (combination mod its count)
    mov rcx, [rsp]
    lea rdx, [rip + fg_gcount]
    mov rsi, [rdx + rcx*8]
    mov rax, rbx
    xor edx, edx
    div rsi
    mov rbx, rax
    mov rdi, [rsp]
    mov rsi, rdx
    call fg_alt                 # -> rax start, rdx end
    mov rdi, rax
    mov rsi, rdx
    call fg_copy
    pop rcx
    pop rcx
    lea rdx, [rip + fg_gend]
    mov r14, [rdx + rcx*8]
    inc r14
    inc rcx
    jmp 1b
5:  mov rdi, r14
    mov rsi, r13
    call fg_copy
    mov rax, r15
    EPILOGUE

# fg_copy(from, to): glob bytes [from, to) onto fg_line at r15 (fg_expand's registers)
fg_copy:
    lea rdx, [rip + fg_line]
1:  cmp rdi, rsi
    jae 2f
    movzx eax, byte ptr [r12 + rdi]
    mov [rdx + r15], al
    inc r15
    inc rdi
    jmp 1b
2:  ret

# fg_alt(group, k) -> rax start, rdx end of the group's alternative k in the glob (r12)
fg_alt:
    push rbx
    lea rax, [rip + fg_gstart]
    mov r8, [rax + rdi*8]       # scan position
    lea rax, [rip + fg_gend]
    mov r9, [rax + rdi*8]       # the }
    mov r10, r8                 # this alternative's start
    mov r11, rsi
1:  cmp r8, r9
    jae 4f
    movzx eax, byte ptr [r12 + r8]
    cmp eax, '['
    jne 2f
    push rdi
    push rsi
    mov rdi, r12
    mov rsi, r8
    mov rdx, r9
    call fg_class_end
    pop rsi
    pop rdi
    test rax, rax
    js 4f
    mov r8, rax
    jmp 1b
2:  cmp eax, ','
    jne 3f
    test r11, r11
    jz 4f
    dec r11
    lea r10, [r8 + 1]
3:  inc r8
    jmp 1b
4:  mov rax, r10
    mov rdx, r8
    pop rbx
    ret

# FN fglob_listed(set, path, len) -> eax 1 when the path is listed
FN fglob_listed
    PROLOGUE
    mov eax, 1
    test rdi, rdi
    jz 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp dword ptr [rbx + FGS_inc], 0
    je 3f
    # an include
    lea r14, [rbx + FGS_HEAD]
    mov r15d, [rbx + FGS_n]
1:  test r15d, r15d
    jz 8f
    cmp byte ptr [r14], FG_INCLUDE
    jne 2f
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call fg_entry_match
    test eax, eax
    jnz 3f
2:  movzx eax, word ptr [r14 + 2]
    lea r14, [r14 + rax + 4]
    dec r15d
    jmp 1b
3:  # no exclude for the path or a folder on its way
    lea r14, [rbx + FGS_HEAD]
    mov r15d, [rbx + FGS_n]
4:  test r15d, r15d
    jz 7f
    cmp byte ptr [r14], FG_EXCLUDE
    jne 6f
    xor ecx, ecx
5:  cmp rcx, r13
    ja 6f
    je 51f
    cmp byte ptr [r12 + rcx], '/'
    jne 52f
51: push rcx
    push rcx
    mov rdi, r14
    mov rsi, r12
    mov rdx, rcx
    call fg_entry_match
    pop rcx
    pop rcx
    test eax, eax
    jnz 8f
52: inc rcx
    jmp 5b
6:  movzx eax, word ptr [r14 + 2]
    lea r14, [r14 + rax + 4]
    dec r15d
    jmp 4b
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# FN fglob_pruned(set, path, len) -> eax 1 when an exclude matches the folder
FN fglob_pruned
    PROLOGUE
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov r12, rsi
    mov r13, rdx
    lea r14, [rdi + FGS_HEAD]
    mov r15d, [rdi + FGS_n]
1:  test r15d, r15d
    jz 8f
    cmp byte ptr [r14], FG_EXCLUDE
    jne 2f
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call fg_entry_match
    test eax, eax
    jnz 9f
2:  movzx eax, word ptr [r14 + 2]
    lea r14, [r14 + rax + 4]
    dec r15d
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# fg_entry_match(entry, path, len) -> eax 1 when the entry's glob matches the path (its base name
# for a glob without /)
fg_entry_match:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    test rdx, rdx
    jz 8f
    cmp byte ptr [rbx + 1], 0
    jne 2f
    mov rcx, r13                # the base name
1:  cmp rcx, r12
    jbe 2f
    cmp byte ptr [rcx - 1], '/'
    je 11f
    dec rcx
    jmp 1b
11: mov r12, rcx
2:  mov qword ptr [rip + fg_steps], 0
    lea rdi, [rbx + 4]
    movzx esi, word ptr [rbx + 2]
    add rsi, rdi
    mov rdx, r12
    mov rcx, r13
    call fg_match
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# fg_lower(c) -> eax c with ASCII case folded where the system ignores case
fg_lower:
    mov eax, edi
.if FG_ICASE
    lea ecx, [rdi - 'A']
    cmp ecx, 25
    ja 1f
    add eax, 32
1:
.endif
    ret

# fg_match(p, pend, s, send) -> eax 1 when the text fits the glob
fg_match:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
.Lfm_loop:
    inc qword ptr [rip + fg_steps]
    cmp qword ptr [rip + fg_steps], FG_STEPS
    ja .Lfm_no
    cmp r12, r13
    jae .Lfm_end
    movzx eax, byte ptr [r12]
    cmp eax, '*'
    je .Lfm_star
    cmp eax, '?'
    je .Lfm_one
    cmp eax, '['
    je .Lfm_class
    cmp r14, r15
    jb 1f
    # at the text's end a last /** matches nothing more: src/** takes the folder src too
    cmp eax, '/'
    jne .Lfm_no
    lea rcx, [r12 + 1]
    cmp rcx, r13
    jae .Lfm_no
    cmp byte ptr [rcx], '*'
    jne .Lfm_no
    inc rcx
    cmp rcx, r13
    jae .Lfm_no
    cmp byte ptr [rcx], '*'
    jne .Lfm_no
2:  inc rcx
    cmp rcx, r13
    jae .Lfm_yes
    cmp byte ptr [rcx], '*'
    je 2b
    jmp .Lfm_no
1:  mov edi, eax
    call fg_lower
    mov ebx, eax
    movzx edi, byte ptr [r14]
    call fg_lower
    cmp eax, ebx
    jne .Lfm_no
    inc r12
    inc r14
    jmp .Lfm_loop
.Lfm_end:
    cmp r14, r15
    jne .Lfm_no
.Lfm_yes:
    mov eax, 1
    EPILOGUE
.Lfm_no:
    xor eax, eax
    EPILOGUE
.Lfm_one:
    # one character, not a /
    cmp r14, r15
    jae .Lfm_no
    cmp byte ptr [r14], '/'
    je .Lfm_no
    inc r14
1:  cmp r14, r15
    jae 2f
    movzx eax, byte ptr [r14]
    and eax, 0xc0
    cmp eax, 0x80
    jne 2f
    inc r14
    jmp 1b
2:  inc r12
    jmp .Lfm_loop
.Lfm_class:
    cmp r14, r15
    jae .Lfm_no
    movzx edi, byte ptr [r14]
    cmp edi, '/'
    je .Lfm_no
    call fg_lower
    mov ebx, eax                # the byte
    lea r8, [r12 + 1]
    xor r9d, r9d                # negated
    cmp r8, r13
    jae .Lfm_no
    movzx eax, byte ptr [r8]
    cmp eax, '!'
    je 1f
    cmp eax, '^'
    jne 2f
1:  mov r9d, 1
    inc r8
2:  xor r10d, r10d              # in the set
    mov r11d, 1                 # first
3:  cmp r8, r13
    jae .Lfm_no
    movzx eax, byte ptr [r8]
    cmp eax, ']'
    jne 4f
    test r11d, r11d
    jz 6f
4:  xor r11d, r11d
    mov esi, eax                # low
    mov edx, eax                # high
    inc r8
    lea rcx, [r8 + 1]
    cmp rcx, r13
    jae 5f
    cmp byte ptr [r8], '-'
    jne 5f
    movzx ecx, byte ptr [r8 + 1]
    cmp ecx, ']'
    je 5f
    mov edx, ecx
    add r8, 2
5:  push r8
    push r9
    push r10
    push rdx
    mov edi, esi
    call fg_lower
    mov esi, eax
    pop rdi
    push rsi
    call fg_lower
    pop rsi
    pop r10
    pop r9
    pop r8
    cmp ebx, esi
    jb 3b
    cmp ebx, eax
    ja 3b
    mov r10d, 1
    jmp 3b
6:  inc r8                      # past ]
    cmp r10d, r9d
    je .Lfm_no
    mov r12, r8
    inc r14
    jmp .Lfm_loop
.Lfm_star:
    lea rbx, [r12 + 1]
    cmp rbx, r13
    jae .Lfm_one_star
    cmp byte ptr [rbx], '*'
    jne .Lfm_one_star
    # **: past every *
1:  cmp rbx, r13
    jae .Lfm_yes                # at the end: anything
    cmp byte ptr [rbx], '*'
    jne 2f
    inc rbx
    jmp 1b
2:  cmp byte ptr [rbx], '/'
    jne .Lfm_any
    inc rbx                     # **/: no segment, or after each / of the text
3:  mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fg_match
    test eax, eax
    jnz .Lfm_yes
4:  cmp r14, r15
    jae .Lfm_no
    movzx eax, byte ptr [r14]
    inc r14
    cmp eax, '/'
    jne 4b
    jmp 3b
.Lfm_any:
    # ** before something else: any run, / too
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fg_match
    test eax, eax
    jnz .Lfm_yes
    cmp r14, r15
    jae .Lfm_no
    inc r14
    jmp .Lfm_any
.Lfm_one_star:
    # *: any run within the segment
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fg_match
    test eax, eax
    jnz .Lfm_yes
    cmp r14, r15
    jae .Lfm_no
    cmp byte ptr [r14], '/'
    je .Lfm_no
    inc r14
    jmp .Lfm_one_star
