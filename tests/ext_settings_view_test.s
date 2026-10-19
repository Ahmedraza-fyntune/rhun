# Synthetic ready schemas use real EP/EO allocation, immutable defaults and retirement.
# No fixture readiness claim authorizes payload execution or catalog publication.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.include "app/extsettingsmemory.inc"
.equ VT_SCHEMA1_LEN, 189
.equ VT_SCHEMA2_LEN, 195
.equ VT_RAW_LEN, 254
.equ VT_INVALID_LEN, 111
.equ VT_EMPTY_LEN, 36
.equ VT_OK_LEN, 72
.equ VT_ONE_LEN, 43
.equ VT_LONG_PREFIX_LEN, 31
.equ VT_INT_PREFIX_LEN, 32
.equ VT_PERSISTED_LEN, 45
.equ VT_UNSAFE1_LEN, 49
.equ VT_UNSAFE2_LEN, 49
.equ VT_SAFE_LEN, 60
.bss
.p2align 3
vt_stage: .quad 0
vt_queue: .quad 0
vt_schema_a: .quad 0
vt_schema_b: .quad 0
vt_source: .quad 0
vt_view: .quad 0
vt_model: .quad 0
.section .rodata
vt_dir: .asciz "/fixture/private"
vt_owner: .asciz "fixture"
vt_name: .asciz "example"
vt_section: .ascii "fixture/example"
vt_schema1: .ascii "[settings]\ntext.type=string\ntext.default=base\nflag.type=bool\nflag.default=no\ncount.type=int\ncount.min=1\ncount.max=99\ncount.default=5\npick.type=choice\npick.options=red blue\npick.default=red\n"
vt_schema1_end:
vt_schema2: .ascii "[settings]\ntext.type=int\ntext.min=10\ntext.max=30\ntext.default=20\nflag.type=bool\nflag.default=yes\ncount.type=string\ncount.default=new\npick.type=choice\npick.options=green yellow\npick.default=green\n"
vt_schema2_end:
vt_raw: .ascii "[fixture/example]\nsetting.text= first \nsetting.text= snow 雪 = still \nsetting.flag=yes\nsetting.count=18446744073709551616\nsetting.count=bad\nsetting.pick=blue\nsetting.pick=invalid\npinned=yes\ndisabled=yes\nunknown=opaque\n[providers]\ncomplete.py=other/tool\n"
vt_raw_end:
vt_invalid: .ascii "[fixture/example]\nsetting.text=bad\nsetting.flag=bad\nsetting.count=bad\nsetting.pick=bad\npinned=bad\ndisabled=bad\n"
vt_invalid_end:
vt_empty: .ascii "[fixture/example]\nunknown=preserved\n"
vt_empty_end:
vt_yes: .asciz "yes"
vt_no: .asciz "no"
vt_text: .asciz "snow 雪 = still"
vt_99: .asciz "99"
vt_blue: .asciz "blue"
vt_20: .asciz "20"
vt_green: .asciz "green"
vt_bad: .asciz "bad"
vt_base: .asciz "base"
vt_five: .asciz "5"
vt_red: .asciz "red"
vt_pending: .asciz "pending"
vt_key: .ascii "setting.text"
vt_dirty_text: .ascii " \t pending \t "
vt_tag: .quad 17,29,0,0
vt_ok: .ascii "ok own-schema values, replacements, dirty intent and bounded retirement\n"
vt_ok_end:
.text
vt_fail:
    mov rdi, [rip + vt_stage]
    call sys_exit
.ifdef VT_FAULTS
.bss
.p2align 3
.globl vt_fail_unmap
vt_fail_unmap: .quad 0
vt_now: .quad 0
.text
FN vt_time
    mov rax, [rip + vt_now]
    ret
# Fail the actual OS boundary, retaining the original live mapping for a real retry.
.ifdef WINDOWS
FN vt_native_unmap
    cmp qword ptr [rip + vt_fail_unmap], 0
    je 1f
    dec qword ptr [rip + vt_fail_unmap]
    mov ecx, 1
1:  jmp [rip + __imp_VirtualFree]
.else
FN vt_native_unmap
    cmp qword ptr [rip + vt_fail_unmap], 0
    je 1f
    dec qword ptr [rip + vt_fail_unmap]
    mov edi, 1
1:  SYS SYS_munmap
    ret
