# Bounded immutable command rows and exact routing tables. No live registry inputs.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntime.inc"
.include "app/keycombo.inc"
.include "app/commandgeneration.inc"
.equ CGB_ROW, 9
.equ CGB_SCAN, 10
.equ CGB_TITLE_SCAN, 11
.equ CGB_TITLE_ALLOC, 12
.equ CGB_TITLE_RAW, 13
.equ CGB_TITLE_LABEL, 14
.equ CGB_HASH_INIT, 15
.equ CGB_HASH_DATA, 16
.equ CGB_HASH_FINAL, 17
.equ CGB_MAP_BEGIN, 18
.equ CGB_MAP_PROBE, 19
.equ CGB_MAP_EQUAL, 20
.equ CGB_DEFAULT_BEGIN, 21
.text
# CG -> current CMD, metadata, authority. All buffers have their final address.
FN cg_row_addresses
    mov rax, [rdi + CG_row]
    mov rdx, rax
    shl rax, 5
    add rax, [rdi + CG_commands + VEC_ptr]
    shl rdx, 6
    mov rcx, rdx
    add rdx, [rdi + CG_metadata]
    add rcx, [rdi + CG_authority + VEC_ptr]
    ret

# CG -> 0 continuation, 1 allocation ends call, or negative primary.
FN cg_build_one
    PROLOGUE 32
    mov rbx, rdi
    mov rax, [rbx + CG_phase]
    cmp rax, CG_DEFAULT_ALLOC_META
    je .Lcgb_default_allocate
    cmp rax, CG_DEFAULT_ALLOC_NODES
    je .Lcgb_default_allocate
    cmp rax, 8
    jbe .Lcgb_allocate
    cmp rax, CGB_ROW
    je .Lcgb_row
    cmp rax, CGB_SCAN
    je .Lcgb_scan
    cmp rax, CGB_TITLE_SCAN
    je .Lcgb_title_scan
    cmp rax, CGB_TITLE_ALLOC
    je .Lcgb_title_alloc
    cmp rax, CGB_TITLE_RAW
    je .Lcgb_title_raw
    cmp rax, CGB_TITLE_LABEL
    je .Lcgb_title_label
    cmp rax, CGB_HASH_INIT
    je .Lcgb_hash_init
    cmp rax, CGB_HASH_DATA
    je .Lcgb_hash_data
    cmp rax, CGB_HASH_FINAL
    je .Lcgb_hash_final
    cmp rax, CGB_MAP_BEGIN
    je .Lcgb_map_begin
    cmp rax, CGB_MAP_PROBE
    je .Lcgb_map_probe
    cmp rax, CGB_MAP_EQUAL
    je .Lcgb_map_equal
    mov rdi, rbx
    call cg_bindings_one
    EPILOGUE
 .Lcgb_default_allocate:
    mov rdi, rbx
    call cg_defaults_allocate
    EPILOGUE
.Lcgb_allocate:
    # Array allocation itself ends this step call, including zero-sized skips.
    mov r12, rax
    mov r13, [rbx + CG_ncommands]
    cmp r12, 1
    jne 2f
    mov ecx, 1
1:  lea rax, [r13 + r13]
    cmp rcx, rax
    jae 3f
    shl rcx, 1
    jmp 1b
3:  mov [rbx + CG_routecap], rcx
2:  lea r14, [rbx + CG_commands]
    mov esi, 32
    cmp r12, 1
    je .Lcgb_alloc_vec
    lea r14, [rbx + CG_owners]
    mov esi, 8
    cmp r12, 2
    je .Lcgb_alloc_vec
    lea r14, [rbx + CG_authority]
    mov esi, 64
    cmp r12, 3
    je .Lcgb_alloc_vec
    lea r14, [rbx + CG_metadata]
    cmp r12, 4
    je .Lcgb_alloc_raw_commands
    mov r13, [rbx + CG_routecap]
    lea r14, [rbx + CG_qualified]
    mov esi, 24
    cmp r12, 5
    je .Lcgb_alloc_raw_commands
    lea r14, [rbx + CG_owned]
    cmp r12, 6
    je .Lcgb_alloc_raw_commands
    mov r13d, CG_BINDING_CAP
    lea r14, [rbx + CG_bindings]
    mov esi, 16
    cmp r12, 7
    je .Lcgb_alloc_vec
    lea r14, [rbx + CG_bindingmap]
    mov r13d, CG_BINDING_MAP_CAP
    jmp .Lcgb_alloc_raw_commands
