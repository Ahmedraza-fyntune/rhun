# Distinct initial legacy snapshot transcript, little-endian and fully counted.
.equ LS_HEADER, 192
.equ LS_CAP, 18 * 1024 * 1024
.equ LS_total, 16
.equ LS_count, 24
.equ LS_tag, 32
.equ LS_source, 96
.equ LS_primary, 128
.equ LS_secondary, 136
.equ LS_programlen, 144
.equ LS_scriptlen, 148
.equ LS_drive, 152
.equ LS_reserved, 156
.equ LR_pathlen, 0
.equ LR_roles, 4
.equ LR_size, 8
.equ LR_exec, 16
.equ LR_hash, 24
.equ LR_datalen, 56
.equ LR_SIZE, 80
.equ LI_dir, 0
.equ LI_owner, 8
.equ LI_name, 16
.equ LI_tag, 24
.equ LI_lease, 32
.equ LI_drive, 40
.equ LI_cwd, 48
.equ LI_SIZE, 56