.endif
vt_native_gc:
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 93
    call vt_gc
    mov qword ptr [rip + vt_stage], 106
    call ext_settings_memory_total
    mov [rsp], rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 8], rax
    mov qword ptr [rip + vt_now], 1000
    lea rdi, [rip + vt_one]
    mov esi, VT_ONE_LEN
    call vt_schema
    mov [rsp + 24], rax
    mov edi, 65520 + VT_LONG_PREFIX_LEN + 1
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + vt_long_prefix]
    mov edx, VT_LONG_PREFIX_LEN
    call memcpy
    lea rdi, [rbx + VT_LONG_PREFIX_LEN]
    mov esi, 'x'
    mov edx, 65520
    call memset
    mov byte ptr [rbx + VT_LONG_PREFIX_LEN + 65520], 10
    mov rdi, rbx
    mov esi, 65520 + VT_LONG_PREFIX_LEN + 1
    call vt_snapshot
    mov [rsp + 32], rax
    mov rdi, rbx
    call ext_settings_memory_free
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    mov edx, 65536
    call vt_build
    mov rbx, rax
    mov rax, [rax + EV_rows + EVR_value]
    mov rax, [rax - 32]
    mov [rsp + 16], rax
    cmp rax, 4096
    jb vt_fail
    mov rdi, [rsp + 24]
    call ext_prepare_release_deferred
    mov rdi, [rsp + 32]
    call ext_settings_snapshot_release
    mov rdi, rbx
    call ext_settings_view_release
    mov qword ptr [rip + vt_fail_unmap], 1
    mov qword ptr [rip + vt_stage], 108
    mov r12d, 1000
1:  mov edi, 1
    call ext_settings_view_gc
    cmp rax, 1
    jne vt_fail
    call ext_settings_view_pending
    test rax, rax
    jz 2f
    dec r12
    jnz 1b
    jmp vt_fail
2:  mov r13d, 1000
5:  mov edi, 64
    call ext_settings_snapshot_gc
    mov edi, 64
    lea rsi, [rsp + 24]
    call ext_prepare_retire_step
    test rax, rax
    js vt_fail
    cmp qword ptr [rsp + 40], 0
    jne vt_fail
    dec r13
    jnz 5b
    mov qword ptr [rip + vt_stage], 95
    mov rdi, rsp
    call vt_retained_check
    # A model can retire while an owned provider mapping transfers independently.
    mov qword ptr [rip + vt_stage], 94
    mov edi, 131072
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rax, [rbx - 32]
    mov [rsp + 16], rax
    mov edi, ELM_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov qword ptr [rax + ELM_refs], 1
    mov qword ptr [rax + ELM_ready], 1
    mov [rax + ELM_providers], rbx
    mov rdi, rax
    call ext_settings_model_release
    mov qword ptr [rip + vt_fail_unmap], 1
    mov r12d, 1000
3:  mov edi, 1
    call ext_settings_model_gc
    cmp rax, 1
    jne vt_fail
    call ext_settings_model_pending
    test rax, rax
    jz 4f
    dec r12
    jnz 3b
    jmp vt_fail
4:  mov rdi, rsp
    call vt_retained_check
    EPILOGUE
# The tuple is caller-owned for this synchronous test, never a product view borrow.
vt_retained_check:
    PROLOGUE
    mov rbx, rdi
    inc qword ptr [rip + vt_stage]
    call ext_settings_memory_pending
    cmp rax, 1
    jne vt_fail
    inc qword ptr [rip + vt_stage]
    call ext_settings_memory_total
    mov rcx, [rbx]
    add rcx, [rbx + 16]
    cmp rax, rcx
    jne vt_fail
    mov rax, [rbx + 8]
    inc rax
    cmp [rip + g_mem_live], rax
    jne vt_fail
    inc qword ptr [rip + vt_stage]
    call ext_settings_memory_timeout
    cmp rax, 16
    jne vt_fail
    inc qword ptr [rip + vt_stage]
    mov edi, 1
    call ext_settings_memory_gc
    test rax, rax
    jnz vt_fail
    or rdx, rcx
    jnz vt_fail
    add qword ptr [rip + vt_now], 16
    inc qword ptr [rip + vt_stage]
    mov edi, 1
    call ext_settings_memory_gc
    cmp rax, 1
    jne vt_fail
    test rdx, rdx
    jnz vt_fail
    cmp rcx, 1
    jne vt_fail
    inc qword ptr [rip + vt_stage]
    call ext_settings_memory_pending
    test rax, rax
    jnz vt_fail
    inc qword ptr [rip + vt_stage]
    call ext_settings_memory_total
    cmp rax, [rbx]
    jne vt_fail
    mov rax, [rbx + 8]
    cmp [rip + g_mem_live], rax
    jne vt_fail
    call ext_settings_memory_ack_cleanup
    test rax, rax
    jnz vt_fail
    EPILOGUE
