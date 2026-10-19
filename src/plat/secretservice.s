# Linux: extensions' secrets in the Secret Service (org.freedesktop.secrets: gnome-keyring,
# KWallet 5.97+, KeePassXC) over the session bus (src/app/secrets.s). Items carry the attributes
# service = "rhun extension OWNER/NAME" and account = KEY and live in the default collection.
#
# A connection of its own, opened at the first request: AUTH EXTERNAL, Hello and OpenSession
# ("plain": values cross the per-user session bus unencrypted, which only the user's processes can
# reach; DH-AES is not implemented) are awaited for a moment (D-Bus may start the keyring); no
# answer means no Secret Service, and secrets.s keeps secrets in memory. Each request is then a
# chain of calls answered on the loop's watch of the bus: SearchItems, Unlock (and its prompt,
# awaited through the prompt's Completed signal), GetSecret, CreateItem, Delete, the Attributes
# property.
.include "rhun.inc"
.ifndef MACOS
.ifndef WINDOWS

.equ SS_MSG_MAX, 1 << 20        # a message from the bus, at most
.equ SS_WAIT_MS, 2500           # connecting: the bus and the keyring may be starting
# what the request waits for (ss_step)
.equ ST_SEARCH_GET, 1
.equ ST_UNLOCK_GET, 2
.equ ST_GET, 3
.equ ST_UNLOCK_SET, 4
.equ ST_COUNT, 5
.equ ST_EXISTS, 6
.equ ST_CREATE, 7
.equ ST_SEARCH_DEL, 8
.equ ST_UNLOCK_DEL, 9
.equ ST_DELETE, 10
.equ ST_SEARCH_KEYS, 11
.equ ST_ATTRS, 12
.equ ST_PROMPT, 13              # Prompt was called; its Completed signal answers
.equ ST_CREATE_PROMPT, 14       # CreateItem's prompt
# message types
.equ MT_CALL, 1
.equ MT_REPLY, 2
.equ MT_ERROR, 3
.equ MT_SIGNAL, 4

.bss
.p2align 3
ss_in: .zero SB_SIZE            # bytes from the bus not handled yet
ss_msg: .zero SB_SIZE           # a message being built
ss_body: .zero SB_SIZE          # its body
mb: .quad 0                     # the buffer the b_* writers append to
ss_session: .zero SB_SIZE       # OpenSession's object path (cstr)
ss_prompt: .zero SB_SIZE        # the prompt being awaited (cstr)
ss_items: .zero SB_SIZE         # item paths of the request, each a cstr
ss_next_item: .quad 0           # the offset in ss_items of the next one to act on
ss_sr: .quad 0                  # the request being served
ss_tmp: .zero SB_SIZE
# the message being read: its header fields
m_type: .long 0
m_reply: .long 0
m_body: .quad 0                 # the body's offset
m_len: .quad 0
m_sig: .quad 0, 0               # ptr, len
m_member: .quad 0, 0
m_iface: .quad 0, 0
m_path: .quad 0, 0
m_error: .quad 0, 0
ss_after: .long 0               # the step a prompt's Completed signal continues with
ss_step: .long 0
ss_wait: .long 0                # the serial of the call the step waits for
ss_serial: .long 0
ss_state: .long 0               # 0 not tried, 1 open, -1 no Secret Service
.data
ss_fd: .long -1

.text

# FN ss_start(sr) -> eax 0 when the request went to the service (secrets_done follows), -1 when
# no Secret Service answers
FN ss_start
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + ss_state], 0
    jg 2f
    jl 8f
    call ss_connect
    test eax, eax
    jnz 2f
    mov dword ptr [rip + ss_state], -1
    jmp 8f
2:  mov [rip + ss_sr], rbx
    mov qword ptr [rbx + SECR_outlen], 0
    mov dword ptr [rbx + SECR_status], SECS_REFUSED
    mov eax, [rbx + SECR_op]
    cmp eax, SECO_SET
    je 3f
    # get and delete look for the key's item; keys and clear for all of the extension's
    mov edi, ST_SEARCH_GET
    cmp eax, SECO_GET
    je 21f
    mov edi, ST_SEARCH_DEL
    cmp eax, SECO_DELETE
    je 21f
    cmp eax, SECO_CLEAR
    je 22f
    mov edi, ST_SEARCH_KEYS
22: xor esi, esi                # without the account
    jmp 23f
21: mov esi, 1
23: call ss_search
    jmp 9f
3:  # set: the default collection unlocked first
    lea rdi, [rip + .Lp_default]
    mov esi, ST_UNLOCK_SET
    call ss_unlock_one
9:  xor eax, eax
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# ---------------- connecting ----------------

# ss_connect() -> eax 1 once the bus took us and the service opened a session
ss_connect:
    PROLOGUE 96
    call dbus_session_connect
    test eax, eax
    js 8f
    mov [rip + ss_fd], eax
    lea rdi, [rip + ss_in]
    call sb_clear
    call time_ms
    lea r12, [rax + SS_WAIT_MS]
    # AUTH EXTERNAL with our uid, its decimal digits in hex
    mov byte ptr [rsp], 0
    lea rdi, [rsp + 1]
    lea rsi, [rip + .Lauth]
    call cstr_copy
    mov r13, rax
    SYS SYS_getuid
    lea rdi, [rsp + 64]
    mov esi, eax
    call fmt_u64
    xor ecx, ecx
