#!/usr/bin/env python3
"""Regenerate `core/dreamwork_core/fixtures/identity.onnx` (single Identity op). Requires `pip install onnx`."""

from pathlib import Path

import onnx
from onnx import TensorProto, helper


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out = root / "core" / "dreamwork_core" / "fixtures" / "identity.onnx"
    out.parent.mkdir(parents=True, exist_ok=True)

    x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [1])
    y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [1])
    node = helper.make_node("Identity", ["x"], ["y"])
    graph = helper.make_graph([node], "identity_g", [x], [y])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    onnx.checker.check_model(model)
    out.write_bytes(model.SerializeToString())
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
