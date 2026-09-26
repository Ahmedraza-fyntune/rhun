# X11 client over a unix socket (fallback when there is no Wayland display)
.include "rhun.inc"

.equ XOUT, 65536
.equ XIN, 262144
.equ EVMASK, 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040 | 0x8000 | 0x20000 | 0x200000
# KeyPress KeyRelease ButtonPress ButtonRelease EnterWindow LeaveWindow PointerMotion Exposure StructureNotify FocusChange

.bss
.p2align 4
xout: .zero XOUT
xin: .zero XIN
xout_len: .long 0
xin_len: .long 0
seq: .long 0
id_base: .long 0
id_mask: .long 0
id_next: .long 0
root: .long 0
root_visual: .long 0
root_depth: .long 0
win: .long 0
gc: .long 0
max_req: .long 0                # in 4-byte units
big_req: .long 0
win_w: .long 0
win_h: .long 0
.p2align 3
fbuf: .quad 0
fb_w: .long 0
fb_h: .long 0
min_kc: .long 0
max_kc: .long 0
kpk: .long 0                    # keysyms per keycode
.p2align 3
kmap: .quad 0                   # keysym table
xmods: .long 0
cursors: .zero 4 * 8
cursor_font: .long 0
# atoms
a_wm_protocols: .long 0
a_wm_delete: .long 0
a_net_wm_name: .long 0
a_utf8: .long 0
a_clipboard: .long 0
a_targets: .long 0
a_sel_prop: .long 0
a_net_wm_state: .long 0
a_max_h: .long 0
a_max_v: .long 0
a_wm_change_state: .long 0
# pending synchronous reply
got_reply: .long 0
.p2align 3
reply_buf: .zero 32
reply_extra: .quad 0            # pointer into xin (valid until the next read)
reply_extra_len: .quad 0
.p2align 3
xclip: .zero SB_SIZE
own_clip: .long 0
maximized: .long 0
addr: .zero 110
tmp: .zero SB_SIZE
iov2: .zero 32
mh: .zero 56

.text

# ---- output ----

x_new_id:
    mov eax, [rip + id_next]
    inc dword ptr [rip + id_next]
    and eax, [rip + id_mask]
    or eax, [rip + id_base]
    ret

# x_req(ptr, len): append a request, bump the sequence number
x_req:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rip + xout_len]
    add eax, r12d
    cmp eax, XOUT
    jb 1f
    call x_flush
1:  lea rdi, [rip + xout]
    mov eax, [rip + xout_len]
    add rdi, rax
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    add [rip + xout_len], r12d
    inc dword ptr [rip + seq]
    add rsp, 8
    pop r12
    pop rbx
    ret

FN x_flush
    mov eax, [rip + xout_len]
    test eax, eax
    jz 1f
    mov edi, [rip + xfd]
    lea rsi, [rip + xout]
    mov edx, eax
    call write_all
    mov dword ptr [rip + xout_len], 0
1:  ret

# ---- input ----

# x_read() -> bytes read
x_read:
    mov edi, [rip + xfd]
    lea rsi, [rip + xin]
    mov eax, [rip + xin_len]
    add rsi, rax
    mov edx, XIN
    sub edx, eax
    SYS SYS_read
    test rax, rax
    jle 1f
    add [rip + xin_len], eax
1:  ret

# x_process(): handle complete messages in xin
x_process:
    PROLOGUE
    xor ebx, ebx
1:  mov eax, [rip + xin_len]
    sub eax, ebx
    cmp eax, 32
    jb 8f
    lea r12, [rip + xin]
    add r12, rbx
    mov r13d, 32
    movzx ecx, byte ptr [r12]
    and ecx, 0x7f
    cmp ecx, 1
    je 2f
    cmp ecx, 35
    jne 3f
2:  mov edx, [r12 + 4]
    shl edx, 2
    add r13d, edx
3:  cmp eax, r13d
    jb 8f
    mov rdi, r12
    mov esi, r13d
    call x_message
    add ebx, r13d
    jmp 1b
8:  # keep the tail
    mov ecx, [rip + xin_len]
    sub ecx, ebx
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + rbx]
    rep movsb
    EPILOGUE

# x_message(ptr, len)
x_message:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    movzx eax, byte ptr [rbx]
    and eax, 0x7f
    test eax, eax
    jz .Lxm_error
    cmp eax, 1
    je .Lxm_reply
    cmp eax, 2
    je .Lxm_key
    cmp eax, 4
    je .Lxm_bpress
    cmp eax, 5
    je .Lxm_brelease
    cmp eax, 6
    je .Lxm_motion
    cmp eax, 8
    je .Lxm_leave
    cmp eax, 9
    je .Lxm_focusin
    cmp eax, 10
    je .Lxm_focusout
    cmp eax, 12
    je .Lxm_expose
    cmp eax, 22
    je .Lxm_configure
    cmp eax, 29
    je .Lxm_selclear
    cmp eax, 30
    je .Lxm_selreq
    cmp eax, 31
    je .Lxm_selnotify
    cmp eax, 33
    je .Lxm_client
    cmp eax, 34
    je .Lxm_mapping
    jmp .Lxm_ret
.Lxm_error:
    # ignore: errors are non-fatal for us (e.g. a stale property)
    jmp .Lxm_ret
