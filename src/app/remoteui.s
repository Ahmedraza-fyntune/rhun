# remote windows, the window's side: what happens once connected, the bar while connecting or after
# the connection was lost, the status bar item, Connect to Host and Attach to Container, and ssh's
# password questions (rhun --ssh-askpass)
.include "rhun.inc"

.bss
.p2align 3
ru_opened: .long 0              # the project was opened (a reconnect keeps it)
.p2align 3
.globl g_remote_shell
g_remote_shell: .zero 256       # the user's shell on the host (its name names terminal tabs)
ru_sb: .zero SB_SIZE

.text

# remote_askpass_env() -> extra environment entries for the transport (0-terminated list)
FN remote_askpass_env
    lea rax, [rip + ru_env_none]
    ret

# remote_connected(): the agent answered: learn the host's home and shell, open the project
FN remote_connected
    PROLOGUE
    lea rdi, [rip + .Lv_info]
    mov esi, 4
    xor edx, edx
    xor ecx, ecx
    call remote_call
    test rax, rax
    js 3f
    # home=... shell=... lines
    mov rbx, [rip + g_remote_reply + SB_ptr]
    mov r12, [rip + g_remote_reply + SB_len]
1:  test r12, r12
    jz 3f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lnl]
    mov ecx, 1
    call str_find
    mov r13, rax                # line length
    test rax, rax
    jns 2f
    mov r13, r12
2:  mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + .Lk_home]
    mov ecx, 5
    call str_starts
    test eax, eax
    jz 21f
    lea rdi, [rip + g_remote_home]
    lea rsi, [rbx + 5]
    lea rdx, [r13 - 5]
    call ru_copy_line
21: mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + .Lk_shell]
    mov ecx, 6
    call str_starts
    test eax, eax
    jz 22f
    lea rdi, [rip + g_remote_shell]
    lea rsi, [rbx + 6]
    lea rdx, [r13 - 6]
    call ru_copy_line
22: lea rax, [r13 + 1]
    add rbx, rax
    sub r12, rax
    jg 1b
3:  cmp dword ptr [rip + ru_opened], 0
    jne 9f
    mov dword ptr [rip + ru_opened], 1
    # the folder from the command line, else the home folder
    call remote_path
    cmp byte ptr [rax], 0
    jne 4f
    lea rax, [rip + g_remote_home]
    cmp byte ptr [rax], 0
    jne 4f
    lea rax, [rip + .Lroot]
4:  mov rdi, rax
    call app_set_project
    call session_restore
    call app_update_title
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ru_copy_line(dst, ptr, len): a value of at most 255 bytes into dst with its NUL
ru_copy_line:
    test rdx, rdx
    jle 9f
    cmp rdx, 255
    jae 9f
    push rdi
    push rdx
    call memcpy
    pop rdx
    pop rdi
    mov byte ptr [rdi + rdx], 0
9:  ret

.section .rodata
.p2align 3
ru_env_none: .quad 0
.Lv_info: .asciz "info"
.Lnl: .ascii "\n"
.Lk_home: .ascii "home="
.Lk_shell: .ascii "shell="
.Lroot: .asciz "/"
.text
