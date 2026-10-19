# workspace edits' file operations (v1.1.md file-operations): create, rename and delete as parts
# of a transaction, with their journal steps, undo and redo, and recovery
.include "rhun.inc"

.text

# FN ws_ops_created(WG*) -> eax 1 when the text group's file is one an earlier create makes (its
# text starts empty)
FN ws_ops_created
    xor eax, eax
    ret

# FN ws_ops_resolve() -> eax 1 when every file operation can be made (0 with ws_code)
FN ws_ops_resolve
    mov eax, 1
    ret

# FN ws_ops_plan(T) -> rax 0 or -errno: the file operations planned in the journal
FN ws_ops_plan
    xor eax, eax
    ret

# FN ws_ops_creates(T) -> rax 0 or -errno: the creates made
FN ws_ops_creates
    xor eax, eax
    ret

# FN ws_ops_moves(T) -> rax 0 or -errno: the renames and deletes made
FN ws_ops_moves
    xor eax, eax
    ret

# FN ws_ops_done(): after file operations: tabs follow, the explorer catches up
FN ws_ops_done
    ret

# FN ws_ops_undo_moves(T) -> rax steps that could not be put back
FN ws_ops_undo_moves
    xor eax, eax
    ret

# FN ws_ops_undo_creates(T) -> rax steps that could not be put back
FN ws_ops_undo_creates
    xor eax, eax
    ret

# FN ws_ops_ready(T, TP, dir) -> eax 1 when a file operation can be undone or redone
FN ws_ops_ready
    mov eax, 1
    ret

# FN ws_ops_step_first(T, dir), ws_ops_step_last(T, dir) -> eax 1 when the picked file
# operations moved (or there were none)
FN ws_ops_step_first
    mov eax, 1
    ret
FN ws_ops_step_last
    mov eax, 1
    ret

# FN ws_recover_steps(plan, len, folder) -> rax files restored, rdx left as they were: the plan's
# steps undone newest first where the disk still shows rhun's result
FN ws_recover_steps
    PROLOGUE 48
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov [rsp], rdx              # the folder
    mov qword ptr [rsp + 8], 0  # restored
    mov qword ptr [rsp + 16], 0 # left
    # the step lines' offsets, oldest first: each "write ..." line and its path line
    lea rdi, [rip + ro_steps]
    call sb_clear
    mov rbx, r12
1:  cmp rbx, r13
    jae 4f
    mov rcx, rbx
2:  cmp rcx, r13
    jae 4f
    cmp byte ptr [rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov r14, rcx                # the line's end
    mov rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    lea rdx, [rip + .Lwrite_sp]
    mov ecx, 6
    call str_starts
    test eax, eax
    jz 31f
    lea rdi, [rip + ro_steps]
    lea rsi, [rsp + 24]
    mov [rsi], rbx
    mov edx, 8
    call sb_push
31: lea rbx, [r14 + 1]
    jmp 1b
4:  # newest first
    mov r15, [rip + ro_steps + SB_len]
5:  test r15, r15
    jz 9f
    sub r15, 8
    mov rax, [rip + ro_steps + SB_ptr]
    mov rbx, [rax + r15]
    # "write SLOT BEFORE AFTER LEN" LF PATH LF
    mov [rip + ps_ptr], rbx
    mov [rip + ps_end], r13
    call ps_line
    test eax, eax
    jz 5b
    call ps_word
    call ps_num
    test edx, edx
    jz 5b
    mov [rsp + 24], rax         # slot
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call parse_hex
    mov [rsp + 32], rax         # before
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call parse_hex
    mov [rsp + 40], rax         # after
    call ps_num
    test edx, edx
    jz 5b
    mov r14, rax
    call ps_eol
    test eax, eax
    jz 5b
    mov rdi, r14
    call lf_take
    test rax, rax
    jz 5b
    mov rdi, rax
    mov rsi, r14
    call mem_dup
    mov r14, rax
    mov rdi, [rsp]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 40]
    mov r8, r14
    call ws_recover_write
    mov r12d, eax
    mov rdi, r14
    call mem_free
    cmp r12d, 1
    jne 6f
    inc qword ptr [rsp + 8]
    jmp 5b
6:  test r12d, r12d
    jnz 5b
    inc qword ptr [rsp + 16]
    jmp 5b
9:  mov rax, [rsp + 8]
    mov rdx, [rsp + 16]
    EPILOGUE

.bss
.p2align 3
ro_steps: .zero SB_SIZE

.section .rodata
.Lwrite_sp: .asciz "write "