.Lxm_reply:
    movzx eax, word ptr [rbx + 2]
    cmp eax, [rip + want_seq]
    jne .Lxm_ret
    lea rdi, [rip + reply_buf]
    mov rsi, rbx
    mov ecx, 32
    rep movsb
    lea rax, [rbx + 32]
    mov [rip + reply_extra], rax
    mov eax, r12d
    sub eax, 32
    mov [rip + reply_extra_len], rax
    mov dword ptr [rip + got_reply], 1
    # a paste reply is handled right here (the buffer moves after this)
    cmp dword ptr [rip + paste_wait], 0
    je .Lxm_ret
    mov dword ptr [rip + paste_wait], 0
    mov dword ptr [rip + want_seq], -1
    mov rdi, [rip + reply_extra]
    mov esi, [rbx + 16]         # value length in format units (format 8)
    call app_on_paste
    jmp .Lxm_ret
.Lxm_key:
    movzx eax, word ptr [rbx + 28]
    mov [rip + xmods], eax
    movzx edi, byte ptr [rbx + 1]
    call x_key
    jmp .Lxm_ret
.Lxm_bpress:
    movzx eax, word ptr [rbx + 28]
    mov [rip + xmods], eax
    call x_motion_from
    movzx edi, byte ptr [rbx + 1]
    cmp edi, 4
    jb 1f
    cmp edi, 7
    ja .Lxm_ret
    # wheel buttons
    mov esi, 60
    xor edi, edi
    movzx eax, byte ptr [rbx + 1]
    cmp eax, 4
    jne 11f
    neg esi
    jmp 13f
11: cmp eax, 5
    je 13f
    mov edi, esi
    xor esi, esi
    cmp eax, 6
    jne 13f
    neg edi
13: call app_on_scroll
    jmp .Lxm_ret
1:  call x_btn
    mov esi, 1
    mov edx, [rip + xmods]
    call x_mods
    call app_on_button
    jmp .Lxm_ret
.Lxm_brelease:
    call x_motion_from
    movzx edi, byte ptr [rbx + 1]
    cmp edi, 4
    jae .Lxm_ret
    call x_btn
    xor esi, esi
    mov edx, [rip + xmods]
    call x_mods
    call app_on_button
    jmp .Lxm_ret
.Lxm_motion:
    call x_motion_from
    jmp .Lxm_ret
.Lxm_leave:
    call app_on_pointer_leave
    jmp .Lxm_ret
.Lxm_focusin:
    mov edi, 1
    call app_on_focus
    jmp .Lxm_ret
.Lxm_focusout:
    xor edi, edi
    call app_on_focus
    jmp .Lxm_ret
.Lxm_expose:
    mov dword ptr [rip + g_dirty], 1
    jmp .Lxm_ret
.Lxm_configure:
    movzx eax, word ptr [rbx + 20]
    movzx ecx, word ptr [rbx + 22]
    cmp eax, [rip + win_w]
    jne 2f
    cmp ecx, [rip + win_h]
    je .Lxm_ret
2:  mov [rip + win_w], eax
    mov [rip + win_h], ecx
    call x_resize_fb
    jmp .Lxm_ret
.Lxm_selclear:
    mov dword ptr [rip + own_clip], 0
    jmp .Lxm_ret
.Lxm_selreq:
    mov rdi, rbx
    call x_serve_selection
    jmp .Lxm_ret
.Lxm_selnotify:
    # property with the pasted text is ready: fetch it
    mov eax, [rbx + 20]
    test eax, eax
    jz .Lxm_ret
    call x_get_paste
    jmp .Lxm_ret
.Lxm_client:
    mov eax, [rbx + 8]
    cmp eax, [rip + a_wm_protocols]
    jne .Lxm_ret
    mov eax, [rbx + 12]
    cmp eax, [rip + a_wm_delete]
    jne .Lxm_ret
    call app_on_close
    jmp .Lxm_ret
.Lxm_mapping:
    call x_load_keymap_async
.Lxm_ret:
    EPILOGUE

x_motion_from:
    movsx edi, word ptr [rbx + 24]
    movsx esi, word ptr [rbx + 26]
    push rbx
    call app_on_motion
    pop rbx
    ret

# X buttons 1 left 2 middle 3 right -> ours
x_btn:
    cmp edi, 2
    jne 1f
    mov edi, BTN_MIDDLE
    ret
1:  cmp edi, 3
    jne 2f
    mov edi, BTN_RIGHT
2:  ret

# x_mods: X state -> MOD_* in edx
x_mods:
    mov eax, edx
    xor edx, edx
    test eax, 1
    jz 1f
    or edx, MOD_SHIFT
1:  test eax, 4
    jz 2f
    or edx, MOD_CTRL
2:  test eax, 8
    jz 3f
    or edx, MOD_ALT
3:  test eax, 64
    jz 4f
    or edx, MOD_SUPER
4:  ret

# x_key(keycode)
x_key:
    PROLOGUE
    mov rax, [rip + kmap]
    test rax, rax
    jz 9f
    cmp edi, [rip + min_kc]
    jb 9f
    cmp edi, [rip + max_kc]
    ja 9f
    mov ebx, edi
    sub ebx, [rip + min_kc]
    imul ebx, [rip + kpk]
    # column: group (state bits 13-14) * 2 + shift
    mov ecx, [rip + xmods]
    shr ecx, 13
    and ecx, 3
    cmp dword ptr [rip + kpk], 4
    jb 1f
    test ecx, ecx
    jz 1f
    # shortcuts use the first layout
    test dword ptr [rip + xmods], 4 | 8 | 64
    jnz 1f
    add ebx, 2
