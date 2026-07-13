# Copilot instructions for `llambda`

This is a Windows-focused Common Lisp GGUF inspection and native inference
runtime. It runs quantized models directly in SBCL rather than wrapping
`llama.cpp`.

## Build, test, and lint

- Requirements are SBCL on x86-64 with AVX2 support plus the ASDF dependencies
  `cffi`, `sb-simd`, `lparallel`, and `fiveam` for tests.
- Load/compile the runtime with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:load-system :llambda)'`
- Run full test suite with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:test-system :llambda)'`
- The full suite includes Gemma 4 end-to-end tests that expect the model at
  `D:/Models/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf`.
- Run single test with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:load-system :llambda/tests)' --eval '(let ((result (fiveam:run (quote llambda/tests::hello-message)))) (fiveam:explain! result) (unless (fiveam:results-status result) (error "single test failed")))'`
- For other single-test runs, replace `llambda/tests::hello-message` with another test symbol from `tests.lisp`.
- No dedicated lint or formatter command is committed.

## High-level architecture

- `llambda.asd` defines two ASDF systems: runtime system `llambda` and test system `llambda/tests`. Both use `:serial t`, so `package.lisp` loads before `llambda.lisp`, and `asdf:test-system :llambda` delegates to `llambda/tests:run-tests`.
- `package.lisp` is public API boundary. Almost all implementation lives in `llambda.lisp`, which mixes several layers:
  - Windows file and memory-mapping bindings via CFFI (`CreateFileW`, `CreateFileMappingW`, `MapViewOfFile`, `UnmapViewOfFile`)
  - GGUF parsing, metadata decoding, tensor discovery, and tensor dequantization/loading
  - AVX2/FMA and `lparallel` numeric kernels for quantized matrix-vector operations
  - Tokenization, prompt evaluation, sampling, and decode loops
  - Architecture-specific Gemma 4, Llama 3.1, Qwen3Next, and Nemotron-H MoE loaders and step functions
- Main runtime flow is: open a GGUF with `call-with-file`/`with-file-handle` -> map it with `call-with-mapped-file`/`with-mapped-file` -> parse header, metadata, and tensor infos -> construct a `gguf-model` for a supported architecture -> evaluate prompt tokens and decode against its step function.
- `test-gguf-file-response` is the end-to-end dispatcher. It selects the Gemma 4, Llama, Qwen3Next, or Nemotron-H MoE loader from `general.architecture`, then creates the matching step function.
- Generic GGUF storage is shared through `gguf-model`: tensor metadata is indexed by name and loaded vectors are cached. Architecture loaders interpret their own metadata and tensor names; their step functions implement attention, recurrent/SSM, dense FFN, or MoE layers as required.
- Generation state is separated from model construction: `evaluate-prompt` advances prompt tokens, `generate-token-loop` samples and decodes continuation tokens, the caller-supplied `kv-cache` stores attention and recurrent state, and a step function closes over a reusable `compute-buffer`.
- `tests.lisp` is not only smoke tests. It exercises Windows file/mmap helpers, numeric kernels, GGUF parsing, tensor loading, tokenization, and end-to-end generation behavior through FiveAM.

## Key conventions

- Runtime is Windows-specific today. File access and mmap behavior go through `kernel32`, so new filesystem or mapping code should match Windows semantics and path handling.
- Performance-sensitive math helpers use `single-float` arrays and commonly come in pairs: non-allocating `*-into` functions plus allocating wrappers. Follow that pattern for new vector/tensor operations.
- Do not allocate or box floats in quantized inner loops. The Q4_K/Q6_K hot paths use `sb-simd` AVX2/FMA expansion macros, aggressive optimization declarations, and a persistent `lparallel` kernel; preserve that structure when changing GEMV code.
- Keep generic GGUF parsing and tensor loading model-agnostic. Architecture checks and metadata interpretation belong in loaders such as `load-gemma4-model`; architecture execution belongs in the corresponding `make-*-step-function`.
- Fail fast on invalid model data or shape mismatches. Existing helpers raise `error` for unsupported GGML types, missing tensors, bad token ids, incompatible vector sizes, and failed Windows handles instead of returning sentinel values.
- GGUF metadata and tensor names are raw strings compared with `string=`. Use architecture-prefixed metadata keys and `blk.<index>.<suffix>.weight` tensor names rather than introducing keyword normalization.
- Tokenizer helpers prefer `tokenizer.ggml.*` keys with `general.*` fallbacks for BOS/EOS and add-BOS values. Gemma 4 uses raw UTF-8 BPE plus special-token parsing; Llama 3.1 uses its `llama-bpe` pre-tokenizer and GPT-2 byte mapping. Both wrap plain prompts in architecture-specific chat templates.
- Reuse model caches instead of reloading tensors repeatedly. `gguf-model` keeps tensor info tables and cached tensors keyed by tensor name, while inference reuses `compute-buffer` scratch storage across token steps.
- Public entrypoints belong in `package.lisp`. Tests mostly import exported symbols, but internal helpers may be referenced as `llambda::...` when behavior is intentionally package-internal and still needs direct coverage.
- Tests create temporary text and GGUF fixtures under `uiop:temporary-directory`, write binary layouts inline, and clean up with `unwind-protect` instead of relying on committed fixture files.
- Test-side binary fixture writers use explicit little-endian helper functions and SBCL conditionals (`#+sbcl`) for float-bit and UTF-8 conversions; extend those helpers in-place rather than introducing external fixture generators.
- Treat compiled Lisp artifacts as generated files. `.gitignore` already excludes `.fasl` variants and related implementation-specific outputs.
