#!/usr/bin/env python3
"""Export Create ML training CSVs from manifest.json + local labels.jsonl.

Reads the golden corpus manifest and optional local session labels, then writes
three standalone-model datasets:

  doc-type-classifier.csv      — text classifier (OCR snippet → document_type)
  passport-page-ranker.csv     — tabular classifier (page features → is_biodata_page)
  field-label-mapper.csv       — text classifier (doc+label+value → profile_key)

Usage:
  python3 scripts/export_training_rows.py
  python3 scripts/export_training_rows.py --labels ~/trustnest/labels.jsonl --output ./local-training/export

labels.jsonl (one JSON object per line, append after each test session):
  {"record_type":"doc_type","text":"SOCIAL SECURITY\\n...","label":"ssnCard","fixture_id":"local_001"}
  {"record_type":"passport_page","fixture_id":"local_passport_01","biodata_page_index":0,
   "pages":[{"line_count":42,"mrz_line_count":2,"noise_ratio":0.1,"has_surname_label":true,"has_pin":false}]}
  {"record_type":"field_label","document_type":"passport","label":"Given Name(s)","value":"Jane","profile_key":"legal_first_name"}

Never commit labels.jsonl — it may contain real OCR from device scans.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO_ROOT / "apps/ios/DreamWorkAppTests/Fixtures/manifest.json"
DEFAULT_LABELS = REPO_ROOT / "local-training/labels.jsonl"
DEFAULT_OUTPUT = REPO_ROOT / "local-training/export"

NONE_LABEL = "_none_"
MAX_OCR_SNIPPET = 2048

# Synthetic OCR snippets keyed by manifest fixture id (aligned with XCTest fixtures; no real PII).
FIXTURE_OCR: dict[str, str] = {
    "texas_dl_clean": """
TEXAS
DRIVER LICENSE
4d. DL: D12345678
3. DOB: 04/25/1990
1. SMITH
2. JANE
8. Address
2457 MEADOWBROOK AVE
AUSTIN, TX 78701
4a. Iss: 01/10/2023
4b. Exp: 01/10/2028
""".strip(),
    "us_passport_clean_mrz": """
UNITED STATES OF AMERICA
PASSPORT
Surname / Nom / Apellidos
SMITH
Given names / Prénoms / Nombres
JANE MICHAEL
Passport No. / No. du Passeport / No. de Pasaporte
P12345678
Date of birth / Date de naissance / Fecha de nacimiento
15 MAR 1985
Date of expiration / Date d'expiration / Fecha de caducidad
01 JAN 2030
P<USASMITH<<JANE<MICHAEL<<<<<<<<<<<<<<<<<<<<
P123456789USA8503150F3001015<<<<<<<<<<<<<<<0
""".strip(),
    "us_passport_biodata_label_noise": """
UNITED STATES OF AMERICA
PASSPORT
Given Names
Given Names
Place of Birth
Piace Of Birth
Passport No.
A18191851
Nationality
United States of America
Date of issue
03/24/2023
Date of expiration
07/20/2028
""".strip(),
    "indian_passport_noisy_multipage": """
REPUBLIC OF INDIA
Passport~do
PATEL
AMIT
INDIAN
02ID6/1990
PUNE, MAHARASHTRA
MUMBAI
27/12/2014
26./.12/24.24
M49kQ123<6INDp~QQfaQ
---PAGE---
M G ROAD, SHIVAJI NAGAR
WHITEFIELD, BANGALORE
PIN:411028, MAHARASHTRA, INDIA
PATEL
AMITKUMAR
N4940123 M 02JUN1990 IND
""".strip(),
    "ssn_card_instruction_boilerplate": """
YOUR SOCIAL SECURITY CARD
ADULTS: Sign this card in ink immediately.
Children: Do Not Sign Until Age 18 Or Your First Job,
Do not laminate.
456-78-9012
JANE DOE
123 MAIN ST
SPRINGFIELD IL 62704-1234
""".strip(),
    "state_id_clean": """
STATE ID
IDENTIFICATION CARD
NON-DRIVER
1. RIVERA
2. ALEX
ID: S98765432
DOB: 06/12/1992
EXP: 06/12/2028
""".strip(),
    "utility_bill_clean": """
AUSTIN ELECTRIC UTILITY
BILLING STATEMENT
SERVICE ADDRESS
742 OAK STREET
AUSTIN TX 78701
""".strip(),
    "insurance_card_clean": """
BLUE CROSS SHIELD INSURANCE
MEMBER ID: ABC123456789
GROUP #: GRP001
SUBSCRIBER: ALEX RIVERA
""".strip(),
    "w2_clean": """
