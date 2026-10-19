# Pure bounded decoding of initial legacy snapshot bytes. No path or process IO.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extpreparelegacy.inc"
.equ LSC_hash, 4096
.equ LSC_base, LSC_hash + SH256_SIZE
.equ LSC_end, LSC_base + 8
.equ LSC_records, LSC_end + 8
.equ LSC_count, LSC_records + 8
.equ LSC_flags, LSC_count + 8
.equ LSC_assets, LSC_flags + 8
.equ LSC_prev, LSC_assets + 8
.equ LSC_curr, LSC_prev + 16
.equ LSC_data, LSC_curr + 16
.equ LSC_digest, LSC_data + 8
.equ LSC_FRAME, LSC_digest + 32
.text
# Counted UTF8 native absolute path, no NUL or control, bounded4095.
FN prep_legacy_path_absolute
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rsi, rsi
    jz 8f
    cmp rsi, 4095
    ja 8f
    call ext_validate_text
    test eax, eax
    jz 8f
.ifdef WINDOWS
    cmp r12, 3
    jb 8f
    cmp byte ptr [rbx + 1], ':'
    jne 2f
    movzx eax, byte ptr [rbx]
    or eax, 32
    sub eax, 'a'
    cmp eax, 25
    ja 8f
    mov al, [rbx + 2]
    cmp al, '/'
    je 9f
    cmp al, 92
    je 9f
    jmp 8f
2:  cmp r12, 5
    jb 8f
    mov al, [rbx]
    cmp al, '/'
    je 3f
    cmp al, 92
    jne 8f
3:  mov al, [rbx + 1]
    cmp al, '/'
    je 4f
    cmp al, 92
    jne 8f
4:  mov al, [rbx + 2]
    cmp al, '?'
    je 8f
    cmp al, '.'
    je 8f
.else
    cmp byte ptr [rbx], '/'
    jne 8f
.endif
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# bytes,len,expectedTag64 ->0/RDX recordsStart, or-primary/RDX0.
FN prep_legacy_snapshot_check
    PROLOGUE LSC_FRAME
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp rsi, LS_HEADER
    jb .Lelsc_bad
    cmp rsi, LS_CAP
    ja .Lelsc_bad
    mov rax, 0x00003153534c4852
    cmp [rbx], rax
    jne .Lelsc_bad
    cmp dword ptr [rbx + 8], 1
    jne .Lelsc_bad
    cmp dword ptr [rbx + 12], LS_HEADER
    jne .Lelsc_bad
    cmp [rbx + LS_total], r12
    jne .Lelsc_bad
    cmp dword ptr [rbx + 28], 0
    jne .Lelsc_bad
    mov rax, [rbx + LS_primary]
    or rax, [rbx + LS_secondary]
    jnz .Lelsc_bad
    xor ecx, ecx
1:  cmp dword ptr [rbx + LS_reserved + rcx], 0
    jne .Lelsc_bad
    add rcx, 4
    cmp rcx, 36
    jb 1b
    mov eax, [rbx + LS_drive]
.ifdef WINDOWS
    test eax, eax
    jz .Lelsc_drive_valid
    sub eax, 'A'
    cmp eax, 25
    ja .Lelsc_bad
.Lelsc_drive_valid:
.else
    test eax, eax
    jnz .Lelsc_bad