1:  movzx edx, byte ptr [rsp + 64 + rcx]
    mov byte ptr [r13], '3'
    mov [r13 + 1], dl
    add r13, 2
    inc ecx
    cmp rcx, rax
    jb 1b
    mov word ptr [r13], 0x0a0d
    add r13, 2
    lea rcx, [rsp]
    sub r13, rcx
    mov edi, [rip + ss_fd]
    lea rsi, [rsp]
    mov rdx, r13
    call write_all
    test rax, rax
    jnz 7f
    # "OK <guid>" CR LF
2:  mov rdi, r12
    call ss_poll
    test eax, eax
    jz 7f
    call ss_read
    test rax, rax
    jle 7f
    mov rcx, [rip + ss_in + SB_len]
    mov rdi, [rip + ss_in + SB_ptr]
    cmp byte ptr [rdi + rcx - 1], 10
    jne 2b
    cmp word ptr [rdi], 0x4b4f          # "OK"
    jne 7f
    lea rdi, [rip + ss_in]
    call sb_clear
    mov edi, [rip + ss_fd]
    lea rsi, [rip + .Lbegin]
    mov edx, 7
    call write_all
    test rax, rax
    jnz 7f
    # Hello, the match for prompts' Completed, OpenSession
    lea rdi, [rip + ss_body]
    call sb_clear
    lea rdi, [rip + .Lp_dbus]
    lea rsi, [rip + .Li_dbus]
    lea rdx, [rip + .Lm_hello]
    lea rcx, [rip + .Lempty]
    lea r8, [rip + .Ld_dbus]
    call ss_send
    lea rdi, [rip + ss_body]
    call sb_clear
    lea rdi, [rip + .Lmatch]
    call b_str
    lea rdi, [rip + .Lp_dbus]
    lea rsi, [rip + .Li_dbus]
    lea rdx, [rip + .Lm_addmatch]
    lea rcx, [rip + .Ls_s]
    lea r8, [rip + .Ld_dbus]
    call ss_send
    lea rdi, [rip + ss_body]
    call sb_clear
    lea rdi, [rip + .Lplain]
    call b_str
    lea rdi, [rip + .Ls_s]          # a variant: the empty string
    call b_sig
    lea rdi, [rip + .Lempty]
    call b_str
    lea rdi, [rip + .Lp_secrets]
    lea rsi, [rip + .Li_service]
    lea rdx, [rip + .Lm_open_session]
    lea rcx, [rip + .Ls_sv]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov r13d, eax                   # its serial
    # its answer: (v output, o session)
3:  call ss_next_message
    test rax, rax
    jnz 4f
    mov rdi, r12
    call ss_poll
    test eax, eax
    jz 7f
    call ss_read
    test rax, rax
    jle 7f
    jmp 3b
4:  mov rbx, rax                    # the message
    mov r15, rdx                    # its length
    cmp dword ptr [rip + m_reply], r13d
    jne 5f
    cmp dword ptr [rip + m_type], MT_REPLY
    jne 6f
    mov r14, [rip + m_body]
    call rd_variant_skip
    jc 6f
    call rd_str
    jc 6f
    lea rdi, [rip + ss_session]
    mov rsi, rax
    call ss_set_cstr
    mov rdi, r15
    call ss_consume
    mov edi, [rip + ss_fd]
    mov esi, POLLIN
    lea rdx, [rip + ss_readable]
    xor ecx, ecx
    call watch_add
    mov dword ptr [rip + ss_state], 1
    mov eax, 1
    EPILOGUE
5:  mov rdi, r15
    call ss_consume
    jmp 3b
6:  mov rdi, r15
    call ss_consume
7:  call ss_close
8:  xor eax, eax
    EPILOGUE

# ss_close(): the connection goes (the next request connects again)
ss_close:
    PROLOGUE
    mov ebx, [rip + ss_fd]
    test ebx, ebx
    js 9f
    mov dword ptr [rip + ss_fd], -1
    cmp dword ptr [rip + ss_state], 1
    jne 1f
    mov dword ptr [rip + ss_state], 0
    mov edi, ebx
    call watch_remove
1:  mov edi, ebx
    SYS SYS_close
9:  EPILOGUE

# ss_poll(deadline) -> eax 1 when the bus has sent something before the deadline
ss_poll:
    PROLOGUE 16
    mov rbx, rdi
