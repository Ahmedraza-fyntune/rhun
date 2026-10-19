# Strict managed metadata checks run before the actual private manifest callbacks.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatemanifest.inc"
.text
# Counted string table lookup -> index/-1.
evm_lookup:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  mov rdx, [r13 + r14*8]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 9f
    inc r14
    jmp 1b
8:  mov r14, -1
9:  mov rax, r14
    EPILOGUE

# ASCII managed identity, no leading dot. Unlike folder spellings these are logical bytes.
FN ext_validate_identity
    mov esi, 100
    push rdi
    call ext_root_length
    pop rdi
    test rax, rax
    jle 8f
    cmp byte ptr [rdi], '.'
    je 8f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    cmp edx, '.'
    je 2f
    cmp edx, '_'
    je 2f
    cmp edx, '-'
    je 2f
    cmp edx, '0'
    jb 8f
    cmp edx, '9'
    jbe 2f
    or edx, 32
    cmp edx, 'a'
    jb 8f
    cmp edx, 'z'
    ja 8f
2:  inc rcx
    cmp rcx, rax
    jb 1b
    ret
8:  xor eax, eax
    ret

# Printable scalar text; validity includes shortest UTF8 and excludes C0/C1 controls.
FN ext_validate_text
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rsi, rsi
    jz 8f
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    xor r13d, r13d
1:  lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp eax, 32
    jb 8f
    cmp eax, 127
    jb 2f
    cmp eax, 160
    jb 8f
2:  add r13, rdx
    cmp r13, r12
    jb 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Strict decimal int31, allowing leading zeros without wrap. -> value, edx 1/0.
evm_int:
    xor eax, eax
    xor ecx, ecx
    test rsi, rsi
    jz 8f
1:  movzx r8d, byte ptr [rdi + rcx]
    sub r8d, '0'
    cmp r8d, 9
    ja 8f
    cmp eax, 214748364
    ja 8f
    jne 2f
    cmp r8d, 7
    ja 8f
2:  imul eax, eax, 10
    add eax, r8d
    inc rcx
    cmp rcx, rsi
    jb 1b
    mov edx, 1
    ret
8:  xor edx, edx
    ret

# Private raw setting records retain presence, avoiding all loader default coercion.
evm_setting:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r14, [r12 + INI_key]
    mov r13, [r12 + INI_keylen]
1:  test r13, r13
    jz .Levms_bad
    dec r13
    cmp byte ptr [r14 + r13], '.'
    jne 1b
    test r13, r13
    jz .Levms_bad
    cmp r13, 64
    ja .Levms_bad
    lea r15, [r14 + r13 + 1]
    mov rax, [r12 + INI_keylen]
    sub rax, r13
    dec rax
    mov [rsp], rax
    xor ecx, ecx
2:  movzx eax, byte ptr [r14 + rcx]
    cmp eax, '_'
    je 3f
    cmp eax, 'a'
    jb 21f
    cmp eax, 'z'
    jbe 3f
21: cmp eax, '0'
    jb .Levms_bad
    cmp eax, '9'
    ja .Levms_bad
3:  inc rcx
    cmp rcx, r13
    jb 2b
    mov qword ptr [rsp + 8], 0
4:  mov rax, [rsp + 8]
    cmp rax, [rbx + MV_nsettings]
    jae 5f
    imul rax, rax, MV_SETTING_SIZE
    lea rax, [rbx + MV_settings + rax]
    mov [rsp + 16], rax
    cmp [rax + 8], r13
    jne 41f
    mov rdi, [rax]
    mov rsi, r14
    mov rdx, r13
    call memeq
    test eax, eax
    jnz 6f
41: inc qword ptr [rsp + 8]
    jmp 4b
5:  cmp rax, 256
    jae .Levms_bad
    inc qword ptr [rbx + MV_nsettings]
    imul rax, rax, MV_SETTING_SIZE
    lea rax, [rbx + MV_settings + rax]
    mov [rsp + 16], rax
    mov [rax], r14
    mov [rax + 8], r13
