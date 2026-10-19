# testing: the coverage of the last coverage run (test-coverage). Per file, a byte per line: bit 0
# "some range hit it", bit 1 "some range missed it"; both is partly covered (Go blocks that share a
# line). The first message of a new coverage run replaces what an older run left.
.include "rhun.inc"

# a file's coverage
STRUCT
F CF_path, 8            # owned cstr
F CF_lines, 8           # owned bytes, CF_n of them: line L at index L - 1
F CF_n, 8
ENDSTRUCT CF_SIZE
.equ COV_HIT, 1
.equ COV_MISS, 2
.equ COV_SPAN_MSG, 4194304      # lines one message may mark, all its ranges together

.bss
.p2align 3
.globl g_cov_run, g_cov_on
files: .zero VEC_SIZE           # CF records
g_cov_run: .quad 0              # the run they are from, 0 for none
ranges: .quad 0                 # ranges taken from that run so far
apply: .long 0                  # 0 checking a body, 1 applying it
cnt: .zero 16

.data
.p2align 2
g_cov_on: .long 1               # tints show (Show Test Coverage toggles)

.text

# testcover_apply(run, body, len) -> rax 0 when applied, else the error text: "N" LF, then N files
#   "PATH_LEN M" LF PATH and M records "L1 L2 COUNT" LF (lines one-based, inclusive)
FN testcover_apply
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov dword ptr [rip + apply], 0
.Ltc_pass:
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call tsb_begin
    call tsb_line
    test rax, rax
    jz .Ltc_syntax
    mov rdi, rax
    mov rsi, rdx
    call tsb_fields
    cmp eax, 1
    jne .Ltc_syntax
    xor edi, edi
    call tsb_num
    test edx, edx
    jz .Ltc_syntax
    cmp rax, TS_COVER_FILES
    ja .Ltc_toobig
    mov r12, rax                # files
    xor r15d, r15d              # lines marked
    mov qword ptr [rsp + 32], 0 # ranges in this message
    cmp dword ptr [rip + apply], 0
    jne 11f
    # checking: the files and ranges this run would hold
    mov rax, [rbx + TSR_num]
    cmp rax, [rip + g_cov_run]
    jne 1f
    mov rax, [rip + files + VEC_len]
    add rax, r12
    cmp rax, TS_COVER_FILES
    ja .Ltc_toobig
    jmp 1f
11:
    # a new run's data replaces the old
    mov rax, [rbx + TSR_num]
    cmp rax, [rip + g_cov_run]
    je 1f
    call testcover_clear
    mov rax, [rbx + TSR_num]
    mov [rip + g_cov_run], rax
1:  test r12, r12
    jz 6f
    dec r12
    call tsb_line
    test rax, rax
    jz .Ltc_syntax
    mov rdi, rax
    mov rsi, rdx
    call tsb_fields
    cmp eax, 2
    jne .Ltc_syntax
    xor edi, edi
    call tsb_num
    test edx, edx
    jz .Ltc_syntax
    test rax, rax
    jz .Ltc_syntax
    cmp rax, 4095
    ja .Ltc_syntax
    mov r13, rax                # path length
    mov edi, 1
    call tsb_num
    test edx, edx
    jz .Ltc_syntax
    cmp rax, TS_COVER_RANGES
    ja .Ltc_toobig
    mov r14, rax                # records
    mov rdi, r13
    call tsb_take
    test rax, rax
    jz .Ltc_syntax
    mov [rsp + 16], rax
    mov rdi, rax
    mov rsi, r13
    call tsb_oneline
    test eax, eax
    jz .Ltc_syntax
    mov rax, [rsp + 16]
    cmp byte ptr [rax], '/'
    je 2f
    cmp r13, 3                  # C:/ on Windows
    jb .Ltc_syntax
    cmp byte ptr [rax + 1], ':'
    jne .Ltc_syntax
2:  mov qword ptr [rsp + 24], 0 # the file (when applying)
    add [rsp + 32], r14
    cmp dword ptr [rip + apply], 0
    jne 21f
    mov rax, [rsp + 32]
    mov rcx, [rbx + TSR_num]
    cmp rcx, [rip + g_cov_run]
    jne 20f
    add rax, [rip + ranges]
20: cmp rax, TS_COVER_RANGES
    ja .Ltc_toobig
    jmp 3f
21: add [rip + ranges], r14
    mov rdi, [rsp + 16]
    mov rsi, r13
    call file_for
    test rax, rax
    jz .Ltc_toobig
    mov [rsp + 24], rax
3:  test r14, r14
    jz 1b
    dec r14
    call tsb_line
    test rax, rax
    jz .Ltc_syntax
    mov rdi, rax
    mov rsi, rdx
    call tsb_fields
    cmp eax, 3
    jne .Ltc_syntax
    xor edi, edi
    call tsb_num
    test edx, edx
    jz .Ltc_syntax
    test rax, rax
    jz .Ltc_syntax
    mov r13, rax                # L1
    mov edi, 1
    call tsb_num
    test edx, edx
    jz .Ltc_syntax
    cmp rax, r13
    jb .Ltc_syntax
    cmp rax, TS_COVER_LINES
    ja .Ltc_toobig
    mov rcx, rax
    sub rcx, r13
    lea r15, [r15 + rcx + 1]
    cmp r15, COV_SPAN_MSG
    ja .Ltc_toobig
    push rax
    push rax
    mov edi, 2
    call tsb_num
    mov rcx, rax
    pop rax
    pop rsi
    test edx, edx
    jz .Ltc_syntax
    cmp qword ptr [rsp + 24], 0
    je 3b
    mov edx, COV_MISS
    test rcx, rcx
    jz 4f
    mov edx, COV_HIT
