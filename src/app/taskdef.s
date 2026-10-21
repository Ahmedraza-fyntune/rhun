# program and task definitions from the wire (tasks design 3.2): what terminal-open, tasks-set and
# task-run carry, checked whole and turned into a DF (rhun.inc), then into a program for term_run.
#
#   TASK_ID FORM LABEL_LEN CMD_LEN CWD_LEN EXTRA_LEN LF <LABEL><CMD><CWD><EXTRA>
#   EXTRA: records NAME ARGS... LEN LF + LEN bytes: detail, group, default, env, unset, depends,
#   matcher, ready, busy, reveal, output, location; unknown names are skipped
#
#   def_parse(ptr, len, task) -> rax DF*, rcx the bytes it took; or 0 with rdx the reason ("label:
#       1 to 128 bytes of plain text"). task 0: a terminal (TASK_ID "-", no task records)
#   def_free(DF*)
#   def_program(DF*, out PG) -> the program: PGM_argv an owned list (mem_free it), the rest borrowed
#   def_command(DF*, sb): the command as the approval dialog shows it
.include "rhun.inc"

.equ HDR_MAX, 512
.equ LABEL_MAX, 128
.equ CMD_MAX, 4096
.equ ARGV_BYTES, 32768
.equ ARGS_MAX, 64
.equ CWD_MAX, 4096
.equ DETAIL_MAX, 200
.equ ENV_MAX, 64
.equ ENV_BYTES, 32768
.equ NAME_MAX, 64
.equ DEPS_MAX, 16
.equ MATCHER_TEXT_MAX, 4096
.equ LIST_MAX, 64                # offsets kept for a list while parsing

.bss
.p2align 3
why: .zero 256                  # the reason a definition was refused
strs: .zero SB_SIZE             # the strings being collected
env_off: .zero 8 * LIST_MAX     # offsets into strs, made pointers at the end
unset_off: .zero 8 * LIST_MAX
deps_off: .zero 8 * LIST_MAX
n_env: .quad 0
n_unset: .quad 0
n_deps: .quad 0
env_bytes: .quad 0
off_id: .quad 0
off_label: .quad 0
off_detail: .quad 0
off_cmd: .quad 0
off_cwd: .quad 0
words: .zero 16 * 8             # a header or record line's words: (ptr, len)
nwords: .quad 0
cur_df: .quad 0

.text

# ---------------- small helpers ----------------

# split(ptr, len) -> eax the words (at most 8) of a line into words/nwords, split at single spaces
split:
    xor ecx, ecx                # words
    xor edx, edx                # position
    lea r8, [rip + words]
1:  cmp rdx, rsi
    jae 9f
    cmp ecx, 8
    jae 8f
    lea rax, [rdi + rdx]
    mov [r8], rax
    mov r9, rdx
2:  cmp rdx, rsi
    jae 3f
    cmp byte ptr [rdi + rdx], ' '
    je 3f
    inc rdx
    jmp 2b
3:  mov rax, rdx
    sub rax, r9
    mov [r8 + 8], rax
    add r8, 16
    inc ecx
    cmp rdx, rsi
    jae 9f
    inc rdx                     # the space
    cmp rdx, rsi
    jb 1b
    # a line ending in a space has an empty last word
    lea rax, [rdi + rdx]
    mov [r8], rax
    mov qword ptr [r8 + 8], 0
    inc ecx
    jmp 9f
8:  mov ecx, 9                  # too many
9:  mov [rip + nwords], rcx
    mov eax, ecx
    ret

# def_word(i) -> rax ptr, rdx len
def_word:
    lea rax, [rip + words]
    shl rdi, 4
    mov rdx, [rax + rdi + 8]
    mov rax, [rax + rdi]
    ret

# word_num(i) -> rax the decimal number, edx 1 when it is one (1 to 9 digits)
word_num:
    push rbx
    call def_word
    mov rcx, rdx
    xor edx, edx
    test rcx, rcx
    jz 9f
    cmp rcx, 9
    ja 9f
    xor ebx, ebx
    xor r8d, r8d
1:  movzx r9d, byte ptr [rax + r8]
    sub r9d, '0'
    cmp r9d, 9
    ja 9f
    imul rbx, rbx, 10
    add rbx, r9
    inc r8
    cmp r8, rcx
    jb 1b
    mov rax, rbx
    mov edx, 1
9:  pop rbx
    ret

# word_is(i, cstr) -> eax 1 when word i is that text
word_is:
    push rsi
    call def_word
    pop rdi
    xchg rdi, rax               # rdi word, rax cstr
    mov rsi, rdx
    mov rdx, rax
    jmp str_eq_cstr

# strs_add(ptr, len) -> rax the offset in strs of the bytes and a NUL
strs_add:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + strs + SB_len]
    lea rdi, [rip + strs]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + strs]
    xor esi, esi
    call sb_push_byte
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

