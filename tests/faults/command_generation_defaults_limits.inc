.equ CFL_OK_LEN, 56
# Real128x64 suppliers. Separate four long real ROs exercise capacity saturation.
.bss
.p2align 3
cfl_slots: .quad 0
cfl_per_slot: .quad 0
cfl_spec: .quad 0
cfl_speclen: .quad 0
cfl_slot: .quad 0
cfl_row: .quad 0
cfl_faultphase: .quad 0
cfl_mapbase: .quad 0
cfl_mapheader: .quad 0
cfl_metahead: .quad 0
cfl_unmap_fault: .quad 0
cfl_unmap_calls: .quad 0
.text
FN cfl_native_unmap
    cmp rdi, [rip + cfl_mapbase]
    jne 1f
    inc qword ptr [rip + cfl_unmap_calls]
    cmp qword ptr [rip + cfl_unmap_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
cfl_inputs:
    PROLOGUE
    call cgbt_new
    mov rbx, rax
    mov [rip + cfd_cg], rax
    mov qword ptr [rip + cfl_slot], 0
.Lcfl_slot:
    lea rdi, [rip + cfd_owner]
    mov rax, [rip + cfl_slot]
    shl rax, 3
    lea rsi, [rip + cfl_names]
    add rsi, rax
    lea rdx, [rip + cfd_title]
    call cgbt_ep
    mov r12, rax
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    imul rdx, [rip + cfl_slot], EXT_SIZE
    lea rax, [rip + cgbt_exts]
    add rdx, rax
    mov rcx, [rip + cfl_slot]
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov qword ptr [rip + cfl_row], 0
.Lcfl_row:
    lea rdi, [rip + cgbt_roc]
    imul rax, [rip + cfl_slot], EXT_SIZE
    lea rcx, [rip + cgbt_exts]
    add rax, rcx
    mov [rdi + ROC_target], rax
    mov qword ptr [rdi + ROC_session], 99
    lea rax, [rip + cfd_owner]
    mov [rdi + ROC_owner], rax
    mov rax, [rip + cfl_slot]
    shl rax, 3
    lea rcx, [rip + cfl_names]
    add rax, rcx
    mov [rdi + ROC_name], rax
    mov rax, [rip + cfl_row]
    shl rax, 3
    lea rcx, [rip + cfl_keys]
    add rax, rcx
    mov [rdi + ROC_key], rax
    lea rax, [rip + cfd_title]
    mov [rdi + ROC_title], rax
    mov rax, [rip + cfl_spec]
    mov [rdi + ROC_keys], rax
    mov rax, [rip + cfl_speclen]
    mov [rdi + ROC_keyslen], rax
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    inc qword ptr [rip + cfl_row]
    mov rax, [rip + cfl_per_slot]
    cmp [rip + cfl_row], rax
    jb .Lcfl_row
    inc qword ptr [rip + cfl_slot]
    mov rax, [rip + cfl_slots]
    cmp [rip + cfl_slot], rax
    jb .Lcfl_slot
    lea rdi, [rip + cgbt_retire]
    call ext_prepare_retire_status
    mov rax, [rip + cgbt_retire + 8]
    or rax, [rip + cgbt_retire + 16]
    jnz cgbt_fail
    mov rax, rbx
    EPILOGUE
cfl_chain:
    PROLOGUE
    mov r12, rdi
    mov edi, '9'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    mov rbx, [rip + cfd_cg]
    cmp [rip + cfd_route + 24], r12
    jne cgbt_fail
    cmp [rbx + CG_defaultcount], r12
    jne cgbt_fail
    cmp qword ptr [rip + cfd_route + 32], 0
    jne cgbt_fail
    mov r13, [rbx + CG_commands + VEC_ptr]
    cmp [rip + cfd_route], r13
    jne cgbt_fail
    mov r14, [rip + cfd_route + 16]
    xor r15d, r15d
1:  cmp r15, r12
    jae 3f
    test r14, r14
    jz cgbt_fail
    cmp r14, r12
    ja cgbt_fail
    dec r14
    shl r14, 4
    add r14, [rip + cfd_route + 8]
    cmp [r14], r13
    jne cgbt_fail
    mov r14, [r14 + 8]
    add r13, CMD_SIZE
    inc r15
    jmp 1b
3:  test r14, r14
    jnz cgbt_fail
    EPILOGUE
# Step with budget1. Each new allocation ends this actual call, even at higher budgets.
cfl_step:
    PROLOGUE
    mov rdi, [rip + cfd_cg]
    lea rsi, [rip + cgbt_context]
    mov edx, 1
    call cgbt_observed_step
    cmp rdx, 1
    ja cgbt_fail
    EPILOGUE
cfl_no_runtime:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 15
    call cgbt_new
    mov rbx, rax
    mov [rip + cfd_cg], rax
    mov rdi, rax
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
1:  cmp qword ptr [rbx + CG_phase], 8
    je 2f
    call cfl_step
    cmp rax, 1
    jne cgbt_fail
    jmp 1b
2:  mov r12, [rip + cgbt_all_alloc_calls]
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 16
    call cgbt_observed_step
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    inc r12
    cmp [rip + cgbt_all_alloc_calls], r12
    jne cgbt_fail
    cmp qword ptr [rbx + CG_phase], 9
    jne cgbt_fail
3:  call cfl_step
    test rax, rax
    js cgbt_fail
    jnz 3b
    mov rax, [rbx + CG_defaultmeta]
    or rax, [rbx + CG_defaultnodes]
    or rax, [rbx + CG_defaultcapacity]
    or rax, [rbx + CG_defaultcount]
    jnz cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    call cfl_no_runtime
    mov qword ptr [rip + cgbt_stage], 10
    mov qword ptr [rip + cfl_slots], 128
    mov qword ptr [rip + cfl_per_slot], 64
    lea rax, [rip + cfd_spec3]
    mov [rip + cfl_spec], rax
    mov qword ptr [rip + cfl_speclen], 10
    call cfl_inputs
    cmp qword ptr [rax + CG_nruntimes], 8192
    jne cgbt_fail
    cmp qword ptr [rax + CG_defaultcapacity], 8192 * 11
    jne cgbt_fail
    mov rdi, rax
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov edi, 8192
    call cfl_chain
    mov rdi, [rip + cfd_cg]
    call cgbt_abort
    # Four65536-byte key specifications saturate the conservative node reserve.
    mov qword ptr [rip + cgbt_stage], 11
    lea rdi, [rip + cgbt_limit_bytes]
    mov esi, ' '
    mov edx, 65536
    call memset
    lea rdi, [rip + cgbt_limit_bytes + 65526]
    lea rsi, [rip + cfd_spec3]
    mov edx, 10
    call memcpy
    lea rax, [rip + cgbt_limit_bytes]
    mov [rip + cfl_spec], rax
    mov qword ptr [rip + cfl_speclen], 65536
    mov qword ptr [rip + cfl_slots], 1
    mov qword ptr [rip + cfl_per_slot], 4
    call cfl_inputs
    cmp qword ptr [rax + CG_defaultcapacity], CG_DEFAULT_NODE_CAP
    jne cgbt_fail
    mov rdi, rax
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov edi, 4
    call cfl_chain
    mov rdi, [rip + cfd_cg]
    call cgbt_abort
    # Fault each added allocation at its real phase. No other allocator is failed.
    lea rax, [rip + cfd_spec3]
    mov [rip + cfl_spec], rax
    mov qword ptr [rip + cfl_speclen], 10
    mov qword ptr [rip + cfl_per_slot], 1
    mov qword ptr [rip + cfl_faultphase], CG_DEFAULT_ALLOC_META
.Lcfl_fault:
    mov qword ptr [rip + cgbt_stage], 12
    call cfl_inputs
    mov rdi, rax
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
1:  mov rbx, [rip + cfd_cg]
    mov rax, [rip + cfl_faultphase]
    cmp [rbx + CG_phase], rax
    je 2f
    call cfl_step
    cmp rax, 1
    jne cgbt_fail
    jmp 1b
2:  mov qword ptr [rip + cgbt_alloc_calls], 0
    mov qword ptr [rip + cgbt_alloc_fault], 1
    call cfl_step
    test rax, rax
    jns cgbt_fail
    cmp qword ptr [rip + cgbt_alloc_calls], 1
    jne cgbt_fail
    mov qword ptr [rip + cgbt_alloc_fault], 0
    mov rbx, [rip + cfd_cg]
    cmp qword ptr [rbx + PO_ready], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_defaultnodes], 0
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    inc qword ptr [rip + cfl_faultphase]
    cmp qword ptr [rip + cfl_faultphase], CG_DEFAULT_ALLOC_NODES
    jbe .Lcfl_fault
    # Successful phases must each end the call even with the largest allowed budget.
    mov qword ptr [rip + cgbt_stage], 13
    call cfl_inputs
    mov rdi, rax
    call command_generation_seal
    test rax, rax
    jnz cgbt_fail
