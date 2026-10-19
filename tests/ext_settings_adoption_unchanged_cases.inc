# Same exact source bytes need no new source epoch, but still require model/ACK/source swap.
.text
svau_set_max:
    mov rax, 0x7fffffffffffffff
    mov rcx, [rip + svw_svc]
    mov [rcx + SV_source_epoch], rax
    ret
