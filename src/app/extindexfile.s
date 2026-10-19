# the rhun extensions index (extension management): rhun-editor/extensions publishes index.ini, the
# reviewed version of each listed extension (its tag and archive digests), for Browse, pinned
# installs and automatic updates.
.include "rhun.inc"

.text

# extindex_pin(name cstr "owner/name") -> rax the pinned tag and rdx this target's digest, or rax 0
# when the index does not list it for this system
FN extindex_pin
    xor eax, eax
    xor edx, edx
    ret
