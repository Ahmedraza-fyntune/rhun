# The keypad's +, - and 0 with Ctrl zoom as the top row's keys do: Windows reports them as VK_ADD,
# VK_SUBTRACT and VK_NUMPAD0, which MapVirtualKeyW turns into the characters the bindings name; the
# character messages that may follow type nothing while Ctrl is down.
.include "win.inc"
.text
FN main
    PROLOGUE 608
    lea rcx, [rsp + 96]
    API GetKeyboardState
    test eax, eax
    jz 8f
    call keys_init
    lea rdi, [rsp + 352]
    xor esi, esi
    mov edx, 256
    call memset
    mov byte ptr [rsp + 352 + 0x11], 128    # VK_CONTROL
    mov byte ptr [rsp + 352 + 0xa2], 128    # VK_LCONTROL
    lea rcx, [rsp + 352]
    API SetKeyboardState
    test eax, eax
    jz 7f
    mov dword ptr [rip + cfg_font_size], 17
    lea r15, [rip + cases]
1:  mov ebx, [r15]
    test ebx, ebx
    jz 6f
    xor ecx, ecx
    mov edx, ebx
    mov r8d, [r15 + 4]
    xor r9d, r9d
    call win_wndproc
    mov eax, [rip + cfg_font_size]
    cmp eax, [r15 + 8]
    jne 7f
    add r15, 12
    jmp 1b
6:  xor ebx, ebx
    jmp 9f
7:  mov ebx, 1
9:  lea rcx, [rsp + 96]
    API SetKeyboardState
    mov eax, ebx
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

.data
.p2align 2
# message, key, then the editor's font size after it
cases:
    .long 0x100, 0x6b, 18         # WM_KEYDOWN VK_ADD
    .long 0x102, '+', 18          # WM_CHAR '+': not typed, not zoomed again
    .long 0x100, 0x6d, 17         # VK_SUBTRACT
    .long 0x100, 0x6d, 16
    .long 0x102, '-', 16
    .long 0x100, 0x60, 14         # VK_NUMPAD0 resets
    .long 0x100, 0xbb, 15         # the top row's = (VK_OEM_PLUS), as before
    .long 0
