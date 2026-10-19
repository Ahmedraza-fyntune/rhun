# WebAssembly extensions: a manifest's run.wasm32-wasip1 = FILE.wasm runs, when the manifest names
# no program for this system, as rhun itself in its --wasm-host mode (src/wasm/wasi.s). The module
# sees the folders its [needs] allow as WASI preopened directories (its state folder always, the
# project and home as declared), and nothing else, on every system; where the kernel sandbox
# exists (confine.s) it holds the host process as it holds any extension program.
.include "rhun.inc"

.bss
.p2align 3
self_buf: .zero 4096

.text
# ext_wasm_program(ext) -> rax 0 when the extension runs as WebAssembly (EXT_prog is then rhun's
# own executable), 1 when it names no module either, else the reason the module cannot run
FN ext_wasm_program
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + EXT_wasm]
    test rdi, rdi
    jz 8f
    mov esi, 4                  # R_OK
    SYS SYS_access
    test rax, rax
    jz 1f
    lea rax, [rip + .Lr_no_module]
    EPILOGUE
1:  lea rdi, [rip + self_buf]
    mov esi, 4096
    call proc_self_path
    test rax, rax
    jle 7f
    lea rdi, [rip + self_buf]
    call dup_cstr
    mov [rbx + EXT_prog], rax
    mov dword ptr [rbx + EXT_wasm_run], 1
    xor eax, eax
    EPILOGUE
7:  lea rax, [rip + .Lr_no_self]
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# ext_wasm_held(ext): a WebAssembly extension is held to its permissions by its WASI host on every
# system, whatever the kernel adds (confine.s still prepares the kernel's part where it can)
FN ext_wasm_held
    cmp dword ptr [rdi + EXT_wasm_run], 0
    je 1f
    mov dword ptr [rdi + EXT_confined], CONFINED_FULL
    mov qword ptr [rdi + EXT_confine_why], 0
1:  ret

# ext_wasm_argv(ext, argv vec) -> rax 0 or -errno: rhun --wasm-host, the folders, the module, the
# manifest's args; the strings are launch scratch (extlaunchscratch.s)
FN ext_wasm_argv
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [r12 + VEC_len], 0
    mov rdi, [rbx + EXT_prog]
    call .Lpush
    lea rdi, [rip + .Lo_host]
    call .Lpush
    # the state folder: read and write, as for every extension; its own folder, read only (a
    # native program's working folder: the module finds it from its path, its first argument)
    lea rdi, [rip + .Lo_dir]
    call .Lpush
    mov rdi, [rbx + EXT_state]
    call .Lpush
    lea rdi, [rip + .Lo_dir_ro]
    call .Lpush
    mov rdi, [rbx + EXT_dir]
    call .Lpush
    # the project, as [needs] project says
    mov rax, [rip + g_project]
    test rax, rax
    jz 2f
    test dword ptr [rbx + EXT_needs], NEEDS_PROJECT_READ | NEEDS_PROJECT_WRITE
    jz 2f
    lea rdi, [rip + .Lo_dir_ro]
    test dword ptr [rbx + EXT_needs], NEEDS_PROJECT_WRITE
    jz 1f
    lea rdi, [rip + .Lo_dir]
1:  call .Lpush
    mov rdi, [rip + g_project]
    call .Lpush
2:  # the home folder, read only, with home = read
    test dword ptr [rbx + EXT_needs], NEEDS_HOME_READ
    jz 3f
    lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 3f
    mov r13, rax
    lea rdi, [rip + .Lo_dir_ro]
    call .Lpush
    mov rdi, r13
    call .Lpush
3:  mov rdi, [rbx + EXT_wasm]
    call .Lpush
    # the manifest's args, word by word
    mov r13, [rbx + EXT_args]
    test r13, r13
    jz 8f
    mov rdi, r13
    call strlen
    mov r14, rax
4:  test r14, r14
    jz 8f
    mov rdi, r13
    mov rsi, r14
    call next_word
    add r13, rcx
    sub r14, rcx
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call ext_launch_scratch_dup
    test rax, rax
    jz 9f
    mov rdi, rax
    call .Lpush
    jmp 4b
8:  xor edi, edi
    call .Lpush
    call ext_launch_scratch_error
    EPILOGUE
9:  call ext_launch_scratch_error
    EPILOGUE
# push(string rdi) onto the argv vector (a failure is kept by the scratch)
.Lpush:
    push rdi
    mov rdi, r12
    mov esi, 8
    call ext_launch_scratch_push
    pop rdi
    test rax, rax
    jz 1f
    mov [rax], rdi
1:  ret

# ---------------------------------------------------------------- headless commands (control.s)

# wait-toast TEXT: until the toast on screen starts with TEXT (10 s at most); prints the toast
# then, "toast=" when none (as print-toast)
wasm_wait_toast:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call time_ms
    lea r14, [rax + 10000]
1:  call time_ms
    cmp rax, [rip + g_toast_until]
    jae 2f
    lea rdi, [rip + g_toast]
    call strlen
    cmp rax, r13
    jb 2f
    lea rdi, [rip + g_toast]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jnz 3f
2:  call time_ms
    cmp rax, r14
    jae 3f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rip + .Ls_toast]
    call sb_push_cstr
    call time_ms
    cmp rax, [rip + g_toast_until]
    jae 4f
    mov rdi, rbx
    lea rsi, [rip + g_toast]
    call sb_push_cstr
4:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# print-wasm: one line per extension that runs as WebAssembly: OWNER/NAME module=PATH
wasm_print:
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    cmp dword ptr [rbx + EXT_wasm_run], 0
    je 1b
    mov rdi, r12
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ls_module]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + EXT_wasm]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
.globl wasm_ctl
wasm_ctl:
    .quad .Lc_wait_toast, wasm_wait_toast, .Lc_print_wasm, wasm_print
    .quad 0, 0
.Lc_wait_toast: .asciz "wait-toast"
.Lc_print_wasm: .asciz "print-wasm"
.Ls_toast: .asciz "toast="
.Ls_module: .asciz " module="
.Lo_host: .asciz "--wasm-host"
.Lo_dir: .asciz "--dir"
.Lo_dir_ro: .asciz "--dir-ro"
.ifdef WINDOWS
.Lenv_home: .asciz "USERPROFILE"
.else
.Lenv_home: .asciz "HOME"
.endif
.Lr_no_module: .asciz "the WebAssembly module named by run.wasm32-wasip1 is missing"
.Lr_no_self: .asciz "rhun cannot find its own executable to run the WebAssembly module"