6:  mov rdi, r15
    mov rsi, [rsp]
    lea rdx, [rip + evm_fields]
    call evm_lookup
    test rax, rax
    js .Levms_ok               # unknown optional fields retain ignore behavior
    mov r13, rax
    mov rcx, rax
    mov eax, 1
    shl rax, cl
    mov r15, [rsp + 16]
    test [r15 + 16], rax
    jnz .Levms_bad
    or [r15 + 16], rax
    shl r13, 4
    mov rax, [r12 + INI_val]
    mov [r15 + r13 + 24], rax
    mov rax, [r12 + INI_vallen]
    mov [r15 + r13 + 32], rax
.Levms_ok:
    xor eax, eax
    EPILOGUE
.Levms_bad:
    mov rax, -EV_BAD_SETTINGS
    EPILOGUE

# Validate one complete setting: type, noncoerced defaults, ranges and choices.
evm_setting_check:
    PROLOGUE 48
    mov rbx, rdi
    xor r12d, r12d             # string is the default type
    test qword ptr [rbx + 16], 1
    jz 1f
    mov rdi, [rbx + 24]
    mov rsi, [rbx + 32]
    lea rdx, [rip + evm_types]
    call evm_lookup
    test rax, rax
    js .Levmsc_bad
    mov r12, rax
1:  cmp r12, SDT_INT
    je .Levmsc_int
    test qword ptr [rbx + 16], 0x60 # min/max only apply to integer settings
    jnz .Levmsc_bad
    cmp r12, SDT_CHOICE
    je .Levmsc_choice
    test qword ptr [rbx + 16], 0x10 # options apply only to choices
    jnz .Levmsc_bad
    cmp r12, SDT_BOOL
    jne .Levmsc_good
    test qword ptr [rbx + 16], 2
    jz .Levmsc_good
    mov rdi, [rbx + 40]
    mov rsi, [rbx + 48]
    lea rdx, [rip + evm_yesno]
    call evm_lookup
    test rax, rax
    js .Levmsc_bad
    jmp .Levmsc_good
.Levmsc_int:
    test qword ptr [rbx + 16], 0x10
    jnz .Levmsc_bad
    xor r13d, r13d
    mov r14d, 0x7fffffff
    test qword ptr [rbx + 16], 0x20
    jz 2f
    mov rdi, [rbx + 104]
    mov rsi, [rbx + 112]
    call evm_int
    test edx, edx
    jz .Levmsc_bad
    mov r13, rax
2:  test qword ptr [rbx + 16], 0x40
    jz 3f
    mov rdi, [rbx + 120]
    mov rsi, [rbx + 128]
    call evm_int
    test edx, edx
    jz .Levmsc_bad
    mov r14, rax
3:  cmp r13, r14
    ja .Levmsc_bad
    test qword ptr [rbx + 16], 2
    jz .Levmsc_good
    mov rdi, [rbx + 40]
    mov rsi, [rbx + 48]
    call evm_int
    test edx, edx
    jz .Levmsc_bad
    cmp rax, r13
    jb .Levmsc_bad
    cmp rax, r14
    ja .Levmsc_bad
    jmp .Levmsc_good
.Levmsc_choice:
    test qword ptr [rbx + 16], 0x10
    jz .Levmsc_bad
    mov r12, [rbx + 88]        # option bytes
    mov r13, [rbx + 96]
    test r13, r13
    jz .Levmsc_bad
    mov qword ptr [rsp + 32], 0 # any option
    mov qword ptr [rsp + 40], 0 # default matched
.Levmsc_next:
    test r13, r13
    jz .Levmsc_options_done
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz .Levmsc_options_done
    mov r14, rax
    mov r15, rdx
    mov qword ptr [rsp + 32], 1
    mov rdi, rax
    mov rsi, rdx
    call ext_validate_text
    test eax, eax
    jz .Levmsc_bad
    # Compare this token against every preceding token for duplicate option ambiguity.
    mov rax, [rbx + 88]
    mov [rsp], rax
    mov rax, r14
    sub rax, [rbx + 88]
    mov [rsp + 8], rax
4:  cmp qword ptr [rsp + 8], 0
    je 6f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call next_word
    add [rsp], rcx
    sub [rsp + 8], rcx
    test rdx, rdx
    jz 6f
    cmp rdx, r15
    jne 4b
    mov rdi, rax
    mov rsi, r14
    call memeq
    test eax, eax
    jnz .Levmsc_bad
    jmp 4b
6:  test qword ptr [rbx + 16], 2
    jz .Levmsc_next
    cmp [rbx + 48], r15
    jne .Levmsc_next
    mov rdi, [rbx + 40]
    mov rsi, r14
    mov rdx, r15
    call memeq
    test eax, eax
    jz .Levmsc_next
    mov qword ptr [rsp + 40], 1
    jmp .Levmsc_next
