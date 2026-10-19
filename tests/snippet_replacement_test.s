.include "rhun.inc"
.bss
.p2align 3
scratch: .zero 4194305
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    lea r12, [rip + cases]
    xor r13d, r13d
.Lcase:
    mov rsi, [r12]
    test rsi, rsi
    jz .Lok
    lea rdi, [rip + scratch]
    mov rdx, [r12 + 8]
    call memcpy
    mov rax, [r12 + 24]
    cmp rax, -1
    je 1f
    lea rcx, [rip + scratch]
    mov edx, [r12 + 32]
    mov [rcx + rax], edx
1:  lea rdi, [rip + scratch]
    mov rsi, [r12 + 16]
    call snippet_replacement_validate
    mov [rsp], rax
    mov [rsp + 8], rdx
    cmp rax, [r12 + 40]
    jne .Lfail
    cmp rdx, [r12 + 48]
    jne .Lfail
    inc r13
    add r12, 56
    jmp .Lcase
.Lok:
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    lea rdi, [rip + failed]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 32
    call sb_push_byte
    lea rdi, [rip + out]
    mov rsi, [rsp]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 32
    call sb_push_byte
    lea rdi, [rip + out]
    mov rsi, [rsp + 8]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE
.section .rodata
ok: .asciz "ok snippet replacement validation\n"
failed: .asciz "failed snippet replacement validation case "
.p2align 3
fixture:
.long 0x46524e52,1,0x00100000,12,12,332,0,0
.long 0,0,0,3,0,0
.long 1,0,0,0,0,0
.long 2,1,0,0,0,0
.long 3,2,0,0,0,0
.long 4,3,0,0,0,0
.long 5,4,0,0,0,0
.long 6,5,0,0,0,0
.long 7,6,0,0,0,0
.long 8,0x7fffffff,0,0,0,0
.long 9,1,3,3,0,0
.long 10,2,6,0,0,0
.long 11,3,6,2,8,4
.byte 0xc3,0xa9,0,121,101,115,105,102,101,108,115,101
emptyprogram:
.long 0x46524e52,1,0x00100000,0,0,32,0,0
splitprogram:
.long 0x46524e52,1,0x00100000,2,2,82,0,0
.long 0,0,0,1,0,0
.long 0,0,1,1,0,0
.byte 0xc3,0xa9
tailprogram:
.long 0x46524e52,1,0x00100000,1,1,57,0,0
.long 0,0,0,0,0,0
.byte 97
unusedprogram:
.long 0x46524e52,1,0x00100000,0,1,33,0,0
.byte 0
maxprogram:
.long 0x46524e52,1,0x00100000,8192,0,196640,0,0
.zero 196608
.p2align 3
cases:
.quad fixture,332,332,-1,0,1,0
.quad fixture,332,332,0,0,0,0
.quad fixture,332,332,4,2,0,4
.quad fixture,332,332,8,0,0,8
.quad fixture,332,332,12,8193,0,12
.quad fixture,332,332,16,4294967295,0,20
.quad fixture,332,332,20,0,0,20
.quad fixture,332,332,24,1,0,24
.quad fixture,332,332,28,1,0,28
.quad fixture,332,332,32,12,0,32
.quad fixture,332,332,36,1,0,36
.quad fixture,332,332,40,1,0,40
.quad fixture,332,332,44,4294967295,0,44
.quad fixture,332,332,44,1,0,44
.quad fixture,332,332,48,1,0,48
.quad fixture,332,332,52,1,0,48
.quad fixture,332,332,60,2147483648,0,60
.quad fixture,332,332,64,1,0,64
.quad fixture,332,332,68,1,0,64
.quad fixture,332,332,72,1,0,72
.quad fixture,332,332,76,1,0,72
.quad fixture,332,332,256,0,0,256
.quad fixture,332,332,280,0,0,280
.quad fixture,332,332,312,0,0,312
.quad fixture,332,332,320,4294967295,0,320
.quad fixture,332,332,320,2038472941,0,320
.quad fixture,332,332,320,2155909364,0,320
.quad fixture,332,332,320,2038017984,0,320
.quad fixture,332,332,320,2038004163,0,320
.quad fixture,332,332,320,2042478575,1,0
.quad fixture,332,0,-1,0,0,0
.quad fixture,332,1,-1,0,0,1
.quad fixture,332,2,-1,0,0,2
.quad fixture,332,3,-1,0,0,3
.quad fixture,332,4,-1,0,0,4
.quad fixture,332,5,-1,0,0,5
.quad fixture,332,6,-1,0,0,6
.quad fixture,332,7,-1,0,0,7
.quad fixture,332,8,-1,0,0,8
.quad fixture,332,9,-1,0,0,9
.quad fixture,332,10,-1,0,0,10
.quad fixture,332,11,-1,0,0,11
.quad fixture,332,12,-1,0,0,12
.quad fixture,332,13,-1,0,0,13
.quad fixture,332,14,-1,0,0,14
.quad fixture,332,15,-1,0,0,15
.quad fixture,332,16,-1,0,0,16
.quad fixture,332,17,-1,0,0,17
.quad fixture,332,18,-1,0,0,18
.quad fixture,332,19,-1,0,0,19
.quad fixture,332,20,-1,0,0,20
.quad fixture,332,21,-1,0,0,21
.quad fixture,332,22,-1,0,0,22
.quad fixture,332,23,-1,0,0,23
.quad fixture,332,24,-1,0,0,24
.quad fixture,332,25,-1,0,0,25
.quad fixture,332,26,-1,0,0,26
.quad fixture,332,27,-1,0,0,27
.quad fixture,332,28,-1,0,0,28
.quad fixture,332,29,-1,0,0,29
.quad fixture,332,30,-1,0,0,30
.quad fixture,332,31,-1,0,0,31
.quad fixture,332,32,-1,0,0,20
.quad fixture,332,33,-1,0,0,20
.quad fixture,332,34,-1,0,0,20
.quad fixture,332,35,-1,0,0,20
.quad fixture,332,36,-1,0,0,20
.quad fixture,332,37,-1,0,0,20
.quad fixture,332,38,-1,0,0,20
.quad fixture,332,39,-1,0,0,20
.quad fixture,332,40,-1,0,0,20
.quad fixture,332,41,-1,0,0,20
.quad fixture,332,42,-1,0,0,20
.quad fixture,332,43,-1,0,0,20
.quad fixture,332,44,-1,0,0,20
.quad fixture,332,45,-1,0,0,20
.quad fixture,332,46,-1,0,0,20
.quad fixture,332,47,-1,0,0,20
.quad fixture,332,48,-1,0,0,20
.quad fixture,332,49,-1,0,0,20
.quad fixture,332,50,-1,0,0,20
.quad fixture,332,51,-1,0,0,20
.quad fixture,332,52,-1,0,0,20
.quad fixture,332,53,-1,0,0,20
.quad fixture,332,54,-1,0,0,20
.quad fixture,332,55,-1,0,0,20
.quad fixture,332,56,-1,0,0,20
.quad fixture,332,57,-1,0,0,20
.quad fixture,332,58,-1,0,0,20
.quad fixture,332,59,-1,0,0,20
.quad fixture,332,60,-1,0,0,20
.quad fixture,332,61,-1,0,0,20
.quad fixture,332,62,-1,0,0,20
.quad fixture,332,63,-1,0,0,20
.quad fixture,332,64,-1,0,0,20
.quad fixture,332,65,-1,0,0,20
.quad fixture,332,66,-1,0,0,20
.quad fixture,332,67,-1,0,0,20
.quad fixture,332,68,-1,0,0,20
.quad fixture,332,69,-1,0,0,20
.quad fixture,332,70,-1,0,0,20
.quad fixture,332,71,-1,0,0,20
.quad fixture,332,72,-1,0,0,20
.quad fixture,332,73,-1,0,0,20
.quad fixture,332,74,-1,0,0,20
.quad fixture,332,75,-1,0,0,20
.quad fixture,332,76,-1,0,0,20
.quad fixture,332,77,-1,0,0,20
.quad fixture,332,78,-1,0,0,20
.quad fixture,332,79,-1,0,0,20
.quad fixture,332,80,-1,0,0,20
.quad fixture,332,81,-1,0,0,20
.quad fixture,332,82,-1,0,0,20
.quad fixture,332,83,-1,0,0,20
.quad fixture,332,84,-1,0,0,20
.quad fixture,332,85,-1,0,0,20
.quad fixture,332,86,-1,0,0,20
.quad fixture,332,87,-1,0,0,20
.quad fixture,332,88,-1,0,0,20
.quad fixture,332,89,-1,0,0,20
.quad fixture,332,90,-1,0,0,20
.quad fixture,332,91,-1,0,0,20
.quad fixture,332,92,-1,0,0,20
.quad fixture,332,93,-1,0,0,20
.quad fixture,332,94,-1,0,0,20
.quad fixture,332,95,-1,0,0,20
.quad fixture,332,96,-1,0,0,20
.quad fixture,332,97,-1,0,0,20
.quad fixture,332,98,-1,0,0,20
.quad fixture,332,99,-1,0,0,20
.quad fixture,332,100,-1,0,0,20
.quad fixture,332,101,-1,0,0,20
.quad fixture,332,102,-1,0,0,20
.quad fixture,332,103,-1,0,0,20
.quad fixture,332,104,-1,0,0,20
.quad fixture,332,105,-1,0,0,20
.quad fixture,332,106,-1,0,0,20
.quad fixture,332,107,-1,0,0,20
.quad fixture,332,108,-1,0,0,20
.quad fixture,332,109,-1,0,0,20
.quad fixture,332,110,-1,0,0,20
.quad fixture,332,111,-1,0,0,20
.quad fixture,332,112,-1,0,0,20
.quad fixture,332,113,-1,0,0,20
.quad fixture,332,114,-1,0,0,20
.quad fixture,332,115,-1,0,0,20
.quad fixture,332,116,-1,0,0,20
.quad fixture,332,117,-1,0,0,20
.quad fixture,332,118,-1,0,0,20
.quad fixture,332,119,-1,0,0,20
.quad fixture,332,120,-1,0,0,20
.quad fixture,332,121,-1,0,0,20
.quad fixture,332,122,-1,0,0,20
.quad fixture,332,123,-1,0,0,20
.quad fixture,332,124,-1,0,0,20
.quad fixture,332,125,-1,0,0,20
.quad fixture,332,126,-1,0,0,20
.quad fixture,332,127,-1,0,0,20
.quad fixture,332,128,-1,0,0,20
.quad fixture,332,129,-1,0,0,20
.quad fixture,332,130,-1,0,0,20
.quad fixture,332,131,-1,0,0,20
.quad fixture,332,132,-1,0,0,20
.quad fixture,332,133,-1,0,0,20
.quad fixture,332,134,-1,0,0,20
.quad fixture,332,135,-1,0,0,20
.quad fixture,332,136,-1,0,0,20
.quad fixture,332,137,-1,0,0,20
.quad fixture,332,138,-1,0,0,20
.quad fixture,332,139,-1,0,0,20
.quad fixture,332,140,-1,0,0,20
.quad fixture,332,141,-1,0,0,20
.quad fixture,332,142,-1,0,0,20
.quad fixture,332,143,-1,0,0,20
.quad fixture,332,144,-1,0,0,20
.quad fixture,332,145,-1,0,0,20
.quad fixture,332,146,-1,0,0,20
.quad fixture,332,147,-1,0,0,20
.quad fixture,332,148,-1,0,0,20
.quad fixture,332,149,-1,0,0,20
.quad fixture,332,150,-1,0,0,20
.quad fixture,332,151,-1,0,0,20
.quad fixture,332,152,-1,0,0,20
.quad fixture,332,153,-1,0,0,20
.quad fixture,332,154,-1,0,0,20
.quad fixture,332,155,-1,0,0,20
.quad fixture,332,156,-1,0,0,20
.quad fixture,332,157,-1,0,0,20
.quad fixture,332,158,-1,0,0,20
.quad fixture,332,159,-1,0,0,20
.quad fixture,332,160,-1,0,0,20
.quad fixture,332,161,-1,0,0,20
.quad fixture,332,162,-1,0,0,20
.quad fixture,332,163,-1,0,0,20
.quad fixture,332,164,-1,0,0,20
.quad fixture,332,165,-1,0,0,20
.quad fixture,332,166,-1,0,0,20
.quad fixture,332,167,-1,0,0,20
.quad fixture,332,168,-1,0,0,20
.quad fixture,332,169,-1,0,0,20
.quad fixture,332,170,-1,0,0,20
.quad fixture,332,171,-1,0,0,20
.quad fixture,332,172,-1,0,0,20
.quad fixture,332,173,-1,0,0,20
.quad fixture,332,174,-1,0,0,20
.quad fixture,332,175,-1,0,0,20
.quad fixture,332,176,-1,0,0,20
.quad fixture,332,177,-1,0,0,20
.quad fixture,332,178,-1,0,0,20
.quad fixture,332,179,-1,0,0,20
.quad fixture,332,180,-1,0,0,20
.quad fixture,332,181,-1,0,0,20
.quad fixture,332,182,-1,0,0,20
.quad fixture,332,183,-1,0,0,20
.quad fixture,332,184,-1,0,0,20
.quad fixture,332,185,-1,0,0,20
.quad fixture,332,186,-1,0,0,20
.quad fixture,332,187,-1,0,0,20
.quad fixture,332,188,-1,0,0,20
.quad fixture,332,189,-1,0,0,20
.quad fixture,332,190,-1,0,0,20
.quad fixture,332,191,-1,0,0,20
.quad fixture,332,192,-1,0,0,20
.quad fixture,332,193,-1,0,0,20
.quad fixture,332,194,-1,0,0,20
.quad fixture,332,195,-1,0,0,20
.quad fixture,332,196,-1,0,0,20
.quad fixture,332,197,-1,0,0,20
.quad fixture,332,198,-1,0,0,20
.quad fixture,332,199,-1,0,0,20
.quad fixture,332,200,-1,0,0,20
.quad fixture,332,201,-1,0,0,20
.quad fixture,332,202,-1,0,0,20
.quad fixture,332,203,-1,0,0,20
.quad fixture,332,204,-1,0,0,20
.quad fixture,332,205,-1,0,0,20
.quad fixture,332,206,-1,0,0,20
.quad fixture,332,207,-1,0,0,20
.quad fixture,332,208,-1,0,0,20
.quad fixture,332,209,-1,0,0,20
.quad fixture,332,210,-1,0,0,20
.quad fixture,332,211,-1,0,0,20
.quad fixture,332,212,-1,0,0,20
.quad fixture,332,213,-1,0,0,20
.quad fixture,332,214,-1,0,0,20
.quad fixture,332,215,-1,0,0,20
.quad fixture,332,216,-1,0,0,20
.quad fixture,332,217,-1,0,0,20
.quad fixture,332,218,-1,0,0,20
.quad fixture,332,219,-1,0,0,20
.quad fixture,332,220,-1,0,0,20
.quad fixture,332,221,-1,0,0,20
.quad fixture,332,222,-1,0,0,20
.quad fixture,332,223,-1,0,0,20
.quad fixture,332,224,-1,0,0,20
.quad fixture,332,225,-1,0,0,20
.quad fixture,332,226,-1,0,0,20
.quad fixture,332,227,-1,0,0,20
.quad fixture,332,228,-1,0,0,20
.quad fixture,332,229,-1,0,0,20
.quad fixture,332,230,-1,0,0,20
.quad fixture,332,231,-1,0,0,20
.quad fixture,332,232,-1,0,0,20
.quad fixture,332,233,-1,0,0,20
.quad fixture,332,234,-1,0,0,20
.quad fixture,332,235,-1,0,0,20
.quad fixture,332,236,-1,0,0,20
.quad fixture,332,237,-1,0,0,20
.quad fixture,332,238,-1,0,0,20
.quad fixture,332,239,-1,0,0,20
.quad fixture,332,240,-1,0,0,20
.quad fixture,332,241,-1,0,0,20
.quad fixture,332,242,-1,0,0,20
.quad fixture,332,243,-1,0,0,20
.quad fixture,332,244,-1,0,0,20
.quad fixture,332,245,-1,0,0,20
.quad fixture,332,246,-1,0,0,20
.quad fixture,332,247,-1,0,0,20
.quad fixture,332,248,-1,0,0,20
.quad fixture,332,249,-1,0,0,20
.quad fixture,332,250,-1,0,0,20
.quad fixture,332,251,-1,0,0,20
.quad fixture,332,252,-1,0,0,20
.quad fixture,332,253,-1,0,0,20
.quad fixture,332,254,-1,0,0,20
.quad fixture,332,255,-1,0,0,20
.quad fixture,332,256,-1,0,0,20
.quad fixture,332,257,-1,0,0,20
.quad fixture,332,258,-1,0,0,20
.quad fixture,332,259,-1,0,0,20
.quad fixture,332,260,-1,0,0,20
.quad fixture,332,261,-1,0,0,20
.quad fixture,332,262,-1,0,0,20
.quad fixture,332,263,-1,0,0,20
.quad fixture,332,264,-1,0,0,20
.quad fixture,332,265,-1,0,0,20
.quad fixture,332,266,-1,0,0,20
.quad fixture,332,267,-1,0,0,20
.quad fixture,332,268,-1,0,0,20
.quad fixture,332,269,-1,0,0,20
.quad fixture,332,270,-1,0,0,20
.quad fixture,332,271,-1,0,0,20
.quad fixture,332,272,-1,0,0,20
.quad fixture,332,273,-1,0,0,20
.quad fixture,332,274,-1,0,0,20
.quad fixture,332,275,-1,0,0,20
.quad fixture,332,276,-1,0,0,20
.quad fixture,332,277,-1,0,0,20
.quad fixture,332,278,-1,0,0,20
.quad fixture,332,279,-1,0,0,20
.quad fixture,332,280,-1,0,0,20
.quad fixture,332,281,-1,0,0,20
.quad fixture,332,282,-1,0,0,20
.quad fixture,332,283,-1,0,0,20
.quad fixture,332,284,-1,0,0,20
.quad fixture,332,285,-1,0,0,20
.quad fixture,332,286,-1,0,0,20
.quad fixture,332,287,-1,0,0,20
.quad fixture,332,288,-1,0,0,20
.quad fixture,332,289,-1,0,0,20
.quad fixture,332,290,-1,0,0,20
.quad fixture,332,291,-1,0,0,20
.quad fixture,332,292,-1,0,0,20
.quad fixture,332,293,-1,0,0,20
.quad fixture,332,294,-1,0,0,20
.quad fixture,332,295,-1,0,0,20
.quad fixture,332,296,-1,0,0,20
.quad fixture,332,297,-1,0,0,20
.quad fixture,332,298,-1,0,0,20
.quad fixture,332,299,-1,0,0,20
.quad fixture,332,300,-1,0,0,20
.quad fixture,332,301,-1,0,0,20
.quad fixture,332,302,-1,0,0,20
.quad fixture,332,303,-1,0,0,20
.quad fixture,332,304,-1,0,0,20
.quad fixture,332,305,-1,0,0,20
.quad fixture,332,306,-1,0,0,20
.quad fixture,332,307,-1,0,0,20
.quad fixture,332,308,-1,0,0,20
.quad fixture,332,309,-1,0,0,20
.quad fixture,332,310,-1,0,0,20
.quad fixture,332,311,-1,0,0,20
.quad fixture,332,312,-1,0,0,20
.quad fixture,332,313,-1,0,0,20
.quad fixture,332,314,-1,0,0,20
.quad fixture,332,315,-1,0,0,20
.quad fixture,332,316,-1,0,0,20
.quad fixture,332,317,-1,0,0,20
.quad fixture,332,318,-1,0,0,20
.quad fixture,332,319,-1,0,0,20
.quad fixture,332,320,-1,0,0,20
.quad fixture,332,321,-1,0,0,20
.quad fixture,332,322,-1,0,0,20
.quad fixture,332,323,-1,0,0,20
.quad fixture,332,324,-1,0,0,20
.quad fixture,332,325,-1,0,0,20
.quad fixture,332,326,-1,0,0,20
.quad fixture,332,327,-1,0,0,20
.quad fixture,332,328,-1,0,0,20
.quad fixture,332,329,-1,0,0,20
.quad fixture,332,330,-1,0,0,20
.quad fixture,332,331,-1,0,0,20
.quad fixture,332,333,-1,0,0,20
.quad fixture,332,4194305,-1,0,0,20
.quad fixture,332,332,60,2147483648,0,60
.quad fixture,332,332,64,1,0,64
.quad fixture,332,332,68,1,0,64
.quad fixture,332,332,72,1,0,72
.quad fixture,332,332,76,1,0,72
.quad fixture,332,332,84,2147483648,0,84
.quad fixture,332,332,88,1,0,88
.quad fixture,332,332,92,1,0,88
.quad fixture,332,332,96,1,0,96
.quad fixture,332,332,100,1,0,96
.quad fixture,332,332,108,2147483648,0,108
.quad fixture,332,332,112,1,0,112
.quad fixture,332,332,116,1,0,112
.quad fixture,332,332,120,1,0,120
.quad fixture,332,332,124,1,0,120
.quad fixture,332,332,132,2147483648,0,132
.quad fixture,332,332,136,1,0,136
.quad fixture,332,332,140,1,0,136
.quad fixture,332,332,144,1,0,144
.quad fixture,332,332,148,1,0,144
.quad fixture,332,332,156,2147483648,0,156
.quad fixture,332,332,160,1,0,160
.quad fixture,332,332,164,1,0,160
.quad fixture,332,332,168,1,0,168
.quad fixture,332,332,172,1,0,168
.quad fixture,332,332,180,2147483648,0,180
.quad fixture,332,332,184,1,0,184
.quad fixture,332,332,188,1,0,184
.quad fixture,332,332,192,1,0,192
.quad fixture,332,332,196,1,0,192
.quad fixture,332,332,204,2147483648,0,204
.quad fixture,332,332,208,1,0,208
.quad fixture,332,332,212,1,0,208
.quad fixture,332,332,216,1,0,216
.quad fixture,332,332,220,1,0,216
.quad fixture,332,332,228,2147483648,0,228
.quad fixture,332,332,232,1,0,232
.quad fixture,332,332,236,1,0,232
.quad fixture,332,332,240,1,0,240
.quad fixture,332,332,244,1,0,240
.quad fixture,332,332,252,2147483648,0,252
.quad fixture,332,332,264,1,0,264
.quad fixture,332,332,268,1,0,264
.quad fixture,332,332,276,2147483648,0,276
.quad fixture,332,332,288,1,0,288
.quad fixture,332,332,292,1,0,288
.quad fixture,332,332,300,2147483648,0,300
.quad emptyprogram,32,32,-1,0,1,0
.quad splitprogram,82,82,-1,0,0,44
.quad tailprogram,57,57,-1,0,0,56
.quad unusedprogram,33,33,-1,0,0,32
.quad maxprogram,196640,196640,-1,0,1,0
.quad 0,0,0,0,0,0,0
