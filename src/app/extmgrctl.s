# extension management's headless commands (control.s hands them the commands it does not know):
#   ext-install-folder PATH [copy|link]   Install from Folder (copied) or Link a Folder
#   ext-install-archive PATH              Install from Archive
#   ext-rollback NAME                     Roll back to the previous version (asks when it may do more)
#   print-ext-versions NAME               "version=V source=S tag=T previous=P link=yes|no fresh=0|1"
.include "rhun.inc"

.bss
.p2align 3
xm_out: .quad 0                 # control.s's output buffer
xm_buf: .zero 4096

.text

# extmgr_control(cmd ptr, len, rest ptr, len, out sb) -> rax 0 done, -1 not one of these
FN extmgr_control
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov [rip + xm_out], r8
    lea rbx, [rip + xm_table]
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add rbx, 16
    jmp 1b
2:  mov rdi, r14
    mov rsi, r15
    call [rbx + 8]
    xor eax, eax
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# xm_push(cstr): onto the output
xm_push:
    mov rsi, rdi
    mov rdi, [rip + xm_out]
    jmp sb_push_cstr

# xm_ext(ptr, len) -> the extension named by the first word of the arguments, or 0 (the output says so)
xm_ext:
    PROLOGUE
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jnz 9f
    push rax
    push rax
    lea rdi, [rip + .Lno_ext]
    call xm_push
    pop rax
    pop rax
9:  EPILOGUE

# ext-install-folder PATH [copy|link]
c_install_folder:
    PROLOGUE
    call trim
    mov rbx, rax
    mov r12, rdx
    mov r13d, IK_FOLDER
    cmp r12, 5
    jb 9f
    lea rdi, [rbx + r12 - 5]
    mov esi, 5
    lea rdx, [rip + .Lsp_link]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov r13d, IK_LINK
    sub r12, 5
    jmp 9f
1:  lea rdi, [rbx + r12 - 5]
    mov esi, 5
    lea rdx, [rip + .Lsp_copy]
    call str_eq_cstr
    test eax, eax
    jz 9f
    sub r12, 5
9:  mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ext_install_local
    EPILOGUE

# ext-install-archive PATH
c_install_archive:
    PROLOGUE
    mov edx, IK_ARCHIVE
    call ext_install_local
    EPILOGUE

# ext-rollback NAME
c_rollback:
    PROLOGUE
    call xm_ext
    test rax, rax
    jz 9f
    mov rdi, rax
    call ext_rollback_ask
9:  EPILOGUE

# print-ext-versions NAME
c_print_versions:
    PROLOGUE
    call xm_ext
    test rax, rax
    jz 9f
    mov rbx, rax
    lea rdi, [rip + .Lp_version]
    call xm_push
    mov rdi, [rbx + EXT_version]
    test rdi, rdi
    jz 1f
    call xm_push
1:  lea rdi, [rip + .Lp_source]
    lea rsi, [rip + .Lk_source]
    call xm_rec_pair
    lea rdi, [rip + .Lp_tag]
    lea rsi, [rip + .Lk_tag]
    call xm_rec_pair
    lea rdi, [rip + .Lp_previous]
    call xm_push
    mov rdi, [rbx + EXT_prev]
    test rdi, rdi
    jnz 2f
    lea rdi, [rip + .Ldash]
2:  call xm_push
    lea rdi, [rip + .Lp_link]
    call xm_push
    lea rdi, [rip + .Lno]
    cmp qword ptr [rbx + EXT_inst], 0
    je 3f
    lea rdi, [rip + .Lyes]
3:  call xm_push
    lea rdi, [rip + .Lp_fresh]
    call xm_push
    mov rdi, [rip + xm_out]
    mov esi, [rbx + EXT_fresh]
    call sb_push_u64
    mov rdi, [rip + xm_out]
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

# xm_rec_pair(" key=", record key): " key=VALUE" (or "-") for rbx's record
xm_rec_pair:
    PROLOGUE
    mov r12, rsi
    call xm_push
    mov rdi, rbx
    mov rsi, r12
    call extrec_get
    test rax, rax
    jz 8f
    test rdx, rdx
    jz 8f
    cmp rdx, 4000
    ja 8f
    lea rdi, [rip + xm_buf]
    mov rsi, rax
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rdi, [rip + xm_buf]
    mov byte ptr [rdi + rdx], 0
    call xm_push
    EPILOGUE
8:  lea rdi, [rip + .Ldash]
    call xm_push
    EPILOGUE

.section .rodata
.Lc_install_folder: .asciz "ext-install-folder"
.Lc_install_archive: .asciz "ext-install-archive"
.Lc_rollback: .asciz "ext-rollback"
.Lc_print_versions: .asciz "print-ext-versions"
.Lsp_link: .asciz " link"
.Lsp_copy: .asciz " copy"
.Lno_ext: .asciz "no such extension\n"
.Lp_version: .asciz "version="
.Lp_source: .asciz " source="
.Lp_tag: .asciz " tag="
.Lp_previous: .asciz " previous="
.Lp_link: .asciz " link="
.Lp_fresh: .asciz " fresh="
.Lk_source: .asciz "source"
.Lk_tag: .asciz "tag"
.Ldash: .asciz "-"
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.p2align 3
xm_table:
    .quad .Lc_install_folder, c_install_folder, .Lc_install_archive, c_install_archive
    .quad .Lc_rollback, c_rollback, .Lc_print_versions, c_print_versions
    .quad 0, 0
