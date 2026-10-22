# Owned exact pending manifest identity. Header followed by owner/name/key NUL strings.
.equ PN_refs, 0
.equ PN_target, 8
.equ PN_revision, 16
.equ PN_ownerlen, 24
.equ PN_namelen, 32
.equ PN_keylen, 40
.equ PN_size, 48
.equ PN_inv, 56              # owned copy of how it was invoked (INV + body), or 0
.equ PN_SIZE, 64
.equ PN_LIMIT, 65536