1:  call time_ms
    mov rdx, rbx
    sub rdx, rax
    jle 8f
    mov eax, [rip + ss_fd]
    mov [rsp], eax
    mov dword ptr [rsp + 4], POLLIN
    lea rdi, [rsp]
    mov esi, 1
    SYS SYS_poll
    cmp rax, -EINTR
    je 1b
    cmp rax, 1
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ss_read() -> rax bytes added to ss_in, or <= 0 when the bus closed or failed
ss_read:
    PROLOGUE
    lea rdi, [rip + ss_in]
    mov esi, 65536
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + ss_fd]
    mov edx, 65536
    SYS SYS_read
    test rax, rax
    jle 9f
    add [rip + ss_in + SB_len], rax
9:  EPILOGUE

# ss_consume(n): the first n bytes of ss_in go
ss_consume:
    PROLOGUE
    mov rbx, rdi
    mov rdx, [rip + ss_in + SB_len]
    sub rdx, rbx
    mov [rip + ss_in + SB_len], rdx
    mov rdi, [rip + ss_in + SB_ptr]
    lea rsi, [rdi + rbx]
    call memmove
    EPILOGUE

# ss_set_cstr(sb, ptr, len): sb holds the bytes and a NUL
ss_set_cstr:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    EPILOGUE

# ---------------- writing messages ----------------

# b_pad(n): mb's buffer to a multiple of n with zeros (n a power of two)
b_pad:
    PROLOGUE
    lea rbx, [rdi - 1]
1:  mov rdi, [rip + mb]
    test [rdi + SB_len], rbx
    jz 9f
    xor esi, esi
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# b_byte(b)
b_byte:
    mov esi, edi
    mov rdi, [rip + mb]
    jmp sb_push_byte

# b_u32(v)
b_u32:
    PROLOGUE 16
    mov [rsp], edi
    mov edi, 4
    call b_pad
    mov rdi, [rip + mb]
    lea rsi, [rsp]
    mov edx, 4
    call sb_push
    EPILOGUE

# b_bytes(ptr, len): an "ay" or "s"-like run: the length, the bytes (no NUL)
b_ay:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, r12d
    call b_u32
    mov rdi, [rip + mb]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    EPILOGUE

# b_str(cstr): a string or object path
b_str:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call b_ay
    xor edi, edi
    call b_byte
    EPILOGUE

# b_sig(cstr): a signature
b_sig:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    mov edi, eax
    call b_byte
    mov rdi, [rip + mb]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    xor edi, edi
    call b_byte
    EPILOGUE

# b_array(elem align) -> rax the length field's offset, rdx the elements' start
b_array:
    PROLOGUE
    mov ebx, edi
    xor edi, edi
    call b_u32
    mov rax, [rip + mb]
    mov r12, [rax + SB_len]
    sub r12, 4
    mov edi, ebx
    call b_pad
    mov rax, [rip + mb]
    mov rdx, [rax + SB_len]
    mov rax, r12
    EPILOGUE

# b_array_end(length offset, start): the array's length written
b_array_end:
    mov rax, [rip + mb]
    mov rcx, [rax + SB_len]
    sub rcx, rsi
    add rdi, [rax + SB_ptr]
    mov [rdi], ecx
    ret

# b_attrs(with account): a{ss} {service: SECR_service, account: SECR_key}
b_attrs:
    PROLOGUE
    mov r12d, edi
    mov rbx, [rip + ss_sr]
    mov edi, 8
    call b_array
    mov r13, rax
    mov r14, rdx
    mov edi, 8
    call b_pad
    lea rdi, [rip + .La_service]
    call b_str
    mov rdi, [rbx + SECR_service]
    call b_str
    test r12d, r12d
    jz 1f
    mov edi, 8
    call b_pad
    lea rdi, [rip + .La_account]
    call b_str
    mov rdi, [rbx + SECR_key]
    call b_str
1:  mov rdi, r13
    mov rsi, r14
    call b_array_end
    EPILOGUE

# ss_send(path, interface, member, signature, destination) -> eax the call's serial: a method
# call with ss_body as its body
ss_send:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    inc dword ptr [rip + ss_serial]
    lea rax, [rip + ss_msg]
    mov [rip + mb], rax
    lea rdi, [rip + ss_msg]
    call sb_clear
    mov edi, 'l'
    call b_byte
    mov edi, MT_CALL
    call b_byte
    xor edi, edi
    call b_byte
    mov edi, 1
    call b_byte
    mov edi, [rip + ss_body + SB_len]
    call b_u32
    mov edi, [rip + ss_serial]
    call b_u32
    mov edi, 8
    call b_array
    mov r12, rax
    mov r13, rdx
    mov edi, 1                      # PATH
    mov esi, 'o'
    mov rdx, [rsp]
    call b_field
    mov edi, 2                      # INTERFACE
    mov esi, 's'
    mov rdx, [rsp + 8]
    call b_field
    mov edi, 3                      # MEMBER
    mov esi, 's'
    mov rdx, [rsp + 16]
    call b_field
    mov edi, 6                      # DESTINATION
    mov esi, 's'
    mov rdx, [rsp + 32]
    call b_field
    mov rax, [rsp + 24]
    cmp byte ptr [rax], 0
    je 1f
    mov edi, 8                      # SIGNATURE
    mov esi, 'g'
    mov rdx, [rsp + 24]
    call b_field