# id_ok(ptr, len) -> eax 1 for a task id: 1 to 64 bytes of a-z 0-9 _ . -, from a letter or a digit
FN def_id_ok
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, NAME_MAX
    ja 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    jbe 2f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 2f
    test ecx, ecx
    jz 9f                       # not first
    cmp edx, '_'
    je 2f
    cmp edx, '.'
    je 2f
    cmp edx, '-'
    jne 9f
2:  inc rcx
    cmp rcx, rsi
    jb 1b
    mov eax, 1
9:  ret

# env_name_ok(ptr, len) -> eax 1 for [A-Za-z_][A-Za-z0-9_]*, at most 64 bytes
env_name_ok:
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, NAME_MAX
    ja 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    cmp edx, '_'
    je 2f
    mov r8d, edx
    or r8d, 0x20
    sub r8d, 'a'
    cmp r8d, 25
    jbe 2f
    test ecx, ecx
    jz 9f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    ja 9f
2:  inc rcx
    cmp rcx, rsi
    jb 1b
    mov eax, 1
9:  ret

# no_nul_lf(ptr, len) -> eax 1 when the bytes hold no NUL and no LF
no_nul_lf:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 8f
    movzx eax, byte ptr [rdi + rcx]
    test eax, eax
    jz 9f
    cmp eax, 10
    je 9f
    inc rcx
    jmp 1b
8:  mov eax, 1
    ret
9:  xor eax, eax
    ret

# ---------------- parsing ----------------

# def_parse(ptr, len, task) -> rax DF*, rcx bytes taken; 0 and rdx the reason
FN def_parse
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + 56], edx         # task
    mov [rip + is_task], edx
    lea rdi, [rip + strs]
    call sb_clear
    xor eax, eax
    mov [rip + n_env], rax
    mov [rip + n_unset], rax
    mov [rip + n_deps], rax
    mov [rip + env_bytes], rax
    mov edi, DF_SIZE
    call mem_alloc
    mov r15, rax                # the DF
    mov [rip + cur_df], rax
    # the header line
    xor ecx, ecx
