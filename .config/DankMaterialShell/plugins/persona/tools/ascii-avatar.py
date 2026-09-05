#!/usr/bin/env python3
"""ascii-avatar - turn a pixel-art sprite into sharp, coloured ASCII art.

Each sprite pixel becomes a 2-wide, 1-tall run of characters, which matches the
1:2 aspect of a monospace cell, so the geometry of the sprite is preserved
exactly. The character is chosen by what the pixel is (outline, hair, skin,
eye, mouth), the colour is the pixel's own colour with hair optionally
re-hued. Output is an SVG, a transparent PNG, and the plain text.

Usage: ascii-avatar.py SPRITE.png OUTBASE [--crop X,Y,W,H] [--hair-hue 335]
                       [--size 512] [--font "JetBrainsMono Nerd Font Mono"]
"""
import argparse
import colorsys
import html
import os
import subprocess
import sys


def load_rgba(path, crop):
    cmd = ["magick", path]
    if crop:
        x, y, w, h = crop
        cmd += ["-crop", f"{w}x{h}+{x}+{y}", "+repage"]
    cmd += ["-depth", "8", "rgba:-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    if crop:
        w, h = crop[2], crop[3]
    else:
        ident = subprocess.run(["magick", "identify", "-format", "%w %h", path],
                               capture_output=True, text=True, check=True).stdout.split()
        w, h = int(ident[0]), int(ident[1])
    px = [[tuple(raw[(r * w + c) * 4:(r * w + c) * 4 + 4]) for c in range(w)] for r in range(h)]
    return px, w, h


def classify(rgba):
    r, g, b, a = rgba
    if a < 64 or (abs(r - BG[0]) + abs(g - BG[1]) + abs(b - BG[2])) < 18:
        return "bg"
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    hue = h * 360
    if l < 0.16:
        return "outline"
    # HSV saturation separates cream skin (low) from yellow hair (high),
    # where HLS saturation cannot because both sit near white.
    mx, mn = max(r, g, b), min(r, g, b)
    sv = (mx - mn) / mx if mx else 0
    # Peach skin is orange-leaning (hue < 42) and mild; hair highlights are
    # yellow (hue ~55) even when pale.
    if l > 0.55 and ((sv < 0.15 and 10 <= hue <= 70) or (sv < 0.42 and 10 <= hue <= 42)):
        return "skin" if l > 0.8 else "skinshade"
    if sv >= 0.3 and 20 <= hue <= 70 and l > 0.3:
        return "hair"
    if s > 0.3 and 15 <= hue <= 50 and l <= 0.3:
        return "hairdark"
    if s > 0.3 and (hue >= 190 and hue <= 250):
        return "eye"
    if s > 0.45 and (hue < 15 or hue > 330) and l < 0.6:
        return "mouth"
    if l > 0.8 and s < 0.5:
        return "skin"
    if l > 0.55:
        return "skinshade"
    return "dark"


BG = (24, 24, 23)  # review-preview backdrop baked into the sprite

CHARS = {
    "bg": "  ",
    "outline": "@@",
    "hair": "##",
    "hairdark": "%%",
    "eye": "()",
    "mouth": "vv",
    "skin": "::",
    "skinshade": "..",
    "dark": "&&",
}


def rehue(rgba, hue_deg):
    r, g, b, a = rgba
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    # Lift lightness so yellow (bright) hair lands on pink rather than crimson.
    l = 0.3 + 0.7 * l
    r2, g2, b2 = colorsys.hls_to_rgb(hue_deg / 360, l, max(s, 0.85))
    return (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sprite")
    ap.add_argument("outbase")
    ap.add_argument("--crop", default="")
    ap.add_argument("--hair-hue", type=float, default=330.0)
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--font", default="JetBrainsMono Nerd Font Mono")
    ap.add_argument("--weight", default="bold")
    ap.add_argument("--underlay", type=float, default=0.0, help="opacity of a pixel-art layer under the glyphs")
    ap.add_argument("--pixel", default="", help="also write a plain pixel-art PNG here")
    a = ap.parse_args()

    crop = tuple(int(v) for v in a.crop.split(",")) if a.crop else None
    px, w, h = load_rgba(a.sprite, crop)

    cols = w * 2
    rows = h
    # Monospace advance is ~0.6em; rows are 1.2em. Fit the wider dimension.
    em = min(a.size / (cols * 0.6), a.size / (rows * 1.2))
    cell_w = em * 0.6
    cell_h = em * 1.2
    x0 = (a.size - cols * cell_w) / 2
    y0 = (a.size - rows * cell_h) / 2

    lines = []
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{a.size}" height="{a.size}" '
           f'viewBox="0 0 {a.size} {a.size}">',
           f'<g font-family="{html.escape(a.font)}" font-weight="{a.weight}" font-size="{em:.3f}" '
           f'xml:space="preserve">']
    for r in range(rows):
        text = ""
        spans = []
        for c in range(w):
            kind = classify(px[r][c])
            ch = CHARS[kind]
            text += ch
            if kind == "bg":
                continue
            col = px[r][c]
            if kind in ("hair", "hairdark"):
                col = rehue(col, a.hair_hue)
            fill = "#%02x%02x%02x" % col[:3]
            x = x0 + c * 2 * cell_w
            spans.append(f'<tspan x="{x:.2f}" fill="{fill}">{html.escape(ch)}</tspan>')
        lines.append(text.rstrip())
        if spans:
            y = y0 + r * cell_h + em * 0.95
            svg.append(f'<text y="{y:.2f}">' + "".join(spans) + "</text>")
    svg.append("</g></svg>")

    with open(a.outbase + ".txt", "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(a.outbase + ".svg", "w") as f:
        f.write("\n".join(svg))
    if a.pixel:
        # Same crop and hair recolour as plain pixel art, nearest-neighbour upscaled.
        buf = bytearray()
        for r in range(rows):
            for c in range(w):
                kind = classify(px[r][c])
                col = px[r][c]
                if kind == "bg":
                    col = (0, 0, 0, 0)
                elif kind in ("hair", "hairdark"):
                    col = rehue(col, a.hair_hue)
                buf += bytes(col)
        scale = max(1, a.size // max(w, h))
        subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgba:-",
                        "-scale", f"{scale * 100}%", "-background", "none", "-gravity", "center",
                        "-extent", f"{a.size}x{a.size}", a.pixel], input=bytes(buf), check=True)
    subprocess.run(["rsvg-convert", "-w", str(a.size), "-h", str(a.size), "-b", "none",
                    "-o", a.outbase + ".png", a.outbase + ".svg"], check=True)
    if a.underlay > 0:
        # Faint nearest-neighbour sprite under the glyphs, aligned to the same
        # cell grid. At avatar sizes the glyphs collapse into texture and the
        # underlay carries the face; at full size the glyphs stay dominant.
        buf = bytearray()
        for r in range(rows):
            for c in range(w):
                kind = classify(px[r][c])
                col = px[r][c]
                if kind == "bg":
                    col = (0, 0, 0, 0)
                elif kind in ("hair", "hairdark"):
                    col = rehue(col, a.hair_hue)
                buf += bytes(col)
        uw, uh = round(cols * cell_w), round(rows * cell_h)
        subprocess.run(["magick", "-size", f"{a.size}x{a.size}", "xc:none",
                        "(", "-size", f"{w}x{h}", "-depth", "8", "rgba:-", "-scale", f"{uw}x{uh}!", ")",
                        "-geometry", f"+{round(x0)}+{round(y0)}", "-composite",
                        "-channel", "A", "-evaluate", "multiply", str(a.underlay), "+channel",
                        a.outbase + ".png", "-composite", a.outbase + ".png"],
                       input=bytes(buf), check=True)
    print(f"{cols}x{rows} cells, em={em:.1f}px -> {a.outbase}.png/.svg/.txt")


if __name__ == "__main__":
    main()