1:  mov rdi, r12
    mov rsi, r13
    call b_array_end
    mov edi, 8
    call b_pad
    lea rdi, [rip + ss_msg]
    mov rsi, [rip + ss_body + SB_ptr]
    mov rdx, [rip + ss_body + SB_len]
    call sb_push
    lea rax, [rip + ss_body]
    mov [rip + mb], rax
    mov edi, [rip + ss_fd]
    mov rsi, [rip + ss_msg + SB_ptr]
    mov rdx, [rip + ss_msg + SB_len]
    call write_all
    mov eax, [rip + ss_serial]
    EPILOGUE

# b_field(code, type, value cstr): a header field (yv)
b_field:
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov edi, 8
    call b_pad
    mov edi, ebx
    call b_byte
    mov edi, 1
    call b_byte
    mov edi, r12d
    call b_byte
    xor edi, edi
    call b_byte
    mov rdi, r13
    cmp r12d, 'g'
    je 1f
    call b_str
    EPILOGUE
1:  call b_sig
    EPILOGUE

# body_begin(): ss_body empty, the writers on it
body_begin:
    lea rax, [rip + ss_body]
    mov [rip + mb], rax
    lea rdi, [rip + ss_body]
    jmp sb_clear

# ---------------- the calls ----------------

# ss_search(step, with account): SearchItems(attributes) -> (ao unlocked, ao locked)
ss_search:
    PROLOGUE
    mov [rip + ss_step], edi
    mov ebx, esi
    call body_begin
    mov edi, ebx
    call b_attrs
    lea rdi, [rip + .Lp_secrets]
    lea rsi, [rip + .Li_service]
    lea rdx, [rip + .Lm_search]
    lea rcx, [rip + .Ls_attrs]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

# ss_unlock_one(object path, step): Unlock([path]) -> (ao unlocked, o prompt)
ss_unlock_one:
    PROLOGUE
    mov rbx, rdi
    mov [rip + ss_step], esi
    call body_begin
    mov edi, 4
    call b_array
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call b_str
    mov rdi, r12
    mov rsi, r13
    call b_array_end
    lea rdi, [rip + .Lp_secrets]
    lea rsi, [rip + .Li_service]
    lea rdx, [rip + .Lm_unlock]
    lea rcx, [rip + .Ls_ao]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

# ss_item_call(item path, member, interface, step): a call on an item without arguments, or
# GetSecret(session), or Get(interface, "Attributes")
ss_get_secret:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rip + ss_step], ST_GET
    call body_begin
    mov rdi, [rip + ss_session + SB_ptr]
    call b_str
    mov rdi, rbx
    lea rsi, [rip + .Li_item]
    lea rdx, [rip + .Lm_get_secret]
    lea rcx, [rip + .Ls_o]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

ss_delete_item:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rip + ss_step], ST_DELETE
    call body_begin
    mov rdi, rbx
    lea rsi, [rip + .Li_item]
    lea rdx, [rip + .Lm_delete]
    lea rcx, [rip + .Lempty]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

ss_get_attrs:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rip + ss_step], ST_ATTRS
    call body_begin
    lea rdi, [rip + .Li_item]
    call b_str
    lea rdi, [rip + .Lattributes]
    call b_str
    mov rdi, rbx
    lea rsi, [rip + .Li_props]
    lea rdx, [rip + .Lm_get]
    lea rcx, [rip + .Ls_ss]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

# ss_create(): CreateItem({Label, Attributes}, (session, [], value, "text/plain"), true) on the
# default collection -> (o item, o prompt)
ss_create:
    PROLOGUE
    mov rbx, [rip + ss_sr]
    mov dword ptr [rip + ss_step], ST_CREATE
    call body_begin
    mov edi, 8                      # a{sv}
    call b_array
    mov r12, rax
    mov r13, rdx
    mov edi, 8
    call b_pad
    lea rdi, [rip + .Lprop_label]
    call b_str
    lea rdi, [rip + .Ls_s]
    call b_sig
    lea rdi, [rip + ss_tmp]
    call sb_clear
    lea rdi, [rip + ss_tmp]
    mov rsi, [rbx + SECR_service]
    call sb_push_cstr
    lea rdi, [rip + ss_tmp]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ss_tmp]
    mov rsi, [rbx + SECR_key]
    call sb_push_cstr
    lea rdi, [rip + ss_tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + ss_tmp + SB_ptr]
    call b_str
    mov edi, 8
    call b_pad
    lea rdi, [rip + .Lprop_attrs]
    call b_str
    lea rdi, [rip + .Ls_attrs]
    call b_sig
    mov edi, 1
    call b_attrs
    mov rdi, r12
    mov rsi, r13
    call b_array_end
    # the secret: (oayays)
    mov edi, 8
    call b_pad
    mov rdi, [rip + ss_session + SB_ptr]
    call b_str
    xor edi, edi                    # no parameters ("plain")
    call b_u32
    mov rdi, [rbx + SECR_val]
    mov rsi, [rbx + SECR_len]
    call b_ay
    lea rdi, [rip + .Ltext_plain]
    call b_str
    mov edi, 1                      # replace
    call b_u32
    lea rdi, [rip + .Lp_default]
    lea rsi, [rip + .Li_collection]
    lea rdx, [rip + .Lm_create]
    lea rcx, [rip + .Ls_create]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov [rip + ss_wait], eax
    EPILOGUE

