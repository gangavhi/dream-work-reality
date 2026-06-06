#!/usr/bin/env python3
"""Generate synthetic household document fixtures for mobile app OCR testing.

All people, IDs, and addresses are fictional. Output: PNG + PDF per document.
"""
from __future__ import annotations

import json
import textwrap
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "demo" / "sample-documents" / "household-fixtures"

WATERMARK = "SAMPLE — FICTIONAL — FOR TESTING ONLY"


@dataclass(frozen=True)
class Person:
    slug: str
    first: str
    middle: str
    last: str
    dob: str  # MM/DD/YYYY
    ssn: str
    dl_number: str
    dl_state: str
    passport_number: str
    state_id: str | None = None

    @property
    def full_name(self) -> str:
        if self.middle:
            return f"{self.first} {self.middle} {self.last}"
        return f"{self.first} {self.last}"

    @property
    def display_name(self) -> str:
        return f"{self.first} {self.last}"


@dataclass(frozen=True)
class Household:
    id: int
    slug: str
    label: str
    city: str
    state: str
    zip_code: str
    address: str
    county: str
    members: tuple[Person, ...]
    spouse_pair: tuple[str, str] | None = None  # person slugs


HOUSEHOLDS: list[Household] = [
    Household(
        1,
        "miller-family",
        "Miller Family (Austin, TX)",
        "Austin",
        "TX",
        "78701",
        "742 Oak Street",
        "Travis",
        (
            Person("john", "John", "Robert", "Miller", "06/12/1980", "900-01-1001", "D10000001", "TX", "P100000001"),
            Person("sarah", "Sarah", "Anne", "Miller", "03/15/1985", "900-01-1002", "D10000002", "TX", "P100000002"),
            Person("lucas", "Lucas", "James", "Miller", "09/10/2012", "900-01-1003", "D10000003", "TX", "P100000003", "S10000003"),
        ),
        ("john", "sarah"),
    ),
    Household(
        2,
        "chen-family",
        "Chen Family (Portland, OR)",
        "Portland",
        "OR",
        "97201",
        "88 Pine Avenue",
        "Multnomah",
        (
            Person("alexander", "Alexander", "Wei", "Chen", "03/15/1985", "900-02-1001", "C20000001", "OR", "P200000001"),
            Person("mei", "Mei", "Ling", "Chen", "11/22/1987", "900-02-1002", "C20000002", "OR", "P200000002"),
        ),
        ("alexander", "mei"),
    ),
    Household(
        3,
        "patel-family",
        "Patel Family (Houston, TX)",
        "Houston",
        "TX",
        "77002",
        "1200 Bayou Lane",
        "Harris",
        (
            Person("priya", "Priya", "K", "Patel", "01/08/1983", "900-03-1001", "D30000001", "TX", "P300000001"),
            Person("raj", "Raj", "V", "Patel", "07/19/1979", "900-03-1002", "D30000002", "TX", "P300000002"),
            Person("anika", "Anika", "R", "Patel", "04/02/2014", "900-03-1003", "D30000003", "TX", "P300000003", "S30000003"),
        ),
        ("priya", "raj"),
    ),
    Household(
        4,
        "johnson-household",
        "Johnson Household (Denver, CO)",
        "Denver",
        "CO",
        "80202",
        "450 Mountain View Rd",
        "Denver",
        (Person("marcus", "Marcus", "Lee", "Johnson", "12/01/1975", "900-04-1001", "J40000001", "CO", "P400000001"),),
    ),
    Household(
        5,
        "williams-family",
        "Williams Family (Seattle, WA)",
        "Seattle",
        "WA",
        "98101",
        "210 Harbor Street",
        "King",
        (
            Person("emily", "Emily", "Rose", "Williams", "05/30/1988", "900-05-1001", "W50000001", "WA", "P500000001"),
            Person("david", "David", "Paul", "Williams", "08/14/1986", "900-05-1002", "W50000002", "WA", "P500000002"),
        ),
        ("emily", "david"),
    ),
    Household(
        6,
        "garcia-family",
        "Garcia Family (Miami, FL)",
        "Miami",
        "FL",
        "33101",
        "55 Coral Way",
        "Miami-Dade",
        (
            Person("sofia", "Sofia", "Maria", "Garcia", "02/18/1990", "900-06-1001", "G60000001", "FL", "P600000001"),
            Person("carlos", "Carlos", "Miguel", "Garcia", "10/05/1988", "900-06-1002", "G60000002", "FL", "P600000002"),
            Person("mateo", "Mateo", "Luis", "Garcia", "06/25/2016", "900-06-1003", "G60000003", "FL", "P600000003", "S60000003"),
        ),
        ("sofia", "carlos"),
    ),
    Household(
        7,
        "kim-family",
        "Kim Family (Los Angeles, CA)",
        "Los Angeles",
        "CA",
        "90012",
        "900 Sunset Boulevard",
        "Los Angeles",
        (
            Person("jennifer", "Jennifer", "Soo", "Kim", "09/09/1992", "900-07-1001", "K70000001", "CA", "P700000001"),
            Person("james", "James", "H", "Kim", "01/27/1990", "900-07-1002", "K70000002", "CA", "P700000002"),
        ),
        ("jennifer", "james"),
    ),
    Household(
        8,
        "brown-household",
        "Brown Household (Chicago, IL)",
        "Chicago",
        "IL",
        "60601",
        "300 Lake Shore Drive",
        "Cook",
        (Person("michael", "Michael", "Thomas", "Brown", "04/04/1978", "900-08-1001", "B80000001", "IL", "P800000001"),),
    ),
    Household(
        9,
        "davis-family",
        "Davis Family (Phoenix, AZ)",
        "Phoenix",
        "AZ",
        "85001",
        "1600 Desert Palm Dr",
        "Maricopa",
        (
            Person("rachel", "Rachel", "Kay", "Davis", "07/07/1984", "900-09-1001", "D90000001", "AZ", "P900000001"),
            Person("thomas", "Thomas", "Ray", "Davis", "03/03/1982", "900-09-1002", "D90000002", "AZ", "P900000002"),
            Person("olivia", "Olivia", "Grace", "Davis", "12/12/2015", "900-09-1003", "D90000003", "AZ", "P900000003", "S90000003"),
        ),
        ("rachel", "thomas"),
    ),
    Household(
        10,
        "nguyen-family",
        "Nguyen Family (San Jose, CA)",
        "San Jose",
        "CA",
        "95110",
        "425 Silicon Valley Blvd",
        "Santa Clara",
        (
            Person("linda", "Linda", "Thi", "Nguyen", "06/16/1991", "900-10-1001", "N10000001", "CA", "P100000001"),
            Person("kevin", "Kevin", "Minh", "Nguyen", "10/20/1989", "900-10-1002", "N10000002", "CA", "P100000002"),
        ),
        ("linda", "kevin"),
    ),
]

