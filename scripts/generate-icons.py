"""Generates easyReminder's PWA icon set (MOBILE.md Stage 1).

Mark: a white completion-ring + checkmark on the Work-context blue
(DESIGN.md §2) — the same "tap to complete" ring used throughout the
reminder-row UI, doubling as the brand glyph so the icon reads as
unmistakably *this app* even at home-screen size.

Requires Pillow: pip install pillow --break-system-packages
Run from the repo root: python3 scripts/generate-icons.py
"""

from PIL import Image, ImageDraw, ImageFilter
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "public")
BLUE_TOP = (0x4C, 0x8D, 0xFF)   # lighter blue, top-left sheen
BLUE_BASE = (0x2E, 0x63, 0xD6)  # deeper Work-blue base
WHITE = (255, 255, 255, 255)


def make_bg(size):
    """Full-bleed blue field with a soft highlight — no manual corner
    rounding, since iOS/Android apply their own icon mask on top."""
    img = Image.new("RGBA", (size, size), BLUE_BASE + (255,))

    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    r = int(size * 0.85)
    cx, cy = int(size * 0.18), int(size * 0.12)
    hd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLUE_TOP + (140,))
    hl = hl.filter(ImageFilter.GaussianBlur(size * 0.18))
    img = Image.alpha_composite(img, hl)

    vg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vg)
    r2 = int(size * 0.75)
    cx2, cy2 = int(size * 0.85), int(size * 0.9)
    vd.ellipse([cx2 - r2, cy2 - r2, cx2 + r2, cy2 + r2], fill=(0, 0, 20, 60))
    vg = vg.filter(ImageFilter.GaussianBlur(size * 0.15))
    return Image.alpha_composite(img, vg)


def draw_mark(img, size, ring_frac, stroke_frac):
    d = ImageDraw.Draw(img)
    stroke = max(2, int(size * stroke_frac))
    r = size * ring_frac / 2
    cx, cy = size / 2, size / 2 * 0.98
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=stroke)

    ck = size * ring_frac * 0.34
    p1 = (cx - ck, cy + ck * 0.05)
    p2 = (cx - ck * 0.15, cy + ck * 0.85)
    p3 = (cx + ck * 1.05, cy - ck * 0.75)
    d.line([p1, p2, p3], fill=WHITE, width=stroke, joint="curve")
    cap = stroke / 2
    for pt in (p1, p2, p3):
        d.ellipse([pt[0] - cap, pt[1] - cap, pt[0] + cap, pt[1] + cap], fill=WHITE)
    return img


def render(size, ring_frac, stroke_frac, filename, flatten=False):
    ss = size * 4  # supersample for antialiasing, then downscale
    img = draw_mark(make_bg(ss), ss, ring_frac, stroke_frac)
    img = img.resize((size, size), Image.LANCZOS)
    if flatten:
        img = img.convert("RGB")
    img.save(os.path.join(OUT, filename))
    print(f"wrote {filename} ({size}x{size})")


if __name__ == "__main__":
    # "any" purpose — generous mark; OS applies its own corner rounding
    render(192, ring_frac=0.60, stroke_frac=0.075, filename="icon-192.png")
    render(512, ring_frac=0.60, stroke_frac=0.075, filename="icon-512.png")

    # maskable — full-bleed required; mark stays inside the ~80% safe-zone
    # circle so circle/squircle/teardrop OS crop shapes never clip it
    render(512, ring_frac=0.46, stroke_frac=0.065, filename="icon-maskable-512.png")

    # apple touch icon — iOS applies its own squircle mask; no alpha allowed
    render(180, ring_frac=0.58, stroke_frac=0.075, filename="apple-icon.png", flatten=True)

    # favicon.ico, built from the 512 master
    Image.open(os.path.join(OUT, "icon-512.png")).save(
        os.path.join(os.path.dirname(__file__), "..", "app", "favicon.ico"),
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64)],
    )
    print("wrote app/favicon.ico")