# ss_prompt_run(prompt path, after): Prompt("") on it; its Completed signal continues with after
ss_prompt_run:
    PROLOGUE
    mov rbx, rdi
    mov [rip + ss_after], esi
    mov dword ptr [rip + ss_step], ST_PROMPT
    mov rdi, rbx
    call strlen
    lea rdi, [rip + ss_prompt]
    mov rsi, rbx
    mov rdx, rax
    call ss_set_cstr
    call body_begin
    lea rdi, [rip + .Lempty]
    call b_str
    mov rdi, [rip + ss_prompt + SB_ptr]
    lea rsi, [rip + .Li_prompt]
    lea rdx, [rip + .Lm_prompt]
    lea rcx, [rip + .Ls_s]
    lea r8, [rip + .Ld_secrets]
    call ss_send
    mov dword ptr [rip + ss_wait], 0    # the reply carries nothing: the signal answers
    EPILOGUE

# ss_finish(status): the request is answered
ss_finish:
    PROLOGUE
    mov rbx, [rip + ss_sr]
    test rbx, rbx
    jz 9f
    mov [rbx + SECR_status], edi
    mov qword ptr [rip + ss_sr], 0
    mov dword ptr [rip + ss_step], 0
    mov dword ptr [rip + ss_wait], 0
    call secrets_done
9:  EPILOGUE

# ---------------- reading ----------------

# ss_readable(fd, revents, ctx): the bus spoke
ss_readable:
    PROLOGUE
    test esi, POLLIN
    jnz 1f
    test esi, POLLHUP | POLLERR
    jz 9f
    jmp 8f
1:  call ss_read
    test rax, rax
    jle 8f
2:  call ss_next_message
    test rax, rax
    jz 9f
    js 8f
    mov rbx, rax
    mov r15, rdx
    call ss_dispatch
    mov rdi, r15
    call ss_consume
    jmp 2b
8:  call ss_close               # the bus or the keyring went away: the request is refused
    mov edi, SECS_REFUSED
    call ss_finish
9:  EPILOGUE

# ss_next_message() -> rax the first whole message in ss_in (its header read into m_*), rdx its
# length; 0 while none is whole; -1 for one rhun cannot read
ss_next_message:
    PROLOGUE
    mov rcx, [rip + ss_in + SB_len]
    cmp rcx, 16
    jb 7f
    mov rbx, [rip + ss_in + SB_ptr]
    cmp byte ptr [rbx], 'l'
    jne 8f
    mov eax, [rbx + 12]             # header fields' length
    mov edx, [rbx + 4]              # the body's
    cmp eax, SS_MSG_MAX
    ja 8f
    cmp edx, SS_MSG_MAX
    ja 8f
    add eax, 16 + 7
    and eax, -8
    mov [rip + m_body], rax
    add rax, rdx
    mov r15, rax
    cmp r15, rcx
    ja 7f
    mov [rip + m_len], r15
    movzx eax, byte ptr [rbx + 1]
    mov [rip + m_type], eax
    xor eax, eax
    mov [rip + m_reply], eax
    lea rdi, [rip + m_sig]
    mov ecx, 10
1:  mov qword ptr [rdi], 0
    add rdi, 8
    dec ecx
    jnz 1b
    mov r14d, 16
    mov eax, [rbx + 12]
    lea r13, [rax + 16]
2:  cmp r14, r13
    jae 6f
    mov edi, 8
    call rd_align
    jc 8f
    lea rax, [r14 + 4]
    cmp r15, rax
    jc 8f
    movzx r12d, byte ptr [rbx + r14]
    cmp byte ptr [rbx + r14 + 1], 1
    jne 8f
    movzx ecx, byte ptr [rbx + r14 + 2]
    add r14, 4
    cmp ecx, 'u'
    je 3f
    cmp ecx, 'g'
    je 4f
    cmp ecx, 's'
    je 5f
    cmp ecx, 'o'
    je 5f
    jmp 8f
3:  call rd_u32
    jc 8f
    cmp r12d, 5                     # REPLY_SERIAL
    jne 2b
    mov [rip + m_reply], eax
    jmp 2b
4:  call rd_sig
    jc 8f
    cmp r12d, 8
    jne 2b
    mov [rip + m_sig], rax
    mov [rip + m_sig + 8], rdx
    jmp 2b
5:  call rd_str
    jc 8f
    lea rcx, [rip + m_path]
    cmp r12d, 1
    je 51f
    lea rcx, [rip + m_iface]
    cmp r12d, 2
    je 51f
    lea rcx, [rip + m_member]
    cmp r12d, 3
    je 51f
    lea rcx, [rip + m_error]
    cmp r12d, 4
    jne 2b