DOC_COLORS = {
    "birth_certificate": ("#1a365d", "#ebf8ff"),
    "ssn_card": ("#22543d", "#f0fff4"),
    "drivers_license": ("#744210", "#fffaf0"),
    "passport": ("#2c5282", "#ebf8ff"),
    "state_id": ("#553c9a", "#faf5ff"),
    "vehicle_registration": ("#9c4221", "#fff5f5"),
    "property_tax": ("#285e61", "#e6fffa"),
    "marriage_certificate": ("#702459", "#fff5f7"),
    "utility_bill": ("#2b6cb0", "#ebf8ff"),
    "insurance_card": ("#2f855a", "#f0fff4"),
    "bank_statement": ("#4a5568", "#f7fafc"),
    "w2_tax": ("#c05621", "#fffaf0"),
    "pay_stub": ("#6b46c1", "#faf5ff"),
}


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def person_by_slug(household: Household, slug: str) -> Person:
    for member in household.members:
        if member.slug == slug:
            return member
    raise KeyError(slug)


def render_document(title: str, doc_type: str, lines: list[str], out_png: Path) -> None:
    header_color, bg_color = DOC_COLORS.get(doc_type, ("#2d3748", "#ffffff"))
    width, height = 1400, max(900, 120 + len(lines) * 42)
    img = Image.new("RGB", (width, height), bg_color)
    draw = ImageDraw.Draw(img)

    title_font = load_font(34, bold=True)
    body_font = load_font(28)
    small_font = load_font(20)

    draw.rectangle((0, 0, width, 88), fill=header_color)
    draw.text((36, 24), title, fill="white", font=title_font)

    y = 110
    for line in lines:
        draw.text((48, y), line, fill="#1a202c", font=body_font)
        y += 42

    wm = small_font
    bbox = draw.textbbox((0, 0), WATERMARK, font=wm)
    wm_w = bbox[2] - bbox[0]
    draw.text((width - wm_w - 24, height - 36), WATERMARK, fill="#a0aec0", font=wm)

    draw.rectangle((16, 16, width - 16, height - 16), outline="#cbd5e0", width=3)

    out_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_png, "PNG", optimize=True)
    img.convert("RGB").save(out_png.with_suffix(".pdf"), "PDF", resolution=150.0)