1:  mov r12d, ebx               # base column
    mov eax, [rip + xmods]
    xor edx, edx
    test eax, 1
    setnz dl
    # caps lock on letters flips shift
    mov rcx, [rip + kmap]
    mov edi, [rcx + r12*4]
    test eax, 2
    jz 2f
    push rdx
    push rdx
    call keysym_is_lower_x
    pop rdx
    pop rdx
    xor edx, eax
2:  lea r13d, [r12 + rdx]
    mov rcx, [rip + kmap]
    mov eax, [rcx + r13*4]
    test eax, eax
    jnz 3f
    mov eax, [rcx + r12*4]
3:  mov r14d, eax
    mov edi, eax
    call keysym_to_unicode
    mov r15d, eax
    mov edx, [rip + xmods]
    call x_mods
    mov edi, r14d
    mov esi, r15d
    call app_on_key
9:  EPILOGUE

# x_key_test(keycode, state): feed a key press as if it came from the server (control socket)
FN x_key_test
    mov [rip + xmods], esi
    jmp x_key

keysym_is_lower_x:
    lea eax, [rdi - 'a']
    cmp eax, 25
    jbe 1f
    lea eax, [rdi - 0x6c0]
    cmp eax, 0x1f
    jbe 1f
    lea eax, [rdi - 0xe0]
    cmp eax, 0x1e
    jbe 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

x_on_readable:
    push rbx
    test esi, POLLIN
    jz 2f
    call x_read
    test rax, rax
    jz 3f
    js 1f
    call x_process
1:  pop rbx
    ret
2:  test esi, POLLHUP | POLLERR
    jz 1b
3:  lea rdi, [rip + .Lclosed]
    call die

# x_wait_reply(): flush, then read until the reply for want_seq arrives
x_wait_reply:
    push rbx
    mov dword ptr [rip + got_reply], 0
    call x_flush
1:  cmp dword ptr [rip + got_reply], 0
    jne 2f
    call x_read
    test rax, rax
    jle 3f
    call x_process_until_reply
    jmp 1b
2:  mov dword ptr [rip + want_seq], -1
    pop rbx
    ret
3:  lea rdi, [rip + .Lclosed]
    call die

# like x_process but stops right after the wanted reply so reply_extra stays valid
x_process_until_reply:
    PROLOGUE
    xor ebx, ebx
1:  cmp dword ptr [rip + got_reply], 0
    jne 8f
    mov eax, [rip + xin_len]
    sub eax, ebx
    cmp eax, 32
    jb 8f
    lea r12, [rip + xin]
    add r12, rbx
    mov r13d, 32
    movzx ecx, byte ptr [r12]
    and ecx, 0x7f
    cmp ecx, 1
    je 2f
    cmp ecx, 35
    jne 3f
2:  mov edx, [r12 + 4]
    shl edx, 2
    add r13d, edx
3:  cmp eax, r13d
    jb 8f
    mov rdi, r12
    mov esi, r13d
    call x_message
    add ebx, r13d
    jmp 1b
8:  # copy the reply payload out before compacting
    cmp dword ptr [rip + got_reply], 0
    je 9f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rip + reply_extra]
    mov rdx, [rip + reply_extra_len]
    call sb_push
    mov rax, [rip + tmp + SB_ptr]
    mov [rip + reply_extra], rax
9:  mov ecx, [rip + xin_len]
    sub ecx, ebx
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + rbx]
    rep movsb
    EPILOGUE

# ---- requests ----

# x_intern(name cstr) -> atom
x_intern:
    PROLOGUE 64
    mov rbx, rdi
    call strlen
    mov r12, rax
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rsp], 16      # InternAtom
    mov byte ptr [rsp + 1], 0   # only_if_exists = false
    lea eax, [r12 + 3]
    and eax, -4
    add eax, 8
    mov r13d, eax
    shr eax, 2
    mov [rsp + 2], ax
    mov [rsp + 4], r12w
    lea rdi, [rsp + 8]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    lea rdi, [rsp]
    mov esi, r13d
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    mov eax, [rip + reply_buf + 8]
    EPILOGUE

# x_change_prop(window, prop, type, format(8/32), data, nunits)
x_change_prop:
    PROLOGUE 32
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov rbx, r8
    mov [rsp + 16], r9
    # bytes of data
    mov eax, r9d
    cmp r15d, 32
    jne 1f
    shl eax, 2
1:  mov [rsp + 24], eax
    add eax, 3
    and eax, -4
    add eax, 24
    mov [rsp + 28], eax         # request bytes
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, [rsp + 28]
    call sb_reserve
    mov rdi, rax
    mov byte ptr [rdi], 18      # ChangeProperty
    mov byte ptr [rdi + 1], 0   # Replace
    mov eax, [rsp + 28]
    shr eax, 2
    mov [rdi + 2], ax
    mov [rdi + 4], r12d
    mov [rdi + 8], r13d
    mov [rdi + 12], r14d
    mov [rdi + 16], r15b
    mov byte ptr [rdi + 17], 0
    mov word ptr [rdi + 18], 0
    mov rax, [rsp + 16]
    mov [rdi + 20], eax
    lea rdi, [rdi + 24]
    mov rsi, rbx
    mov ecx, [rsp + 24]
    rep movsb
    mov ecx, [rsp + 28]
    sub ecx, [rsp + 24]
    sub ecx, 24
    xor eax, eax
    rep stosb
    mov rdi, [rip + tmp + SB_ptr]
    mov esi, [rsp + 28]
    call x_req
    EPILOGUE

