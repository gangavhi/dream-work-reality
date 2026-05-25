#!/usr/bin/env bash
# Converts the selected Hugging Face LayoutLMv3 FUNSD model into an iOS-loadable
# CoreML artifact and installs it where the app can discover it.

set -euo pipefail

MODEL_ID="${MODEL_ID:-HYPJUDY/layoutlmv3-base-finetuned-funsd}"
APP_SUPPORT="${HOME}/Library/Application Support/DreamWork"
VENV_DIR="${APP_SUPPORT}/layoutlmv3-coreml-venv"
WORK_DIR="${APP_SUPPORT}/layoutlmv3-coreml-work"
MODELS_DIR="${APP_SUPPORT}/models"
OUT_NAME="layoutlmv3"
PYTHON_BIN="${PYTHON_BIN:-python3}"

mkdir -p "${APP_SUPPORT}" "${WORK_DIR}" "${MODELS_DIR}"

PY_VERSION="$("${PYTHON_BIN}" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
case "${PY_VERSION}" in
  3.10|3.11|3.12)
    ;;
  *)
    echo "error: LayoutLMv3 CoreML conversion requires Python 3.10, 3.11, or 3.12." >&2
    echo "Current ${PYTHON_BIN} is Python ${PY_VERSION}." >&2
    echo "Install a supported Python and rerun, for example:" >&2
    echo "  PYTHON_BIN=/opt/homebrew/bin/python3.11 scripts/convert-layoutlmv3-to-coreml.sh" >&2
    exit 1
    ;;
esac

if [[ ! -d "${VENV_DIR}" ]]; then
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

# shellcheck source=/dev/null
. "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip
python -m pip install --upgrade "torch==2.7.0" "transformers==4.52.3" "coremltools==8.3.0" "numpy<2"

PYTHON_OUT="${WORK_DIR}/${OUT_NAME}.mlpackage"
COMPILED_OUT="${MODELS_DIR}/${OUT_NAME}.mlmodelc"

rm -rf "${PYTHON_OUT}" "${COMPILED_OUT}" "${WORK_DIR}/${OUT_NAME}.mlmodelc"

MODEL_ID="${MODEL_ID}" PYTHON_OUT="${PYTHON_OUT}" python - <<'PY'
import os
import numpy as np
import torch
import coremltools as ct
from transformers import LayoutLMv3ForTokenClassification

model_id = os.environ["MODEL_ID"]
out = os.environ["PYTHON_OUT"]

model = LayoutLMv3ForTokenClassification.from_pretrained(model_id)
model.eval()

class LayoutLMv3TokenClassifier(torch.nn.Module):
    def __init__(self, wrapped):
        super().__init__()
        self.wrapped = wrapped

    def forward(self, input_ids, attention_mask, bbox, pixel_values):
        output = self.wrapped(
            input_ids=input_ids.long(),
            attention_mask=attention_mask.long(),
            bbox=bbox.long(),
            pixel_values=pixel_values.float(),
        )
        return output.logits

wrapper = LayoutLMv3TokenClassifier(model).eval()
example_input_ids = torch.ones((1, 512), dtype=torch.long)
example_attention = torch.ones((1, 512), dtype=torch.long)
example_bbox = torch.zeros((1, 512, 4), dtype=torch.long)
example_pixels = torch.zeros((1, 3, 224, 224), dtype=torch.float32)

traced = torch.jit.trace(
    wrapper,
    (example_input_ids, example_attention, example_bbox, example_pixels),
    strict=False,
)

try:
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        inputs=[
            ct.TensorType(name="input_ids", shape=example_input_ids.shape, dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=example_attention.shape, dtype=np.int32),
            ct.TensorType(name="bbox", shape=example_bbox.shape, dtype=np.int32),
            ct.TensorType(name="pixel_values", shape=example_pixels.shape, dtype=np.float32),
        ],
        outputs=[ct.TensorType(name="logits")],
    )
except NotImplementedError as exc:
    raise SystemExit(
        "coremltools could not convert this LayoutLMv3 graph directly. "
        "If the message mentions an unsupported PyTorch op such as 'new_ones', "
        "export a wrapper that removes dynamic attention-mask creation or convert "
        "through an ONNX graph with static masks before running coremltools. "
        f"Original error: {exc}"
    )
mlmodel.save(out)
print(out)
PY

xcrun coremlcompiler compile "${PYTHON_OUT}" "${WORK_DIR}"
mv "${WORK_DIR}/${OUT_NAME}.mlmodelc" "${COMPILED_OUT}"

echo "Installed LayoutLMv3 CoreML artifact:"
echo "  ${COMPILED_OUT}"
echo
echo "For the booted simulator, copy this directory into the app container's Application Support/DreamWork/models/ directory."