def birth_certificate(h: Household, p: Person) -> list[str]:
    return [
        "CERTIFICATE OF LIVE BIRTH",
        f"BUREAU OF VITAL STATISTICS — {h.state}",
        f"COUNTY: {h.county.upper()}",
        f"NAME: {p.full_name.upper()}",
        f"DATE OF BIRTH: {p.dob}",
        "SEX: M" if p.first in {"John", "Marcus", "David", "Carlos", "James", "Michael", "Thomas", "Kevin", "Raj", "Lucas", "Mateo", "Alexander"} else "SEX: F",
        f"PLACE OF BIRTH: {h.city.upper()}, {h.state}",
        f"REGISTRATION NO: BC-{h.id:02d}-{p.slug.upper()}",
    ]


def ssn_card(h: Household, p: Person) -> list[str]:
    return [
        "YOUR SOCIAL SECURITY CARD",
        "THIS NUMBER HAS BEEN ESTABLISHED FOR",
        p.display_name.upper(),
        p.ssn,
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
        "SIGNATURE: _________________________",
    ]


def texas_drivers_license(h: Household, p: Person) -> list[str]:
    state_name = {
        "TX": "TEXAS",
        "OR": "OREGON",
        "CO": "COLORADO",
        "WA": "WASHINGTON",
        "FL": "FLORIDA",
        "CA": "CALIFORNIA",
        "IL": "ILLINOIS",
        "AZ": "ARIZONA",
    }.get(p.dl_state, p.dl_state)
    return [
        state_name,
        "DRIVER LICENSE",
        f"4d. DL: {p.dl_number}",
        f"3. DOB: {p.dob}",
        f"1. {p.last.upper()}",
        f"2. {p.first.upper()}",
        "8. Address",
        h.address.upper(),
        f"{h.city.upper()}, {p.dl_state} {h.zip_code}",
        "4a. Iss: 01/10/2023",
        "4b. Exp: 01/10/2028",
        "CLASS C",
    ]


def passport_doc(h: Household, p: Person) -> list[str]:
    parts = p.dob.split("/")
    months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    dob_passport = f"{parts[1]} {months[int(parts[0]) - 1]} {parts[2]}"
    return [
        "UNITED STATES OF AMERICA",
        "PASSPORT",
        f"Surname {p.last.upper()}",
        f"Given Names {p.first.upper()} {p.middle.upper()}".strip(),
        "Nationality UNITED STATES OF AMERICA",
        f"Date of Birth {dob_passport}",
        f"Passport No. {p.passport_number}",
        f"Place of Birth {h.city.upper()}, {h.state}",
    ]


def state_id_card(h: Household, p: Person) -> list[str]:
    sid = p.state_id or f"S{h.id:02d}{p.slug[:3].upper()}001"
    return [
        h.state,
        "IDENTIFICATION CARD",
        "STATE ID",
        "NON-DRIVER IDENTIFICATION",
        f"NAME: {p.display_name.upper()}",
        f"ID: {sid}",
        f"DOB: {p.dob}",
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
    ]


def vehicle_registration(h: Household, p: Person) -> list[str]:
    vin = f"1HGBH41JXMN{h.id:02d}{int(p.ssn[-4:]):04d}"
    plate = f"{h.state}-{h.id:02d}{p.slug[0].upper()}{p.slug[-1].upper()}"
    return [
        f"STATE OF {h.state}",
        "DEPARTMENT OF MOTOR VEHICLES",
        "VEHICLE REGISTRATION CERTIFICATE",
        f"OWNER: {p.display_name.upper()}",
        f"VIN: {vin}",
        f"PLATE: {plate}",
        "MAKE/MODEL: 2022 HONDA ACCORD",
        "EXPIRATION: 12/31/2026",
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
    ]


def property_tax(h: Household, p: Person) -> list[str]:
    assessed = 350_000 + h.id * 25_000
    tax_due = assessed // 50
    return [
        f"{h.county.upper()} COUNTY TAX ASSESSOR",
        "PROPERTY TAX STATEMENT",
        "TAX YEAR 2024",
        f"PROPERTY OWNER: {p.display_name.upper()}",
        f"PROPERTY ADDRESS: {h.address.upper()}",
        f"{h.city.upper()} {h.state} {h.zip_code}",
        f"ACCOUNT NUMBER: PT-{h.id:02d}-{p.slug.upper()}",
        f"ASSESSED VALUE: ${assessed:,}",
        f"AMOUNT DUE: ${tax_due:,}.00",
        "DUE DATE: 01/31/2025",
    ]


