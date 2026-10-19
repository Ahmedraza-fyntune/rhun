# WebAssembly modules: decoding the binary format, linking imports, instantiation, exports;
# memories and tables. wasm_load does everything from the bytes to a started instance.
.include "rhun.inc"
.include "wasm/wasm.inc"

.bss
.p2align 3
.globl g_wasm_types, g_wasm_resolve, g_wasm_trapped
g_wasm_types: .zero VEC_SIZE        # interned function types (WTY)
g_wasm_resolve: .quad 0             # resolve(module ptr, len, field ptr, len, kind r8, type id r9) -> object or 0
g_wasm_trapped: .long 0             # the last failed load trapped while starting (else it was malformed, invalid or unlinkable)
.p2align 3
types_tmp: .zero 2 * WASM_MAX_RESULTS + 16
imp_mod: .quad 0, 0
imp_field: .quad 0, 0
sec_end_module: .quad 0

.data
.p2align 3
.globl wasm_no_memory
wasm_no_memory: .quad 0, 0, 0, 0    # WMEM of an instance without memory: every access traps

.text
# wasm_type_intern(types ptr, nparams, nresults) -> eax id: equal signatures get equal ids
FN wasm_type_intern
    PROLOGUE
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    lea r15d, [r13 + r14]
    xor ebx, ebx
1:  cmp rbx, [rip + g_wasm_types + VEC_len]
    jae 3f
    mov rax, rbx
    shl rax, 4
    add rax, [rip + g_wasm_types + VEC_ptr]
    cmp [rax + WTY_nparams], r13d
    jne 2f
    cmp [rax + WTY_nresults], r14d
    jne 2f
    mov rdi, [rax + WTY_types]
    mov rsi, r12
    mov edx, r15d
    call memeq
    test eax, eax
    jnz 9f
2:  inc rbx
    jmp 1b
3:  lea rdi, [rip + g_wasm_types]
    mov esi, WTY_SIZE
    call vec_push
    mov [rax + WTY_nparams], r13d
    mov [rax + WTY_nresults], r14d
    push rax
    push rax
    lea rdi, [r15 + 1]
    call mem_alloc
    pop rcx
    pop rcx
    mov [rcx + WTY_types], rax
    mov rdi, rax
    mov rsi, r12
    mov edx, r15d
    call memcpy
9:  mov eax, ebx
    EPILOGUE

# wasm_type(id) -> rax WTY record
FN wasm_type
    mov eax, edi
    shl rax, 4
    add rax, [rip + g_wasm_types + VEC_ptr]
    ret

# ---------------------------------------------------------------- memories and tables

# wasm_mem_new(min pages, max pages or -1) -> rax WMEM, or 0 past the cap
FN wasm_mem_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp r12, WASM_MAX_PAGES
    ja 8f
    mov edi, WMEM_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + WMEM_max], r13
    mov rax, r12
    shl rax, 16
    mov [rbx + WMEM_size], rax
    test rax, rax
    jz 1f
    mov rdi, rax
    mov [rbx + WMEM_cap], rax
    call os_map_try
    test rax, rax
    jz 8f
    mov [rbx + WMEM_base], rax
1:  mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wasm_mem_grow(WMEM, delta pages) -> rax the old size in pages, or -1
FN wasm_mem_grow
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + WMEM_size]
    shr r13, 16                     # old pages
    lea r14, [r13 + r12]            # new pages
    cmp r14, WASM_MAX_PAGES
    ja 8f
    mov rax, [rbx + WMEM_max]
    test rax, rax
    js 1f
    cmp r14, rax
    ja 8f
1:  mov r15, r14
    shl r15, 16                     # new bytes
    cmp r15, [rbx + WMEM_cap]
    jbe 5f
    # a new mapping, twice the old one or what is asked, up to the cap or the maximum
    mov rax, [rbx + WMEM_cap]
    add rax, rax
    cmp rax, r15
    cmovb rax, r15
    mov rcx, WASM_MAX_PAGES << 16
    cmp rax, rcx
    cmova rax, rcx
    mov rcx, [rbx + WMEM_max]
    test rcx, rcx
    js 2f
    shl rcx, 16
    cmp rax, rcx
    cmova rax, rcx
2:  mov [rsp], rax
    mov rdi, rax
    call os_map_try
    test rax, rax
    jz 8f
    mov r12, rax
    mov rdi, rax
    mov rsi, [rbx + WMEM_base]
    mov rdx, [rbx + WMEM_size]
    test rdx, rdx
    jz 3f
    call memcpy
    mov rdi, [rbx + WMEM_base]
    mov rsi, [rbx + WMEM_cap]
    SYS SYS_munmap
3:  mov [rbx + WMEM_base], r12
    mov rax, [rsp]
    mov [rbx + WMEM_cap], rax
5:  mov [rbx + WMEM_size], r15
    mov rax, r13
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# wasm_table_new(min, max or -1, type) -> rax WTB
FN wasm_table_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r12, WASM_MAX_TABLE
    ja 8f
    mov edi, WTB_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + WTB_size], r12
    mov [rbx + WTB_max], r13
    mov [rbx + WTB_type], r14
    mov [rbx + WTB_cap], r12
    lea rdi, [r12*8 + 8]
    call mem_alloc
    mov [rbx + WTB_elems], rax
    mov rax, rbx
    EPILOGUE
