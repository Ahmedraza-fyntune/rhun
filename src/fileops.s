# Namespace and coordination primitives for managed extension transactions.
# Callers own regular-file descriptors, stable lock names and prepared paths.
.include "rhun.inc"
.text
# file_lock_try(fd, exclusive=0|1) -> 0 or -errno. One lock per independent
# descriptor. No upgrade/downgrade or reentrant acquisition; never waits.
FN file_lock_try
    cmp rsi, 1
    ja .Lfop_invalid
.ifdef WINDOWS
    jmp win_file_lock_try
.else
    inc esi                    # LOCK_SH=1, LOCK_EX=2
    or esi, 4                  # LOCK_NB
    SYS SYS_flock
    ret
.endif

# file_lock_release(fd) -> 0 or -errno. Descriptor remains caller-owned/open.
# Requires one held lock acquired through file_lock_try.
FN file_lock_release
.ifdef WINDOWS
    jmp win_file_lock_release
.else
    mov esi, 8                 # LOCK_UN
    SYS SYS_flock
    ret
.endif

# file_publish_new(source, destination) -> 0 or -errno. Distinct paths in one
# prepared directory; never replaces, copies across volumes or undoes a rename.
# Native failure can be ambiguous: caller must inspect final under its lock.
FN file_publish_new
    test rdi, rdi
    jz .Lfop_invalid
    test rsi, rsi
    jz .Lfop_invalid
.ifdef WINDOWS
    jmp win_file_publish_new
.else
.ifdef MACOS
    SYS SYS_rename_new
.else
    mov r10, rsi
    mov rsi, rdi
    mov rdi, -100              # AT_FDCWD
    mov rdx, -100
    mov r8d, 1                 # RENAME_NOREPLACE
    SYS SYS_renameat2
.endif
    ret
.endif
.Lfop_invalid:
    mov rax, -22
    ret
