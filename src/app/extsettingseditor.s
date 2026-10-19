# Synchronous compatibility reads. No SD_value authority or deferred pointers.
.include "rhun.inc"
.include "app/extprepare.inc"
.text
# Internal ext->RAX historical slot ornegative,RDX EP,RCX SDbase,R8 count.
FN settings_editor_metadata
    PROLOGUE
    mov rbx, rdi
    mov rcx, [rip + g_exts + VEC_len]
    test rcx, rcx
    jz .Lsem_bad
    cmp rcx, 128
    ja .Lsem_bad
    mov rax, [rip + g_exts + VEC_ptr]
    test rax, rax
    jz .Lsem_bad
    cmp rbx, rax
    jb .Lsem_bad
    mov rdi, rbx
    sub rdi, rax
    imul rcx, rcx, EXT_SIZE
    cmp rdi, rcx
    jae .Lsem_bad
    mov rax, rdi
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    test rdx, rdx
    jnz .Lsem_bad
    mov r12, rax
    mov rdi, rbx
    call ext_has_metadata
    cmp eax, 1
    jne .Lsem_stale
    mov r13, [rbx + EXT_metadata_owner]
    test r13, r13
    jz .Lsem_stale
    cmp qword ptr [r13 + PO_refs], 0
    jle .Lsem_stale
    cmp qword ptr [r13 + PO_ready], 1
    jne .Lsem_stale
    mov rcx, [rbx + EXT_sdefs + VEC_ptr]
    cmp [r13 + EP_ext + EXT_sdefs + VEC_ptr], rcx
    jne .Lsem_stale
    mov r8, [rbx + EXT_sdefs + VEC_len]
    cmp [r13 + EP_ext + EXT_sdefs + VEC_len], r8
    jne .Lsem_stale
    cmp r8, 256
    ja .Lsem_stale
    mov rax, [rbx + EXT_sdefs + VEC_cap]
    cmp [r13 + EP_ext + EXT_sdefs + VEC_cap], rax
    jne .Lsem_stale
    cmp rax, r8
    jb .Lsem_stale
    test r8, r8
    jz .Lsem_ok
    test rcx, rcx
    jz .Lsem_stale
.Lsem_ok:
    mov rax, r12
    mov rdx, r13
    EPILOGUE
.Lsem_bad:
    mov rax, -22
    jmp .Lsem_error
.Lsem_stale:
    mov rax, -116
.Lsem_error:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

# Metadata only: ext,SD ->ordinal ornegative,RDX borrowedEP,R8 index.
# Does not grant active model, edit, runtime or capability authority.
FN ext_setting_resolve
    PROLOGUE
    mov rbx, rsi
    call settings_editor_metadata
    test rax, rax
    js .Lsev_meta_error
    mov r12, rax
    mov r13, rdx
    test r8, r8
    jz .Lsev_bad
    cmp rbx, rcx
    jb .Lsev_bad
    sub rbx, rcx
    imul r8, r8, SD_SIZE
    cmp rbx, r8
    jae .Lsev_bad
    mov rax, rbx
    xor edx, edx
    mov ecx, SD_SIZE
    div rcx
    test rdx, rdx
    jnz .Lsev_bad
    mov r8, rax
    mov rax, r12
    mov rdx, r13
    xor ecx, ecx
    EPILOGUE
.Lsev_bad:
    mov rax, -22
.Lsev_meta_error:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

# ext,exact immutable SD->borrowed canonical cstr/NULL,RDX error,RCX length.
# Copy the borrow before any intent/service/model mutation or yield.
FN ext_setting_value
    PROLOGUE
    call ext_setting_resolve
    test rax, rax
    js .Lsevalue_error
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r8
    call ext_settings_effective_value
    EPILOGUE
.Lsevalue_error:
    mov rdx, rax
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# ext->RAX pinned,RDX disabled,RCX error. Missing authority is never enabled.
FN ext_setting_flags
    PROLOGUE
    call settings_editor_metadata
    test rax, rax
    js .Lsef_error
    mov rdi, rax
    mov rsi, rdx
    call ext_settings_effective_flags
    EPILOGUE
.Lsef_error:
    mov rcx, rax
    xor eax, eax
    xor edx, edx
    EPILOGUE