8:  lea rdi, [rip + .Lm_table_large]
    jmp wasm_fail

# wasm_table_grow(WTB, delta, init) -> rax the old size, or -1
FN wasm_table_grow
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + WTB_size]
    lea r15, [r14 + r12]
    cmp r15, WASM_MAX_TABLE
    ja 8f
    mov rax, [rbx + WTB_max]
    test rax, rax
    js 1f
    cmp r15, rax
    ja 8f
1:  cmp r15, [rbx + WTB_cap]
    jbe 3f
    mov rsi, [rbx + WTB_cap]
    add rsi, rsi
    cmp rsi, r15
    cmovb rsi, r15
    mov [rbx + WTB_cap], rsi
    lea rsi, [rsi*8 + 8]
    mov rdi, [rbx + WTB_elems]
    call mem_realloc
    mov [rbx + WTB_elems], rax
3:  mov rdi, [rbx + WTB_elems]
    mov rcx, r14
4:  cmp rcx, r15
    jae 5f
    mov [rdi + rcx*8], r13
    inc rcx
    jmp 4b
5:  mov [rbx + WTB_size], r15
    mov rax, r14
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# ---------------------------------------------------------------- loading

# wasm_load(bytes, len) -> rax instance, or 0 with g_wasm_err (and g_wasm_trapped when it trapped
# while instantiating). The instance keeps the bytes.
FN wasm_load
    PROLOGUE 64
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov dword ptr [rip + g_wasm_trapped], 0
    mov [rip + g_wasm_fail_rsp], rsp
    mov [rip + g_wasm_fail_rbp], rbp
    lea rax, [rip + .Lload_failed]
    mov [rip + g_wasm_fail_ip], rax
    mov edi, WI_SIZE
    call mem_alloc
    mov rbx, rax
    mov rax, [rsp]
    mov [rbx + WI_bytes], rax
    mov rax, [rsp + 8]
    mov [rbx + WI_len], rax
    mov qword ptr [rbx + WI_start], -1
    mov qword ptr [rbx + WI_datacount], -1
    lea rax, [rip + wasm_no_memory]
    mov [rbx + WI_mem], rax
    mov r12, [rsp]
    mov r13, r12
    add r13, [rsp + 8]
    mov [rip + sec_end_module], r13
    # the header: \0asm and version 1
    mov rax, r13
    sub rax, r12
    cmp rax, 4
    jb .Lbad_magic
    cmp dword ptr [r12], 0x6d736100
    jne .Lbad_magic
    cmp rax, 8
    jb .Lbad_version
    cmp dword ptr [r12 + 4], 1
    jne .Lbad_version
    add r12, 8
    mov dword ptr [rsp + 16], 0     # the last section's rank
.Lsection:
    mov r13, [rip + sec_end_module]
    cmp r12, r13
    jae .Lsections_done
    call wasm_byte
    mov r14d, eax                   # id
    call wasm_u32
    mov rcx, r13
    sub rcx, r12
    mov eax, eax
    cmp rax, rcx
    ja wasm_fail_eof
    lea r13, [r12 + rax]            # this section's end
    test r14d, r14d
    jz .Lcustom
    cmp r14d, 12
    ja .Lbad_section
    lea rax, [rip + .Lsection_rank]
    movzx eax, byte ptr [rax + r14]
    cmp eax, [rsp + 16]
    jbe .Lbad_order
    mov [rsp + 16], eax
    lea rax, [rip + .Lsection_table]
    call [rax + r14*8]
    cmp r12, r13
    jne .Lsize_mismatch
    jmp .Lsection
.Lcustom:
    call wasm_name
    mov r12, r13
    jmp .Lsection
.Lsections_done:
    mov rax, [rbx + WI_ndefined]
    cmp rax, [rbx + WI_nbodies]
    jne .Lcode_count
    mov rax, [rbx + WI_datacount]
    test rax, rax
    js 1f
    cmp rax, [rbx + WI_ndatas]
    jne .Ldata_count
1:  # compile every defined function, then give each its code's address
    xor r14d, r14d
2:  cmp r14, [rbx + WI_ndefined]
    jae 3f
    mov rdi, rbx
    mov rsi, r14
    call wasm_compile
    inc r14
    jmp 2b
3:  xor r14d, r14d
    mov r15, [rbx + WI_fnmem]
4:  cmp r14, [rbx + WI_ndefined]
    jae 5f
    mov rax, [r15 + WFN_code]
    add rax, [rbx + WI_code]
    mov [r15 + WFN_code], rax
    add r15, WFN_SIZE
    inc r14
    jmp 4b
5:  mov rdi, rbx
    call wasm_instantiate
    test rax, rax
    jnz .Lload_trapped
    mov rax, rbx
    EPILOGUE
.Lload_trapped:
    mov dword ptr [rip + g_wasm_trapped], 1
    mov edi, eax
    call wasm_trap_text
    mov [rip + g_wasm_err], rax
.Lload_failed:
    xor eax, eax
    EPILOGUE
