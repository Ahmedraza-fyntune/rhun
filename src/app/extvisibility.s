# Membership authority is independent from historical native host ownership.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
.globl g_ext_prepared_catalog_active
g_ext_prepared_catalog_active: .quad 0
.text
FN ext_catalog_visibility_check
    xor eax, eax
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 1
    jbe 1f
    mov rax, -22
1:  ret

# Infallible after coordinator preflight. This latch never returns to staging.
FN ext_catalog_begin_prepared_pure
    mov qword ptr [rip + g_ext_prepared_catalog_active], 1
    ret

FN ext_is_visible
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp dword ptr [rdi + EXT_status], ES_REMOVED
    je 9f
    mov ecx, [rdi + EXT_catalog_state]
    cmp ecx, 1
    je 8f
    test ecx, ecx
    jnz 9f
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 0
    jne 9f
8:  mov eax, 1
9:  ret

# Exact typed HI ownership, including the three borrowed slot string pointers.
# Trusted stable slot only. Does not imply membership, metadata or freshness.
FN ext_host_identity_matches
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lhim_no
    mov r12, [rbx + EXT_identity_owner]
    mov rdi, r12
    call hi_is_ready
    test eax, eax
    jz .Lhim_no
    mov rdi, r12
    call ext_host_identity_owner
    cmp [rbx + EXT_owner], rax
    jne .Lhim_no
    mov rdi, r12
    call ext_host_identity_name
    cmp [rbx + EXT_name], rax
    jne .Lhim_no
    mov rdi, r12
    call ext_host_identity_state
    cmp [rbx + EXT_state], rax
    jne .Lhim_no
    mov eax, 1
    EPILOGUE
.Lhim_no:
    xor eax, eax
    EPILOGUE

# Visible accepted identity, including diagnostic HI with an unavailable empty state path.
FN ext_has_identity
    PROLOGUE
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz .Lvhi_no
    cmp dword ptr [rbx + EXT_catalog_state], 0
    je .Lvhi_yes
    mov rdi, rbx
    call ext_host_identity_matches
    test eax, eax
    jz .Lvhi_no
.Lvhi_yes:
    mov eax, 1
    EPILOGUE
.Lvhi_no:
    xor eax, eax
    EPILOGUE

FN ext_can_act
    PROLOGUE
    mov rbx, rdi
    call ext_has_identity
    test eax, eax
    jz .Lvca_no
    cmp dword ptr [rbx + EXT_catalog_state], 0
    je .Lvca_yes
    mov rax, [rbx + EXT_state]
    cmp byte ptr [rax], 0
    je .Lvca_no
.Lvca_yes:
    mov eax, 1
    EPILOGUE
.Lvca_no:
    xor eax, eax
    EPILOGUE

FN ext_has_metadata
    PROLOGUE
    mov rbx, rdi
    call ext_has_identity
    test eax, eax
    jz .Lvhm_no
    cmp dword ptr [rbx + EXT_catalog_state], 0
    je .Lvhm_yes
    mov rax, [rbx + EXT_metadata_owner]
    test rax, rax
    jz .Lvhm_no
    cmp qword ptr [rax - RD_PO_BACK + RD_kind], RD_EP
    jne .Lvhm_no
    test qword ptr [rax - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz .Lvhm_no
    cmp qword ptr [rax + PO_refs], 0
    je .Lvhm_no
    cmp qword ptr [rax + PO_ready], 1
    jne .Lvhm_no
    mov rcx, [rax + EP_kind]
    dec rcx
    cmp rcx, 1
    ja .Lvhm_no
.Lvhm_yes:
    mov eax, 1
    EPILOGUE
.Lvhm_no:
    xor eax, eax
    EPILOGUE

FN ext_slot_hide_pure
    mov dword ptr [rdi + EXT_catalog_state], 2
    mov dword ptr [rdi + EXT_wait_slot], 0
    mov dword ptr [rdi + EXT_restart], 0
    mov dword ptr [rdi + EXT_start_armed], 0
    mov dword ptr [rdi + EXT_activation_stale], 1
    ret