4:  mov rdi, [rsp + 24]
    mov rsi, r13
    mov rcx, rax
    call mark
    jmp 3b
6:  call tsb_left
    test rax, rax
    jnz .Ltc_syntax
    cmp dword ptr [rip + apply], 0
    jne 7f
    mov dword ptr [rip + apply], 1
    jmp .Ltc_pass
7:  mov dword ptr [rip + g_dirty], 1
    mov dword ptr [rip + g_ts_dirty], 1
    xor eax, eax
    EPILOGUE
.Ltc_syntax:
    lea rax, [rip + .Le_syntax]
    EPILOGUE
.Ltc_toobig:
    lea rax, [rip + .Le_toobig]
    EPILOGUE

# mark(CF*, l1, bit, l2): lines l1..l2 get the bit (the file's array grows to l2)
mark:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    cmp r14, [rbx + CF_n]
    jbe 2f
    # grow to at least l2, doubling
    mov r15, [rbx + CF_n]
    add r15, r15
    cmp r15, r14
    jae 1f
    mov r15, r14
1:  mov rdi, [rbx + CF_lines]
    mov rsi, r15
    call mem_realloc
    mov [rbx + CF_lines], rax
    mov rdi, rax
    add rdi, [rbx + CF_n]
    xor esi, esi
    mov rdx, r15
    sub rdx, [rbx + CF_n]
    call memset
    mov [rbx + CF_n], r15
2:  mov rax, [rbx + CF_lines]
    lea rcx, [r12 - 1]
3:  cmp rcx, r14
    jae 9f
    or [rax + rcx], r13b
    inc rcx
    jmp 3b
9:  EPILOGUE

# file_for(path, len) -> CF* for that path, added when it has none (0 past 20000 files)
file_for:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + files + VEC_len]
    jae 2f
    imul r14, rbx, CF_SIZE
    add r14, [rip + files + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r14 + CF_path]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r14
    EPILOGUE
2:  cmp qword ptr [rip + files + VEC_len], TS_COVER_FILES
    jae 8f
    lea rdi, [rip + files]
    mov esi, CF_SIZE
    call vec_push
    mov r14, rax
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r14 + CF_path], rax
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# testcover_clear(): no coverage
FN testcover_clear
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + files + VEC_len]
    jae 2f
    imul r12, rbx, CF_SIZE
    add r12, [rip + files + VEC_ptr]
    mov rdi, [r12 + CF_path]
    call mem_free
    mov rdi, [r12 + CF_lines]
    call mem_free
    inc rbx
    jmp 1b
2:  lea rdi, [rip + files]
    call vec_free
    mov qword ptr [rip + g_cov_run], 0
    mov qword ptr [rip + ranges], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# testcover_file(path cstr) -> CF* or 0
FN testcover_file
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + files + VEC_len]
    jae 8f
    imul r13, rbx, CF_SIZE
    add r13, [rip + files + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, [r13 + CF_path]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# testcover_line(CF*, line one-based) -> eax 0 unknown, COV_HIT covered, COV_MISS missed, 3 partly
FN testcover_line
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, [rdi + CF_n]
    ja 9f
    mov rcx, [rdi + CF_lines]
    movzx eax, byte ptr [rcx + rsi - 1]
9:  ret

# testcover_dump(sb, path): print-coverage: "covered=N partial=N missed=N lines=L:C,L:P,L:M..."
FN testcover_dump
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    call testcover_file
    mov r12, rax
    lea rdi, [rip + cnt]
    xor esi, esi
    mov edx, 16
    call memset
    test r12, r12
    jz 3f
    xor r13d, r13d
1:  cmp r13, [r12 + CF_n]
    jae 3f
    mov rax, [r12 + CF_lines]
    movzx eax, byte ptr [rax + r13]
    inc r13
    lea rcx, [rip + cnt]
    inc dword ptr [rcx + rax*4]
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rip + .Lp_covered]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + cnt + 4]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lp_partial]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + cnt + 12]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lp_missed]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + cnt + 8]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lp_lines]
    call sb_push_cstr
    test r12, r12
    jz 9f
    xor r13d, r13d
    xor r14d, r14d              # 1 after the first
4:  cmp r13, [r12 + CF_n]
    jae 9f
    mov rax, [r12 + CF_lines]
    movzx r15d, byte ptr [rax + r13]
    inc r13
    test r15d, r15d
    jz 4b
    test r14d, r14d
    jz 5f
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
5:  mov r14d, 1
    mov rdi, rbx
    mov rsi, r13
    call sb_push_u64
    mov rdi, rbx
    mov esi, ':'
    call sb_push_byte
    lea rax, [rip + .Lcov_letters]
    movzx esi, byte ptr [rax + r15]
    mov rdi, rbx
    call sb_push_byte
    jmp 4b
9:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

.section .rodata
.Le_syntax: .asciz "syntax bad coverage body"
.Le_toobig: .asciz "toobig coverage: 20000 files, 1000000 ranges a run, 1048576 lines a file"
.Lp_covered: .asciz "covered="
.Lp_partial: .asciz " partial="
.Lp_missed: .asciz " missed="
.Lp_lines: .asciz " lines="
.Lcov_letters: .ascii "-CMP"
