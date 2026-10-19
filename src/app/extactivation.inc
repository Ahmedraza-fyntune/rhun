# Native activation evidence and lifetime owner. Freshness is checked by the coordinator/keeper.
.equ EA_KIND, 6
.equ EA_MANAGED, 1
.equ EA_LEGACY, 2
.equ EA_ep, 40
.equ EA_proof_kind, 48
.equ EA_source, 56
.equ EA_tree, 88
.equ EA_wirelen, 120
.equ EA_plan, 128
.equ EA_wire, 256
.equ EA_SIZE, EA_wire + KA_MAX
.equ EAP_kind, 0
.equ EAP_source, 8
.equ EAP_tree, 40
.equ EAP_context, 72
.equ EAP_SIZE, 80
