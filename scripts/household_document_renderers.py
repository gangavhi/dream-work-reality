"""Realistic synthetic document renderers for household OCR test fixtures."""
from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass
from typing import Any

from PIL import Image, ImageDraw, ImageFilter, ImageFont

Household = Any
Person = Any

WATERMARK = "SAMPLE — FICTIONAL — FOR TESTING ONLY"

STATE_NAMES = {
    "TX": "TEXAS",
    "OR": "OREGON",
    "CO": "COLORADO",
    "WA": "WASHINGTON",
    "FL": "FLORIDA",
    "CA": "CALIFORNIA",
    "IL": "ILLINOIS",
    "AZ": "ARIZONA",
}

STATE_DL_COLORS = {
    "TX": ("#0b3d91", "#f4e4bc", "#1a1a1a"),
    "OR": ("#1f4d2a", "#e8f5e9", "#1a1a1a"),
    "CO": ("#5d1f1f", "#fff3e0", "#1a1a1a"),
    "WA": ("#1b3a5c", "#e3f2fd", "#1a1a1a"),
    "FL": ("#8b1c1c", "#fff8e1", "#1a1a1a"),
    "CA": ("#1a237e", "#fce4ec", "#1a1a1a"),
    "IL": ("#263238", "#eceff1", "#1a1a1a"),
    "AZ": ("#4a148c", "#f3e5f5", "#1a1a1a"),
}


