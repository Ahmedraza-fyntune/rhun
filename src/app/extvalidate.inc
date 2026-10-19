# Isolated managed validation and raw-handle rooted filesystem contract.
# open/open_at/reopen_dir: RAX owned handle or negative primary errno; RDX 0 or
# first negative mandatory cleanup errno. Success always has RDX=0. A negative
# secondary error must prevent interpreting primary ENOENT as clean absence.
.equ EV_BAD_ID, 1001
.equ EV_BAD_PATH, 1002
.equ EV_BAD_MANIFEST, 1003
.equ EV_BAD_SETTINGS, 1004
.equ EV_BAD_EXEC, 1005
.equ EV_BAD_RUNTIME, 1006
.equ EV_RESOURCE, 1007
.equ EV_CHANGED, 1008
.equ EV_IO, 1009
.equ EV_USAGE, 1010
.equ ER_FILE, 1
.equ ER_DIR, 2
.equ ER_ANY, 3
.equ ER_WRITE, 1
.equ ER_CREATE, 2
.equ ER_EXCL, 4
.equ ER_DELETE, 8
.equ ER_kind, 0
.equ ER_size, 8
.equ ER_exec, 16
.equ ER_STAT_SIZE, 32

.equ EV_BAD_GRAMMAR, 1011
.equ EV_BAD_THEME, 1012
.equ EV_BAD_ASSET, 1013
.equ EV_BAD_PREPARE, 1014