1:  cmp rcx, r12
    jae .Ldp_header
    cmp rcx, HDR_MAX
    jae .Ldp_header
    cmp byte ptr [rbx + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov [rsp], rcx              # header bytes
    mov rdi, rbx
    mov rsi, rcx
    call split
    cmp eax, 6
    jne .Ldp_header
    mov edi, 2
    call word_num
    test edx, edx
    jz .Ldp_header
    mov [rsp + 8], rax          # label bytes
    mov edi, 3
    call word_num
    test edx, edx
    jz .Ldp_header
    mov [rsp + 16], rax         # command bytes
    mov edi, 4
    call word_num
    test edx, edx
    jz .Ldp_header
    mov [rsp + 24], rax         # folder bytes
    mov edi, 5
    call word_num
    test edx, edx
    jz .Ldp_header
    mov [rsp + 32], rax         # extra bytes
    # all of it here
    mov rax, [rsp]
    inc rax
    add rax, [rsp + 8]
    add rax, [rsp + 16]
    add rax, [rsp + 24]
    add rax, [rsp + 32]
    cmp rax, r12
    ja .Ldp_short
    mov [rsp + 40], rax         # the whole definition
    # the id
    xor edi, edi
    call def_word
    mov r13, rax
    mov r14, rdx
    cmp dword ptr [rsp + 56], 0
    jne 3f
    cmp r14, 1
    jne .Ldp_id_dash
    cmp byte ptr [r13], '-'
    jne .Ldp_id_dash
    jmp 4f
3:  mov rdi, r13
    mov rsi, r14
    call def_id_ok
    test eax, eax
    jz .Ldp_id
4:  mov rdi, r13
    mov rsi, r14
    call strs_add
    mov [rip + off_id], rax
    # the form
    mov edi, 1
    lea rsi, [rip + .Lw_shell]
    call word_is
    test eax, eax
    jnz 5f
    mov edi, 1
    lea rsi, [rip + .Lw_argv]
    call word_is
    test eax, eax
    jz .Ldp_form
    mov dword ptr [r15 + DF_form], 1
5:  # the label: one line of plain text
    mov rax, [rsp]
    lea r13, [rbx + rax + 1]    # where the fields begin
    mov r14, [rsp + 8]
    test r14, r14
    jz .Ldp_label
    cmp r14, LABEL_MAX
    ja .Ldp_label
    mov rdi, r13
    mov rsi, r14
    call plain_text
    test eax, eax
    jz .Ldp_label
    mov rdi, r13
    mov rsi, r14
    call strs_add
    mov [rip + off_label], rax
    add r13, r14
    # the command
    mov r14, [rsp + 16]
    cmp dword ptr [r15 + DF_form], 0
    jne 6f
    test r14, r14
    jnz 51f
    cmp dword ptr [rsp + 56], 0
    jne .Ldp_cmd                # only a terminal may run the interactive shell
    jmp 52f
51: cmp r14, CMD_MAX
    ja .Ldp_cmd
    mov rdi, r13
    mov rsi, r14
    call plain_text
    test eax, eax
    jz .Ldp_cmd
52: mov rdi, r13
    mov rsi, r14
    call strs_add
    mov [rip + off_cmd], rax
    mov [r15 + DF_cmdlen], r14
    jmp 7f
6:  # argv: 1 to 64 arguments, each ending with its NUL, the first not empty
    test r14, r14
    jz .Ldp_argv
    cmp r14, ARGV_BYTES
    ja .Ldp_argv
    cmp byte ptr [r13 + r14 - 1], 0
    jne .Ldp_argv
    cmp byte ptr [r13], 0
    je .Ldp_argv
    xor ecx, ecx
    xor edx, edx
61: cmp rcx, r14
    jae 62f
    cmp byte ptr [r13 + rcx], 0
    jne 63f
    inc edx
63: inc rcx
    jmp 61b
62: cmp edx, ARGS_MAX
    ja .Ldp_argv
    # kept as they are (their NULs included)
    mov rax, [rip + strs + SB_len]
    mov [rip + off_cmd], rax
    lea rdi, [rip + strs]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    lea rdi, [rip + strs]
    xor esi, esi
    call sb_push_byte
    mov [r15 + DF_cmdlen], r14
7:  add r13, r14
    # the folder
    mov r14, [rsp + 24]
    cmp r14, CWD_MAX
    ja .Ldp_cwd
    mov rdi, r13
    mov rsi, r14
    call no_nul_lf
    test eax, eax
    jz .Ldp_cwd
    mov rdi, r13
    mov rsi, r14
    call strs_add
    mov [rip + off_cwd], rax
    add r13, r14
    lea rax, [rip + .Lempty]
    mov qword ptr [rip + off_detail], -1
    # the extra records
    mov r14, r13
    add r14, [rsp + 32]         # their end
.Ldp_rec:
    cmp r13, r14
    jae .Ldp_done
    mov rcx, r13
8:  cmp rcx, r14
    jae .Ldp_record
    cmp byte ptr [rcx], 10
    je 81f
    inc rcx
    jmp 8b
81: mov [rsp + 48], rcx         # the record's line ends here
    mov rdi, r13
    mov rsi, rcx
    sub rsi, r13
    call split
    cmp eax, 2
    jb .Ldp_record
    cmp eax, 8
    ja .Ldp_record
    lea edi, [rax - 1]
    call word_num
    test edx, edx
    jz .Ldp_record
    mov rcx, [rsp + 48]
    lea r13, [rcx + 1]          # its bytes
    lea rdx, [r13 + rax]
    cmp rdx, r14
    ja .Ldp_record
    mov [rsp + 48], rax         # their length
    mov rdi, r13
    mov rsi, rax
    call record
    test rax, rax
    jnz .Ldp_refuse
    add r13, [rsp + 48]
    jmp .Ldp_rec
.Ldp_done:
    # the strings stay where they are now: pointers into them
    mov rdi, [rip + strs + SB_len]
    call mem_alloc
    mov [r15 + DF_strs], rax
    mov rdi, rax
    mov rsi, [rip + strs + SB_ptr]
    mov rdx, [rip + strs + SB_len]
    call memcpy
    mov rcx, [r15 + DF_strs]
    mov rax, [rip + off_id]
    add rax, rcx
    mov [r15 + DF_id], rax
    mov rax, [rip + off_label]
    add rax, rcx
    mov [r15 + DF_label], rax
    mov rax, [rip + off_cmd]
    add rax, rcx
    mov [r15 + DF_cmd], rax
    mov rax, [rip + off_cwd]
    add rax, rcx
    mov [r15 + DF_cwd], rax
    lea rax, [rip + .Lempty]
    mov rdx, [rip + off_detail]
    cmp rdx, -1
    je 91f
    lea rax, [rcx + rdx]
91: mov [r15 + DF_detail], rax
    lea rdi, [rip + env_off]
    mov rsi, [rip + n_env]
    call make_list
    mov [r15 + DF_env], rax
    lea rdi, [rip + unset_off]
    mov rsi, [rip + n_unset]
    call make_list
    mov [r15 + DF_unset], rax
    lea rdi, [rip + deps_off]
    mov rsi, [rip + n_deps]
    call make_list
    mov [r15 + DF_deps], rax
    # a background task is one with ready patterns; busy needs them
    cmp dword ptr [r15 + DF_nbusy], 0
    je 92f
    cmp dword ptr [r15 + DF_nready], 0
    je .Ldp_busy
92: mov rax, r15
    mov rcx, [rsp + 40]
    EPILOGUE
.Ldp_header:
    lea rax, [rip + .Le_header]
    jmp .Ldp_refuse
.Ldp_short:
    lea rax, [rip + .Le_short]
    jmp .Ldp_refuse
.Ldp_id_dash:
    lea rax, [rip + .Le_id_dash]
    jmp .Ldp_refuse
.Ldp_id:
    lea rax, [rip + .Le_id]
    jmp .Ldp_refuse
.Ldp_form:
    lea rax, [rip + .Le_form]
    jmp .Ldp_refuse
.Ldp_label:
    lea rax, [rip + .Le_label]
    jmp .Ldp_refuse
.Ldp_cmd:
    lea rax, [rip + .Le_cmd]
    jmp .Ldp_refuse
.Ldp_argv:
    lea rax, [rip + .Le_argv]
    jmp .Ldp_refuse
.Ldp_cwd:
    lea rax, [rip + .Le_cwd]
    jmp .Ldp_refuse
.Ldp_record:
    lea rax, [rip + .Le_record]
    jmp .Ldp_refuse
.Ldp_busy:
    lea rax, [rip + .Le_busy]
.Ldp_refuse:
    mov rsi, rax                # the reason
    lea rdi, [rip + why]
    call cstr_copy
    mov rdi, r15
    call def_free
    lea rdx, [rip + why]
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# make_list(offsets, n) -> an owned 0-terminated list of pointers into the DF's strings (r15 the DF)
make_list:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [r12 + 1]
    shl rdi, 3
    call mem_alloc
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    mov rdx, [rbx + rcx*8]
    add rdx, [r15 + DF_strs]
    mov [rax + rcx*8], rdx
    inc rcx
    jmp 1b
2:  mov qword ptr [rax + rcx*8], 0
    pop r13
    pop r12
    pop rbx
    ret

# record(ptr, len) -> 0 taken (or skipped: an unknown name), or the reason (cstr); words/nwords hold
#   its line, cur_df the DF, is_task whether task records may come
record:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rip + nwords]     # NAME ARGS... LEN
    # detail LEN: one line, at most 200 bytes
    xor edi, edi
    lea rsi, [rip + .Lr_detail]
    call word_is
    test eax, eax
    jz 1f
    cmp r13, 2
    jne .Lrc_syntax
    cmp r12, DETAIL_MAX
    ja .Lrc_detail
    mov rdi, rbx
    mov rsi, r12
    call plain_text
    test eax, eax
    jz .Lrc_detail
    mov rdi, rbx
    mov rsi, r12
    call strs_add
    mov [rip + off_detail], rax
    jmp .Lrc_ok
