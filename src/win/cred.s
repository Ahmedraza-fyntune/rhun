# Windows: extensions' secrets in the Credential Manager (src/app/secrets.s). Generic credentials
# named "rhun extension OWNER/NAME/KEY" (the service, a slash, the key), kept on this computer
# (CRED_PERSIST_LOCAL_MACHINE, not roaming). A credential holds at most 2560 bytes, so a longer
# value is split into KEY, KEY#2, KEY#3 and KEY#4 (a key never has a "#"). The calls are quick and
# answer at once.
.include "win.inc"

.equ CRED_TYPE_GENERIC, 1
.equ CRED_PERSIST_LOCAL_MACHINE, 2
.equ CRED_BLOB_MAX, 2560
.equ CRED_PARTS, 4
.equ ERROR_NOT_FOUND, 1168
# the frame of win_cred_op
.equ CF_CRED, 96                # CREDENTIALW, 80 bytes
.equ CF_PTR, 176                # PCREDENTIALW from CredReadW
.equ CF_UTF8, 192               # a target name, UTF-8, 1024 bytes
.equ CF_WIDE, 1216              # the same, UTF-16, 1024 units
.equ CF_SIZE, 3264

.text

# win_cred_op(sr): the request, answered in SECR_status and SECR_buf
FN win_cred_op
    PROLOGUE CF_SIZE
    mov rbx, rdi
    mov dword ptr [rbx + SECR_status], SECS_REFUSED
    mov qword ptr [rbx + SECR_outlen], 0
    mov eax, [rbx + SECR_op]
    cmp eax, SECO_GET
    je .Lco_get
    cmp eax, SECO_SET
    je .Lco_set
    cmp eax, SECO_DELETE
    je .Lco_delete
    cmp eax, SECO_KEYS
    je .Lco_keys
    cmp eax, SECO_CLEAR
    je .Lco_clear
    EPILOGUE

.Lco_get:
    mov r12d, 1                 # the part
1:  mov rdi, rbx
    mov esi, r12d
    lea rdx, [rsp + CF_UTF8]
    lea rcx, [rsp + CF_WIDE]
    call target_name
    lea rcx, [rsp + CF_WIDE]
    mov edx, CRED_TYPE_GENERIC
    xor r8d, r8d
    lea r9, [rsp + CF_PTR]
    API CredReadW
    test eax, eax
    jnz 2f
    cmp r12d, 1
    jne 8f                      # a later part missing: the value ends
    API GetLastError
    cmp eax, ERROR_NOT_FOUND
    jne 9f
    mov dword ptr [rbx + SECR_status], SECS_NONE
    EPILOGUE
2:  mov r13, [rsp + CF_PTR]
    mov r14d, [r13 + 32]        # CredentialBlobSize
    mov rax, [rbx + SECR_outlen]
    lea rcx, [rax + r14]
    cmp rcx, SECRET_VALUE_MAX
    ja 3f
    lea rdi, [rbx + SECR_buf + rax]
    mov rsi, [r13 + 40]         # CredentialBlob
    mov rdx, r14
    call memcpy
    add [rbx + SECR_outlen], r14
3:  mov rcx, r13
    API CredFree
    cmp r14d, CRED_BLOB_MAX
    jne 8f
    inc r12d
    cmp r12d, CRED_PARTS
    jbe 1b
8:  mov dword ptr [rbx + SECR_status], SECS_OK
9:  EPILOGUE

.Lco_set:
    # a new key needs room: SECRET_KEYS_MAX at most
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rsp + CF_UTF8]
    lea rcx, [rsp + CF_WIDE]
    call target_name
    lea rcx, [rsp + CF_WIDE]
    mov edx, CRED_TYPE_GENERIC
    xor r8d, r8d
    lea r9, [rsp + CF_PTR]
    API CredReadW
    test eax, eax
    jz 1f
    mov rcx, [rsp + CF_PTR]
    API CredFree
    jmp 2f