.endif
# rdi manifest, rsi length -> real EP with fixture-ready private defaults.
vt_schema:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, -1
    lea rsi, [rip + vt_dir]
    lea rdx, [rip + vt_owner]
    lea rcx, [rip + vt_name]
    call ext_prepare_alloc
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call ext_manifest_parse_owned
    test rax, rax
    jnz vt_fail
    mov rdi, rbx
    call ext_prepare_defaults
    test rax, rax
    jnz vt_fail
    mov qword ptr [rbx + PO_ready], 1
    mov rax, rbx
    EPILOGUE
# rdi bytes, rsi length -> helper-validated owned ESB ref1.
vt_snapshot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + vt_tag]
    mov esi, EW_SNAPSHOT
    lea rdx, [r12 + 48]
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz vt_fail
    mov r13, rax
    mov qword ptr [rax + EJF_body], 1
    mov [rax + EJF_body + 8], r12
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rax + EJF_body + 16]
    call sha256_hash
    cmp eax, 1
    jne vt_fail
    lea rdi, [r13 + EJF_body + 48]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov qword ptr [r13 + EJF_sealed], 1
    mov rdi, r13
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jz vt_fail
    EPILOGUE
# rdi EP, rsi ESB, rdx budget -> fully built view. Bound and progress each call.
vt_build:
    PROLOGUE
    mov r12, rdx
    call ext_settings_view_begin
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov r13d, 4000000
1:  mov rdi, rbx
    mov rsi, r12
    call ext_settings_view_step
    cmp rdx, r12
    ja vt_fail
    cmp rcx, 1024
    ja vt_fail
    cmp r8, 64
    ja vt_fail
    test rax, rax
    js vt_fail
    cmp rax, 1
    je 2f
    or rdx, rcx
    or rdx, r8
    jz vt_fail
    dec r13
    jnz 1b
    jmp vt_fail
2:  mov rdi, rbx
    call ext_settings_view_check
    test rax, rax
    jnz vt_fail
    mov rax, rbx
    EPILOGUE
# rdi view, rsi ordinal, rdx expected. Check owns independent bytes.
vt_value:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_settings_view_value
    test rax, rax
    jz vt_fail
    mov r14, rax
    mov rdi, rax
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz vt_fail
    imul rax, r12, SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    cmp [rax + SD_value], r14
    je vt_fail
    test dword ptr [rax + SD_pad], 1
    jz vt_fail
    EPILOGUE
# Adopt only a synthetic retained test model, not the catalog splice API.
vt_hold_previous:
    PROLOGUE
    mov r12, rdi
    mov edi, ELM_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov qword ptr [rax + ELM_refs], 1
    mov qword ptr [rax + ELM_ready], 1
    mov [rax + ELM_slots], r12
    mov rdi, r12
    call ext_settings_view_retain
    test rax, rax
    jnz vt_fail
    mov rdi, [r12 + EV_source]
    mov [rbx + ELM_source], rdi
    call ext_settings_snapshot_retain
    test rax, rax
    jnz vt_fail
    mov [rip + esv_live_model], rbx
    mov [rip + vt_model], rbx
    mov rax, rbx
    EPILOGUE
