# Prepared discovery partial construction. All pointers are trusted native owners.
.equ DIA_state, 0
.equ DIA_cursor, 8
.equ DIA_primary, 16
.equ DIA_cleanup, 24
.equ DIA_active, 48
.equ DIA_blocked, 56
.equ DIA_eo, 64
.equ DIA_ep, 72
.equ DIA_gp, 80
.equ DIA_settings, 88
.equ DIA_settings_cap, 96
.equ DIA_settings_len, 104
.equ DIA_grammars, 112
.equ DIA_grammars_cap, 120
.equ DIA_slots, 128
.equ DIA_SIZE, 1152
.equ DIA_ACTIVE, 0
.equ DIA_ABORT, 1
.equ DIA_EMPTY, 2
.equ DTS_raw, 0
.equ DTS_request, 8
.equ DTS_charge, 16
.equ DTS_initialized, 24
.equ DTS_kind, 32
.equ DTS_state, 40
.equ DTS_logical, 48
.equ DTS_due, 56
.equ DTS_SIZE, 64
.equ DTS_EMPTY, 0
.equ DTS_RAW, 1
.equ DTS_INITIALIZED, 2
.equ DTS_RETAINED, 3
.equ PD_EXTRA, 1
.equ PD_EO, 2
.equ PD_EP, 3
.equ PD_GP, 4
.equ PD_MEMBER, 5
.equ PD_VALUE, 6
.equ PD_EXTRA_CAP, 80 * 1024 * 1024
.equ PD_FOREIGN_CAP, 160 * 1024 * 1024
.equ PD_COMBINED_CAP, 512 * 1024 * 1024
