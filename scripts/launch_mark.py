#!/usr/bin/env python3
"""Write and check the Enough launch mark.

The image is a solid ink tile with a paper bar and the word Enough.
A mostly transparent file is a failed launch screen, which is what shipped
in 149ea9c (400x48, 221 bytes).
"""

import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSET = os.path.join(ROOT, "App", "Assets.xcassets", "LaunchMark.imageset")
INK = (0x24, 0x33, 0x30, 255)
PAPER = (0xE6, 0xE1, 0xD6, 255)

# 5x7 glyphs. Enough is drawn in title case with a capital E.
FONT = {
    "E": ["11111", "10000", "11110", "10000", "10000", "10000", "11111"],
    "n": ["00000", "00000", "11110", "10001", "10001", "10001", "10001"],
    "o": ["00000", "00000", "01110", "10001", "10001", "10001", "01110"],
    "u": ["00000", "00000", "10001", "10001", "10001", "10001", "01110"],
    "g": ["00000", "00000", "01111", "10001", "10001", "01111", "00001", "01110"],
    "h": ["10000", "10000", "11110", "10001", "10001", "10001", "10001"],
}


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def draw(size):
    pixels = [INK] * (size * size)
    scale = max(6, size // 90)
    gap = scale * 2
    word = "Enough"
    letter_w = 5 * scale
    width = len(word) * letter_w + (len(word) - 1) * gap
    bar_w = width + scale * 4
    bar_h = max(8, scale * 2)
    origin_x = (size - width) // 2
    origin_y = (size // 2) - (4 * scale)

    def put(x, y, color):
        if 0 <= x < size and 0 <= y < size:
            pixels[y * size + x] = color

    bar_x = (size - bar_w) // 2
    bar_y = origin_y - bar_h - scale * 3
    for y in range(bar_y, bar_y + bar_h):
        for x in range(bar_x, bar_x + bar_w):
            put(x, y, PAPER)

    cursor = origin_x
    for char in word:
        glyph = FONT[char]
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit != "1":
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        put(cursor + gx * scale + dx, origin_y + gy * scale + dy, PAPER)
        cursor += letter_w + gap
    return pixels


def encode(size, pixels):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(pixels[y * size + x])
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def write_assets(root=ROOT):
    folder = os.path.join(root, "App", "Assets.xcassets", "LaunchMark.imageset")
    os.makedirs(folder, exist_ok=True)
    for scale, size in (("2x", 800), ("3x", 1200)):
        pixels = draw(size)
        path = os.path.join(folder, f"launch-mark@{scale}.png")
        with open(path, "wb") as handle:
            handle.write(encode(size, pixels))
    stale = os.path.join(folder, "launch-mark.png")
    if os.path.exists(stale):
        os.remove(stale)


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    pos = 8
    width = height = None
    idat = b""
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        chunk_data = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height = struct.unpack(">II", chunk_data[:8])
        elif tag == b"IDAT":
            idat += chunk_data
        elif tag == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(idat)
    rows = []
    stride = width * 4
    index = 0
    for _ in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        if filt != 0:
            raise SystemExit(f"{path} uses PNG filter {filt}; expected none")
        rows.append(row)
    return width, height, rows, len(data)


def near(pixel, color, tolerance=12):
    return all(abs(pixel[i] - color[i]) <= tolerance for i in range(3)) and pixel[3] > 240


def check_file(path, expected):
    width, height, rows, nbytes = read_png(path)
    if (width, height) != (expected, expected):
        raise SystemExit(f"{path} is {width}x{height}, expected {expected}x{expected}")
    # A solid tile compresses well. The broken 400x48 transparent file was 221 bytes.
    if nbytes < 2500:
        raise SystemExit(f"{path} is only {nbytes} bytes and will not read as a branded mark")
    opaque = ink = paper = 0
    total = width * height
    for row in rows:
        for index in range(0, len(row), 4):
            pixel = row[index:index + 4]
            if pixel[3] > 240:
                opaque += 1
            if near(pixel, INK):
                ink += 1
            elif near(pixel, PAPER):
                paper += 1
    if opaque < int(total * 0.98):
        raise SystemExit(f"{path} is mostly transparent ({opaque}/{total} opaque)")
    if ink < int(total * 0.5):
        raise SystemExit(f"{path} is missing the ink background ({ink} ink pixels)")
    if paper < 2000:
        raise SystemExit(f"{path} mark is too small to see ({paper} paper pixels)")
    print(f"{os.path.basename(path)}: {width}x{height}, {nbytes} bytes, {paper} paper pixels")


def check_assets(root=ROOT):
    folder = os.path.join(root, "App", "Assets.xcassets", "LaunchMark.imageset")
    check_file(os.path.join(folder, "launch-mark@2x.png"), 800)
    check_file(os.path.join(folder, "launch-mark@3x.png"), 1200)
    contents = open(os.path.join(folder, "Contents.json"), encoding="utf-8").read()
    if "launch-mark@2x.png" not in contents or "launch-mark@3x.png" not in contents:
        raise SystemExit("LaunchMark Contents.json is not pointing at the @2x and @3x files")


def main():
    if "--check" in sys.argv:
        check_assets()
        return
    write_assets()
    check_assets()


if __name__ == "__main__":
    main()