.Lcgb_alloc_vec:
    mov [r14 + VEC_cap], r13
    mov [r14 + VEC_len], r13
    cmp r12, 7
    jne .Lcgb_alloc_raw_commands
    mov qword ptr [r14 + VEC_len], 0
.Lcgb_alloc_raw_commands:
    imul rsi, r13
    test rsi, rsi
    jz .Lcgb_alloc_next
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lcgb_alloc_error
    mov [r14], rax
.Lcgb_alloc_next:
    inc qword ptr [rbx + CG_phase]
    cmp qword ptr [rbx + CG_phase], CGB_ROW
    jne .Lcgb_alloc_end
    cmp qword ptr [rbx + CG_nruntimes], 0
    je .Lcgb_alloc_end
    mov qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_META
.Lcgb_alloc_end:
    mov eax, 1
    EPILOGUE
.Lcgb_alloc_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lcgb_row:
    mov r12, [rbx + CG_row]
    cmp r12, [rbx + CG_ncommands]
    jae .Lcgb_rows_done
    cmp r12, [rbx + CG_nmanifest]
    jae .Lcgb_runtime_row
    mov r13, [rbx + CG_slot]
    cmp r13, [rbx + CG_nslots]
    jae .Lcgb_invalid
    imul r14, r13, CS_SIZE
    lea r14, [rbx + r14 + CG_slots]
    mov r15, [rbx + CG_runtime]
    cmp r15, [r14 + CS_count]
    jae .Lcgb_slot_next
    mov rax, [r14 + CS_ep]
    test rax, rax
    jz .Lcgb_invalid
    imul r15, r15, PC_SIZE
    add r15, [rax + EP_commands + VEC_ptr]
    mov rdi, rbx
    call cg_row_addresses
    mov r8, [r15 + CMD_name]
    mov [rax + CMD_name], r8
    mov r8, [r15 + CMD_title]
    mov [rax + CMD_title], r8
    lea r8, [rip + ext_cmd_run]
    mov [rax + CMD_fn], r8
    mov r8, [r15 + CMD_keys]
    mov [rax + CMD_keys], r8
    mov qword ptr [rcx], 0
    mov r8, [r14 + CS_ep]
    mov [rcx + 8], r8
    mov r8, [r15 + PC_key]
    mov [rcx + 40], r8
    mov qword ptr [rcx + 48], 0
    mov qword ptr [rcx + 56], 0
    jmp .Lcgb_row_common
.Lcgb_slot_next:
    inc qword ptr [rbx + CG_slot]
    mov qword ptr [rbx + CG_runtime], 0
    jmp .Lcgb_continue
.Lcgb_runtime_row:
    sub r12, [rbx + CG_nmanifest]
    shl r12, 4
    lea r12, [rbx + r12 + CG_runtimes]
    mov r15, [r12]
    cmp qword ptr [r15 + RO_live], 1
    jne .Lcgb_stale
    cmp qword ptr [r15 + RO_session], 0
    jle .Lcgb_stale
    cmp qword ptr [r15 + RO_incarnation], 0
    jle .Lcgb_stale
    mov r13, [r12 + 8]
    imul r14, r13, CS_SIZE
    lea r14, [rbx + r14 + CG_slots]
    mov rdi, rbx
    call cg_row_addresses
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov qword ptr [rcx], 1
    mov [rcx + 8], r15
    mov r8, [r15 + RO_session]
    mov [rcx + 48], r8
    mov r8, [r15 + RO_incarnation]
    mov [rcx + 56], r8
    mov rdi, r15
    mov esi, 5
    call ext_runtime_get
    mov rcx, [rsp]
    mov [rcx + CMD_name], rax
    lea rax, [rip + ext_cmd_run]
    mov [rcx + CMD_fn], rax
    mov rdi, r15
    mov esi, 4
    call ext_runtime_get
    mov rcx, [rsp]
    mov [rcx + CMD_keys], rax
    mov rdi, r15
    mov esi, 2
    call ext_runtime_get
    mov rcx, [rsp + 16]
    mov [rcx + 40], rax
    mov rdx, [rsp + 8]
    mov rax, [rsp]