# rdi value, rsi len, rdx remove -> exact queued intent with copied bytes.
vt_put:
    PROLOGUE 56
    mov [rsp + EC_value], rdi
    mov [rsp + EC_vallen], rsi
    mov [rsp + EC_remove], rdx
    lea rax, [rip + vt_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 15
    lea rax, [rip + vt_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 12
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    EPILOGUE
# One-unit GC must make progress and converge with all root-owned references gone.
vt_gc:
    PROLOGUE 32
    mov r12d, 100000
1:  mov edi, 1
    call ext_settings_model_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_gc_cleanup_bad
    mov edi, 1
    call ext_settings_view_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_gc_cleanup_bad
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_gc_cleanup_bad
    mov edi, 1
    lea rsi, [rsp]
    call ext_prepare_retire_step
    test rax, rax
    js vt_fail
    cmp qword ptr [rsp + 16], 0
    jne vt_fail
    dec r12
    jnz 1b
    call ext_settings_view_pending
    test rax, rax
    jnz vt_gc_views_bad
    call ext_settings_model_pending
    test rax, rax
    jnz vt_gc_model_bad
    call ext_settings_memory_pending
    test rax, rax
    jnz vt_gc_memory_bad
    EPILOGUE
vt_gc_cleanup_bad:
    mov qword ptr [rip + vt_stage], 111
    jmp vt_fail
vt_gc_views_bad:
    mov qword ptr [rip + vt_stage], 115
    jmp vt_fail
vt_gc_model_bad:
    mov qword ptr [rip + vt_stage], 116
    jmp vt_fail
vt_gc_memory_bad:
    mov qword ptr [rip + vt_stage], 117
    jmp vt_fail
FN main
    PROLOGUE 32
    mov qword ptr [rip + vt_stage], 70
    mov r15, [rip + g_mem_live]
    call ext_settings_queue_create
    test rax, rax
    jz vt_fail
    mov [rip + vt_queue], rax
    mov rdi, rax
    mov esi, 29
    call ext_settings_model_context_init
    test rax, rax
    jnz vt_fail
    lea rdi, [rip + vt_schema1]
    mov esi, VT_SCHEMA1_LEN
    call vt_schema
    mov [rip + vt_schema_a], rax
    lea rdi, [rip + vt_schema2]
    mov esi, VT_SCHEMA2_LEN
    call vt_schema
    mov [rip + vt_schema_b], rax
    lea rdi, [rip + vt_raw]
    mov esi, VT_RAW_LEN
    call vt_snapshot
    mov [rip + vt_source], rax
    mov qword ptr [rip + vt_stage], 71
    mov rdi, [rip + vt_schema_a]
    mov rsi, rax
    mov edx, 1
    call vt_build
    mov [rip + vt_view], rax
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_text]
    call vt_value
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rip + vt_yes]
    call vt_value
    mov rdi, rbx
    mov esi, 2
    lea rdx, [rip + vt_99]
    call vt_value
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + vt_blue]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_flags
    cmp rax, 1
    jne vt_fail
    cmp rdx, 1
    jne vt_fail
    cmp rcx, 2
    jne vt_fail
    mov rdi, rbx
    call vt_hold_previous
    mov qword ptr [rip + vt_stage], 72
    # Same persisted bytes interpreted by the candidate's schema and own defaults.
    mov rdi, [rip + vt_schema_b]
    mov rsi, [rip + vt_source]
    mov edx, 7
    call vt_build
    mov qword ptr [rip + vt_stage], 82
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_20]
    call vt_value
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + vt_green]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov qword ptr [rip + vt_stage], 83
    # Invalid flags may use a previous identity across replacement schema.
    lea rdi, [rip + vt_invalid]
    mov esi, VT_INVALID_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, [rip + vt_schema_b]
    mov rsi, rax
    mov edx, 65536
    call vt_build
    mov rbx, rax
    mov rdi, rax
    call ext_settings_view_flags
    cmp rax, 1
    jne vt_fail
    cmp rdx, 1
    jne vt_fail
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + vt_20]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov qword ptr [rip + vt_stage], 84
    # Same exact schema permits copied previous valid values for malformed integer input.
    mov rdi, [rip + vt_schema_a]
    mov rsi, r12
    mov edx, 1
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_bad]
    call vt_value
    mov rdi, rbx
    mov esi, 2
    lea rdx, [rip + vt_99]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov rdi, r12
    call ext_settings_snapshot_release
    mov qword ptr [rip + vt_stage], 73
    # Missing fields use own defaults, rather than retaining old effective values.
    lea rdi, [rip + vt_empty]
    mov esi, VT_EMPTY_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, [rip + vt_schema_a]
    mov rsi, rax
    mov edx, 7
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_base]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_flags
    or rax, rdx
    jnz vt_fail
    mov rdi, rbx
    call ext_settings_view_release
    mov rdi, r12
    call ext_settings_snapshot_release
    mov qword ptr [rip + vt_stage], 74
    lea rdi, [rip + vt_dirty_text]
    mov esi, 13
    xor edx, edx
    call vt_put
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    mov edx, 1
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_pending]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    # The queue retains exactly the original accepted bytes and sequence.
    mov rdi, [rip + vt_queue]
    lea rsi, [rip + vt_section]
    mov edx, 15
    lea rcx, [rip + vt_key]
    mov r8d, 12
    call ext_settings_queue_find
    test rax, rax
    jz vt_fail
    cmp qword ptr [rax + EC_vallen], 13
    jne vt_fail
    mov rdi, [rax + EC_value]
    lea rsi, [rip + vt_dirty_text]
    mov edx, 13
    call memeq
    test eax, eax
    jz vt_fail
    # A remove intent restores own schema default despite persisted override.
    xor edi, edi
    xor esi, esi
    mov edx, 1
    call vt_put
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    mov edx, 7
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_base]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov qword ptr [rip + vt_stage], 75
    # Replacing dirty storage after a yield invalidates before another queue read.
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    mov rbx, rax
    test rax, rax
    jz vt_fail
    mov rdi, rax
    mov esi, 1
    call ext_settings_view_step
    test rax, rax
    jnz vt_fail
    lea rdi, [rip + vt_dirty_text]
    mov esi, 13
    xor edx, edx
    call vt_put
    mov rdi, [rip + vt_queue]
    mov esi, 64
    call ext_settings_queue_gc
    mov rdi, rbx
    mov esi, 1
    call ext_settings_view_step
    cmp rax, -116
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    mov rdi, rbx
    call ext_settings_view_release
    # Invalid budgets and cap pressure never take caller references.
    mov qword ptr [rip + vt_stage], 76
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    mov rbx, rax
    test rax, rax
    jz vt_fail
    mov rdi, rax
    xor esi, esi
    call ext_settings_view_step
    cmp rax, -22
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    cmp qword ptr [rbx + EV_phase], EVP_ID_OWNER
    jne vt_fail
    mov rdi, rbx
    mov esi, 65537
    call ext_settings_view_step
    cmp rax, -22
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    mov rdi, rbx
    call ext_settings_view_release
    call ext_settings_memory_total
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz vt_fail
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    test rax, rax
    jnz vt_fail
    cmp rdx, -12
    jne vt_fail
    mov rdi, r14
    call ext_settings_memory_release
    mov qword ptr [rip + vt_stage], 77
    # Incompatible pending intent blocks a replacement without acknowledging it.
    mov rdi, [rip + vt_schema_b]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    test rax, rax
    jz vt_fail
    mov rbx, rax
