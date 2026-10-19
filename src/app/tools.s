# tools (wider-parity D3): tools extensions declare and rhun's own rhun.* tools, called by other
# extensions through rhun, with the user's confirmation for tools that change anything
.include "rhun.inc"

.text
# FN tools_ext_reset(ext): a record being (re)loaded drops its tools
FN tools_ext_reset
    ret

# FN tools_ext_gone(ext): an extension stopped: calls to its tools fail, its own calls end
FN tools_ext_gone
    ret

# FN tools_manifest_kv(ext, ini): one key of [tools]
FN tools_manifest_kv
    ret

# FN tools_propose_done(call, accepted, rejected): the review a rhun.propose call waits for is done
FN tools_propose_done
    ret
