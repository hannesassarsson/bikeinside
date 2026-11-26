"""Generates the app icon (Bikeinside/Assets.xcassets/AppIcon.appiconset).
Run: python3 scripts/make_icon.py  (needs Pillow)"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Bikeinside", "Assets.xcassets", "AppIcon.appiconset")
S = 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def master():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # macOS icon grid: 824px rounded square centred, radius ~185
    pad, size, radius = 100, 824, 185
    bg = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(bg)
    top, bottom = (255, 176, 92), (33, 64, 138)   # sunset sky → evening blue
    for y in range(S):
        t = min(max((y - pad) / size, 0), 1)
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, t ** 0.9) + (255,))
    # sun
    d.ellipse([S/2 - 150, 300, S/2 + 150, 600], fill=(255, 226, 150, 255))
    # mountain/forest silhouettes
    def ridge(base, amp, freq, phase, color):
        pts = [(pad, S)]
        for x in range(pad, pad + size + 1, 4):
            y = base - amp * (0.6 * math.sin(x / freq + phase) + 0.4 * math.sin(x / (freq * 0.37) + phase * 2))
            pts.append((x, y))
        pts.append((pad + size, S))
        d.polygon(pts, fill=color)
    ridge(600, 70, 120, 0.5, (86, 72, 130, 255))
    ridge(680, 45, 70, 2.0, (40, 62, 92, 255))
    # spruce trees
    for x, h in [(180, 150), (240, 210), (300, 140), (760, 190), (830, 240), (890, 160)]:
        d.polygon([(x, 760 - h), (x - h * 0.3, 760), (x + h * 0.3, 760)], fill=(18, 48, 52, 255))
    # road
    d.polygon([(S/2 - 40, 640), (S/2 + 40, 640), (S/2 + 330, S), (S/2 - 330, S)], fill=(38, 40, 48, 255))
    for k in range(5):
        y0 = 660 + k * 70; y1 = y0 + 35
        w0 = 4 + k * 6; w1 = w0 + 5
        d.polygon([(S/2 - w0, y0), (S/2 + w0, y0), (S/2 + w1, y1), (S/2 - w1, y1)], fill=(250, 240, 210, 255))
    # bicycle (white line art)
    W = 26
    c = (255, 255, 255, 255)
    lw, rw, wy, r = (330, 700), (694, 700), 700, 120
    for cx, cy in (lw, rw):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=W)
    crank = (500, 700)
    seat = (455, 500)
    head = (650, 515)
    d.line([lw, crank, seat, lw], fill=c, width=W, joint="curve")
    d.line([seat, head, crank], fill=c, width=W, joint="curve")
    d.line([head, rw], fill=c, width=W)
    d.line([(410, 480), (500, 480)], fill=c, width=W)       # saddle
    d.line([head, (640, 455), (705, 450)], fill=c, width=W, joint="curve")  # bars
    d.ellipse([crank[0] - 30, crank[1] - 30, crank[0] + 30, crank[1] + 30], fill=c)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad, pad + size, pad + size], radius=radius, fill=255)
    # soft drop shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 12, pad + size, pad + size + 12], radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(shadow)
    img.paste(bg, (0, 0), mask)
    return img

def main():
    os.makedirs(OUT, exist_ok=True)
    m = master()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            m.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    m.save(os.path.join(os.path.dirname(OUT), "..", "..", "docs-icon.png")) if len(sys.argv) > 1 else None

main()
