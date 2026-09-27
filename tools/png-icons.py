#!/usr/bin/env python3
# Writes assets/icons/rhun-256.png and rhun-512.png: assets/icons/rhun.svg as PNG, for the launchers
# and docks on Linux that do not draw SVG; drawn with the distance fields of tools/mac-icon.py.
# usage: tools/png-icons.py
import importlib.util
import os
import sys

sys.dont_write_bytecode = True

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('mac_icon', os.path.join(here, 'mac-icon.py'))
mac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mac)


def render(n):
    unit = n / 64                     # svg units -> pixels
    c = 32 * unit
    half = 28 * unit                  # the 56 unit body at (4, 4)
    radius = 12.5 * unit
    rune = [((a[0] * unit, a[1] * unit), (b[0] * unit, b[1] * unit)) for a, b in mac.RUNE]
    sw = mac.STROKE * unit / 2
    rows = []
    for y in range(n):
        row = bytearray()
        py = y + 0.5
        for x in range(n):
            px = x + 0.5
            a = min(1, max(0, 0.5 - mac.rrect(px, py, c, c, half, radius)))
            if a <= 0:
                row += b'\0\0\0\0'
                continue
            dr = min(mac.segment(px, py, p, q) for p, q in rune) - sw
            k = min(1, max(0, 0.5 - dr))
            row += bytes([round(bg + (fg - bg) * k) for bg, fg in zip(mac.BG, mac.FG)] + [round(a * 255)])
        rows.append(bytes(row))
    return rows


def main():
    for n in (256, 512):
        mac.png(os.path.join(here, '..', 'assets', 'icons', 'rhun-%d.png' % n), render(n), n)


if __name__ == '__main__':
    main()