51: mov [rcx], rax
    mov [rcx + 8], rdx
    jmp 2b
6:  mov rax, rbx
    mov rdx, r15
    EPILOGUE
7:  xor eax, eax
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# Message readers: rbx the message, r14 the offset read next, r15 its length. Carry set when the
# message ends first.
rd_align:
    lea r14, [r14 + rdi - 1]
    neg rdi
    and r14, rdi
    cmp r15, r14
    ret
rd_u32:
    mov edi, 4
    call rd_align
    jc 9f
    lea rax, [r14 + 4]
    cmp r15, rax
    jc 9f
    mov eax, [rbx + r14]
    add r14, 4
    clc
9:  ret
# rd_str() -> rax, rdx a string, object path or byte array (without a NUL for ay)
rd_str:
    call rd_u32
    jc 9f
    mov edx, eax
    lea rax, [r14 + rdx + 1]
    cmp r15, rax
    jc 9f
    lea rax, [rbx + r14]
    lea r14, [r14 + rdx + 1]
    clc
9:  ret
rd_ay:
    call rd_u32
    jc 9f
    mov edx, eax
    lea rax, [r14 + rdx]
    cmp r15, rax
    jc 9f
    lea rax, [rbx + r14]
    add r14, rdx
    clc
9:  ret
rd_sig:
    lea rax, [r14 + 1]
    cmp r15, rax
    jc 9f
    movzx edx, byte ptr [rbx + r14]
    lea rax, [r14 + rdx + 2]
    cmp r15, rax
    jc 9f
    lea rax, [rbx + r14 + 1]
    lea r14, [r14 + rdx + 2]
    clc
9:  ret
# rd_variant_skip(): a variant holding a string (OpenSession's output) read past
rd_variant_skip:
    call rd_sig
    jc 9f
    cmp rdx, 1
    jne 8f
    cmp byte ptr [rax], 's'
    jne 8f
    jmp rd_str
8:  stc
9:  ret

# rd_paths(keep) -> eax how many paths an "ao" holds; with keep 1 they join ss_items; carry when
# the message ends first. The first path is in rax.. too: rd_first, rd_first_len
rd_paths:
    push r12
    push r13
    push rax
    mov r12d, edi
    call rd_u32
    jc 8f
    lea r13, [r14 + rax]            # the array's end
    cmp r15, r13
    jc 8f
    xor ecx, ecx
    mov [rip + rd_count], ecx
1:  cmp r14, r13
    jae 7f
    call rd_str
    jc 8f
    inc dword ptr [rip + rd_count]
    test r12d, r12d
    jz 1b
    lea rdi, [rip + ss_items]
    mov rsi, rax
    call sb_push
    lea rdi, [rip + ss_items]
    xor esi, esi
    call sb_push_byte
    jmp 1b
7:  pop rax
    mov eax, [rip + rd_count]
    pop r13
    pop r12
    clc
    ret
8:  pop rax
    pop r13
    pop r12
    stc
    ret

# ss_dispatch(): rbx a whole message: the answer the step waits for, or a prompt's Completed
ss_dispatch:
    PROLOGUE 32
    cmp qword ptr [rip + ss_sr], 0
    je 9f
    mov eax, [rip + m_type]
    cmp eax, MT_SIGNAL
    je .Ld_signal
    cmp eax, MT_REPLY
    je 1f
    cmp eax, MT_ERROR
    jne 9f
1:  mov ecx, [rip + ss_wait]
    test ecx, ecx
    jz 9f
    cmp [rip + m_reply], ecx
    jne 9f
    cmp eax, MT_ERROR
    jne 2f
    mov edi, SECS_REFUSED             # locked, no such object, denied
    call ss_finish
    jmp 9f
2:  mov r14, [rip + m_body]
    mov eax, [rip + ss_step]
    cmp eax, ST_SEARCH_GET
    je .Ld_search_get
    cmp eax, ST_UNLOCK_GET
    je .Ld_unlock
    cmp eax, ST_UNLOCK_SET
    je .Ld_unlock
    cmp eax, ST_UNLOCK_DEL
    je .Ld_unlock
    cmp eax, ST_GET
    je .Ld_get
    cmp eax, ST_COUNT
    je .Ld_count
    cmp eax, ST_EXISTS
    je .Ld_exists
    cmp eax, ST_CREATE
    je .Ld_create
    cmp eax, ST_SEARCH_DEL
    je .Ld_search_del
    cmp eax, ST_SEARCH_KEYS
    je .Ld_search_del
    cmp eax, ST_DELETE
    je .Ld_next_delete
    cmp eax, ST_ATTRS
    je .Ld_attrs
    jmp 9f
.Ld_bad:
    mov edi, SECS_REFUSED
    call ss_finish
9:  EPILOGUE

