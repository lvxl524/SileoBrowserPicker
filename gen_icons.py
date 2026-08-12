#!/usr/bin/env python3
"""Generate icon PNGs for SileoBrowserPicker using only stdlib (struct + zlib)."""

import struct
import zlib
import math
import os

def write_png(filename, width, height, pixels):
    """Write RGBA pixels to a PNG file."""
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        for x in range(width):
            r, g, b, a = pixels[y][x]
            raw.extend([r, g, b, a])

    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(sig + ihdr + idat + iend)
    print(f"  Written: {filename} ({width}x{height})")


def in_rounded_rect(x, y, w, h, r):
    """Check if point (x,y) is inside a rounded rectangle."""
    # x, y are pixel coordinates (0-based)
    # Check corners
    if x < r and y < r:
        return (r - x) ** 2 + (r - y) ** 2 <= r * r
    if x >= w - r and y < r:
        return (x - (w - r - 1)) ** 2 + (r - y) ** 2 <= r * r
    if x < r and y >= h - r:
        return (r - x) ** 2 + (y - (h - r - 1)) ** 2 <= r * r
    if x >= w - r and y >= h - r:
        return (x - (w - r - 1)) ** 2 + (y - (h - r - 1)) ** 2 <= r * r
    return True


def generate_icon(size):
    """Generate icon pixel data at given size."""
    pixels = []
    cx = (size - 1) / 2.0
    cy = (size - 1) / 2.0
    corner_r = size * 0.22

    # Globe parameters
    globe_r = size * 0.30
    lw = max(1.2, size / 24.0)  # line width scales with icon size

    for y in range(size):
        row = []
        for x in range(size):
            # Default: transparent
            r, g, b, a = 0, 0, 0, 0

            if not in_rounded_rect(x, y, size, size, corner_r):
                row.append((r, g, b, a))
                continue

            # Background gradient: top-left #4A90D9 -> bottom-right #2E5C8A
            t = (x + y) / (2.0 * (size - 1))
            t = max(0.0, min(1.0, t))
            r = int(74 + (46 - 74) * t)
            g = int(144 + (92 - 144) * t)
            b = int(217 + (138 - 217) * t)
            a = 255

            dx = x - cx
            dy = y - cy
            dist = math.sqrt(dx * dx + dy * dy)

            if dist <= globe_r + lw:
                # Globe outline
                if abs(dist - globe_r) < lw:
                    r, g, b = 255, 255, 255
                elif dist < globe_r:
                    drawn = False

                    # Vertical meridian (ellipse: narrower in x)
                    ex = dx / (globe_r * 0.45)
                    ey = dy / globe_r
                    ed = math.sqrt(ex * ex + ey * ey)
                    if abs(ed - 1.0) < lw / globe_r * 0.8:
                        r, g, b = 255, 255, 255
                        drawn = True

                    # Equator (horizontal line)
                    if not drawn and abs(dy) < lw * 0.8 and dist < globe_r - lw:
                        r, g, b = 255, 255, 255
                        drawn = True

                    # Prime meridian (vertical line through center)
                    if not drawn and abs(dx) < lw * 0.8 and dist < globe_r - lw:
                        r, g, b = 255, 255, 255
                        drawn = True

            row.append((r, g, b, a))
        pixels.append(row)

    return pixels


def main():
    out_dir = os.path.dirname(os.path.abspath(__file__))
    resources_dir = os.path.join(out_dir, 'sileopickerprefs', 'Resources')
    layout_dir = os.path.join(out_dir, 'layout', 'Library', 'PreferenceLoader', 'Preferences')

    os.makedirs(resources_dir, exist_ok=True)
    os.makedirs(layout_dir, exist_ok=True)

    sizes = [
        ('icon.png', 29),
        ('icon@2x.png', 58),
        ('icon@3x.png', 87),
        ('icon-512.png', 512),
    ]

    print("Generating icons...")
    for name, sz in sizes:
        pixels = generate_icon(sz)
        # Write to bundle resources
        write_png(os.path.join(resources_dir, name), sz, sz, pixels)
        # Write to layout (only the small icons needed for PreferenceLoader entry)
        if name != 'icon-512.png':
            write_png(os.path.join(layout_dir, name), sz, sz, pixels)

    print("Done!")


if __name__ == '__main__':
    main()
