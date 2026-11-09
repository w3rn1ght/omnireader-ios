#!/usr/bin/env python3
"""Generate the OmniReader icon set without external dependencies.

Draws a flat "open book" mark on a warm gradient and downsamples it with a box
filter. Run from the repository root: python Tools/make_icons.py
"""
import math
import pathlib
import struct
import zlib

SIZE = 1024
OUT = pathlib.Path(__file__).resolve().parents[1] / "Resources"

def blend(dst, src, alpha):
    return tuple(int(s * alpha + d * (1 - alpha)) for s, d in zip(src, dst))

def rounded_rect(px, w, h, x0, y0, x1, y1, radius, color, alpha=1.0):
    for y in range(max(0, int(y0)), min(h, int(y1))):
        for x in range(max(0, int(x0)), min(w, int(x1))):
            dx = min(max(x0 + radius - x, 0), max(x - (x1 - radius), 0))
            dy = min(max(y0 + radius - y, 0), max(y - (y1 - radius), 0))
            if dx * dx + dy * dy <= radius * radius:
                i = (y * w + x) * 4
                px[i:i+3] = blend(px[i:i+3], color, alpha)

def triangle(px, w, h, p1, p2, p3, color, alpha=1.0):
    def edge(a, b, p):
        return (p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0])
    xs = [p[0] for p in (p1, p2, p3)]
    ys = [p[1] for p in (p1, p2, p3)]
    for y in range(max(0, int(min(ys))), min(h, int(max(ys)) + 1)):
        for x in range(max(0, int(min(xs))), min(w, int(max(xs)) + 1)):
            p = (x + 0.5, y + 0.5)
            e1, e2, e3 = edge(p1, p2, p), edge(p2, p3, p), edge(p3, p1, p)
            if (e1 >= 0 and e2 >= 0 and e3 >= 0) or (e1 <= 0 and e2 <= 0 and e3 <= 0):
                i = (y * w + x) * 4
                px[i:i+3] = blend(px[i:i+3], color, alpha)

def make_master():
    px = bytearray(SIZE * SIZE * 4)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        top = (34, 43, 58)
        bottom = (18, 22, 31)
        color = tuple(int(a + (b - a) * t) for a, b in zip(top, bottom))
        for x in range(SIZE):
            i = (y * SIZE + x) * 4
            px[i:i+4] = bytes((*color, 255))

    cream = (240, 232, 214)
    page = (252, 249, 241)
    accent = (226, 122, 58)

    # Left and right pages of an open book.
    rounded_rect(px, SIZE, SIZE, 176, 300, 508, 760, 26, cream)
    rounded_rect(px, SIZE, SIZE, 516, 300, 848, 760, 26, cream)
    rounded_rect(px, SIZE, SIZE, 196, 322, 496, 738, 14, page)
    rounded_rect(px, SIZE, SIZE, 528, 322, 828, 738, 14, page)
    # Spine shadow.
    rounded_rect(px, SIZE, SIZE, 496, 300, 528, 760, 8, (206, 196, 176))
    # Text lines.
    for index in range(9):
        y = 372 + index * 34
        rounded_rect(px, SIZE, SIZE, 232, y, 464, y + 9, 4, (198, 188, 168), 0.9)
        rounded_rect(px, SIZE, SIZE, 560, y, 792, y + 9, 4, (198, 188, 168), 0.9)
    # Bookmark.
    triangle(px, SIZE, SIZE, (652, 300), (716, 300), (684, 418), accent)
    # Small "play" badge to hint at audiobooks.
    cx, cy, r = 512, 828, 92
    for y in range(cy - r, cy + r):
        for x in range(cx - r, cx + r):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                i = (y * SIZE + x) * 4
                px[i:i+3] = blend(px[i:i+3], accent, 1.0)
    triangle(px, SIZE, SIZE, (492, 786), (492, 870), (558, 828), (255, 250, 242))
    return px

def downsample(px, size, target):
    factor = size // target
    out = bytearray(target * target * 4)
    for y in range(target):
        for x in range(target):
            r = g = b = a = 0
            for dy in range(factor):
                base = ((y * factor + dy) * size + x * factor) * 4
                for dx in range(factor):
                    i = base + dx * 4
                    r += px[i]; g += px[i+1]; b += px[i+2]; a += px[i+3]
            n = factor * factor
            i = (y * target + x) * 4
            out[i:i+4] = bytes((r // n, g // n, b // n, a // n))
    return out

def write_png(path, px, size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw += px[y * size * 4:(y + 1) * size * 4]
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    master = make_master()
    targets = {
        "Icon-1024.png": 1024,
        "Icon-83.5@2x.png": 167,
        "Icon-76@2x.png": 152,
        "Icon-76.png": 76,
        "Icon-60@3x.png": 180,
        "Icon-60@2x.png": 120,
        "Icon-40@3x.png": 120,
        "Icon-40@2x.png": 80,
        "Icon-29@3x.png": 87,
        "Icon-29@2x.png": 58,
        "Icon-20@3x.png": 60,
        "Icon-20@2x.png": 40,
    }
    for name, size in targets.items():
        if size == 1024:
            data = master
        else:
            data = downsample(master, SIZE, size)
        write_png(OUT / name, data, size)
        print("wrote", name, size)

if __name__ == "__main__":
    main()