.endif
    cmp qword ptr [rbx + LS_tag], 0
    je .Lelsc_bad
    cmp qword ptr [rbx + LS_tag + 8], 0
    je .Lelsc_bad
    lea rdi, [rbx + LS_tag]
    mov rsi, r13
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lelsc_bad
    mov eax, [rbx + LS_count]
    cmp eax, 2
    jb .Lelsc_bad
    cmp eax, 258
    ja .Lelsc_bad
    mov [rsp + LSC_count], rax
    mov eax, [rbx + LS_programlen]
    test eax, eax
    jz .Lelsc_bad
    cmp eax, 4095
    ja .Lelsc_bad
    mov r13, rax
    mov edx, [rbx + LS_scriptlen]
    cmp edx, 4095
    ja .Lelsc_bad
    lea rax, [r13 + rdx + LS_HEADER]
    cmp rax, r12
    ja .Lelsc_bad
    add rax, rbx
    jc .Lelsc_bad
    mov [rsp + LSC_records], rax
    mov [rsp + LSC_base], rbx
    lea rax, [rbx + r12]
    mov [rsp + LSC_end], rax
    mov qword ptr [rsp + LSC_flags], 0
    mov qword ptr [rsp + LSC_assets], 0
    lea rdi, [rbx + LS_HEADER]
    mov rsi, r13
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lelsc_bad
    mov esi, [rbx + LS_scriptlen]
    test esi, esi
    jz 2f
    lea rdi, [rbx + r13 + LS_HEADER]
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lelsc_bad
2:  lea rdi, [rsp + LSC_hash]
    call sha256_init
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rip + elsc_domain]
    mov edx, 23
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rbx + LS_count]
    mov edx, 4
    call sha256_update
    mov r14, [rsp + LSC_records]
    xor r13d, r13d
.Lelsc_record:
    cmp r13, [rsp + LSC_count]
    jae .Lelsc_finish
    mov rax, [rsp + LSC_end]
    sub rax, r14
    cmp rax, LR_SIZE
    jb .Lelsc_bad
    mov eax, [r14 + LR_pathlen]
    test eax, eax
    jz .Lelsc_bad
    cmp eax, 4095
    ja .Lelsc_bad
    mov r12, rax
    lea r15, [r14 + LR_SIZE]
    mov [rsp + LSC_curr], r15
    mov [rsp + LSC_curr + 8], rax
    add rax, LR_SIZE
    add rax, [r14 + LR_datalen]
    jc .Lelsc_bad
    mov rcx, [rsp + LSC_end]
    sub rcx, r14
    cmp rax, rcx
    ja .Lelsc_bad
    lea rax, [r15 + r12]
    mov [rsp + LSC_data], rax
    mov eax, [r14 + LR_exec]
.ifdef WINDOWS
    test eax, eax
.else
    test eax, -74            # only mode & 0111
.endif
    jnz .Lelsc_bad
    cmp dword ptr [r14 + 20], 0
    jne .Lelsc_bad
    mov rax, [r14 + 64]
    or rax, [r14 + 72]
    jnz .Lelsc_bad
    mov rdi, r15
    mov rsi, r12
    call ext_validate_text
    test eax, eax
    jz .Lelsc_bad
    test r13, r13
    jz 3f
    lea rdi, [rsp + LSC_prev]
    lea rsi, [rsp + LSC_curr]
    call ext_validate_records_compare
    test rax, rax
    jns .Lelsc_bad
3:  mov [rsp + LSC_prev], r15
    mov [rsp + LSC_prev + 8], r12
    mov eax, [r14 + LR_roles]
    cmp eax, SR_LAUNCH | SR_EXTERNAL
    je .Lelsc_external
    mov rax, [r14 + LR_size]
    cmp rax, [r14 + LR_datalen]
    jne .Lelsc_bad
    cmp dword ptr [r14 + LR_roles], SR_MANIFEST
    je .Lelsc_manifest
    cmp dword ptr [r14 + LR_roles], SR_GRAMMAR
    je .Lelsc_grammar
    cmp dword ptr [r14 + LR_roles], SR_THEME
    jne .Lelsc_bad
    cmp r12, 13
    jb .Lelsc_bad
    cmp rax, 65536
    ja .Lelsc_bad
    lea rsi, [rip + elsc_themes]
    mov edx, 7
    mov rdi, r15
    call memeq
    test eax, eax
    jz .Lelsc_bad
    lea rdi, [r15 + r12 - 6]
    lea rsi, [rip + elsc_theme]
    mov edx, 6
    call memeq
    test eax, eax
    jz .Lelsc_bad
    jmp .Lelsc_asset
