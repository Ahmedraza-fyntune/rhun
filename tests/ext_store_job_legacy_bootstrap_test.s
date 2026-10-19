.ifdef WINDOWS
# Child bootstrap is stack-only and never changes cwd for absent or malformed input.
.include "win.inc"
.section .rdata,"dr"
elf_boot_cases: .quad 0,elf_boot_empty,elf_boot_relative,elf_boot_drive_relative,elf_boot_root_relative,elf_boot_device,elf_boot_device_dot,elf_boot_unc_no_share,elf_boot_unc_empty_server,elf_boot_unc_empty_share,elf_boot_unc_dotdot,elf_boot_large,elf_boot_invalid,elf_boot_drive,elf_boot_unc,elf_boot_control
elf_boot_empty: .asciz "RHUN_LEGACY_CWD="
elf_boot_relative: .asciz "RHUN_LEGACY_CWD=relative/path"
elf_boot_drive_relative: .asciz "RHUN_LEGACY_CWD=C:relative"
elf_boot_root_relative: .asciz "RHUN_LEGACY_CWD=/relative"
elf_boot_device: .asciz "RHUN_LEGACY_CWD=//?/C:/path"
elf_boot_device_dot: .asciz "RHUN_LEGACY_CWD=//./C:/path"
elf_boot_unc_no_share: .asciz "RHUN_LEGACY_CWD=//server"
elf_boot_unc_empty_server: .asciz "RHUN_LEGACY_CWD=///share"
elf_boot_unc_empty_share: .asciz "RHUN_LEGACY_CWD=//server/"
elf_boot_unc_dotdot: .asciz "RHUN_LEGACY_CWD=//server/.."
elf_boot_large: .ascii "RHUN_LEGACY_CWD=C:/"
.fill 4093,1,120
.byte 0
elf_boot_invalid: .ascii "RHUN_LEGACY_CWD=C:/"
.byte 255,0
elf_boot_drive: .asciz "RHUN_LEGACY_CWD=C:/"
elf_boot_unc: .asciz "RHUN_LEGACY_CWD=//server/share/space Ω"
elf_boot_control: .asciz "RHUN_LEGACY_CWD=C:/bad\npath"
.bss
elf_boot_env: .zero 16
elf_boot_calls: .zero 8
.text
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 2
    jne 9f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    mov rbx, rax
    call parse_u64
    cmp rdx, rbx
    jne 9f
    cmp rax, 15
    ja 9f
    lea rdx, [rip + elf_boot_cases]
    mov rax, [rdx + rax*8]
    mov [rip + elf_boot_env], rax
    lea rax, [rip + elf_boot_env]
    mov [rip + g_envp], rax
    mov r12, [rip + g_mem_live]
    call ext_store_job_legacy_child_context
    cmp [rip + g_mem_live], r12
    jne 9f
    mov [rsp], rax
    mov rax, [rip + elf_boot_calls]
    mov [rsp + 8], rax
    mov edi, 1
    mov rsi, rsp
    mov edx, 16
    call write_all
    test rax, rax
    jnz 9f
    xor eax, eax
    EPILOGUE
9:  mov edi, 73
    call sys_exit
FN elf_boot_chdir
    inc qword ptr [rip + elf_boot_calls]
    mov eax, 1
    ret

.else
.include "rhun.inc"
.text
FN main
    xor eax, eax
    ret
.endif
