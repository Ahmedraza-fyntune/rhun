.include "rhun.inc"
.bss
.p2align 3
scratch: .zero 262145
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
    call snippet_regex_validate
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
ok: .asciz "ok snippet regex validation\n"
failed: .asciz "failed snippet regex validation case "
.p2align 3
fixture:
.long 0x58524e52,1,0x00100000,127,1,14,1,1,1,0,304,0
.long 1,97,0,0
.long 2,0,0,0
.long 3,0,0,0
.long 4,1,0,0
.long 5,2,0,0
.long 6,2,2,0
.long 7,7,8,0
.long 8,8,0,0
.long 9,1,0,0
.long 10,0,0,0
.long 11,0,11,13
.long 12,0,10,0
.long 13,13,13,3
.long 0,0,0,0
.long 0,1
.long 97,122
.long 0,0xffffffff,1,0
one:
.long 0x58524e52,1,0x00100000,0,0,1,0,0,0,0,64,0
.long 0,0,0,0
ranges:
.long 0x58524e52,1,0x00100000,0,0,1,1,2,0,0,88,0
.long 0,0,0,0
.long 0,2
.long 1,2,4,4
empty:
.long 0x58524e52,1,0x00100000,0,0,1,2,1,0,0,88,0
.long 0,0,0,0
.long 0,0,0,1
.long 1,2
unowned:
.long 0x58524e52,1,0x00100000,0,0,1,0,1,0,0,72,0
.long 0,0,0,0
.long 1,2
.p2align 3
cases:
.quad scoped,96,96,-1,0,1,0
.quad scoped,96,96,52,0,0,52
.quad scoped,96,96,52,5,0,52
.quad scoped,96,96,56,8,0,56
.quad scoped,96,96,56,128,0,56
.quad scoped,96,96,60,1,0,60
.quad scoped,96,96,68,0,0,68
.quad scoped,96,96,68,2,0,68
.quad scoped,96,96,72,4,0,72
.quad scoped,96,96,72,128,0,72
.quad scoped,96,96,76,1,0,76
.quad fixture,304,304,-1,0,1,0
.quad fixture,304,304,0,0,0,0
.quad fixture,304,304,4,2,0,4
.quad fixture,304,304,8,0,0,8
.quad fixture,304,304,44,1,0,44
.quad fixture,304,304,20,0,0,20
.quad fixture,304,304,20,8193,0,20
.quad fixture,304,304,24,257,0,24
.quad fixture,304,304,28,8193,0,28
.quad fixture,304,304,32,257,0,32
.quad fixture,304,304,40,0,0,40
.quad fixture,304,304,12,128,0,12
.quad fixture,304,304,16,65,0,16
.quad fixture,304,304,36,14,0,36
.quad fixture,304,0,-1,0,0,0
.quad fixture,304,1,-1,0,0,1
.quad fixture,304,2,-1,0,0,2
.quad fixture,304,3,-1,0,0,3
.quad fixture,304,4,-1,0,0,4
.quad fixture,304,5,-1,0,0,5
.quad fixture,304,6,-1,0,0,6
.quad fixture,304,7,-1,0,0,7
.quad fixture,304,8,-1,0,0,8
.quad fixture,304,9,-1,0,0,9
.quad fixture,304,10,-1,0,0,10
.quad fixture,304,11,-1,0,0,11
.quad fixture,304,12,-1,0,0,12
.quad fixture,304,13,-1,0,0,13
.quad fixture,304,14,-1,0,0,14
.quad fixture,304,15,-1,0,0,15
.quad fixture,304,16,-1,0,0,16
.quad fixture,304,17,-1,0,0,17
.quad fixture,304,18,-1,0,0,18
.quad fixture,304,19,-1,0,0,19
.quad fixture,304,20,-1,0,0,20
.quad fixture,304,21,-1,0,0,21
.quad fixture,304,22,-1,0,0,22
.quad fixture,304,23,-1,0,0,23
.quad fixture,304,24,-1,0,0,24
.quad fixture,304,25,-1,0,0,25
.quad fixture,304,26,-1,0,0,26
.quad fixture,304,27,-1,0,0,27
.quad fixture,304,28,-1,0,0,28
.quad fixture,304,29,-1,0,0,29
.quad fixture,304,30,-1,0,0,30
.quad fixture,304,31,-1,0,0,31
.quad fixture,304,32,-1,0,0,32
.quad fixture,304,33,-1,0,0,33
.quad fixture,304,34,-1,0,0,34
.quad fixture,304,35,-1,0,0,35
.quad fixture,304,36,-1,0,0,36
.quad fixture,304,37,-1,0,0,37
.quad fixture,304,38,-1,0,0,38
.quad fixture,304,39,-1,0,0,39
.quad fixture,304,40,-1,0,0,40
.quad fixture,304,41,-1,0,0,41
.quad fixture,304,42,-1,0,0,42
.quad fixture,304,43,-1,0,0,43
.quad fixture,304,44,-1,0,0,44
.quad fixture,304,45,-1,0,0,45
.quad fixture,304,46,-1,0,0,46
.quad fixture,304,47,-1,0,0,47
.quad fixture,304,48,-1,0,0,40
.quad fixture,304,49,-1,0,0,40
.quad fixture,304,50,-1,0,0,40
.quad fixture,304,51,-1,0,0,40
.quad fixture,304,52,-1,0,0,40
.quad fixture,304,53,-1,0,0,40
.quad fixture,304,54,-1,0,0,40
.quad fixture,304,55,-1,0,0,40
.quad fixture,304,56,-1,0,0,40
.quad fixture,304,57,-1,0,0,40
.quad fixture,304,58,-1,0,0,40
.quad fixture,304,59,-1,0,0,40
.quad fixture,304,60,-1,0,0,40
.quad fixture,304,61,-1,0,0,40
.quad fixture,304,62,-1,0,0,40
.quad fixture,304,63,-1,0,0,40
.quad fixture,304,64,-1,0,0,40
.quad fixture,304,65,-1,0,0,40
.quad fixture,304,66,-1,0,0,40
.quad fixture,304,67,-1,0,0,40
.quad fixture,304,68,-1,0,0,40
.quad fixture,304,69,-1,0,0,40
.quad fixture,304,70,-1,0,0,40
.quad fixture,304,71,-1,0,0,40
.quad fixture,304,72,-1,0,0,40
.quad fixture,304,73,-1,0,0,40
.quad fixture,304,74,-1,0,0,40
.quad fixture,304,75,-1,0,0,40
.quad fixture,304,76,-1,0,0,40
.quad fixture,304,77,-1,0,0,40
.quad fixture,304,78,-1,0,0,40
.quad fixture,304,79,-1,0,0,40
.quad fixture,304,80,-1,0,0,40
.quad fixture,304,81,-1,0,0,40
.quad fixture,304,82,-1,0,0,40
.quad fixture,304,83,-1,0,0,40
.quad fixture,304,84,-1,0,0,40
.quad fixture,304,85,-1,0,0,40
.quad fixture,304,86,-1,0,0,40
.quad fixture,304,87,-1,0,0,40
.quad fixture,304,88,-1,0,0,40
.quad fixture,304,89,-1,0,0,40
.quad fixture,304,90,-1,0,0,40
.quad fixture,304,91,-1,0,0,40
.quad fixture,304,92,-1,0,0,40
.quad fixture,304,93,-1,0,0,40
.quad fixture,304,94,-1,0,0,40
.quad fixture,304,95,-1,0,0,40
.quad fixture,304,96,-1,0,0,40
.quad fixture,304,97,-1,0,0,40
.quad fixture,304,98,-1,0,0,40
.quad fixture,304,99,-1,0,0,40
.quad fixture,304,100,-1,0,0,40
.quad fixture,304,101,-1,0,0,40
.quad fixture,304,102,-1,0,0,40
.quad fixture,304,103,-1,0,0,40
.quad fixture,304,104,-1,0,0,40
.quad fixture,304,105,-1,0,0,40
.quad fixture,304,106,-1,0,0,40
.quad fixture,304,107,-1,0,0,40
.quad fixture,304,108,-1,0,0,40
.quad fixture,304,109,-1,0,0,40
.quad fixture,304,110,-1,0,0,40
.quad fixture,304,111,-1,0,0,40
.quad fixture,304,112,-1,0,0,40
.quad fixture,304,113,-1,0,0,40
.quad fixture,304,114,-1,0,0,40
.quad fixture,304,115,-1,0,0,40
.quad fixture,304,116,-1,0,0,40
.quad fixture,304,117,-1,0,0,40
.quad fixture,304,118,-1,0,0,40
.quad fixture,304,119,-1,0,0,40
.quad fixture,304,120,-1,0,0,40
.quad fixture,304,121,-1,0,0,40
.quad fixture,304,122,-1,0,0,40
.quad fixture,304,123,-1,0,0,40
.quad fixture,304,124,-1,0,0,40
.quad fixture,304,125,-1,0,0,40
.quad fixture,304,126,-1,0,0,40
.quad fixture,304,127,-1,0,0,40
.quad fixture,304,128,-1,0,0,40
.quad fixture,304,129,-1,0,0,40
.quad fixture,304,130,-1,0,0,40
.quad fixture,304,131,-1,0,0,40
.quad fixture,304,132,-1,0,0,40
.quad fixture,304,133,-1,0,0,40
.quad fixture,304,134,-1,0,0,40
.quad fixture,304,135,-1,0,0,40
.quad fixture,304,136,-1,0,0,40
.quad fixture,304,137,-1,0,0,40
.quad fixture,304,138,-1,0,0,40
.quad fixture,304,139,-1,0,0,40
.quad fixture,304,140,-1,0,0,40
.quad fixture,304,141,-1,0,0,40
.quad fixture,304,142,-1,0,0,40
.quad fixture,304,143,-1,0,0,40
.quad fixture,304,144,-1,0,0,40
.quad fixture,304,145,-1,0,0,40
.quad fixture,304,146,-1,0,0,40
.quad fixture,304,147,-1,0,0,40
.quad fixture,304,148,-1,0,0,40
.quad fixture,304,149,-1,0,0,40
.quad fixture,304,150,-1,0,0,40
.quad fixture,304,151,-1,0,0,40
.quad fixture,304,152,-1,0,0,40
.quad fixture,304,153,-1,0,0,40
.quad fixture,304,154,-1,0,0,40
.quad fixture,304,155,-1,0,0,40
.quad fixture,304,156,-1,0,0,40
.quad fixture,304,157,-1,0,0,40
.quad fixture,304,158,-1,0,0,40
.quad fixture,304,159,-1,0,0,40
.quad fixture,304,160,-1,0,0,40
.quad fixture,304,161,-1,0,0,40
.quad fixture,304,162,-1,0,0,40
.quad fixture,304,163,-1,0,0,40
.quad fixture,304,164,-1,0,0,40
.quad fixture,304,165,-1,0,0,40
.quad fixture,304,166,-1,0,0,40
.quad fixture,304,167,-1,0,0,40
.quad fixture,304,168,-1,0,0,40
.quad fixture,304,169,-1,0,0,40
.quad fixture,304,170,-1,0,0,40
.quad fixture,304,171,-1,0,0,40
.quad fixture,304,172,-1,0,0,40
.quad fixture,304,173,-1,0,0,40
.quad fixture,304,174,-1,0,0,40
.quad fixture,304,175,-1,0,0,40
.quad fixture,304,176,-1,0,0,40
.quad fixture,304,177,-1,0,0,40
.quad fixture,304,178,-1,0,0,40
.quad fixture,304,179,-1,0,0,40
.quad fixture,304,180,-1,0,0,40
.quad fixture,304,181,-1,0,0,40
.quad fixture,304,182,-1,0,0,40
.quad fixture,304,183,-1,0,0,40
.quad fixture,304,184,-1,0,0,40
.quad fixture,304,185,-1,0,0,40
.quad fixture,304,186,-1,0,0,40
.quad fixture,304,187,-1,0,0,40
.quad fixture,304,188,-1,0,0,40
.quad fixture,304,189,-1,0,0,40
.quad fixture,304,190,-1,0,0,40
.quad fixture,304,191,-1,0,0,40
.quad fixture,304,192,-1,0,0,40
.quad fixture,304,193,-1,0,0,40
.quad fixture,304,194,-1,0,0,40
.quad fixture,304,195,-1,0,0,40
.quad fixture,304,196,-1,0,0,40
.quad fixture,304,197,-1,0,0,40
.quad fixture,304,198,-1,0,0,40
.quad fixture,304,199,-1,0,0,40
.quad fixture,304,200,-1,0,0,40
.quad fixture,304,201,-1,0,0,40
.quad fixture,304,202,-1,0,0,40
.quad fixture,304,203,-1,0,0,40
.quad fixture,304,204,-1,0,0,40
.quad fixture,304,205,-1,0,0,40
.quad fixture,304,206,-1,0,0,40
.quad fixture,304,207,-1,0,0,40
.quad fixture,304,208,-1,0,0,40
.quad fixture,304,209,-1,0,0,40
.quad fixture,304,210,-1,0,0,40
.quad fixture,304,211,-1,0,0,40
.quad fixture,304,212,-1,0,0,40
.quad fixture,304,213,-1,0,0,40
.quad fixture,304,214,-1,0,0,40
.quad fixture,304,215,-1,0,0,40
.quad fixture,304,216,-1,0,0,40
.quad fixture,304,217,-1,0,0,40
.quad fixture,304,218,-1,0,0,40
.quad fixture,304,219,-1,0,0,40
.quad fixture,304,220,-1,0,0,40
.quad fixture,304,221,-1,0,0,40
.quad fixture,304,222,-1,0,0,40
.quad fixture,304,223,-1,0,0,40
.quad fixture,304,224,-1,0,0,40
.quad fixture,304,225,-1,0,0,40
.quad fixture,304,226,-1,0,0,40
.quad fixture,304,227,-1,0,0,40
.quad fixture,304,228,-1,0,0,40
.quad fixture,304,229,-1,0,0,40
.quad fixture,304,230,-1,0,0,40
.quad fixture,304,231,-1,0,0,40
.quad fixture,304,232,-1,0,0,40
.quad fixture,304,233,-1,0,0,40
.quad fixture,304,234,-1,0,0,40
.quad fixture,304,235,-1,0,0,40
.quad fixture,304,236,-1,0,0,40
.quad fixture,304,237,-1,0,0,40
.quad fixture,304,238,-1,0,0,40
.quad fixture,304,239,-1,0,0,40
.quad fixture,304,240,-1,0,0,40
.quad fixture,304,241,-1,0,0,40
.quad fixture,304,242,-1,0,0,40
.quad fixture,304,243,-1,0,0,40
.quad fixture,304,244,-1,0,0,40
.quad fixture,304,245,-1,0,0,40
.quad fixture,304,246,-1,0,0,40
.quad fixture,304,247,-1,0,0,40
.quad fixture,304,248,-1,0,0,40
.quad fixture,304,249,-1,0,0,40
.quad fixture,304,250,-1,0,0,40
.quad fixture,304,251,-1,0,0,40
.quad fixture,304,252,-1,0,0,40
.quad fixture,304,253,-1,0,0,40
.quad fixture,304,254,-1,0,0,40
.quad fixture,304,255,-1,0,0,40
.quad fixture,304,256,-1,0,0,40
.quad fixture,304,257,-1,0,0,40
.quad fixture,304,258,-1,0,0,40
.quad fixture,304,259,-1,0,0,40
.quad fixture,304,260,-1,0,0,40
.quad fixture,304,261,-1,0,0,40
.quad fixture,304,262,-1,0,0,40
.quad fixture,304,263,-1,0,0,40
.quad fixture,304,264,-1,0,0,40
.quad fixture,304,265,-1,0,0,40
.quad fixture,304,266,-1,0,0,40
.quad fixture,304,267,-1,0,0,40
.quad fixture,304,268,-1,0,0,40
.quad fixture,304,269,-1,0,0,40
.quad fixture,304,270,-1,0,0,40
.quad fixture,304,271,-1,0,0,40
.quad fixture,304,272,-1,0,0,40
.quad fixture,304,273,-1,0,0,40
.quad fixture,304,274,-1,0,0,40
.quad fixture,304,275,-1,0,0,40
.quad fixture,304,276,-1,0,0,40
.quad fixture,304,277,-1,0,0,40
.quad fixture,304,278,-1,0,0,40
.quad fixture,304,279,-1,0,0,40
.quad fixture,304,280,-1,0,0,40
.quad fixture,304,281,-1,0,0,40
.quad fixture,304,282,-1,0,0,40
.quad fixture,304,283,-1,0,0,40
.quad fixture,304,284,-1,0,0,40
.quad fixture,304,285,-1,0,0,40
.quad fixture,304,286,-1,0,0,40
.quad fixture,304,287,-1,0,0,40
.quad fixture,304,288,-1,0,0,40
.quad fixture,304,289,-1,0,0,40
.quad fixture,304,290,-1,0,0,40
.quad fixture,304,291,-1,0,0,40
.quad fixture,304,292,-1,0,0,40
.quad fixture,304,293,-1,0,0,40
.quad fixture,304,294,-1,0,0,40
.quad fixture,304,295,-1,0,0,40
.quad fixture,304,296,-1,0,0,40
.quad fixture,304,297,-1,0,0,40
.quad fixture,304,298,-1,0,0,40
.quad fixture,304,299,-1,0,0,40
.quad fixture,304,300,-1,0,0,40
.quad fixture,304,301,-1,0,0,40
.quad fixture,304,302,-1,0,0,40
.quad fixture,304,303,-1,0,0,40
.quad fixture,304,305,-1,0,0,40
.quad fixture,304,262145,-1,0,0,40
.quad fixture,304,304,48,16,0,48
.quad fixture,304,304,52,55296,0,52
.quad fixture,304,304,52,4294967295,0,52
.quad fixture,304,304,56,1,0,56
.quad fixture,304,304,60,1,0,56
.quad fixture,304,304,68,1,0,68
.quad fixture,304,304,84,1,0,84
.quad fixture,304,304,88,1,0,88
.quad fixture,304,304,100,0,0,100
.quad fixture,304,304,100,5,0,100
.quad fixture,304,304,104,1,0,104
.quad fixture,304,304,116,0,0,116
.quad fixture,304,304,116,4,0,116
.quad fixture,304,304,120,1,0,120
.quad fixture,304,304,132,3,0,132
.quad fixture,304,304,136,0,0,132
.quad fixture,304,304,136,1,0,132
.quad fixture,304,304,136,4,0,132
.quad fixture,304,304,132,4294967294,0,132
.quad fixture,304,304,140,1,0,140
.quad fixture,304,304,148,14,0,148
.quad fixture,304,304,152,14,0,152
.quad fixture,304,304,156,1,0,156
.quad fixture,304,304,164,14,0,164
.quad fixture,304,304,168,1,0,168
.quad fixture,304,304,180,0,0,180
.quad fixture,304,304,180,2,0,180
.quad fixture,304,304,184,1,0,184
.quad fixture,304,304,196,1,0,196
.quad fixture,304,304,200,1,0,200
.quad fixture,304,304,212,1,0,212
.quad fixture,304,304,216,14,0,216
.quad fixture,304,304,220,14,0,220
.quad fixture,304,304,228,1,0,228
.quad fixture,304,304,232,14,0,232
.quad fixture,304,304,236,1,0,236
.quad fixture,304,304,244,14,0,244
.quad fixture,304,304,248,14,0,248
.quad fixture,304,304,252,4,0,252
.quad fixture,304,304,260,1,0,260
.quad fixture,304,304,264,1,0,260
.quad fixture,304,304,268,1,0,260
.quad fixture,304,304,272,1,0,272
.quad fixture,304,304,276,2,0,272
.quad fixture,304,304,280,55296,0,280
.quad fixture,304,304,280,123,0,280
.quad fixture,304,304,284,1114112,0,280
.quad fixture,304,304,288,2147483648,0,288
.quad fixture,304,304,292,2147483648,0,292
.quad fixture,304,304,296,2,0,296
.quad fixture,304,304,300,1,0,300
.quad fixture,304,304,100,2,1,0
.quad fixture,304,304,100,3,1,0
.quad fixture,304,304,100,4,1,0
.quad fixture,304,304,116,3,1,0
.quad fixture,304,304,252,0,1,0
.quad fixture,304,304,252,1,1,0
.quad fixture,304,304,252,2,1,0
.quad one,64,64,-1,0,1,0
.quad one,64,64,48,8,1,0
.quad one,64,64,48,2,0,48
.quad ranges,88,88,-1,0,1,0
.quad ranges,88,88,80,3,0,80
.quad ranges,88,88,80,2,0,80
.quad ranges,88,88,72,55295,0,72
.quad ranges,88,88,76,57344,0,72
.quad empty,88,88,-1,0,1,0
.quad empty,88,88,72,1,0,72
.quad unowned,72,72,-1,0,0,64
.quad 0,0,0,0,0,0,0
.p2align 3
scoped:
.long 0x58524e52,1,0x00100000,16,1,3,0,0,0,0,96,0
.long 14,3,6,0
.long 15,1,2,0
.long 0,0,0,0