1:  mov rdi, rbx
    lea rsi, [rsp + CF_UTF8]
    lea rdx, [rsp + CF_WIDE]
    call key_count
    cmp eax, SECRET_KEYS_MAX
    jb 2f
    mov dword ptr [rbx + SECR_status], SECS_TOOBIG
    EPILOGUE
2:  xor r12d, r12d              # bytes written
    mov r13d, 1                 # the part
3:  mov rdi, rbx
    mov esi, r13d
    lea rdx, [rsp + CF_UTF8]
    lea rcx, [rsp + CF_WIDE]
    call target_name
    lea rdi, [rsp + CF_CRED]
    xor esi, esi
    mov edx, 80
    call memset
    mov dword ptr [rsp + CF_CRED + 4], CRED_TYPE_GENERIC
    lea rax, [rsp + CF_WIDE]
    mov [rsp + CF_CRED + 8], rax            # TargetName
    mov r14, [rbx + SECR_len]
    sub r14, r12
    cmp r14, CRED_BLOB_MAX
    jbe 4f
    mov r14d, CRED_BLOB_MAX
4:  mov [rsp + CF_CRED + 32], r14d          # CredentialBlobSize
    mov rax, [rbx + SECR_val]
    add rax, r12
    mov [rsp + CF_CRED + 40], rax           # CredentialBlob
    mov dword ptr [rsp + CF_CRED + 48], CRED_PERSIST_LOCAL_MACHINE
    lea rcx, [rsp + CF_CRED]
    xor edx, edx
    API CredWriteW
    test eax, eax
    jz 9b
    add r12, r14
    inc r13d
    cmp r12, [rbx + SECR_len]
    jb 3b
    # the parts a longer value left behind go
5:  cmp r13d, CRED_PARTS
    ja 8b
    mov rdi, rbx
    mov esi, r13d
    lea rdx, [rsp + CF_UTF8]
    lea rcx, [rsp + CF_WIDE]
    call target_name
    lea rcx, [rsp + CF_WIDE]
    mov edx, CRED_TYPE_GENERIC
    xor r8d, r8d
    API CredDeleteW
    inc r13d
    jmp 5b

.Lco_delete:
    mov r13d, 1
    jmp 5b

.Lco_keys:
    mov rdi, rbx
    lea rsi, [rsp + CF_UTF8]
    lea rdx, [rsp + CF_WIDE]
    call enumerate
    test eax, eax
    js 9b
    jz 8b
    mov r12d, eax
    xor r13d, r13d
1:  cmp r13d, r12d
    jae 7f
    mov rax, [rip + en_array]
    mov rax, [rax + r13*8]
    inc r13d
    mov rcx, [rax + 8]          # TargetName, UTF-16
    lea rdi, [rsp + CF_UTF8]
    mov esi, 1024
    call to_utf8
    test eax, eax
    jz 1b
    # past "SERVICE/"; a part ("#2") is not a key
    mov rdi, [rbx + SECR_service]
    call strlen
    lea r14, [rsp + CF_UTF8 + rax + 1]
    mov rdi, r14
    call strlen
    mov r15, rax
    test r15, r15
    jz 1b
    xor ecx, ecx
2:  cmp rcx, r15
    jae 3f
    cmp byte ptr [r14 + rcx], '#'
    je 1b
    inc rcx
    jmp 2b
3:  mov rax, [rbx + SECR_outlen]
    lea rcx, [rax + r15 + 1]
    cmp rcx, SECRET_BUF
    ja 1b
    lea rdi, [rbx + SECR_buf + rax]
    mov rsi, r14
    mov rdx, r15
    call memcpy
    mov rax, [rbx + SECR_outlen]
    add rax, r15
    mov byte ptr [rbx + SECR_buf + rax], 10
    inc rax
    mov [rbx + SECR_outlen], rax
    jmp 1b