1:  mov rdi, rbx
    mov esi, 65536
    call ext_settings_view_step
    test rax, rax
    jz 1b
    cmp rax, -22
    jne vt_fail
    mov rdi, rbx
    call ext_settings_view_release
    mov rax, [rip + vt_queue]
    cmp qword ptr [rax + EQ_count], 1
    jne vt_fail
    call vt_canonical_keys
    call vt_edges
.ifdef VT_FAULTS
    call vt_native_gc
.endif
    mov qword ptr [rip + vt_stage], 78
    # Releasing producer EP/ESB/model refs first is safe for independently owned views.
    mov rdi, [rip + vt_schema_a]
    call ext_prepare_release_deferred
    mov rdi, [rip + vt_schema_b]
    call ext_prepare_release_deferred
    mov rdi, [rip + vt_source]
    call ext_settings_snapshot_release
    mov rdi, [rip + vt_view]
    call ext_settings_view_release
    mov rdi, [rip + vt_model]
    mov qword ptr [rip + esv_live_model], 0
    call ext_settings_model_release
    mov r12d, 1000
2:  mov rdi, [rip + vt_queue]
    mov esi, 1
    call ext_settings_queue_discard_step
    test rax, rax
    js vt_fail
    test rax, rax
    jz 3f
    dec r12
    jnz 2b
    jmp vt_fail
3:  mov qword ptr [rip + vt_stage], 85
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_gc
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_free
    test rax, rax
    jnz vt_fail
    mov qword ptr [rip + esv_service_queue], 0
    mov qword ptr [rip + vt_stage], 86
    call vt_gc
    mov qword ptr [rip + vt_stage], 87
    call ext_settings_memory_total
    test rax, rax
    jnz vt_fail
    mov qword ptr [rip + vt_stage], 88
    cmp [rip + g_mem_live], r15
    jne vt_fail
    mov edi, 1
    lea rsi, [rip + vt_ok]
    mov edx, VT_OK_LEN
    call write_all
    xor eax, eax
    EPILOGUE

