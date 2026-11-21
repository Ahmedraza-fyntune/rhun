# Gitignore rules engine for file search (Issue #128)
# Parses and matches .gitignore rules during file search / Quick Open / Find in Files.
# Supports root and nested .gitignore files, wildcards, directory-only rules, and negation (!).
.include "rhun.inc"

.equ GI_KIND_EXCLUDE, 0
.equ GI_KIND_INCLUDE, 1

STRUCT
F GR_kind, 1        # 0 = EXCLUDE, 1 = INCLUDE (!)
F GR_dironly, 1     # 1 if pattern had trailing '/' (matches directories only)
F GR_anchored, 1    # 1 if pattern had leading '/' or '/' in middle
F GR_pad, 1
F GR_depth, 4       # directory depth where rule was loaded
F GR_base_off, 4    # offset in gi_strings for base relpath
F GR_base_len, 4    # length in gi_strings of base relpath
F GR_pat_off, 4     # offset in gi_strings for pattern string
F GR_pat_len, 4     # length of pattern string
ENDSTRUCT GR_SIZE

.equ GI_MAX_STEPS, 100000

.bss
.p2align 3
gi_rules: .zero VEC_SIZE
gi_strings: .zero SB_SIZE
gi_steps: .quad 0

.section .rodata
.Lgi_dot_gitignore: .asciz ".gitignore"
.Lgi_git_exclude:   .asciz ".git/info/exclude"

.text

# gitignore_init(): prepare for a new file search walk
FN gitignore_init
    PROLOGUE
    mov qword ptr [rip + gi_rules + VEC_len], 0
    lea rdi, [rip + gi_strings]
    call sb_clear
    EPILOGUE

# gitignore_free(): release resources when walk is complete
FN gitignore_free
    PROLOGUE
    lea rdi, [rip + gi_rules]
    call vec_free
    lea rdi, [rip + gi_strings]
    call sb_free
    EPILOGUE

# gitignore_enter_dir(abs_dir, rel_dir, rel_len, depth)
# Reads <abs_dir>/.gitignore if present, pushing rules with given depth and base prefix.
FN gitignore_enter_dir
    PROLOGUE 48
    mov [rsp], rdi              # abs_dir
    mov [rsp + 8], rsi          # rel_dir
    mov [rsp + 16], rdx         # rel_len
    mov [rsp + 24], rcx         # depth

    # If depth == 0, check .git/info/exclude first
    test ecx, ecx
    jnz .Lge_check_gitignore
    mov rdi, [rsp]
    lea rsi, [rip + .Lgi_git_exclude]
    call path_join
    mov [rsp + 32], rax
    mov rdi, rax
    call file_read_all
    mov r12, rax                # buffer
    mov r13, rdx                # len
    mov rdi, [rsp + 32]
    call mem_free
    test r12, r12
    jz .Lge_check_gitignore
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp + 8]          # rel_dir
    mov rcx, [rsp + 16]         # rel_len
    mov r8d, [rsp + 24]         # depth
    call gitignore_parse_buf
    mov rdi, r12
    call mem_free

.Lge_check_gitignore:
    mov rdi, [rsp]
    lea rsi, [rip + .Lgi_dot_gitignore]
    call path_join
    mov [rsp + 32], rax
    mov rdi, rax
    call file_read_all
    mov r12, rax
    mov r13, rdx
    mov rdi, [rsp + 32]
    call mem_free
    test r12, r12
    jz .Lge_done

    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp + 8]          # rel_dir
    mov rcx, [rsp + 16]         # rel_len
    mov r8d, [rsp + 24]         # depth
    call gitignore_parse_buf
    mov rdi, r12
    call mem_free

.Lge_done:
    EPILOGUE

# gitignore_leave_dir(depth)
# Pops all rules added at or above the given directory depth.
FN gitignore_leave_dir
    PROLOGUE
    mov edx, edi
    mov r8, [rip + gi_rules + VEC_ptr]
1:  mov rax, [rip + gi_rules + VEC_len]
    test rax, rax
    jz 9f
    dec rax
    imul rcx, rax, GR_SIZE
    add rcx, r8
    cmp [rcx + GR_depth], edx
    jl 9f
    mov [rip + gi_rules + VEC_len], rax
    jmp 1b
9:  EPILOGUE

