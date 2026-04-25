#!/usr/bin/env python3
"""Validate integration protocol fixtures against local JSON Schemas.

This script intentionally uses only Python's standard library and implements
only a small JSON Schema subset needed by our protocol files.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple


SCHEMA_MAP: Dict[str, str] = {
    "request": "protocol/request.schema.json",
    "response": "protocol/response.schema.json",
    "error": "protocol/error.schema.json",
}


def _json_type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _matches_type(expected: str, value: Any) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return (isinstance(value, int) and not isinstance(value, bool)) or isinstance(value, float)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return False


def validate_instance(schema: Mapping[str, Any], instance: Any, path: str = "$") -> List[str]:
    """Validate an instance against a limited JSON Schema subset."""
    errors: List[str] = []

    expected_type = schema.get("type")
    if isinstance(expected_type, str):
        if not _matches_type(expected_type, instance):
            return [f"{path}: expected type '{expected_type}', got '{_json_type_name(instance)}'"]

    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: expected const {schema['const']!r}, got {instance!r}")

    enum_values = schema.get("enum")
    if isinstance(enum_values, list) and instance not in enum_values:
        errors.append(f"{path}: expected one of {enum_values!r}, got {instance!r}")

    if isinstance(instance, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if key not in instance:
                    errors.append(f"{path}: missing required property '{key}'")

        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for key, subschema in properties.items():
                if key in instance and isinstance(subschema, dict):
                    errors.extend(validate_instance(subschema, instance[key], f"{path}.{key}"))

        if schema.get("additionalProperties") is False and isinstance(properties, dict):
            allowed = set(properties.keys())
            for key in instance.keys():
                if key not in allowed:
                    errors.append(f"{path}: unexpected property '{key}'")

    if isinstance(instance, str):
        pattern = schema.get("pattern")
        if isinstance(pattern, str):
            if re.fullmatch(pattern, instance) is None:
                errors.append(f"{path}: string does not match pattern {pattern!r}")

    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        matches = 0
        nested_failures: List[List[str]] = []
        for subschema in one_of:
            if not isinstance(subschema, dict):
                continue
            sub_errors = validate_instance(subschema, instance, path)
            if not sub_errors:
                matches += 1
            else:
                nested_failures.append(sub_errors)
        if matches != 1:
            errors.append(f"{path}: oneOf expected exactly one matching schema, got {matches}")
            if nested_failures:
                # Include one nested failure to keep output concise and useful.
                errors.append(f"{path}: sample nested failure: {nested_failures[0][0]}")

    return errors


def infer_fixture_kind(fixture_path: Path) -> str:
    name = fixture_path.name
    if name.endswith(".request.json"):
        return "request"
    if name.endswith(".response.json"):
        return "response"
    if name.endswith(".error.json"):
        return "error"
    raise ValueError(
        f"Cannot infer fixture kind from '{name}'. Expected suffix .request.json, .response.json, or .error.json."
    )


def validate_file(base_dir: Path, fixture_path: Path) -> List[str]:
    kind = infer_fixture_kind(fixture_path)
    schema_rel = SCHEMA_MAP[kind]
    schema_path = base_dir / schema_rel

    with schema_path.open("r", encoding="utf-8") as f:
        schema = json.load(f)

    with fixture_path.open("r", encoding="utf-8") as f:
        fixture = json.load(f)

    return validate_instance(schema, fixture, "$")


def validate_all(base_dir: Path, fixtures_dir: Path) -> List[Tuple[Path, List[str]]]:
    failures: List[Tuple[Path, List[str]]] = []
    fixtures = sorted(fixtures_dir.glob("*.json"))
    for fixture in fixtures:
        errors = validate_file(base_dir, fixture)
        if errors:
            failures.append((fixture, errors))
    return failures


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate integration protocol fixtures.")
    parser.add_argument(
        "--base-dir",
        default=str(Path(__file__).resolve().parent),
        help="Base integration directory containing protocol/ and fixtures/ (default: script directory).",
    )
    parser.add_argument(
        "--fixtures-dir",
        default=None,
        help="Optional path to fixtures directory (default: <base-dir>/fixtures).",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    base_dir = Path(args.base_dir).resolve()
    fixtures_dir = Path(args.fixtures_dir).resolve() if args.fixtures_dir else (base_dir / "fixtures")

    if not (base_dir / "protocol").exists():
        print(f"error: protocol directory not found under {base_dir}", file=sys.stderr)
        return 2
    if not fixtures_dir.exists():
        print(f"error: fixtures directory not found: {fixtures_dir}", file=sys.stderr)
        return 2

    failures = validate_all(base_dir, fixtures_dir)
    if failures:
        for fixture, errors in failures:
            print(f"FAIL {fixture}")
            for err in errors:
                print(f"  - {err}")
        print(f"{len(failures)} fixture file(s) failed validation.")
        return 1

    print(f"OK - validated {len(list(fixtures_dir.glob('*.json')))} fixture file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
