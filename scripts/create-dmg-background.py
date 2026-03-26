#!/usr/bin/env python3
"""
Generate a DMG background image with an arrow pointing from app icon to Applications folder.
Dimensions: 660x400 (standard DMG window with Retina support).
"""

import struct
import zlib
import math
import os

WIDTH = 660
HEIGHT = 400

# We'll create a 2x image for Retina (1320x800) but the logical DMG window is 660x400
# Actually, create-dmg handles Retina via --hdiutil-quiet. Let's do 660x400 standard.

def create_png(width, height, pixels):
    """Create PNG from pixel data. pixels is a list of rows, each row is list of (r,g,b,a) tuples."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for row in pixels:
        raw += b'\x00'  # filter: none
        for r, g, b, a in row:
            raw += struct.pack('BBBB', r, g, b, a)

    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')

    return header + ihdr + idat + iend


def lerp(a, b, t):
    return int(a + (b - a) * t)


def draw_background(width, height):
    """Draw a clean gradient background."""
    pixels = []
    for y in range(height):
        row = []
        t = y / height
        # Subtle gradient: light gray top to slightly darker bottom
        r = lerp(245, 228, t)
        g = lerp(245, 228, t)
        b = lerp(248, 232, t)
        for x in range(width):
            row.append((r, g, b, 255))
        pixels.append(row)
    return pixels


def draw_arrow(pixels, width, height):
    """Draw a stylized arrow between the app position and Applications position."""
    # App icon center: ~165, 180  (left side)
    # Applications center: ~495, 180  (right side)
    # Arrow should go roughly from x=230 to x=430, centered at y=180

    arrow_y = 180
    arrow_x_start = 235
    arrow_x_end = 425
    arrow_color = (120, 120, 130, 180)  # semi-transparent gray
    shaft_thickness = 3

    # Draw shaft
    for x in range(arrow_x_start, arrow_x_end - 20):
        for dy in range(-shaft_thickness, shaft_thickness + 1):
            y = arrow_y + dy
            if 0 <= y < height and 0 <= x < width:
                # Alpha blend
                r0, g0, b0, a0 = pixels[y][x]
                r1, g1, b1, a1 = arrow_color
                alpha = a1 / 255.0
                r = int(r0 * (1 - alpha) + r1 * alpha)
                g = int(g0 * (1 - alpha) + g1 * alpha)
                b = int(b0 * (1 - alpha) + b1 * alpha)
                pixels[y][x] = (r, g, b, 255)

    # Draw arrowhead (triangle pointing right)
    head_tip_x = arrow_x_end
    head_base_x = arrow_x_end - 35
    head_half_height = 16

    for x in range(head_base_x, head_tip_x + 1):
        progress = (x - head_base_x) / (head_tip_x - head_base_x)
        half_h = int(head_half_height * (1 - progress))
        for dy in range(-half_h, half_h + 1):
            y = arrow_y + dy
            if 0 <= y < height and 0 <= x < width:
                r0, g0, b0, a0 = pixels[y][x]
                r1, g1, b1, a1 = arrow_color
                # Softer edge
                edge_dist = abs(abs(dy) - half_h)
                alpha = (a1 / 255.0) * min(1.0, edge_dist / 2.0 + 0.3)
                r = int(r0 * (1 - alpha) + r1 * alpha)
                g = int(g0 * (1 - alpha) + g1 * alpha)
                b = int(b0 * (1 - alpha) + b1 * alpha)
                pixels[y][x] = (r, g, b, 255)

    return pixels


def draw_text_label(pixels, width, height):
    """Draw a subtle instruction text area at the bottom."""
    # We'll draw a subtle darker band at the bottom with no actual text
    # (text rendering in pure Python is complex; the icons + arrow are self-explanatory)
    # create-dmg will show the app name under each icon automatically
    return pixels


def main():
    pixels = draw_background(WIDTH, HEIGHT)
    pixels = draw_arrow(pixels, WIDTH, HEIGHT)
    pixels = draw_text_label(pixels, WIDTH, HEIGHT)

    png_data = create_png(WIDTH, HEIGHT, pixels)

    out_dir = os.path.join(os.path.dirname(__file__), 'dmg-resources')
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, 'dmg-background.png')

    with open(out_path, 'wb') as f:
        f.write(png_data)

    print(f"✅ Created {out_path} ({WIDTH}x{HEIGHT})")


if __name__ == '__main__':
    main()
