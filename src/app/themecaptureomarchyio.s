# Isolated helper only. One complete Omarchy observation, no live registry mutation.
.include "rhun.inc"
.include "app/themecapture.inc"
.section .rodata
tcoi_name: .asciz "/theme.name"
tcoi_colors: .asciz "/theme/colors.toml"
tcoi_marker: .asciz "/theme/light.mode"
tcoi_one: .byte 1
.text
# capture(dir,scope1/2,outTOB240,deadline)->primary/cleanup; untouched output on failure.
# Success transfers only name bytes; caller must release TOB_name with checked helper cleanup.
FN tc_omarchy_capture
    PROLOGUE 4496
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsp
    xor esi, esi
    mov edx, 4496
    call memset
    test rbx, rbx
    jz .Ltcoi_bad
    test r13, r13
    jz .Ltcoi_bad
    lea rax, [r12 - 1]
    cmp rax, 1
    ja .Ltcoi_bad
    test r14, r14
    jle .Ltcoi_bad
    mov rdi, rbx
    call tc_path_len
    test rax, rax
    js .Ltcoi_error
    cmp rax, TC_DIR_MAX
    ja .Ltcoi_long
    mov r15, rax
    mov [rsp + TOB_scope], r12
    mov qword ptr [rsp + TOB_records + 48], 2
    mov qword ptr [rsp + TOB_records + 96], 2
    lea rsi, [rip + tcoi_name]
    call .Ltcoi_path
    lea rdi, [rsp + 400]
    mov esi, TC_NAME_CAP
    lea rdx, [rsp + 240]
    mov rcx, r14
    call tc_file_capture
    mov [rsp + 288], rax
    mov [rsp + 296], rdx
    test rdx, rdx
    js .Ltcoi_capture_error
    cmp rax, -2
    je .Ltcoi_name_done
    test rax, rax
    js .Ltcoi_capture_error
    mov rax, [rsp + 240]
    mov [rsp + TOB_name], rax
    mov rax, [rsp + 248]
    mov [rsp + TOB_raw_length], rax
    mov qword ptr [rsp + TOB_records], 1
    mov [rsp + TOB_records + 8], rax
    lea rdi, [rsp + TOB_records + 16]
    lea rsi, [rsp + 256]
    mov edx, 32
    call memcpy
    mov rdi, [rsp + TOB_name]
    mov rsi, [rsp + TOB_raw_length]
    call tc_omarchy_effective
    test rax, rax
    js .Ltcoi_error
    mov [rsp + TOB_length], rax
    or qword ptr [rsp + TOB_presence], 1
.Ltcoi_name_done:
    cmp r12, TC_SCOPE_NAME
    je .Ltcoi_proof
    mov qword ptr [rsp + TOB_records + 48], 0
    lea rsi, [rip + tcoi_colors]
    call .Ltcoi_path
    lea rdi, [rsp + 400]
    mov esi, TC_THEME_CAP
    lea rdx, [rsp + 240]
    mov rcx, r14
    call tc_file_capture
    mov [rsp + 288], rax
    mov [rsp + 296], rdx
    test rdx, rdx
    js .Ltcoi_capture_error
    cmp rax, -2
    je .Ltcoi_marker
    test rax, rax
    js .Ltcoi_capture_error
    mov rax, [rsp + 240]
    mov [rsp + 304], rax
    mov rax, [rsp + 248]
    mov qword ptr [rsp + TOB_records + 48], 1
    mov [rsp + TOB_records + 56], rax
    lea rdi, [rsp + TOB_records + 64]
    lea rsi, [rsp + 256]
    mov edx, 32
    call memcpy
    or qword ptr [rsp + TOB_presence], 2
    mov rdi, [rsp + 304]
    mov rsi, [rsp + 248]
    call tc_omarchy_light
    test rax, rax
    js .Ltcoi_error
    mov [rsp + TOB_light], rax
    lea rdi, [rsp + 304]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    js .Ltcoi_cleanup_error
    cmp qword ptr [rsp + TOB_light], 0
    jne .Ltcoi_proof
.Ltcoi_marker:
    mov qword ptr [rsp + TOB_records + 96], 0
    lea rsi, [rip + tcoi_marker]
    call .Ltcoi_path
    lea rdi, [rsp + 400]
    mov rsi, r14
    call tc_marker_presence
    test rax, rax
    js .Ltcoi_error
    or qword ptr [rsp + TOB_presence], 8
    test rax, rax
    jz .Ltcoi_proof
    or qword ptr [rsp + TOB_presence], 4
    mov qword ptr [rsp + TOB_records + 96], 1
    mov qword ptr [rsp + TOB_light], 1
    lea rdi, [rip + tcoi_one]
    mov esi, 1
    lea rdx, [rsp + TOB_records + 112]
    call sha256_hash
    test eax, eax
    jz .Ltcoi_io
.Ltcoi_proof:
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcoi_error
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    lea rcx, [rsp + TOB_records]
    lea r8, [rsp + TOB_proof]
    call tc_omarchy_proof
    test rax, rax
    js .Ltcoi_error
    mov rdi, r13
    mov rsi, rsp
    mov edx, TOB_SIZE
    call memcpy
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Ltcoi_capture_error:
    mov rax, [rsp + 288]
    mov [rsp + TOB_primary], rax
    mov rax, [rsp + 296]
    mov [rsp + TOB_cleanup], rax
    jmp .Ltcoi_dispose
.Ltcoi_cleanup_error:
    mov [rsp + TOB_cleanup], rax
    jmp .Ltcoi_dispose
.Ltcoi_io:
    mov rax, -5
    jmp .Ltcoi_error
.Ltcoi_long:
    mov rax, -36
    jmp .Ltcoi_error
.Ltcoi_bad:
    mov rax, -22
.Ltcoi_error:
    mov [rsp + TOB_primary], rax
.Ltcoi_dispose:
    lea rdi, [rsp + 304]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 1f
    cmp qword ptr [rsp + TOB_cleanup], 0
    jne 1f
    mov [rsp + TOB_cleanup], rax
1:  lea rdi, [rsp + TOB_name]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 2f
    cmp qword ptr [rsp + TOB_cleanup], 0
    jne 2f
    mov [rsp + TOB_cleanup], rax
2:  mov rax, [rsp + TOB_primary]
    mov rdx, [rsp + TOB_cleanup]
    EPILOGUE
# Internal stack path builder: copies the validated directory plus a fixed suffix.
# CALL adds8: caller local path starts at rsp+408 here.
.Ltcoi_path:
    push rsi
    lea rdi, [rsp + 416]
    mov rsi, rbx
    mov rdx, r15
    call memcpy
    pop rsi
    lea rdi, [rsp + r15 + 408]
    jmp cstr_copy

# Presence semantics match ordinary legacy lookup, only clean ENOENT is absence.
FN tc_marker_presence
.ifdef WINDOWS
    jmp win_tc_marker_presence
.else
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  mov rdi, r12
    call tc_before_deadline
    test rax, rax
    js 2f
    mov rdi, rbx
    xor esi, esi
    SYS SYS_access
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jz 3f
    cmp rax, -2
    jne 2f
    xor eax, eax
    EPILOGUE
3:  mov eax, 1
2:  EPILOGUE
.endif