1:  mov rbx, [rip + cfd_cg]
    cmp qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_META
    je 2f
    call cfl_step
    cmp rax, 1
    jne cgbt_fail
    jmp 1b
2:  mov r12, [rip + cgbt_all_alloc_calls]
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 16
    call cgbt_observed_step
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    inc r12
    cmp [rip + cgbt_all_alloc_calls], r12
    jne cgbt_fail
    cmp qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_NODES
    jne cgbt_fail
    mov rdi, rbx
    lea rsi, [rip + cgbt_context]
    mov edx, 16
    call cgbt_observed_step
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    inc r12
    cmp [rip + cgbt_all_alloc_calls], r12
    jne cgbt_fail
    cmp qword ptr [rbx + CG_phase], 9
    jne cgbt_fail
3:  call cfl_step
    test rax, rax
    js cgbt_fail
    jnz 3b
    # Real metadata map refusal retains its exact ledger link, charge, and census.
    mov qword ptr [rip + cgbt_stage], 14
    mov rax, [rbx + CG_defaultmeta]
    mov rcx, [rax]
    mov [rip + cfl_metahead], rcx
    sub rax, AO_SIZE + 16
    mov [rip + cfl_mapbase], rax
    mov rcx, [rax]
    cmp rcx, 1024 * 1024
    jbe cgbt_fail
    mov [rip + cfl_mapheader], rcx
    mov qword ptr [rip + cfl_unmap_fault], 1
    mov rdi, rbx
    call command_generation_release_deferred
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    mov r15d, 10000
4:  mov r12, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov r13, rax
    mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cgbt_retire], 1
    ja cgbt_fail
    cmp qword ptr [rip + cfl_unmap_calls], 0
    jne 5f
    dec r15
    jnz 4b
    jmp cgbt_fail