# Adversarial size, epoch and allocation cases use independent owned sources.
.section .rodata
vt_one: .ascii "[settings]\nlong.type=string\nlong.default=x\n"
vt_one_end:
vt_long_prefix: .ascii "[fixture/example]\nsetting.long="
vt_long_prefix_end:
vt_int_prefix: .ascii "[fixture/example]\nsetting.count="
vt_int_prefix_end:
vt_42: .asciz "42"
vt_allocphases: .quad EVP_ID_ALLOC, EVP_KEY_ALLOC, EVP_BASE_ALLOC, EVP_NORM_ALLOC
.text
vt_edges:
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 89
    lea rdi, [rip + vt_one]
    mov esi, VT_ONE_LEN
    call vt_schema
    mov [rsp], rax
    mov edi, 65536 + VT_LONG_PREFIX_LEN
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + vt_long_prefix]
    mov edx, VT_LONG_PREFIX_LEN
    call memcpy
    lea rdi, [rbx + VT_LONG_PREFIX_LEN]
    mov esi, 'x'
    mov edx, 65536
    call memset
    mov r12d, 65520
1:  mov byte ptr [rbx + VT_LONG_PREFIX_LEN + r12], 10
    mov rdi, rbx
    lea rsi, [r12 + VT_LONG_PREFIX_LEN + 1]
    call vt_snapshot
    mov r13, rax
    mov rdi, [rsp]
    mov rsi, rax
    mov edx, 7
    call vt_build
    mov r14, rax
    mov rdi, rax
    xor esi, esi
    call ext_settings_view_value
    test rax, rax
    jz vt_fail
    mov rdi, rax
    call strlen
    cmp r12, 65520
    jne 2f
    cmp rax, 65520
    jne vt_fail
    cmp qword ptr [r14 + EV_invalid], 0
    jne vt_fail
    jmp 3f
2:  cmp rax, 1
    jne vt_fail
    cmp qword ptr [r14 + EV_invalid], 1
    jne vt_fail
3:  mov rdi, r14
    call ext_settings_view_release
    mov rdi, r13
    call ext_settings_snapshot_release
    mov byte ptr [rbx + VT_LONG_PREFIX_LEN + r12], 'x'
    inc r12
    cmp r12, 65522
    jbe 1b
    mov rdi, [rsp]
    call ext_prepare_release_deferred
    mov rdi, rbx
    call ext_settings_memory_free
    # An entire maximal source of leading zeros remains bounded and yields 42.
    mov qword ptr [rip + vt_stage], 90
    mov edi, EC_LIMIT
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + vt_int_prefix]
    mov edx, VT_INT_PREFIX_LEN
    call memcpy
    lea rdi, [rbx + VT_INT_PREFIX_LEN]
    mov esi, '0'
    mov edx, EC_LIMIT - VT_INT_PREFIX_LEN
    call memset
    mov byte ptr [rbx + EC_LIMIT - 3], '4'
    mov byte ptr [rbx + EC_LIMIT - 2], '2'
    mov byte ptr [rbx + EC_LIMIT - 1], 10
    mov rdi, rbx
    mov esi, EC_LIMIT
    call vt_snapshot
    mov r12, rax
    mov rdi, rbx
    call ext_settings_memory_free
    mov rdi, [rip + vt_schema_a]
    mov rsi, r12
    mov edx, 65536
    call vt_build
    mov rbx, rax
    mov rdi, rax
    mov esi, 2
    lea rdx, [rip + vt_42]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov rdi, r12
    call ext_settings_snapshot_release
    # Epoch invalidation at a paused scalar-copy stage always returns zero work.
    mov qword ptr [rip + vt_stage], 91
    xor r14d, r14d
4:  mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov r13d, 100000
5:  cmp qword ptr [rbx + EV_phase], EVP_NORM_COPY
    je 6f
    mov rdi, rbx
    mov esi, 1
    call ext_settings_view_step
    test rax, rax
    jnz vt_fail
    dec r13
    jnz 5b
    jmp vt_fail
6:  lea r12, [rip + esv_cfg_context]
    test r14, r14
    jz 7f
    lea r12, [rip + esv_registry_epoch]
    cmp r14, 1
    je 7f
    lea r12, [rip + esv_model_epoch]
