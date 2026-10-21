.include "rhun.inc"
.text

# Completion has priority; live fields then consume Tab/Shift+Tab/Escape before Vim/bindings.
FN snippet_key
    PROLOGUE
    mov r12d, edi
    mov r13d, edx
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne .Lsk_none
    test r13d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .Lsk_none
    cmp r12d, KEY_TAB
    je .Lsk_eligible
    cmp r12d, KEY_ISO_LEFT_TAB
    je .Lsk_eligible
    cmp r12d, KEY_ESCAPE
    jne .Lsk_none
    test r13d, MOD_SHIFT
    jnz .Lsk_none
.Lsk_eligible:
    cmp dword ptr [rip + cfg_vim], 0
    je 1f
    cmp dword ptr [rip + g_vim_mode], VM_INSERT
    jne .Lsk_none
1:  mov rbx, [rip + g_doc]
    mov rdi, rbx
    call snippet_check
    test rax, rax
    jz .Lsk_none
    cmp r12d, KEY_ESCAPE
    je .Lsk_cancel
    mov rdi, rbx                # wsedit: a linked-editing session lets Tab reach the editor
    call ws_linked_passes
    test eax, eax
    jnz .Lsk_none
    mov esi, 1
    cmp r12d, KEY_ISO_LEFT_TAB
    je 2f
    test r13d, MOD_SHIFT
    jz 3f
2:  mov esi, -1
3:  mov rdi, rbx
    call snippet_step
    mov eax, 1
    EPILOGUE
.Lsk_cancel:
    mov rdi, rbx
    call snippet_forget
    mov rax, [rbx + DOC_cur]
    mov [rbx + DOC_anchor], rax
    call ed_touch
    mov eax, 1
    EPILOGUE
.Lsk_none:
    xor eax, eax
    EPILOGUE

FN cmd_snippet_next
    mov esi, 1
    jmp snippet_command_step
FN cmd_snippet_previous
    mov esi, -1
snippet_command_step:
    PROLOGUE
    mov r12d, esi
    call snippet_focused_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_check
    test rax, rax
    jz 9f
    mov rdi, rbx
    mov esi, r12d
    call snippet_step
9:  EPILOGUE

FN cmd_snippet_cancel
    PROLOGUE
    call snippet_focused_doc
    mov rbx, rax
    mov rdi, rax
    call snippet_check
    test rax, rax
    jz 9f
    mov rdi, rbx
    call snippet_forget
    mov rax, [rbx + DOC_cur]
    mov [rbx + DOC_anchor], rax
    call ed_touch
9:  EPILOGUE

snippet_focused_doc:
    xor eax, eax
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    mov rax, [rip + g_doc]
9:  ret