5:  cmp qword ptr [rip + cfl_unmap_calls], 1
    jne cgbt_fail
    cmp [rip + g_mem_live], r12
    jne cgbt_fail
    call ext_prepare_retire_charge
    cmp rax, r13
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_retire + 16], 1
    jne cgbt_fail
    mov rax, [rip + cfl_mapbase]
    mov rcx, [rip + cfl_mapheader]
    cmp [rax], rcx
    jne cgbt_fail
    lea rcx, [rax + 16]
    cmp [rbx + PO_allocs], rcx
    jne cgbt_fail
    mov rcx, [rip + cfl_metahead]
    cmp [rax + 16 + AO_SIZE], rcx
    jne cgbt_fail
    mov r15d, 100
6:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cfl_unmap_calls], 1
    jne cgbt_fail
    dec r15
    jnz 6b
    mov qword ptr [rip + cfl_unmap_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    cmp qword ptr [rip + cfl_unmap_calls], 2
    jne cgbt_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz cgbt_fail
    mov edi, 1
    lea rsi, [rip + cfl_ok]
    mov edx, CFL_OK_LEN
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
cfl_ok: .ascii "ok maximum runtime default chains and allocation phases\n"
cfl_ok_end:

.p2align 3
cfl_names:
    .asciz "h000"
    .zero 3
    .asciz "h001"
    .zero 3
    .asciz "h002"
    .zero 3
    .asciz "h003"
    .zero 3
    .asciz "h004"
    .zero 3
    .asciz "h005"
    .zero 3
    .asciz "h006"
    .zero 3
    .asciz "h007"
    .zero 3
    .asciz "h008"
    .zero 3
    .asciz "h009"
    .zero 3
    .asciz "h010"
    .zero 3
    .asciz "h011"
    .zero 3
    .asciz "h012"
    .zero 3
    .asciz "h013"
    .zero 3
    .asciz "h014"
    .zero 3
    .asciz "h015"
    .zero 3
    .asciz "h016"
    .zero 3
    .asciz "h017"
    .zero 3
    .asciz "h018"
    .zero 3
    .asciz "h019"
    .zero 3
    .asciz "h020"
    .zero 3
    .asciz "h021"
    .zero 3
    .asciz "h022"
    .zero 3
    .asciz "h023"
    .zero 3
    .asciz "h024"
    .zero 3
    .asciz "h025"
    .zero 3
    .asciz "h026"
    .zero 3
    .asciz "h027"
    .zero 3
    .asciz "h028"
    .zero 3
    .asciz "h029"
    .zero 3
    .asciz "h030"
    .zero 3
    .asciz "h031"
    .zero 3
    .asciz "h032"
    .zero 3
    .asciz "h033"
    .zero 3
    .asciz "h034"
    .zero 3
    .asciz "h035"
    .zero 3
    .asciz "h036"
    .zero 3
    .asciz "h037"
    .zero 3
    .asciz "h038"
    .zero 3
    .asciz "h039"
    .zero 3
    .asciz "h040"
    .zero 3
    .asciz "h041"
    .zero 3
    .asciz "h042"
    .zero 3
    .asciz "h043"
    .zero 3
    .asciz "h044"
    .zero 3
    .asciz "h045"
    .zero 3
    .asciz "h046"
    .zero 3
    .asciz "h047"
    .zero 3
    .asciz "h048"
    .zero 3
    .asciz "h049"
    .zero 3
    .asciz "h050"
    .zero 3
    .asciz "h051"
    .zero 3
    .asciz "h052"
    .zero 3
    .asciz "h053"
    .zero 3
    .asciz "h054"
    .zero 3
    .asciz "h055"
    .zero 3
    .asciz "h056"
    .zero 3
    .asciz "h057"
    .zero 3
    .asciz "h058"
    .zero 3
    .asciz "h059"
    .zero 3
    .asciz "h060"
    .zero 3
    .asciz "h061"
    .zero 3
    .asciz "h062"
    .zero 3
    .asciz "h063"
    .zero 3
    .asciz "h064"
    .zero 3
    .asciz "h065"
    .zero 3
    .asciz "h066"
    .zero 3
    .asciz "h067"
    .zero 3
    .asciz "h068"
    .zero 3
    .asciz "h069"
    .zero 3
    .asciz "h070"
    .zero 3
    .asciz "h071"
    .zero 3
    .asciz "h072"
    .zero 3
    .asciz "h073"
    .zero 3
    .asciz "h074"
    .zero 3
    .asciz "h075"
    .zero 3
    .asciz "h076"
    .zero 3
    .asciz "h077"
    .zero 3
    .asciz "h078"
    .zero 3
    .asciz "h079"
    .zero 3
    .asciz "h080"
    .zero 3
    .asciz "h081"
    .zero 3
    .asciz "h082"
    .zero 3
    .asciz "h083"
    .zero 3
    .asciz "h084"
    .zero 3
    .asciz "h085"
    .zero 3
    .asciz "h086"
    .zero 3
    .asciz "h087"
    .zero 3
    .asciz "h088"
    .zero 3
    .asciz "h089"
    .zero 3
    .asciz "h090"
    .zero 3
    .asciz "h091"
    .zero 3
    .asciz "h092"
    .zero 3
    .asciz "h093"
    .zero 3
    .asciz "h094"
    .zero 3
    .asciz "h095"
    .zero 3
    .asciz "h096"
    .zero 3
    .asciz "h097"
    .zero 3
    .asciz "h098"
    .zero 3
    .asciz "h099"
    .zero 3
    .asciz "h100"
    .zero 3
    .asciz "h101"
    .zero 3
    .asciz "h102"
    .zero 3
    .asciz "h103"
    .zero 3
    .asciz "h104"
    .zero 3
    .asciz "h105"
    .zero 3
    .asciz "h106"
    .zero 3
    .asciz "h107"
    .zero 3
    .asciz "h108"
    .zero 3
    .asciz "h109"
    .zero 3
    .asciz "h110"
    .zero 3
    .asciz "h111"
    .zero 3
    .asciz "h112"
    .zero 3
    .asciz "h113"
    .zero 3
    .asciz "h114"
    .zero 3
    .asciz "h115"
    .zero 3
    .asciz "h116"
    .zero 3
    .asciz "h117"
    .zero 3
    .asciz "h118"
    .zero 3
    .asciz "h119"
    .zero 3
    .asciz "h120"
    .zero 3
    .asciz "h121"
    .zero 3
    .asciz "h122"
    .zero 3
    .asciz "h123"
    .zero 3
    .asciz "h124"
    .zero 3
    .asciz "h125"
    .zero 3
    .asciz "h126"
    .zero 3
    .asciz "h127"
    .zero 3
cfl_keys:
    .asciz "k00"
    .zero 4
    .asciz "k01"
    .zero 4
    .asciz "k02"
    .zero 4
    .asciz "k03"
    .zero 4
    .asciz "k04"
    .zero 4
    .asciz "k05"
    .zero 4
    .asciz "k06"
    .zero 4
    .asciz "k07"
    .zero 4
    .asciz "k08"
    .zero 4
    .asciz "k09"
    .zero 4
    .asciz "k10"
    .zero 4
    .asciz "k11"
    .zero 4
    .asciz "k12"
    .zero 4
    .asciz "k13"
    .zero 4
    .asciz "k14"
    .zero 4
    .asciz "k15"
    .zero 4
    .asciz "k16"
    .zero 4
    .asciz "k17"
    .zero 4
    .asciz "k18"
    .zero 4
    .asciz "k19"
    .zero 4
    .asciz "k20"
    .zero 4
    .asciz "k21"
    .zero 4
    .asciz "k22"
    .zero 4
    .asciz "k23"
    .zero 4
    .asciz "k24"
    .zero 4
    .asciz "k25"
    .zero 4
    .asciz "k26"
    .zero 4
    .asciz "k27"
    .zero 4
    .asciz "k28"
    .zero 4
    .asciz "k29"
    .zero 4
    .asciz "k30"
    .zero 4
    .asciz "k31"
    .zero 4
    .asciz "k32"
    .zero 4
    .asciz "k33"
    .zero 4
    .asciz "k34"
    .zero 4
    .asciz "k35"
    .zero 4
    .asciz "k36"
    .zero 4
    .asciz "k37"
    .zero 4
    .asciz "k38"
    .zero 4
    .asciz "k39"
    .zero 4
    .asciz "k40"
    .zero 4
    .asciz "k41"
    .zero 4
    .asciz "k42"
    .zero 4
    .asciz "k43"
    .zero 4
    .asciz "k44"
    .zero 4
    .asciz "k45"
    .zero 4
    .asciz "k46"
    .zero 4
    .asciz "k47"
    .zero 4
    .asciz "k48"
    .zero 4
    .asciz "k49"
    .zero 4
    .asciz "k50"
    .zero 4
    .asciz "k51"
    .zero 4
    .asciz "k52"
    .zero 4
    .asciz "k53"
    .zero 4
    .asciz "k54"
    .zero 4
    .asciz "k55"
    .zero 4
    .asciz "k56"
    .zero 4
    .asciz "k57"
    .zero 4
    .asciz "k58"
    .zero 4
    .asciz "k59"
    .zero 4
    .asciz "k60"
    .zero 4
    .asciz "k61"
    .zero 4
    .asciz "k62"
    .zero 4
    .asciz "k63"
    .zero 4

