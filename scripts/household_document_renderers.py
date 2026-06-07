"""High-fidelity synthetic document renderers for household OCR test fixtures."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

from household_document_art import (
    add_paper_texture,
    apply_sample_watermark,
    desk_background,
    draw_bilingual_field,
    draw_code128_barcode,
    draw_footer,
    draw_ghost_photo,
    draw_guilloche,
    draw_hologram_patch,
    draw_label_value_row,
    draw_microprint_line,
    draw_pdf417_blocks,
    draw_realistic_photo,
    draw_security_mesh,
    draw_star,
    draw_state_seal,
    load_font,
    ornate_border,
    phone_scan_scene,
    save_document,
)

Household = Any
Person = Any

STATE_NAMES = {
    "TX": "TEXAS", "OR": "OREGON", "CO": "COLORADO", "WA": "WASHINGTON",
    "FL": "FLORIDA", "CA": "CALIFORNIA", "IL": "ILLINOIS", "AZ": "ARIZONA",
}

STATE_DL_THEME = {
    "TX": ("#0a2f7a", "#f2e3b3", "#102040", "#d32f2f"),
    "OR": ("#1b5e20", "#e8f5e9", "#1b4332", "#2e7d32"),
    "CO": ("#6d1b1b", "#fff8e1", "#4e342e", "#bf360c"),
    "WA": ("#0d47a1", "#e3f2fd", "#01579b", "#0277bd"),
    "FL": ("#b71c1c", "#fffde7", "#880e4f", "#f57f17"),
    "CA": ("#1a237e", "#fce4ec", "#311b92", "#c62828"),
    "IL": ("#263238", "#eceff1", "#37474f", "#455a64"),
    "AZ": ("#4a148c", "#f3e5f5", "#6a1b9a", "#ad1457"),
}


def _sex_label(person: Person) -> str:
    male = {
        "John", "Marcus", "David", "Carlos", "James", "Michael", "Thomas", "Kevin",
        "Raj", "Lucas", "Mateo", "Alexander",
    }
    return "M" if person.first in male else "F"


def _passport_digits(passport_no: str) -> str:
    digits = "".join(ch for ch in passport_no if ch.isdigit())
    return digits[-9:].rjust(9, "0")


def _passport_mrz(p: Person, passport_no: str) -> tuple[str, str]:
    mm, dd, yyyy = p.dob.split("/")
    yymmdd = f"{yyyy[2:]}{mm}{dd}"
    doc = _passport_digits(passport_no)
    line1 = f"P<USA{p.last.upper()}<<{p.first.upper()}<{p.middle.upper()}".ljust(44, "<")[:44]
    line2 = f"{doc}7USA{yymmdd}{_sex_label(p)}3001091234567890<<<<<<06".ljust(44, "<")[:44]
    return line1, line2


def _dob_passport(dob: str) -> str:
    months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    mm, dd, yyyy = dob.split("/")
    return f"{dd} {months[int(mm) - 1]} {yyyy}"


def render_drivers_license(h: Household, p: Person) -> Image.Image:
    """Landscape REAL ID-style driver license (Texas AAMVA field layout)."""
    state = p.dl_state
    header, bg, text, accent = STATE_DL_THEME.get(state, ("#0a2f7a", "#f2e3b3", "#102040", "#d32f2f"))
    w, hgt = 1280, 804  # CR80 landscape ratio
    card = Image.new("RGB", (w, hgt), bg)
    card = draw_security_mesh(card, (210, 220, 235))
    draw = ImageDraw.Draw(card)
    draw_guilloche(draw, (0, 90, w, hgt), "#d7c89a", 22)

    draw.rectangle((0, 0, w, 96), fill=header)
    draw.rectangle((0, 92, w, 96), fill=accent)
    state_name = STATE_NAMES.get(state, state)
    draw.text((24, 14), state_name, fill="white", font=load_font(40, bold=True))
    draw.text((24, 58), "DRIVER LICENSE", fill="#e3f2fd", font=load_font(22, bold=True))
    draw_star(draw, w - 70, 48, 24, "#ffc107")
    draw.text((w - 150, 30), "USA", fill="#ffc107", font=load_font(30, bold=True))
    draw.text((w - 150, 64), "REAL ID", fill="white", font=load_font(16, bold=True))

    draw_realistic_photo(card, (28, 118, 250, 430), f"{p.first[0]}{p.last[0]}")
    draw_ghost_photo(draw, (860, 360, 980, 500))
    draw_hologram_patch(draw, (1040, 130, 1140, 230))

    label_font = load_font(15)
    value_font = load_font(30, bold=True)
    small_font = load_font(20, bold=True)
    x, y = 280, 118
    fields = [
        ("4d. DL", p.dl_number, value_font),
        ("3. DOB", p.dob, small_font),
        ("1.", p.last.upper(), value_font),
        ("2.", p.first.upper(), value_font),
        ("8. Address", h.address.upper(), load_font(18)),
        ("", f"{h.city.upper()}, {state} {h.zip_code}", load_font(18)),
        ("4a. Iss", "01/10/2023", small_font),
        ("4b. Exp", "01/10/2028", small_font),
        ("9. Class", "C", small_font),
        ("12. Rest", "NONE", load_font(16)),
        ("16. Hgt", "5'-10\"", load_font(16)),
    ]
    for label, value, font in fields:
        if label:
            draw.text((x, y), label, fill="#444", font=label_font)
            y += 18
        draw.text((x, y), value, fill=text, font=font)
        y += 30 if font == value_font else 24

    draw_pdf417_blocks(draw, (28, 500, 430, 700), p.dl_number)
    draw_microprint_line(draw, 760, 40, w - 40, "DLDLDLDLDLDL")
    draw.text((450, 730), "LIMITED TERM", fill="#555", font=load_font(16, bold=True))
    draw.rectangle((450, 758, 560, 782), fill="#2e7d32")
    draw.text((462, 760), "DONOR", fill="white", font=load_font(16, bold=True))
    draw.rectangle((900, 758, 1030, 782), fill="#1565c0")
    draw.text((912, 760), "VETERAN", fill="white", font=load_font(16, bold=True))

    scene = phone_scan_scene(card, rotation=-2.8, desk_tone="#b0bec5")
    draw2 = ImageDraw.Draw(scene)
    draw_footer(draw2, scene.size[0], scene.size[1])
    return apply_sample_watermark(scene)


def render_ssn_card(h: Household, p: Person) -> Image.Image:
    """SSA card stock with blue/peach security tint and signature panel."""
    w, hgt = 1020, 640
    card = Image.new("RGB", (w, hgt), "#f7fbff")
    draw = ImageDraw.Draw(card)
    for y in range(hgt):
        t = y / hgt
        color = (int(230 - 40 * t), int(240 - 20 * t), int(255 - 10 * t))
        draw.line([(0, y), (w, y)], fill=color)
    draw_guilloche(draw, (30, 30, w - 30, hgt - 30), "#bbdefb", 18)
    draw.rectangle((24, 24, w - 24, hgt - 24), outline="#0d47a1", width=5)
    draw.rectangle((24, 24, w - 24, 128), fill="#0d47a1")
    draw_state_seal(draw, w - 120, 76, 46, "SSA", "#bbdefb")

    draw.text((48, 42), "Social Security", fill="white", font=load_font(34, bold=True, serif=True))
    draw.text((48, 84), "YOUR SOCIAL SECURITY CARD", fill="#e3f2fd", font=load_font(18, bold=True))

    body = load_font(22)
    ssn_font = load_font(44, bold=True, mono=True)
    y = 160
    for i, line in enumerate([
        "THIS NUMBER HAS BEEN ESTABLISHED FOR",
        p.display_name.upper(),
        p.ssn,
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
    ]):
        font = ssn_font if i == 2 else body
        color = "#0d47a1" if i == 2 else "#212121"
        draw.text((56, y), line, fill=color, font=font)
        y += 56 if i == 2 else 36

    draw.rectangle((56, hgt - 120, w - 56, hgt - 48), outline="#90a4ae", width=2, fill="#fafafa")
    draw.text((68, hgt - 112), "SIGNATURE", fill="#546e7a", font=load_font(16, bold=True))
    draw.line((170, hgt - 62, w - 80, hgt - 62), fill="#263238", width=2)
    draw.text((68, hgt - 38), "Do not laminate. Sign this card in ink immediately.", fill="#607d8b", font=load_font(14))

    scene = phone_scan_scene(card, rotation=2.2, desk_tone="#eceff1")
    draw2 = ImageDraw.Draw(scene)
    draw_footer(draw2, scene.size[0], scene.size[1])
    return apply_sample_watermark(scene)


def render_passport(h: Household, p: Person) -> Image.Image:
    """US passport biodata page with bilingual labels and MRZ."""
    w, hgt = 1240, 1754
    img = Image.new("RGB", (w, hgt), "#f3efe2")
    img = add_paper_texture(img, 0.03)
    img = draw_security_mesh(img, (225, 210, 195))
    draw = ImageDraw.Draw(img)
    draw_guilloche(draw, (0, 130, w, hgt), "#d7ccc8", 16)

    draw.rectangle((0, 0, w, 140), fill="#0b2f6a")
    draw.text((52, 34), "PASSPORT", fill="white", font=load_font(42, bold=True))
    draw.text((52, 88), "UNITED STATES OF AMERICA", fill="#dbeafe", font=load_font(24, bold=True))
    draw_state_seal(draw, w - 120, 70, 48, "USA", "#90caf9")

    label_font = load_font(18)
    value_font = load_font(30, bold=True)
    y = 180
    rows = [
        ("Type / Type", "P", "P"),
        ("Country Code / Code du pays", "USA", "USA"),
        ("Passport No. / No. du passeport", p.passport_number, p.passport_number),
        ("Surname / Nom", p.last.upper(), p.last.upper()),
        ("Given Names / Prenoms", f"{p.first.upper()} {p.middle.upper()}".strip(), f"{p.first.upper()} {p.middle.upper()}".strip()),
        ("Nationality / Nationalite", "UNITED STATES OF AMERICA", "UNITED STATES OF AMERICA"),
        ("Date of Birth / Date de naissance", _dob_passport(p.dob), _dob_passport(p.dob)),
        ("Place of Birth / Lieu de naissance", f"{h.state}, U.S.A.", f"{h.state}, U.S.A."),
        ("Date of Issue / Date de delivrance", "10 JAN 2020", "10 JAN 2020"),
        ("Date of Expiry / Date d'expiration", "09 JAN 2030", "09 JAN 2030"),
        ("Sex / Sexe", _sex_label(p), _sex_label(p)),
    ]
    for en, fr, value in rows:
        y = draw_bilingual_field(draw, 56, y, en.split(" / ")[0], fr, value, label_font, value_font)

    draw_realistic_photo(img, (820, 180, 1120, 560), f"{p.first[0]}{p.last[0]}")
    draw.line((56, 620, 760, 620), fill="#bbb", width=2)
    draw.text((56, 640), "Signature of Bearer", fill="#666", font=load_font(16))
    draw.line((56, 700, 520, 700), fill="#444", width=2)

    draw.line((40, 1280, w - 40, 1280), fill="#999", width=3)
    mrz_font = load_font(34, mono=True)
    line1, line2 = _passport_mrz(p, p.passport_number)
    draw.rectangle((36, 1310, w - 36, 1460), fill="#efebe2")
    draw.text((48, 1330), line1, fill="#111", font=mrz_font)
    draw.text((48, 1388), line2, fill="#111", font=mrz_font)

    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_birth_certificate(h: Household, p: Person) -> Image.Image:
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#fffdf8")
    img = add_paper_texture(img, 0.04)
    draw = ImageDraw.Draw(img)
    ornate_border(draw, 56, (w, hgt), "#1a365d", 6)
    draw_state_seal(draw, w // 2, 180, 78, h.state, "#1a365d")

    title_font = load_font(46, bold=True, serif=True)
    body_font = load_font(28, serif=True)
    label_font = load_font(20, bold=True)

    title = "CERTIFICATE OF LIVE BIRTH"
    tb = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((w - (tb[2] - tb[0])) // 2, 300), title, fill="#1a365d", font=title_font)
    draw.line((200, 370, w - 200, 370), fill="#1a365d", width=3)

    blocks = [
        (f"STATE OF {h.state}", f"BUREAU OF VITAL STATISTICS"),
        (f"COUNTY OF {h.county.upper()}", f"FILE NO. BC-{h.id:02d}-{p.slug.upper()}"),
        ("CHILD'S NAME", p.full_name.upper()),
        ("DATE OF BIRTH", p.dob),
        ("SEX", _sex_label(p)),
        ("PLACE OF BIRTH", f"{h.city.upper()}, {h.state}"),
        ("HOSPITAL / FACILITY", f"{h.city.upper()} GENERAL HOSPITAL"),
        ("MOTHER'S MAIDEN NAME", f"{p.last.upper()}, JANE"),
        ("FATHER'S NAME", f"{p.last.upper()}, ROBERT"),
    ]
    y = 430
    for label, value in blocks:
        draw.text((180, y), label, fill="#4a5568", font=label_font)
        draw.text((180, y + 28), value, fill="#111", font=body_font)
        y += 78

    draw.line((200, hgt - 250, 500, hgt - 250), fill="#444", width=2)
    draw.text((200, hgt - 230), "Registrar of Vital Records", fill="#666", font=load_font(18, serif=True))
    draw.line((w - 500, hgt - 250, w - 200, hgt - 250), fill="#444", width=2)
    draw.text((w - 500, hgt - 230), "County Health Officer", fill="#666", font=load_font(18, serif=True))
    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_marriage_certificate(h: Household, a: Person, b: Person) -> Image.Image:
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#fff9fb")
    img = add_paper_texture(img, 0.04)
    draw = ImageDraw.Draw(img)
    ornate_border(draw, 56, (w, hgt), "#702459", 6)
    draw_state_seal(draw, w // 2, 180, 78, h.state, "#702459")

    title = "CERTIFICATE OF MARRIAGE"
    title_font = load_font(46, bold=True, serif=True)
    body_font = load_font(30, serif=True)
    tb = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((w - (tb[2] - tb[0])) // 2, 300), title, fill="#702459", font=title_font)
    draw.line((200, 370, w - 200, 370), fill="#702459", width=3)

    y = 430
    lines = [
        f"COUNTY CLERK — {h.county.upper()} COUNTY, {h.state}",
        f"RECORD NO. MC-{h.id:02d}-001",
        "",
        "THIS CERTIFIES THAT THE RITE OF MATRIMONY WAS CELEBRATED BETWEEN:",
        "",
        f"PARTY A: {a.display_name.upper()}",
        f"PARTY B: {b.display_name.upper()}",
        "",
        "DATE OF MARRIAGE: 06/01/2010",
        f"PLACE OF MARRIAGE: {h.city.upper()}, {h.state}",
    ]
    for line in lines:
        if not line:
            y += 20
            continue
        bb = draw.textbbox((0, 0), line, font=body_font)
        draw.text(((w - (bb[2] - bb[0])) // 2, y), line, fill="#222", font=body_font)
        y += 56

    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_state_id(h: Household, p: Person) -> Image.Image:
    sid = p.state_id or f"S{h.id:02d}{p.slug[:3].upper()}001"
    header, bg, text, accent = STATE_DL_THEME.get(p.dl_state, ("#4a148c", "#f3e5f5", "#311b92", "#6a1b9a"))
    w, hgt = 1280, 804
    card = Image.new("RGB", (w, hgt), bg)
    card = draw_security_mesh(card, (220, 210, 230))
    draw = ImageDraw.Draw(card)
    draw.rectangle((0, 0, w, 96), fill=header)
    draw.rectangle((0, 92, w, 96), fill=accent)
    draw.text((24, 14), h.state, fill="white", font=load_font(38, bold=True))
    draw.text((24, 56), "IDENTIFICATION CARD", fill="#ede7f6", font=load_font(22, bold=True))
    draw.text((w - 360, 24), "STATE ID", fill="white", font=load_font(28, bold=True))
    draw.text((w - 360, 62), "NON-DRIVER IDENTIFICATION", fill="#e1bee7", font=load_font(16, bold=True))

    draw_realistic_photo(card, (28, 118, 250, 430), f"{p.first[0]}{p.last[0]}")
    x, y = 280, 130
    for label, value in [
        ("NAME", p.display_name.upper()),
        ("ID NUMBER", sid),
        ("DATE OF BIRTH", p.dob),
        ("ADDRESS", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("ISSUED", "01/10/2023"),
        ("EXPIRES", "01/10/2028"),
    ]:
        if label:
            draw.text((x, y), label, fill="#555", font=load_font(15, bold=True))
            y += 18
        draw.text((x, y), value, fill=text, font=load_font(28 if label in {"NAME", "ID NUMBER"} else 20, bold=True))
        y += 34

    draw_code128_barcode(draw, (28, 500, w - 28, 620), sid)
    scene = phone_scan_scene(card, rotation=-1.5, desk_tone="#cfd8dc")
    draw2 = ImageDraw.Draw(scene)
    draw_footer(draw2, scene.size[0], scene.size[1])
    return apply_sample_watermark(scene)


def render_vehicle_registration(h: Household, p: Person) -> Image.Image:
    vin = f"1HGBH41JXMN{h.id:02d}{int(p.ssn[-4:]):04d}"
    plate = f"{h.state}-{h.id:02d}{p.slug[0].upper()}{p.slug[-1].upper()}"
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = add_paper_texture(img, 0.025)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 130), fill="#7f1d1d")
    draw_state_seal(draw, w - 110, 65, 42, h.state, "#ffcdd2")
    draw.text((48, 28), f"STATE OF {h.state}", fill="white", font=load_font(36, bold=True))
    draw.text((48, 78), "DEPARTMENT OF MOTOR VEHICLES", fill="#fecaca", font=load_font(22, bold=True))

    draw.text((48, 170), "VEHICLE REGISTRATION / TITLE APPLICATION", fill="#111", font=load_font(34, bold=True))
    label_font = load_font(20)
    value_font = load_font(28, bold=True)
    y = 250
    for label, value in [
        ("Registered Owner", p.display_name.upper()),
        ("Co-Owner", "NONE"),
        ("Vehicle Identification Number (VIN)", vin),
        ("License Plate Number", plate),
        ("Year / Make / Model", "2022 HONDA ACCORD"),
        ("Body Style", "4 DOOR SEDAN"),
        ("Registration Expiration", "12/31/2026"),
        ("Garaging Address", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
    ]:
        y = draw_label_value_row(draw, 60, y, label, value, label_font, value_font, 360) + 10

    draw.rectangle((60, 900, w - 60, 1080), outline="#bdbdbd", width=2)
    draw.text((80, 920), "REGISTRATION STICKER / VALIDATION AREA", fill="#757575", font=load_font(20, bold=True))
    draw_code128_barcode(draw, (80, 960, w - 80, 1060), vin)
    draw.rectangle((60, 1120, w - 60, 1280), fill="#fafafa", outline="#ccc", width=2)
    draw.text((80, 1145), "COUNTY: " + h.county.upper(), fill="#333", font=load_font(22, bold=True))
    draw.text((80, 1190), "FEE PAID: $78.50", fill="#333", font=load_font(22))

    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_property_tax(h: Household, p: Person) -> Image.Image:
    assessed = 350_000 + h.id * 25_000
    tax_due = assessed // 50
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = add_paper_texture(img, 0.025)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 120), fill="#134e4a")
    draw_state_seal(draw, 90, 60, 40, h.county[:3].upper(), "#b2dfdb")
    draw.text((160, 28), f"{h.county.upper()} COUNTY TAX ASSESSOR-COLLECTOR", fill="white", font=load_font(30, bold=True))
    draw.text((160, 78), "2024 PROPERTY TAX STATEMENT", fill="#ccfbf1", font=load_font(22, bold=True))

    y = 160
    label_font = load_font(20)
    value_font = load_font(28, bold=True)
    for label, value in [
        ("Property Owner", p.display_name.upper()),
        ("Property Location", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("Account Number", f"PT-{h.id:02d}-{p.slug.upper()}"),
        ("Legal Description", f"LOT 12 BLK 4 {h.city.upper()} ESTATES"),
        ("Market Value", f"${assessed:,}"),
        ("Assessed Value", f"${int(assessed * 0.9):,}"),
        ("Total Tax Due", f"${tax_due:,}.00"),
        ("Due Date", "01/31/2025"),
    ]:
        y = draw_label_value_row(draw, 60, y, label, value, label_font, value_font, 280) + 8

    top = 700
    draw.rectangle((60, top, w - 60, top + 320), outline="#94a3b8", width=2)
    draw.rectangle((60, top, w - 60, top + 48), fill="#e2e8f0")
    for text, x in [("Jurisdiction", 80), ("Taxing Unit", 420), ("Rate", 760), ("Amount", 980)]:
        draw.text((x, top + 12), text, fill="#111", font=load_font(20, bold=True))
    items = [
        ("County General Fund", "County Operations", "0.412%", f"${tax_due // 3:,}.00"),
        ("School District", f"{h.city} ISD", "1.174%", f"${tax_due // 3:,}.00"),
        ("Hospital District", "Regional Health", "0.238%", f"${tax_due - 2 * (tax_due // 3):,}.00"),
    ]
    ry = top + 70
    for a, b, c, d in items:
        draw.text((80, ry), a, fill="#222", font=load_font(19))
        draw.text((420, ry), b, fill="#222", font=load_font(19))
        draw.text((760, ry), c, fill="#222", font=load_font(19))
        draw.text((980, ry), d, fill="#222", font=load_font(19, bold=True))
        ry += 54

    draw.line((60, 1380, w - 60, 1380), fill="#bbb", width=2)
    draw.text((80, 1400), "PAYMENT STUB — DETACH ALONG PERFORATION", fill="#666", font=load_font(18, bold=True))
    draw.text((80, 1440), f"Amount Enclosed: ${tax_due:,}.00", fill="#111", font=load_font(24, bold=True))
    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_utility_bill(h: Household, p: Person) -> Image.Image:
    providers = {
        "TX": "CITY OF AUSTIN ELECTRIC UTILITY", "OR": "PORTLAND GENERAL ELECTRIC",
        "CO": "XCEL ENERGY COLORADO", "WA": "SEATTLE CITY LIGHT", "FL": "FLORIDA POWER & LIGHT",
        "CA": "PACIFIC GAS & ELECTRIC", "IL": "COMED", "AZ": "APS ARIZONA PUBLIC SERVICE",
    }
    provider = providers.get(h.state, "REGIONAL ELECTRIC UTILITY")
    account = str(1_000_000_000 + h.id * 111_111)
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 110), fill="#1d4ed8")
    draw.ellipse((w - 120, 20, w - 30, 90), fill="#60a5fa", outline="white", width=2)
    draw.text((48, 28), provider, fill="white", font=load_font(32, bold=True))
    draw.text((48, 72), "ELECTRIC SERVICE INVOICE", fill="#bfdbfe", font=load_font(20, bold=True))

    draw.rectangle((60, 140, 560, 360), outline="#cbd5e1", width=2, fill="#f8fafc")
    draw.text((80, 160), "Account Number", fill="#64748b", font=load_font(18))
    draw.text((80, 190), account, fill="#111", font=load_font(30, bold=True, mono=True))
    draw.text((80, 250), "Service Address", fill="#64748b", font=load_font(18))
    draw.text((80, 280), p.display_name.upper(), fill="#111", font=load_font(22, bold=True))
    draw.text((80, 310), h.address.upper(), fill="#111", font=load_font(20))
    draw.text((80, 338), f"{h.city.upper()} {h.state} {h.zip_code}", fill="#111", font=load_font(20))

    draw.rectangle((600, 140, w - 60, 360), outline="#1d4ed8", width=3, fill="#eff6ff")
    draw.text((630, 170), "Amount Due", fill="#1e40af", font=load_font(22, bold=True))
    draw.text((630, 220), "$125.00", fill="#111", font=load_font(52, bold=True))
    draw.text((630, 290), "Due Date: 01/25/2025", fill="#334155", font=load_font(22))
    draw.text((630, 322), "Billing Period: 12/01/2024 - 12/31/2024", fill="#334155", font=load_font(18))

    draw.rectangle((60, 400, w - 60, 760), outline="#cbd5e1", width=2)
    draw.rectangle((60, 400, w - 60, 450), fill="#eff6ff")
    for text, x in [("Read Date", 80), ("Description", 260), ("Meter Reading", 620), ("Usage", 820), ("Charge", 1040)]:
        draw.text((x, 416), text, fill="#111", font=load_font(18, bold=True))
    rows = [
        ("11/30", "Previous Read", "18,442", "", ""),
        ("12/31", "Current Read", "19,184", "742 kWh", "$125.00"),
    ]
    ry = 480
    for row in rows:
        for val, x in zip(row, [80, 260, 620, 820, 1040]):
            draw.text((x, ry), val, fill="#222", font=load_font(18))
        ry += 48

    draw.rectangle((60, 800, w - 60, 980), fill="#f8fafc", outline="#cbd5e1", width=2)
    draw.text((80, 830), "Usage History (kWh)", fill="#334155", font=load_font(20, bold=True))
    for i, hval in enumerate([620, 680, 710, 742]):
        x = 120 + i * 180
        draw.rectangle((x, 980 - hval // 2, x + 80, 940), fill="#3b82f6")
        draw.text((x + 10, 950), str(hval), fill="#111", font=load_font(16))

    draw.line((60, 1420, w - 60, 1420), fill="#bbb", width=2)
    draw.text((80, 1440), "REMITTANCE STUB", fill="#666", font=load_font(18, bold=True))
    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_insurance_card(h: Household, p: Person) -> Image.Image:
    member_id = f"XYZ{h.id:02d}{p.passport_number[-6:]}"
    w, hgt = 1016, 638
    card = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, w - 1, hgt - 1), radius=22, outline="#1d4ed8", width=4)
    draw.rectangle((0, 0, w, 100), fill="#1d4ed8")
    draw.ellipse((w - 130, 16, w - 24, 84), fill="#60a5fa", outline="white", width=2)
    draw.text((28, 20), "BLUE CROSS BLUE SHIELD", fill="white", font=load_font(28, bold=True))
    draw.text((28, 58), "PPO MEDICAL PLAN", fill="#bfdbfe", font=load_font(18, bold=True))

    left_x, right_x = 28, 520
    y = 120
    for lbl, val in [
        ("MEMBER ID", member_id),
        ("SUBSCRIBER", p.display_name.upper()),
        ("GROUP", str(10000 + h.id)),
        ("DOB", p.dob),
    ]:
        draw.text((left_x, y), lbl, fill="#64748b", font=load_font(14, bold=True))
        draw.text((left_x, y + 18), val, fill="#111", font=load_font(24, bold=True))
        y += 62

    draw.line((500, 110, 500, hgt - 30), fill="#cbd5e1", width=2)
    draw.text((right_x, 120), "RX BIN / PCN", fill="#64748b", font=load_font(14, bold=True))
    draw.text((right_x, 144), "610014 / ADV", fill="#111", font=load_font(24, bold=True))
    draw.text((right_x, 220), "COPAY", fill="#64748b", font=load_font(14, bold=True))
    draw.text((right_x, 244), "$25 Office  |  $50 Specialist", fill="#111", font=load_font(18))
    draw.text((right_x, 310), "DEDUCTIBLE", fill="#64748b", font=load_font(14, bold=True))
    draw.text((right_x, 334), "$1,500 Individual", fill="#111", font=load_font(20, bold=True))
    draw.rectangle((right_x, 400, w - 28, 470), fill="#e3f2fd", outline="#90caf9", width=2)
    draw.text((right_x + 12, 420), "Medical Claims: 800-555-0100", fill="#1565c0", font=load_font(16, bold=True))

    draw.rectangle((0, hgt - 36, w, hgt), fill="#f1f5f9")
    draw.text((28, hgt - 28), "Present this card when receiving care", fill="#475569", font=load_font(14))
    scene = phone_scan_scene(card, rotation=1.6, desk_tone="#eceff1")
    draw2 = ImageDraw.Draw(scene)
    draw_footer(draw2, scene.size[0], scene.size[1])
    return apply_sample_watermark(scene)


def render_bank_statement(h: Household, p: Person) -> Image.Image:
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#ffffff")
    img = add_paper_texture(img, 0.02)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 110), fill="#1e293b")
    draw_state_seal(draw, w - 100, 55, 36, "FNB", "#cbd5e1")
    draw.text((48, 28), "FIRST NATIONAL BANK", fill="white", font=load_font(34, bold=True))
    draw.text((48, 72), "CONSOLIDATED ACCOUNT STATEMENT", fill="#cbd5e1", font=load_font(20, bold=True))

    y = 150
    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    for label, value in [
        ("Statement Period", "01/01/2025 - 01/31/2025"),
        ("Primary Account Holder", p.display_name.upper()),
        ("Mailing Address", h.address.upper()),
        ("", f"{h.city.upper()} {h.state} {h.zip_code}"),
        ("Routing Number", "021000021"),
        ("Account Number", f"**** **** {1000 + h.id}"),
        ("Ending Balance", "$1,234.56"),
    ]:
        y = draw_label_value_row(draw, 60, y, label, value, label_font, value_font, 300) + 8

    draw.rectangle((60, 520, w - 60, 1080), outline="#cbd5e1", width=2)
    draw.rectangle((60, 520, w - 60, 570), fill="#f8fafc")
    for text, x in [("Date", 80), ("Description", 220), ("Withdrawals", 720), ("Deposits", 900), ("Balance", 1080)]:
        draw.text((x, 536), text, fill="#111", font=load_font(18, bold=True))
    tx = [
        ("01/03", "ACH DEPOSIT PAYROLL ACME", "", "$2,150.00", "$3,384.56"),
        ("01/08", "ONLINE PMT UTILITY", "$125.00", "", "$3,259.56"),
        ("01/15", "ACH DEPOSIT PAYROLL ACME", "", "$2,150.00", "$5,409.56"),
        ("01/22", "DEBIT CARD PURCHASE", "$84.25", "", "$5,325.31"),
        ("01/28", "MONTHLY SERVICE FEE", "$12.00", "", "$1,234.56"),
    ]
    ry = 600
    for row in tx:
        for val, x in zip(row, [80, 220, 720, 900, 1080]):
            draw.text((x, ry), val, fill="#222", font=load_font(18))
        ry += 44

    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_w2_form(h: Household, p: Person) -> Image.Image:
    w, hgt = 1275, 1650
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 100), fill="#111827")
    draw.text((48, 20), "Form W-2 Wage and Tax Statement", fill="white", font=load_font(32, bold=True))
    draw.text((48, 62), "2024  —  Copy B (To Be Filed With Employee's FEDERAL Tax Return)", fill="#d1d5db", font=load_font(18))

    boxes = [
        ("a Employee's social security number", p.ssn, 50, 130, 600, 220),
        ("b Employer identification number (EIN)", f"{10 + h.id:02d}-{3456780 + h.id}", 620, 130, 1220, 220),
        ("c Employer's name, address, and ZIP code", f"ACME CORPORATION #{h.id:02d}\n{h.address}\n{h.city} {h.state} {h.zip_code}", 50, 240, 1220, 390),
        ("e Employee's first name and initial Last name", f"{p.first[0]}  {p.display_name.upper()}", 50, 410, 1220, 500),
        ("1 Wages, tips, other compensation", "84500.00", 50, 530, 420, 620),
        ("2 Federal income tax withheld", "12450.00", 440, 530, 820, 620),
        ("3 Social security wages", "84500.00", 840, 530, 1220, 620),
        ("4 Social security tax withheld", "5239.00", 50, 640, 420, 730),
        ("5 Medicare wages and tips", "84500.00", 440, 640, 820, 730),
        ("6 Medicare tax withheld", "1225.25", 840, 640, 1220, 730),
        ("12a Code D", "4100.00", 50, 760, 420, 850),
        ("12b Code DD", "9200.00", 440, 760, 820, 850),
        ("15 State", h.state, 50, 880, 220, 970),
        ("16 State wages, tips, etc.", "84500.00", 240, 880, 620, 970),
        ("17 State income tax", "3850.00", 640, 880, 1220, 970),
    ]
    label_font = load_font(16)
    value_font = load_font(24, bold=True)
    for label, value, x0, y0, x1, y1 in boxes:
        draw.rectangle((x0, y0, x1, y1), outline="#111", width=2)
        draw.rectangle((x0, y0, x1, y0 + 28), fill="#fee2e2")
        draw.text((x0 + 10, y0 + 4), label, fill="#444", font=label_font)
        draw.multiline_text((x0 + 12, y0 + 36), value, fill="#111", font=value_font, spacing=4)

    draw.text((50, 1040), "Department of the Treasury — Internal Revenue Service", fill="#666", font=load_font(18))
    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


def render_pay_stub(h: Household, p: Person) -> Image.Image:
    w, hgt = 1275, 1275
    img = Image.new("RGB", (w, hgt), "#ffffff")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 100), fill="#4c1d95")
    draw.text((48, 24), f"ACME CORPORATION #{h.id:02d}", fill="white", font=load_font(34, bold=True))
    draw.text((48, 64), "EARNINGS STATEMENT", fill="#ddd6fe", font=load_font(20, bold=True))

    y = 130
    label_font = load_font(20)
    value_font = load_font(26, bold=True)
    for label, value in [
        ("Employee Name", p.display_name),
        ("Employee ID", f"EMP-{h.id:02d}{p.slug[:3].upper()}"),
        ("Pay Date", "01/15/2025"),
        ("Pay Period", "01/01/2025 - 01/15/2025"),
    ]:
        y = draw_label_value_row(draw, 60, y, label, value, label_font, value_font, 260) + 6

    draw.rectangle((60, 360, w - 60, 920), outline="#cbd5e1", width=2)
    draw.rectangle((60, 360, w - 60, 410), fill="#f5f3ff")
    for text, x in [("Earnings", 80), ("Rate", 420), ("Hours", 620), ("Current", 860), ("YTD", 1080)]:
        draw.text((x, 376), text, fill="#111", font=load_font(18, bold=True))
    rows = [
        ("Regular", "$48.08", "80.00", "$3,846.40", "$3,846.40"),
        ("Overtime", "$72.12", "0.00", "$0.00", "$0.00"),
        ("Bonus", "", "", "$403.60", "$403.60"),
    ]
    ry = 440
    for row in rows:
        for val, x in zip(row, [80, 420, 620, 860, 1080]):
            draw.text((x, ry), val, fill="#222", font=load_font(18))
        ry += 44

    draw.rectangle((60, 940, w - 60, 1160), outline="#cbd5e1", width=2)
    draw.rectangle((60, 940, w - 60, 990), fill="#faf5ff")
    for text, x in [("Deductions", 80), ("Current", 860), ("YTD", 1080)]:
        draw.text((x, 956), text, fill="#111", font=load_font(18, bold=True))
    for i, (name, cur, ytd) in enumerate([("Federal Tax", "$1,038.00", "$1,038.00"), ("Social Security", "$238.50", "$238.50"), ("Medicare", "$55.75", "$55.75")]):
        draw.text((80, 1020 + i * 40), name, fill="#222", font=load_font(18))
        draw.text((860, 1020 + i * 40), cur, fill="#222", font=load_font(18))
        draw.text((1080, 1020 + i * 40), ytd, fill="#222", font=load_font(18))

    draw.rectangle((60, 1180, w - 60, 1260), fill="#ede7f6", outline="#7c3aed", width=2)
    draw.text((80, 1200), "NET PAY", fill="#4c1d95", font=load_font(24, bold=True))
    draw.text((260, 1190), "$4,250.00", fill="#111", font=load_font(44, bold=True))
    draw_footer(draw, w, hgt)
    return apply_sample_watermark(img)


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
