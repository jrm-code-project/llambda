import argparse
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper


def bfloat16_raw(values: np.ndarray) -> bytes:
    bits = values.astype(np.float32, copy=False).view(np.uint32)
    rounded = bits + np.uint32(0x7FFF) + ((bits >> 16) & 1)
    return (rounded >> 16).astype(np.uint16).tobytes()


def make_model(rows: int, columns: int, dtype: str,
               weights_path: Path | None) -> onnx.ModelProto:
    if weights_path:
        if dtype != "bfloat16":
            raise ValueError("external weights currently require bfloat16")
        raw_weights = weights_path.read_bytes()
        expected_size = rows * columns * 2
        if len(raw_weights) != expected_size:
            raise ValueError(
                f"{weights_path} has {len(raw_weights)} bytes; "
                f"expected {expected_size}"
            )
        weights_shape = (rows, columns)
    else:
        rng = np.random.default_rng(12345)
        weights = rng.standard_normal((rows, columns), dtype=np.float32)
        weights /= np.sqrt(np.float32(columns))
        weights_shape = weights.shape
        raw_weights = bfloat16_raw(weights)

    nodes = []
    if dtype == "bfloat16":
        initializer = helper.make_tensor(
            "weights",
            TensorProto.BFLOAT16,
            weights_shape,
            raw_weights,
            raw=True,
        )
        nodes.extend(
            [
                helper.make_node("Cast", ["input"], ["input_bf16"],
                                 to=TensorProto.BFLOAT16),
                helper.make_node("Gemm", ["input_bf16", "weights"],
                                 ["output_bf16"], transB=1),
                helper.make_node("Cast", ["output_bf16"], ["output"],
                                 to=TensorProto.FLOAT),
            ]
        )
    else:
        initializer = helper.make_tensor(
            "weights",
            TensorProto.FLOAT,
            weights_shape,
            weights.tobytes(),
            raw=True,
        )
        nodes.append(helper.make_node("Gemm", ["input", "weights"],
                                      ["output"], transB=1))

    graph = helper.make_graph(
        nodes,
        "llambda_projection",
        [helper.make_tensor_value_info("input", TensorProto.FLOAT,
                                       [1, columns])],
        [helper.make_tensor_value_info("output", TensorProto.FLOAT,
                                       [1, rows])],
        [initializer],
    )
    model = helper.make_model(
        graph,
        producer_name="llambda",
        opset_imports=[helper.make_opsetid("", 17)],
    )
    model.ir_version = 8
    onnx.checker.check_model(model)
    return model


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a fixed-shape ONNX projection for NPU benchmarks."
    )
    parser.add_argument("output", type=Path)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument(
        "--dtype", choices=("bfloat16", "float32"), default="bfloat16"
    )
    parser.add_argument(
        "--weights",
        type=Path,
        help="Raw row-major BF16 weights with shape [rows, columns].",
    )
    args = parser.parse_args()
    if args.rows <= 0 or args.columns <= 0:
        parser.error("rows and columns must be positive")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    onnx.save_model(make_model(args.rows, args.columns, args.dtype,
                               args.weights),
                    args.output)
    print(args.output)


if __name__ == "__main__":
    main()
