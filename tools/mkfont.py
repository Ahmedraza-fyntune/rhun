#!/usr/bin/env python3
"""Copy a TrueType font keeping only the tables rhun reads."""
import struct, sys

KEEP = [b'OS/2', b'cmap', b'glyf', b'head', b'hhea', b'hmtx', b'loca', b'maxp', b'name', b'post']

def main(src, dst):
    data = open(src, 'rb').read()
    n = struct.unpack('>H', data[4:6])[0]
    tables = {}
    for i in range(n):
        tag, _, off, ln = struct.unpack('>4sIII', data[12 + 16*i:28 + 16*i])
        if tag in KEEP:
            tables[tag] = data[off:off + ln]
    tags = sorted(tables)
    out = bytearray(struct.pack('>IHHHH', 0x00010000, len(tags), 0, 0, 0))
    off = 12 + 16 * len(tags)
    body = bytearray()
    for tag in tags:
        t = tables[tag]
        pad = t + b'\0' * (-len(t) % 4)
        csum = sum(struct.unpack('>%dI' % (len(pad) // 4), pad)) & 0xffffffff
        out += struct.pack('>4sIII', tag, csum, off + len(body), len(t))
        body += pad
    open(dst, 'wb').write(out + body)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
