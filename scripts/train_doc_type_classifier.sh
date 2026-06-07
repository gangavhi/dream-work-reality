#!/usr/bin/env bash
# Export training CSVs and print Create ML steps for trustnest.doc-type.v1
# (all must-have scannable document types in the feature list).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_DIR="${ROOT}/local-training/export"
LABELS="${ROOT}/local-training/labels.jsonl"
MODEL_OUT="${ROOT}/local-training/DocumentTypeClassifier.mlpackage"

python3 "${ROOT}/scripts/export_training_rows.py" \
  --labels "${LABELS}" \
  --output "${EXPORT_DIR}"

CSV="${EXPORT_DIR}/doc-type-classifier.csv"
META="${EXPORT_DIR}/export-metadata.json"

echo ""
echo "=== trustnest.doc-type.v1 training pack ==="
echo "CSV:      ${CSV}"
echo "Metadata: ${META}"
echo ""

if command -v python3 >/dev/null; then
  python3 - <<'PY' "${META}" 2>/dev/null || true
import json, sys
meta = json.load(open(sys.argv[1]))
labels = meta.get("doc_type_classifier_labels", [])
print(f"Classes ({len(labels)}): {', '.join(labels)}")
for row in meta.get("must_have_feature_list", []):
    if row.get("manualOnly"):
        print(f"  [manual] {row['category']}")
    else:
        types = ", ".join(row.get("documentTypes", []))
        print(f"  [scan]   {row['category']} → {types}")
PY
fi

echo ""
echo "=== Create ML (Xcode on Mac) ==="
echo "1. Open Xcode → Create ML → New Document → Text Classifier"
echo "2. Training Data: ${CSV}"
echo "   - Text column: text"
echo "   - Label column: label"
echo "3. Train → Export .mlpackage to:"
echo "   ${MODEL_OUT}"
echo "4. Copy into app bundle:"
echo "   apps/ios/DreamWorkApp/Resources/Models/DocumentTypeClassifier.mlpackage"
echo "5. Rebuild app — RewritePipeline uses it when heuristic confidence < 0.85"
echo ""
echo "After each device test session, append OCR rows to:"
echo "  ${LABELS}"
echo "Then re-run: ./scripts/train_doc_type_classifier.sh"
