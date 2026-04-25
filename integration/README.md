# Integration Protocol Harness

This directory contains:

- JSON Schema envelopes for extension/native-host JSON-RPC messages in `protocol/`
- sample method fixtures in `fixtures/`
- a stdlib-only validator script in `validate_protocol.py`
- tests in `tests/`

## Covered methods

- `vault.fill.getCandidates`
- `vault.session.open`

Fixtures are named with suffixes to select schema:

- `*.request.json` -> `protocol/request.schema.json`
- `*.response.json` -> `protocol/response.schema.json`
- `*.error.json` -> `protocol/error.schema.json`

## Run fixture validation

From repository root:

```bash
python3 integration/validate_protocol.py
```

Optional override:

```bash
python3 integration/validate_protocol.py --base-dir integration --fixtures-dir integration/fixtures
```

## Run tests

From repository root:

```bash
python3 -m unittest discover -s integration/tests -p "test_*.py"
```

## Validator limitations

To avoid third-party dependencies, the validator implements a narrow JSON Schema subset:

- `type`
- `const`
- `enum`
- `required`
- `properties`
- `additionalProperties` (boolean form)
- `pattern`
- `oneOf`

It does not implement advanced features such as `$ref`, `allOf`, conditional keywords, numeric ranges, or array item schemas. This is sufficient for the envelope schemas in this directory.
