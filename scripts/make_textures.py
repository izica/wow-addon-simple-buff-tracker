"""Draw the addon's textures into SimpleBuffTracker/media/ (32-bit TGA, the size a
power of two, as the game wants). White art: the code colors it.

    python scripts/make_textures.py

corner_round.tga -- a quarter disc, the top left corner of a rounded shape (the
                    disc's center in the texture's bottom right corner),
                    smoothed by supersampling; ui/rounded_rect.lua turns it for
                    the other corners.
"""
import math
import os
import struct

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(REPOSITORY, "SimpleBuffTracker", "media")
SIZE = 64
SAMPLES = 4   # per side of a pixel, for smooth edges


def coverage(inside):
    def alpha(x, y):
        hits = 0
        for sx in range(SAMPLES):
            for sy in range(SAMPLES):
                if inside(x + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES):
                    hits += 1
        return hits / (SAMPLES * SAMPLES)
    return alpha


def round_corner(x, y):
    return math.hypot(SIZE - x, SIZE - y) <= SIZE


def write_tga(name, alpha_at):
    # uncompressed true color with alpha, rows from the top (descriptor bit 5)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8 | 0x20)
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            alpha = max(0, min(255, round(alpha_at(x, y) * 255)))
            pixels += bytes((255, 255, 255, alpha))   # B, G, R, A
    path = os.path.join(FOLDER, name)
    with open(path, "wb") as file:
        file.write(header + pixels)
    print(os.path.relpath(path, REPOSITORY))


def main():
    os.makedirs(FOLDER, exist_ok=True)
    write_tga("corner_round.tga", coverage(round_corner))


if __name__ == "__main__":
    main()
