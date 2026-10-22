# One soft parse budget shared by every extension. A complete message handler is atomic, so
# one message may overrun the byte/time budget. Pausing for this budget never counts as flooding.
.include "rhun.inc"

.bss
.p2align 3
budget_t0: .quad 0
budget_us: .quad 0
budget_messages: .quad 0
budget_bytes: .quad 0
budget_windows: .quad 0
budget_yields: .quad 0
budget_max_messages: .quad 0
budget_max_bytes: .quad 0

.text
# ext_budget_enter(now): reset a window when due, then report whether it has room.
FN ext_budget_enter
    mov rax, rdi
    sub rax, [rip + budget_t0]
    cmp rax, EXT_WIN_MS
    jb 1f
    mov [rip + budget_t0], rdi
    mov qword ptr [rip + budget_us], 0
    mov qword ptr [rip + budget_messages], 0
    mov qword ptr [rip + budget_bytes], 0
    inc qword ptr [rip + budget_windows]
1:  xor edi, edi
    jmp ext_budget_room

# ext_budget_room(elapsed microseconds in current pump) -> 1 if another message can be handled.
FN ext_budget_room
    add rdi, [rip + budget_us]
    cmp rdi, EXT_GLOBAL_MS * 1000
    jae 8f
    cmp qword ptr [rip + budget_messages], EXT_GLOBAL_MSGS
    jae 8f
    cmp qword ptr [rip + budget_bytes], EXT_GLOBAL_BYTES
    jae 8f
    mov eax, 1
    ret
8:  xor eax, eax
    ret

FN ext_budget_leave
    add [rip + budget_us], rdi
    ret

FN ext_budget_message
    inc qword ptr [rip + budget_messages]
    mov rax, [rip + budget_messages]
    cmp rax, [rip + budget_max_messages]
    jbe 1f
    mov [rip + budget_max_messages], rax
1:  ret

FN ext_budget_bytes
    add [rip + budget_bytes], rdi
    mov rax, [rip + budget_bytes]
    cmp rax, [rip + budget_max_bytes]
    jbe 1f
    mov [rip + budget_max_bytes], rax
1:  ret

# ext_budget_pause(ext): just the shared limit, without EXT_win_hit/flood accounting.
FN ext_budget_pause
    inc qword ptr [rip + budget_yields]
    mov rax, [rip + budget_t0]
    add rax, EXT_WIN_MS
    mov [rdi + EXT_global_until], rax
    mov dword ptr [rdi + EXT_global_wait], 1
    mov dword ptr [rdi + EXT_throttled], 1
    mov edi, [rdi + EXT_out]
    test edi, edi
    js 1f
    xor esi, esi
    jmp watch_set_events
1:  ret

# ext_budget_due(ext) -> absolute time when its throttle may resume. A provider blocked by
# both limits needs the later deadline. Backpressure-only throttles retain the own-window wake.
FN ext_budget_due
    mov rax, [rdi + EXT_win_t0]
    add rax, EXT_WIN_MS
    cmp dword ptr [rdi + EXT_global_wait], 0
    je 2f
    mov rcx, [rdi + EXT_global_until]
    cmp dword ptr [rdi + EXT_win_hit], 0
    je 1f
    cmp rcx, rax
    jbe 2f
1:  mov rax, rcx
2:  ret

FN ext_budget_dump
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lwindows]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + budget_windows]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lyields]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + budget_yields]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lmessages]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + budget_max_messages]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lbytes]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + budget_max_bytes]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

.section .rodata
.Lwindows: .asciz "budget windows="
.Lyields: .asciz " yields="
.Lmessages: .asciz " max_messages="
.Lbytes: .asciz " max_bytes="
