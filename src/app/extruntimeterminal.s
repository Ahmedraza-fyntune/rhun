# Freeze one small owned response. Queue delivery is a separate operation.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeadmit.inc"
.text
# table,ordinal,session,reason,now -> pure0/-errno, no stores.
FN rt_reply_freeze_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    cmp r12, RT_SLOT_COUNT
    jae .Lrf_invalid
    test r13, r13
    jle .Lrf_invalid
    cmp r14, RTRSP_CANCELLED
    ja .Lrf_invalid
    test r15, r15
    js .Lrf_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrf_invalid
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrf_invalid
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrf_invalid
    imul rax, r12, RT_SLOT_SIZE
    lea rdx, [rbx + rax + RT_slots]
    cmp [rdx + RTS_session], r13
    jne .Lrf_invalid
    mov rax, [rdx + RTS_state]
    cmp rax, RTS_ACTIVE
    je 1f
    cmp rax, RTS_DRAINING
    jne .Lrf_invalid
1:  mov rax, [rdx + RTS_flags]
    and eax, RTSF_OP_CREDIT | RTSF_ID_IN_USE
    cmp eax, RTSF_OP_CREDIT | RTSF_ID_IN_USE
    jne .Lrf_invalid
    mov rax, [rdx + RTS_replyID]
    test rax, rax
    jle .Lrf_invalid
    cmp rax, 0x7fffffff
    ja .Lrf_invalid
    mov rax, [rdx + RTS_delivery]
    or rax, [rdx + RTS_outcome]
    or rax, [rdx + RTS_replyLen]
    or rax, [rdx + RTS_retryDue]
    or rax, [rdx + RTS_backoff]
    or rax, [rdx + RTS_stallDeadline]
    jnz .Lrf_already
    xor eax, eax
    EPILOGUE
.Lrf_already:
    mov rax, -114
    EPILOGUE
.Lrf_invalid:
    mov rax, -22
    EPILOGUE

FN rt_reply_freeze
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    call rt_reply_freeze_check
    test rax, rax
    jnz 1f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8, [rsp + 32]
    call rt_reply_freeze_publish
    xor eax, eax
1:  EPILOGUE

# VOID. Complete check or successful credit acquisition and valid reason/now precedes.
# No yield, callback, source mutation or fallible instruction may intervene.
FN rt_reply_freeze_publish
    PROLOGUE 32
    imul rax, rsi, RT_SLOT_SIZE
    lea rbx, [rdi + rax + RT_slots]
    mov r14, rcx
    mov r15, r8
    lea r12, [rbx + RTS_reply]
    mov r13, r12
    lea rsi, [rip + .Lrf_ok]
    test r14, r14
    jz 1f
    lea rsi, [rip + .Lrf_error]
1:  mov al, [rsi]
    test al, al
    jz 2f
    mov [r12], al
    inc r12
    inc rsi
    jmp 1b
2:  mov rax, [rbx + RTS_replyID]
    mov ecx, 10
    xor r8d, r8d
3:  xor edx, edx
    div rcx
    add dl, '0'
    mov [rsp + r8], dl
    inc r8
    test rax, rax
    jnz 3b
4:  dec r8
    mov al, [rsp + r8]
    mov [r12], al
    inc r12
    test r8, r8
    jnz 4b
    test r14, r14
    jz 7f
    mov byte ptr [r12], ' '
    inc r12
    lea rsi, [rip + .Lrf_strings]
    mov rsi, [rsi + r14*8]
5:  mov al, [rsi]
    test al, al
    jz 7f
    mov [r12], al
    inc r12
    inc rsi
    jmp 5b
7:  mov byte ptr [r12], 10
    inc r12
    mov byte ptr [r12], 0
    sub r12, r13
    mov [rbx + RTS_replyLen], r12
    lea rax, [r14 + 1]
    mov [rbx + RTS_outcome], rax
    mov qword ptr [rbx + RTS_delivery], RTDEL_WAIT
    mov [rbx + RTS_retryDue], r15
    mov qword ptr [rbx + RTS_backoff], 0
    mov rax, 0x7fffffffffffffff
    mov rcx, rax
    sub rcx, 10000
    cmp r15, rcx
    ja 8f
    lea rax, [r15 + 10000]
8:  mov [rbx + RTS_stallDeadline], rax
    EPILOGUE
.section .rodata
.p2align 3
.globl rt_reply_errors
rt_reply_errors: .quad 0,-22,-11,-12,-7,-17,-2,-95,-22,-125
.Lrf_strings: .quad 0,.Lrf_invalid_text,.Lrf_busy,.Lrf_oom,.Lrf_toobig,.Lrf_name,.Lrf_not_runtime,.Lrf_unknown,.Lrf_catalog,.Lrf_cancelled
.Lrf_ok: .asciz "ok "
.Lrf_error: .asciz "error "
.Lrf_invalid_text: .asciz "syntax invalid runtime request"
.Lrf_busy: .asciz "busy runtime request cancelled"
.Lrf_oom: .asciz "busy allocation failed"
.Lrf_toobig: .asciz "toobig 64 commands"
.Lrf_name: .asciz "refused the name is in use"
.Lrf_not_runtime: .asciz "refused not a runtime command of this extension"
.Lrf_unknown: .asciz "unknown unsupported request"
.Lrf_catalog: .asciz "refused command catalogue invalid"
.Lrf_cancelled: .asciz "cancelled"
