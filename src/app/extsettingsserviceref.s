# Domain references use intrusive retirement, including failed constructors.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.bss
.p2align 3
.globl settings_service_retired_head, settings_service_retired_tail
.globl settings_service_retired_count
settings_service_retired_head: .quad 0
settings_service_retired_tail: .quad 0
settings_service_retired_count: .quad 0
.text
# Internal, sole owned unpublished/detached reference, all child slots reachable.
FN settings_service_abort
    mov qword ptr [rdi + SV_refs], 0
    mov qword ptr [rdi + SV_state], SV_RETIRED
    mov qword ptr [rdi + SV_next], 0
    mov rax, [rip + settings_service_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + SV_next], rdi
    jmp 2f
1:  mov [rip + settings_service_retired_head], rdi
2:  mov [rip + settings_service_retired_tail], rdi
    inc qword ptr [rip + settings_service_retired_count]
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    ret
FN ext_settings_service_retain
    test rdi, rdi
    jz .Lsvr_bad
    mov rax, SVC_MAGIC
    cmp [rdi + SV_magic], rax
    jne .Lsvr_bad
    cmp qword ptr [rdi + SV_refs], 0
    jle .Lsvr_bad
    cmp qword ptr [rdi + SV_state], SV_RETIRED
    jae .Lsvr_bad
    mov rax, 0x7fffffffffffffff
    cmp [rdi + SV_refs], rax
    jae .Lsvr_overflow
    inc qword ptr [rdi + SV_refs]
    xor eax, eax
    ret
.Lsvr_bad:
    mov rax, -22
    ret
.Lsvr_overflow:
    mov rax, -75
    ret
# release(owned SVCref)->0/-errno,RDX cleanup0,RCX consumed0/1.
# A current attached service cannot lose its final application reference.
FN ext_settings_service_release
    test rdi, rdi
    jz .Lsvr_release_ok
    mov rax, SVC_MAGIC
    cmp [rdi + SV_magic], rax
    jne .Lsvr_release_bad
    cmp qword ptr [rdi + SV_refs], 0
    jle .Lsvr_release_bad
    cmp qword ptr [rdi + SV_state], SV_RETIRED
    jae .Lsvr_release_bad
    cmp qword ptr [rdi + SV_refs], 1
    ja 1f
    cmp [rip + settings_service_current], rdi
    je .Lsvr_release_busy
    cmp qword ptr [rdi + SV_state], SV_DETACHED
    jne .Lsvr_release_busy
    jmp settings_service_abort
1:  dec qword ptr [rdi + SV_refs]
.Lsvr_release_ok:
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    ret
.Lsvr_release_bad:
    mov rax, -22
    jmp .Lsvr_release_refused
.Lsvr_release_busy:
    mov rax, -16
.Lsvr_release_refused:
    xor edx, edx
    xor ecx, ecx
    ret
FN ext_settings_service_pending
    mov rax, [rip + settings_service_retired_count]
    ret