.Ld_signal:
    cmp dword ptr [rip + ss_step], ST_PROMPT
    jne 9b
    mov rdi, [rip + m_member]
    mov rsi, [rip + m_member + 8]
    lea rdx, [rip + .Lm_completed]
    call str_eq_cstr
    test eax, eax
    jz 9b
    mov rdi, [rip + m_path]
    mov rsi, [rip + m_path + 8]
    mov rdx, [rip + ss_prompt + SB_ptr]
    call str_eq_cstr
    test eax, eax
    jz 9b
    mov r14, [rip + m_body]
    call rd_u32                     # dismissed
    jc .Ld_bad
    test eax, eax
    jnz .Ld_bad
    call ss_continue
    jmp 9b

# get: the key's item, unlocked first when it is locked
.Ld_search_get:
    lea rdi, [rip + ss_items]
    call sb_clear
    mov edi, 1
    call rd_paths                   # unlocked
    jc .Ld_bad
    test eax, eax
    jnz 1f
    mov edi, 1
    call rd_paths                   # locked
    jc .Ld_bad
    test eax, eax
    jnz 2f
    mov edi, SECS_NONE
    call ss_finish
    jmp 9b
1:  mov rdi, [rip + ss_items + SB_ptr]
    call ss_get_secret
    jmp 9b
2:  mov rdi, [rip + ss_items + SB_ptr]
    mov esi, ST_UNLOCK_GET
    call ss_unlock_one
    jmp 9b

# an Unlock answer: (ao unlocked, o prompt)
.Ld_unlock:
    xor edi, edi
    call rd_paths
    jc .Ld_bad
    call rd_str
    jc .Ld_bad
    cmp rdx, 1
    jne 1f
    cmp byte ptr [rax], '/'
    jne 1f
    mov eax, [rip + ss_step]
    mov [rip + ss_after], eax
    call ss_continue
    jmp 9b
1:  mov byte ptr [rax + rdx], 0     # the path's NUL is the message's own byte
    mov rdi, rax
    mov esi, [rip + ss_step]
    call ss_prompt_run
    jmp 9b

# GetSecret: (oayays) -> the value
.Ld_get:
    mov edi, 8
    call rd_align
    jc .Ld_bad
    call rd_str                     # the session
    jc .Ld_bad
    call rd_ay                      # parameters
    jc .Ld_bad
    call rd_ay                      # the value
    jc .Ld_bad
    cmp rdx, SECRET_VALUE_MAX
    ja .Ld_bad
    mov r12, [rip + ss_sr]
    mov [r12 + SECR_outlen], rdx
    lea rdi, [r12 + SECR_buf]
    mov rsi, rax
    call memcpy
    mov edi, SECS_OK
    call ss_finish
    jmp 9b

# set: how many keys it has; at SECRET_KEYS_MAX only an existing key may change
.Ld_count:
    xor edi, edi
    call rd_paths
    jc .Ld_bad
    mov r12d, eax
    xor edi, edi
    call rd_paths
    jc .Ld_bad
    add eax, r12d
    cmp eax, SECRET_KEYS_MAX
    jb 1f
    mov edi, ST_EXISTS
    mov esi, 1
    call ss_search
    jmp 9b
1:  call ss_create
    jmp 9b
.Ld_exists:
    xor edi, edi
    call rd_paths
    jc .Ld_bad
    mov r12d, eax
    xor edi, edi
    call rd_paths
    jc .Ld_bad
    add eax, r12d
    jnz 1f
    mov edi, SECS_TOOBIG
    call ss_finish
    jmp 9b
1:  call ss_create
    jmp 9b

# CreateItem: (o item, o prompt)
.Ld_create:
    call rd_str
    jc .Ld_bad
    call rd_str
    jc .Ld_bad
    cmp rdx, 1
    jne 1f
    cmp byte ptr [rax], '/'
    jne 1f
    mov edi, SECS_OK
    call ss_finish
    jmp 9b
1:  mov byte ptr [rax + rdx], 0
    mov rdi, rax
    mov esi, ST_CREATE_PROMPT
    call ss_prompt_run
    jmp 9b

# delete, clear, keys: every item found; locked ones are unlocked first (delete, clear)
.Ld_search_del:
    lea rdi, [rip + ss_items]
    call sb_clear
    mov qword ptr [rip + ss_next_item], 0
    mov edi, 1
    call rd_paths
    jc .Ld_bad
    mov r12, [rip + ss_items + SB_len]      # where the locked ones start
    mov edi, 1
    call rd_paths
    jc .Ld_bad
    cmp dword ptr [rip + ss_step], ST_SEARCH_KEYS
    je .Ld_next_attrs
    cmp r12, [rip + ss_items + SB_len]
    je .Ld_next_delete
    # the first locked one unlocked (the collection with it)
    mov rdi, [rip + ss_items + SB_ptr]
    add rdi, r12
    mov esi, ST_UNLOCK_DEL
    call ss_unlock_one
    jmp 9b
.Ld_next_delete:
    call next_item
    test rax, rax
    jz 1f
    mov rdi, rax
    call ss_delete_item
    jmp 9b
1:  mov edi, SECS_OK
    call ss_finish
    jmp 9b
.Ld_attrs:
    # v(a{ss}): the account's value
    call rd_sig
    jc .Ld_bad
    call rd_u32
    jc .Ld_bad
    mov r13, rax
    mov edi, 8
    call rd_align
    jc .Ld_bad
    add r13, r14                    # the array's end