# ---- connection ----

# read_auth(display number cstr) -> tmp holds cookie (16 bytes) ; eax = 1 if found
read_auth:
    PROLOGUE 16
    mov [rsp], rdi
    lea rdi, [rip + .Lxauth_env]
    call getenv
    test rax, rax
    jnz 1f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz .Lra_no
    mov rdi, rax
    lea rsi, [rip + .Lxauth_file]
    call path_join_tmp
1:  mov rdi, rax
    call file_read_all
    test rax, rax
    jz .Lra_no
    mov rbx, rax
    lea r15, [rax + rdx]        # end
    mov r12, rax
.Lra_entry:
    lea rax, [r12 + 2]
    cmp rax, r15
    jae .Lra_free
    add r12, 2                  # family
    # address
    movzx eax, word ptr [r12]
    rol ax, 8
    lea r12, [r12 + rax + 2]
    # number
    movzx r13d, word ptr [r12]
    rol r13w, 8
    lea r14, [r12 + 2]
    lea r12, [r14 + r13]
    # name
    movzx eax, word ptr [r12]
    rol ax, 8
    mov [rsp + 8], rax
    lea rcx, [r12 + 2]
    lea r12, [rcx + rax]
    # data
    movzx edx, word ptr [r12]
    rol dx, 8
    lea r8, [r12 + 2]
    lea r12, [r8 + rdx]
    cmp r12, r15
    ja .Lra_free
    cmp edx, 16
    jne .Lra_entry
    push r8
    push rcx
    mov rdi, rcx
    mov rsi, [rsp + 8 + 16]
    lea rdx, [rip + .Lmit]
    call str_eq_cstr
    pop rcx
    pop r8
    test eax, eax
    jz .Lra_entry
    # display number matches (empty number matches any)
    test r13, r13
    jz 2f
    push r8
    push r8
    mov rdi, r14
    mov rsi, r13
    mov rdx, [rsp + 16]
    call str_eq_cstr
    pop r8
    pop r8
    test eax, eax
    jz .Lra_entry
2:  lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, r8
    mov edx, 16
    call sb_push
    mov rdi, rbx
    call mem_free
    mov eax, 1
    EPILOGUE
.Lra_free:
    mov rdi, rbx
    call mem_free
.Lra_no:
    xor eax, eax
    EPILOGUE

# x_connect() -> 1 on success
FN x_connect
    PROLOGUE 64
    lea rdi, [rip + .Ldisplay_env]
    call getenv
    test rax, rax
    jz .Lxc_fail
    # ":N[.S]" or "unix:N" only
    mov rbx, rax
1:  mov al, [rbx]
    test al, al
    jz .Lxc_fail
    inc rbx
    cmp al, ':'
    jne 1b
    # display number into [rsp+32]
    lea rdi, [rsp + 32]
    xor ecx, ecx
2:  mov al, [rbx + rcx]
    cmp al, '0'
    jb 3f
    cmp al, '9'
    ja 3f
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 8
    jb 2b
3:  mov byte ptr [rdi + rcx], 0
    test ecx, ecx
    jz .Lxc_fail
    # socket path
    lea rdi, [rip + addr]
    mov word ptr [rdi], AF_UNIX
    add rdi, 2
    lea rsi, [rip + .Lsock_prefix]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rsp + 32]
    call cstr_copy
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lxc_fail
    mov [rip + xfd], eax
    mov edi, eax
    lea rsi, [rip + addr]
    mov edx, 110
    SYS SYS_connect
    test rax, rax
    js .Lxc_close
    # setup request
    lea rdi, [rsp + 32]
    call read_auth
    mov r12d, eax               # have cookie
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp], 'l'
    mov word ptr [rsp + 2], 11
    mov word ptr [rsp + 4], 0
    test r12d, r12d
    jz 4f
    mov word ptr [rsp + 6], 18
    mov word ptr [rsp + 8], 16
4:  lea rdi, [rsp]
    mov esi, 12
    call x_req_raw
    test r12d, r12d
    jz 5f
    lea rdi, [rip + .Lmit]
    mov esi, 20                 # 18 + 2 pad
    call x_req_raw
    mov rdi, [rip + tmp + SB_ptr]
    mov esi, 16
    call x_req_raw
5:  call x_flush
    # reply: 8-byte header, then 4*len bytes
6:  cmp dword ptr [rip + xin_len], 8
    jae 7f
    call x_read
    test rax, rax
    jle .Lxc_close
    jmp 6b
7:  cmp byte ptr [rip + xin], 1
    jne .Lxc_close
    movzx eax, word ptr [rip + xin + 6]
    lea r13d, [rax*4 + 8]
8:  cmp [rip + xin_len], r13d
    jae 9f
    call x_read
    test rax, rax
    jle .Lxc_close
    jmp 8b
9:  lea r14, [rip + xin]
    mov eax, [r14 + 12]
    mov [rip + id_base], eax
    mov eax, [r14 + 16]
    mov [rip + id_mask], eax
    movzx eax, word ptr [r14 + 26]
    mov [rip + max_req], eax
    movzx ecx, word ptr [r14 + 24]  # vendor length
    movzx edx, byte ptr [r14 + 29]  # number of formats
    add ecx, 3
    and ecx, -4
    lea r15, [r14 + 40]
    add r15, rcx
    lea r15, [r15 + rdx*8]          # first screen
    mov eax, [r15]
    mov [rip + root], eax
    mov eax, [r15 + 32]
    mov [rip + root_visual], eax
    movzx eax, byte ptr [r15 + 38]
    mov [rip + root_depth], eax
    # drop the setup reply
    mov ecx, [rip + xin_len]
    sub ecx, r13d
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + r13]
    rep movsb
    mov dword ptr [rip + seq], 0
    mov eax, 1
    EPILOGUE