7:  mov rcx, [rip + en_array]
    API CredFree
    jmp 8b

.Lco_clear:
    mov rdi, rbx
    lea rsi, [rsp + CF_UTF8]
    lea rdx, [rsp + CF_WIDE]
    call enumerate
    test eax, eax
    js 9b
    jz 8b
    mov r12d, eax
    xor r13d, r13d
1:  cmp r13d, r12d
    jae 7b
    mov rax, [rip + en_array]
    mov rax, [rax + r13*8]
    inc r13d
    mov rcx, [rax + 8]
    mov edx, CRED_TYPE_GENERIC
    xor r8d, r8d
    API CredDeleteW
    jmp 1b

# target_name(sr, part, utf8 buffer, wide buffer): "SERVICE/KEY", "SERVICE/KEY#N" for a part after
# the first, in both buffers
target_name:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    mov rdi, r13
    mov rsi, [rbx + SECR_service]
    call cstr_copy
    mov byte ptr [rax], '/'
    lea rdi, [rax + 1]
    mov rsi, [rbx + SECR_key]
    call cstr_copy
    cmp r12d, 1
    je 1f
    mov byte ptr [rax], '#'
    add r12d, '0'
    mov [rax + 1], r12b
    mov byte ptr [rax + 2], 0
1:  mov rdi, r13
    mov rsi, r14
    call to_wide
    EPILOGUE

# to_wide(utf8 cstr, wide buffer of 1024 units)
to_wide:
    PROLOGUE 64
    mov r8, rdi
    mov ecx, 65001              # CP_UTF8
    xor edx, edx
    mov r9d, -1
    mov qword ptr [rsp + 32], rsi
    mov qword ptr [rsp + 40], 1024
    API MultiByteToWideChar
    EPILOGUE

# to_utf8(dst, cap, wide cstr in rcx) -> eax the bytes with the NUL, 0 when it did not fit
to_utf8:
    PROLOGUE 64
    mov rbx, rdi
    mov r12d, esi
    mov rdx, rcx
    mov ecx, 65001
    mov r8, rdx
    xor edx, edx
    mov r9d, -1
    mov [rsp + 32], rbx
    mov [rsp + 40], r12
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    EPILOGUE

# enumerate(sr, utf8 buffer, wide buffer) -> eax how many credentials the service has (their array
# in en_array, for CredFree), 0 for none, -1 when refused
enumerate:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, [rbx + SECR_service]
    call cstr_copy
    mov byte ptr [rax], '/'
    mov byte ptr [rax + 1], '*'
    mov byte ptr [rax + 2], 0
    mov rdi, r12
    mov rsi, r13
    call to_wide
    mov rcx, r13
    xor edx, edx
    lea r8, [rsp]
    mov qword ptr [rsp], 0
    lea r9, [rip + en_array]
    API CredEnumerateW
    test eax, eax
    jnz 1f
    API GetLastError
    cmp eax, ERROR_NOT_FOUND
    jne 8f
    xor eax, eax
    EPILOGUE
1:  mov eax, [rsp]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# key_count(sr, utf8 buffer, wide buffer) -> eax the keys it has (parts not counted)
key_count:
    PROLOGUE
    mov rbx, rdi
    call enumerate
    test eax, eax
    jle 8f
    mov r12d, eax
    xor r13d, r13d              # keys
    xor r14d, r14d
1:  cmp r14d, r12d
    jae 7f
    mov rax, [rip + en_array]
    mov rax, [rax + r14*8]
    inc r14d
    mov rcx, [rax + 8]
    # a part has "#" in its name
2:  movzx edx, word ptr [rcx]
    test edx, edx
    jz 3f
    add rcx, 2
    cmp edx, '#'
    jne 2b
    jmp 1b
3:  inc r13d
    jmp 1b
7:  mov rcx, [rip + en_array]
    API CredFree
    mov eax, r13d
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.bss
.p2align 3
en_array: .quad 0