.Lbad_magic:
    lea rdi, [rip + .Lm_magic]
    jmp wasm_fail
.Lbad_version:
    lea rdi, [rip + .Lm_version]
    jmp wasm_fail
.Lbad_section:
    lea rdi, [rip + .Lm_section]
    jmp wasm_fail
.Lbad_order:
    lea rdi, [rip + .Lm_order]
    jmp wasm_fail
.Lsize_mismatch:
    lea rdi, [rip + .Lm_size]
    jmp wasm_fail
.Lcode_count:
    lea rdi, [rip + .Lm_code_count]
    jmp wasm_fail
.Ldata_count:
    lea rdi, [rip + .Lm_data_count]
    jmp wasm_fail

# wasm_valtype -> eax: a value type byte
FN wasm_valtype
    call wasm_byte
    cmp eax, WV_I32
    je 1f
    cmp eax, WV_I64
    je 1f
    cmp eax, WV_F32
    je 1f
    cmp eax, WV_F64
    je 1f
    cmp eax, WV_FUNCREF
    je 1f
    cmp eax, WV_EXTERNREF
    je 1f
    cmp eax, WV_V128
    je 2f
    lea rdi, [rip + .Lm_valtype]
    jmp wasm_fail
1:  ret
2:  lea rdi, [rip + .Lm_simd]
    jmp wasm_fail

# wasm_reftype -> eax
FN wasm_reftype
    call wasm_byte
    cmp eax, WV_FUNCREF
    je 1f
    cmp eax, WV_EXTERNREF
    je 1f
    lea rdi, [rip + .Lm_reftype]
    jmp wasm_fail
1:  ret

# wasm_limits(max allowed) -> rax min, rdx max or -1
FN wasm_limits
    push rbx
    push r14
    mov r14, rdi
    call wasm_byte
    mov ebx, eax
    cmp ebx, 1
    ja 7f
    call wasm_u32
    mov ecx, eax
    push rcx
    mov rdx, -1
    test ebx, ebx
    jz 1f
    call wasm_u32
    mov edx, eax
1:  pop rax
    cmp rax, r14
    ja 8f
    test rdx, rdx
    js 2f
    cmp rdx, r14
    ja 8f
    cmp rax, rdx
    ja 9f
2:  pop r14
    pop rbx
    ret
7:  lea rdi, [rip + .Lm_limits]
    jmp wasm_fail
8:  lea rdi, [rip + .Lm_mem_pages]
    jmp wasm_fail
9:  lea rdi, [rip + .Lm_min_max]
    jmp wasm_fail

# wasm_mark_ref(function index): ref.func may name it in code
FN wasm_mark_ref
    push rdi
    cmp qword ptr [rbx + WI_refs], 0
    jne 1f
    mov rdi, [rbx + WI_nfuncs]
    inc rdi
    call mem_alloc
    mov [rbx + WI_refs], rax
1:  pop rdi
    mov rax, [rbx + WI_refs]
    mov byte ptr [rax + rdi], 1
    ret

# wasm_const(expected type edi; WV_UNKNOWN for any reference type) -> rax value, edx its type
# A constant expression: one constant, ref.null, ref.func or global.get of an imported immutable
# global, then end.
FN wasm_const
    DPROLOGUE 16
    mov r14d, edi
    call wasm_byte
    cmp eax, 0x41
    je .Lc_i32
    cmp eax, 0x42
    je .Lc_i64
    cmp eax, 0x43
    je .Lc_f32
    cmp eax, 0x44
    je .Lc_f64
    cmp eax, 0xd0
    je .Lc_null
    cmp eax, 0xd2
    je .Lc_func
    cmp eax, 0x23
    je .Lc_global
    cmp eax, 0x0b
    je .Lc_mismatch
    jmp .Lc_required
.Lc_i32:
    call wasm_s32
    mov eax, eax
    mov r15d, WV_I32
    jmp .Lc_end
.Lc_i64:
    call wasm_s64
    mov r15d, WV_I64
    jmp .Lc_end
.Lc_f32:
    mov edi, 4
    call wasm_bytes
    mov eax, [rax]
    mov r15d, WV_F32
    jmp .Lc_end
.Lc_f64:
    mov edi, 8
    call wasm_bytes
    mov rax, [rax]
    mov r15d, WV_F64
    jmp .Lc_end
.Lc_null:
    call wasm_reftype
    mov r15d, eax
    xor eax, eax
    jmp .Lc_end
.Lc_func:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nfuncs]
    jae .Lc_unknown_func
    mov rdi, rax
    push rax
    push rax
    call wasm_mark_ref
    pop rax
    pop rax
    mov rcx, [rbx + WI_funcs]
    mov rax, [rcx + rax*8]
    mov r15d, WV_FUNCREF
    jmp .Lc_end
.Lc_global:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nimpglobals]
    jae .Lc_unknown_global
    mov rcx, [rbx + WI_globals]
    mov rcx, [rcx + rax*8]
    cmp byte ptr [rcx + WGL_mut], 0
    jne .Lc_required
    movzx r15d, byte ptr [rcx + WGL_type]
    mov rax, [rcx + WGL_value]