.Levmsc_options_done:
    cmp qword ptr [rsp + 32], 0
    je .Levmsc_bad
    test qword ptr [rbx + 16], 2
    jz .Levmsc_good
    cmp qword ptr [rsp + 40], 0
    je .Levmsc_bad
.Levmsc_good:
    xor eax, eax
    EPILOGUE
.Levmsc_bad:
    mov rax, -EV_BAD_SETTINGS
    EPILOGUE

# Snapshot a regular rooted file, exact initial length plus EOF, <= caller cap.
# (rawFile,cap) -> owned bytes/count; 0/negative error. Always closes the supplied file.
FN ext_validate_snapshot
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Levs_close_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Levs_bad
    mov r13, [rsp + ER_size]
    cmp r13, r12
    ja .Levs_large
    lea rdi, [r13 + 1]
    call mem_alloc_try
    test rax, rax
    jz .Levs_oom
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, r13
    jae 2f
    mov rdi, rbx
    lea rsi, [r14 + r15]
    mov rdx, r13
    sub rdx, r15
    mov rcx, r15
    call ext_root_read
    test rax, rax
    jle .Levs_changed
    add r15, rax
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [rsp + 40]
    mov edx, 1
    mov rcx, r13
    call ext_root_read
    test rax, rax
    jnz .Levs_changed
    mov byte ptr [r14 + r13], 0
    mov r15, -1
    mov rdi, rbx
    call ext_root_close
    test rax, rax
    js .Levs_free_error
    mov rax, r14
    mov rdx, r13
    EPILOGUE
.Levs_changed:
    mov rax, -EV_CHANGED
.Levs_free_error:
    mov r12, rax
    mov rdi, r14
    call mem_free
    mov rax, r12
    # Close already attempted on the successful-read close failure path.
    cmp r15, -1
    je .Levs_error
.Levs_close_error:
    mov r12, rax
    mov rdi, rbx
    call ext_root_close
    mov rax, r12
.Levs_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.Levs_bad:
    mov rax, -EV_BAD_MANIFEST
    jmp .Levs_close_error
.Levs_large:
    mov rax, -EV_RESOURCE
    jmp .Levs_close_error
.Levs_oom:
    mov rax, -12
    jmp .Levs_close_error

# Strict raw lines. Real callbacks run only after all raw settings are accepted.
evm_raw:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + MV_buffer]
    mov rdx, [rbx + MV_len]
    call ini_init
.Levmr_next:
    mov rdi, rbx
    call ini_next
    test eax, eax
    jz .Levmr_end
    cmp qword ptr [rbx + INI_seclen], 0
    jne .Levmr_section
    mov rdi, [rbx + INI_key]
    mov rsi, [rbx + INI_keylen]
    lea rdx, [rip + evm_topkeys]
    call evm_lookup
    test rax, rax
    js .Levmr_next
    mov r12, rax
    mov rcx, rax
    mov eax, 1
    shl rax, cl
    test [rbx + MV_flags], rax
    jnz .Levmr_bad
    or [rbx + MV_flags], rax
    shl r12, 4
    mov rax, [rbx + INI_val]
    mov [rbx + MV_top + r12], rax
    mov rax, [rbx + INI_vallen]
    mov [rbx + MV_top + r12 + 8], rax
    jmp .Levmr_next
.Levmr_section:
    mov rdi, rbx
    lea rsi, [rip + evm_settings]
    call ini_sec_is
    test eax, eax
    jz .Levmr_next
    mov rdi, rbx
    mov rsi, rbx
    call evm_setting
    test rax, rax
    jnz .Levmr_return
    jmp .Levmr_next