1:  # env NAME LEN
    xor edi, edi
    lea rsi, [rip + .Lr_env]
    call word_is
    test eax, eax
    jz 2f
    cmp r13, 3
    jne .Lrc_syntax
    mov edi, 1
    call def_word
    mov r14, rax
    mov r15, rdx
    mov rdi, rax
    mov rsi, rdx
    call env_name_ok
    test eax, eax
    jz .Lrc_env
    mov rdi, rbx
    mov rsi, r12
    call no_nul_lf
    test eax, eax
    jz .Lrc_env
    mov rax, [rip + n_env]
    cmp rax, ENV_MAX
    jae .Lrc_toomany
    mov rax, [rip + env_bytes]
    add rax, r12
    add rax, r15
    cmp rax, ENV_BYTES
    ja .Lrc_toomany
    mov [rip + env_bytes], rax
    # NAME=value
    mov rax, [rip + strs + SB_len]
    mov rcx, [rip + n_env]
    lea rdx, [rip + env_off]
    mov [rdx + rcx*8], rax
    inc qword ptr [rip + n_env]
    lea rdi, [rip + strs]
    mov rsi, r14
    mov rdx, r15
    call sb_push
    lea rdi, [rip + strs]
    mov esi, '='
    call sb_push_byte
    lea rdi, [rip + strs]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    lea rdi, [rip + strs]
    xor esi, esi
    call sb_push_byte
    mov r15, [rip + cur_df]
    jmp .Lrc_ok
2:  # unset NAME 0
    xor edi, edi
    lea rsi, [rip + .Lr_unset]
    call word_is
    test eax, eax
    jz 3f
    cmp r13, 3
    jne .Lrc_syntax
    test r12, r12
    jnz .Lrc_syntax
    mov edi, 1
    call def_word
    mov r14, rax
    mov r15, rdx
    mov rdi, rax
    mov rsi, rdx
    call env_name_ok
    test eax, eax
    jz .Lrc_env
    mov rax, [rip + n_unset]
    cmp rax, ENV_MAX
    jae .Lrc_toomany
    mov rdi, r14
    mov rsi, r15
    call strs_add
    mov rcx, [rip + n_unset]
    lea rdx, [rip + unset_off]
    mov [rdx + rcx*8], rax
    inc qword ptr [rip + n_unset]
    mov r15, [rip + cur_df]
    jmp .Lrc_ok