.Lc_end:
    mov [rsp], rax
    call wasm_byte
    cmp eax, 0x0b
    jne .Lc_required
    test r14d, r14d
    jz 1f
    cmp r15d, r14d
    jne .Lc_mismatch
    jmp 2f
1:  cmp r15d, WV_FUNCREF
    je 2f
    cmp r15d, WV_EXTERNREF
    jne .Lc_mismatch
2:  mov rax, [rsp]
    mov edx, r15d
    DEPILOGUE
.Lc_required:
    lea rdi, [rip + .Lm_const]
    jmp wasm_fail
.Lc_mismatch:
    lea rdi, [rip + .Lm_type_mismatch]
    jmp wasm_fail
.Lc_unknown_func:
    lea rdi, [rip + .Lm_unknown_func]
    jmp wasm_fail
.Lc_unknown_global:
    lea rdi, [rip + .Lm_unknown_global]
    jmp wasm_fail

# ---------------------------------------------------------------- sections (rbx instance, r12..r13)

sec_type:
    DPROLOGUE 16
    mov edi, 3
    call wasm_count
    cmp eax, WASM_MAX_TYPES
    ja .Lt_many
    mov [rbx + WI_ntypes], rax
    lea rdi, [rax*4 + 4]
    call mem_alloc
    mov [rbx + WI_types], rax
    xor r14d, r14d
1:  cmp r14, [rbx + WI_ntypes]
    jae 9f
    call wasm_byte
    cmp eax, 0x60
    jne .Lt_form
    call wasm_u32
    cmp eax, WASM_MAX_RESULTS
    ja .Lt_many
    mov r15d, eax                   # params
    lea rdi, [rip + types_tmp]
    xor ecx, ecx
2:  cmp ecx, r15d
    jae 3f
    push rcx
    push rdi
    call wasm_valtype
    pop rdi
    pop rcx
    mov [rdi + rcx], al
    inc ecx
    jmp 2b
3:  call wasm_u32
    cmp eax, WASM_MAX_RESULTS
    ja .Lt_many
    mov [rsp], eax                  # results
    lea rdi, [rip + types_tmp]
    add rdi, r15
    xor ecx, ecx
4:  cmp ecx, [rsp]
    jae 5f
    push rcx
    push rdi
    call wasm_valtype
    pop rdi
    pop rcx
    mov [rdi + rcx], al
    inc ecx
    jmp 4b
5:  lea rdi, [rip + types_tmp]
    mov esi, r15d
    mov edx, [rsp]
    call wasm_type_intern
    mov rcx, [rbx + WI_types]
    mov [rcx + r14*4], eax
    inc r14
    jmp 1b
9:  DEPILOGUE
.Lt_form:
    lea rdi, [rip + .Lm_form]
    jmp wasm_fail
.Lt_many:
    lea rdi, [rip + .Lm_too_many]
    jmp wasm_fail

sec_import:
    DPROLOGUE 32
    mov edi, 4
    call wasm_count
    mov [rsp], rax
    xor r14d, r14d
.Li_next:
    cmp r14, [rsp]
    jae .Li_done
    call wasm_name
    mov [rip + imp_mod], rax
    mov [rip + imp_mod + 8], rdx
    call wasm_name
    mov [rip + imp_field], rax
    mov [rip + imp_field + 8], rdx
    call wasm_byte
    cmp eax, WK_FUNC
    je .Li_func
    cmp eax, WK_TABLE
    je .Li_table
    cmp eax, WK_MEM
    je .Li_mem
    cmp eax, WK_GLOBAL
    je .Li_global
    lea rdi, [rip + .Lm_import_kind]
    jmp wasm_fail
.Li_func:
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_ntypes]
    jae .Li_unknown_type
    mov rcx, [rbx + WI_types]
    mov r15d, [rcx + rax*4]         # the type id
    mov r8d, WK_FUNC
    mov r9d, r15d
    call .Li_resolve
    cmp [rax + WFN_type], r15d
    jne .Li_incompatible
    mov [rsp + 8], rax
    lea rdi, [rbx + WI_funcs]
    mov esi, 8
    call vec_push
    mov rcx, [rsp + 8]
    mov [rax], rcx
    inc qword ptr [rbx + WI_nimpfuncs]
    jmp .Li_step
.Li_table:
    call wasm_reftype
    mov r15d, eax
    mov edi, -1
    call wasm_limits
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov r8d, WK_TABLE
    xor r9d, r9d
    call .Li_resolve
    cmp [rax + WTB_type], r15
    jne .Li_incompatible
    mov rdi, [rax + WTB_size]
    mov rsi, [rax + WTB_max]
    mov r15, rax
    call .Li_limits_match
    lea rdi, [rbx + WI_tables]
    mov esi, 8
    call vec_push
    mov [rax], r15
    jmp .Li_step
.Li_mem:
    cmp qword ptr [rbx + WI_nmems], 0
    jne .Li_multi_mem
    mov edi, 65536
    call wasm_limits
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov r8d, WK_MEM
    xor r9d, r9d
    call .Li_resolve
    mov r15, rax
    mov rdi, [rax + WMEM_size]
    shr rdi, 16
    mov rsi, [rax + WMEM_max]
    call .Li_limits_match
    mov [rbx + WI_mem], r15
    inc qword ptr [rbx + WI_nmems]
    jmp .Li_step
