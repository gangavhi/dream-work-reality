# ADR 0005: Schema inference via constrained LLM output and transactional DDL

## Status

Accepted

## Date

2026-04-19

## Context

Extracted text must map into a **relational** model that may require **new tables or columns**. Letting a model emit arbitrary SQL is unsafe and hard to validate. Fully manual mapping does not scale for batch import and varied documents.

## Decision

1. The LLM emits a **strictly structured plan** (JSON) validated against a **JSON Schema**; prefer **grammar-constrained decoding** when the runtime supports it.
2. Allowed operations are a **small internal DSL** (for example: `create_table`, `add_column`, `insert_row`, `upsert_by_natural_key`) implemented by **trusted code**, not raw SQL from the model.
3. Apply DDL and row writes in a **single SQLite transaction** with **dry-run validation** (types, nullability, policy limits) before commit.
4. Log every applied change to **`schema_change_log`** with enough metadata to **reverse** when SQLite semantics allow.

Policies (rate limits, forbidden names, max columns, sensitive-field gates) are enforced in code **after** schema validation and **before** execution.

## Consequences

**Positive**

- Safer evolution of local schema with reviewable, machine-readable plans.
- Failed ingestions roll back cleanly without partial orphan tables.

**Negative**

- The DSL must be extended when new capabilities are needed; product asks may bottleneck on engine work.
- Undo/replay complexity grows; needs tooling and tests.

**Follow-ups**

- ADR or spec for **sensitive-field** confirmation paths that can block auto-DDL even when the model is confident.
- **On-device LLM runtime** selection and EP/backends: **ADR 0017** (grammar-constrained decoding depends on engine capabilities there).
