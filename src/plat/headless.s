# headless platform: offscreen framebuffer, used by tests and scripted runs
.include "rhun.inc"

.bss
.p2align 3
hbuf: .quad 0
hw: .long 0
hh: .long 0
.p2align 3
.globl headless_clip_plain, headless_clip_native
headless_clip_plain:
hclip: .zero SB_SIZE
headless_clip_native:
hclip_wire: .zero SB_SIZE
# window requests, recorded for tests; a move grabs the pointer like a compositor does
.globl g_hl_grab, g_hl_moves, g_hl_minimized, g_hl_frames
g_hl_grab: .long 0
g_hl_moves: .long 0
g_hl_minimized: .long 0
g_hl_frames: .long 0            # frames drawn, for tests

.text

FN headless_init
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    lea rax, [rip + hl_nop]
    lea rdi, [rip + g_plat]
    mov ecx, PLAT_SIZE / 8
1:  mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz 1b
    lea rax, [rip + hl_timeout]
    mov [rip + g_plat + P_timeout], rax
    lea rax, [rip + hl_draw]
    mov [rip + g_plat + P_draw], rax
    lea rax, [rip + headless_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + headless_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    lea rax, [rip + headless_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    lea rax, [rip + hl_move]
    mov [rip + g_plat + P_move], rax
    lea rax, [rip + hl_minimize]
    mov [rip + g_plat + P_minimize], rax
    lea rax, [rip + hl_maximize]
    mov [rip + g_plat + P_maximize], rax
    mov dword ptr [rip + g_headless], 1
    mov dword ptr [rip + g_csd], 1
    mov edi, r12d
    mov esi, r13d
    call headless_resize
    EPILOGUE

FN headless_resize
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    mov [rip + hw], edi
    mov [rip + hh], esi
    mov rdi, [rip + hbuf]
    call mem_free
    mov eax, r12d
    imul eax, r13d
    lea rdi, [rax*4]
    call mem_alloc
    mov [rip + hbuf], rax
    mov edi, r12d
    mov esi, r13d
    call app_on_resize
    mov dword ptr [rip + g_dirty], 1
    pop r13
    pop r12
    pop rbx
    ret

hl_nop:
    ret

hl_move:
    inc dword ptr [rip + g_hl_moves]
    mov dword ptr [rip + g_hl_grab], 1
    ret

hl_minimize:
    inc dword ptr [rip + g_hl_minimized]
    ret

hl_maximize:
    xor dword ptr [rip + g_win_states], 1
    mov dword ptr [rip + g_dirty], 1
    ret

# hl_timeout(): at once when the last frame asked for another, otherwise forever
hl_timeout:
    xor eax, eax
    cmp dword ptr [rip + g_dirty], 0
    jne 1f
    mov eax, -1
1:  ret

hl_draw:
    push rbx
    mov rdi, [rip + hbuf]
    mov esi, [rip + hw]
    mov edx, [rip + hh]
    mov ecx, esi
    call gfx_set_target
    mov dword ptr [rip + g_dirty], 0
    inc dword ptr [rip + g_hl_frames]
    call app_render
    pop rbx
    ret

# Detach counted clipboard storage before a setter or a completion can replace it.
hl_clip_copy:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp rsi, CLW_MAX
    ja 2f
    test rdi, rdi
    jnz 1f
    test rsi, rsi
    jnz 2f
1:  lea rdi, [rsi + 1]
    call mem_alloc_try
    test rax, rax
    jz 3f
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rax, r13
    jmp 3f
2:  xor eax, eax
3:  EPILOGUE

FN headless_clip_reset
    PROLOGUE
    lea rdi, [rip + hclip]
    call sb_free
    lea rdi, [rip + hclip_wire]
    call sb_free
    EPILOGUE

FN headless_clip_set
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp rsi, DOC_MULTI_BYTES_MAX
    ja .Lhcs_bad
    test rdi, rdi
    jnz 1f
    test rsi, rsi
    jnz .Lhcs_bad
1:  call snippet_utf8_valid
    test eax, eax
    jz .Lhcs_bad
    mov rdi, rbx
    mov rsi, r12
    call hl_clip_copy
    test rax, rax
    jz .Lhcs_bad
    mov rbx, rax
    call headless_clip_reset
    mov [rip + hclip + SB_ptr], rbx
    mov [rip + hclip + SB_len], r12
    inc r12
    mov [rip + hclip + SB_cap], r12
    mov eax, 1
    EPILOGUE
.Lhcs_bad:
    xor eax, eax
    EPILOGUE

FN headless_clip_write
    PROLOGUE CWB_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov rdx, rsp
    call clip_wire_decode
    test eax, eax
    jz .Lhcw_bad
    mov rdi, rbx
    mov rsi, r12
    call hl_clip_copy
    test rax, rax
    jz .Lhcw_bad
    mov r13, rax
    mov rdi, [rsp + CWB_text]
    mov rsi, [rsp + CWB_len]
    call hl_clip_copy
    test rax, rax
    jz .Lhcw_free
    mov r14, rax
    call headless_clip_reset
    mov [rip + hclip_wire + SB_ptr], r13
    mov [rip + hclip_wire + SB_len], r12
    inc r12
    mov [rip + hclip_wire + SB_cap], r12
    mov [rip + hclip + SB_ptr], r14
    mov rax, [rsp + CWB_len]
    mov [rip + hclip + SB_len], rax
    inc rax
    mov [rip + hclip + SB_cap], rax
    mov eax, 1
    EPILOGUE
.Lhcw_free:
    mov rdi, r13
    call mem_free
.Lhcw_bad:
    xor eax, eax
    EPILOGUE

FN headless_clip_get
    PROLOGUE
    mov rbx, [rip + app_clip_active_token]
    mov rdi, [rip + hclip_wire + SB_ptr]
    test rdi, rdi
    jz .Lhcg_plain
    mov r13, [rip + hclip_wire + SB_len]
    mov rsi, r13
    call hl_clip_copy
    test rax, rax
    jz .Lhcg_plain
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r13
    call app_clip_complete_native
    mov r14d, eax
    mov rdi, r12
    call mem_free
    test r14d, r14d
    jnz .Lhcg_done
.Lhcg_plain:
    mov rdi, [rip + hclip + SB_ptr]
    test rdi, rdi
    jz .Lhcg_failure
    mov r13, [rip + hclip + SB_len]
    mov rsi, r13
    call hl_clip_copy
    test rax, rax
    jz .Lhcg_failure
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r13
    mov ecx, 1
    call app_clip_complete
    mov rdi, r12
    call mem_free
    jmp .Lhcg_done
.Lhcg_failure:
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call app_clip_complete
.Lhcg_done:
    EPILOGUE
