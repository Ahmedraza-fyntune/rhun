# The WebAssembly worker modes of the rhun binary: rhun --wasm-host (an extension compiled to
# wasm32-wasip1, run behind the extension pipe protocol) and rhun --wasm-spec (the spec tests).
.include "rhun.inc"
.include "wasm/wasm.inc"

.text
# wasm_worker_main(argc, argv): runs a worker mode named by argv[1] and exits; returns otherwise
FN wasm_worker_main
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp r12, 2
    jb 9f
    mov rdi, [r13 + 8]
    lea rsi, [rip + .Lo_spec]
    call strcmp_eq
    test eax, eax
    jz 1f
    mov rdi, r12
    mov rsi, r13
    call wasm_spec_main
1:  mov rdi, [r13 + 8]
    lea rsi, [rip + .Lo_host]
    call strcmp_eq
    test eax, eax
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call wasm_host_main
9:  EPILOGUE

.section .rodata
.Lo_spec: .asciz "--wasm-spec"
.Lo_host: .asciz "--wasm-host"
