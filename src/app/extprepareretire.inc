# Private retirement prefix, outside all public object payload layouts.
.equ RD_next, 0
.equ RD_object, 8
.equ RD_kind, 16
.equ RD_phase, 24
.equ RD_index, 32
.equ RD_diagnostic, 40
.equ RD_native, 48
.equ RD_state, 56
.equ RD_SIZE, 64
.equ RD_PO_BACK, RD_SIZE + AO_SIZE
.equ RD_EO, 1
.equ RD_LEDGER, 2
.equ RD_EP, 3
.equ RD_ACTIVE, 0
.equ RD_READY, 1
.equ RD_BLOCKED_KNOWN, 2
.equ RD_BLOCKED_UNKNOWN, 3
.equ RD_RUNNING, 4
.equ RDF_PO, 256
.equ PREP_TOTAL_CAP, 256 * 1024 * 1024
.equ RDF_STATE_MASK, 255
.equ RDF_UNKNOWN_BASE, 16
.equ RDF_KNOWN_BASE, 20
.equ RDF_KNOWN_MASK, 7 << RDF_KNOWN_BASE
.equ RDF_NATIVE_MASK, (7 << RDF_UNKNOWN_BASE) | RDF_KNOWN_MASK

# Callback registry capacity; instance ownership and numeric kinds1..7 unchanged.
.equ RD_CUSTOM_FIRST, 4
.equ RD_CUSTOM_LAST, 8
.equ RD_CUSTOM_COUNT, 9