3:  # reveal show|focus|silent 0
    xor edi, edi
    lea rsi, [rip + .Lr_reveal]
    call word_is
    test eax, eax
    jz 4f
    cmp r13, 3
    jne .Lrc_syntax
    test r12, r12
    jnz .Lrc_syntax
    xor r14d, r14d
31: lea rax, [rip + reveal_words]
    mov rsi, [rax + r14*8]
    test rsi, rsi
    jz .Lrc_reveal
    mov edi, 1
    call word_is
    test eax, eax
    jnz 32f
    inc r14d
    jmp 31b
32: mov r15, [rip + cur_df]
    mov [r15 + DF_reveal], r14d
    jmp .Lrc_ok
4:  # output 0
    xor edi, edi
    lea rsi, [rip + .Lr_output]
    call word_is
    test eax, eax
    jz 5f
    cmp r13, 2
    jne .Lrc_syntax
    test r12, r12
    jnz .Lrc_syntax
    mov r15, [rip + cur_df]
    mov dword ptr [r15 + DF_output], 1
    jmp .Lrc_ok
5:  # location local 0: the only place 0.18.0 runs programs
    xor edi, edi
    lea rsi, [rip + .Lr_location]
    call word_is
    test eax, eax
    jz 6f
    cmp r13, 3
    jne .Lrc_syntax
    mov edi, 1
    lea rsi, [rip + .Lr_local]
    call word_is
    test eax, eax
    jz .Lrc_location
    jmp .Lrc_ok
6:  # the records of a task
    xor edi, edi
    lea rsi, [rip + .Lr_group]
    call word_is
    test eax, eax
    jnz .Lrc_group
    xor edi, edi
    lea rsi, [rip + .Lr_default]
    call word_is
    test eax, eax
    jnz .Lrc_default
    xor edi, edi
    lea rsi, [rip + .Lr_depends]
    call word_is
    test eax, eax
    jnz .Lrc_depends
    xor edi, edi
    lea rsi, [rip + .Lr_matcher]
    call word_is
    test eax, eax
    jnz .Lrc_matcher
    xor edi, edi
    lea rsi, [rip + .Lr_ready]
    call word_is
    test eax, eax
    jnz .Lrc_ready
    xor edi, edi
    lea rsi, [rip + .Lr_busy]
    call word_is
    test eax, eax
    jnz .Lrc_busyrec
.Lrc_ok:
    mov r15, [rip + cur_df]
    xor eax, eax
    EPILOGUE
.Lrc_task_only:
    lea rax, [rip + .Le_task_only]
    jmp .Lrc_out
.Lrc_group:
    cmp dword ptr [rip + is_task], 0
    je .Lrc_task_only
    cmp r13, 3
    jne .Lrc_syntax
    test r12, r12
    jnz .Lrc_syntax
    mov r15, [rip + cur_df]
    mov edi, 1
    lea rsi, [rip + .Lr_build]
    call word_is
    mov ecx, 1
    test eax, eax
    jnz 1f
    mov edi, 1
    lea rsi, [rip + .Lr_test]
    call word_is
    mov ecx, 2
    test eax, eax
    jz .Lrc_groupword
1:  mov [r15 + DF_group], ecx
    jmp .Lrc_ok
.Lrc_default:
    cmp dword ptr [rip + is_task], 0
    je .Lrc_task_only
    cmp r13, 2
    jne .Lrc_syntax
    test r12, r12
    jnz .Lrc_syntax
    mov r15, [rip + cur_df]
    mov dword ptr [r15 + DF_default], 1
    jmp .Lrc_ok
.Lrc_depends:
    # depends sequence|parallel LEN: 1 to 16 task ids, separated by spaces
    cmp dword ptr [rip + is_task], 0
    je .Lrc_task_only
    cmp r13, 3
    jne .Lrc_syntax
    mov r15, [rip + cur_df]
    mov edi, 1
    lea rsi, [rip + .Lr_sequence]
    call word_is
    mov ecx, 1
    test eax, eax
    jnz 1f
    mov edi, 1
    lea rsi, [rip + .Lr_parallel]
    call word_is
    mov ecx, 2
    test eax, eax
    jz .Lrc_order
1:  mov [r15 + DF_order], ecx
    mov qword ptr [rip + n_deps], 0
    mov rdi, rbx
    mov rsi, r12
    call split
    cmp eax, 8
    ja 3f
    test eax, eax
    jz .Lrc_deps
    # (split keeps 8: more are read again by hand)
3:  xor r14d, r14d              # position
4:  cmp r14, r12
    jae 7f
    mov r13, r14
5:  cmp r14, r12
    jae 6f
    cmp byte ptr [rbx + r14], ' '
    je 6f
    inc r14
    jmp 5b
