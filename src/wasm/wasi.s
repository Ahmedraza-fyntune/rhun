# WASI preview 1 for rhun --wasm-host (placeholder until the host lands)
.include "rhun.inc"
.include "wasm/wasm.inc"

.text
FN wasm_host_main
    lea rdi, [rip + .Lm]
    call die
.section .rodata
.Lm: .asciz "rhun --wasm-host: not built yet"
