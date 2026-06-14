#!/usr/bin/env python3
"""Generate TrustNest app icon set for iOS."""

from pathlib import Path
from PIL import Image, ImageDraw

OUTPUT = Path(__file__).resolve().parent.parent / "TrustNest/Resources/Assets.xcassets/AppIcon.appiconset"

SIZES = [
    ("iphone", "20x20", 2, 40),
    ("iphone", "20x20", 3, 60),
    ("iphone", "29x29", 2, 58),
    ("iphone", "29x29", 3, 87),
    ("iphone", "40x40", 2, 80),
    ("iphone", "40x40", 3, 120),
    ("iphone", "60x60", 2, 120),
    ("iphone", "60x60", 3, 180),
    ("ipad", "20x20", 1, 20),
    ("ipad", "20x20", 2, 40),
    ("ipad", "29x29", 1, 29),
    ("ipad", "29x29", 2, 58),
    ("ipad", "40x40", 1, 40),
    ("ipad", "40x40", 2, 80),
    ("ipad", "76x76", 1, 76),
    ("ipad", "76x76", 2, 152),
    ("ipad", "83.5x83.5", 2, 167),
    ("ios-marketing", "1024x1024", 1, 1024),
]


def render_icon(size: int, opaque: bool = False) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size * 0.08
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=size * 0.22,
        fill=(33, 92, 158, 255),
    )

    roof_h = size * 0.22
    base_y = size * 0.52
    roof = [
        (size * 0.28, base_y),
        (size * 0.5, base_y - roof_h),
        (size * 0.72, base_y),
    ]
    draw.polygon(roof, fill=(255, 255, 255, 255))

    body_left = size * 0.34
    body_right = size * 0.66
    body_bottom = size * 0.74
    draw.rectangle((body_left, base_y, body_right, body_bottom), fill=(255, 255, 255, 255))

    door_w = size * 0.12
    door_h = size * 0.14
    door_x = size * 0.5 - door_w / 2
    door_y = body_bottom - door_h
    draw.rectangle((door_x, door_y, door_x + door_w, door_y + door_h), fill=(33, 92, 158, 255))

    if opaque:
        background = Image.new("RGB", (size, size), (33, 92, 158))
        background.paste(img, mask=img.split()[3])
        return background
    return img


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []

    for idiom, size_label, scale, pixels in SIZES:
        filename = f"icon-{size_label.replace('.', '_')}@{scale}x.png" if scale > 1 else f"icon-{size_label.replace('.', '_')}.png"
        if idiom == "ios-marketing":
            filename = "icon-1024.png"
        opaque = idiom == "ios-marketing"
        render_icon(pixels, opaque=opaque).save(OUTPUT / filename)
        if idiom == "ios-marketing":
            entries.append({
                "filename": filename,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            })
            continue
        entry = {
            "filename": filename,
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": size_label,
        }
        entries.append(entry)

    import json

    contents = {
        "images": entries,
        "info": {"author": "xcode", "version": 1},
    }
    (OUTPUT / "Contents.json").write_text(json.dumps(contents, indent=2))
    print(f"Generated {len(entries)} icons in {OUTPUT}")


if __name__ == "__main__":
    main()