def load_font(size: int, bold: bool = False, mono: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    if mono:
        candidates = [
            "/System/Library/Fonts/Menlo.ttc",
            "/System/Library/Fonts/Supplemental/Courier New Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Courier New.ttf",
        ]
    else:
        candidates = [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/Library/Fonts/Arial.ttf",
        ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _seeded_rng(*parts: str) -> random.Random:
    digest = hashlib.sha256("".join(parts).encode()).hexdigest()
    return random.Random(int(digest[:16], 16))


def _hex_to_rgb(color: str) -> tuple[int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4))


def _add_paper_texture(img: Image.Image, strength: float = 0.04) -> Image.Image:
    rng = _seeded_rng("paper", str(img.size))
    noise = Image.new("RGB", img.size)
    px = noise.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            n = rng.randint(-18, 18)
            px[x, y] = (128 + n, 128 + n, 128 + n)
    noise = noise.filter(ImageFilter.GaussianBlur(1.2))
    return Image.blend(img, noise, strength)


def _draw_watermark(draw: ImageDraw.ImageDraw, size: tuple[int, int], alpha: int = 55) -> None:
    wm = Image.new("RGBA", size, (0, 0, 0, 0))
    wdraw = ImageDraw.Draw(wm)
    font = load_font(max(22, size[0] // 28), bold=True)
    text = "SAMPLE"
    bbox = wdraw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    wdraw.text(
        ((size[0] - tw) // 2, (size[1] - th) // 2),
        text,
        fill=(180, 180, 180, alpha),
        font=font,
    )
    wm = wm.rotate(32, expand=0, resample=Image.Resampling.BICUBIC)
    base = wm.convert("RGBA")
    return base


def _apply_watermark(img: Image.Image) -> Image.Image:
    overlay = _draw_watermark(ImageDraw.Draw(Image.new("RGBA", img.size)), img.size)
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    return Image.alpha_composite(img, overlay).convert("RGB")


def _draw_footer(draw: ImageDraw.ImageDraw, width: int, height: int) -> None:
    font = load_font(16)
    bbox = draw.textbbox((0, 0), WATERMARK, font=font)
    tw = bbox[2] - bbox[0]
    draw.text((width - tw - 20, height - 28), WATERMARK, fill="#9aa0a6", font=font)


def _draw_photo(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], initials: str, bg: str = "#d7ccc8") -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=bg, outline="#8d6e63", width=3)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    head_r = min(x1 - x0, y1 - y0) // 6
    draw.ellipse((cx - head_r, cy - head_r * 2, cx + head_r, cy), fill="#bcaaa4", outline="#8d6e63", width=2)
    draw.ellipse((cx - head_r * 2, cy, cx + head_r * 2, cy + head_r * 4), fill="#bcaaa4", outline="#8d6e63", width=2)
    font = load_font(max(18, head_r), bold=True)
    ib = draw.textbbox((0, 0), initials, font=font)
    draw.text((cx - (ib[2] - ib[0]) // 2, y1 - 34), initials, fill="#5d4037", font=font)


def _draw_barcode(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], seed: str) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill="white", outline="#333", width=1)
    rng = _seeded_rng("barcode", seed)
    x = x0 + 8
    while x < x1 - 8:
        w = rng.choice([2, 3, 4, 5, 2, 3, 6])
        if rng.random() > 0.45:
            draw.rectangle((x, y0 + 4, x + w, y1 - 18), fill="#111")
        x += w + rng.choice([1, 2, 2, 3])
    font = load_font(14, mono=True)
    draw.text((x0 + 10, y1 - 16), seed[:18], fill="#333", font=font)


def _draw_label_value(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    label: str,
    value: str,
    label_font: ImageFont.ImageFont,
    value_font: ImageFont.ImageFont,
    label_color: str = "#5f6368",
    value_color: str = "#111",
    gap: int = 8,
) -> int:
    draw.text((x, y), label, fill=label_color, font=label_font)
    lb = draw.textbbox((x, y), label, font=label_font)
    draw.text((x, lb[3] + gap), value, fill=value_color, font=value_font)
    vb = draw.textbbox((x, lb[3] + gap), value, font=value_font)
    return vb[3]


def _card_on_desk(card: Image.Image, padding: int = 80, rotation: float = -2.5) -> Image.Image:
    card = card.rotate(rotation, expand=True, resample=Image.Resampling.BICUBIC, fillcolor=(0, 0, 0, 0))
    cw, ch = card.size
    desk = Image.new("RGB", (cw + padding * 2, ch + padding * 2), "#e8eaed")
    desk = _add_paper_texture(desk, 0.03)
    shadow = Image.new("RGBA", (cw + 24, ch + 24), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle((12, 12, cw + 12, ch + 12), radius=18, fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    desk.paste(shadow, (padding - 4, padding + 6), shadow)
    if card.mode == "RGBA":
        desk.paste(card, (padding, padding), card)
    else:
        desk.paste(card, (padding, padding))
    return desk


def _rounded_card(size: tuple[int, int], radius: int = 24) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill="white")
    return img


def _sex_label(person: "Person") -> str:
    male = {
        "John", "Marcus", "David", "Carlos", "James", "Michael", "Thomas", "Kevin",
        "Raj", "Lucas", "Mateo", "Alexander",
    }
    return "M" if person.first in male else "F"


def _passport_number_digits(passport_no: str) -> str:
    digits = "".join(ch for ch in passport_no if ch.isdigit())
    return digits[-9:].rjust(9, "0")


def _passport_mrz(p: "Person", passport_no: str) -> tuple[str, str]:
    mm, dd, yyyy = p.dob.split("/")
    yymmdd = f"{yyyy[2:]}{mm}{dd}"
    doc_digits = _passport_number_digits(passport_no)
    line1 = f"P<USA{p.last.upper()}<<{p.first.upper()}<{p.middle.upper()}".ljust(44, "<")[:44]
    line2 = f"{doc_digits}7USA{yymmdd}{_sex_label(p)}3001091234567890<<<<<<06".ljust(44, "<")[:44]
    return line1, line2


def render_drivers_license(h: "Household", p: "Person") -> Image.Image:
    state = p.dl_state
    header, bg, text = STATE_DL_COLORS.get(state, ("#0b3d91", "#f8f5e8", "#111"))
    w, hgt = 1050, 720
    card = _rounded_card((w, hgt))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, w - 1, hgt - 1), radius=24, fill=bg)
    draw.rectangle((0, 0, w, 90), fill=header)

    title_font = load_font(34, bold=True)
    sub_font = load_font(20, bold=True)
    label_font = load_font(16)
    value_font = load_font(26, bold=True)
    small_font = load_font(18)

    state_name = STATE_NAMES.get(state, state)
    draw.text((28, 16), state_name, fill="white", font=title_font)
    draw.text((28, 56), "DRIVER LICENSE", fill="#e3f2fd", font=sub_font)
    draw.text((w - 210, 24), "USA", fill="#ffc107", font=load_font(28, bold=True))

    _draw_photo(draw, (36, 110, 230, 330), f"{p.first[0]}{p.last[0]}")
    x = 260
    y = 108
    fields = [
        ("4d. DL", p.dl_number, value_font),
        ("3. DOB", p.dob, small_font),
        ("1.", p.last.upper(), value_font),
        ("2.", p.first.upper(), value_font),
        ("8. Address", h.address.upper(), small_font),
        ("", f"{h.city.upper()}, {state} {h.zip_code}", small_font),
        ("4a. Iss", "01/10/2023", small_font),
        ("4b. Exp", "01/10/2028", small_font),
        ("Class", "C", small_font),
    ]
    for label, value, font in fields:
        if label:
            draw.text((x, y), label, fill="#444", font=label_font)
            y += 20
        draw.text((x, y), value, fill=text, font=font)
        y += 30 if font == value_font else 26

    _draw_barcode(draw, (36, 430, w - 36, 540), p.dl_number)
    draw.text((36, 560), "LIMITED TERM", fill="#666", font=label_font)
    draw.text((36, 595), "DONOR", fill="#2e7d32", font=load_font(18, bold=True))
    draw.text((w - 180, 595), "VETERAN", fill="#1565c0", font=load_font(18, bold=True))

    result = _card_on_desk(card.convert("RGB"))
    draw2 = ImageDraw.Draw(result)
    _draw_footer(draw2, result.size[0], result.size[1])
    return _apply_watermark(result)


def render_ssn_card(h: "Household", p: "Person") -> Image.Image:
    w, hgt = 950, 620
    card = Image.new("RGB", (w, hgt), "#e8f4fc")
    draw = ImageDraw.Draw(card)
    draw.rectangle((0, 0, w, hgt), fill="#dbeafe")
    draw.rectangle((20, 20, w - 20, hgt - 20), outline="#1e3a8a", width=4)
    draw.rectangle((20, 20, w - 20, 110), fill="#1e40af")

    title_font = load_font(30, bold=True)
    body_font = load_font(22)
    ssn_font = load_font(40, bold=True, mono=True)
    small = load_font(18)

    draw.text((40, 38), "Social Security", fill="white", font=title_font)
    draw.text((40, 74), "YOUR SOCIAL SECURITY CARD", fill="#bfdbfe", font=small)

    y = 145
    lines = [
        "THIS NUMBER HAS BEEN ESTABLISHED FOR",
        p.display_name.upper(),
        p.ssn,
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
    ]
    for i, line in enumerate(lines):
        font = ssn_font if i == 2 else body_font
        color = "#111" if i != 2 else "#1e3a8a"
        draw.text((50, y), line, fill=color, font=font)
        y += 58 if i == 2 else 38

    draw.text((50, hgt - 95), "SIGNATURE", fill="#444", font=small)
    draw.line((140, hgt - 55, w - 60, hgt - 55), fill="#333", width=2)
    draw.text((50, hgt - 42), "Do not laminate. Sign in ink immediately.", fill="#666", font=load_font(15))

    result = _card_on_desk(card, rotation=1.8)
    draw2 = ImageDraw.Draw(result)
    _draw_footer(draw2, result.size[0], result.size[1])
    return _apply_watermark(result)


def render_passport(h: "Household", p: "Person") -> Image.Image:
    w, hgt = 1100, 1500
    img = Image.new("RGB", (w, hgt), "#f8f4e8")
    img = _add_paper_texture(img, 0.025)
    draw = ImageDraw.Draw(img)

    draw.rectangle((0, 0, w, 130), fill="#0b2f6a")
    title = load_font(38, bold=True)
    sub = load_font(24, bold=True)
    draw.text((48, 28), "PASSPORT", fill="white", font=title)
    draw.text((48, 78), "UNITED STATES OF AMERICA", fill="#dbeafe", font=sub)

    label_font = load_font(20)
    value_font = load_font(28, bold=True)
    y = 170
    months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    mm, dd, yyyy = p.dob.split("/")
    dob = f"{dd} {months[int(mm) - 1]} {yyyy}"
    rows = [
        ("Type", "P"),
        ("Country Code", "USA"),
        ("Passport No.", p.passport_number),
        ("Surname", p.last.upper()),
        ("Given Names", f"{p.first.upper()} {p.middle.upper()}".strip()),
        ("Nationality", "UNITED STATES OF AMERICA"),
        ("Date of Birth", dob),
        ("Place of Birth", f"{h.state}, U.S.A."),
        ("Date of Issue", "10 JAN 2020"),
        ("Date of Expiry", "09 JAN 2030"),
        ("Sex", _sex_label(p)),
    ]
    for label, value in rows:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 18

    _draw_photo(draw, (760, 170, 1020, 470), f"{p.first[0]}{p.last[0]}", bg="#cfd8dc")

    draw.line((40, 1120, w - 40, 1120), fill="#bbb", width=2)
    mrz_font = load_font(30, mono=True)
    line1, line2 = _passport_mrz(p, p.passport_number)
    draw.text((48, 1155), line1, fill="#111", font=mrz_font)
    draw.text((48, 1205), line2, fill="#111", font=mrz_font)

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def _ornate_certificate(title: str, lines: list[str], accent: str = "#1a365d") -> Image.Image:
    w, hgt = 1200, 1550
    img = Image.new("RGB", (w, hgt), "#fffdf7")
    img = _add_paper_texture(img, 0.03)
    draw = ImageDraw.Draw(img)

    margin = 50
    for offset in range(6):
        c = _hex_to_rgb(accent)
        fade = tuple(min(255, v + offset * 18) for v in c)
        draw.rectangle(
            (margin - offset, margin - offset, w - margin + offset, hgt - margin + offset),
            outline=fade,
            width=2,
        )

    draw.ellipse((w // 2 - 70, 90, w // 2 + 70, 230), outline=accent, width=3)
    draw.text((w // 2 - 55, 145), "SEAL", fill=accent, font=load_font(22, bold=True))

    title_font = load_font(42, bold=True)
    body_font = load_font(28)
    tb = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((w - (tb[2] - tb[0])) // 2, 280), title, fill=accent, font=title_font)
    draw.line((180, 350, w - 180, 350), fill=accent, width=2)

    y = 420
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=body_font)
        draw.text(((w - (bb[2] - bb[0])) // 2, y), line, fill="#222", font=body_font)
        y += 52

    draw.line((220, hgt - 220, 520, hgt - 220), fill="#444", width=2)
    draw.text((220, hgt - 205), "Registrar Signature", fill="#666", font=load_font(18))
    draw.line((w - 520, hgt - 220, w - 220, hgt - 220), fill="#444", width=2)
    draw.text((w - 520, hgt - 205), "County Clerk", fill="#666", font=load_font(18))

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_birth_certificate(h: "Household", p: "Person") -> Image.Image:
    lines = [
        f"BUREAU OF VITAL STATISTICS — {h.state}",
        f"COUNTY OF {h.county.upper()}",
        "",
        f"NAME: {p.full_name.upper()}",
        f"DATE OF BIRTH: {p.dob}",
        f"SEX: {_sex_label(p)}",
        f"PLACE OF BIRTH: {h.city.upper()}, {h.state}",
        f"REGISTRATION NO: BC-{h.id:02d}-{p.slug.upper()}",
    ]
    return _ornate_certificate("CERTIFICATE OF LIVE BIRTH", lines, "#1a365d")


def render_marriage_certificate(h: "Household", a: "Person", b: "Person") -> Image.Image:
    lines = [
        f"COUNTY CLERK — {h.county.upper()} COUNTY",
        f"STATE OF {h.state}",
        "",
        f"PARTY A: {a.display_name.upper()}",
        f"PARTY B: {b.display_name.upper()}",
        "DATE OF MARRIAGE: 06/01/2010",
        f"RECORD NO: MC-{h.id:02d}-001",
        f"PLACE: {h.city.upper()}, {h.state}",
    ]
    return _ornate_certificate("CERTIFICATE OF MARRIAGE", lines, "#702459")


def render_state_id(h: "Household", p: "Person") -> Image.Image:
    sid = p.state_id or f"S{h.id:02d}{p.slug[:3].upper()}001"
    header, bg, text = STATE_DL_COLORS.get(p.dl_state, ("#4a148c", "#f3e5f5", "#111"))
    w, hgt = 1050, 660
    card = _rounded_card((w, hgt))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, w - 1, hgt - 1), radius=24, fill=bg)
    draw.rectangle((0, 0, w, 90), fill=header)

    draw.text((28, 16), h.state, fill="white", font=load_font(34, bold=True))
    draw.text((28, 56), "IDENTIFICATION CARD", fill="#ede7f6", font=load_font(20, bold=True))
    draw.text((28, 82), "STATE ID", fill="#ede7f6", font=load_font(16, bold=True))
    draw.text((w - 280, 30), "NON-DRIVER IDENTIFICATION", fill="#ede7f6", font=load_font(16, bold=True))

    _draw_photo(draw, (36, 120, 230, 350), f"{p.first[0]}{p.last[0]}")
    x = 260
    y = 130
    for label, value in [
        ("NAME", p.display_name.upper()),
        ("ID", sid),
        ("DOB", p.dob),
        ("ADDRESS", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
    ]:
        if label:
            draw.text((x, y), f"{label}:", fill="#555", font=load_font(16))
            y += 22
        draw.text((x, y), value, fill=text, font=load_font(26, bold=True))
        y += 36

    _draw_barcode(draw, (36, 390, w - 36, 500), sid)
    result = _card_on_desk(card.convert("RGB"), rotation=-1.2)
    draw2 = ImageDraw.Draw(result)
    _draw_footer(draw2, result.size[0], result.size[1])
    return _apply_watermark(result)


def render_vehicle_registration(h: "Household", p: "Person") -> Image.Image:
    vin = f"1HGBH41JXMN{h.id:02d}{int(p.ssn[-4:]):04d}"
    plate = f"{h.state}-{h.id:02d}{p.slug[0].upper()}{p.slug[-1].upper()}"
    w, hgt = 1200, 1500
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = _add_paper_texture(img, 0.02)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 120), fill="#7f1d1d")
    draw.text((48, 30), f"STATE OF {h.state}", fill="white", font=load_font(34, bold=True))
    draw.text((48, 78), "DEPARTMENT OF MOTOR VEHICLES", fill="#fecaca", font=load_font(22, bold=True))

    title_font = load_font(36, bold=True)
    draw.text((48, 160), "VEHICLE REGISTRATION CERTIFICATE", fill="#111", font=title_font)

    label_font = load_font(20)
    value_font = load_font(28, bold=True)
    y = 250
    rows = [
        ("Registered Owner", p.display_name.upper()),
        ("VIN", vin),
        ("License Plate", plate),
        ("Make / Model", "2022 HONDA ACCORD"),
        ("Body Style", "4 DOOR SEDAN"),
        ("Expiration Date", "12/31/2026"),
        ("Registration Address", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
    ]
    for label, value in rows:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 22

    _draw_barcode(draw, (60, 980, w - 60, 1100), vin)
    draw.rectangle((60, 1140, w - 60, 1320), outline="#ccc", width=2)
    draw.text((80, 1165), "VALIDATION STICKER AREA", fill="#888", font=load_font(20, bold=True))

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_property_tax(h: "Household", p: "Person") -> Image.Image:
    assessed = 350_000 + h.id * 25_000
    tax_due = assessed // 50
    w, hgt = 1200, 1500
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = _add_paper_texture(img, 0.02)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 110), fill="#134e4a")
    draw.text((48, 28), f"{h.county.upper()} COUNTY TAX ASSESSOR-COLLECTOR", fill="white", font=load_font(30, bold=True))
    draw.text((48, 72), "PROPERTY TAX STATEMENT — TAX YEAR 2024", fill="#ccfbf1", font=load_font(20))

    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    y = 150
    rows = [
        ("Property Owner", p.display_name.upper()),
        ("Property Address", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("Account Number", f"PT-{h.id:02d}-{p.slug.upper()}"),
        ("Assessed Value", f"${assessed:,}"),
        ("Amount Due", f"${tax_due:,}.00"),
        ("Due Date", "01/31/2025"),
    ]
    for label, value in rows:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 18

    # summary table
    top = 620
    draw.rectangle((60, top, w - 60, top + 280), outline="#94a3b8", width=2)
    draw.rectangle((60, top, w - 60, top + 48), fill="#e2e8f0")
    cols = [("Description", 80), ("Taxing Unit", 420), ("Amount", 900)]
    for text, x in cols:
        draw.text((x, top + 12), text, fill="#111", font=load_font(20, bold=True))
    items = [
        ("General Fund", "County General", f"${tax_due // 3:,}.00"),
        ("School District", f"{h.city} ISD", f"${tax_due // 3:,}.00"),
        ("Hospital District", "Regional Health", f"${tax_due - 2 * (tax_due // 3):,}.00"),
    ]
    ry = top + 70
    for a, b, c in items:
        draw.text((80, ry), a, fill="#222", font=load_font(20))
        draw.text((420, ry), b, fill="#222", font=load_font(20))
        draw.text((900, ry), c, fill="#222", font=load_font(20, bold=True))
        ry += 52

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_utility_bill(h: "Household", p: "Person") -> Image.Image:
    providers = {
        "TX": "CITY OF AUSTIN ELECTRIC UTILITY",
        "OR": "PORTLAND GENERAL ELECTRIC",
        "CO": "XCEL ENERGY COLORADO",
        "WA": "SEATTLE CITY LIGHT",
        "FL": "FLORIDA POWER & LIGHT",
        "CA": "PACIFIC GAS & ELECTRIC",
        "IL": "COMED ELECTRIC UTILITY",
        "AZ": "APS ARIZONA PUBLIC SERVICE",
    }
    provider = providers.get(h.state, "REGIONAL ELECTRIC UTILITY")
    account = str(1_000_000_000 + h.id * 111_111)

    w, hgt = 1200, 1500
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 100), fill="#1d4ed8")
    draw.text((48, 28), provider, fill="white", font=load_font(30, bold=True))
    draw.text((48, 68), "ELECTRIC SERVICE BILL", fill="#bfdbfe", font=load_font(18, bold=True))

    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    y = 140
    rows = [
        ("Account Number", account),
        ("Billing Period", "12/01/2024 - 12/31/2024"),
        ("Service Address", p.display_name.upper()),
        ("", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("kWh Usage", "742"),
        ("Amount Due", "$125.00"),
        ("Due Date", "01/25/2025"),
    ]
    for label, value in rows:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 16

    draw.rectangle((60, 620, w - 60, 980), outline="#cbd5e1", width=2)
    draw.rectangle((60, 620, w - 60, 670), fill="#eff6ff")
    for text, x in [("Date", 80), ("Description", 260), ("Usage", 720), ("Charge", 920)]:
        draw.text((x, 636), text, fill="#111", font=load_font(18, bold=True))
    usage_rows = [
        ("12/05", "Energy Charge", "182 kWh", "$42.00"),
        ("12/12", "Energy Charge", "190 kWh", "$44.00"),
        ("12/19", "Energy Charge", "188 kWh", "$39.00"),
    ]
    ry = 700
    for a, b, c, d in usage_rows:
        draw.text((80, ry), a, fill="#222", font=load_font(18))
        draw.text((260, ry), b, fill="#222", font=load_font(18))
        draw.text((720, ry), c, fill="#222", font=load_font(18))
        draw.text((920, ry), d, fill="#222", font=load_font(18, bold=True))
        ry += 48

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_insurance_card(h: "Household", p: "Person") -> Image.Image:
    member_id = f"XYZ{h.id:02d}{p.passport_number[-6:]}"
    w, hgt = 980, 620
    card = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, w - 1, hgt - 1), radius=20, fill="#ffffff", outline="#2563eb", width=4)
    draw.rectangle((0, 0, w, 95), fill="#1d4ed8")
    draw.ellipse((w - 120, 18, w - 30, 78), fill="#60a5fa", outline="white", width=2)
    draw.text((36, 24), "BLUE CROSS BLUE SHIELD", fill="white", font=load_font(28, bold=True))
    draw.text((36, 64), "HEALTH PLAN", fill="#bfdbfe", font=load_font(18))

    label = load_font(16)
    value = load_font(24, bold=True)
    y = 120
    for lbl, val in [
        ("MEMBER ID", member_id),
        ("SUBSCRIBER", p.display_name.upper()),
        ("GROUP #", str(10000 + h.id)),
        ("DOB", p.dob),
        ("PLAN", "PPO"),
        ("RXBIN", "610014"),
    ]:
        draw.text((40, y), lbl, fill="#64748b", font=label)
        draw.text((40, y + 20), val, fill="#111", font=value)
        y += 68

    draw.text((40, hgt - 42), "Copay: $25  |  Deductible: $1,500", fill="#475569", font=load_font(16))
    result = _card_on_desk(card, rotation=2.0)
    draw2 = ImageDraw.Draw(result)
    _draw_footer(draw2, result.size[0], result.size[1])
    return _apply_watermark(result)


def render_bank_statement(h: "Household", p: "Person") -> Image.Image:
    w, hgt = 1200, 1500
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = _add_paper_texture(img, 0.02)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 100), fill="#334155")
    draw.text((48, 28), "FIRST NATIONAL BANK", fill="white", font=load_font(34, bold=True))
    draw.text((48, 68), "ACCOUNT STATEMENT", fill="#cbd5e1", font=load_font(20, bold=True))

    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    y = 140
    rows = [
        ("Statement Date", "01/31/2025"),
        ("Account Holder", p.display_name.upper()),
        ("Mailing Address", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("Routing Number", "021000021"),
        ("Account ending in", str(1000 + h.id)),
        ("Account Balance", "$1,234.56"),
    ]
    for label, value in rows:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 16

    draw.rectangle((60, 560, w - 60, 1020), outline="#cbd5e1", width=2)
    draw.rectangle((60, 560, w - 60, 610), fill="#f1f5f9")
    for text, x in [("Date", 80), ("Description", 240), ("Withdrawal", 720), ("Deposit", 880), ("Balance", 1020)]:
        draw.text((x, 576), text, fill="#111", font=load_font(18, bold=True))
    tx = [
        ("01/03", "Direct Deposit - Payroll", "", "$2,150.00", "$3,384.56"),
        ("01/08", "ACH Payment - Utility", "$125.00", "", "$3,259.56"),
        ("01/15", "Direct Deposit - Payroll", "", "$2,150.00", "$5,409.56"),
        ("01/22", "Debit Card Purchase", "$84.25", "", "$5,325.31"),
    ]
    ry = 640
    for a, b, c, d, e in tx:
        draw.text((80, ry), a, fill="#222", font=load_font(18))
        draw.text((240, ry), b, fill="#222", font=load_font(18))
        draw.text((720, ry), c, fill="#222", font=load_font(18))
        draw.text((880, ry), d, fill="#222", font=load_font(18))
        draw.text((1020, ry), e, fill="#222", font=load_font(18, bold=True))
        ry += 48

    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_w2_form(h: "Household", p: "Person") -> Image.Image:
    w, hgt = 1200, 1500
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 90), fill="#111827")
    draw.text((48, 20), "Form W-2 Wage and Tax Statement", fill="white", font=load_font(30, bold=True))
    draw.text((48, 58), "2024", fill="#d1d5db", font=load_font(22, bold=True))
    draw.rectangle((48, 120, w - 48, 1320), outline="#111", width=3)

    label_font = load_font(18)
    value_font = load_font(24, bold=True)
    boxes = [
        ("a Employee's SSA number", p.ssn, 70, 160, 520, 250),
        ("b Employer identification number (EIN)", f"{10 + h.id:02d}-{3456780 + h.id}", 560, 160, 1050, 250),
        ("c Employer's name, address", f"ACME CORPORATION #{h.id:02d}\n{h.address}\n{h.city} {h.state} {h.zip_code}", 70, 280, 1050, 430),
        ("e Employee's name", p.display_name.upper(), 70, 470, 1050, 560),
        ("1 Wages, tips, other compensation", "$84,500.00", 70, 600, 520, 690),
        ("2 Federal income tax withheld", "$12,450.00", 560, 600, 1050, 690),
        ("3 Social security wages", "$84,500.00", 70, 720, 520, 810),
        ("4 Social security tax withheld", "$5,239.00", 560, 720, 1050, 810),
    ]
    for label, value, x0, y0, x1, y1 in boxes:
        draw.rectangle((x0, y0, x1, y1), outline="#111", width=2)
        draw.text((x0 + 12, y0 + 10), label, fill="#444", font=label_font)
        draw.multiline_text((x0 + 12, y0 + 38), value, fill="#111", font=value_font, spacing=6)

    draw.text((70, 1380), "Copy B — To Be Filed With Employee's FEDERAL Tax Return", fill="#666", font=load_font(18))
    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