def marriage_certificate(h: Household, a: Person, b: Person) -> list[str]:
    return [
        "CERTIFICATE OF MARRIAGE",
        f"COUNTY CLERK — {h.county.upper()} COUNTY",
        f"PARTY A: {a.display_name.upper()}",
        f"PARTY B: {b.display_name.upper()}",
        "DATE OF MARRIAGE: 06/01/2010",
        f"RECORD NO: MC-{h.id:02d}-001",
        f"PLACE: {h.city.upper()}, {h.state}",
    ]


def utility_bill(h: Household, p: Person) -> list[str]:
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
    return [
        provider,
        "Account Number: " + str(1_000_000_000 + h.id * 111_111),
        "Service Address:",
        p.display_name.upper(),
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
        "Billing Period: 12/01/2024 - 12/31/2024",
        "kWh Usage: 742",
        "Amount Due: $125.00",
    ]


def insurance_card(h: Household, p: Person) -> list[str]:
    return [
        "BLUE CROSS BLUE SHIELD",
        f"MEMBER ID: XYZ{h.id:02d}{p.passport_number[-6:]}",
        f"SUBSCRIBER: {p.display_name.upper()}",
        f"GROUP #: {10000 + h.id}",
        f"DOB: {p.dob}",
        "PLAN: PPO",
        "RXBIN: 610014",
    ]


def bank_statement(h: Household, p: Person) -> list[str]:
    return [
        "FIRST NATIONAL BANK",
        "ACCOUNT STATEMENT",
        "STATEMENT DATE: 01/31/2025",
        "ACCOUNT BALANCE: $1,234.56",
        "ROUTING NUMBER: 021000021",
        p.display_name.upper(),
        h.address.upper(),
        f"{h.city.upper()} {h.state} {h.zip_code}",
        f"Account ending in {1000 + h.id}",
    ]


def w2_form(h: Household, p: Person) -> list[str]:
    return [
        "Form W-2 Wage and Tax Statement",
        "2024",
        f"Employer's name: ACME CORPORATION #{h.id:02d}",
        f"Employee's name: {p.display_name}",
        f"Employee's SSA number: {p.ssn}",
        f"c Employer identification number {10 + h.id:02d}-{3456780 + h.id}",
        f"Employee address: {h.address}, {h.city} {h.state} {h.zip_code}",
    ]


def pay_stub(h: Household, p: Person) -> list[str]:
    return [
        f"ACME CORPORATION #{h.id:02d}",
        "PAY STUB",
        f"Employee: {p.display_name}",
        f"Employer: ACME CORPORATION #{h.id:02d}",
        "Pay Date: 01/15/2025",
        "EARNINGS: $4,250.00",
        f"{h.address}",
        f"{h.city} {h.state} {h.zip_code}",
    ]


DocumentBuilder = Callable[[Household, Person], list[str]]

# Primary adult gets more docs; children get birth cert + state ID
HOUSEHOLD_DOC_PLAN: dict[str, list[tuple[str, str, DocumentBuilder]]] = {
    "primary_adult": [
        ("drivers_license", "Driver License", texas_drivers_license),
        ("ssn_card", "Social Security Card", ssn_card),
        ("passport", "US Passport", passport_doc),
        ("vehicle_registration", "Vehicle Registration", vehicle_registration),
        ("property_tax", "Property Tax Statement", property_tax),
        ("utility_bill", "Utility Bill", utility_bill),
        ("insurance_card", "Health Insurance Card", insurance_card),
        ("bank_statement", "Bank Statement", bank_statement),
        ("w2_tax", "W-2 Tax Form", w2_form),
    ],
    "spouse": [
        ("birth_certificate", "Birth Certificate", birth_certificate),
        ("drivers_license", "Driver License", texas_drivers_license),
        ("insurance_card", "Health Insurance Card", insurance_card),
        ("pay_stub", "Pay Stub", pay_stub),
    ],
    "child": [
        ("birth_certificate", "Birth Certificate", birth_certificate),
        ("state_id", "State ID Card", state_id_card),
    ],
}


def household_folder(h: Household) -> Path:
    return OUT_DIR / f"household-{h.id:02d}-{h.slug}"