.Lcgb_row_common:
    mov [rdx + CM_slot], r13
    mov r8, [r14 + CS_target]
    mov [rcx + 16], r8
    mov r8, [r14 + CS_owner]
    mov [rcx + 24], r8
    mov r8, [r14 + CS_name]
    mov [rcx + 32], r8
    mov r8, [r14 + CS_ordinal]
    mov r9, [rbx + CG_owners + VEC_ptr]
    mov r10, [rbx + CG_row]
    mov [r9 + r10*8], r8
    cmp qword ptr [rcx], 1
    je .Lcgb_runtime_lengths
    mov r8, [rax + CMD_name]
    mov [rbx + CG_source], r8
    mov qword ptr [rbx + CG_scanfield], 0
    mov qword ptr [rbx + CG_scanoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_SCAN
    jmp .Lcgb_continue
.Lcgb_runtime_lengths:
    mov r8, [r15 + RO_namelen]
    add r8, [r15 + RO_keylen]
    inc r8
    mov [rdx + CM_wirelen], r8
    mov r8, [r15 + RO_keylen]
    mov [rdx + CM_keylen], r8
    mov r8, [r15 + RO_keyslen]
    mov [rdx + CM_keyslen], r8
    mov r8, [r14 + CS_ep]
    mov r8, [r8 + EP_ext + EXT_title]
    test r8, r8
    jnz 1f
    mov r8, [r14 + CS_name]
1:  mov [rbx + CG_label], r8
    mov qword ptr [rbx + CG_scanoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_TITLE_SCAN
    jmp .Lcgb_continue
.Lcgb_scan:
    mov r12, [rbx + CG_source]
    test r12, r12
    jz .Lcgb_invalid
    mov r13, [rbx + CG_scanoffset]
    xor r14d, r14d
1:  cmp r13, CG_STRING_CAP
    ja .Lcgb_resource
    cmp byte ptr [r12 + r13], 0
    je .Lcgb_scan_end
    inc r13
    inc r14
    cmp r14, 4096
    jb 1b
    mov [rbx + CG_scanoffset], r13
    jmp .Lcgb_continue
.Lcgb_scan_end:
    mov rdi, rbx
    call cg_row_addresses
    mov r8, [rbx + CG_scanfield]
    mov [rdx + r8*8], r13
    inc r8
    cmp r8, 3
    je .Lcgb_row_hashed_start
    mov [rbx + CG_scanfield], r8
    mov qword ptr [rbx + CG_scanoffset], 0
    mov r12, [rcx + 40]
    cmp r8, 1
    je 1f
    mov r12, [rax + CMD_keys]
1:  mov [rbx + CG_source], r12
    jmp .Lcgb_continue
.Lcgb_title_scan:
    mov r12, [rbx + CG_label]
    mov r13, [rbx + CG_scanoffset]
    xor r14d, r14d
1:  cmp r13, CG_STRING_CAP
    ja .Lcgb_resource
    cmp byte ptr [r12 + r13], 0
    je 2f
    inc r13
    inc r14
    cmp r14, 4096
    jb 1b
    mov [rbx + CG_scanoffset], r13
    jmp .Lcgb_continue
2:  mov [rbx + CG_labellen], r13
    mov qword ptr [rbx + CG_phase], CGB_TITLE_ALLOC
    jmp .Lcgb_continue
.Lcgb_title_alloc:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rcx + 8]
    mov rsi, [r12 + RO_titlelen]
    add rsi, [rbx + CG_labellen]
    add rsi, 4
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lcgb_alloc_error
    mov [rbx + CG_title], rax
    mov qword ptr [rbx + CG_titleoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_TITLE_RAW
    mov eax, 1
    EPILOGUE
.Lcgb_title_raw:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rcx + 8]
    mov rdi, r12
    mov esi, 3
    call ext_runtime_get
    mov r13, [rbx + CG_titleoffset]
    mov r14, [r12 + RO_titlelen]
    sub r14, r13
    mov edx, 4096
    cmp r14, rdx
    cmovb rdx, r14
    mov r14, rdx
    lea rsi, [rax + r13]
    mov rdi, [rbx + CG_title]
    add rdi, r13
    call memcpy
    add r13, r14
    mov [rbx + CG_titleoffset], r13
    cmp r13, [r12 + RO_titlelen]
    jb .Lcgb_continue
    mov rdi, [rbx + CG_title]
    mov byte ptr [rdi + r13], ' '
    mov byte ptr [rdi + r13 + 1], '('
    mov qword ptr [rbx + CG_titleoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_TITLE_LABEL
    jmp .Lcgb_continue
.Lcgb_title_label:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rcx + 8]
    mov r13, [rbx + CG_titleoffset]
    mov r14, [rbx + CG_labellen]
    sub r14, r13
    mov edx, 4096
    cmp r14, rdx
    cmovb rdx, r14
    mov r14, rdx
    mov rsi, [rbx + CG_label]
    add rsi, r13
    mov rdi, [rbx + CG_title]
    add rdi, [r12 + RO_titlelen]
    lea rdi, [rdi + r13 + 2]
    call memcpy
    add r13, r14
    mov [rbx + CG_titleoffset], r13
    cmp r13, [rbx + CG_labellen]
    jb .Lcgb_continue
    mov rdi, [rbx + CG_title]
    add r13, [r12 + RO_titlelen]
    mov byte ptr [rdi + r13 + 2], ')'
    mov byte ptr [rdi + r13 + 3], 0
    mov rdi, rbx
    call cg_row_addresses
    mov r8, [rbx + CG_title]
    mov [rax + CMD_title], r8
.Lcgb_row_hashed_start:
    mov qword ptr [rbx + CG_hashkind], 0
    mov qword ptr [rbx + CG_phase], CGB_HASH_INIT
    jmp .Lcgb_continue
.Lcgb_hash_init:
    lea rdi, [rbx + CG_sha]
    call sha256_init
    mov byte ptr [rsp], 'O'
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    mov byte ptr [rsp], 'Q'
1:  lea rdi, [rbx + CG_sha]
    mov rsi, rsp
    mov edx, 1
    call sha256_update
    test eax, eax
    jz .Lcgb_invalid
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rdx + CM_slot]
    imul r12, r12, CS_SIZE
    lea r12, [rbx + r12 + CG_slots]
    cmp qword ptr [rbx + CG_hashkind], 0
    jne 2f
    lea rsi, [r12 + CS_ordinal]
    mov edx, 8
    jmp 3f