.Lelsc_grammar:
    cmp r12, 11
    jb .Lelsc_bad
    cmp rax, 2 * 1024 * 1024
    ja .Lelsc_bad
    mov rdi, r15
    lea rsi, [rip + elsc_syntax]
    mov edx, 7
    call memeq
    test eax, eax
    jz .Lelsc_bad
    lea rdi, [r15 + r12 - 4]
    lea rsi, [rip + elsc_syn]
    mov edx, 4
    call memeq
    test eax, eax
    jz .Lelsc_bad
.Lelsc_asset:
    mov rax, [r14 + LR_size]
    add [rsp + LSC_assets], rax
    cmp qword ptr [rsp + LSC_assets], 16 * 1024 * 1024
    ja .Lelsc_bad
    mov rdi, rsp
    lea rsi, [r15 + 7]
    lea rdx, [r12 - 7]
    call memcpy
    lea rax, [r12 - 7]
    mov byte ptr [rsp + rax], 0
    mov rdi, rsp
    call ext_root_name
    test rax, rax
    js .Lelsc_bad
    jmp .Lelsc_data_hash
.Lelsc_manifest:
    test qword ptr [rsp + LSC_flags], 1
    jnz .Lelsc_bad
    or qword ptr [rsp + LSC_flags], 1
    cmp r12, 13
    jne .Lelsc_bad
    cmp rax, 65536
    ja .Lelsc_bad
    mov rdi, r15
    lea rsi, [rip + elsc_manifest]
    mov edx, 13
    call memeq
    test eax, eax
    jz .Lelsc_bad
.Lelsc_data_hash:
    mov rdi, [rsp + LSC_data]
    mov rsi, [r14 + LR_datalen]
    lea rdx, [rsp + LSC_digest]
    call prep_hash_bytes
    lea rdi, [rsp + LSC_digest]
    lea rsi, [r14 + LR_hash]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lelsc_bad
    jmp .Lelsc_hash_record
.Lelsc_external:
    test qword ptr [rsp + LSC_flags], 2
    jnz .Lelsc_bad
    or qword ptr [rsp + LSC_flags], 2
    cmp qword ptr [r14 + LR_datalen], 0
    jne .Lelsc_bad
    cmp qword ptr [r14 + LR_size], 64 * 1024 * 1024
    ja .Lelsc_bad
    mov rdi, r15
    mov rsi, r12
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lelsc_bad
.Lelsc_hash_record:
    lea rdi, [rsp + LSC_hash]
    lea rsi, [r14 + LR_pathlen]
    mov edx, 4
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    mov rsi, r15
    mov rdx, r12
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [r14 + LR_size]
    mov edx, 12
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [r14 + LR_hash]
    mov edx, 32
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [r14 + LR_roles]
    mov edx, 4
    call sha256_update
    mov rax, [r14 + LR_datalen]
    mov r14, [rsp + LSC_data]
    add r14, rax
    inc r13
    jmp .Lelsc_record
.Lelsc_finish:
    cmp r14, [rsp + LSC_end]
    jne .Lelsc_bad
    cmp qword ptr [rsp + LSC_flags], 3
    jne .Lelsc_bad
    mov rbx, [rsp + LSC_base]
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rbx + LS_programlen]
    mov edx, 4
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rbx + LS_HEADER]
    mov edx, [rbx + LS_programlen]
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rbx + LS_scriptlen]
    mov edx, 4
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rbx + LS_HEADER]
    mov eax, [rbx + LS_programlen]
    add rsi, rax
    mov edx, [rbx + LS_scriptlen]
    call sha256_update
    lea rdi, [rsp + LSC_hash]
    lea rsi, [rsp + LSC_digest]
    call sha256_final
    lea rdi, [rsp + LSC_digest]
    lea rsi, [rbx + LS_source]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lelsc_bad
    xor eax, eax
    mov rdx, [rsp + LSC_records]
    EPILOGUE
.Lelsc_bad:
    mov rax, -EV_CHANGED
    xor edx, edx
    EPILOGUE
.section .rodata
elsc_domain: .asciz "rhun-legacy-sources-v1"
elsc_manifest: .asciz "extension.ini"
elsc_syntax: .asciz "syntax/"
elsc_themes: .asciz "themes/"
elsc_syn: .asciz ".syn"
elsc_theme: .asciz ".theme"
