.equ KSI_MAGIC, 0x4b534931
.equ KSI_magic, 40
.equ KSI_epoch, 48
.equ KSI_nrows, 56
.equ KSI_bytes, 64
.equ KSI_row, 72
.equ KSI_phase, 80
.equ KSI_offset, 88
.equ KSI_open, 96
.equ KSI_creation, 104
.equ KSI_rows, 128
.equ KSI_MAX_ROWS, 4096
.equ KSI_MAX_BYTES, 1024 * 1024
.equ KSI_ROW, 1
.equ KSI_COMBO, 2
.equ KSI_COMMAND, 3
.equ KSI_FINISH, 4
.equ KSI_READY, 5
.equ KSC_ksi, 0
.equ KSC_cg, 8
.equ KSC_row, 16
.equ KSC_phase, 24
.equ KSC_offset, 32
.equ KSC_error, 40
.equ KSC_done, 48
.equ KSC_SIZE, 64

# Typed immutable source of a cursor; kind0 preserves existing zero cursor ABI.
.equ KSC_kind, 56
.equ KSC_KSI, 0
.equ KSC_CG, 1