.Li_global:
    call wasm_valtype
    mov r15d, eax
    call wasm_byte
    cmp eax, 1
    ja .Li_mutability
    mov [rsp + 8], eax
    mov r8d, WK_GLOBAL
    xor r9d, r9d
    call .Li_resolve
    movzx ecx, byte ptr [rax + WGL_type]
    cmp ecx, r15d
    jne .Li_incompatible
    movzx ecx, byte ptr [rax + WGL_mut]
    cmp ecx, [rsp + 8]
    jne .Li_incompatible
    mov r15, rax
    lea rdi, [rbx + WI_globals]
    mov esi, 8
    call vec_push
    mov [rax], r15
    inc qword ptr [rbx + WI_nimpglobals]
.Li_step:
    inc r14
    jmp .Li_next
.Li_done:
    DEPILOGUE
# the resolver's object for the import being read (r8 kind, r9 type id), or fail
.Li_resolve:
    mov rax, [rip + g_wasm_resolve]
    test rax, rax
    jz .Li_unknown
    mov rdi, [rip + imp_mod]
    mov rsi, [rip + imp_mod + 8]
    mov rdx, [rip + imp_field]
    mov rcx, [rip + imp_field + 8]
    call rax
    test rax, rax
    jz .Li_unknown
    ret
# the exporter's (current size rdi, max rsi) against the import's ([rsp+16] min, [rsp+24] max)
.Li_limits_match:
    cmp rdi, [rsp + 16]
    jb .Li_incompatible
    mov rax, [rsp + 24]
    test rax, rax
    js 1f
    test rsi, rsi
    js .Li_incompatible
    cmp rsi, rax
    ja .Li_incompatible
1:  ret
.Li_unknown:
    lea rdi, [rip + .Lm_unknown_import]
    jmp wasm_fail
.Li_incompatible:
    lea rdi, [rip + .Lm_incompatible]
    jmp wasm_fail
.Li_unknown_type:
    lea rdi, [rip + .Lm_unknown_type]
    jmp wasm_fail
.Li_multi_mem:
    lea rdi, [rip + .Lm_multi_mem]
    jmp wasm_fail
.Li_mutability:
    lea rdi, [rip + .Lm_mutability]
    jmp wasm_fail

sec_function:
    DPROLOGUE 16
    mov edi, 1
    call wasm_count
    cmp eax, WASM_MAX_FUNCS
    ja .Lt_many
    mov [rbx + WI_ndefined], rax
    imul rdi, rax, WFN_SIZE
    add rdi, 8
    call mem_alloc
    mov [rbx + WI_fnmem], rax
    mov r15, rax
    xor r14d, r14d
1:  cmp r14, [rbx + WI_ndefined]
    jae 9f
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_ntypes]
    jae .Li_unknown_type
    mov rcx, [rbx + WI_types]
    mov edi, [rcx + rax*4]
    mov [r15 + WFN_type], edi
    call wasm_type
    mov ecx, [rax + WTY_nparams]
    mov [r15 + WFN_nparams], ecx
    mov ecx, [rax + WTY_nresults]
    mov [r15 + WFN_nresults], ecx
    mov [r15 + WFN_inst], rbx
    lea rdi, [rbx + WI_funcs]
    mov esi, 8
    call vec_push
    mov [rax], r15
    add r15, WFN_SIZE
    inc r14
    jmp 1b
9:  DEPILOGUE

sec_table:
    DPROLOGUE 16
    mov edi, 3
    call wasm_count
    mov [rsp], rax
    xor r14d, r14d
1:  cmp r14, [rsp]
    jae 9f
    call wasm_reftype
    mov r15d, eax
    mov edi, -1
    call wasm_limits
    mov rdi, rax
    mov rsi, rdx
    mov edx, r15d
    call wasm_table_new
    mov r15, rax
    lea rdi, [rbx + WI_tables]
    mov esi, 8
    call vec_push
    mov [rax], r15
    inc r14
    jmp 1b
9:  DEPILOGUE

sec_memory:
    DPROLOGUE 16
    mov edi, 2
    call wasm_count
    mov [rsp], rax
    xor r14d, r14d
1:  cmp r14, [rsp]
    jae 9f
    cmp qword ptr [rbx + WI_nmems], 0
    jne .Li_multi_mem
    mov edi, 65536
    call wasm_limits
    mov rdi, rax
    mov rsi, rdx
    call wasm_mem_new
    test rax, rax
    jz 8f
    mov [rbx + WI_mem], rax
    inc qword ptr [rbx + WI_nmems]
    inc r14
    jmp 1b
9:  DEPILOGUE
8:  lea rdi, [rip + .Lm_mem_large]
    jmp wasm_fail

sec_global:
    DPROLOGUE 16
    mov edi, 3
    call wasm_count
    mov [rsp], rax
    xor r14d, r14d
