#!/usr/bin/env python3
"""Renders Support/AppIcon.png (1024x1024) with analytic anti-aliasing.

Pure stdlib: shapes are signed distance fields, coverage is clamped distance,
and the canvas is packed into an RGBA PNG with zlib. Run from the repo root.
"""
import math, struct, zlib, os

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "Support", "AppIcon.png")


def rounded_box(px, py, half, radius):
    qx = abs(px) - (half - radius)
    qy = abs(py) - (half - radius)
    ax, ay = max(qx, 0.0), max(qy, 0.0)
    outside = math.hypot(ax, ay)
    inside = min(max(qx, qy), 0.0)
    return outside + inside - radius


def segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = (wx * vx + wy * vy) / (vx * vx + vy * vy)
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return math.hypot(wx - vx * t, wy - vy * t)


def lerp(a, b, t):
    return a + (b - a) * t


TOP = (79, 70, 229)      # indigo 600
BOTTOM = (124, 58, 237)  # violet 600
GLYPH = (255, 255, 255)

rows = []
for y in range(S):
    row = bytearray()
    for x in range(S):
        px = x + 0.5 - S / 2
        py = y + 0.5 - S / 2

        d_bg = rounded_box(px, py, S / 2 - 48, 190)
        bg_cov = min(max(0.5 - d_bg, 0.0), 1.0)
        if bg_cov <= 0.0:
            row += b"\x00\x00\x00\x00"
            continue

        t = (y / (S - 1)) ** 0.85
        # subtle diagonal sheen
        t = min(1.0, max(0.0, t * 0.9 + (x / (S - 1)) * 0.1))
        r = lerp(TOP[0], BOTTOM[0], t)
        g = lerp(TOP[1], BOTTOM[1], t)
        b = lerp(TOP[2], BOTTOM[2], t)

        # glyph: ">_" prompt
        d1 = segment(px, py, -170, -150, 20, 0) - 44
        d2 = segment(px, py, 20, 0, -170, 150) - 44
        d3 = segment(px, py, 80, 150, 205, 150) - 34
        d_glyph = min(d1, d2, d3)
        g_cov = min(max(0.5 - d_glyph, 0.0), 1.0)

        r = lerp(r, GLYPH[0], g_cov)
        g = lerp(g, GLYPH[1], g_cov)
        b = lerp(b, GLYPH[2], g_cov)

        a = int(round(255 * bg_cov))
        row += bytes((int(round(r)), int(round(g)), int(round(b)), a))
    rows.append(bytes(row))

raw = b"".join(b"\x00" + r for r in rows)


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as handle:
    handle.write(png)
print("wrote %s (%d bytes)" % (os.path.normpath(OUT), len(png)))