6:  lea rdi, [rbx + r13]
    mov rsi, r14
    sub rsi, r13
    push rdi
    push rsi
    call def_id_ok
    pop rsi
    pop rdi
    test eax, eax
    jz .Lrc_deps
    cmp qword ptr [rip + n_deps], DEPS_MAX
    jae .Lrc_deps
    call strs_add
    mov rcx, [rip + n_deps]
    lea rdx, [rip + deps_off]
    mov [rdx + rcx*8], rax
    inc qword ptr [rip + n_deps]
    inc r14                     # the space
    jmp 4b
7:  cmp qword ptr [rip + n_deps], 0
    je .Lrc_deps
    jmp .Lrc_ok
.Lrc_matcher:
    # matcher NAME 0 (a built-in) or matcher - LEN (its text); 4 at most
    cmp dword ptr [rip + is_task], 0
    je .Lrc_task_only
    cmp r13, 3
    jne .Lrc_syntax
    mov r15, [rip + cur_df]
    cmp dword ptr [r15 + DF_nmatch], DF_MATCHERS
    jae .Lrc_toomany
    mov edi, 1
    lea rsi, [rip + .Lr_dash]
    call word_is
    test eax, eax
    jnz 2f
    test r12, r12
    jnz .Lrc_syntax
    mov edi, 1
    call def_word
    mov rdi, rax
    mov rsi, rdx
    call matcher_builtin
    test rax, rax
    jz .Lrc_builtin
    mov ecx, [r15 + DF_nmatch]
    mov [r15 + rcx*8 + DF_match], rax
    inc dword ptr [r15 + DF_nmatch]
    jmp .Lrc_ok
2:  cmp r12, MATCHER_TEXT_MAX
    ja .Lrc_toomany
    mov rdi, rbx
    mov rsi, r12
    call matcher_compile
    test rax, rax
    jz 3f
    mov r15, [rip + cur_df]
    mov ecx, [r15 + DF_nmatch]
    mov [r15 + rcx*8 + DF_match], rax
    mov eax, 1
    shl eax, cl
    or [r15 + DF_mown], eax
    inc dword ptr [r15 + DF_nmatch]
    jmp .Lrc_ok
3:  mov rax, rdx                # the matcher's reason
    jmp .Lrc_out
.Lrc_ready:
    lea r14, [rip + .Lr_ready]
    mov r13d, DF_ready
    jmp .Lrc_patterns
.Lrc_busyrec:
    lea r14, [rip + .Lr_busy]
    mov r13d, DF_busy
.Lrc_patterns:
    # ready LEN, busy LEN: one to eight patterns, one per line
    cmp dword ptr [rip + is_task], 0
    je .Lrc_task_only
    cmp qword ptr [rip + nwords], 2
    jne .Lrc_syntax
    mov r15, [rip + cur_df]
    xor r14d, r14d              # position
1:  cmp r14, r12
    jae 4f
    mov rcx, r14
2:  cmp rcx, r12
    jae 3f
    cmp byte ptr [rbx + rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov [rsp], rcx
    lea rdx, [r15 + r13]        # the DF's list
    mov eax, DF_nready
    cmp r13d, DF_ready
    je 31f
    mov eax, DF_nbusy
31: mov ecx, [r15 + rax]
    cmp ecx, DF_PATTERNS
    jae .Lrc_toomany
    mov [rsp + 8], rax
    lea rdi, [rbx + r14]
    mov rsi, [rsp]
    sub rsi, r14
    call tpat_new
    test rax, rax
    jz .Lrc_pattern
    mov r15, [rip + cur_df]
    mov rcx, [rsp + 8]
    mov edx, [r15 + rcx]
    lea r8, [r15 + r13]
    mov [r8 + rdx*8], rax
    inc dword ptr [r15 + rcx]
    mov r14, [rsp]
    inc r14
    jmp 1b
4:  mov eax, DF_nready
    cmp r13d, DF_ready
    je 5f
    mov eax, DF_nbusy
5:  cmp dword ptr [r15 + rax], 0
    je .Lrc_pattern_none
    jmp .Lrc_ok
.Lrc_pattern:
    mov rax, rdx
    jmp .Lrc_out
.Lrc_pattern_none:
    lea rax, [rip + .Le_patterns]
    jmp .Lrc_out
.Lrc_syntax:
    lea rax, [rip + .Le_record]
    jmp .Lrc_out
.Lrc_detail:
    lea rax, [rip + .Le_detail]
    jmp .Lrc_out
.Lrc_env:
    lea rax, [rip + .Le_env]
    jmp .Lrc_out
.Lrc_toomany:
    lea rax, [rip + .Le_toomany]
    jmp .Lrc_out
.Lrc_reveal:
    lea rax, [rip + .Le_reveal]
    jmp .Lrc_out
.Lrc_location:
    lea rax, [rip + .Le_location]
    jmp .Lrc_out
.Lrc_groupword:
    lea rax, [rip + .Le_group]
    jmp .Lrc_out
.Lrc_order:
    lea rax, [rip + .Le_order]
    jmp .Lrc_out
.Lrc_deps:
    lea rax, [rip + .Le_deps]
    jmp .Lrc_out
.Lrc_builtin:
    lea rax, [rip + .Le_builtin]
.Lrc_out:
    mov r15, [rip + cur_df]
    EPILOGUE

# def_free(DF*)
FN def_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    mov rdi, [rbx + DF_strs]
    call mem_free
    mov rdi, [rbx + DF_env]
    call mem_free
    mov rdi, [rbx + DF_unset]
    call mem_free
    mov rdi, [rbx + DF_deps]
    call mem_free
    xor r12d, r12d
1:  cmp r12d, [rbx + DF_nmatch]
    jae 2f
    mov eax, [rbx + DF_mown]
    bt eax, r12d
    jnc 11f
    mov rdi, [rbx + r12*8 + DF_match]
    call matcher_free
11: inc r12d
    jmp 1b
2:  xor r12d, r12d
3:  cmp r12d, DF_PATTERNS
    jae 4f
    mov rdi, [rbx + r12*8 + DF_ready]
    call mem_free
    mov rdi, [rbx + r12*8 + DF_busy]
    call mem_free
    inc r12d
    jmp 3b
4:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

# ---------------- the program ----------------

# def_program(DF*, out PG): the argv (owned list) and the rest pointing into the DF: a shell
#   command runs as /bin/sh -c (PowerShell on Windows), an empty one is the user's interactive shell
FN def_program
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + DF_env]
    mov [r12 + PGM_sets], rax
    mov rax, [rbx + DF_unset]
    mov [r12 + PGM_unsets], rax
    xor eax, eax
    mov rcx, [rbx + DF_cwd]
    cmp byte ptr [rcx], 0
    je 1f
    mov rax, rcx