1:  cmp r14, [rsp]
    jae 9f
    call wasm_valtype
    mov r15d, eax
    call wasm_byte
    cmp eax, 1
    ja .Li_mutability
    mov [rsp + 8], eax
    mov edi, r15d
    call wasm_const
    push rax
    push rax
    mov edi, WGL_SIZE
    call mem_alloc
    pop rcx
    pop rcx
    mov [rax + WGL_value], rcx
    mov [rax + WGL_type], r15b
    mov ecx, [rsp + 8]
    mov [rax + WGL_mut], cl
    mov r15, rax
    lea rdi, [rbx + WI_globals]
    mov esi, 8
    call vec_push
    mov [rax], r15
    inc r14
    jmp 1b
9:  DEPILOGUE

sec_export:
    DPROLOGUE 16
    mov edi, 3
    call wasm_count
    mov [rbx + WI_nexports], rax
    imul rdi, rax, WEX_SIZE
    add rdi, 8
    call mem_alloc
    mov [rbx + WI_exports], rax
    xor r14d, r14d
1:  cmp r14, [rbx + WI_nexports]
    jae 9f
    imul r15, r14, WEX_SIZE
    add r15, [rbx + WI_exports]
    call wasm_name
    mov [r15 + WEX_name], rax
    mov [r15 + WEX_len], rdx
    call wasm_byte
    mov [r15 + WEX_kind], rax
    mov [rsp], eax
    call wasm_u32
    mov eax, eax
    mov [r15 + WEX_index], rax
    mov ecx, [rsp]
    cmp ecx, WK_FUNC
    je 2f
    cmp ecx, WK_TABLE
    je 3f
    cmp ecx, WK_MEM
    je 4f
    cmp ecx, WK_GLOBAL
    je 5f
    lea rdi, [rip + .Lm_export_kind]
    jmp wasm_fail
2:  cmp rax, [rbx + WI_nfuncs]
    jae .Lc_unknown_func
    mov rdi, rax
    call wasm_mark_ref
    jmp 6f
3:  cmp rax, [rbx + WI_ntables]
    jae .Le_unknown_table
    jmp 6f
4:  cmp rax, [rbx + WI_nmems]
    jae .Le_unknown_memory
    jmp 6f
5:  cmp rax, [rbx + WI_nglobals]
    jae .Lc_unknown_global
6:  # names are unique
    mov rcx, [rbx + WI_exports]
7:  cmp rcx, r15
    jae 8f
    mov rdx, [rcx + WEX_len]
    cmp rdx, [r15 + WEX_len]
    jne 71f
    push rcx
    push rcx
    mov rdi, [rcx + WEX_name]
    mov rsi, [r15 + WEX_name]
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jnz .Le_duplicate
71: add rcx, WEX_SIZE
    jmp 7b
8:  inc r14
    jmp 1b
9:  DEPILOGUE
.Le_unknown_table:
    lea rdi, [rip + .Lm_unknown_table]
    jmp wasm_fail
.Le_unknown_memory:
    lea rdi, [rip + .Lm_unknown_memory]
    jmp wasm_fail
.Le_duplicate:
    lea rdi, [rip + .Lm_duplicate]
    jmp wasm_fail

sec_start:
    DPROLOGUE
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nfuncs]
    jae .Lc_unknown_func
    mov [rbx + WI_start], rax
    mov rcx, [rbx + WI_funcs]
    mov rcx, [rcx + rax*8]
    cmp dword ptr [rcx + WFN_nparams], 0
    jne 8f
    cmp dword ptr [rcx + WFN_nresults], 0
    jne 8f
    DEPILOGUE
8:  lea rdi, [rip + .Lm_start]
    jmp wasm_fail

sec_element:
    DPROLOGUE 32
    mov edi, 1
    call wasm_count
    mov [rbx + WI_nelems], rax
    imul rdi, rax, WEL_SIZE
    add rdi, 8
    call mem_alloc
    mov [rbx + WI_elems], rax
    xor r14d, r14d
.Lel_next:
    cmp r14, [rbx + WI_nelems]
    jae .Lel_done
    imul r15, r14, WEL_SIZE
    add r15, [rbx + WI_elems]
    call wasm_u32
    cmp eax, 7
    ja .Lel_kind
    mov [rsp], eax                  # flags
    mov qword ptr [r15 + WEL_type], WV_FUNCREF
    test eax, 1
    jnz 2f
    # active: a table (flag 2) and an offset
    mov qword ptr [r15 + WEL_mode], 1
    xor eax, eax
    test dword ptr [rsp], 2
    jz 1f
    call wasm_u32
    mov eax, eax
1:  mov [r15 + WEL_table], rax
    cmp rax, [rbx + WI_ntables]
    jae .Le_unknown_table
    mov edi, WV_I32
    call wasm_const
    mov [r15 + WEL_offset], rax
    jmp 3f
2:  # passive (flag 2 clear) or declarative
    xor eax, eax
    test dword ptr [rsp], 2
    jz 21f
    mov eax, 2
21: mov [r15 + WEL_mode], rax
3:  # an element kind or reference type when flag 1 or 2 is set
    test dword ptr [rsp], 3
    jz 5f
    test dword ptr [rsp], 4
    jnz 4f
    call wasm_byte
    test eax, eax
    jnz .Lel_elemkind
    jmp 5f
4:  call wasm_reftype
    mov [r15 + WEL_type], rax
