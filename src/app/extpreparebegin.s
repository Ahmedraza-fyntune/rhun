# Begin private managed preparation from an exact borrowed root anchor.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatemanifest.inc"
.include "app/extprepare.inc"
.text
# Verify DIR still names the actual borrowed anchor. No payload IO uses the pathname root.
FN prep_anchor_check
    PROLOGUE 64
    mov rbx, rdi
    mov rdi, rsi
    call ext_root_open
    test rax, rax
    js .Lepac_done
    mov r12, rax
    mov rdi, rbx
    mov rsi, rsp
    call ext_root_identity
    mov r13, rax
    test rax, rax
    js 1f
    mov rdi, r12
    lea rsi, [rsp + 32]
    call ext_root_identity
    mov r13, rax
    test rax, rax
    js 1f
    mov rdi, rsp
    lea rsi, [rsp + 32]
    mov edx, 32
    call memeq
    test eax, eax
    jnz 1f
    mov r13, -EV_CHANGED
1:  mov rdi, r12
    call ext_root_close
    mov rdx, rax
    test r13, r13
    jnz 2f
    mov r13, rax
2:  mov rax, r13
.Lepac_done:
    EPILOGUE

# Begin(rootBorrowed,DIR,owner,name,ownedLeaseOr-1)->EP* or0/RDXprimary/RCXcleanup.
# Lease ownership transfers only when the fully initialized EP is returned.
FN ext_prepare_begin
    PROLOGUE 112
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    call prep_anchor_check
    test rax, rax
    js .Lepb_anchor_error
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    call ext_prepare_alloc
    test rax, rax
    jz .Lepb_done
    mov rbx, rax
    mov rdi, [rbx + EP_root]
    lea rsi, [rip + epb_manifest]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Lepb_open_error
    mov r12, rax
    mov rdi, rax
    lea rsi, [rsp + 48]
    call ext_root_stat
    test rax, rax
    js .Lepb_stat_error
    mov rdi, rbx
    mov rsi, r12
    mov edx, 65536
    call prep_snapshot
    test rax, rax
    jz .Lepb_snapshot_error
    mov [rbx + EP_manifest], rax
    mov [rbx + EP_manifestlen], rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rsp + 80]
    call prep_hash_bytes
    mov rdi, rbx
    lea rsi, [rip + epb_manifest]
    mov edx, 13
    mov rcx, [rbx + EP_manifestlen]
    mov r8, [rsp + 48 + ER_exec]
    lea r9, [rsp + 80]
    mov r10d, SR_MANIFEST
    call prep_source_add
    test rax, rax
    jnz .Lepb_fail
    mov rdi, rbx
    mov esi, MV_SIZE
    call prep_owned_alloc
    mov [rbx + EP_raw], rax
    test rax, rax
    jz .Lepb_po_error
    mov r8, rax
    mov rdi, [rbx + EP_manifest]
    mov rsi, [rbx + EP_manifestlen]
    mov rdx, [rbx + EP_ext + EXT_owner]
    mov rcx, [rbx + EP_ext + EXT_name]
    call ext_manifest_check_bytes
    test rax, rax
    jnz .Lepb_fail
    mov rdi, rbx
    mov rsi, [rbx + EP_manifest]
    mov rdx, [rbx + EP_manifestlen]
    call ext_manifest_parse_owned
    test rax, rax
    jnz .Lepb_fail
    mov rdi, rbx
    call ext_manifest_finish_owned
    test rax, rax
    jnz .Lepb_fail
    mov rdi, rbx
    call prep_launch
    test rax, rax
    jnz .Lepb_fail
    mov rdi, rbx
    mov rsi, [rbx + EP_raw]
    call prep_owned_free
    mov qword ptr [rbx + EP_raw], 0
    mov rdi, rbx
    call prep_asset_plan
    test rax, rax
    jnz .Lepb_fail
    mov rax, [rbx + PO_eo]
    mov rcx, [rsp + 32]
    mov [rax + EO_lease], rcx
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
.Lepb_done:
    EPILOGUE
.Lepb_stat_error:
    mov r13, rax
    mov rdi, r12
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    mov rax, r13
    jmp .Lepb_fail
.Lepb_open_error:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
    mov rax, r12
    jmp .Lepb_fail
.Lepb_snapshot_error:
    mov rax, rdx
    jmp .Lepb_fail
.Lepb_po_error:
    mov rax, [rbx + PO_error]
.Lepb_fail:
    mov r12, rax
    mov rdi, rbx
    call ext_prepare_release
    mov rcx, rax
    mov rdx, r12
    xor eax, eax
    EPILOGUE
.Lepb_anchor_error:
    mov rcx, rdx
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.section .rodata
epb_manifest: .asciz "extension.ini"
