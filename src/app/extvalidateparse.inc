.include "app/extprepare.inc"
# Included only by ext.s: real manifest callbacks without global command publication.
.bss
.p2align 3
.globl g_ext_manifest_private
g_ext_manifest_private: .quad 0
g_ext_manifest_owner: .quad 0
.text
# Fresh zeroed EXT, bounded checked bytes, borrowed directory. Isolated process only.
FN ext_manifest_parse_private
    PROLOGUE INI_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rbx + EXT_dir], rcx
    mov r14, [rip + cur_ext]
    mov r15, [rip + g_ext_manifest_private]
    mov [rip + cur_ext], rbx
    mov qword ptr [rip + g_ext_manifest_private], 1
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call ini_init
1:  mov rdi, rsp
    call ini_next
    test eax, eax
    jz 2f
    mov rdi, rsp
    call manifest_kv
    jmp 1b
2:  mov [rip + cur_ext], r14
    mov [rip + g_ext_manifest_private], r15
    xor eax, eax
    EPILOGUE
# Keep Windows' existing python3/python/py resolution semantics in the actual parser object.
FN ext_manifest_runtime
.ifdef WINDOWS
    jmp win_runtime
.else
    jmp proc_which
.endif

# Actual manifest callbacks with a private allocation context. Globals restored on every exit.
FN ext_manifest_parse_owned
    PROLOGUE INI_SIZE + 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rip + cur_ext]
    mov r15, [rip + g_ext_manifest_private]
    mov rax, [rip + g_ext_manifest_owner]
    mov [rsp + INI_SIZE], rax
    lea rax, [rbx + EP_ext]
    mov [rip + cur_ext], rax
    mov qword ptr [rip + g_ext_manifest_private], 2
    mov [rip + g_ext_manifest_owner], rbx
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call ini_init
1:  cmp qword ptr [rbx + PO_error], 0
    jne 2f
    mov rdi, rsp
    call ini_next
    test eax, eax
    jz 2f
    mov rdi, rsp
    call manifest_kv
    jmp 1b
2:  mov [rip + cur_ext], r14
    mov [rip + g_ext_manifest_private], r15
    mov rax, [rsp + INI_SIZE]
    mov [rip + g_ext_manifest_owner], rax
    mov rax, [rbx + PO_error]
    EPILOGUE

# Same callback argument shapes as the legacy allocator helpers.
ext_manifest_dup:
    mov rax, [rip + g_ext_manifest_owner]
    test rax, rax
    jz 1f
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rax
    jmp prep_owned_dup
1:  jmp mem_dup
ext_manifest_free:
    mov rax, [rip + g_ext_manifest_owner]
    test rax, rax
    jz 1f
    mov rsi, rdi
    mov rdi, rax
    jmp prep_owned_free
1:  jmp mem_free
ext_manifest_vec_push:
    mov rax, [rip + g_ext_manifest_owner]
    test rax, rax
    jz 1f
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rax
    jmp prep_owned_vec_push
1:  jmp vec_push

# Complete the actual provider/activation/default semantics without publishing anything.
FN ext_manifest_finish_owned
    PROLOGUE 16
    mov rbx, rdi
    mov rax, [rip + g_ext_manifest_owner]
    mov [rsp], rax
    mov [rip + g_ext_manifest_owner], rbx
    call ext_prepare_defaults
    test rax, rax
    jnz 9f
    mov rdi, rbx
    call ext_prepare_runs_check
    test rax, rax
    jnz 9f
    cmp dword ptr [rbx + EP_ext + EXT_on], 0
    jne 1f
    mov dword ptr [rbx + EP_ext + EXT_on], ON_STARTUP | ON_COMMAND
1:  lea rdi, [rbx + EP_ext]
    mov rsi, [rbx + EP_ext + EXT_pv_complete]
    call provides_merge
    lea rdi, [rbx + EP_ext]
    mov rsi, [rbx + EP_ext + EXT_pv_signature]
    call provides_merge
    xor r12d, r12d
2:  cmp qword ptr [rbx + PO_error], 0
    jne 9f
    lea rax, [rip + pv_more]
    mov rcx, [rax + r12*8]
    test rcx, rcx
    jz 9f
    lea rdi, [rbx + EP_ext]
    mov rsi, [rdi + rcx]
    call provides_merge
    inc r12
    jmp 2b
9:  mov rax, [rsp]
    mov [rip + g_ext_manifest_owner], rax
    mov rax, [rbx + PO_error]
    EPILOGUE