.Lxc_close:
    mov edi, [rip + xfd]
    SYS SYS_close
    mov dword ptr [rip + xfd], -1
.Lxc_fail:
    xor eax, eax
    EPILOGUE

# append bytes without counting a request
x_req_raw:
    push rbx
    mov rbx, rdi
    mov ecx, esi
    lea rdi, [rip + xout]
    mov eax, [rip + xout_len]
    add rdi, rax
    add [rip + xout_len], ecx
    mov rsi, rbx
    rep movsb
    pop rbx
    ret

# big requests: lift the 256 KiB request limit if the server allows
x_big_requests:
    PROLOGUE 32
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp], 98      # QueryExtension
    mov word ptr [rsp + 2], 5   # 8 + 12 bytes name
    mov word ptr [rsp + 4], 12
    lea rdi, [rsp + 8]
    lea rsi, [rip + .Lbigreq]
    mov ecx, 12
    rep movsb
    lea rdi, [rsp]
    mov esi, 20
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf + 8], 0
    je 9f
    movzx eax, byte ptr [rip + reply_buf + 9]
    mov byte ptr [rsp], al
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 1
    lea rdi, [rsp]
    mov esi, 4
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    mov eax, [rip + reply_buf + 8]
    mov [rip + max_req], eax
    mov dword ptr [rip + big_req], 1
9:  EPILOGUE

# keyboard mapping (synchronous)
x_load_keymap:
    PROLOGUE 16
    # min/max keycode from the setup are not kept; use the usual 8..255
    mov dword ptr [rip + min_kc], 8
    mov dword ptr [rip + max_kc], 255
    mov byte ptr [rsp], 101     # GetKeyboardMapping
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 2
    mov byte ptr [rsp + 4], 8
    mov byte ptr [rsp + 5], 248
    mov word ptr [rsp + 6], 0
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    movzx eax, byte ptr [rip + reply_buf + 1]
    mov [rip + kpk], eax
    mov rdi, [rip + kmap]
    call mem_free
    mov rdi, [rip + reply_extra_len]
    call mem_alloc
    mov [rip + kmap], rax
    mov rdi, rax
    mov rsi, [rip + reply_extra]
    mov rcx, [rip + reply_extra_len]
    rep movsb
    EPILOGUE

x_load_keymap_async:
    # MappingNotify arrives inside event processing: reload on the next loop turn
    mov dword ptr [rip + keymap_stale], 1
    ret

# cursors from the standard cursor font
x_cursor_init:
    PROLOGUE 32
    call x_new_id
    mov [rip + cursor_font], eax
    mov byte ptr [rsp], 45      # OpenFont
    mov word ptr [rsp + 2], 5
    mov [rsp + 4], eax
    mov word ptr [rsp + 8], 6
    mov word ptr [rsp + 10], 0
    mov dword ptr [rsp + 12], 0x73727563    # "curs"
    mov dword ptr [rsp + 16], 0x0000726f    # "or"
    lea rdi, [rsp]
    mov esi, 20
    call x_req
    xor ebx, ebx
1:  cmp ebx, 7
    jae 9f
    call x_new_id
    lea rcx, [rip + cursors]
    mov [rcx + rbx*4], eax
    lea rcx, [rip + cursor_glyphs]
    movzx ecx, byte ptr [rcx + rbx]
    mov byte ptr [rsp], 94      # CreateGlyphCursor
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 8
    mov [rsp + 4], eax
    mov edx, [rip + cursor_font]
    mov [rsp + 8], edx
    mov [rsp + 12], edx
    mov [rsp + 16], cx
    inc ecx
    mov [rsp + 18], cx
    mov word ptr [rsp + 20], 0      # fore rgb (black)
    mov word ptr [rsp + 22], 0
    mov word ptr [rsp + 24], 0
    mov word ptr [rsp + 26], 0xffff # back rgb (white)
    mov word ptr [rsp + 28], 0xffff
    mov word ptr [rsp + 30], 0xffff
    lea rdi, [rsp]
    mov esi, 32
    call x_req
    inc ebx
    jmp 1b
9:  EPILOGUE

