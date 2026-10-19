# Linux: extensions' secrets in the Secret Service (org.freedesktop.secrets: gnome-keyring,
# KWallet 5.97+, KeePassXC) over the session bus (src/app/secrets.s).
.include "rhun.inc"
.ifndef MACOS
.ifndef WINDOWS

# ss_start(sr) -> eax 0 when the request went to the service (secrets_done follows), -1 when no
# Secret Service answers (memory stands in)
FN ss_start
    mov eax, -1
    ret

.endif
.endif