2:  mov rsi, [r12 + CS_owner]
    mov rdx, [r12 + CS_ownerlen]
    inc rdx
3:  lea rdi, [rbx + CG_sha]
    call sha256_update
    test eax, eax
    jz .Lcgb_invalid
    mov qword ptr [rbx + CG_hashoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_HASH_DATA
    jmp .Lcgb_continue
.Lcgb_hash_data:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rbx + CG_hashoffset]
    mov r13, [rdx + CM_wirelen]
    sub r13, r12
    mov edx, 4096
    cmp r13, rdx
    cmovb rdx, r13
    mov r13, rdx
    mov rsi, [rax + CMD_name]
    add rsi, r12
    lea rdi, [rbx + CG_sha]
    call sha256_update
    test eax, eax
    jz .Lcgb_invalid
    add r12, r13
    mov [rbx + CG_hashoffset], r12
    mov rdi, rbx
    call cg_row_addresses
    cmp r12, [rdx + CM_wirelen]
    jb .Lcgb_continue
    mov qword ptr [rbx + CG_phase], CGB_HASH_FINAL
    jmp .Lcgb_continue
.Lcgb_hash_final:
    lea rdi, [rbx + CG_sha]
    lea rsi, [rbx + CG_digest]
    call sha256_final
    test eax, eax
    jz .Lcgb_invalid
    mov rdi, rbx
    call cg_row_addresses
    mov r8, [rbx + CG_digest]
    cmp qword ptr [rbx + CG_hashkind], 0
    jne 1f
    mov [rdx + CM_ownedhash], r8
    jmp 2f
1:  mov [rdx + CM_qualifiedhash], r8
2:  mov qword ptr [rbx + CG_phase], CGB_MAP_BEGIN
    jmp .Lcgb_continue
