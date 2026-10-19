# testing: what the test model puts in the editor. Failure messages with a place become problems
# (problems.s): one source per controller ("tests:OWNER/NAME"), rebuilt from the items' last results
# after results change, so the problems and their marks (gutter dot, underline, hover) follow each
# run and go when a test passes or is removed. Gutter glyphs and coverage tints are the editor
# presentation's lanes (later).
.include "rhun.inc"

.bss
.p2align 3
.globl g_ts_marks
g_ts_marks: .long 0             # results changed: the problems are rebuilt at the next tick
.p2align 3
pr: .zero PR_SIZE
key: .zero SB_SIZE
msg: .zero SB_SIZE
path: .zero 4096

.text

# testgutter_item_gone(ext, index): an item went: its problems with it (at the next rebuild)
FN testgutter_item_gone
    mov dword ptr [rip + g_ts_marks], 1
    ret

# testgutter_item_changed(ext, index): an item's range or file changed
FN testgutter_item_changed
    ret

# source_of(TSC*) -> PS*: the controller's problems source
source_of:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + key]
    call sb_clear
    lea rdi, [rip + key]
    lea rsi, [rip + .Lkey]
    call sb_push_cstr
    mov r12, [rbx + TSC_ext]
    lea rdi, [rip + key]
    mov rsi, [r12 + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + key]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + key]
    mov rsi, [r12 + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + key]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    xor esi, esi
    call testmodel_item
    mov rsi, [rax + TSI_label]  # the controller's title
    mov rdi, [rip + key + SB_ptr]
    call problems_source
    EPILOGUE

# testgutter_tick(): the problems again from the results, when they changed
FN testgutter_tick
    PROLOGUE
    cmp dword ptr [rip + g_ts_marks], 0
    je 9f
    mov dword ptr [rip + g_ts_marks], 0
    lea rbx, [rip + g_ts_ctrls]
    xor r12d, r12d
1:  cmp qword ptr [rbx + TSC_ext], 0
    je 4f
    mov rdi, rbx
    call source_of
    mov r13, rax
    mov rdi, rax
    call problems_clear
    mov r14d, 1
2:  cmp r14, [rbx + TSC_items + VEC_len]
    jae 4f
    mov rdi, rbx
    mov rsi, r14
    call testmodel_item
    cmp qword ptr [rax + TSI_id], 0
    je 3f
    mov ecx, [rax + TSI_own]
    cmp ecx, TSS_FAILED
    je 21f
    cmp ecx, TSS_ERRORED
    jne 3f
21: mov rdi, rbx
    mov rsi, r14
    call testmodel_result
    test rax, rax
    jz 3f
    mov rdi, r13
    mov rsi, rax
    mov rdx, rbx
    mov rcx, r14
    call add_messages
3:  inc r14
    jmp 2b
4:  add rbx, TSC_SIZE
    inc r12d
    cmp r12d, TS_CTRL_MAX
    jb 1b
9:  EPILOGUE

# add_messages(PS*, TSE*, tsc, index): a problem per message with a place: "LABEL: first line", then
#   "Expected: …" and "Actual: …" first lines when the message has values
add_messages:
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov r12, [rsi + TSE_msgs + SB_ptr]
    mov r13, [rsi + TSE_msgs + SB_len]
    add r13, r12
1:  cmp r12, r13
    jae 9f
    mov r14, r12                # the header
    lea r15, [r12 + TSM_SIZE]   # the text
    mov eax, [r14 + TSM_text]
    mov ecx, [r14 + TSM_path]
    lea rdx, [r15 + rax]        # the path
    cmp dword ptr [r14 + TSM_l1], 0
    je 8f
    test ecx, ecx
    jz 8f
    cmp ecx, 4000
    jae 8f
    lea rdi, [rip + path]
    mov rsi, rdx
    mov rdx, rcx
    call memcpy
    mov ecx, [r14 + TSM_path]
    lea rax, [rip + path]
    mov byte ptr [rax + rcx], 0
    # the message
    lea rdi, [rip + msg]
    call sb_clear
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call testmodel_item
    mov rsi, [rax + TSI_label]
    lea rdi, [rip + msg]
    call sb_push_cstr
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    mov rdi, r15
    mov esi, [r14 + TSM_text]
    call first_line
    push rdx
    push rdx
    lea rdi, [rip + msg]
    mov rsi, rax
    call sb_push
    pop rdx
    pop rdx
    # the values' first lines
    mov eax, [r14 + TSM_text]
    add eax, [r14 + TSM_path]
    lea r15, [r15 + rax]        # expected
    cmp dword ptr [r14 + TSM_exp], -1
    je 3f
    cmp dword ptr [r14 + TSM_act], -1
    je 3f
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lexpected]
    call sb_push_cstr
    mov rdi, r15
    mov esi, [r14 + TSM_exp]
    call first_line
    lea rdi, [rip + msg]
    mov rsi, rax
    call sb_push
    mov eax, [r14 + TSM_exp]
    add r15, rax                # actual
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lactual]
    call sb_push_cstr
    mov rdi, r15
    mov esi, [r14 + TSM_act]
    call first_line
    lea rdi, [rip + msg]
    mov rsi, rax
    call sb_push
3:  lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    # the problem: its place (an empty range marks the line)
    lea rdi, [rip + pr]
    xor esi, esi
    mov edx, PR_SIZE
    call memset
    lea rax, [rip + path]
    mov [rip + pr + PR_path], rax
    mov eax, [r14 + TSM_l1]
    mov [rip + pr + PR_line], eax
    mov eax, [r14 + TSM_c1]
    mov [rip + pr + PR_col], eax
    mov eax, [r14 + TSM_l1]
    cmp eax, [r14 + TSM_l2]
    jne 4f
    mov eax, [r14 + TSM_c1]
    cmp eax, [r14 + TSM_c2]
    je 5f
4:  mov eax, [r14 + TSM_l2]
    mov [rip + pr + PR_endline], eax
    mov eax, [r14 + TSM_c2]
    mov [rip + pr + PR_endcol], eax
5:  mov dword ptr [rip + pr + PR_sev], SEV_ERROR
    mov rax, [rip + msg + SB_ptr]
    mov [rip + pr + PR_msg], rax
    mov rdi, rbx
    lea rsi, [rip + pr]
    call problems_add
8:  # the next message
    mov eax, TSM_SIZE
    add eax, [r14 + TSM_text]
    add eax, [r14 + TSM_path]
    mov ecx, [r14 + TSM_exp]
    cmp ecx, -1
    je 81f
    add eax, ecx
81: mov ecx, [r14 + TSM_act]
    cmp ecx, -1
    je 82f
    add eax, ecx
82: add r12, rax
    jmp 1b
9:  EPILOGUE

# first_line(ptr, len) -> rax ptr, rdx the length of its first line (at most 200 bytes)
first_line:
    mov rax, rdi
    mov esi, esi
    xor edx, edx
1:  cmp rdx, rsi
    jae 9f
    cmp rdx, 200
    jae 9f
    cmp byte ptr [rax + rdx], 10
    je 9f
    inc rdx
    jmp 1b
9:  ret

# testgutter_forget(ext): its problems go (the extension is removed)
FN testgutter_forget
    PROLOGUE
    call testmodel_ctrl
    test rax, rax
    jz 9f
    mov rdi, rax
    call source_of
    mov rdi, rax
    call problems_clear
9:  EPILOGUE

.section .rodata
.Lkey: .asciz "tests:"
.Lcolon: .asciz ": "
.Lexpected: .asciz "\nExpected: "
.Lactual: .asciz "\nActual: "
