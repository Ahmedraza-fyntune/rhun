# The edit tape (src/app/edtape.s): the gravity of tape_shift, positions and line/column points
# moved from older versions through inserts and deletions, and a ring that no longer reaches back.
.include "rhun.inc"
.text
FN main
    PROLOGUE 16
    call pres_enable
    # ---- tape_shift: one case per row of the gravity table ----
    lea r12, [rip + shifts]
1:  cmp qword ptr [r12], -1
    je 2f
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    mov rcx, [r12 + 24]
    mov r8, [r12 + 32]
    call tape_shift
    cmp rax, [r12 + 40]
    jne .Lfail
    add r12, 48
    jmp 1b
2:  lea rdi, [rip + .Lok_shift]
    call log_cstr
    # ---- a document and its edits ----
    call doc_new
    mov rbx, rax
    mov rdi, rbx
    lea rsi, [rip + text]
    mov edx, text_end - text
    call doc_set_text
    mov r13, [rbx + DOC_version]      # the version the old positions belong to
    # "\n\nxx" at the top, "zz" inside "line" of "xxline one" (now line 2), then "ne" deleted from it:
    # "\n\nxxlizz one\nline two\n"
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + two_lines]
    mov ecx, 4
    call raw_insert
    mov rdi, rbx
    mov esi, 4 + 2                    # after "li" of line 3
    lea rdx, [rip + zz]
    mov ecx, 2
    call raw_insert
    mov rdi, rbx
    mov esi, 8                        # "ne": \n \n x x l i z z n e
    mov edx, 2
    call raw_delete
    # byte positions: "one" of line 1 (old 5) and the start of line 2 (old 9)
    mov rdi, rbx
    mov rsi, r13
    mov edx, 5
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, 9                        # 'o'
    jne .Lfail
    mov rdi, rbx
    mov rsi, r13
    mov edx, 9
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, 13
    jne .Lfail
    # the "e" of "line" (old 3) was deleted: to the deletion's start
    mov rdi, rbx
    mov rsi, r13
    mov edx, 3
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, 8
    jne .Lfail
    lea rdi, [rip + .Lok_map]
    call log_cstr
    # line and column points: (1, 2) of old line 2 -> line 3, column 2
    mov rdi, rbx
    mov rsi, r13
    mov edx, 1
    mov ecx, 2
    mov r8d, GR_RIGHT
    call tape_map_lc
    mov r14, rax
    mov rdi, rbx
    mov esi, 3
    call doc_line_start
    add rax, 2
    cmp r14, rax
    jne .Lfail
    # (0, 5), the "o" of old line 0 -> line 2, column 7: position 9
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    mov ecx, 5
    mov r8d, GR_RIGHT
    call tape_map_lc
    cmp rax, 9
    jne .Lfail
    # a column past the line's end is clamped; a newer version than the text fails
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    mov ecx, 99
    mov r8d, GR_RIGHT
    call tape_map_lc
    cmp rax, 12                       # the end of "xxlizz one"
    jne .Lfail
    mov rdi, rbx
    mov rsi, [rbx + DOC_version]
    inc rsi
    mov edx, 1
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, -1
    jne .Lfail
    lea rdi, [rip + .Lok_lc]
    call log_cstr
    # ---- the ring: TAPE_N more edits and the old version is out of reach ----
    mov r15d, TAPE_N
3:  mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + zz]
    mov ecx, 1
    call raw_insert
    dec r15d
    jnz 3b
    mov rdi, rbx
    mov rsi, r13
    mov edx, 5
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, -1
    jne .Lfail
    # the version just before the last TAPE_N edits still maps: 256 bytes were put in front
    mov rdi, rbx
    mov rsi, [rbx + DOC_version]
    sub rsi, TAPE_N
    mov edx, 5
    mov ecx, GR_RIGHT
    call tape_map
    cmp rax, 5 + TAPE_N
    jne .Lfail
    lea rdi, [rip + .Lok_ring]
    call log_cstr
    mov rdi, rbx
    call doc_free
    xor eax, eax
    EPILOGUE
.Lfail:
    lea rdi, [rip + .Lfail_msg]
    call log_cstr
    mov eax, 1
    EPILOGUE

.section .rodata
text: .ascii "line one\nline two\n"
text_end:
two_lines: .ascii "\n\n"
    .ascii "xx"
zz: .ascii "zz"
.p2align 3
# value, pos, del, ins, gravity -> expected
shifts:
    .quad 5, 5, 0, 3, GR_RIGHT, 8       # insert at it: GR_RIGHT moves
    .quad 5, 5, 0, 3, GR_LEFT, 5        # GR_LEFT stays
    .quad 4, 5, 0, 3, GR_RIGHT, 4       # before: stays
    .quad 6, 5, 0, 3, GR_LEFT, 9        # after: moves
    .quad 7, 5, 4, 0, GR_RIGHT, 5       # inside a deletion: to its start
    .quad 9, 5, 4, 0, GR_RIGHT, 5       # at its end: to its start
    .quad 12, 5, 4, 0, GR_LEFT, 8       # after: back
    .quad 5, 5, 4, 0, GR_RIGHT, 5       # at its start: stays
    .quad -1
.Lok_shift: .asciz "ok shift\n"
.Lok_map: .asciz "ok map\n"
.Lok_lc: .asciz "ok lines and columns\n"
.Lok_ring: .asciz "ok ring\n"
.Lfail_msg: .asciz "FAIL\n"
