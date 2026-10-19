# Single-owner bounded frames. Only sealed objects may enter a settings job.
.include "rhun.inc"
.include "app/extsettingsframe.inc"
.text
# new(tag32,kind,length,round)->owned frame/NULL,RDX error; no payload copy.
FN ext_settings_frame_new
    PROLOGUE 96
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, rdi
    mov [rsp + 64 + EWE_tag], rdi
    mov [rsp + 64 + EWE_kind], rsi
    mov [rsp + 64 + EWE_length], rdx
    mov [rsp + 64 + EWE_round], rcx
    mov rdi, rsp
    lea rsi, [rsp + 64]
    call ext_settings_wire_encode
    test rax, rax
    js 1f
    lea rdi, [r13 + EJF_SIZE]
    call ext_settings_memory_try
    test rax, rax
    jz 2f
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r15
    mov edx, 32
    call memcpy
    mov [rbx + EJF_kind], r12
    mov [rbx + EJF_length], r13
    mov [rbx + EJF_round], r14
    lea rdi, [rbx + EJF_header]
    mov rsi, rsp
    mov edx, EW_HEADER
    call memcpy
    mov rax, rbx
    xor edx, edx
    EPILOGUE
1:  mov rdx, rax
    xor eax, eax
2:  EPILOGUE
# seal(frame)->0/-EPROTO. No body walk; the owned local producer validates its data.
FN ext_settings_frame_seal
    test rdi, rdi
    jz 2f
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EJF_sealed], 0
    jne 1f
    lea rdi, [rbx + EJF_header]
    mov rsi, rbx
    call ext_settings_wire_check
    test rax, rax
    js 1f
    cmp [rbx + EJF_kind], rdx
    jne 1f
    cmp [rbx + EJF_length], r8
    jne 1f
    cmp [rbx + EJF_round], r9
    jne 1f
    mov qword ptr [rbx + EJF_sealed], 1
    xor eax, eax
    EPILOGUE
1:  mov rax, -71
    EPILOGUE
2:  mov rax, -71
    ret
FN ext_settings_frame_free
    jmp ext_settings_memory_free
