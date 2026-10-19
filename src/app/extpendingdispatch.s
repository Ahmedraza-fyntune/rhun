# Pending manifest command policy. Lifecycle pumping still visits every historical EXT.
.include "rhun.inc"
.include "app/extpending.inc"
.text
# ext_cmd_index_owned(ext,index)->1/0, no borrowed element escapes this call.
FN ext_cmd_index_owned
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rip + g_exts + VEC_len], 128
    ja .Lpco_no
    cmp r12, [rip + g_ext_cmds + VEC_len]
    jae .Lpco_no
    cmp r12, [rip + g_ext_owner + VEC_len]
    jae .Lpco_no
    mov rax, rbx
    sub rax, [rip + g_exts + VEC_ptr]
    jc .Lpco_no
    xor edx, edx
    mov r8d, EXT_SIZE
    div r8
    test rdx, rdx
    jnz .Lpco_no
    cmp rax, [rip + g_exts + VEC_len]
    jae .Lpco_no
    mov r13, rax
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz .Lpco_no
    mov rcx, [rip + g_ext_owner + VEC_ptr]
    test rcx, rcx
    jz .Lpco_no
    cmp [rcx + r12*8], r13
    jne .Lpco_no
    mov eax, 1
    EPILOGUE
.Lpco_no:
    xor eax, eax
    EPILOGUE

# Is the current owned request eligible to survive an ordinary lifecycle callback?
# Returns1 kept/0 absent-or-cleared. Never starts or sends anything.
FN ext_pending_reconcile
    cmp qword ptr [rdi + EXT_pending], 0
    je .Lpr_no
    push rdi
    call ext_is_visible
    pop rdi
    test eax, eax
    jz .Lpr_clear
    cmp qword ptr [rip + ext_pending_shutting_down], 0
    jne .Lpr_clear
    cmp dword ptr [rdi + EXT_disabled], 0
    jne .Lpr_clear
    mov eax, [rdi + EXT_status]
    cmp eax, ES_RUNNING
    je .Lpr_yes
    cmp eax, ES_STARTING
    je .Lpr_yes
    cmp eax, ES_IDLE
    jne 1f
    cmp dword ptr [rdi + EXT_wait_slot], 0
    jne .Lpr_yes
    jmp .Lpr_clear
1:  cmp eax, ES_STOPPING
    jne .Lpr_clear
    cmp dword ptr [rdi + EXT_restart], 0
    jne .Lpr_yes
.Lpr_clear:
    PROLOGUE
    call ext_pending_clear
    xor eax, eax
    EPILOGUE
.Lpr_yes:
    mov eax, 1
    ret
.Lpr_no:
    xor eax, eax
    ret

# Set only from an exact current manifest row. Constructor refusal preserves previous ownership.
FN ext_pending_set
    xor edx, edx
    jmp ext_pending_set_inv
# ext_pending_set_inv(ext, index, INV* or 0): the same, keeping how it was invoked (FROM, the
# document and a copy of the body, at most INV_BODY_MAX bytes)
FN ext_pending_set_inv
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rdx
    call ext_is_visible
    test eax, eax
    jz .Lps_closed
    cmp dword ptr [rbx + EXT_disabled], 0
    jne .Lps_closed
    mov eax, [rbx + EXT_status]
    cmp eax, ES_FAILED
    jae .Lps_closed
    cmp eax, ES_STOPPED
    je .Lps_closed
    cmp eax, ES_STOPPING
    jne 1f
    cmp dword ptr [rbx + EXT_restart], 0
    je .Lps_closed
