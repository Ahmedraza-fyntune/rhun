# Exact constructor/admission refusal and retained caller ownership.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.equ CL_FAULT, 0
.section .rodata
cl_dir: .asciz "/registry/empty"
cl_owner: .asciz "fixture"
cl_name: .asciz "empty"
cl_input: .quad 0,0,0,0,0,-1,83,0
.bss
.p2align 3
cl_stage: .quad 0
cl_live: .quad 0
cl_charge: .quad 0
cl_base: .quad 0
cl_ep: .quad 0
cl_eps: .zero 128*8
cl_rg: .quad 0
cl_alloc_calls: .quad 0
cl_eo_target: .quad 0
cl_eo_armed: .quad 0
cl_report: .zero 32
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
 .if CL_FAULT >= 4
 mov r13d, 1
 .endif
3:
 .if CL_FAULT == 7
 lea rdi, [rip + cl_input]
 call registry_base_begin
 .else
 mov rdi, [rip + cl_base]
 mov rsi, r13
 add rsi, 91
 call registry_begin
 .endif
 .if CL_FAULT == 6
 test rax, rax
 jz cl_fail
 cmp rdx, -5
 jne cl_fail
 mov rbx, rax
 cmp qword ptr [rbx + PO_error], -5
 jne cl_fail
 mov rax, [rbx + PO_eo]
 cmp [rbx + RG_constructor_eo], rax
 jne cl_fail
 cmp [rip + cl_eo_target], rax
 jne cl_fail
 cmp qword ptr [rax + EO_refs], 2
 jne cl_fail
 cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
 jne cl_fail
 mov rdi, rbx
 call registry_status
 cmp rax, RG_FAILED
 jne cl_fail
 cmp rdx, -5
 jne cl_fail
 test r8, r8
 jnz cl_fail
 mov rdi, rbx
 call registry_view
 test rax, rax
 jnz cl_fail
 jmp cl_release_failed
 .endif
 .if CL_FAULT == 7
 test rax, rax
 jz cl_fail
 cmp rdx, -5
 jne cl_fail
 mov rbx, rax
 cmp qword ptr [rbx + PO_error], -5
 jne cl_fail
 mov rax, [rbx + PO_eo]
 cmp [rbx + RB_constructor_eo], rax
 jne cl_fail
 cmp [rip + cl_eo_target], rax
 jne cl_fail
 cmp qword ptr [rax + EO_refs], 2
 jne cl_fail
 cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
 jne cl_fail
 mov rdi, rbx
 call registry_base_status
 cmp rax, RB_FAILED
 jne cl_fail
 cmp rdx, -5
 jne cl_fail
 test r8, r8
 jnz cl_fail
 mov rdi, rbx
 call registry_base_view
 test rax, rax
 jnz cl_fail
 mov rdi, rbx
 call registry_base_release_deferred
 cmp rdx, 1
 jne cl_fail
 jmp cl_constructor_refused
 .endif
 .if CL_FAULT == 1
 test rax, rax
 jnz cl_fail
 cmp rdx, -12
 jne cl_fail
 jmp cl_constructor_refused
 .endif
 .if CL_FAULT == 2
 test rax, rax
 jnz cl_fail
 cmp rdx, -12
 jne cl_fail
 jmp cl_constructor_refused
 .endif
 .if CL_FAULT == 3
 test rax, rax
 jz cl_fail
 cmp rdx, -75
 jne cl_fail
 mov rbx, rax
 cmp qword ptr [rbx + PO_error], -75
 jne cl_fail
 cmp qword ptr [rbx + RG_base], 0
 jne cl_fail
 jmp cl_release_failed
 .endif
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
 .if CL_FAULT == 4
 cmp rax, -12
 jne cl_fail
 cmp qword ptr [rbx + PO_error], -12
 jne cl_fail
 jmp cl_admission_refused
 .endif
 .if CL_FAULT == 5
 cmp rax, -75
 jne cl_fail
 cmp qword ptr [rbx + PO_error], 0
 jne cl_fail
 jmp cl_admission_refused
 .endif
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
 cmp qword ptr [rax + 8], 0
 jne cl_fail
 cmp qword ptr [rax + 32], 0
 jne cl_fail
 cmp qword ptr [rax + 56], 0
 jne cl_fail
 cmp qword ptr [rax + 64], -1
 jne cl_fail
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
cl_fault_cleanup:
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

cl_admission_refused:
 cmp qword ptr [rbx + RG_ninput], 0
 jne cl_fail
 mov rax, [rip + cl_ep]
 cmp qword ptr [rax + PO_refs], 1
 jne cl_fail
cl_release_failed:
 mov rdi, rbx
 call registry_release_deferred
 cmp rdx, 1
 jne cl_fail
cl_constructor_refused:
 mov rax, [rip + cl_ep]
 cmp qword ptr [rax + PO_refs], 1
 jne cl_fail
 call cl_drain
 mov rax, [rip + cl_base]
 cmp qword ptr [rax + PO_refs], 1
 jne cl_fail
 jmp cl_fault_cleanup
 .if CL_FAULT == 1
FN mem_alloc_try
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_mem_alloc_try
 inc qword ptr [rip + cl_alloc_calls]
 cmp qword ptr [rip + cl_alloc_calls], 1
 jne cl_actual_mem_alloc_try
 xor eax, eax
 ret
 .endif
 .if CL_FAULT == 2
FN mem_alloc_try
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_mem_alloc_try
 inc qword ptr [rip + cl_alloc_calls]
 cmp qword ptr [rip + cl_alloc_calls], 2
 jne cl_actual_mem_alloc_try
 xor eax, eax
 ret
 .endif
 .if CL_FAULT == 4
FN mem_alloc_try
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_mem_alloc_try
 cmp rdi, REG_EP_CAP * RGS_SIZE + AO_SIZE
 jne cl_actual_mem_alloc_try
 xor eax, eax
 ret
 .endif
 .if CL_FAULT == 3
FN registry_base_retain
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_registry_base_retain
 mov rax, -75
 ret
 .endif
 .if CL_FAULT == 5
FN ext_prepare_retain
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_ext_prepare_retain
 mov rax, -75
 ret
 .endif

 .if CL_FAULT >= 6
FN ext_prepare_owner_release_deferred
 cmp qword ptr [rip + cl_stage], 2
 jne cl_actual_ext_prepare_owner_release_deferred
 cmp qword ptr [rdi + EO_refs], 2
 jne cl_actual_ext_prepare_owner_release_deferred
 cmp qword ptr [rip + cl_eo_armed], 0
 jne cl_actual_ext_prepare_owner_release_deferred
 mov qword ptr [rip + cl_eo_armed], 1
 mov [rip + cl_eo_target], rdi
 mov rax, -5
 xor edx, edx
 ret
 .endif
