# Separate private legacy semantics. No active registry/state mutation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Allocation only: root=-1 is the pure import path, never a filesystem operation.
FN ext_prepare_alloc_legacy
    PROLOGUE
    call ext_prepare_alloc
    test rax, rax
    jz 1f
    mov qword ptr [rax + EP_kind], 2
1:  EPILOGUE

# Checked source bytes, then the actual callbacks and compatible default/provider completion.
FN prep_legacy_manifest
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp rdx, 65536
    ja .Leplm_resource
    mov rdi, rsi
    mov rsi, rdx
    call prep_ini_text_valid
    test eax, eax
    jz .Leplm_bad
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_manifest_parse_owned
    test rax, rax
    jnz .Leplm_done
    mov rdi, [rbx + EP_ext + EXT_mowner]
    test rdi, rdi
    jz .Leplm_bad
    mov rsi, [rbx + EP_ext + EXT_owner]
    call strcmp_eq
    test eax, eax
    jz .Leplm_bad
    mov rdi, [rbx + EP_ext + EXT_mname]
    test rdi, rdi
    jz .Leplm_bad
    mov rsi, [rbx + EP_ext + EXT_name]
    call strcmp_eq
    test eax, eax
    jz .Leplm_bad
    mov rdi, [rbx + EP_ext + EXT_title]
    test rdi, rdi
    jz .Leplm_bad
    cmp byte ptr [rdi], 0
    je .Leplm_bad
    mov rdi, [rbx + EP_ext + EXT_version]
    test rdi, rdi
    jz .Leplm_bad
    cmp byte ptr [rdi], 0
    je .Leplm_bad
    cmp dword ptr [rbx + EP_ext + EXT_hello], 1
    jne .Leplm_bad
    mov dword ptr [rbx + EP_ext + EXT_hello], 0
    mov rdi, [rbx + EP_ext + EXT_prog]
    test rdi, rdi
    jz .Leplm_bad
    cmp byte ptr [rdi], 0
    je .Leplm_bad
    mov rdi, rbx
    call ext_manifest_finish_owned
.Leplm_done:
    EPILOGUE
.Leplm_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Leplm_bad:
    mov rax, -EV_BAD_MANIFEST
    EPILOGUE

.ifdef WINDOWS
# Return an owned absolute legacy span, or0 if relative. No OS path lookup.
FN prep_legacy_absolute_join
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, 3
    jb 1f
    cmp byte ptr [r12 + 1], ':'
    jne 1f
    mov al, [r12 + 2]
    cmp al, '/'
    je .Leplaj_copy
    cmp al, 92
    je .Leplaj_copy
1:  mov al, [r12]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne .Leplaj_relative
2:  cmp r13, 2
    jb 3f
    mov al, [r12 + 1]
    cmp al, '/'
    je .Leplaj_copy
    cmp al, 92
    je .Leplaj_copy
3:  mov r14, [rbx + EP_legacy_rootlen]
    cmp r14, 2
    jb .Leplaj_bad
    cmp qword ptr [rbx + EP_legacy_cwd], 0
    je .Leplaj_bad
    lea rsi, [r13 + r14 + 1]
    cmp rsi, 4096
    ja .Leplaj_bad
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Leplaj_relative
    mov r15, rax
    mov rdi, rax
    mov rsi, [rbx + EP_legacy_cwd]
    mov rdx, r14
    call memcpy
    lea rdi, [r15 + r14]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    lea rcx, [r14 + r13]
    mov byte ptr [r15 + rcx], 0
    mov rax, r15
    EPILOGUE
.Leplaj_copy:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call prep_owned_dup
    EPILOGUE
.Leplaj_relative:
    xor eax, eax
    EPILOGUE
.Leplaj_bad:
    mov qword ptr [rbx + PO_error], -EV_BAD_PATH
    xor eax, eax
    EPILOGUE
.endif