# x_open_window(title)
FN x_open_window
    PROLOGUE 64
    mov r15, rdi
    call x_big_requests
    call x_load_keymap
    lea rdi, [rip + .La_wm_protocols]
    call x_intern
    mov [rip + a_wm_protocols], eax
    lea rdi, [rip + .La_wm_delete]
    call x_intern
    mov [rip + a_wm_delete], eax
    lea rdi, [rip + .La_net_wm_name]
    call x_intern
    mov [rip + a_net_wm_name], eax
    lea rdi, [rip + .La_utf8]
    call x_intern
    mov [rip + a_utf8], eax
    lea rdi, [rip + .La_clipboard]
    call x_intern
    mov [rip + a_clipboard], eax
    lea rdi, [rip + .La_targets]
    call x_intern
    mov [rip + a_targets], eax
    lea rdi, [rip + .La_sel_prop]
    call x_intern
    mov [rip + a_sel_prop], eax
    lea rdi, [rip + .La_net_wm_state]
    call x_intern
    mov [rip + a_net_wm_state], eax
    lea rdi, [rip + .La_max_h]
    call x_intern
    mov [rip + a_max_h], eax
    lea rdi, [rip + .La_max_v]
    call x_intern
    mov [rip + a_max_v], eax
    lea rdi, [rip + .La_change_state]
    call x_intern
    mov [rip + a_wm_change_state], eax
    call x_cursor_init
    # window
    call x_new_id
    mov [rip + win], eax
    mov dword ptr [rip + win_w], 1280
    mov dword ptr [rip + win_h], 820
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rsp], 1       # CreateWindow
    mov eax, [rip + root_depth]
    mov [rsp + 1], al
    mov word ptr [rsp + 2], 10
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + root]
    mov [rsp + 8], eax
    mov word ptr [rsp + 16], 1280
    mov word ptr [rsp + 18], 820
    mov word ptr [rsp + 22], 1      # InputOutput
    mov dword ptr [rsp + 24], 0     # CopyFromParent visual
    mov dword ptr [rsp + 28], 0x0802    # CWBackPixel | CWEventMask
    mov dword ptr [rsp + 32], 0x001c1e24
    mov dword ptr [rsp + 36], EVMASK
    lea rdi, [rsp]
    mov esi, 40
    call x_req
    # gc
    call x_new_id
    mov [rip + gc], eax
    mov byte ptr [rsp], 55      # CreateGC
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 4
    mov [rsp + 4], eax
    mov eax, [rip + win]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0
    lea rdi, [rsp]
    mov esi, 16
    call x_req
    # WM_PROTOCOLS, WM_CLASS, title
    mov edi, [rip + win]
    mov esi, [rip + a_wm_protocols]
    mov edx, 4                  # ATOM
    mov ecx, 32
    lea r8, [rip + a_wm_delete]
    mov r9d, 1
    call x_change_prop
    mov edi, [rip + win]
    mov esi, 67                 # WM_CLASS
    mov edx, 31                 # STRING
    mov ecx, 8
    lea r8, [rip + .Lwm_class]
    mov r9d, 10
    call x_change_prop
    mov rdi, r15
    call x_title
    # map
    mov byte ptr [rsp], 8       # MapWindow
    mov word ptr [rsp + 2], 2
    mov eax, [rip + win]
    mov [rsp + 4], eax
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    call x_flush
    mov dword ptr [rip + g_csd], 0
    call x_resize_fb
    # vtable
    lea rax, [rip + x_flush]
    mov [rip + g_plat + P_flush], rax
    lea rax, [rip + x_timeout]
    mov [rip + g_plat + P_timeout], rax
    lea rax, [rip + x_tick]
    mov [rip + g_plat + P_tick], rax
    lea rax, [rip + x_draw]
    mov [rip + g_plat + P_draw], rax
    lea rax, [rip + x_set_cursor]
    mov [rip + g_plat + P_cursor], rax
    lea rax, [rip + x_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + x_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    lea rax, [rip + x_nop]
    mov [rip + g_plat + P_move], rax
    mov [rip + g_plat + P_resize], rax
    mov [rip + g_plat + P_menu], rax
    lea rax, [rip + x_minimize]
    mov [rip + g_plat + P_minimize], rax
    lea rax, [rip + x_maximize]
    mov [rip + g_plat + P_maximize], rax
    lea rax, [rip + x_title]
    mov [rip + g_plat + P_title], rax
    mov edi, [rip + xfd]
    mov esi, POLLIN
    lea rdx, [rip + x_on_readable]
    xor ecx, ecx
    call watch_add
    EPILOGUE

x_nop:
    ret

x_timeout:
    mov eax, -1
    ret

x_tick:
    cmp dword ptr [rip + keymap_stale], 0
    je 1f
    mov dword ptr [rip + keymap_stale], 0
    jmp x_load_keymap
1:  ret

FN x_title
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call strlen
    mov r12d, eax
    mov edi, [rip + win]
    mov esi, [rip + a_net_wm_name]
    mov edx, [rip + a_utf8]
    mov ecx, 8
    mov r8, rbx
    mov r9d, r12d
    call x_change_prop
    mov edi, [rip + win]
    mov esi, 39                 # WM_NAME
    mov edx, 31                 # STRING
    mov ecx, 8
    mov r8, rbx
    mov r9d, r12d
    call x_change_prop
    add rsp, 8
    pop r12
    pop rbx
    ret

x_resize_fb:
    push rbx
    mov eax, [rip + win_w]
    cmp eax, [rip + fb_w]
    jne 1f
    mov eax, [rip + win_h]
    cmp eax, [rip + fb_h]
    je 2f
1:  mov rdi, [rip + fbuf]
    call mem_free
    mov eax, [rip + win_w]
    mov [rip + fb_w], eax
    mov ecx, [rip + win_h]
    mov [rip + fb_h], ecx
    imul eax, ecx
    lea rdi, [rax*4]
    call mem_alloc
    mov [rip + fbuf], rax
    mov edi, [rip + fb_w]
    mov esi, [rip + fb_h]
    call app_on_resize
2:  mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# x_draw(): render and PutImage (one request with BIG-REQUESTS, strips otherwise)
x_draw:
    PROLOGUE 48
    mov rdi, [rip + fbuf]
    mov esi, [rip + fb_w]
    mov edx, [rip + fb_h]
    mov ecx, esi
    call gfx_set_target
    mov dword ptr [rip + g_dirty], 0
    call app_render
    call x_flush
    # rows per request
    mov eax, [rip + max_req]
    shl rax, 2
    sub rax, 32
    xor edx, edx
    mov ecx, [rip + fb_w]
    shl ecx, 2
    div rcx
    mov r12d, eax
    test r12d, r12d
    jz .Lxd_ret
    xor ebx, ebx                # row
.Lxd_strip:
    cmp ebx, [rip + fb_h]
    jae .Lxd_ret
    mov r13d, [rip + fb_h]
    sub r13d, ebx
    cmp r13d, r12d
    cmova r13d, r12d            # rows in this request
    mov eax, [rip + fb_w]
    imul eax, r13d
    shl eax, 2
    mov r14d, eax               # pixel bytes
    # header (28 bytes with the big-request length word, else 24)
    lea rdi, [rsp]
    mov byte ptr [rdi], 72      # PutImage
    mov byte ptr [rdi + 1], 2   # ZPixmap
    cmp dword ptr [rip + big_req], 0
    je 1f
    mov word ptr [rdi + 2], 0
    lea eax, [r14 + 28]
    shr eax, 2
    mov [rdi + 4], eax
    add rdi, 4
    mov r15d, 28
    jmp 2f
1:  lea eax, [r14 + 24]
    shr eax, 2
    mov [rdi + 2], ax
    mov r15d, 24
2:  mov eax, [rip + win]
    mov [rdi + 4], eax
    mov eax, [rip + gc]
    mov [rdi + 8], eax
    mov eax, [rip + fb_w]
    mov [rdi + 12], ax
    mov [rdi + 14], r13w
    mov word ptr [rdi + 16], 0
    mov [rdi + 18], bx
    mov byte ptr [rdi + 20], 0
    mov eax, [rip + root_depth]
    mov [rdi + 21], al
    mov word ptr [rdi + 22], 0
    # writev(header, pixels)
    lea rax, [rsp]
    mov [rip + iov2], rax
    mov [rip + iov2 + 8], r15
    mov eax, ebx
    imul eax, [rip + fb_w]
    shl rax, 2
    add rax, [rip + fbuf]
    mov [rip + iov2 + 16], rax
    mov [rip + iov2 + 24], r14
    call x_writev2
    inc dword ptr [rip + seq]
    add ebx, r13d
    jmp .Lxd_strip
.Lxd_ret:
    EPILOGUE

# write both iovecs completely
x_writev2:
    push rbx
1:  mov edi, [rip + xfd]
    lea rsi, [rip + iov2]
    mov edx, 2
    mov eax, 20                 # writev
    syscall
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 1b
    test rax, rax
    js 9f
    # advance
    mov rcx, [rip + iov2 + 8]
    cmp rax, rcx
    jb 2f
    sub rax, rcx
    mov qword ptr [rip + iov2 + 8], 0
    add [rip + iov2 + 16], rax
    sub [rip + iov2 + 24], rax
    cmp qword ptr [rip + iov2 + 24], 0
    jne 1b
    jmp 9f
2:  add [rip + iov2], rax
    sub [rip + iov2 + 8], rax
    jmp 1b
9:  pop rbx
    ret

x_set_cursor:
    cmp edi, [rip + cur_shape]
    je 1f
    mov [rip + cur_shape], edi
    cmp edi, 7
    jae 1f
    lea rax, [rip + cursors]
    mov eax, [rax + rdi*4]
    sub rsp, 24
    mov byte ptr [rsp], 2       # ChangeWindowAttributes
    mov word ptr [rsp + 2], 4
    mov ecx, [rip + win]
    mov [rsp + 4], ecx
    mov dword ptr [rsp + 8], 0x4000     # CWCursor
    mov [rsp + 12], eax
    mov rdi, rsp
    mov esi, 16
    call x_req
    add rsp, 24
1:  ret

# clipboard: become the CLIPBOARD owner
x_clip_set:
    push rbx
    push r12
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + xclip]
    call sb_clear
    lea rdi, [rip + xclip]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    mov byte ptr [rsp], 22      # SetSelectionOwner
    mov word ptr [rsp + 2], 4
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_clipboard]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0
    mov rdi, rsp
    mov esi, 16
    call x_req
    mov dword ptr [rip + own_clip], 1
    add rsp, 24
    pop r12
    pop rbx
    ret