5:  # the table's type must be the segment's
    cmp qword ptr [r15 + WEL_mode], 1
    jne 6f
    mov rax, [r15 + WEL_table]
    mov rcx, [rbx + WI_tables]
    mov rcx, [rcx + rax*8]
    mov rax, [rcx + WTB_type]
    cmp rax, [r15 + WEL_type]
    jne .Lc_mismatch
6:  mov edi, 1
    call wasm_count
    mov [r15 + WEL_count], rax
    lea rdi, [rax*8 + 8]
    call mem_alloc
    mov [r15 + WEL_items], rax
    xor ecx, ecx
    mov [rsp + 8], rcx
7:  mov rcx, [rsp + 8]
    cmp rcx, [r15 + WEL_count]
    jae 9f
    test dword ptr [rsp], 4
    jnz 8f
    call wasm_u32
    mov eax, eax
    cmp rax, [rbx + WI_nfuncs]
    jae .Lc_unknown_func
    mov rdi, rax
    push rax
    push rax
    call wasm_mark_ref
    pop rax
    pop rax
    mov rcx, [rbx + WI_funcs]
    mov rax, [rcx + rax*8]
    jmp 81f
8:  mov rdi, [r15 + WEL_type]
    call wasm_const
81: mov rcx, [rsp + 8]
    mov rdx, [r15 + WEL_items]
    mov [rdx + rcx*8], rax
    inc qword ptr [rsp + 8]
    jmp 7b
9:  inc r14
    jmp .Lel_next
.Lel_done:
    DEPILOGUE
.Lel_kind:
    lea rdi, [rip + .Lm_elem_kind]
    jmp wasm_fail
.Lel_elemkind:
    lea rdi, [rip + .Lm_elemkind]
    jmp wasm_fail

sec_datacount:
    DPROLOGUE
    call wasm_u32
    mov eax, eax
    mov [rbx + WI_datacount], rax
    DEPILOGUE

sec_code:
    DPROLOGUE 16
    mov edi, 1
    call wasm_count
    mov [rbx + WI_nbodies], rax
    cmp rax, [rbx + WI_ndefined]
    jne .Lcode_count
    shl rax, 4
    lea rdi, [rax + 16]
    call mem_alloc
    mov [rbx + WI_bodies], rax
    mov r15, rax
    xor r14d, r14d
1:  cmp r14, [rbx + WI_nbodies]
    jae 9f
    call wasm_u32
    mov edi, eax
    call wasm_bytes
    mov [r15 + WBO_start], rax
    mov [r15 + WBO_end], r12
    add r15, WBO_SIZE
    inc r14
    jmp 1b
9:  DEPILOGUE

sec_data:
    DPROLOGUE 16
    mov edi, 1
    call wasm_count
    mov [rbx + WI_ndatas], rax
    mov rcx, [rbx + WI_datacount]
    test rcx, rcx
    js 1f
    cmp rax, rcx
    jne .Ldata_count
1:  imul rdi, rax, WDA_SIZE
    add rdi, 8
    call mem_alloc
    mov [rbx + WI_datas], rax
    xor r14d, r14d
2:  cmp r14, [rbx + WI_ndatas]
    jae 9f
    imul r15, r14, WDA_SIZE
    add r15, [rbx + WI_datas]
    call wasm_u32
    cmp eax, 2
    ja .Ld_kind
    cmp eax, 1
    je 4f
    mov qword ptr [r15 + WDA_mode], 1
    cmp eax, 2
    jne 3f
    call wasm_u32
    test eax, eax
    jnz .Le_unknown_memory
3:  cmp qword ptr [rbx + WI_nmems], 0
    je .Le_unknown_memory
    mov edi, WV_I32
    call wasm_const
    mov [r15 + WDA_offset], rax
4:  call wasm_u32
    mov [r15 + WDA_len], rax
    mov edi, eax
    call wasm_bytes
    mov [r15 + WDA_ptr], rax
    inc r14
    jmp 2b
9:  DEPILOGUE
.Ld_kind:
    lea rdi, [rip + .Lm_data_kind]
    jmp wasm_fail

# ---------------------------------------------------------------- instantiation

# wasm_instantiate(instance) -> rax 0, or the trap code: the active segments in order, then the
# start function. Writes before a trap stay, as the spec says.
FN wasm_instantiate
    PROLOGUE 16
    mov rbx, rdi
    xor r14d, r14d
1:  cmp r14, [rbx + WI_nelems]
    jae 4f
    imul r15, r14, WEL_SIZE
    add r15, [rbx + WI_elems]
    mov rax, [r15 + WEL_mode]
    cmp rax, 2
    je 3f
    cmp rax, 1
    jne 31f
    mov rax, [r15 + WEL_table]
    mov rcx, [rbx + WI_tables]
    mov rdi, [rcx + rax*8]
    mov eax, [r15 + WEL_offset]
    mov rdx, [r15 + WEL_count]
    lea rcx, [rax + rdx]
    cmp rcx, [rdi + WTB_size]
    ja 8f
    mov rdi, [rdi + WTB_elems]
    lea rdi, [rdi + rax*8]
    mov rsi, [r15 + WEL_items]
    shl rdx, 3
    call memmove