IRS W-2 WAGE AND TAX STATEMENT
TAX YEAR 2024
EMPLOYER'S NAME: ACME CORP
""".strip(),
    "form1099_clean": """
IRS FORM 1099-MISC
TAX YEAR 2024
PAYER: FREELANCE CLIENT LLC
""".strip(),
    "pay_stub_clean": """
PAY STUB
EMPLOYER: ACME CORP
EARNINGS STATEMENT
PAY PERIOD END 03/15/2024
""".strip(),
    "bank_statement_clean": """
FIRST NATIONAL BANK
BANK STATEMENT
ACCOUNT STATEMENT
ROUTING 111000025
ACCOUNT ****1234
""".strip(),
    "indian_passport_noisy_back": """
REPUBLIC OF INDIA
Surname
DESAI
Given Name(s)
PRIYA
Date of Birth 19/07/1981
P1234567
P<INDDESAI<<PRIYA<<<<<<<<<<<<<<<<<<<<<<<<<<<
P1234567<6IND8107199F2807205<<<<<<<<<<<<<<04
---PAGE---
R X0101 ~ A ~~~~~ ~fi~~,r3} Andhra, Pradesh, Chennai Name Of Spouse Kavali 2016327705007
PIN:560001, ANDHRA PRADESH, INDIA
""".strip(),
}

# Rename legacy manifest id alias
FIXTURE_OCR["indian_passport_megia_noisy_back"] = FIXTURE_OCR["indian_passport_noisy_back"]

# Canonical OCR labels used to synthesize positive field-label rows from manifest expectedFields.
PROFILE_KEY_LABELS: dict[str, list[str]] = {
    "legal_first_name": ["Given Name(s)", "Given Names", "First Name", "2."],
    "legal_middle_name": ["Middle Name", "Given names"],
    "legal_last_name": ["Surname", "Last Name", "1."],
    "display_name": ["Name", "Subscriber", "Cardholder"],
    "date_of_birth": ["Date of Birth", "DOB", "3. DOB"],
    "ssn": ["Social Security Number", "SSN"],
    "passport_number": ["Passport No.", "Passport No"],
    "passport_expiry": ["Date of Expiry", "Date of expiration", "4b. Exp"],
    "passport_issue_date": ["Date of Issue", "4a. Iss"],
    "passport_country": ["Nationality", "Country"],
    "passport_address": ["Address", "Permanent Address"],
    "drivers_license_number": ["DL", "4d. DL", "License No"],
    "drivers_license_state": ["State", "Issuing State"],
    "drivers_license_issue_date": ["4a. Iss", "Issue Date"],
    "drivers_license_expiry": ["4b. Exp", "Expiry Date"],
    "address_line1": ["Address", "8. Address", "Street"],
    "city": ["City"],
    "state": ["State"],
    "postal_code": ["ZIP", "Postal Code", "PIN"],
    "country": ["Country", "Nationality"],
    "insurance_member_id": ["Member ID", "ID Number", "Subscriber ID"],
    "insurance_carrier": ["Carrier", "Plan", "Insurance"],
    "insurance_group_number": ["Group #", "Group Number"],
}

PASSPORT_PAGE_FIXTURES = frozenset(
    {
        "indian_passport_noisy_multipage",
        "indian_passport_noisy_back",
        "indian_passport_megia_noisy_back",
    }
)

DOC_TYPE_CSV = "doc-type-classifier.csv"
PASSPORT_PAGE_CSV = "passport-page-ranker.csv"
FIELD_LABEL_CSV = "field-label-mapper.csv"


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON — {exc}") from exc
    return rows


def clip_text(text: str, limit: int = MAX_OCR_SNIPPET) -> str:
    text = re.sub(r"\s+", " ", text.strip())
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def split_pages(ocr_text: str) -> list[str]:
    if "---PAGE---" in ocr_text:
        return [chunk.strip() for chunk in ocr_text.split("---PAGE---") if chunk.strip()]
    chunks = [chunk.strip() for chunk in re.split(r"\n{3,}", ocr_text.strip()) if chunk.strip()]
    return chunks if chunks else [ocr_text.strip()]


def page_features(page_text: str) -> dict[str, Any]:
    lines = [line.strip() for line in page_text.splitlines() if line.strip()]
    line_count = len(lines)
    mrz_line_count = sum(
        1
        for line in lines
        if line.startswith("P<") or (line.count("<") >= 3 and len(line) >= 30)
    )
    noise_hits = sum(1 for line in lines if re.search(r"[~_{}\[\]]", line))
    noise_ratio = round(noise_hits / max(line_count, 1), 4)
    joined = "\n".join(lines).lower()
    has_surname_label = "surname" in joined
    has_pin = bool(re.search(r"pin:\s*\d", joined, re.IGNORECASE))
    return {
        "line_count": line_count,
        "mrz_line_count": mrz_line_count,
        "noise_ratio": noise_ratio,
        "has_surname_label": has_surname_label,
        "has_pin": has_pin,
    }


def field_label_text(document_type: str, label: str, value: str) -> str:
    return f"{document_type}\t{label}\t{value}"


def manifest_doc_type_rows(fixtures: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for fixture in fixtures:
        fixture_id = fixture["id"]
        ocr = fixture.get("ocrSnippet") or FIXTURE_OCR.get(fixture_id)
        if not ocr:
            continue
        rows.append(
            {
                "text": clip_text(ocr),
                "label": fixture["documentType"],
                "source": f"manifest:{fixture_id}",
            }
        )
    return rows


def manifest_field_label_rows(fixtures: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for fixture in fixtures:
        fixture_id = fixture["id"]
        document_type = fixture["documentType"]
        expected: dict[str, str] = fixture.get("expectedFields") or {}
        for profile_key, value in expected.items():
            labels = PROFILE_KEY_LABELS.get(profile_key, [profile_key.replace("_", " ").title()])
            for label in labels[:2]:
                rows.append(
                    {
                        "text": field_label_text(document_type, label, value),
                        "label": profile_key,
                        "source": f"manifest:{fixture_id}:expected",
                    }
                )
        rejected: dict[str, list[str]] = fixture.get("rejectedFields") or {}
        for wrong_profile_key, bad_values in rejected.items():
            labels = PROFILE_KEY_LABELS.get(
                wrong_profile_key, [wrong_profile_key.replace("_", " ").title()]
            )
            for bad_value in bad_values:
                for label in labels[:1]:
                    rows.append(
                        {
                            "text": field_label_text(document_type, label, bad_value),
                            "label": NONE_LABEL,
                            "source": f"manifest:{fixture_id}:rejected",
                        }
                    )
    return rows


def manifest_passport_page_rows(fixtures: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for fixture in fixtures:
        fixture_id = fixture["id"]
        if fixture_id not in PASSPORT_PAGE_FIXTURES:
            continue
        ocr = fixture.get("ocrSnippet") or FIXTURE_OCR.get(fixture_id)
        if not ocr:
            continue
        pages = split_pages(ocr)
        biodata_index = int(fixture.get("biodataPageIndex", 0))
        for page_index, page_text in enumerate(pages):
            features = page_features(page_text)
            rows.append(
                {
                    "fixture_id": fixture_id,
                    "page_index": page_index,
                    "line_count": features["line_count"],
                    "mrz_line_count": features["mrz_line_count"],
                    "noise_ratio": features["noise_ratio"],
                    "has_surname_label": int(features["has_surname_label"]),
                    "has_pin": int(features["has_pin"]),
                    "is_biodata_page": int(page_index == biodata_index),
                    "source": f"manifest:{fixture_id}",
                }
            )
    return rows


def labels_doc_type_rows(records: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for record in records:
        if record.get("record_type") != "doc_type":
            continue
        text = record.get("text") or record.get("ocr_text") or record.get("ocrSnippet")
        label = record.get("label") or record.get("document_type")
        if not text or not label:
            continue
        source = record.get("fixture_id") or record.get("source") or "labels.jsonl"
        rows.append({"text": clip_text(str(text)), "label": str(label), "source": f"labels:{source}"})
    return rows


def labels_field_label_rows(records: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for record in records:
        if record.get("record_type") != "field_label":
            continue
        document_type = record.get("document_type")
        label = record.get("label")
        value = record.get("value")
        profile_key = record.get("profile_key")
        if not document_type or label is None or value is None:
            continue
        mapped = NONE_LABEL if profile_key in (None, "", NONE_LABEL) else str(profile_key)
        source = record.get("fixture_id") or record.get("source") or "labels.jsonl"
        rows.append(
            {
                "text": field_label_text(str(document_type), str(label), str(value)),
                "label": mapped,
                "source": f"labels:{source}",
            }
        )
    return rows


def labels_passport_page_rows(records: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for record in records:
        if record.get("record_type") != "passport_page":
            continue
        pages = record.get("pages")
        biodata_index = record.get("biodata_page_index")
        if not isinstance(pages, list) or biodata_index is None:
            continue
        fixture_id = str(record.get("fixture_id") or record.get("source") or "labels.jsonl")
        for page_index, page in enumerate(pages):
            if not isinstance(page, dict):
                continue
            rows.append(
                {
                    "fixture_id": fixture_id,
                    "page_index": page_index,
                    "line_count": int(page.get("line_count", 0)),
                    "mrz_line_count": int(page.get("mrz_line_count", 0)),
                    "noise_ratio": float(page.get("noise_ratio", 0.0)),
                    "has_surname_label": int(bool(page.get("has_surname_label"))),
                    "has_pin": int(bool(page.get("has_pin"))),
                    "is_biodata_page": int(page_index == int(biodata_index)),
                    "source": f"labels:{fixture_id}",
                }
            )
    return rows


def dedupe_rows(rows: list[dict[str, Any]], key_fields: list[str]) -> list[dict[str, Any]]:
    seen: set[tuple[Any, ...]] = set()
    unique: list[dict[str, Any]] = []
    for row in rows:
        key = tuple(row.get(field) for field in key_fields)
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)
    return unique


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def export_training_rows(
    manifest_path: Path,
    labels_path: Path,
    output_dir: Path,
) -> dict[str, int]:
    manifest = load_json(manifest_path)
    fixtures = manifest.get("fixtures") or []
    label_records = load_jsonl(labels_path)

    doc_type_rows = dedupe_rows(
        manifest_doc_type_rows(fixtures) + labels_doc_type_rows(label_records),
        ["text", "label"],
    )
    field_label_rows = dedupe_rows(
        manifest_field_label_rows(fixtures) + labels_field_label_rows(label_records),
        ["text", "label"],
    )
    passport_page_rows = dedupe_rows(
        manifest_passport_page_rows(fixtures) + labels_passport_page_rows(label_records),
        ["fixture_id", "page_index"],
    )

    write_csv(
        output_dir / DOC_TYPE_CSV,
        ["text", "label", "source"],
        doc_type_rows,
    )
    write_csv(
        output_dir / FIELD_LABEL_CSV,
        ["text", "label", "source"],
        field_label_rows,
    )
    write_csv(
        output_dir / PASSPORT_PAGE_CSV,
        [
            "fixture_id",
            "page_index",
            "line_count",
            "mrz_line_count",
            "noise_ratio",
            "has_surname_label",
            "has_pin",
            "is_biodata_page",
            "source",
        ],
        passport_page_rows,
    )

    summary = {
        DOC_TYPE_CSV: len(doc_type_rows),
        FIELD_LABEL_CSV: len(field_label_rows),
        PASSPORT_PAGE_CSV: len(passport_page_rows),
    }

    feature_list = manifest.get("mustHaveFeatureList") or []
    doc_type_labels = sorted({row["label"] for row in doc_type_rows})

    metadata = {
        "manifest": str(manifest_path),
        "labels": str(labels_path),
        "labels_present": labels_path.exists(),
        "output_dir": str(output_dir),
        "must_have_feature_list": feature_list,
        "doc_type_classifier_labels": doc_type_labels,
        "models": manifest.get("standaloneModels", []),
        "row_counts": summary,
    }
    with (output_dir / "export-metadata.json").open("w", encoding="utf-8") as handle:
        json.dump(metadata, handle, indent=2)
        handle.write("\n")

    return summary


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help=f"Path to manifest.json (default: {DEFAULT_MANIFEST})",
    )
    parser.add_argument(
        "--labels",
        type=Path,
        default=DEFAULT_LABELS,
        help=f"Path to local labels.jsonl (default: {DEFAULT_LABELS})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output directory for CSVs (default: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.manifest.exists():
        print(f"error: manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    counts = export_training_rows(args.manifest, args.labels, args.output)

    print(f"manifest: {args.manifest}")
    print(f"labels:   {args.labels} {'(found)' if args.labels.exists() else '(missing — manifest-only export)'}")
    print(f"output:   {args.output}")
    for filename, count in counts.items():
        print(f"  {filename}: {count} rows")
    print()
    print("Create ML next steps:")
    print("  1. Text Classifier  → doc-type-classifier.csv   (text → label)")
    print("     Train first — covers all must-have scannable document types.")
    print("  2. Tabular Classifier → passport-page-ranker.csv (features → is_biodata_page)")
    print("  3. Text Classifier  → field-label-mapper.csv    (text → profile_key)")
    print()
    print("Doc-type training: ./scripts/train_doc_type_classifier.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
