# Simulator test documents (local only)

Put **your own** PDF/PNG/JPG test files here for iOS Simulator OCR testing.

- Do **not** commit real IDs, passports, or SSN cards to git.
- Files in this folder are served only on your Mac at `http://127.0.0.1:8010/` while `./scripts/prepare_simulator_testing.sh` is running.

## Quick start

```bash
# From repo root
./scripts/prepare_simulator_testing.sh

# In Simulator → DreamWork → Home → Browse laptop documents
```

You can also use files in `~/Downloads` (port 8009) or drag a file from Finder onto the Simulator window.
