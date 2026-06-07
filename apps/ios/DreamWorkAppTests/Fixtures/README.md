# Test fixtures

## Committed (synthetic only)

| File | Purpose |
|------|---------|
| `sample-document.png` | Synthetic US passport (Jane Smith) for CI/E2E |
| `manifest.json` | Golden corpus metadata for parser + ML training export |

## Local only (gitignored — never commit)

Place real scans here **only on your machine** for manual QA. Tests skip when missing.

| File | Test |
|------|------|
| `texas-driver-license-reference.png` | `SimulatorDocumentPipelineE2ETests` |
| `ssn-card-reference.png` | `SSNCardPipelineE2ETests` |
| `indian-passport-reference.pdf` | `PassportSamplePipelineE2ETests` |
| `insurance-cards-reference.pdf` | `InsuranceCardPipelineE2ETests` |

Delete local reference files when done testing.
