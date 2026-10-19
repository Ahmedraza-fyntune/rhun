# Helper-only strict config path initialization, after full request validation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.text
# create_path(owned mutable absolute cstr)->0/-errno,RDX first cleanup.
# Every raw handle is closed exactly once, including opened children after a parent-close error.
FN sw_create_path
    PROLOGUE 48
    mov rbx, rdi
    call ext_settings_worker_path
    test rax, rax
    js .Lswd_return_plain
    mov r12, rdx
    mov rdi, rbx
    mov esi, 4095
    call ext_root_length
    test rax, rax
    js .Lswd_return_plain
    mov r13, rax
    movzx eax, byte ptr [rbx + r12]
    mov [rsp + 8], rax
    mov byte ptr [rbx + r12], 0
    mov rdi, rbx
    call ext_root_open
    mov r14, rax
    mov [rsp + 24], rdx
    mov rax, [rsp + 8]
    mov [rbx + r12], al
    test r14, r14
    js .Lswd_open_failed
    cmp qword ptr [rsp + 24], 0
    jne .Lswd_root_secondary
    mov r15, r12
.Lswd_next:
    cmp r15, r13
    jae .Lswd_finish
    cmp byte ptr [rbx + r15], '/'
    je .Lswd_skip
.ifdef WINDOWS
    cmp byte ptr [rbx + r15], 92
    je .Lswd_skip
.endif
    mov [rsp], r15
.Lswd_scan:
    cmp r15, r13
    jae .Lswd_component
    cmp byte ptr [rbx + r15], '/'
    je .Lswd_component
.ifdef WINDOWS
    cmp byte ptr [rbx + r15], 92
    je .Lswd_component
.endif
    inc r15
    jmp .Lswd_scan
.Lswd_component:
    movzx eax, byte ptr [rbx + r15]
    mov [rsp + 8], rax
    mov byte ptr [rbx + r15], 0
    mov rdi, r14
    mov rsi, [rsp]
    add rsi, rbx
    mov edx, ER_DIR
    mov ecx, ER_CREATE
    mov r8d, 0700
    call ext_root_open_at
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rax, [rsp + 8]
    mov [rbx + r15], al
    mov rdi, r14
    call ext_root_close
    mov [rsp + 32], rax
    mov r14, -1
    cmp qword ptr [rsp + 16], 0
    jl .Lswd_child_failed
    mov r14, [rsp + 16]
    cmp qword ptr [rsp + 24], 0
    jne .Lswd_child_secondary
    cmp qword ptr [rsp + 32], 0
    jne .Lswd_parent_failed
    jmp .Lswd_next
.Lswd_skip:
    inc r15
    jmp .Lswd_next
.Lswd_finish:
    mov rdi, r14
    call ext_root_close
    xor edx, edx
    EPILOGUE
.Lswd_open_failed:
    mov rax, r14
    mov rdx, [rsp + 24]
    EPILOGUE
.Lswd_child_failed:
    mov rax, [rsp + 16]
    mov rdx, [rsp + 24]
    test rdx, rdx
    jnz 1f
    mov rdx, [rsp + 32]
1:  EPILOGUE
.Lswd_child_secondary:
    mov rax, [rsp + 24]
    mov [rsp + 40], rax
    mov rax, [rsp + 32]
    mov [rsp + 24], rax
    jmp .Lswd_close_child
.Lswd_parent_failed:
    mov rax, [rsp + 32]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 24], 0
.Lswd_close_child:
    mov rdi, r14
    call ext_root_close
    cmp qword ptr [rsp + 24], 0
    jne 2f
    mov [rsp + 24], rax
2:  mov rax, [rsp + 40]
    mov rdx, [rsp + 24]
    EPILOGUE
.Lswd_root_secondary:
    mov rax, [rsp + 24]
    mov [rsp + 40], rax
    mov rdi, r14
    call ext_root_close
    mov rdx, rax
    mov rax, [rsp + 40]
    EPILOGUE
.Lswd_return_plain:
    xor edx, edx
    EPILOGUE