# gitignore_parse_buf(buf, len, rel_dir, rel_len, depth)
# Parses gitignore file content lines and pushes rules.
FN gitignore_parse_buf
    PROLOGUE 64
    mov [rsp], rdi              # buf
    mov [rsp + 8], rsi          # len
    mov [rsp + 16], rdx         # rel_dir
    mov [rsp + 24], rcx         # rel_len
    mov [rsp + 32], r8d         # depth

    # Record base_off and push base_dir into gi_strings
    mov rax, [rip + gi_strings + SB_len]
    mov [rsp + 40], eax         # base_off
    mov rsi, [rsp + 16]         # rel_dir
    mov rdx, [rsp + 24]         # rel_len
    test rdx, rdx
    jz .Lpb_no_base
    lea rdi, [rip + gi_strings]
    call sb_push
    lea rdi, [rip + gi_strings]
    xor esi, esi
    call sb_push_byte
.Lpb_no_base:

    mov rbx, [rsp]              # current ptr
    mov r12, [rsp]
    add r12, [rsp + 8]          # end ptr

.Lpb_line_loop:
    cmp rbx, r12
    jae .Lpb_done

    # Find line end (\n or r12)
    mov r13, rbx
1:  cmp r13, r12
    jae 2f
    cmp byte ptr [r13], 10
    je 2f
    inc r13
    jmp 1b
2:  mov r14, r13                # r14 = line_end
    # Advance rbx for next iteration (past \n)
    lea rax, [r13 + 1]
    mov [rsp + 48], rax

    # Strip trailing \r
    cmp r14, rbx
    jbe .Lpb_trim_trailing
    cmp byte ptr [r14 - 1], 13
    jne .Lpb_trim_trailing
    dec r14

.Lpb_trim_trailing:
    # Trim trailing spaces and tabs
    cmp r14, rbx
    jbe .Lpb_next_line
    mov al, [r14 - 1]
    cmp al, ' '
    je 3f
    cmp al, 9
    jne .Lpb_trim_leading
3:  dec r14
    jmp .Lpb_trim_trailing

.Lpb_trim_leading:
    # Trim leading spaces and tabs
    cmp rbx, r14
    jae .Lpb_next_line
    mov al, [rbx]
    cmp al, ' '
    je 4f
    cmp al, 9
    jne .Lpb_check_comment
4:  inc rbx
    jmp .Lpb_trim_leading

.Lpb_check_comment:
    cmp rbx, r14
    jae .Lpb_next_line
    cmp byte ptr [rbx], '#'
    je .Lpb_next_line

    # Line has content from rbx to r14
    # Check negation '!'
    mov dword ptr [rsp + 56], GI_KIND_EXCLUDE   # kind
    cmp byte ptr [rbx], '!'
    jne 5f
    mov dword ptr [rsp + 56], GI_KIND_INCLUDE
    inc rbx
    cmp rbx, r14
    jae .Lpb_next_line
    jmp 6f
5:  cmp byte ptr [rbx], '\\'
    jne 6f
    lea rax, [rbx + 1]
    cmp rax, r14
    jae 6f
    mov al, [rbx + 1]
    cmp al, '!'
    je 51f
    cmp al, '#'
    jne 6f
51: inc rbx                     # skip escaping backslash
6:
    # Check directory-only (trailing '/')
    xor eax, eax
    cmp r14, rbx
    jbe .Lpb_next_line
    cmp byte ptr [r14 - 1], '/'
    jne 7f
    mov eax, 1                  # dironly = 1
    dec r14
    cmp rbx, r14
    jae .Lpb_next_line
7:  mov [rsp + 60], eax         # dironly

    # Check anchored (leading '/' or '/' within pattern)
    xor r15d, r15d              # anchored = 0
    cmp byte ptr [rbx], '/'
    jne 8f
    mov r15d, 1                 # anchored = 1
    inc rbx
    cmp rbx, r14
    jae .Lpb_next_line
    jmp .Lpb_save_rule
8:  # Scan for '/' in middle of pattern
    mov rcx, rbx
9:  cmp rcx, r14
    jae .Lpb_save_rule
    cmp byte ptr [rcx], '/'
    jne 91f
    mov r15d, 1
    jmp .Lpb_save_rule
91: inc rcx
    jmp 9b

.Lpb_save_rule:
    # Pattern is from rbx to r14
    mov rdx, r14
    sub rdx, rbx                # pat_len
    jz .Lpb_next_line

    # Save pattern in gi_strings
    mov rax, [rip + gi_strings + SB_len]
    push rax                    # pat_off
    push rdx                    # pat_len
    lea rdi, [rip + gi_strings]
    mov rsi, rbx
    call sb_push
    lea rdi, [rip + gi_strings]
    xor esi, esi
    call sb_push_byte
    pop rdx
    pop rax

    # Push to gi_rules
    push rax                    # pat_off
    push rdx                    # pat_len
    lea rdi, [rip + gi_rules]
    mov esi, GR_SIZE
    call vec_push
    pop rdx                     # pat_len
    pop rcx                     # pat_off

    mov r8b, byte ptr [rsp + 56]
    mov [rax + GR_kind], r8b
    mov r8b, byte ptr [rsp + 60]
    mov [rax + GR_dironly], r8b
    mov [rax + GR_anchored], r15b
    mov byte ptr [rax + GR_pad], 0
    mov r8d, [rsp + 32]
    mov [rax + GR_depth], r8d
    mov r8d, [rsp + 40]
    mov [rax + GR_base_off], r8d
    mov r8d, [rsp + 24]
    mov [rax + GR_base_len], r8d
    mov [rax + GR_pat_off], ecx
    mov [rax + GR_pat_len], edx