7:  inc qword ptr [r12]
    mov rdi, rbx
    mov esi, 65536
    call ext_settings_view_step
    cmp rax, -116
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    dec qword ptr [r12]
    mov rdi, rbx
    call ext_settings_view_release
    inc r14
    cmp r14, 3
    jb 4b
    # Cap failure at each private allocation phase leaves all owned inputs releasable.
    mov qword ptr [rip + vt_stage], 92
    xor r14d, r14d
8:  mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    call ext_settings_view_begin
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov r13d, 100000
9:  lea rcx, [rip + vt_allocphases]
    mov rcx, [rcx + r14 * 8]
    cmp [rbx + EV_phase], rcx
    je 10f
    mov rdi, rbx
    mov esi, 1
    call ext_settings_view_step
    test rax, rax
    jnz vt_fail
    dec r13
    jnz 9b
    jmp vt_fail
10: call ext_settings_memory_total
    mov r12d, ESM_CAP
    sub r12, rax
    mov rdi, r12
    call ext_settings_memory_reserve
    test rax, rax
    jnz vt_fail
    mov rdi, rbx
    mov esi, 65536
    call ext_settings_view_step
    cmp rax, -12
    jne vt_fail
    cmp r8, 1
    jne vt_fail
    mov rdi, r12
    call ext_settings_memory_release
    mov rdi, rbx
    call ext_settings_view_release
    inc r14
    cmp r14, 4
    jb 8b
    EPILOGUE

.section .rodata
vt_whitespace: .ascii " \t \t "
vt_persisted: .ascii "[fixture/example]\nsetting.text= \t pending \t \n"
vt_zero: .asciz ""
vt_unsafe1: .ascii "[settings]\nbad key.type=string\nbad key.default=x\n"
vt_unsafe2: .ascii "[settings]\nbad\tkey.type=string\nbad\tkey.default=x\n"
vt_safe: .ascii "[settings]\nstrange:雪.type=string\nstrange:雪.default=okay\n"
vt_okay: .asciz "okay"
.text
vt_queue_clear:
    PROLOGUE
    mov r12d, 16
1:  mov rdi, [rip + vt_queue]
    call ext_settings_queue_discard_step
    test rax, rax
    js vt_fail
    jz 2f
    dec r12
    jnz 1b
    jmp vt_fail
2:  mov rdi, [rip + vt_queue]
    call ext_settings_queue_gc
    test rdx, rdx
    js vt_fail
    EPILOGUE
vt_canonical_keys:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 118
    call vt_queue_clear
    lea rdi, [rip + vt_whitespace]
    mov esi, 5
    xor edx, edx
    call vt_put
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    mov edx, 1
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_zero]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    call vt_queue_clear
    lea rdi, [rip + vt_persisted]
    mov esi, VT_PERSISTED_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, [rip + vt_schema_a]
    mov rsi, rax
    mov edx, 1
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_pending]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov rdi, r12
    call ext_settings_snapshot_release
    # Pure schema parser fixtures intentionally bypass static package validation;
    # ESV must still refuse unescaped protocol keys before producing ready values.
    mov qword ptr [rip + vt_stage], 119
    lea rdi, [rip + vt_unsafe1]
    mov esi, VT_UNSAFE1_LEN
    call vt_schema
    mov r12, rax
    mov rdi, rax
    mov rsi, [rip + vt_source]
    call vt_key_refused
    mov rdi, r12
    call ext_prepare_release_deferred
    lea rdi, [rip + vt_unsafe2]
    mov esi, VT_UNSAFE2_LEN
    call vt_schema
    mov r12, rax
    mov rdi, rax
    mov rsi, [rip + vt_source]
    call vt_key_refused
    mov rdi, r12
    call ext_prepare_release_deferred
    lea rdi, [rip + vt_safe]
    mov esi, VT_SAFE_LEN
    call vt_schema
    mov r12, rax
    mov rdi, rax
    mov rsi, [rip + vt_source]
    mov edx, 1
    call vt_build
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_okay]
    call vt_value
    mov rdi, rbx
    call ext_settings_view_release
    mov rdi, r12
    call ext_prepare_release_deferred
    EPILOGUE
vt_key_refused:
    PROLOGUE
    call ext_settings_view_begin
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov r12d, 10000
1:  mov rdi, rbx
    mov esi, 1
    call ext_settings_view_step
    test rax, rax
    jnz 2f
    dec r12
    jnz 1b
    jmp vt_fail
2:  cmp rax, -22
    jne vt_fail
    mov rdi, rbx
    call ext_settings_view_release
    EPILOGUE
