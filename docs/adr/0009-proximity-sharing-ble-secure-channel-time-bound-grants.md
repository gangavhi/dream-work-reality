# ADR 0009: Proximity sharing: BLE discovery, strong session crypto, time-bound grants

## Status

Accepted

## Date

2026-04-19

## Context

Household members need to share **structured subsets** without sending payloads through our cloud. Proximity is a UX and security signal: transfers should require **physical nearness** and **explicit grants**, with **expiry** and **revocation**.

## Decision

1. **Discovery**: Bluetooth Low Energy advertisements with **rotating ephemeral identifiers** (subject to OS privacy APIs).
2. **Session key establishment**: modern PAKE or Noise-style handshake (implementation choice documented in security spec), not “just BLE pairing” as the sole security layer.
3. **Payload**: encrypted package (subset export or signed operation log) with **manifest** listing scopes, TTL, issuer device key, and nonce.
4. **Authorization model**: **time-bound grants** with optional **row/field/table** scopes; receiver imports under **`foreign_provenance`** without silently overwriting canonical rows unless user confirms merge rules.
5. **Optional bootstrap**: NFC or QR for out-of-band short code when BLE is flaky; optional **UWB** for “confirmed proximity” UX on supported hardware.

## Consequences

**Positive**

- Payload never transits product servers by design.
- Expiry and scope reduce blast radius of a lost device.

**Negative**

- OS background limits (especially iOS) complicate discovery and completion; UX must state honest limitations.
- Cryptographic and RF edge cases require dedicated QA devices and field testing.

**Follow-ups**

- Formal **threat model** (malicious neighbor, compromised grantee) and **key rotation** story for household membership changes.