3:  mov qword ptr [r15 + WEL_count], 0
31: inc r14
    jmp 1b
4:  xor r14d, r14d
5:  cmp r14, [rbx + WI_ndatas]
    jae 6f
    imul r15, r14, WDA_SIZE
    add r15, [rbx + WI_datas]
    cmp qword ptr [r15 + WDA_mode], 1
    jne 51f
    mov rdi, [rbx + WI_mem]
    mov eax, [r15 + WDA_offset]
    mov rdx, [r15 + WDA_len]
    lea rcx, [rax + rdx]
    cmp rcx, [rdi + WMEM_size]
    ja 7f
    mov rdi, [rdi + WMEM_base]
    add rdi, rax
    mov rsi, [r15 + WDA_ptr]
    call memmove
    mov qword ptr [r15 + WDA_len], 0
51: inc r14
    jmp 5b
6:  mov rax, [rbx + WI_start]
    test rax, rax
    js 9f
    mov rcx, [rbx + WI_funcs]
    mov rdi, [rcx + rax*8]
    xor esi, esi
    xor edx, edx
    call wasm_invoke
    EPILOGUE
7:  mov eax, WT_OOB_MEMORY
    EPILOGUE
8:  mov eax, WT_OOB_TABLE
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# wasm_export(instance, name ptr, len, kind) -> rax the index, or -1
FN wasm_export
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, [rbx + WI_exports]
    xor ecx, ecx
1:  cmp rcx, [rbx + WI_nexports]
    jae 8f
    cmp [r15 + WEX_kind], r14
    jne 2f
    cmp [r15 + WEX_len], r13
    jne 2f
    push rcx
    push rcx
    mov rdi, [r15 + WEX_name]
    mov rsi, r12
    mov rdx, r13
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jz 2f
    mov rax, [r15 + WEX_index]
    EPILOGUE
2:  add r15, WEX_SIZE
    inc rcx
    jmp 1b
8:  mov rax, -1
    EPILOGUE

# wasm_export_object(instance, name ptr, len, kind) -> rax the exported WFN, WTB, WMEM or WGL, or 0
FN wasm_export_object
    PROLOGUE
    mov rbx, rdi
    mov r14, rcx
    call wasm_export
    test rax, rax
    js 8f
    cmp r14, WK_FUNC
    jne 1f
    mov rcx, [rbx + WI_funcs]
    mov rax, [rcx + rax*8]
    EPILOGUE
1:  cmp r14, WK_TABLE
    jne 2f
    mov rcx, [rbx + WI_tables]
    mov rax, [rcx + rax*8]
    EPILOGUE
2:  cmp r14, WK_MEM
    jne 3f
    mov rax, [rbx + WI_mem]
    EPILOGUE
3:  mov rcx, [rbx + WI_globals]
    mov rax, [rcx + rax*8]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
.Lsection_table:
    .quad 0, sec_type, sec_import, sec_function, sec_table, sec_memory, sec_global, sec_export
    .quad sec_start, sec_element, sec_code, sec_data, sec_datacount
.Lsection_rank: .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 10
.Lm_magic: .asciz "magic header not detected"
.Lm_version: .asciz "unknown binary version"
.Lm_section: .asciz "malformed section id"
.Lm_order: .asciz "unexpected content after last section"
.Lm_size: .asciz "section size mismatch"
.Lm_code_count: .asciz "function and code section have inconsistent lengths"
.Lm_data_count: .asciz "data count and data section have inconsistent lengths"
.Lm_valtype: .asciz "malformed value type"
.Lm_simd: .asciz "SIMD is not supported"
.Lm_reftype: .asciz "malformed reference type"
.Lm_limits: .asciz "integer too large"
.Lm_mem_pages: .asciz "memory size must be at most 65536 pages (4GiB)"
.Lm_min_max: .asciz "size minimum must not be greater than maximum"
.Lm_const: .asciz "constant expression required"
.globl wasm_m_type_mismatch
wasm_m_type_mismatch:
.Lm_type_mismatch: .asciz "type mismatch"
.Lm_unknown_func: .asciz "unknown function"
.Lm_unknown_global: .asciz "unknown global"
.Lm_unknown_table: .asciz "unknown table"
.Lm_unknown_memory: .asciz "unknown memory"
.Lm_unknown_type: .asciz "unknown type"
.Lm_form: .asciz "malformed function type"
.Lm_too_many: .asciz "too many types or parameters"
.Lm_import_kind: .asciz "malformed import kind"
.Lm_export_kind: .asciz "malformed export kind"
.Lm_unknown_import: .asciz "unknown import"
.Lm_incompatible: .asciz "incompatible import type"
.Lm_multi_mem: .asciz "multiple memories"
.Lm_mutability: .asciz "malformed mutability"
.Lm_mem_large: .asciz "memory too large"
.Lm_table_large: .asciz "table too large"
.Lm_duplicate: .asciz "duplicate export name"
.Lm_start: .asciz "start function"
.Lm_elem_kind: .asciz "malformed elements segment kind"
.Lm_elemkind: .asciz "malformed element kind"
.Lm_data_kind: .asciz "malformed data segment kind"