.Levmr_end:
    mov rax, [rbx + MV_flags]
    and eax, 0x1f
    cmp eax, 0x1f
    jne .Levmr_bad
    # Identity is copied to bounded stack by this checker, not passed as an unterminated INI span.
    mov rdi, rbx
    xor esi, esi
    call evm_identity_pair
    test rax, rax
    jz .Levmr_bad_id
    mov rdi, rbx
    mov esi, 1
    call evm_identity_pair
    test rax, rax
    jz .Levmr_bad_id
    mov rdi, [rbx + MV_top + MT_TITLE*16]
    mov rsi, [rbx + MV_top + MT_TITLE*16 + 8]
    cmp rsi, 128
    ja .Levmr_bad
    call ext_validate_text
    test eax, eax
    jz .Levmr_bad
    mov rdi, [rbx + MV_top + MT_VERSION*16]
    mov rsi, [rbx + MV_top + MT_VERSION*16 + 8]
    cmp rsi, 64
    ja .Levmr_bad
    call ext_validate_text
    test eax, eax
    jz .Levmr_bad
    cmp qword ptr [rbx + MV_top + MT_PROTOCOL*16 + 8], 1
    jne .Levmr_bad
    mov rax, [rbx + MV_top + MT_PROTOCOL*16]
    cmp byte ptr [rax], '1'
    jne .Levmr_bad
    test qword ptr [rbx + MV_flags], 1 << MT_RUNTIME
    jz 1f
    test qword ptr [rbx + MV_flags], 1 << MT_RUN
    jz .Levmr_bad
    test qword ptr [rbx + MV_flags], 1 << MT_TARGET
    jnz .Levmr_bad
    jmp 2f
1:  test qword ptr [rbx + MV_flags], 1 << MT_RUN
    jnz .Levmr_bad
    test qword ptr [rbx + MV_flags], 1 << MT_TARGET
    jz .Levmr_bad
2:  xor r12d, r12d
3:  cmp r12, [rbx + MV_nsettings]
    jae .Levmr_ok
    imul rdi, r12, MV_SETTING_SIZE
    lea rdi, [rbx + MV_settings + rdi]
    call evm_setting_check
    test rax, rax
    jnz .Levmr_return
    inc r12
    jmp 3b
.Levmr_ok:
    xor eax, eax
.Levmr_return:
    EPILOGUE
.Levmr_bad:
    mov rax, -EV_BAD_MANIFEST
    EPILOGUE
.Levmr_bad_id:
    mov rax, -EV_BAD_ID
    EPILOGUE

evm_identity_pair:
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    shl rsi, 4
    mov r13, [rbx + MV_top + rsi + 8]
    test r13, r13
    jz 8f
    cmp r13, 100
    ja 8f
    mov rsi, [rbx + MV_top + rsi]
    mov rdi, rsp
    mov rdx, r13
    call memcpy
    mov byte ptr [rsp + r13], 0
    mov rdi, rsp
    call ext_validate_identity
    test rax, rax
    jz 8f
    mov rdi, rsp
    mov rsi, [rbx + MV_owner + r12*8]
    call strcmp_eq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Pure counted raw check shared by private preparation. Caller supplies zeroable MV_SIZE.
FN ext_manifest_check_bytes
    PROLOGUE 32
    mov rbx, r8
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov rdi, rbx
    xor esi, esi
    mov edx, MV_SIZE
    call memset
    mov rax, [rsp]
    mov [rbx + MV_buffer], rax
    mov rax, [rsp + 8]
    mov [rbx + MV_len], rax
    mov rax, [rsp + 16]
    mov [rbx + MV_owner], rax
    mov rax, [rsp + 24]
    mov [rbx + MV_name], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    cmp rsi, 65536
    ja 8f
    call prep_ini_text_valid
    test eax, eax
    jz 8f
    mov rdi, rbx
    call evm_raw
    EPILOGUE
8:  mov rax, -EV_BAD_MANIFEST
    EPILOGUE

# ext_validate_manifest(rootHandle,dir,owner,name). Never calls app_init/ext_load/ext_init.
FN ext_validate_manifest
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov edi, MV_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Levm_oom
    mov rbx, rax
    mov rax, [rsp]
    mov [rbx + MV_root], rax
    mov rax, [rsp + 8]
    mov [rbx + MV_dir], rax
    mov rax, [rsp + 16]
    mov [rbx + MV_owner], rax
    mov rax, [rsp + 24]
    mov [rbx + MV_name], rax
    mov rdi, [rbx + MV_root]
    lea rsi, [rip + evm_manifest]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Levm_error
    mov rdi, rax
    mov esi, 65536
    call ext_validate_snapshot
    test rax, rax
    jz .Levm_snapshot_error
    mov [rbx + MV_buffer], rax
    mov [rbx + MV_len], rdx
    mov rdi, rax
    mov rsi, rdx
    call snippet_utf8_valid
    test eax, eax
    jz .Levm_bad
    xor r12d, r12d
