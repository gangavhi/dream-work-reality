#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterable

from playwright.sync_api import Page, sync_playwright


def _load_profile(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(
            f"Profile not found: {path}\n"
            f"Create one by copying demo/profile.example.json -> demo/profile.json"
        )
    except Exception as e:  # noqa: BLE001
        raise SystemExit(f"Invalid JSON in profile {path}: {e!r}")
    if not isinstance(raw, dict):
        raise SystemExit("Profile JSON must be an object/dict.")
    return raw


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def _iter_profile_aliases(profile: dict[str, Any]) -> Iterable[tuple[str, Any]]:
    # canonical keys
    for k, v in profile.items():
        yield k, v

    # common aliases to help generic web forms
    if "first_name" in profile and "fname" not in profile:
        yield "fname", profile.get("first_name")
    if "last_name" in profile and "lname" not in profile:
        yield "lname", profile.get("last_name")
    if "zip" in profile and "postal_code" not in profile:
        yield "postal_code", profile.get("zip")
    if "address1" in profile and "address_line_1" not in profile:
        yield "address_line_1", profile.get("address1")
    if "address2" in profile and "address_line_2" not in profile:
        yield "address_line_2", profile.get("address2")


def _hints() -> dict[str, list[str]]:
    # Heuristic mapping: profile key -> strings to search in label/placeholder/name/id
    return {
        "first_name": ["first name", "given name", "fname"],
        "last_name": ["last name", "surname", "family name", "lname"],
        "email": ["email", "e-mail"],
        "phone": ["phone", "mobile", "cell", "tel"],
        "address1": ["address", "street", "street address", "address line 1"],
        "address2": ["address line 2", "apt", "apartment", "suite", "unit"],
        "city": ["city", "town"],
        "state": ["state", "province", "region"],
        "zip": ["zip", "zipcode", "postal"],
        "country": ["country"],
        "linkedin": ["linkedin"],
        "website": ["website", "portfolio", "url"],
    }


def _best_label_text(page: Page, selector: str) -> str:
    return _norm(
        page.eval_on_selector(
            selector,
            """(el) => {
              const pick = (s) => (s == null ? "" : String(s));
              const id = pick(el.id);
              const name = pick(el.getAttribute("name"));
              const ph = pick(el.getAttribute("placeholder"));
              const aria = pick(el.getAttribute("aria-label"));
              let label = "";
              if (id) {
                const lbl = document.querySelector(`label[for="${CSS.escape(id)}"]`);
                if (lbl) label = pick(lbl.textContent);
              }
              return [label, aria, ph, name, id].filter(Boolean).join(" ");
            }""",
        )
    )


def _set_value(page: Page, selector: str, value: Any) -> bool:
    if value is None:
        return False
    v = str(value)
    if not v.strip():
        return False

    tag = page.eval_on_selector(selector, "(el) => (el.tagName || '').toLowerCase()")
    if tag == "select":
        # try exact option value then option text
        ok = page.eval_on_selector(
            selector,
            """(el, val) => {
              const norm = (s) => String(s || "").trim().toLowerCase();
              const opts = Array.from(el.options || []);
              const match = opts.find(o => o.value === val || norm(o.textContent) === norm(val));
              if (!match) return false;
              el.value = match.value;
              el.dispatchEvent(new Event("input", { bubbles: true }));
              el.dispatchEvent(new Event("change", { bubbles: true }));
              return true;
            }""",
            v,
        )
        return bool(ok)

    # don't clobber file inputs
    t = page.eval_on_selector(selector, "(el) => (el.getAttribute('type') || '').toLowerCase()")
    if t == "file":
        return False

    page.fill(selector, v)
    return True


def fill_form(page: Page, profile: dict[str, Any]) -> dict[str, int]:
    inputs = page.query_selector_all("input, textarea, select")
    selectors: list[str] = []
    for i, _ in enumerate(inputs):
        selectors.append(f"(input, textarea, select):nth-match({i + 1})")

    filled = 0
    filled_by_exact = 0
    filled_by_hint = 0

    # 1) Exact id/name match.
    for key, value in _iter_profile_aliases(profile):
        if value is None or str(value).strip() == "":
            continue
        key_css = re.sub(r'"', '\\"', str(key))
        exact = page.query_selector(f'#{key_css}, [name="{key_css}"]')
        if exact is None:
            continue
        sel = f'#{key_css}' if page.query_selector(f'#{key_css}') else f'[name="{key_css}"]'
        if _set_value(page, sel, value):
            filled += 1
            filled_by_exact += 1

    # 2) Heuristic label matching for remaining.
    hints = _hints()
    for sel in selectors:
        # if already has a value, leave it
        has_value = page.eval_on_selector(
            sel,
            """(el) => {
              const tag = (el.tagName || '').toLowerCase();
              if (tag === 'select') return String(el.value || '').trim().length > 0;
              return String(el.value || '').trim().length > 0;
            }""",
        )
        if has_value:
            continue

        label = _best_label_text(page, sel)
        if not label:
            continue

        for key, value in profile.items():
            if value is None or str(value).strip() == "":
                continue
            key_hints = hints.get(key)
            if not key_hints:
                continue
            if any(h in label for h in key_hints):
                if _set_value(page, sel, value):
                    filled += 1
                    filled_by_hint += 1
                break

    return {"filled": filled, "exact": filled_by_exact, "hint": filled_by_hint}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Open a URL and autofill a form from a local profile JSON.")
    p.add_argument("url", help="Target URL (the form page).")
    p.add_argument(
        "--profile",
        default=str(Path(__file__).resolve().parents[1] / "demo" / "profile.json"),
        help="Path to profile JSON (default: demo/profile.json).",
    )
    p.add_argument("--submit", action="store_true", help="Attempt to click a submit button after fill.")
    p.add_argument("--headed", action="store_true", help="Run with a visible browser window.")
    p.add_argument("--timeout", type=int, default=45000, help="Navigation timeout in ms (default: 45000).")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    profile_path = Path(args.profile).expanduser().resolve()
    profile = _load_profile(profile_path)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headed)
        ctx = browser.new_context()
        page = ctx.new_page()
        page.set_default_timeout(args.timeout)
        page.goto(args.url, wait_until="domcontentloaded")

        stats = fill_form(page, profile)
        print(f"Filled {stats['filled']} fields (exact={stats['exact']}, hint={stats['hint']}).")

        if args.submit:
            # best-effort: click first obvious submit control
            btn = page.query_selector('button[type="submit"], input[type="submit"], button:has-text("Submit"), button:has-text("Next")')
            if btn is None:
                print("No submit button found; leaving page open for manual submit.")
            else:
                btn.click()
                print("Clicked submit (best-effort).")

        if args.headed:
            print("Browser left open (close window to exit).")
            page.wait_for_timeout(10_000_000)

        ctx.close()
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

