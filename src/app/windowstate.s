# Native window placement is separate from project/tab sessions and from headless dimensions.
.include "rhun.inc"
.bss
.p2align 3
path: .zero SB_SIZE
.globl g_window_save
g_window_save: .quad 0          # installed only by native backends that use this state file
.text

# window_state_valid(record) -> bool. Ignore corrupt/future state before any native allocation.
FN window_state_valid
    cmp dword ptr [rdi + WPOS_magic], WPOS_MAGIC
    jne 9f
    cmp dword ptr [rdi + WPOS_max], 3
    ja 9f
    mov eax, [rdi + WPOS_w]
    sub eax, 1
    cmp eax, 8192 - 1
    ja 9f
    mov eax, [rdi + WPOS_h]
    sub eax, 1
    cmp eax, 8192 - 1
    ja 9f
    mov eax, [rdi + WPOS_x]
    add eax, 1048576
    cmp eax, 2097152
    ja 9f
    mov eax, [rdi + WPOS_y]
    add eax, 1048576
    cmp eax, 2097152
    ja 9f
    mov eax, 1
    ret
9:  xor eax, eax
    ret

# window_state_path(backend constant cstr) -> path, or 0 with no state directory.
window_state_path:
    PROLOGUE
    mov r12, rdi
    lea rdi, [rip + path]
    call session_state_dir
    test eax, eax
    jz 9f
    lea rdi, [rip + path]
    lea rsi, [rip + prefix]
    call sb_push_cstr
    lea rdi, [rip + path]
    mov rsi, r12
    call sb_push_cstr
    mov rax, [rip + path + SB_ptr]
9:  EPILOGUE

# window_state_load(backend constant cstr, record) -> bool; failure leaves record unchanged.
FN window_state_load
    PROLOGUE
    mov rbx, rsi
    call window_state_path
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, WPOS_SIZE
    call file_read_limited
    mov r12, rax
    test rax, rax
    jz 9f
    xor r13d, r13d
    cmp rdx, WPOS_SIZE
    jne 8f
    mov rdi, r12
    call window_state_valid
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    mov edx, WPOS_SIZE
    call memcpy
    mov r13d, 1
8:  mov rdi, r12
    call mem_free
    mov eax, r13d
9:  EPILOGUE

# window_state_save(backend constant cstr, record): best effort, using the atomic file writer.
FN window_state_save
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call window_state_valid
    test eax, eax
    jz 9f
    mov rdi, rbx
    call window_state_path
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, r12
    mov edx, WPOS_SIZE
    call file_write_all
9:  EPILOGUE
.section .rodata
prefix: .asciz "/window-"
