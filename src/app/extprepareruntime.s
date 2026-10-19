# Fallible PATH-only resolution for private candidate launch preparation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Resolution result uses the owner ledger when EP!=0, regular fallible heap otherwise.
FN prep_runtime_dup
    test rdi, rdi
    jnz 1f
    mov rdi, rsi
    mov rsi, rdx
    push rbx
    call mem_dup_try
    pop rbx
    xor edx, edx
    test rax, rax
    jnz 2f
    mov rdx, -12
2:  ret
1:  PROLOGUE
    mov rbx, rdi
    call prep_owned_dup
    xor edx, edx
    test rax, rax
    jnz 3f
    mov rdx, [rbx + PO_error]
3:  EPILOGUE

FN prep_runtime_free
    test rsi, rsi
    jz 1f
    test rdi, rdi
    jnz 2f
    mov rdi, rsi
    jmp mem_free
2:  jmp prep_owned_free
1:  ret

# Candidate basename, actual loader PATH-only search semantics.
FN prep_runtime_candidate
.ifdef WINDOWS
    jmp win_prep_runtime_candidate
.else
    PROLOGUE 4112
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov r13, rax
    lea rdi, [rip + epr_path]
    call getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + epr_default_path]
1:  mov r14, rax
2:  cmp byte ptr [r14], 0
    je .Leprc_none
    xor r15d, r15d
3:  cmp byte ptr [r14 + r15], 0
    je 4f
    cmp byte ptr [r14 + r15], ':'
    je 4f
    inc r15
    jmp 3b
4:  lea rax, [r15 + r13 + 1]
    cmp rax, 4095
    ja 6f
    mov rdi, rsp
    mov rsi, r14
    mov rdx, r15
    call memcpy
    mov byte ptr [rsp + r15], '/'
    lea rdi, [rsp + r15 + 1]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    lea rax, [r15 + r13 + 1]
    mov byte ptr [rsp + rax], 0
    mov [rsp + 4096], rax
    mov rdi, rsp
    mov esi, 1
    SYS SYS_access
    test rax, rax
    jnz 6f
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, [rsp + 4096]
    call prep_runtime_dup
    EPILOGUE
6:  add r14, r15
    cmp byte ptr [r14], ':'
    jne 2b
    inc r14
    jmp 2b
.Leprc_none:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.endif

# prep_runtime_resolve(EPOr0,nameSpan,len,requirePresentPATH)->path or0/RDX reason.
FN prep_runtime_resolve
    PROLOGUE 272
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test r13, r13
    jz .Lepr_bad
    cmp r13, 255
    ja .Lepr_bad
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [rsp + r13], 0
    mov rdi, rsp
    call ext_root_name
    test rax, rax
    js .Lepr_bad
    mov rdi, r14
    test rbx, rbx
    jz .Lepr_managed_path
    cmp qword ptr [rbx + EP_kind], 2
    jne .Lepr_managed_path
    call prep_legacy_path_env
    jmp .Lepr_path_checked
.Lepr_managed_path:
    call ext_validate_path_env
.Lepr_path_checked:
    test rax, rax
    jnz .Lepr_error
.ifdef WINDOWS
    mov rdi, rsp
    lea rsi, [rip + epr_python3]
    call strcmp_eq
    test eax, eax
    jnz .Lepr_python
.endif
    mov rdi, rbx
    mov rsi, rsp
    call prep_runtime_candidate
    test rdx, rdx
    js .Lepr_done
    test rax, rax
    jz .Lepr_bad
.Lepr_done:
    EPILOGUE
.ifdef WINDOWS
.Lepr_python:
    xor r12d, r12d           # first WindowsApps fallback, while searching all real candidates
    xor r13d, r13d
.Lepr_python_next:
    cmp r13, 3
    jae .Lepr_python_last
    lea rax, [rip + epr_python_names]
    mov rsi, [rax + r13*8]
    mov rdi, rbx
    call prep_runtime_candidate
    test rdx, rdx
    js .Lepr_python_error
    test rax, rax
    jz .Lepr_python_more
    mov r14, rax
    mov rdi, rax
    call strlen
    mov rdi, r14
    mov rsi, rax
    lea rdx, [rip + epr_windowsapps]
    mov ecx, 13
    call str_find
    test rax, rax
    js .Lepr_python_real
    test r12, r12
    jnz .Lepr_python_drop
    mov r12, r14
    jmp .Lepr_python_more
.Lepr_python_drop:
    mov rdi, rbx
    mov rsi, r14
    call prep_runtime_free
.Lepr_python_more:
    inc r13
    jmp .Lepr_python_next
.Lepr_python_real:
    mov rdi, rbx
    mov rsi, r12
    call prep_runtime_free
    mov rax, r14
    xor edx, edx
    EPILOGUE
.Lepr_python_error:
    mov r15, rdx
    mov rdi, rbx
    mov rsi, r12
    call prep_runtime_free
    mov rdx, r15
    xor eax, eax
    EPILOGUE
.Lepr_python_last:
    mov rax, r12
    test rax, rax
    jz .Lepr_bad
    xor edx, edx
    EPILOGUE
.endif
.Lepr_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.Lepr_bad:
    mov rdx, -EV_BAD_RUNTIME
    xor eax, eax
    EPILOGUE
.section .rodata
epr_path: .asciz "PATH"
epr_default_path: .asciz "/usr/local/bin:/usr/bin:/bin"
.ifdef WINDOWS
epr_python_names: .quad epr_python3,epr_python,epr_py
epr_python3: .asciz "python3"
epr_python: .asciz "python"
epr_py: .asciz "py"
epr_windowsapps: .asciz "/WindowsApps/"
.endif
