# Same-map settings adoption. SVC registration is borrowed, SAP retains SVC.
.include "app/extsettingsservice.inc"
.equ SAP_MAGIC, 0x31504153554e4852
.equ AP_magic, 0
.equ AP_refs, 8
.equ AP_next, 16
.equ AP_svc, 24
.equ AP_pending, 32
.equ AP_oldmodel, 40
.equ AP_oldsource, 48
.equ AP_retiredsource, 56
.equ AP_plan, 64
.equ AP_ticket, 72
.equ AP_pendingepoch, 80
.equ AP_sourceepoch, 88
.equ AP_context, 96
.equ AP_registry, 104
.equ AP_model, 112
.equ AP_provider, 120
.equ AP_dirty, 128
.equ AP_sequence, 136
.equ AP_batch, 144
.equ AP_batchphase, 152
.equ AP_commit, 160
.equ AP_changed, 168
.equ AP_futureepoch, 176
.equ AP_state, 184
.equ AP_phase, 192
.equ AP_index, 200
.equ AP_count, 208
.equ AP_dropindex, 216
.equ AP_error, 224
.equ AP_cleanup, 232
.equ AP_rebuild, 240
.equ AP_retiredue, 248
.equ AP_retiredelay, 256
.equ AP_views, 320
.equ AP_rows, AP_views + 128 * 8
.equ AP_SIZE, AP_rows + 128 * ECSR_SIZE
.equ APS_BUILDING, 1
.equ APS_READY, 2
.equ APS_EXPORTED, 3
.equ APS_PUBLISHED, 4
.equ APS_CANCELED, 5
.equ APS_RETIRED, 6
.equ APP_NEXT, 1
.equ APP_VIEW, 2
.equ APP_PLAN, 3
.equ APP_PLANSTEP, 4
.equ APP_DROPS, 5
.equ APP_READY, 6
.if AP_SIZE != 5440
.error "settings adoption owned allocation shape changed"
.endif
.if AP_retiredelay + 8 > AP_views
.error "settings adoption header overlaps retained view slots"
.endif
