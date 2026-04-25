import json
import tempfile
import unittest
from pathlib import Path

from integration.validate_protocol import (
    infer_fixture_kind,
    validate_all,
    validate_instance,
)


ROOT = Path(__file__).resolve().parents[2]
INTEGRATION_DIR = ROOT / "integration"


class ValidateInstanceTests(unittest.TestCase):
    def test_request_requires_api_version(self) -> None:
        schema = {
            "type": "object",
            "required": ["params"],
            "properties": {
                "params": {
                    "type": "object",
                    "required": ["apiVersion"],
                }
            },
        }
        payload = {"params": {}}
        errors = validate_instance(schema, payload)
        self.assertTrue(any("apiVersion" in err for err in errors))

    def test_rejects_additional_properties(self) -> None:
        schema = {
            "type": "object",
            "additionalProperties": False,
            "properties": {"jsonrpc": {"type": "string"}},
        }
        payload = {"jsonrpc": "2.0", "extra": True}
        errors = validate_instance(schema, payload)
        self.assertTrue(any("unexpected property 'extra'" in err for err in errors))


class FixtureValidationTests(unittest.TestCase):
    def test_known_fixtures_validate(self) -> None:
        failures = validate_all(INTEGRATION_DIR, INTEGRATION_DIR / "fixtures")
        self.assertEqual([], failures)

    def test_invalid_fixture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fixtures_dir = tmp_path / "fixtures"
            protocol_dir = tmp_path / "protocol"
            fixtures_dir.mkdir(parents=True)
            protocol_dir.mkdir(parents=True)

            for schema_name in ("request.schema.json", "response.schema.json", "error.schema.json"):
                src = INTEGRATION_DIR / "protocol" / schema_name
                dst = protocol_dir / schema_name
                dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

            bad_request = {
                "jsonrpc": "2.0",
                "id": "bad-1",
                "method": "vault.session.open",
                "params": {
                    "apiVersion": 2
                },
            }
            (fixtures_dir / "bad.request.json").write_text(
                json.dumps(bad_request, indent=2),
                encoding="utf-8",
            )

            failures = validate_all(tmp_path, fixtures_dir)
            self.assertEqual(1, len(failures))
            self.assertIn("apiVersion", " ".join(failures[0][1]))


class InferFixtureKindTests(unittest.TestCase):
    def test_infer_kind(self) -> None:
        self.assertEqual("request", infer_fixture_kind(Path("x.request.json")))
        self.assertEqual("response", infer_fixture_kind(Path("x.response.json")))
        self.assertEqual("error", infer_fixture_kind(Path("x.error.json")))

    def test_invalid_suffix_raises(self) -> None:
        with self.assertRaises(ValueError):
            infer_fixture_kind(Path("x.json"))


if __name__ == "__main__":
    unittest.main()
