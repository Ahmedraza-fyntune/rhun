# Independent immutable host identity, using the generic charged PO ledger.
.equ HI_magic, 40
.equ HI_owner, 48
.equ HI_name, 56
.equ HI_state, 64
.equ HI_bytes, 72
.equ HI_SIZE, 80
.equ HI_MAGIC, 0x314954534f484852
.equ HI_DIAGNOSTIC, 1
.equ HI_CAP, 65536
.equ HI_MAX, HI_SIZE + 100 + 100 + 4095 + 3
