#!/usr/bin/env python3
"""Draws the home-screen icons.

iOS will not take an SVG for `apple-touch-icon`, so these have to be
PNGs - and a PNG checked into a repository with no way to regenerate it
is a binary nobody can change. This is that way. It writes the same
bytes every time it runs, so re-running it produces no diff unless the
drawing actually changed.

    python3 web/orbitai/assets/make-icons.py

Deliberately dependency-free: Pillow is not installed on a stock Mac, and
"install Pillow to change an icon" is how an icon stays wrong forever.
"""

import pathlib
import struct
import zlib

HERE = pathlib.Path(__file__).resolve().parent
SITE = HERE.parent

# The palette, from styles.css. Deep navy ground, because a home screen
# is mostly other people's white icons, and the sky blue ring on top.
GROUND = (12, 36, 57)
RING = (56, 163, 232)
GLOW = (19, 114, 184)
DOT = (226, 238, 249)


def blend(under, over, alpha):
    return tuple(round(u + (o - u) * alpha) for u, o in zip(under, over))


def coverage(distance, edge, softness=1.0):
    """How much of a pixel at `distance` falls inside a boundary at `edge`.

    A hard comparison gives stairsteps on a circle, and at 180 pixels a
    stairstepped ring is what the eye lands on first. One pixel of
    feathering either side is enough to read as smooth.
    """
    if distance <= edge - softness:
        return 1.0
    if distance >= edge + softness:
        return 0.0
    return (edge + softness - distance) / (2 * softness)


def draw(size):
    """One icon, as rows of RGB bytes.

    A ring with a dot inside it - the same mark as the wordmark on the
    site, which is a circle with a smaller circle riding on its edge.
    """
    middle = (size - 1) / 2
    radius = size * 0.30          # the ring's centre line
    thickness = size * 0.055
    dot_at = size * 0.30          # the dot rides on the ring, up and right
    dot_radius = size * 0.085
    dot_x = middle + dot_at * 0.707
    dot_y = middle - dot_at * 0.707

    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            dx, dy = x - middle, y - middle
            from_middle = (dx * dx + dy * dy) ** 0.5

            # A soft glow behind everything, brightest in the middle, so
            # the icon does not read as a flat rectangle.
            pixel = blend(GROUND, GLOW, max(0.0, 0.22 - from_middle / size * 0.3))

            # The ring: inside the outer edge and outside the inner one.
            ring = min(coverage(from_middle, radius + thickness / 2),
                       1.0 - coverage(from_middle, radius - thickness / 2))
            if ring > 0:
                pixel = blend(pixel, RING, ring)

            ddx, ddy = x - dot_x, y - dot_y
            dot = coverage((ddx * ddx + ddy * ddy) ** 0.5, dot_radius)
            if dot > 0:
                pixel = blend(pixel, DOT, dot)

            row += bytes(pixel)
        rows.append(bytes(row))
    return rows


def png(rows, size):
    """The smallest PNG that holds it: 8-bit RGB, no filtering."""
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    # 180 is what iOS asks for; 192 and 512 are what a web manifest wants.
    for size, name in ((180, "apple-touch-icon.png"),
                       (192, "icon-192.png"),
                       (512, "icon-512.png")):
        path = SITE / name
        path.write_bytes(png(draw(size), size))
        print("%s  %d bytes" % (name, path.stat().st_size))


if __name__ == "__main__":
    main()
