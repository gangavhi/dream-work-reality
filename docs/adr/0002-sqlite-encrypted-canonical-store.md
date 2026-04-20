# ADR 0002: SQLite as canonical on-device relational store

## Status

Accepted

## Date

2026-04-19

## Context

The system must persist structured household and personal data, support **evolving schema** (new tables and columns), maintain **history**, and ship on **mobile** and **desktop** with mature tooling. Alternatives include embedded NoSQL (Realm, embedded KV), document-only stores, or per-feature databases.

## Decision

Use **SQLite** as the **single canonical** embedded relational database on each device, with **encryption at rest**. Concrete stack (SQLCipher-class + OS keystore) is specified in **ADR 0014**.

- Use **migrations** for baseline schema; **dynamic DDL** for user-driven growth is allowed but must be logged and policy-governed (see ADR 0005).
- Prefer **typed columns** for well-known fields; use **JSON staging** only when promotion to typed columns is deferred.

## Consequences

**Positive**

- One query model across features: provenance, history, joins, exports.
- Mature backup, introspection, and corruption recovery patterns.

**Negative**

- Dynamic schema requires discipline: **catalog tables**, migration tooling, and UI that tolerates physical schema drift (views help).
- Encryption key handling and **SQLCipher-class** licensing/build complexity must be owned explicitly per platform (see ADR 0014).

**Follow-ups**

- Define a **`schema_change_log`** and rollback strategy for failed or disputed DDL.