# paste: ask the owner to convert CLIPBOARD to UTF8_STRING into our property
x_clip_get:
    cmp dword ptr [rip + own_clip], 0
    je 1f
    mov rdi, [rip + xclip + SB_ptr]
    mov rsi, [rip + xclip + SB_len]
    jmp app_on_paste
1:  sub rsp, 40
    mov byte ptr [rsp], 24      # ConvertSelection
    mov word ptr [rsp + 2], 6
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_clipboard]
    mov [rsp + 8], eax
    mov eax, [rip + a_utf8]
    mov [rsp + 12], eax
    mov eax, [rip + a_sel_prop]
    mov [rsp + 16], eax
    mov dword ptr [rsp + 20], 0
    mov rdi, rsp
    mov esi, 24
    call x_req
    add rsp, 40
    ret

# SelectionNotify arrived: GetProperty (delete) and deliver the reply asynchronously
x_get_paste:
    sub rsp, 40
    mov byte ptr [rsp], 20      # GetProperty
    mov byte ptr [rsp + 1], 1   # delete
    mov word ptr [rsp + 2], 6
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_sel_prop]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0         # AnyPropertyType
    mov dword ptr [rsp + 16], 0
    mov dword ptr [rsp + 20], 0x1000000 # up to 64 MiB
    mov rdi, rsp
    mov esi, 24
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    mov dword ptr [rip + paste_wait], 1
    add rsp, 40
    ret

