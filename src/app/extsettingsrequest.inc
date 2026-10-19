# REQUEST-only producer. Cursor borrows the outer owner's exact frame and batch.
.include "app/extsettingsqueue.inc"
.include "app/extsettingsframe.inc"
.equ SRQ_tag, 0
.equ SRQ_path, 8
.equ SRQ_length, 16
.equ SRQ_batch, 24
.equ SRQ_mode, 32
.equ SRQ_SIZE, 40
.equ ESQ_frame, 0
.equ ESQ_batch, 8
.equ ESQ_count, 16
.equ ESQ_row, 24
.equ ESQ_span, 32
.equ ESQ_offset, 40
.equ ESQ_pos, 48
.equ ESQ_magic, 56
.equ ESQ_SIZE, 64
.equ ESQ_ACTIVE, 0x31514553554e4852
.equ ESQ_DONE, 0x32514553554e4852
.if SRQ_mode + 8 != SRQ_SIZE
.error "REQUEST input descriptor size mismatch"
.endif
.if ESQ_magic + 8 != ESQ_SIZE
.error "REQUEST cursor size mismatch"
.endif