.Lcgb_map_begin:
    mov rdi, rbx
    call cg_row_addresses
    mov r8, [rdx + CM_ownedhash]
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    mov r8, [rdx + CM_qualifiedhash]
1:  mov r9, [rbx + CG_routecap]
    dec r9
    and r8, r9
    mov [rbx + CG_probe], r8
    mov qword ptr [rbx + CG_hashoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_MAP_PROBE
    jmp .Lcgb_continue
.Lcgb_map_probe:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, rax
    mov r13, rdx
    mov r14, rcx
    mov r15, [rbx + CG_owned]
    mov r8, [rdx + CM_ownedhash]
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    mov r15, [rbx + CG_qualified]
    mov r8, [rdx + CM_qualifiedhash]
1:  imul r9, [rbx + CG_probe], 24
    add r15, r9
    cmp qword ptr [r15 + 8], 0
    je .Lcgb_map_insert
    cmp [r15], r8
    jne .Lcgb_map_advance
    mov r9, [r15 + 8]
    dec r9
    mov [rbx + CG_comparerow], r9
    shl r9, 6
    add r9, [rbx + CG_metadata]
    mov r10, [r13 + CM_wirelen]
    cmp [r9 + CM_wirelen], r10
    jne .Lcgb_map_advance
    cmp qword ptr [rbx + CG_hashkind], 0
    jne .Lcgb_map_owner
    mov r10, [r13 + CM_slot]
    cmp [r9 + CM_slot], r10
    jne .Lcgb_map_advance
    jmp .Lcgb_map_compare
.Lcgb_map_owner:
    mov r9, [rbx + CG_comparerow]
    shl r9, 6
    add r9, [rbx + CG_authority + VEC_ptr]
    mov rdi, [r14 + 24]
    mov rsi, [r9 + 24]
    mov rdx, [r13 + CM_slot]
    imul rdx, rdx, CS_SIZE
    mov rdx, [rbx + rdx + CG_slots + CS_ownerlen]
    # Both identities are bounded, but compare lengths before prefix bytes.
    mov r8, [r9 + 24]
    mov r9, [rbx + CG_comparerow]
    shl r9, 6
    add r9, [rbx + CG_metadata]
    mov r9, [r9 + CM_slot]
    imul r9, r9, CS_SIZE
    cmp [rbx + r9 + CG_slots + CS_ownerlen], rdx
    jne .Lcgb_map_advance
    call memeq
    test eax, eax
    jz .Lcgb_map_advance
.Lcgb_map_compare:
    mov qword ptr [rbx + CG_compareoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_MAP_EQUAL
    jmp .Lcgb_continue
.Lcgb_map_equal:
    mov rdi, rbx
    call cg_row_addresses
    mov r12, [rbx + CG_compareoffset]
    mov r13, [rdx + CM_wirelen]
    sub r13, r12
    mov edx, 2048
    cmp r13, rdx
    cmovb rdx, r13
    mov r13, rdx
    mov rdi, [rax + CMD_name]
    add rdi, r12
    mov rsi, [rbx + CG_comparerow]
    shl rsi, 5
    add rsi, [rbx + CG_commands + VEC_ptr]
    mov rsi, [rsi + CMD_name]
    add rsi, r12
    call memeq
    test eax, eax
    jz .Lcgb_map_advance
    add r12, r13
    mov [rbx + CG_compareoffset], r12
    mov rdi, rbx
    call cg_row_addresses
    cmp r12, [rdx + CM_wirelen]
    jb .Lcgb_continue
    cmp qword ptr [rbx + CG_hashkind], 0
    jne .Lcgb_map_duplicate_qualified
    cmp qword ptr [rcx], 1
    je .Lcgb_exists
    jmp .Lcgb_map_done
.Lcgb_map_duplicate_qualified:
    imul r15, [rbx + CG_probe], 24
    add r15, [rbx + CG_qualified]
    inc qword ptr [r15 + 16]
    jmp .Lcgb_map_done
.Lcgb_map_insert:
    mov [r15], r8
    mov r8, [rbx + CG_row]
    inc r8
    mov [r15 + 8], r8
    mov qword ptr [r15 + 16], 1
    jmp .Lcgb_map_done
.Lcgb_map_advance:
    inc qword ptr [rbx + CG_hashoffset]
    mov rax, [rbx + CG_hashoffset]
    cmp rax, [rbx + CG_routecap]
    jae .Lcgb_resource
    mov rax, [rbx + CG_routecap]
    dec rax
    inc qword ptr [rbx + CG_probe]
    and [rbx + CG_probe], rax
    mov qword ptr [rbx + CG_phase], CGB_MAP_PROBE
    jmp .Lcgb_continue
.Lcgb_map_done:
    cmp qword ptr [rbx + CG_hashkind], 0
    jne 1f
    mov qword ptr [rbx + CG_hashkind], 1
    mov qword ptr [rbx + CG_phase], CGB_HASH_INIT
    jmp .Lcgb_continue
1:  inc qword ptr [rbx + CG_row]
    inc qword ptr [rbx + CG_runtime]
    mov qword ptr [rbx + CG_phase], CGB_ROW
    jmp .Lcgb_continue
.Lcgb_rows_done:
    mov qword ptr [rbx + CG_phase], CGB_DEFAULT_BEGIN
    mov qword ptr [rbx + CG_row], 0
    mov qword ptr [rbx + CG_wordmode], 0
.Lcgb_continue:
    xor eax, eax
    EPILOGUE
.Lcgb_invalid:
    mov rax, -22
    EPILOGUE
.Lcgb_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lcgb_stale:
    mov rax, -116
    EPILOGUE
.Lcgb_exists:
    mov rax, -17
    EPILOGUE
