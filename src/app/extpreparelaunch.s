# Launch validation stays private and binds exactly the payload bytes it inspects.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatemanifest.inc"
.include "app/extprepare.inc"
.text
# Hash borrowed regular payload with64KiB scratch, max64MiB, EOF and metadata recheck.
# Out64 = size8,exec8,hash32,reserved16. Output changes only on success.
FN prep_hash_file
    PROLOGUE 65536 + SH256_SIZE + 128
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + 65536 + SH256_SIZE + 112], rdx
    mov rdi, rdx
    mov rsi, rbx
    mov rdx, rsp
    call prep_payload_stat
    test rax, rax
    js .Lephf_done
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lephf_changed
    cmp qword ptr [rsp + ER_size], 64 * 1024 * 1024
    ja .Lephf_resource
    lea rdi, [rsp + 64]
    call sha256_init
    xor r13d, r13d
1:  cmp r13, [rsp + ER_size]
    jae 3f
    mov r14, [rsp + ER_size]
    sub r14, r13
    cmp r14, 65536
    jbe 2f
    mov r14d, 65536
2:  mov rdi, rbx
    lea rsi, [rsp + 64 + SH256_SIZE]
    mov rdx, r14
    mov rcx, r13
    call ext_root_read
    test rax, rax
    js .Lephf_done
    jz .Lephf_changed
    cmp rax, r14
    ja .Lephf_changed
    mov [rsp + 65536 + SH256_SIZE + 104], rax
    mov rdi, [rsp + 65536 + SH256_SIZE + 112]
    lea rsi, [rsp + 64 + SH256_SIZE]
    mov rdx, r13
    mov rcx, rax
    call prep_capture_compare
    test rax, rax
    jnz .Lephf_done
    mov rax, [rsp + 65536 + SH256_SIZE + 104]
    add r13, rax
    lea rdi, [rsp + 64]
    lea rsi, [rsp + 64 + SH256_SIZE]
    mov rdx, rax
    call sha256_update
    test eax, eax
    jz .Lephf_changed
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rsp + 64 + SH256_SIZE]
    mov edx, 1
    mov rcx, r13
    call ext_root_read
    test rax, rax
    js .Lephf_done
    jnz .Lephf_changed
    mov rdi, [rsp + 65536 + SH256_SIZE + 112]
    mov rsi, rbx
    lea rdx, [rsp + 32]
    call prep_payload_stat
    test rax, rax
    js .Lephf_done
    mov rdi, rsp
    lea rsi, [rsp + 32]
    mov edx, ER_STAT_SIZE
    call memeq
    test eax, eax
    jz .Lephf_changed
    lea rdi, [rsp + 64]
    lea rsi, [rsp + 65536 + SH256_SIZE + 64]
    call sha256_final
    test eax, eax
    jz .Lephf_changed
    mov rax, [rsp + ER_size]
    mov [r12], rax
    mov rax, [rsp + ER_exec]
    mov [r12 + 8], rax
    lea rdi, [r12 + 16]
    lea rsi, [rsp + 65536 + SH256_SIZE + 64]
    mov edx, 32
    call memcpy
    mov qword ptr [r12 + 48], 0
    mov qword ptr [r12 + 56], 0
    xor eax, eax
.Lephf_done:
    EPILOGUE
.Lephf_changed:
    mov rax, -EV_CHANGED
    EPILOGUE
.Lephf_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE

FN prep_launch
    PROLOGUE 144
    mov rbx, rdi
    mov r12, [rbx + EP_raw]
    mov qword ptr [rbx + EP_native], 1
    test qword ptr [r12 + MV_flags], 1 << MT_RUNTIME
    jz 11f
    mov qword ptr [rbx + EP_native], 0
11: mov eax, MT_TARGET
    test qword ptr [r12 + MV_flags], 1 << MT_RUNTIME
    jz 1f
    mov eax, MT_RUN
1:  shl rax, 4
    mov r13, [r12 + MV_top + rax]
    mov r14, [r12 + MV_top + rax + 8]
    mov rdi, [rbx + EP_root]
    mov rsi, r13
    mov rdx, r14
    call ext_validate_open_relative
    test rax, rax
    js .Lepl_open_error
    mov r15, rax
    mov rdi, rax
    mov rsi, rsp
    mov rdx, rbx
    call prep_hash_file
    test rax, rax
    jnz .Lepl_close
    test qword ptr [r12 + MV_flags], 1 << MT_RUNTIME
    jnz 3f
    mov rdi, rbx
    mov rsi, r15
    mov edx, 1
    mov rcx, rsp
    call prep_capture_image
    test rax, rax
    jnz .Lepl_close
3:  mov rdi, r15
    lea rsi, [rsp + 64]
    mov rdx, rbx
    call prep_hash_file
    test rax, rax
    jnz .Lepl_close
    mov rdi, rsp
    lea rsi, [rsp + 64]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lepl_changed
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rsp]
    mov r8, [rsp + 8]
    lea r9, [rsp + 16]
    mov r10d, SR_LAUNCH
    call prep_source_add
.Lepl_close:
    mov r13, rax
    mov rdi, r15
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    test r13, r13
    jnz .Lepl_return
    mov r13, [rbx + EP_cleanup]
    test r13, r13
    jnz .Lepl_return
    test qword ptr [r12 + MV_flags], 1 << MT_RUNTIME
    jz .Lepl_accepted
    mov rdi, rbx
    mov rsi, [r12 + MV_top + MT_RUNTIME * 16]
    mov rdx, [r12 + MV_top + MT_RUNTIME * 16 + 8]
    xor ecx, ecx
    call prep_runtime_resolve
    test rax, rax
    jz .Lepl_runtime_error
    mov [rsp + 128], rax
    mov rdi, rax
    call ext_validate_system_open
    test rax, rax
    js .Lepl_open_error
    mov r15, rax
    mov rdi, rax
    mov esi, 1
    mov rdx, rbx
    call ext_validate_image_owned
    mov r13, rax
    mov rdi, r15
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    test r13, r13
    jnz .Lepl_return
    mov r13, [rbx + EP_cleanup]
    test r13, r13
    jnz .Lepl_return
    mov rdi, rbx
    mov rsi, [rbx + EP_ext + EXT_prog]
    call prep_owned_free
    test rax, rax
    jnz .Lepl_done
    mov rax, [rsp + 128]
    mov [rbx + EP_ext + EXT_prog], rax
.Lepl_accepted:
    mov rdi, rbx
    call prep_capture_reset
    test rax, rax
    jnz .Lepl_done
    mov dword ptr [rbx + EP_ext + EXT_hello], 0
    mov dword ptr [rbx + EP_ext + EXT_manifest_ok], 1
    xor eax, eax
.Lepl_done:
    EPILOGUE
.Lepl_runtime_error:
    mov rax, rdx
    EPILOGUE
.Lepl_changed:
    mov rax, -EV_CHANGED
    jmp .Lepl_close
.Lepl_open_error:
    mov r13, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
.Lepl_return:
    mov rax, r13
    EPILOGUE
