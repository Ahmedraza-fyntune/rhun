# Actual bounded base owner, source independence, scratch charge and lazy builtin.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.section .rodata
cbase_follow_id: .asciz "follow"
cbase_follow_name: .asciz "Follow"
cbase_builtin_id: .asciz "rhun-dark"
cbase_builtin_name: .asciz "Builtin"
cbase_user_id: .asciz "user"
cbase_user_name: .asciz "User header"
cbase_raw_path: .asciz "themes/relative.theme"
cbase_source: .ascii "name = Builtin\nkind = dark\n"
cbase_source_end:
cbase_grammar_source: .ascii "name = Lazy builtin\nfiles = *.lazy\n"
cbase_grammar_source_end:
cbase_grammar_length: .quad cbase_grammar_source_end-cbase_grammar_source
cbase_first: .asciz "first"
cbase_second: .asciz "second"
cbase_lazy: .asciz "unparsed"
.data
.p2align 3
cbase_grptrs: .quad cbase_gr1, cbase_gr2, cbase_gr3
cbase_many: .zero 800
cbase_themes:
    .quad cbase_follow_id, cbase_follow_name
    .long 1,0
    .quad 0,0,0,0
    .quad cbase_builtin_id, cbase_builtin_name
    .long 1,0
    .quad cbase_source,cbase_source_end-cbase_source,0,0
    .quad cbase_user_id, cbase_user_name
    .long 1,0
    .quad 0,0,cbase_raw_path,0
cbase_input: .quad cbase_grptrs,3,2,cbase_themes,3,0,19,0
.bss
.p2align 3
cbase_gr1: .zero GR_SIZE
cbase_gr2: .zero GR_SIZE
cbase_gr3: .zero GR_SIZE
cbase_stage: .quad 0
cbase_charge: .quad 0
cbase_live: .quad 0
cbase_before_charge: .quad 0
cbase_before_used: .quad 0
cbase_report: .zero 32
cbase_object: .quad 0
cbase_output_length: .quad 0
cbase_long_name: .zero 8193
.text
cbase_fail:
    mov rdi, [rip + cbase_stage]
    add rdi, 40
    call sys_exit
    ud2
cbase_drain:
    PROLOGUE
    mov r12d, 1000
1:  mov edi, 1
    lea rsi, [rip + cbase_report]
    call ext_prepare_retire_step
    test rax, rax
    js cbase_fail
    cmp qword ptr [rip + cbase_report], 1
    ja cbase_fail
    cmp qword ptr [rip + cbase_report + 16], 0
    jne cbase_fail
    test rax, rax
    jz 2f
    dec r12
    jnz 1b
    jmp cbase_fail
2:  call ext_prepare_retire_charge
    cmp rax, [rip + cbase_charge]
    jne cbase_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cbase_live]
    jne cbase_fail
    EPILOGUE

# mode0 ready;1 cancel before qualification;2 held Small;3 allocated ledger copy.
cbase_capture:
    PROLOGUE
    mov r13, rdi
    lea rdi, [rip + cbase_input]
    call registry_base_begin
    test rax, rax
    jz cbase_fail
    test rdx, rdx
    jnz cbase_fail
    mov rbx, rax
    mov r12d, 100000
1:  mov rdi, rbx
    lea rsi, [rip + cbase_input]
    mov edx, 1
    call registry_base_step
    cmp r8, 1
    ja cbase_fail
    cmp r9, REG_STEP_UNITS
    ja cbase_fail
    test rax, rax
    js cbase_fail
    jz .Lcbase_captured
    cmp r13, 3
    jne 2f
    cmp qword ptr [rbx + RB_phase], RB_COPY_QUALIFIED
    jne 2f
    cmp qword ptr [rbx + RB_subphase], 3
    je .Lcbase_captured