1:  cmp r14, r13
    jae .Ld_next_attrs
    mov edi, 8
    call rd_align
    jc .Ld_bad
    call rd_str
    jc .Ld_bad
    mov [rsp], rax                  # the attribute's name
    mov [rsp + 8], rdx
    call rd_str
    jc .Ld_bad
    mov [rsp + 16], rax             # its value
    mov [rsp + 24], rdx
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .La_account]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    mov r12, [rip + ss_sr]
    mov rax, [r12 + SECR_outlen]
    lea rcx, [rax + rdx + 1]
    cmp rcx, SECRET_BUF
    ja .Ld_next_attrs
    lea rdi, [r12 + SECR_buf + rax]
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    mov rax, [r12 + SECR_outlen]
    add rax, rdx
    mov byte ptr [r12 + SECR_buf + rax], 10
    inc rax
    mov [r12 + SECR_outlen], rax
.Ld_next_attrs:
    call next_item
    test rax, rax
    jz 1f
    mov rdi, rax
    call ss_get_attrs
    jmp 9b
1:  mov edi, SECS_OK
    call ss_finish
    jmp 9b

# next_item() -> rax the next path in ss_items, or 0
next_item:
    mov rax, [rip + ss_next_item]
    cmp rax, [rip + ss_items + SB_len]
    jae 8f
    mov rcx, [rip + ss_items + SB_ptr]
    add rax, rcx
    push rax
    mov rdi, rax
    call strlen
    pop rcx
    lea rdx, [rcx + rax + 1]
    sub rdx, [rip + ss_items + SB_ptr]
    mov [rip + ss_next_item], rdx
    mov rax, rcx
    ret
8:  xor eax, eax
    ret

# ss_continue(): an unlock (or its prompt) is done: the step after it
ss_continue:
    PROLOGUE
    mov eax, [rip + ss_after]
    cmp eax, ST_UNLOCK_GET
    je 1f
    cmp eax, ST_UNLOCK_SET
    je 2f
    cmp eax, ST_UNLOCK_DEL
    je 3f
    mov edi, SECS_OK                  # CreateItem's prompt: stored
    call ss_finish
    EPILOGUE
1:  mov rdi, [rip + ss_items + SB_ptr]
    call ss_get_secret
    EPILOGUE
2:  mov edi, ST_COUNT
    xor esi, esi
    call ss_search
    EPILOGUE
3:  call next_item
    test rax, rax
    jz 4f
    mov rdi, rax
    call ss_delete_item
    EPILOGUE
4:  mov edi, SECS_OK
    call ss_finish
    EPILOGUE

.bss
rd_count: .long 0

.section .rodata
.Lempty: .byte 0
.Lauth: .asciz "AUTH EXTERNAL "
.Lbegin: .ascii "BEGIN\r\n"
.Lp_dbus: .asciz "/org/freedesktop/DBus"
.Li_dbus: .asciz "org.freedesktop.DBus"
.Ld_dbus: .asciz "org.freedesktop.DBus"
.Lm_hello: .asciz "Hello"
.Lm_addmatch: .asciz "AddMatch"
.Lmatch: .asciz "type='signal',interface='org.freedesktop.Secret.Prompt',member='Completed'"
.Lp_secrets: .asciz "/org/freedesktop/secrets"
.Lp_default: .asciz "/org/freedesktop/secrets/aliases/default"
.Ld_secrets: .asciz "org.freedesktop.secrets"
.Li_service: .asciz "org.freedesktop.Secret.Service"
.Li_collection: .asciz "org.freedesktop.Secret.Collection"
.Li_item: .asciz "org.freedesktop.Secret.Item"
.Li_prompt: .asciz "org.freedesktop.Secret.Prompt"
.Li_props: .asciz "org.freedesktop.DBus.Properties"
.Lm_open_session: .asciz "OpenSession"
.Lm_search: .asciz "SearchItems"
.Lm_unlock: .asciz "Unlock"
.Lm_get_secret: .asciz "GetSecret"
.Lm_create: .asciz "CreateItem"
.Lm_delete: .asciz "Delete"
.Lm_prompt: .asciz "Prompt"
.Lm_completed: .asciz "Completed"
.Lm_get: .asciz "Get"
.Lattributes: .asciz "Attributes"
.Lprop_label: .asciz "org.freedesktop.Secret.Item.Label"
.Lprop_attrs: .asciz "org.freedesktop.Secret.Item.Attributes"
.Lplain: .asciz "plain"
.Ltext_plain: .asciz "text/plain"
.La_service: .asciz "service"
.La_account: .asciz "account"
.Ls_s: .asciz "s"
.Ls_o: .asciz "o"
.Ls_ss: .asciz "ss"
.Ls_sv: .asciz "sv"
.Ls_ao: .asciz "ao"
.Ls_attrs: .asciz "a{ss}"
.Ls_create: .asciz "a{sv}(oayays)b"

.endif
.endif
