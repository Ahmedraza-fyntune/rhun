# the debug adapter's reverse request runInTerminal: the program it names runs in a terminal tab
# (the tasks group's term_run), so the user can type to it; the answer carries its pid once it
# started. dap.s dispatches reverse requests here.
.include "rhun.inc"

.equ RIT_ARGS_MAX, 1024         # argv words
.equ RIT_ENV_MAX, 1024          # env entries

.text

# dap_run_in_terminal(ds, request seq, arguments JV*): {kind, title, cwd, args: [...], env: {...}}.
#   An env value that is null unsets the name. The tab opens with the keyboard, as the program reads
#   what the user types; the answer goes out from rit_event
FN dap_run_in_terminal
    PROLOGUE 96
    mov rbx, rdi
    mov [rsp], rsi              # seq
    mov r12, rdx                # arguments
    xor eax, eax
    mov [rsp + 8], rax          # argv
    mov [rsp + 16], rax         # sets
    mov [rsp + 24], rax         # unsets
    mov [rsp + 32], rax         # cwd
    mov [rsp + 40], rax         # title
    # argv: the args strings
    mov rdi, r12
    lea rsi, [rip + .Lk_args]
    call json_get
    mov r13, rax
    mov rdi, rax
    call json_len
    mov r14, rax
    test r14, r14
    jz .Lrit_noargs
    cmp r14, RIT_ARGS_MAX
    ja .Lrit_noargs
    lea rdi, [r14*8 + 8]
    call mem_alloc
    mov [rsp + 8], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [r14*8 + 8]
    call memset                 # an early end frees only what was filled
    xor r15d, r15d
1:  cmp r15, r14
    jae 2f
    mov rdi, r13
    mov rsi, r15
    call json_at
    mov rdi, rax
    call json_str
    test rax, rax
    jz .Lrit_noargs             # not a string
    mov rdi, rax
    mov rsi, rdx
    call dupz
    mov rcx, [rsp + 8]
    mov [rcx + r15*8], rax
    inc r15
    jmp 1b
2:  mov rcx, [rsp + 8]
    mov qword ptr [rcx + r15*8], 0
    # env: NAME=value sets, null unsets
    mov rdi, r12
    lea rsi, [rip + .Lk_env]
    call json_get
    mov r13, rax
    mov rdi, rax
    call json_npairs
    mov r14, rax
    cmp r14, RIT_ENV_MAX
    jbe 3f
    mov r14d, RIT_ENV_MAX
3:  lea rdi, [r14*8 + 8]
    call mem_alloc
    mov [rsp + 16], rax
    lea rdi, [r14*8 + 8]
    call mem_alloc
    mov [rsp + 24], rax
    xor r15d, r15d
    mov qword ptr [rsp + 48], 0     # sets so far
    mov qword ptr [rsp + 56], 0     # unsets so far
4:  cmp r15, r14
    jae 6f
    mov rdi, r13
    mov rsi, r15
    call json_pair
    mov [rsp + 64], rdx             # the value
    mov rdi, rax
    call json_str
    test rax, rax
    jz 55f
    mov [rsp + 72], rax
    mov [rsp + 80], rdx
    mov rdi, [rsp + 64]
    call json_type
    cmp eax, JT_STR
    jne 5f
    # NAME=value
    lea rdi, [rip + ritbuf]
    call sb_clear
    lea rdi, [rip + ritbuf]
    mov rsi, [rsp + 72]
    mov rdx, [rsp + 80]
    call sb_push
    lea rdi, [rip + ritbuf]
    mov esi, '='
    call sb_push_byte
    mov rdi, [rsp + 64]
    call json_str
    lea rdi, [rip + ritbuf]
    mov rsi, rax
    call sb_push
    mov rdi, [rip + ritbuf + SB_ptr]
    mov rsi, [rip + ritbuf + SB_len]
    call dupz
    mov rcx, [rsp + 16]
    mov rdx, [rsp + 48]
    mov [rcx + rdx*8], rax
    inc qword ptr [rsp + 48]
    jmp 55f
5:  # null (or anything else): the name is unset
    mov rdi, [rsp + 72]
    mov rsi, [rsp + 80]
    call dupz
    mov rcx, [rsp + 24]
    mov rdx, [rsp + 56]
    mov [rcx + rdx*8], rax
    inc qword ptr [rsp + 56]
55: inc r15
    jmp 4b
6:  mov rcx, [rsp + 16]
    mov rdx, [rsp + 48]
    mov qword ptr [rcx + rdx*8], 0
    mov rcx, [rsp + 24]
    mov rdx, [rsp + 56]
    mov qword ptr [rcx + rdx*8], 0
    # cwd
    mov rdi, r12
    lea rsi, [rip + .Lk_cwd]
    call json_get
    mov rdi, rax
    call json_str
    test rax, rax
    jz 7f
    mov rdi, rax
    mov rsi, rdx
    call dupz
    mov [rsp + 32], rax
7:  # the tab's title: the adapter's, else the session's name
    mov rdi, r12
    lea rsi, [rip + .Lk_title]
    call json_get
    mov rdi, rax
    call json_str
    test rax, rax
    jnz 8f
    mov rdi, [rbx + DS_name]
    test rdi, rdi
    jz 71f
    call strlen
    mov rdx, rax
    mov rax, [rbx + DS_name]
    jmp 8f
71: lea rax, [rip + .Ls_debug]
    mov edx, 5