2:  cmp qword ptr [rbx + RB_phase], RB_NEEDS_QUALIFY
    jne 5f
    cmp r13, 1
    je .Lcbase_captured
    call ext_prepare_retire_charge
    mov [rip + cbase_before_charge], rax
    mov rax, [rbx + PO_eo]
    mov rax, [rax + EO_used]
    mov [rip + cbase_before_used], rax
    mov rdi, rbx
    lea rsi, [rip + cbase_input]
    call registry_base_qualify_one
    test rax, rax
    jnz cbase_fail
    test rdx, rdx
    jnz cbase_fail
    cmp qword ptr [rbx + RB_reservation], 0
    jne cbase_fail
    mov rdi, [rbx + RB_scratch]
    test rdi, rdi
    jz cbase_fail
    call prep_pointer_charge
    mov r14, rax
    cmp [rbx + RB_scratch_charge], rax
    jne cbase_fail
    call ext_prepare_retire_charge
    sub rax, [rip + cbase_before_charge]
    cmp rax, r14
    jne cbase_fail
    mov rax, [rbx + PO_eo]
    mov rax, [rax + EO_used]
    sub rax, [rip + cbase_before_used]
    cmp rax, r14
    jne cbase_fail
    cmp r13, 2
    je .Lcbase_captured
5:  dec r12
    jnz 1b
    jmp cbase_fail
.Lcbase_captured:
    mov rax, rbx
    EPILOGUE
FN main
    PROLOGUE
    call ext_prepare_retire_charge
    mov [rip + cbase_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + cbase_live], rax
    lea rax, [rip + cbase_first]
    mov [rip + cbase_gr1 + GR_name], rax
    lea rax, [rip + cbase_second]
    mov [rip + cbase_gr2 + GR_name], rax
    lea rax, [rip + cbase_lazy]
    mov [rip + cbase_gr3 + GR_name], rax
    lea rax, [rip + cbase_grammar_source]
    mov [rip + cbase_gr3 + GR_src], rax
    mov rax, [rip + cbase_grammar_length]
    mov qword ptr [rip + cbase_gr3 + GR_srclen], rax
    lea rdi, [rip + cbase_long_name]
    mov esi, 'x'
    mov edx, 8192
    call memset
    lea rax, [rip + cbase_long_name]
    mov [rip + cbase_themes + 2*TH_SIZE + TH_name], rax
    mov qword ptr [rip + cbase_stage], 1
    call catalog_kind7_init
    test rax, rax
    jnz cbase_fail
    call theme_capture_startup_begin
    test rax, rax
    jnz cbase_fail
    lea rdi, [rip + cbase_input]
    call registry_base_begin
    test rax, rax
    jz cbase_fail
    mov rbx, rax
    inc qword ptr [rip + cbase_input + RBI_version]
    mov rdi, rbx
    lea rsi, [rip + cbase_input]
    mov edx, 1
    call registry_base_step
    cmp rax, -116
    jne cbase_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call registry_base_step
    cmp rax, -116
    jne cbase_fail
    test r8, r8
    jnz cbase_fail
    test r9, r9
    jnz cbase_fail
    dec qword ptr [rip + cbase_input + RBI_version]
    mov rdi, rbx
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    mov qword ptr [rip + cbase_stage], 20
    lea rdi, [rip + cbase_many]
    lea rax, [rip + cbase_gr1]
    mov ecx, 100