def render_pay_stub(h: "Household", p: "Person") -> Image.Image:
    w, hgt = 1200, 1100
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 90), fill="#4c1d95")
    draw.text((48, 24), f"ACME CORPORATION #{h.id:02d}", fill="white", font=load_font(32, bold=True))
    draw.text((48, 62), "EARNINGS STATEMENT", fill="#ddd6fe", font=load_font(18, bold=True))

    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    y = 130
    for label, value in [
        ("Employee", p.display_name),
        ("Employer", f"ACME CORPORATION #{h.id:02d}"),
        ("Pay Date", "01/15/2025"),
        ("Pay Period", "01/01/2025 - 01/15/2025"),
    ]:
        y = _draw_label_value(draw, 60, y, label, value, label_font, value_font, gap=4) + 14

    draw.rectangle((60, 360, w - 60, 760), outline="#cbd5e1", width=2)
    draw.rectangle((60, 360, w - 60, 410), fill="#f5f3ff")
    for text, x in [("Earnings", 80), ("Rate", 420), ("Hours", 620), ("Current", 820), ("YTD", 1020)]:
        draw.text((x, 376), text, fill="#111", font=load_font(18, bold=True))
    rows = [
        ("Regular", "$48.08", "80.00", "$3,846.40", "$3,846.40"),
        ("Bonus", "", "", "$403.60", "$403.60"),
    ]
    ry = 440
    for a, b, c, d, e in rows:
        draw.text((80, ry), a, fill="#222", font=load_font(18))
        draw.text((420, ry), b, fill="#222", font=load_font(18))
        draw.text((620, ry), c, fill="#222", font=load_font(18))
        draw.text((820, ry), d, fill="#222", font=load_font(18, bold=True))
        draw.text((1020, ry), e, fill="#222", font=load_font(18))
        ry += 48

    draw.text((60, 810), "NET PAY", fill="#444", font=load_font(22, bold=True))
    draw.text((220, 800), "$4,250.00", fill="#111", font=load_font(40, bold=True))
    _draw_footer(draw, w, hgt)
    return _apply_watermark(img)


RENDERERS = {
    "drivers_license": render_drivers_license,
    "ssn_card": render_ssn_card,
    "passport": render_passport,
    "birth_certificate": render_birth_certificate,
    "state_id": render_state_id,
    "vehicle_registration": render_vehicle_registration,
    "property_tax": render_property_tax,
    "utility_bill": render_utility_bill,
    "insurance_card": render_insurance_card,
    "bank_statement": render_bank_statement,
    "w2_tax": render_w2_form,
    "pay_stub": render_pay_stub,
}


def save_document(image: Image.Image, out_png: Path) -> None:
    out_png.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_png, "PNG", optimize=True)
    image.convert("RGB").save(out_png.with_suffix(".pdf"), "PDF", resolution=200.0)
