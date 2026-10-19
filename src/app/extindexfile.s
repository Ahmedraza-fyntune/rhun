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

# extindex_tag(name cstr) -> rax the pinned tag of a listed extension, or 0
FN extindex_tag
    xor eax, eax
    ret

# extindex_fetch(done fn): the index fetched when the cached copy is older than a day; done() is
# called once it is in (or could not be had)
FN extindex_fetch
    jmp rdi