.Lcbase_many_init:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .Lcbase_many_init
    lea rax, [rip + cbase_many]
    mov [rip + cbase_input + RBI_grammars], rax
    mov qword ptr [rip + cbase_input + RBI_ngrammar], 100
    mov qword ptr [rip + cbase_input + RBI_nuser], 100
    mov qword ptr [rip + cbase_input + RBI_ntheme], 0
    mov qword ptr [rip + cbase_input + RBI_follow], -1
    xor edi, edi
    call cbase_capture
    mov rbx, rax
    mov rdi, rbx
    call registry_base_view
    cmp qword ptr [rax + 8], 100
    jne cbase_fail
    mov rax, [rax]
    lea rcx, [rip + cbase_gr1]
    cmp [rax + 99*8], rcx
    jne cbase_fail
    mov rdi, rbx
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    lea rax, [rip + cbase_grptrs]
    mov [rip + cbase_input + RBI_grammars], rax
    mov qword ptr [rip + cbase_input + RBI_ngrammar], 3
    mov qword ptr [rip + cbase_input + RBI_nuser], 2
    mov qword ptr [rip + cbase_input + RBI_ntheme], 3
    mov qword ptr [rip + cbase_input + RBI_follow], 0
    mov qword ptr [rip + cbase_stage], 2
    mov edi, 1
    call cbase_capture
    mov rdi, rax
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    mov qword ptr [rip + cbase_stage], 3
    mov edi, 2
    call cbase_capture
    mov rdi, rax
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    mov qword ptr [rip + cbase_stage], 4
    mov edi, 3
    call cbase_capture
    mov rdi, rax
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    mov qword ptr [rip + cbase_stage], 5
    xor edi, edi
    call cbase_capture
    mov rbx, rax
    mov [rip + cbase_object], rax
    mov rdi, rbx
    call registry_base_view
    test rax, rax
    jz cbase_fail
    mov r12, rax
    cmp qword ptr [r12 + 8], 2
    jne cbase_fail
    cmp qword ptr [r12 + 24], 1
    jne cbase_fail
    cmp qword ptr [r12 + 40], 3
    jne cbase_fail
    cmp qword ptr [r12 + 56], 0
    jne cbase_fail
    cmp qword ptr [r12 + 64], 19
    jne cbase_fail
    mov rax, [r12]
    lea rcx, [rip + cbase_gr1]
    cmp [rax], rcx
    jne cbase_fail
    lea rcx, [rip + cbase_gr2]
    cmp [rax + 8], rcx
    jne cbase_fail
    mov rax, [r12 + 16]
    lea rcx, [rip + cbase_gr3]
    cmp [rax], rcx
    jne cbase_fail
    mov r13, [r12 + 48]
    cmp qword ptr [r13 + BTM_kind], REG_FOLLOW
    jne cbase_fail
    cmp qword ptr [r13 + BTM_SIZE + BTM_kind], REG_BUILTIN
    jne cbase_fail
    add r13, 2*BTM_SIZE
    cmp qword ptr [r13 + BTM_kind], REG_USER
    jne cbase_fail
    cmp qword ptr [r13 + BTM_namelen], 8192
    jne cbase_fail
    mov rax, [r12 + 32]
    mov rax, [rax + 2*TH_SIZE + TH_name]
    lea rcx, [rip + cbase_long_name]
    cmp rax, rcx
    je cbase_fail
    cmp byte ptr [rax], 'x'
    jne cbase_fail
    cmp byte ptr [rax + 8191], 'x'
    jne cbase_fail
    cmp byte ptr [rax + 8192], 0
    jne cbase_fail
    mov rdi, [r13 + BTM_key]
    lea rsi, [rip + cbase_raw_path]
    cmp rdi, rsi
    je cbase_fail
    call strcmp_eq
    test eax, eax
    jz cbase_fail
    mov r14, [r13 + BTM_path]
    test r14, r14
    jz cbase_fail
    mov rax, [r13 + BTM_pathlen]
    mov [rip + cbase_output_length], rax
    mov qword ptr [rip + cbase_themes + 2*TH_SIZE + TH_path], 1
    mov qword ptr [rip + cbase_themes + 2*TH_SIZE + TH_name], 1
    mov qword ptr [rip + cbase_grptrs], 1
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call registry_base_step
    test rax, rax
    jnz cbase_fail
    test r8, r8
    jnz cbase_fail
    test r9, r9
    jnz cbase_fail
    call theme_capture_startup_seal
    test rax, rax
    jnz cbase_fail
    mov r15, [rip + g_mem_live]
    lea rdi, [rip + cbase_gr3]
    call syntax_ready
    cmp qword ptr [rip + cbase_gr3 + GR_src], 0
    jne cbase_fail
    mov rax, [rip + g_mem_live]
    sub rax, r15
    add [rip + cbase_live], rax
    mov edi, 1
    lea rsi, [rip + cbase_output_length]
    mov edx, 8
    call write_all
    mov edi, 1
    mov rsi, r14
    mov rdx, [rip + cbase_output_length]
    call write_all
    mov rdi, rbx
    call registry_base_release_deferred
    cmp rdx, 1
    jne cbase_fail
    call cbase_drain
    xor eax, eax
    EPILOGUE