def write_index(manifest: list[dict]) -> None:
    rows = []
    for entry in manifest:
        folder = entry["folder"]
        for doc in entry["documents"]:
            base = doc["filename"]
            rows.append(
                f"<tr><td>{entry['label']}</td><td>{doc['person']}</td>"
                f"<td>{doc['title']}</td>"
                f"<td><a href=\"{folder}/{base}.png\">PNG</a></td>"
                f"<td><a href=\"{folder}/{base}.pdf\">PDF</a></td></tr>"
            )

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Household Test Documents</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; color: #1a202c; }}
    h1 {{ margin-bottom: 0.25rem; }}
    p.note {{ color: #4a5568; max-width: 52rem; }}
    table {{ border-collapse: collapse; width: 100%; margin-top: 1.5rem; }}
    th, td {{ border: 1px solid #e2e8f0; padding: 0.5rem 0.75rem; text-align: left; }}
    th {{ background: #edf2f7; }}
    tr:nth-child(even) {{ background: #f7fafc; }}
    a {{ color: #2b6cb0; }}
    .zip {{ margin-top: 1rem; }}
  </style>
</head>
<body>
  <h1>Household Test Documents</h1>
  <p class="note">10 fictional households with synthetic birth certificates, SSN cards, driver licenses,
  passports, vehicle registrations, property tax statements, marriage certificates, and more.
  All data is fake — safe for OCR and profile-routing tests.</p>
  <p class="zip"><strong>Download all:</strong> <a href="household-fixtures.zip">household-fixtures.zip</a></p>
  <table>
    <thead><tr><th>Household</th><th>Person</th><th>Document</th><th>PNG</th><th>PDF</th></tr></thead>
    <tbody>
      {''.join(rows)}
    </tbody>
  </table>
</body>
</html>
"""
    (OUT_DIR / "index.html").write_text(html, encoding="utf-8")


def main() -> None:
    import shutil
    import zipfile

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True)

    manifest: list[dict] = []
    total_files = 0

    for household in HOUSEHOLDS:
        folder = household_folder(household)
        folder.mkdir(parents=True, exist_ok=True)
        entry = {
            "id": household.id,
            "slug": household.slug,
            "label": household.label,
            "folder": folder.name,
            "city": household.city,
            "state": household.state,
            "members": [p.display_name for p in household.members],
            "documents": [],
        }

        primary = household.members[0]
        for doc_type, title, builder in HOUSEHOLD_DOC_PLAN["primary_adult"]:
            lines = builder(household, primary)
            filename = f"{primary.slug}-{doc_type.replace('_', '-')}"
            out_png = folder / f"{filename}.png"
            render_document(title, doc_type, lines, out_png)
            entry["documents"].append({"person": primary.display_name, "title": title, "filename": filename, "type": doc_type})
            total_files += 2

        if household.spouse_pair:
            a = person_by_slug(household, household.spouse_pair[0])
            b = person_by_slug(household, household.spouse_pair[1])
            lines = marriage_certificate(household, a, b)
            filename = f"{household.slug}-marriage-certificate"
            out_png = folder / f"{filename}.png"
            render_document("Marriage Certificate", "marriage_certificate", lines, out_png)
            entry["documents"].append({"person": f"{a.display_name} & {b.display_name}", "title": "Marriage Certificate", "filename": filename, "type": "marriage_certificate"})
            total_files += 2

            spouse = household.members[1]
            for doc_type, title, builder in HOUSEHOLD_DOC_PLAN["spouse"]:
                lines = builder(household, spouse)
                filename = f"{spouse.slug}-{doc_type.replace('_', '-')}"
                out_png = folder / f"{filename}.png"
                render_document(title, doc_type, lines, out_png)
                entry["documents"].append({"person": spouse.display_name, "title": title, "filename": filename, "type": doc_type})
                total_files += 2

        for member in household.members[2:]:
            for doc_type, title, builder in HOUSEHOLD_DOC_PLAN["child"]:
                lines = builder(household, member)
                filename = f"{member.slug}-{doc_type.replace('_', '-')}"
                out_png = folder / f"{filename}.png"
                render_document(title, doc_type, lines, out_png)
                entry["documents"].append({"person": member.display_name, "title": title, "filename": filename, "type": doc_type})
                total_files += 2

        manifest.append(entry)

    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    write_index(manifest)

    zip_path = OUT_DIR / "household-fixtures.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(OUT_DIR.rglob("*")):
            if path.is_file() and path != zip_path:
                zf.write(path, path.relative_to(OUT_DIR))

    print(f"Generated {len(HOUSEHOLDS)} households, {total_files} files (PNG+PDF pairs)")
    print(f"Output: {OUT_DIR}")
    print(f"Zip: {zip_path}")
    print(f"Browse: file://{OUT_DIR / 'index.html'}")
    print("Serve for Simulator: ./scripts/serve_sample_documents.sh 8010")
    print("  then open http://127.0.0.1:8010/household-fixtures/")


if __name__ == "__main__":
    main()
