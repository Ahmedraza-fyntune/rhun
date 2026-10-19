# Pure scoped Omarchy interpretation. No filesystem or live registry access.
.include "rhun.inc"
.include "app/themecapture.inc"
.section .rodata
tco_domain: .asciz "RHUN_OMARCHY_CAPTURE_V2"
.equ tco_domain_length, 24
tco_mode: .asciz "mode"
tco_light: .ascii "light"
tco_catppuccin: .asciz "catppuccin"
tco_catppuccin_mocha: .asciz "catppuccin-mocha"
tco_gruvbox: .asciz "gruvbox"
tco_gruvbox_dark: .asciz "gruvbox-dark"
tco_rose_pine: .asciz "rose-pine"
tco_rose_pine_dawn: .asciz "rose-pine-dawn"
.p2align 3
tco_aliases:
    .quad tco_catppuccin, tco_catppuccin_mocha, 16
    .quad tco_gruvbox, tco_gruvbox_dark, 12
    .quad tco_rose_pine, tco_rose_pine_dawn, 14
    .quad 0, 0, 0
.text
# Counted raw name -> effective length. Keep present-empty distinct at caller.
FN tc_omarchy_effective
    cmp rsi, TC_NAME_CAP
    ja .Ltco_bad
    test rsi, rsi
    jz 4f
    test rdi, rdi
    jz .Ltco_bad
1:  cmp byte ptr [rdi + rsi - 1], 32
    ja 2f
    dec rsi
    jnz 1b
2:  xor eax, eax
3:  cmp rax, rsi
    jae 5f
    cmp byte ptr [rdi + rax], 0
    je 5f
    inc rax
    jmp 3b
4:  xor eax, eax
5:  ret
# Alias lookup -> borrowed canonical pointer/length, no encoding or registry lookup.
FN theme_capture_omarchy_alias
    cmp rsi, TC_NAME_CAP
    ja .Ltco_alias_bad
    test rsi, rsi
    jz 1f
    test rdi, rdi
    jz .Ltco_alias_bad
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + tco_aliases]
2:  mov rdx, [r13]
    test rdx, rdx
    jz 4f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 3f
    add r13, 24
    jmp 2b
3:  mov rax, [r13 + 8]
    mov rdx, [r13 + 16]
    EPILOGUE
4:  mov rax, rbx
    mov rdx, r12
    EPILOGUE
.Ltco_alias_bad:
    xor eax, eax
    mov rdx, -22
    ret
# Counted colors bytes -> whether the FIRST mode key contains lowercase light.
FN tc_omarchy_light
    cmp rsi, TC_THEME_CAP
    ja .Ltco_bad
    test rsi, rsi
    jz 4f
    test rdi, rdi
    jz .Ltco_bad
    PROLOGUE INI_SIZE
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rsp
    call ini_init
1:  mov rdi, rsp
    call ini_next
    test eax, eax
    jz 3f
    mov rdi, rsp
    lea rsi, [rip + tco_mode]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    lea rdx, [rip + tco_light]
    mov ecx, 5
    call str_find
    test rax, rax
    setns al
    movzx eax, al
    EPILOGUE
3:  xor eax, eax
    EPILOGUE
4:  xor eax, eax
    ret
.Ltco_bad:
    mov rax, -22
    ret

# proof(dir,count,scope1/2,records144,out32)->0/-errno.
# Scope1 projects only the same captured name, forcibly marking remaining sources unused.
FN tc_omarchy_proof
    test rdi, rdi
    jz .Ltco_bad
    test rsi, rsi
    jz .Ltco_bad
    cmp rsi, TC_DIR_MAX
    ja .Ltco_bad
    lea rax, [rdx - 1]
    cmp rax, 1
    ja .Ltco_bad
    test rcx, rcx
    jz .Ltco_bad
    test r8, r8
    jz .Ltco_bad
    PROLOGUE 256
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp + 128], r13
    mov [rsp + 136], r12
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    lea rsi, [rip + tco_domain]
    mov edx, tco_domain_length
    call sha256_update
    test eax, eax
    jz .Ltco_hash_bad
    mov rdi, rsp
    lea rsi, [rsp + 128]
    mov edx, 16
    call sha256_update
    test eax, eax
    jz .Ltco_hash_bad
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call sha256_update
    test eax, eax
    jz .Ltco_hash_bad
    mov rdi, rsp
    mov rsi, r14
    mov edx, 48
    call sha256_update
    test eax, eax
    jz .Ltco_hash_bad
    lea rsi, [r14 + 48]
    cmp r13, TC_SCOPE_NAME
    jne 1f
    lea rdi, [rsp + 144]
    xor esi, esi
    mov edx, 96
    call memset
    mov qword ptr [rsp + 144], 2
    mov qword ptr [rsp + 192], 2
    lea rsi, [rsp + 144]
1:  mov rdi, rsp
    mov edx, 96
    call sha256_update
    test eax, eax
    jz .Ltco_hash_bad
    mov rdi, rsp
    mov rsi, r15
    call sha256_final
    test eax, eax
    jz .Ltco_hash_bad
    xor eax, eax
    EPILOGUE
.Ltco_hash_bad:
    mov rax, -5
    EPILOGUE
