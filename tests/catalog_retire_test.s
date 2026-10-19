# Actual LARGE scratch retirement retains exact ledger/header/charge on unmap refusal.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.section .rodata
cl_dir: .asciz "/registry/empty"
cl_owner: .asciz "fixture"
cl_name: .asciz "empty"
cl_input: .quad cl_grammars,8192,8192,0,0,-1,83,0
.bss
.globl cl_fail_unmap, cl_failed_header, cl_failed_size, cl_failed_request, cl_unmap_calls
.p2align 3
cl_stage: .quad 0
cl_live: .quad 0
cl_charge: .quad 0
cl_base: .quad 0
cl_ep: .quad 0
cl_eps: .zero 128*8
cl_rg: .quad 0
cl_report: .zero 32
cl_gr: .zero GR_SIZE
cl_grammars: .zero 8192*8
cl_large_tested: .quad 0
cl_fail_unmap: .quad 0
cl_unmap_calls: .quad 0
cl_failed_header: .quad 0
cl_failed_size: .quad 0
cl_failed_request: .quad 0
cl_before_charge: .quad 0
cl_before_live: .quad 0
.text
cl_fail:
 mov rdi, [rip + cl_stage]
 add rdi, 60
 call sys_exit
 ud2
cl_drain:
 PROLOGUE
 mov r12d, 100000
1: mov edi, 1
 lea rsi, [rip + cl_report]
 call ext_prepare_retire_step
 test rax, rax
 js cl_fail
 cmp qword ptr [rip + cl_report], 1
 ja cl_fail
 cmp qword ptr [rip + cl_report + 16], 0
 jne cl_fail
 test rax, rax
 jz 2f
 dec r12
 jnz 1b
 jmp cl_fail
2: EPILOGUE
FN main
 PROLOGUE
 mov rax, [rip + g_mem_live]
 mov [rip + cl_live], rax
 mov rax, [rip + prep_total_charge]
 mov [rip + cl_charge], rax
 mov qword ptr [rip + cl_stage], 1
 call catalog_kind7_init
 test rax, rax
 jnz cl_fail
 lea rdx, [rip + cl_gr]
 lea rdi, [rip + cl_grammars]
 xor ecx, ecx
30: mov [rdi + rcx*8], rdx
 inc rcx
 cmp rcx, 8192
 jb 30b
 lea rdi, [rip + cl_input]
 call registry_base_begin
 test rax, rax
 jz cl_fail
 mov [rip + cl_base], rax
 mov r12d, 1000
1: mov rdi, [rip + cl_base]
 lea rsi, [rip + cl_input]
 mov edx, 65536
 call registry_base_step
 cmp r9, 16
 ja cl_fail
 test r8, r8
 jnz cl_fail
 test rax, rax
 js cl_fail
 jz 2f
 dec r12
 jnz 1b
 jmp cl_fail
2: xor r12d, r12d
20: mov rdi, -1
 lea rsi, [rip + cl_dir]
 lea rdx, [rip + cl_owner]
 lea rcx, [rip + cl_name]
 call ext_prepare_alloc
 test rax, rax
 jz cl_fail
 lea rcx, [rip + cl_eps]
 mov [rcx + r12*8], rax
 mov rdx, [rax + PO_eo]
 mov qword ptr [rdx + EO_deferred], 1
 mov qword ptr [rax + PO_ready], 1
 inc r12
 cmp r12, 128
 jb 20b
 mov rax, [rip + cl_eps]
 mov [rip + cl_ep], rax
 mov qword ptr [rip + cl_stage], 2
 xor r13d, r13d
3: mov rdi, [rip + cl_base]
 mov rsi, r13
 add rsi, 91
 call registry_begin
 test rax, rax
 jz cl_fail
 test rdx, rdx
 jnz cl_fail
 mov rbx, rax
 mov [rip + cl_rg], rax
 # A real generic RB object is not an EP despite being ready and positively held.
 mov rdi, rbx
 mov rsi, [rip + cl_base]
 call registry_add_ep
 cmp rax, -22
 jne cl_fail
 cmp qword ptr [rbx + RG_ninput], 0
 jne cl_fail
 test r13, r13
 jz 5f
 xor r12d, r12d
4: mov rdi, rbx
 lea rax, [rip + cl_eps]
 mov rsi, [rax + r12*8]
 call registry_add_ep
 test rax, rax
 jnz cl_fail
 test r12, r12
 jnz 21f
 mov r15, [rip + prep_total_charge]
 mov rdi, rbx
 mov rsi, [rip + cl_ep]
 call registry_add_ep
 cmp rax, -17
 jne cl_fail
 cmp qword ptr [rbx + RG_ninput], 1
 jne cl_fail
 cmp [rip + prep_total_charge], r15
 jne cl_fail
21: lea rax, [rip + cl_eps]
 mov rax, [rax + r12*8]
 cmp qword ptr [rax + PO_refs], 2
 jne cl_fail
 inc r12
 cmp r12, 128
 jb 4b
 mov r14, [rip + cl_ep]
 cmp qword ptr [r14 + PO_refs], 2
 jne cl_fail
 mov r15, [rip + prep_total_charge]
 mov rdi, rbx
 mov rsi, r14
 call registry_add_ep
 cmp rax, -EV_RESOURCE
 jne cl_fail
 cmp qword ptr [r14 + PO_refs], 2
 jne cl_fail
 cmp [rip + prep_total_charge], r15
 jne cl_fail
 cmp qword ptr [rbx + RG_ninput], 128
 jne cl_fail
