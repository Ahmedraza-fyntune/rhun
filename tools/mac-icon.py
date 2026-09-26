#!/usr/bin/env python3
# Writes assets/icons/rhun.icns: the icon of assets/icons/rhun.svg on the macOS icon grid
# (an 824 px body with a soft shadow on a 1024 px canvas), drawn with distance fields.
# usage: tools/mac-icon.py   (needs iconutil, part of macOS)
import math
import os
import struct
import subprocess
import tempfile
import zlib

BG = (0x1c, 0x1e, 0x24)
FG = (0x8a, 0xa4, 0xff)
# the rune of rhun.svg, in its 64 unit box: strokes 4.8 wide on a 56 unit body at (4, 4)
RUNE = [((25, 17.1), (25, 46.9)), ((25, 17.1), (37.25, 25)), ((37.25, 25), (25, 32.9)),
        ((25, 32.9), (39, 46.9))]
STROKE = 4.8


def rrect(px, py, cx, cy, half, r):
    """signed distance to a rounded square"""
    qx = abs(px - cx) - half + r
    qy = abs(py - cy) - half + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def segment(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = min(1, max(0, t))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def render(n):
    s = n / 1024
    body = 824 * s
    half = body / 2
    c = n / 2
    radius = 185.4 * s
    unit = body / 56                  # svg units -> pixels
    rune = [((c + (a[0] - 32) * unit, c + (a[1] - 32) * unit),
             (c + (b[0] - 32) * unit, c + (b[1] - 32) * unit)) for a, b in RUNE]
    sw = STROKE * unit / 2
    blur = 22 * s
    rows = []
    for y in range(n):
        row = bytearray()
        py = y + 0.5
        for x in range(n):
            px = x + 0.5
            d = rrect(px, py, c, c, half, radius)
            body_a = min(1, max(0, 0.5 - d))
            # shadow: the body, lower and blurred
            ds = rrect(px, py - 12 * s, c, c, half, radius)
            t = min(1, max(0, (ds + blur) / (2 * blur)))
            shadow = 0.32 * (1 - t * t * (3 - 2 * t))
            r, g, b = BG
            if body_a > 0:
                dr = min(segment(px, py, p, q) for p, q in rune) - sw
                k = min(1, max(0, 0.5 - dr))
                r = BG[0] + (FG[0] - BG[0]) * k
                g = BG[1] + (FG[1] - BG[1]) * k
                b = BG[2] + (FG[2] - BG[2]) * k
            # body over shadow (black), premultiplied then straight alpha
            a = body_a + shadow * (1 - body_a)
            if a <= 0:
                row += b'\0\0\0\0'
                continue
            row += bytes((round(r * body_a / a), round(g * body_a / a), round(b * body_a / a),
                          round(a * 255)))
        rows.append(bytes(row))
    return rows


def png(path, rows, n):
    raw = b''.join(b'\0' + r for r in rows)

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0)) +
                chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, 'rhun.iconset')
        os.mkdir(iconset)
        done = {}
        for size in (16, 32, 128, 256, 512):
            for k in (1, 2):
                n = size * k
                if n not in done:
                    done[n] = render(n)
                name = 'icon_%dx%d%s.png' % (size, size, '@2x' if k == 2 else '')
                png(os.path.join(iconset, name), done[n], n)
        subprocess.check_call(['iconutil', '-c', 'icns', iconset, '-o',
                               os.path.join(root, 'assets', 'icons', 'rhun.icns')])


if __name__ == '__main__':
    main()