1:  cmp r12, [rbx + MV_len]
    jae 3f
    mov rdi, [rbx + MV_buffer]
    add rdi, r12
    mov rsi, [rbx + MV_len]
    sub rsi, r12
    call utf8_decode
    cmp eax, 9
    je 2f
    cmp eax, 10
    je 2f
    cmp eax, 13
    je 2f
    cmp eax, 32
    jb .Levm_bad
    cmp eax, 127
    jb 2f
    cmp eax, 160
    jb .Levm_bad
2:  add r12, rdx
    jmp 1b
3:  mov rdi, rbx
    call evm_raw
    test rax, rax
    jnz .Levm_error
    lea rdi, [rbx + MV_ext]
    mov rsi, [rbx + MV_buffer]
    mov rdx, [rbx + MV_len]
    mov rcx, [rbx + MV_dir]
    call ext_manifest_parse_private
    # Preserve the actual loader's additional needs.run path-token bound.
    mov r12, [rbx + MV_ext + EXT_runs]
    test r12, r12
    jz 5f
    mov rdi, r12
    call strlen
    mov r13, rax
4:  test r13, r13
    jz 5f
    mov rdi, r12
    mov rsi, r13
    call next_word
    cmp rdx, 4096
    jae .Levm_bad
    add r12, rcx
    sub r13, rcx
    jmp 4b
5:  cmp dword ptr [rbx + MV_ext + EXT_hello], 1
    jne .Levm_bad
    cmp qword ptr [rbx + MV_ext + EXT_prog], 0
    je .Levm_bad
    mov rdi, [rbx + MV_root]
    mov rsi, [rbx + MV_dir]
    mov rax, MT_TARGET
    test qword ptr [rbx + MV_flags], 1 << MT_RUNTIME
    jz 6f
    mov eax, MT_RUN
6:  shl rax, 4
    mov rdx, [rbx + MV_top + rax]
    mov rcx, [rbx + MV_top + rax + 8]
    mov r8, [rbx + MV_top + MT_RUNTIME*16]
    mov r9, [rbx + MV_top + MT_RUNTIME*16 + 8]
    call ext_validate_launch
    jmp .Levm_error
.Levm_bad:
    mov rax, -EV_BAD_MANIFEST
    jmp .Levm_error
.Levm_snapshot_error:
    mov rax, rdx
.Levm_error:
    mov r15, rax
    mov rdi, [rbx + MV_buffer]
    call mem_free
    mov rdi, rbx
    call mem_free
    mov rax, r15
    EPILOGUE
.Levm_oom:
    mov rax, -12
    EPILOGUE
.section .rodata
evm_manifest: .asciz "extension.ini"
evm_settings: .asciz "settings"
evm_topkeys:
    .quad evm_owner,evm_name,evm_title,evm_version,evm_protocol,evm_target,evm_runtime,evm_run
    .quad evm_args,evm_description,evm_icon,evm_color,evm_on,0
evm_owner: .asciz "owner"
evm_name: .asciz "name"
evm_title: .asciz "title"
evm_version: .asciz "version"
evm_protocol: .asciz "protocol"
.ifdef WINDOWS
evm_target: .asciz "run.windows-x64"
.else
.ifdef MACOS
evm_target: .asciz "run.macos-arm64"
.else
evm_target: .asciz "run.linux-x86_64"
.endif
.endif
evm_runtime: .asciz "runtime"
evm_run: .asciz "run"
evm_args: .asciz "args"
evm_description: .asciz "description"
evm_icon: .asciz "icon"
evm_color: .asciz "color"
evm_on: .asciz "on"
evm_fields: .quad evm_type,evm_default,evm_title,evm_description,evm_options,evm_min,evm_max,0
evm_type: .asciz "type"
evm_default: .asciz "default"
evm_options: .asciz "options"
evm_min: .asciz "min"
evm_max: .asciz "max"
evm_types: .quad evm_string,evm_bool,evm_int_type,evm_choice,0
evm_string: .asciz "string"
evm_bool: .asciz "bool"
evm_int_type: .asciz "int"
evm_choice: .asciz "choice"
evm_yesno: .quad evm_yes,evm_no,0
evm_yes: .asciz "yes"
evm_no: .asciz "no"
