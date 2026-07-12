# Copilot instructions for `llambda`

`README.md` currently describes this repository as **"LLM hacks"**. In practice, current codebase is Windows-focused Common Lisp runtime for GGUF inspection, tensor loading, tokenization, and Gemma 4 inference experiments.

## Build, test, and lint

- No dedicated lint command is committed.
- Run full test suite with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:test-system :llambda)'`
- Run single test with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:load-system :llambda/tests)' --eval '(let ((result (fiveam:run (quote llambda/tests::hello-message)))) (fiveam:explain! result) (unless (fiveam:results-status result) (error "single test failed")))'`
- For other single-test runs, replace `llambda/tests::hello-message` with another test symbol from `tests.lisp`.

## High-level architecture

- `llambda.asd` defines two ASDF systems: runtime system `llambda` and test system `llambda/tests`. Both use `:serial t`, so `package.lisp` loads before `llambda.lisp`, and `asdf:test-system :llambda` delegates to `llambda/tests:run-tests`.
- `package.lisp` is public API boundary. Almost all implementation lives in `llambda.lisp`, which mixes several layers:
  - Windows file and memory-mapping bindings via CFFI (`CreateFileW`, `CreateFileMappingW`, `MapViewOfFile`, `UnmapViewOfFile`)
  - GGUF parsing, metadata decoding, tensor discovery, and tensor dequantization/loading
  - Numeric and generation primitives such as RMS norm, matrix/vector math, RoPE, softmax, sampling, tokenization, prompt evaluation, and decode loops
  - Gemma 4 model loading and inference, centered on `gguf-model`, `load-gemma4-model`, and `make-gemma4-step-function`
- Main runtime data flow is: open file with `call-with-file`/`with-file-handle` -> map bytes with `call-with-mapped-file`/`with-mapped-file` -> parse header, metadata, and tensor infos -> optionally build `gguf-model` -> run prompt evaluation and token generation against a step function.
- Inference path is split between generic GGUF readers and model-specific execution. `load-gemma4-model` validates `general.architecture = "gemma4"`, then `make-gemma4-step-function` closes over reusable compute buffers and KV-cache state for autoregressive decoding.
- Generation state is intentionally separated: `evaluate-prompt` advances prompt tokens through step function, `generate-token-loop` samples and decodes continuation tokens, `kv-cache` stores per-layer attention state across positions, and `compute-buffer` reuses scratch vectors/chunk views to reduce allocation churn during inference.
- `tests.lisp` is not only smoke tests. It exercises Windows file/mmap helpers, numeric kernels, GGUF parsing, tensor loading, tokenization, and end-to-end generation behavior through FiveAM.

## Key conventions

- Runtime is Windows-specific today. File access and mmap behavior go through `kernel32`, so new filesystem or mapping code should match Windows semantics and path handling.
- Performance-sensitive math helpers use `single-float` arrays and commonly come in pairs: non-allocating `*-into` functions plus allocating wrappers. Follow that pattern for new vector/tensor operations.
- Keep generic GGUF parsing separate from architecture-specific inference. Container readers should stay model-agnostic; architecture checks belong in loaders like `load-gemma4-model`.
- Fail fast on invalid model data or shape mismatches. Existing helpers raise `error` for unsupported GGML types, missing tensors, bad token ids, incompatible vector sizes, and failed Windows handles instead of returning sentinel values.
- GGUF metadata keys are handled as raw strings, and tokenizer helpers prefer `tokenizer.ggml.*` keys with fallbacks to `general.*` where models may encode BOS/EOS or add-BOS defaults there.
- Reuse model caches instead of reloading tensors repeatedly. `gguf-model` keeps tensor info tables and cached tensors keyed by tensor name, while inference reuses `compute-buffer` scratch storage across token steps.
- Public entrypoints belong in `package.lisp`. Tests mostly import exported symbols, but internal helpers may be referenced as `llambda::...` when behavior is intentionally package-internal and still needs direct coverage.
- Tests create temporary text and GGUF fixtures under `uiop:temporary-directory`, write binary layouts inline, and clean up with `unwind-protect` instead of relying on committed fixture files.
- Test-side binary fixture writers use explicit little-endian helper functions and SBCL conditionals (`#+sbcl`) for float-bit and UTF-8 conversions; extend those helpers in-place rather than introducing external fixture generators.
- Treat compiled Lisp artifacts as generated files. `.gitignore` already excludes `.fasl` variants and related implementation-specific outputs.