5: mov rdi, rbx
 call registry_seal_inputs
 test rax, rax
 jnz cl_fail
 mov r12d, 10000
6: mov rdi, rbx
 mov esi, 65536
 call registry_step
 test r8, r8
 jnz cl_fail
 cmp r9, 16
 ja cl_fail
 test rax, rax
 js cl_fail
 jz 7f
 dec r12
 jnz 6b
 jmp cl_fail
7: mov r14, [rip + cl_ep]
 cmp qword ptr [r14 + PO_refs], 1
 jne cl_fail
 mov rdi, rbx
 call registry_view
 test rax, rax
 jz cl_fail
 cmp qword ptr [rax + 8], 8192
 jne cl_fail
 cmp qword ptr [rax + 32], 0
 jne cl_fail
 cmp qword ptr [rax + 56], 0
 jne cl_fail
 cmp qword ptr [rax + 64], -1
 jne cl_fail
 cmp qword ptr [rip + cl_large_tested], 0
 jne 31f
 call cl_large_refusal
 mov qword ptr [rip + cl_large_tested], 1
31:
 # Terminal calls must not inspect the now-unavailable input/map borrows.
 mov qword ptr [rbx + RG_grammar_map], 1
 mov qword ptr [rbx + RG_theme_map], 1
 mov rdi, rbx
 mov esi, 1
 call registry_step
 test rax, rax
 jnz cl_fail
 test r8, r8
 jnz cl_fail
 test r9, r9
 jnz cl_fail
 mov qword ptr [rbx + RG_grammar_map], 0
 mov qword ptr [rbx + RG_theme_map], 0
 mov rdi, rbx
 call registry_retain
 test rax, rax
 jnz cl_fail
 cmp qword ptr [rbx + PO_refs], 2
 jne cl_fail
 mov rdi, rbx
 call registry_release_deferred
 cmp rdx, 1
 jne cl_fail
 cmp qword ptr [rbx + PO_refs], 1
 jne cl_fail
 mov rdi, rbx
 call registry_release_deferred
 cmp rdx, 1
 jne cl_fail
 call cl_drain
 inc r13
 cmp r13, 2
 jb 3b
 mov qword ptr [rip + cl_stage], 3
 xor r12d, r12d
22: lea rax, [rip + cl_eps]
 mov rdi, [rax + r12*8]
 cmp qword ptr [rdi + PO_refs], 1
 jne cl_fail
 call ext_prepare_release_deferred
 cmp rdx, 1
 jne cl_fail
 inc r12
 cmp r12, 128
 jb 22b
 mov rdi, [rip + cl_base]
 call registry_base_release_deferred
 cmp rdx, 1
 jne cl_fail
 call cl_drain
 mov rax, [rip + prep_total_charge]
 cmp rax, [rip + cl_charge]
 jne cl_fail
 mov rax, [rip + g_mem_live]
 cmp rax, [rip + cl_live]
 jne cl_fail
 xor eax, eax
 EPILOGUE

# This fixture owns a READY registry while its scratch PO remains queued.
cl_large_refusal:
 PROLOGUE
 mov qword ptr [rip + cl_fail_unmap], 1
 mov r12d, 1000
1: mov rax, [rip + prep_total_charge]
 mov [rip + cl_before_charge], rax
 mov rax, [rip + g_mem_live]
 mov [rip + cl_before_live], rax
 mov edi, 1
 lea rsi, [rip + cl_report]
 call ext_prepare_retire_step
 test rax, rax
 js cl_fail
 cmp qword ptr [rip + cl_fail_unmap], 0
 je 2f
 dec r12
 jnz 1b
 jmp cl_fail
2: cmp qword ptr [rip + cl_report + 16], 1
 jne cl_fail
 mov rax, [rip + prep_total_charge]
 cmp rax, [rip + cl_before_charge]
 jne cl_fail
 mov rax, [rip + g_mem_live]
 cmp rax, [rip + cl_before_live]
 jne cl_fail
 mov rax, [rip + cl_failed_header]
 mov rdx, [rip + cl_failed_size]
 cmp [rax], rdx
 jne cl_fail
 mov rdx, [rip + cl_failed_request]
 cmp [rax + 8], rdx
 jne cl_fail
 mov rdx, [rip + prep_retire_blocked_head]
 test rdx, rdx
 jz cl_fail
 mov rdx, [rdx + RD_object]
 add rax, 16
 cmp [rdx + PO_allocs], rax
 jne cl_fail
 mov edi, 1
 call ext_prepare_retire_retry_known
 cmp rax, 1
 jne cl_fail
 call cl_drain
 # The separately retained final array remains usable after scratch collection.
 mov rdi, rbx
 call registry_view
 test rax, rax
 jz cl_fail
 mov rax, [rax]
 lea rdx, [rip + cl_gr]
 cmp [rax], rdx
 jne cl_fail
 cmp [rax + 8191*8], rdx
 jne cl_fail
 EPILOGUE