1:  mov rdi, rbx
    mov rsi, r12
    call ext_cmd_index_owned
    test eax, eax
    jz .Lps_missing
    call ext_cmd_manifest_count
    cmp r12, rax
    jae .Lps_missing
    imul rax, r12, CMD_SIZE
    add rax, [rip + g_ext_cmds + VEC_ptr]
    mov rsi, [rax + CMD_name]
    mov rdi, rbx
    call ext_pending_new
    test rax, rax
    jz .Lps_constructor
    mov r13, rax
    mov rsi, [rsp]
    test rsi, rsi
    jz 2f
    mov rcx, [rsi + INV_len]
    cmp rcx, INV_BODY_MAX
    ja .Lps_toobig
    lea rdi, [rcx + INV_SIZE]
    call mem_alloc
    mov [r13 + PN_inv], rax
    mov rsi, [rsp]
    mov rcx, [rsi + INV_from]
    mov [rax + INV_from], rcx
    mov rcx, [rsi + INV_doc]
    mov [rax + INV_doc], rcx
    mov rcx, [rsi + INV_len]
    mov [rax + INV_len], rcx
    lea rdi, [rax + INV_SIZE]
    mov [rax + INV_body], rdi
    mov rdx, rcx
    mov rsi, [rsi + INV_body]
    call memcpy
2:  mov rax, r13
    mov rdi, [rbx + EXT_pending]
    mov [rbx + EXT_pending], rax
    call ext_pending_release
    xor eax, eax
    EPILOGUE
.Lps_constructor:
    mov rax, rdx
    EPILOGUE
.Lps_toobig:
    mov rdi, r13
    call ext_pending_release
    mov rdi, rbx                # nothing older is delivered in its place either
    call ext_pending_clear
    mov rax, -7
    EPILOGUE
.Lps_missing:
    mov rax, -2
    EPILOGUE
.Lps_closed:
    mov rax, -32
    EPILOGUE

# ext_pending_resolve(ext,PN)->current owned manifest index/-ENOENT.
FN ext_pending_resolve
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_is_visible
    test eax, eax
    jz 8f
    call ext_cmd_manifest_count
    mov r14, rax
    cmp r14, [rip + g_ext_cmds + VEC_len]
    cmova r14, [rip + g_ext_cmds + VEC_len]
    cmp r14, [rip + g_ext_owner + VEC_len]
    cmova r14, [rip + g_ext_owner + VEC_len]
    xor r13d, r13d
1:  cmp r13, r14
    jae 8f
    mov rdi, rbx
    mov rsi, r13
    call ext_cmd_index_owned
    test eax, eax
    jz 2f
    imul rax, r13, CMD_SIZE
    add rax, [rip + g_ext_cmds + VEC_ptr]
    mov rdx, [rax + CMD_name]
    mov rdi, r12
    mov rsi, rbx
    call ext_pending_matches
    test eax, eax
    jnz 3f
2:  inc r13
    jmp 1b
3:  mov rax, r13
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# Try once in normal frame context. Only transient output/language synchronization is retained.
FN ext_pending_try
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EXT_pending], 0
    je .Lpt_ok
    call ext_is_visible
    test eax, eax
    jz .Lpt_closed
    cmp qword ptr [rip + ext_pending_shutting_down], 0
    jne .Lpt_closed
    cmp dword ptr [rbx + EXT_disabled], 0
    jne .Lpt_closed
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    je 1f
    mov rdi, rbx
    call ext_pending_reconcile
    test eax, eax
    jnz .Lpt_retry
    mov rax, -32
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, [rbx + EXT_pending]
    call ext_pending_resolve
    test rax, rax
    js .Lpt_terminal
    mov r14, rax
    mov r13, [rbx + EXT_pending]   # held while sending: its body is read after the catch-up
    mov rdi, r13
    call ext_pending_retain
    mov rsi, r14
    mov rdi, rbx
    mov rdx, [r13 + PN_inv]
    call extproto_send_invoke
    mov r14, rax
    mov rdi, r13
    call ext_pending_release
    mov rax, r14
    test rax, rax
    jns .Lpt_accepted
    cmp rax, -11
    je .Lpt_retry
    cmp rax, -16
    je .Lpt_retry
.Lpt_terminal:
    mov r12, rax
    mov rdi, rbx
    call ext_pending_clear
    lea rdi, [rip + .Lpending_unavailable]
    call app_toast
    mov rax, r12
    EPILOGUE
.Lpt_closed:
    mov rax, -32
    jmp .Lpt_terminal
.Lpt_accepted:
    mov rdi, rbx
    call ext_pending_clear
.Lpt_ok:
    xor eax, eax
    EPILOGUE
.Lpt_retry:
    mov rax, -11
    EPILOGUE
.section .rodata
.Lpending_unavailable: .asciz "The requested extension command is no longer available"