# x_serve_selection(event): answer another client's paste request
x_serve_selection:
    PROLOGUE 48
    mov rbx, rdi
    mov r12d, [rbx + 12]        # requestor
    mov r13d, [rbx + 16]        # selection
    mov r14d, [rbx + 20]        # target
    mov r15d, [rbx + 24]        # property
    test r15d, r15d
    jnz 1f
    mov r15d, r14d
1:  cmp r14d, [rip + a_targets]
    jne 2f
    mov eax, [rip + a_targets]
    mov [rsp + 32], eax
    mov eax, [rip + a_utf8]
    mov [rsp + 36], eax
    mov dword ptr [rsp + 40], 31        # STRING
    mov edi, r12d
    mov esi, r15d
    mov edx, 4
    mov ecx, 32
    lea r8, [rsp + 32]
    mov r9d, 3
    call x_change_prop
    jmp 4f
2:  cmp r14d, [rip + a_utf8]
    je 3f
    cmp r14d, 31
    je 3f
    xor r15d, r15d              # refuse
    jmp 4f
3:  mov edi, r12d
    mov esi, r15d
    mov edx, r14d
    mov ecx, 8
    mov r8, [rip + xclip + SB_ptr]
    mov r9, [rip + xclip + SB_len]
    call x_change_prop
4:  # SendEvent SelectionNotify
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 44
    call memset
    mov byte ptr [rsp], 25      # SendEvent
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov [rsp + 4], r12d
    mov dword ptr [rsp + 8], 0
    mov byte ptr [rsp + 12], 31 # SelectionNotify
    mov eax, [rbx + 4]
    mov [rsp + 16], eax         # time
    mov [rsp + 20], r12d
    mov [rsp + 24], r13d
    mov [rsp + 28], r14d
    mov [rsp + 32], r15d
    lea rdi, [rsp]
    mov esi, 44
    call x_req
    EPILOGUE

# _NET_WM_STATE toggle (maximize) via a client message to the root window
x_maximize:
    sub rsp, 56
    mov byte ptr [rsp], 25      # SendEvent
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x180000   # SubstructureNotify | SubstructureRedirect
    mov byte ptr [rsp + 12], 33 # ClientMessage
    mov byte ptr [rsp + 13], 32
    mov word ptr [rsp + 14], 0
    mov eax, [rip + win]
    mov [rsp + 16], eax
    mov eax, [rip + a_net_wm_state]
    mov [rsp + 20], eax
    mov dword ptr [rsp + 24], 2         # toggle
    mov eax, [rip + a_max_h]
    mov [rsp + 28], eax
    mov eax, [rip + a_max_v]
    mov [rsp + 32], eax
    mov dword ptr [rsp + 36], 1
    mov dword ptr [rsp + 40], 0
    mov rdi, rsp
    mov esi, 44
    call x_req
    add rsp, 56
    ret

x_minimize:
    sub rsp, 56
    mov byte ptr [rsp], 25
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x180000
    mov byte ptr [rsp + 12], 33
    mov byte ptr [rsp + 13], 32
    mov word ptr [rsp + 14], 0
    mov eax, [rip + win]
    mov [rsp + 16], eax
    mov eax, [rip + a_wm_change_state]
    mov [rsp + 20], eax
    mov dword ptr [rsp + 24], 3         # IconicState
    mov dword ptr [rsp + 28], 0
    mov dword ptr [rsp + 32], 0
    mov dword ptr [rsp + 36], 0
    mov dword ptr [rsp + 40], 0
    mov rdi, rsp
    mov esi, 44
    call x_req
    add rsp, 56
    ret

.section .rodata
.Ldisplay_env: .asciz "DISPLAY"
.Lxauth_env: .asciz "XAUTHORITY"
.Lhome: .asciz "HOME"
.Lxauth_file: .asciz ".Xauthority"
.Lsock_prefix: .asciz "/tmp/.X11-unix/X"
.Lmit: .ascii "MIT-MAGIC-COOKIE-1\0\0"
.Lbigreq: .ascii "BIG-REQUESTS"
.Lclosed: .asciz "rhun: X11 connection closed"
.La_wm_protocols: .asciz "WM_PROTOCOLS"
.La_wm_delete: .asciz "WM_DELETE_WINDOW"
.La_net_wm_name: .asciz "_NET_WM_NAME"
.La_utf8: .asciz "UTF8_STRING"
.La_clipboard: .asciz "CLIPBOARD"
.La_targets: .asciz "TARGETS"
.La_sel_prop: .asciz "RHUN_SELECTION"
.La_net_wm_state: .asciz "_NET_WM_STATE"
.La_max_h: .asciz "_NET_WM_STATE_MAXIMIZED_HORZ"
.La_max_v: .asciz "_NET_WM_STATE_MAXIMIZED_VERT"
.La_change_state: .asciz "WM_CHANGE_STATE"
.Lwm_class: .ascii "rhun\0rhun\0"
# CUR_* -> X cursor font glyphs: left_ptr xterm hand2 sb_h_double_arrow sb_v_double_arrow bottom_right_corner bottom_left_corner
cursor_glyphs: .byte 68, 152, 60, 108, 116, 14, 12

.bss
paste_wait: .long 0
keymap_stale: .long 0

.data
xfd: .long -1
cur_shape: .long -1
want_seq: .long -1