1:  mov [r12 + PGM_cwd], rax
    cmp dword ptr [rbx + DF_form], 0
    jne 5f
    mov edi, 8 * 6
    call mem_alloc
    mov [r12 + PGM_argv], rax
    mov r13, rax
    mov rcx, [rbx + DF_cmd]
    cmp byte ptr [rcx], 0
    jne 2f
    # the interactive shell, as the terminal panel starts one
    lea rdi, [rip + .Lshell_var]
    call getenv
    test rax, rax
    jz 11f
    cmp byte ptr [rax], 0
    jne 12f
11: lea rax, [rip + .Lsh]
12: mov [r13], rax
    mov qword ptr [r13 + 8], 0
    EPILOGUE
2:  lea rax, [rip + .Lsh]
    mov [r13], rax
.ifdef WINDOWS
    lea rax, [rip + .Lnologo]
    mov [r13 + 8], rax
    lea rax, [rip + .Lnoprofile]
    mov [r13 + 16], rax
    lea rax, [rip + .Lcommand]
    mov [r13 + 24], rax
    mov rax, [rbx + DF_cmd]
    mov [r13 + 32], rax
    mov qword ptr [r13 + 40], 0
.else
    lea rax, [rip + .Ldash_c]
    mov [r13 + 8], rax
    mov rax, [rbx + DF_cmd]
    mov [r13 + 16], rax
    mov qword ptr [r13 + 24], 0
.endif
    EPILOGUE
5:  # argv: the arguments as they came
    mov rdi, [rbx + DF_cmdlen]
    inc rdi
    shl rdi, 3
    call mem_alloc
    mov [r12 + PGM_argv], rax
    mov r13, rax
    mov rcx, [rbx + DF_cmd]
    mov rdx, rcx
    add rdx, [rbx + DF_cmdlen]
6:  cmp rcx, rdx
    jae 8f
    mov [r13], rcx
    add r13, 8
7:  cmp byte ptr [rcx], 0
    je 71f
    inc rcx
    jmp 7b
71: inc rcx
    jmp 6b
8:  mov qword ptr [r13], 0
    EPILOGUE

# def_command(DF*, sb): the command as the approval dialog shows it: a shell command as it is, the
#   arguments joined by spaces, each with blanks or quotes in it in single quotes
FN def_command
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [rbx + DF_form], 0
    jne 2f
    mov rsi, [rbx + DF_cmd]
    cmp byte ptr [rsi], 0
    jne 1f
    lea rsi, [rip + .Linteractive]
1:  mov rdi, r12
    call sb_push_cstr
    EPILOGUE
2:  mov r13, [rbx + DF_cmd]
    mov r14, r13
    add r14, [rbx + DF_cmdlen]
    xor r15d, r15d              # arguments so far
3:  cmp r13, r14
    jae 9f
    test r15d, r15d
    jz 4f
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
4:  inc r15d
    # quoted when it has a blank, a quote or a shell character, or is empty
    xor ecx, ecx
    xor edx, edx
5:  movzx eax, byte ptr [r13 + rcx]
    test eax, eax
    jz 6f
    push rcx
    push rdx
    mov edi, eax
    lea rsi, [rip + .Lspecial]
    call char_in_cstr
    pop rdx
    pop rcx
    or edx, eax
    inc rcx
    jmp 5b