.Lpb_next_line:
    mov rbx, [rsp + 48]
    jmp .Lpb_line_loop

.Lpb_done:
    EPILOGUE

# gitignore_is_ignored(rel_path, rel_len, name, is_dir) -> eax 1 if ignored, 0 if included
FN gitignore_is_ignored
    PROLOGUE 32
    mov r12, rdi                # rel_path
    mov r13, rsi                # rel_len
    mov r14, rdx                # name
    mov r15d, ecx               # is_dir

    mov rbx, [rip + gi_rules + VEC_len]
    test rbx, rbx
    jz .Lgii_not_ignored

    mov rdi, r14
    call strlen
    mov [rsp], rax              # name_len

.Lgii_rule_loop:
    test rbx, rbx
    jz .Lgii_not_ignored
    dec rbx

    imul rax, rbx, GR_SIZE
    add rax, [rip + gi_rules + VEC_ptr]
    mov [rsp + 8], rax          # current rule pointer

    # Check dironly: if rule.dironly == 1 and is_dir == 0, cannot match
    cmp byte ptr [rax + GR_dironly], 0
    je .Lgii_check_base
    test r15d, r15d
    jz .Lgii_rule_loop

.Lgii_check_base:
    mov ecx, [rax + GR_base_len]
    test ecx, ecx
    jz .Lgii_base_ok
    cmp r13d, ecx
    jb .Lgii_rule_loop

    # Verify rel_path starts with base_dir
    mov r8, [rip + gi_strings + SB_ptr]
    mov edx, [rax + GR_base_off]
    add r8, rdx
    mov rdi, r12
    mov rsi, rcx
    mov rdx, r8
    call str_eq
    test eax, eax
    jz .Lgii_rule_loop

.Lgii_base_ok:
    mov rax, [rsp + 8]
    mov ecx, [rax + GR_base_len]
    lea r8, [r12 + rcx]         # sub_rel = rel_path + base_len
    mov r9d, r13d
    sub r9d, ecx                # sub_len = rel_len - base_len

    mov r10, [rip + gi_strings + SB_ptr]
    mov edx, [rax + GR_pat_off]
    add r10, rdx                # pattern ptr
    mov edx, [rax + GR_pat_len] # pattern len

    cmp byte ptr [rax + GR_anchored], 0
    jne .Lgii_anchored

    # UNANCHORED:
    # 1. Match against name (basename)
    mov rdi, r10
    mov esi, edx
    mov rdx, r14
    mov rcx, [rsp]              # name_len
    call gi_match
    test eax, eax
    jnz .Lgii_matched

    # 2. Also match against sub_rel
    mov rax, [rsp + 8]
    mov r10, [rip + gi_strings + SB_ptr]
    mov edx, [rax + GR_pat_off]
    add r10, rdx
    mov edx, [rax + GR_pat_len]
    mov ecx, [rax + GR_base_len]
    lea r8, [r12 + rcx]
    mov r9d, r13d
    sub r9d, ecx

    mov rdi, r10
    mov esi, edx
    mov rdx, r8
    mov ecx, r9d
    call gi_match
    test eax, eax
    jnz .Lgii_matched
    jmp .Lgii_rule_loop

.Lgii_anchored:
    # ANCHORED:
    mov rdi, r10
    mov esi, edx
    mov rdx, r8
    mov ecx, r9d
    call gi_match
    test eax, eax
    jz .Lgii_rule_loop

.Lgii_matched:
    mov rax, [rsp + 8]
    movzx eax, byte ptr [rax + GR_kind]
    cmp eax, GI_KIND_INCLUDE
    je .Lgii_not_ignored
    mov eax, 1
    EPILOGUE

.Lgii_not_ignored:
    xor eax, eax
    EPILOGUE

# gi_match(pat, pat_len, str, str_len) -> eax 1 on match, 0 on mismatch
FN gi_match
    PROLOGUE
    mov r12, rdi                # pat
    lea r13, [rdi + rsi]        # pat_end
    mov r14, rdx                # str
    lea r15, [rdx + rcx]        # str_end

