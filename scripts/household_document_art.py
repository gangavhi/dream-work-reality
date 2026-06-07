"""Shared drawing primitives for high-fidelity synthetic document fixtures."""
from __future__ import annotations

import hashlib
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WATERMARK = "SAMPLE — FICTIONAL — FOR TESTING ONLY"


def load_font(size: int, bold: bool = False, mono: bool = False, serif: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    if mono:
        paths = [
            "/System/Library/Fonts/Menlo.ttc",
            "/System/Library/Fonts/Supplemental/Courier New Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Courier New.ttf",
        ]
    elif serif:
        paths = [
            "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
            "/System/Library/Fonts/Supplemental/Georgia Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Georgia.ttf",
        ]
    else:
        paths = [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def seeded_rng(*parts: str) -> random.Random:
    digest = hashlib.sha256("".join(parts).encode()).hexdigest()
    return random.Random(int(digest[:16], 16))


def hex_to_rgb(color: str) -> tuple[int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4))


def add_paper_texture(img: Image.Image, strength: float = 0.035) -> Image.Image:
    rng = seeded_rng("paper", str(img.size))
    noise = Image.new("RGB", img.size)
    px = noise.load()
    step = 2
    for y in range(0, img.size[1], step):
        for x in range(0, img.size[0], step):
            n = rng.randint(-16, 16)
            c = (128 + n, 128 + n, 128 + n)
            for dy in range(step):
                for dx in range(step):
                    if x + dx < img.size[0] and y + dy < img.size[1]:
                        px[x + dx, y + dy] = c
    noise = noise.filter(ImageFilter.GaussianBlur(1.0))
    return Image.blend(img, noise, strength)


def draw_guilloche(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: str = "#c5d5e8", lines: int = 28) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    rgb = hex_to_rgb(color)
    for i in range(lines):
        pts = []
        amp = 8 + (i % 5) * 2
        freq = 0.018 + i * 0.0008
        for x in range(0, w, 6):
            y = int(h / 2 + math.sin(x * freq + i * 0.4) * amp + math.cos(x * freq * 0.5) * amp * 0.5)
            pts.append((x0 + x, y0 + y))
        if len(pts) > 1:
            draw.line(pts, fill=rgb, width=1)


def draw_security_mesh(img: Image.Image, tint: tuple[int, int, int] = (200, 215, 235)) -> Image.Image:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    w, h = img.size
    for y in range(0, h, 14):
        draw.line([(0, y), (w, y)], fill=(*tint, 18), width=1)
    for x in range(0, w, 14):
        draw.line([(x, 0), (x, h)], fill=(*tint, 12), width=1)
    base = img.convert("RGBA")
    return Image.alpha_composite(base, overlay).convert("RGB")


def draw_state_seal(draw: ImageDraw.ImageDraw, cx: int, cy: int, radius: int, label: str, accent: str) -> None:
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=accent, width=4, fill="#fafafa")
    draw.ellipse((cx - radius + 10, cy - radius + 10, cx + radius - 10, cy + radius - 10), outline=accent, width=2)
    for i in range(12):
        ang = math.radians(i * 30)
        x1 = cx + int(math.cos(ang) * (radius - 8))
        y1 = cy + int(math.sin(ang) * (radius - 8))
        x2 = cx + int(math.cos(ang) * (radius - 20))
        y2 = cy + int(math.sin(ang) * (radius - 20))
        draw.line([(x1, y1), (x2, y2)], fill=accent, width=2)
    font = load_font(max(14, radius // 4), bold=True)
    bb = draw.textbbox((0, 0), label, font=font)
    draw.text((cx - (bb[2] - bb[0]) // 2, cy - (bb[3] - bb[1]) // 2), label, fill=accent, font=font)


def draw_star(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int, fill: str) -> None:
    pts = []
    for i in range(10):
        ang = math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.42
        pts.append((cx + rad * math.cos(ang), cy - rad * math.sin(ang)))
    draw.polygon(pts, fill=fill)


def draw_realistic_photo(
    base: Image.Image,
    box: tuple[int, int, int, int],
    initials: str,
    skin: str = "#c8a88a",
    shirt: str = "#455a64",
) -> None:
    x0, y0, x1, y1 = box
    draw = ImageDraw.Draw(base)
    draw.rectangle(box, fill="#eceff1", outline="#546e7a", width=3)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    w, h = x1 - x0, y1 - y0
    head_r = int(min(w, h) * 0.17)
    draw.ellipse((cx - head_r, cy - head_r * 2, cx + head_r, cy - head_r * 0.2), fill=skin, outline="#8d6e63", width=2)
    draw.rectangle((cx - head_r * 1.4, cy - head_r * 0.1, cx + head_r * 1.4, y1 - 12), fill=shirt)
    draw.ellipse((cx - head_r * 0.25, cy - head_r * 1.35, cx - head_r * 0.05, cy - head_r * 1.1), fill="#263238")
    draw.ellipse((cx + head_r * 0.05, cy - head_r * 1.35, cx + head_r * 0.25, cy - head_r * 1.1), fill="#263238")
    draw.arc((cx - head_r * 0.35, cy - head_r * 1.05, cx + head_r * 0.35, cy - head_r * 0.65), 20, 160, fill="#6d4c41", width=2)
    font = load_font(max(16, head_r // 2), bold=True)
    bb = draw.textbbox((0, 0), initials, font=font)
    draw.text((x1 - (bb[2] - bb[0]) - 8, y1 - (bb[3] - bb[1]) - 6), initials, fill="#37474f", font=font)


def draw_ghost_photo(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill="#e0e0e0", outline="#bdbdbd", width=1)
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    r = min(x1 - x0, y1 - y0) // 5
    draw.ellipse((cx - r, cy - r * 2, cx + r, cy), fill="#bdbdbd")


def draw_hologram_patch(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    for i in range(y0, y1, 3):
        t = (i - y0) / max(1, y1 - y0)
        color = (
            int(120 + 80 * math.sin(t * 6)),
            int(120 + 80 * math.sin(t * 6 + 2)),
            int(180 + 50 * math.sin(t * 6 + 4)),
        )
        draw.line([(x0, i), (x1, i)], fill=color, width=3)
    draw.ellipse(box, outline="#90a4ae", width=2)


def draw_pdf417_blocks(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], seed: str) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill="white", outline="#333", width=2)
    rng = seeded_rng("pdf417", seed)
    row_h = 5
    y = y0 + 6
    while y < y1 - 8:
        x = x0 + 6
        while x < x1 - 6:
            bw = rng.choice([2, 3, 4, 2, 3])
            bh = rng.choice([row_h, row_h + 2, row_h])
            if rng.random() > 0.35:
                draw.rectangle((x, y, x + bw, y + bh), fill="#111")
            x += bw + rng.choice([1, 1, 2])
        y += row_h + 1
    draw.text((x0 + 8, y1 - 18), "PDF417", fill="#555", font=load_font(12, mono=True))


def draw_code128_barcode(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], seed: str) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill="white", outline="#333", width=1)
    rng = seeded_rng("code128", seed)
    x = x0 + 10
    while x < x1 - 10:
        w = rng.choice([2, 3, 4, 2, 5, 3])
        if rng.random() > 0.4:
            draw.rectangle((x, y0 + 6, x + w, y1 - 22), fill="#111")
        x += w + rng.choice([1, 2, 2])
    draw.text((x0 + 10, y1 - 18), seed[:22], fill="#333", font=load_font(13, mono=True))


def draw_microprint_line(draw: ImageDraw.ImageDraw, y: int, x0: int, x1: int, text: str = "USAUSAUSA") -> None:
    font = load_font(8)
    x = x0
    while x < x1:
        draw.text((x, y), text, fill="#9e9e9e", font=font)
        x += 52


def draw_label_value_row(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    label: str,
    value: str,
    label_font: ImageFont.ImageFont,
    value_font: ImageFont.ImageFont,
    label_w: int = 220,
) -> int:
    draw.text((x, y), label, fill="#5f6368", font=label_font)
    draw.text((x + label_w, y), value, fill="#111", font=value_font)
    return y + max(draw.textbbox((0, 0), label, font=label_font)[3], draw.textbbox((0, 0), value, font=value_font)[3]) + 8


def draw_bilingual_field(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    en: str,
    fr: str,
    value: str,
    label_font: ImageFont.ImageFont,
    value_font: ImageFont.ImageFont,
) -> int:
    draw.text((x, y), en, fill="#666", font=label_font)
    draw.text((x + 200, y), f"/ {fr}", fill="#999", font=load_font(label_font.size - 4))
    draw.text((x, y + 22), value, fill="#111", font=value_font)
    return y + 22 + draw.textbbox((0, 0), value, font=value_font)[3] - draw.textbbox((0, 0), value, font=value_font)[1] + 10


def apply_sample_watermark(img: Image.Image) -> Image.Image:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font = load_font(max(28, img.size[0] // 24), bold=True)
    text = "SAMPLE"
    bb = draw.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    draw.text(((img.size[0] - tw) // 2, (img.size[1] - th) // 2), text, fill=(160, 160, 160, 48), font=font)
    overlay = overlay.rotate(28, resample=Image.Resampling.BICUBIC)
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


def draw_footer(draw: ImageDraw.ImageDraw, width: int, height: int) -> None:
    font = load_font(15)
    bb = draw.textbbox((0, 0), WATERMARK, font=font)
    draw.text((width - (bb[2] - bb[0]) - 16, height - 24), WATERMARK, fill="#9aa0a6", font=font)


def desk_background(size: tuple[int, int], tone: str = "#d7ccc8") -> Image.Image:
    img = Image.new("RGB", size, tone)
    img = add_paper_texture(img, 0.05)
    draw = ImageDraw.Draw(img)
    rng = seeded_rng("desk", str(size), tone)
    for _ in range(120):
        x, y = rng.randint(0, size[0]), rng.randint(0, size[1])
        c = rng.randint(-12, 12)
        base = hex_to_rgb(tone)
        dot = tuple(max(0, min(255, v + c)) for v in base)
        draw.ellipse((x, y, x + 3, y + 3), fill=dot)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def phone_scan_scene(
    card: Image.Image,
    padding: int = 100,
    rotation: float = -3.0,
    desk_tone: str = "#cfd8dc",
) -> Image.Image:
    card = card.convert("RGBA")
    card = card.rotate(rotation, expand=True, resample=Image.Resampling.BICUBIC)
    cw, ch = card.size
    scene_w, scene_h = cw + padding * 2, ch + padding * 2
    scene = desk_background((scene_w, scene_h), desk_tone)

    shadow = Image.new("RGBA", (cw + 40, ch + 40), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle((18, 18, cw + 22, ch + 22), radius=16, fill=(0, 0, 0, 85))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    scene.paste(shadow, (padding - 6, padding + 10), shadow)
    scene.paste(card, (padding, padding), card)

    vignette = Image.new("L", (scene_w, scene_h), 255)
    vdraw = ImageDraw.Draw(vignette)
    vdraw.ellipse((-80, -80, scene_w + 80, scene_h + 80), fill=185)
    vignette = vignette.filter(ImageFilter.GaussianBlur(80))
    scene = Image.composite(scene, Image.new("RGB", scene.size, "#b0bec5"), vignette)
    return scene


def ornate_border(draw: ImageDraw.ImageDraw, margin: int, size: tuple[int, int], accent: str, layers: int = 5) -> None:
    w, h = size
    base = hex_to_rgb(accent)
    for i in range(layers):
        shade = tuple(max(0, min(255, c + i * 14)) for c in base)
        inset = margin - i * 3
        draw.rectangle((inset, inset, w - inset, h - inset), outline=shade, width=2)
    for corner in [(margin, margin), (w - margin - 60, margin), (margin, h - margin - 60), (w - margin - 60, h - margin - 60)]:
        draw.rectangle((corner[0], corner[1], corner[0] + 60, corner[1] + 60), outline=accent, width=2)
        draw.line([(corner[0] + 8, corner[1] + 30), (corner[0] + 52, corner[1] + 30)], fill=accent, width=2)
        draw.line([(corner[0] + 30, corner[1] + 8), (corner[0] + 30, corner[1] + 52)], fill=accent, width=2)


def save_document(image: Image.Image, out_png: Path) -> None:
    out_png.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_png, "PNG", optimize=True)
    image.convert("RGB").save(out_png.with_suffix(".pdf"), "PDF", resolution=220.0)
