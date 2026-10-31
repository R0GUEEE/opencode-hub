#!/usr/bin/env python3
"""Slices Support/AppIcon.png into the AppIcon.appiconset.

Stdlib only: decodes the master PNG, box-downsamples by integer factors and
re-encodes every size the asset catalog asks for, so the icons are committed
and Xcode can build without sips or a pre-build phase.
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(ROOT, "Support", "AppIcon.png")
OUT = os.path.join(ROOT, "Resources", "Assets.xcassets", "AppIcon.appiconset")

TARGETS = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s is not a PNG" % path)
    pos, width, height, depth, color = 8, None, None, None, None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if depth != 8 or color not in (2, 6):
        raise SystemExit("expected an 8-bit RGB/RGBA PNG")
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows, previous, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if kind == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        rows.append(line)
        previous = line
    if channels == 3:
        expanded = []
        for row in rows:
            out = bytearray(width * 4)
            for x in range(width):
                out[x * 4:x * 4 + 3] = row[x * 3:x * 3 + 3]
                out[x * 4 + 3] = 255
            expanded.append(out)
        rows = expanded
    return width, height, rows


def downsample(rows, factor):
    height = len(rows) // factor
    width = len(rows[0]) // 4 // factor
    out = []
    for y in range(height):
        line = bytearray(width * 4)
        for x in range(width):
            r = g = b = a = 0
            for dy in range(factor):
                src = rows[y * factor + dy]
                for dx in range(factor):
                    i = (x * factor + dx) * 4
                    alpha = src[i + 3]
                    r += src[i] * alpha
                    g += src[i + 1] * alpha
                    b += src[i + 2] * alpha
                    a += alpha
            if a == 0:
                r = g = b = 0
            else:
                r, g, b = r // a, g // a, b // a
            line[x * 4:x * 4 + 4] = bytes((r, g, b, a // (factor * factor)))
        out.append(line)
    return out


def write_png(path, rows):
    width, height = len(rows[0]) // 4, len(rows)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def main():
    width, _, rows = read_png(MASTER)
    os.makedirs(OUT, exist_ok=True)
    cache = {}
    for size, name in TARGETS:
        if width % size:
            raise SystemExit("master is %dpx; %d does not divide evenly" % (width, size))
        factor = width // size
        if factor not in cache:
            cache[factor] = downsample(rows, factor)
        write_png(os.path.join(OUT, name), cache[factor])
        print("  %-22s %dx%d" % (name, size, size))
    print("wrote %d icons" % len(TARGETS))


if __name__ == "__main__":
    main()