.Lgim_loop:
    inc qword ptr [rip + gi_steps]
    cmp qword ptr [rip + gi_steps], GI_MAX_STEPS
    ja .Lgim_no

    cmp r12, r13
    jae .Lgim_end

    movzx eax, byte ptr [r12]
    cmp eax, '*'
    je .Lgim_star
    cmp eax, '?'
    je .Lgim_one
    cmp eax, '['
    je .Lgim_class

    # Literal char match
    cmp r14, r15
    jae .Lgim_no

.ifdef WINDOWS
    or al, 0x20
    mov cl, [r14]
    or cl, 0x20
    cmp al, cl
.else
.ifdef MACOS
    or al, 0x20
    mov cl, [r14]
    or cl, 0x20
    cmp al, cl
.else
    cmp al, [r14]
.endif
.endif
    jne .Lgim_no

    inc r12
    inc r14
    jmp .Lgim_loop

.Lgim_end:
    cmp r14, r15
    jne .Lgim_no
.Lgim_yes:
    mov eax, 1
    EPILOGUE
.Lgim_no:
    xor eax, eax
    EPILOGUE

.Lgim_one:
    # '?' matches any single byte except '/'
    cmp r14, r15
    jae .Lgim_no
    cmp byte ptr [r14], '/'
    je .Lgim_no
    inc r12
    inc r14
    jmp .Lgim_loop

.Lgim_class:
    cmp r14, r15
    jae .Lgim_no
    movzx edi, byte ptr [r14]
    cmp edi, '/'
    je .Lgim_no

    lea r8, [r12 + 1]
    xor r9d, r9d                # negated
    cmp r8, r13
    jae .Lgim_no
    movzx eax, byte ptr [r8]
    cmp eax, '!'
    je 1f
    cmp eax, '^'
    jne 2f
1:  mov r9d, 1
    inc r8
2:  xor r10d, r10d              # matched in set
    mov r11d, 1                 # first char in set
3:  cmp r8, r13
    jae .Lgim_no
    movzx eax, byte ptr [r8]
    cmp eax, ']'
    jne 4f
    test r11d, r11d
    jz 6f
4:  xor r11d, r11d
    mov esi, eax                # range low
    mov edx, eax                # range high
    inc r8
    lea rcx, [r8 + 1]
    cmp rcx, r13
    jae 5f
    cmp byte ptr [r8], '-'
    jne 5f
    cmp byte ptr [r8 + 1], ']'
    je 5f
    movzx edx, byte ptr [r8 + 1]
    add r8, 2
5:  cmp edi, esi
    jb 3b
    cmp edi, edx
    ja 3b
    mov r10d, 1
    jmp 3b
6:  inc r8                      # past ']'
    cmp r10d, r9d
    je .Lgim_no
    mov r12, r8
    inc r14
    jmp .Lgim_loop

.Lgim_star:
    lea rbx, [r12 + 1]
    cmp rbx, r13
    jae .Lgim_one_star
    cmp byte ptr [rbx], '*'
    jne .Lgim_one_star

    # '**':
1:  cmp rbx, r13
    jae .Lgim_yes               # trailing '**' matches everything
    cmp byte ptr [rbx], '*'
    jne 2f
    inc rbx
    jmp 1b
2:  cmp byte ptr [rbx], '/'
    jne .Lgim_any

    # '**/' : match zero or more path segments
    inc rbx
3:  mov rdi, rbx
    mov rsi, r13
    sub rsi, rbx
    mov rdx, r14
    mov rcx, r15
    sub rcx, r14
    call gi_match
    test eax, eax
    jnz .Lgim_yes
4:  cmp r14, r15
    jae .Lgim_no
    movzx eax, byte ptr [r14]
    inc r14
    cmp eax, '/'
    jne 4b
    jmp 3b

.Lgim_any:
    # '**' followed by non-slash
    mov rdi, rbx
    mov rsi, r13
    sub rsi, rbx
    mov rdx, r14
    mov rcx, r15
    sub rcx, r14
    call gi_match
    test eax, eax
    jnz .Lgim_yes
    cmp r14, r15
    jae .Lgim_no
    inc r14
    jmp .Lgim_any

.Lgim_one_star:
    # Single '*': matches within current segment (stops at '/')
    mov rdi, rbx
    mov rsi, r13
    sub rsi, rbx
    mov rdx, r14
    mov rcx, r15
    sub rcx, r14
    call gi_match
    test eax, eax
    jnz .Lgim_yes
    cmp r14, r15
    jae .Lgim_no
    cmp byte ptr [r14], '/'
    je .Lgim_no
    inc r14
    jmp .Lgim_one_star