6:  test rcx, rcx
    jnz 61f
    mov edx, 1
61: mov [rsp], edx              # quoted
    test edx, edx
    jz 7f
    mov rdi, r12
    mov esi, 0x27
    call sb_push_byte
7:  # its bytes; in quotes a quote is '\'' (shell quoting the user can paste)
    mov qword ptr [rsp + 8], 0
71: mov rax, [rsp + 8]
    movzx esi, byte ptr [r13 + rax]
    test esi, esi
    jz 74f
    inc qword ptr [rsp + 8]
    cmp esi, 0x27
    jne 73f
    cmp dword ptr [rsp], 0
    je 73f
    mov rdi, r12
    lea rsi, [rip + .Lq_escape]
    call sb_push_cstr
    jmp 71b
73: mov rdi, r12
    call sb_push_byte
    jmp 71b
74: cmp dword ptr [rsp], 0
    je 8f
    mov rdi, r12
    mov esi, 0x27
    call sb_push_byte
8:  mov rdi, r13
    call strlen
    lea r13, [r13 + rax + 1]
    jmp 3b
9:  EPILOGUE

# char_in_cstr(byte, cstr) -> eax 1 when the byte is one of the string's
char_in_cstr:
1:  movzx eax, byte ptr [rsi]
    test eax, eax
    jz 8f
    cmp eax, edi
    je 9f
    inc rsi
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

.section .rodata
.Lempty: .asciz ""
.Lq_escape: .asciz "'\\''"
.Lw_shell: .asciz "shell"
.Lw_argv: .asciz "argv"
.Lr_detail: .asciz "detail"
.Lr_env: .asciz "env"
.Lr_unset: .asciz "unset"
.Lr_reveal: .asciz "reveal"
.Lr_show: .asciz "show"
.Lr_focus: .asciz "focus"
.Lr_silent: .asciz "silent"
.Lr_output: .asciz "output"
.Lr_location: .asciz "location"
.Lr_local: .asciz "local"
.Lr_group: .asciz "group"
.Lr_build: .asciz "build"
.Lr_test: .asciz "test"
.Lr_default: .asciz "default"
.Lr_depends: .asciz "depends"
.Lr_sequence: .asciz "sequence"
.Lr_parallel: .asciz "parallel"
.Lr_matcher: .asciz "matcher"
.Lr_dash: .asciz "-"
.Lr_ready: .asciz "ready"
.Lr_busy: .asciz "busy"
.Lshell_var: .asciz "SHELL"
.ifdef WINDOWS
.Lsh: .asciz "powershell.exe"
.Lnologo: .asciz "-NoLogo"
.Lnoprofile: .asciz "-NoProfile"
.Lcommand: .asciz "-Command"
.else
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.endif
.Linteractive: .asciz "(an interactive shell)"
.Lspecial: .ascii " \t\"'\\$`!*?&|;<>()[]{}#~"
           .byte 0
.Le_header: .asciz "header: TASK_ID FORM LABEL_LEN CMD_LEN CWD_LEN EXTRA_LEN"
.Le_short: .asciz "header: the lengths go past the body"
.Le_id_dash: .asciz "id: a terminal's is -"
.Le_id: .asciz "id: 1 to 64 bytes of a-z 0-9 _ . -, from a letter or digit"
.Le_form: .asciz "form: shell or argv"
.Le_label: .asciz "label: 1 to 128 bytes of plain text"
.Le_cmd: .asciz "command: 1 to 4096 bytes of plain text"
.Le_argv: .asciz "argv: 1 to 64 arguments, each ending with a NUL, the first not empty"
.Le_cwd: .asciz "cwd: at most 4096 bytes, no NUL or LF"
.Le_record: .asciz "record: NAME ARGS... LEN"
.Le_detail: .asciz "detail: one line, at most 200 bytes"
.Le_env: .asciz "env: NAME is [A-Za-z_][A-Za-z0-9_]*, the value one line"
.Le_toomany: .asciz "too many: 64 env, 4 matchers, 8 patterns"
.Le_reveal: .asciz "reveal: show, focus or silent"
.Le_location: .asciz "unsupported location"
.Le_task_only: .asciz "not in a terminal: group, default, depends, matcher, ready, busy"
.Le_group: .asciz "group: build or test"
.Le_order: .asciz "depends: sequence or parallel"
.Le_deps: .asciz "depends: 1 to 16 task ids"
.Le_builtin: .asciz "matcher: go, gcc, rustc, tsc or msbuild"
.Le_patterns: .asciz "ready, busy: 1 to 8 patterns"
.Le_busy: .asciz "busy needs ready"
.p2align 3
reveal_words: .quad .Lr_show, .Lr_focus, .Lr_silent, 0

.data
.globl is_task
is_task: .long 0                # def_parse's task flag, for record