8:  mov rdi, rax
    mov rsi, rdx
    call dupz
    mov [rsp + 40], rax
    # run it: the PG is argv, sets, unsets, cwd in a row ([rsp + 8])
    lea rdi, [rsp + 8]
    mov rsi, [rsp + 40]
    mov edx, TK_TERMINAL | TRV_FOCUS   # the user types to the program there
    lea rcx, [rip + rit_event]
    mov r8, [rsp]
    shl r8, 32
    mov eax, [rbx + DS_id]
    or r8, rax                  # cookie: seq << 32 | session id
    mov rax, [rsp]
    mov [rbx + DS_rit_seq], eax
    call term_run
    test rax, rax
    jle 9f
    # the panel shows its terminals, not a view tab such as the Debug Console (term_run leaves
    # g_panel_cur alone)
    mov dword ptr [rip + g_panel_cur], -1
    jmp .Lrit_free
9:  mov dword ptr [rbx + DS_rit_seq], 0
    # all 32 tabs are taken
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [rip + .Lm_tabs]
    call rit_fail
    jmp .Lrit_free
.Lrit_noargs:
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [rip + .Lm_noargs]
    call rit_fail
.Lrit_free:
    # term_run copied what it keeps
    lea rax, [rsp + 8]
    mov rdi, [rax]
    call free_list
    mov rdi, [rsp + 16]
    call free_list
    mov rdi, [rsp + 24]
    call free_list
    mov rdi, [rsp + 32]
    call mem_free
    mov rdi, [rsp + 40]
    call mem_free
    EPILOGUE

# rit_event(cookie, TERM, event, code): started (code: its pid) answers with processId; failing to
#   start answers with an error. Later events (its exit) are the debug session's business, not the
#   terminal's: the adapter reports the program's end itself
rit_event:
    PROLOGUE
    mov r12, rdi
    mov r13d, edx
    mov r14d, ecx
    cmp r13d, TE_STARTED
    je 1f
    cmp r13d, TE_FAILED
    jne 9f
1:  mov edi, r12d
    call dap_slot_of_id
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + DS_state], DSS_ENDED
    je 9f
    mov r15, r12
    shr r15, 32                 # the request's seq
    # an answer is owed once (a restarted tab starts again)
    cmp [rbx + DS_rit_seq], r15d
    jne 9f
    mov dword ptr [rbx + DS_rit_seq], 0
    cmp r13d, TE_STARTED
    jne 5f
    lea rdi, [rip + g_dmsg]
    call jw_begin
    lea rdi, [rip + g_dmsg]
    call jw_obj
    lea rdi, [rip + .Lk_seq]
    mov esi, [rbx + DS_seq]
    inc dword ptr [rbx + DS_seq]
    call aki
    lea rdi, [rip + .Lk_type]
    lea rsi, [rip + .Lv_response]
    call akv
    lea rdi, [rip + .Lk_request_seq]
    mov rsi, r15
    call aki
    lea rdi, [rip + .Lk_success]
    mov esi, 1
    call akb
    lea rdi, [rip + .Lk_command]
    lea rsi, [rip + .Lv_rit]
    call akv
    lea rdi, [rip + .Lk_body]
    call ak
    lea rdi, [rip + g_dmsg]
    call jw_obj
    lea rdi, [rip + .Lk_processId]
    mov esi, r14d
    call aki
    lea rdi, [rip + g_dmsg]
    call jw_end_obj
    lea rdi, [rip + g_dmsg]
    call jw_end_obj
    mov rdi, rbx
    mov rsi, [rip + g_dmsg + SB_ptr]
    mov rdx, [rip + g_dmsg + SB_len]
    call dap_send
    EPILOGUE
5:  mov rdi, rbx
    mov rsi, r15
    lea rdx, [rip + .Lm_failed]
    call rit_fail
9:  EPILOGUE

# rit_fail(ds, seq, message cstr)
rit_fail:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    call strlen
    mov r9, rax
    mov r8, r13
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lv_rit]
    mov ecx, .Lv_rit_end - .Lv_rit
    call dap_reply_fail
    pop r13
    pop r12
    pop rbx
    ret

# dupz(ptr, len) -> an owned NUL-terminated copy
dupz:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsi + 1]
    call mem_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov byte ptr [r13 + r12], 0
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

# free_list(0-terminated list of owned cstrs, or 0): the strings and the list
free_list:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  mov rdi, [rbx + r12*8]
    test rdi, rdi
    jz 2f
    call mem_free
    inc r12
    jmp 1b
2:  mov rdi, rbx
    call mem_free
9:  pop r13
    pop r12
    pop rbx
    ret

.bss
.p2align 3
ritbuf: .zero SB_SIZE

.section .rodata
.Lk_args: .asciz "args"
.Lk_env: .asciz "env"
.Lk_cwd: .asciz "cwd"
.Lk_title: .asciz "title"
.Lk_seq: .asciz "seq"
.Lk_type: .asciz "type"
.Lk_request_seq: .asciz "request_seq"
.Lk_success: .asciz "success"
.Lk_command: .asciz "command"
.Lk_body: .asciz "body"
.Lk_processId: .asciz "processId"
.Lv_response: .asciz "response"
.Lv_rit: .ascii "runInTerminal"
.Lv_rit_end:
    .byte 0
.Ls_debug: .asciz "Debug"
.Lm_noargs: .asciz "runInTerminal needs args, a list of strings"
.Lm_tabs: .asciz "all 32 terminal tabs are in use"
.Lm_failed: .asciz "the program could not be started in the terminal"
