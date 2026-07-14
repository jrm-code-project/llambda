# Technical debt

This register covers the highest-impact debt in `llambda.lisp`. It is ordered
by risk, not by ease of cleanup. It is not a list of style complaints or a
request to replace the specialized numeric kernels.

## Snapshot

- `llambda.lisp` contains 6,974 lines and 313 `defun` forms.
- It combines Win32 resource management, GGUF parsing, tensor formats,
  quantized kernels, accelerator integration, sampling, tokenization, and five
  model architectures.
- The largest forms include `make-qwen3next-step-function` (about 298 lines),
  `make-gemma4-step-function` (about 235 lines), and
  `generate-gguf-response` (about 162 lines).

Priority meanings:

- **P0:** Native-memory safety or resource-ownership risk.
- **P1:** High change amplification, correctness risk, or blocked evolution.
- **P2:** Material operational or performance debt without immediate safety
  impact.

## Ranked summary

| Rank | Priority | Item | Primary consequence |
| ---: | :---: | --- | --- |
| 1 | P0 | GGUF reads were not bounded by the mapped file size (**addressed 2026-07-14**) | Malformed input could drive out-of-bounds native reads or excessive allocation |
| 2 | P0 | Native resource ownership and forged arrays lack a safe lifecycle | Dangling arrays, leaked views/handles/sessions, and SBCL-version fragility |
| 3 | P1 | Architecture support is centralized in a superset model and large forward passes | Adding or changing a model family touches multiple coupled dispatch sites |
| 4 | P1 | Accelerator implementations are duplicated and coupled through NPU-named state | Backend behavior can drift and another provider would multiply code paths |
| 5 | P1 | Inference state is implicit and step functions are non-reentrant | Concurrent or interleaved use can corrupt scratch or architecture-specific state |
| 6 | P1 | GGML type behavior is spread across several independent dispatch tables | New formats are easy to implement partially or inconsistently |
| 7 | P1 | Chat templates are detected but not interpreted | Valid model templates can silently receive the wrong conversation format |
| 8 | P2 | Runtime tuning and sampling state are global or repeatedly recomputed | Hardware underutilization, thread contention, and avoidable per-token work |

## 1. Bound every GGUF read

**Status: Addressed on 2026-07-14.** `call-with-mapped-file` now registers an
exact `mapped-region`, all GGUF structural reads use checked range helpers,
metadata and tensor counts are bounded by the remaining bytes, and tensor data
intervals are validated once before model construction. Malformed fixtures
cover truncated headers, oversized strings, invalid dimensions, and tensor
data outside the mapping. The validated inference kernels still receive raw
pointers, so no checks were added to per-row or per-element hot paths.

**Evidence**

- Mapped-region registration and range validation are implemented at
  `llambda.lisp:498-542` and `568-626`.
- Checked GGUF readers and structurally bounded metadata parsing are at
  `llambda.lisp:1745-1895`.
- Tensor dimensions, descriptors, and data intervals are validated at
  `llambda.lisp:1965-2047`.

**Original risk**

The parser cannot prove that a read lies within the mapping because size is
not part of its input. A truncated, corrupt, or adversarial GGUF can therefore
cause native reads past the mapping, arithmetic overflow, or allocations based
on unreasonable counts. Validation distributed after individual reads cannot
repair this missing boundary.

**Implemented remediation**

1. Introduced a `mapped-region` containing pointer and byte length.
2. Replaced parser-level raw reads with checked helpers using
   overflow-safe range calculations.
3. Bounded metadata/tensor counts by the remaining encoded bytes and restricted
   tensor dimensionality to the GGUF limit.
4. Validated every supported tensor interval against the mapped file before
   model construction.
5. Added focused truncated/corrupt fixture tests.

**Exit criterion met:** file-backed parsing and tensor loading prove ranges
inside a `mapped-region` before dereferencing. Explicit caller-owned foreign
buffers remain supported by the low-level tensor-loading API.

## 2. Make native ownership explicit

**Evidence**

- `gguf-model` stores a borrowed mapping pointer alongside caches and
  accelerator sessions (`llambda.lisp:1958-1982`).
- Public model loaders return models without owning or closing their mapping
  (`llambda.lisp:5221-5272`, `5434-5467`).
- NPU/GPU sessions require manual unregister/clear calls
  (`llambda.lisp:1984-2057`).
- `map-gguf-tensors-to-aligned-arrays` returns live views and handles in a
  plist but has no matching close operation (`llambda.lisp:6641-6762`).
- That function forges SBCL object headers using hard-coded widetags, object
  offsets, and internal slots (`llambda.lisp:6714-6749`).
- The global `lparallel` kernel is persistent and has no public shutdown
  lifecycle (`llambda.lisp:663-674`).

**Why this is debt**

The code exposes objects whose validity depends on external handles remaining
open, but the ownership relationship is not represented by the type system or
API. The forged arrays are especially hazardous: using one after unmapping is
a native-memory error, while SBCL layout changes can invalidate the forging
logic even when callers clean up correctly.

**Remediation**

1. Add idempotent `close-model`, `close-aligned-mapping`, and
   `close-gemv-runtime` operations plus `call-with-*`/`with-*` scopes.
2. Replace the aligned-mapping plist with a structure that owns its views,
   mapping handle, file handle, and validity state.
3. Keep forged arrays behind an explicitly SBCL-specific module; prefer
   foreign-storage accessors or a copy-based fallback at public boundaries.
4. Invalidate access before unmapping and preserve the primary condition when
   cleanup also fails.
5. Use finalizers only as leak protection, not as the primary lifecycle.

**Exit criterion:** every native handle, view, session, worker pool, and
mapping has one documented owner and an idempotent close path.

## 3. Replace central architecture dispatch with descriptors

**Evidence**

- `gguf-model` is a superset structure containing generic and
  architecture-specific fields (`llambda.lisp:1958-1982`).
- Model loading and step construction use separate central dispatch blocks
  (`llambda.lisp:1503-1533`).
- Loaders repeat metadata extraction and model construction
  (`llambda.lisp:4418-4441`, `5115-5138`, `5221-5272`, `5434-5467`).
- Forward passes are large architecture-specific closures
  (`llambda.lisp:4443-4740`, `5140-5220`, `5274-5426`, `5503-5737`).

**Why this is debt**

Adding an architecture requires synchronized edits to loader dispatch, step
dispatch, metadata extraction, tensor naming, tokenizer/chat behavior, and a
shared structure. The loader and step registries can diverge. Common dense
attention, FFN, normalization, and cache behavior is embedded inside large
functions instead of being composed from validated components.

**Remediation**

1. Define an architecture descriptor containing metadata schema, loader,
   tensor naming, tokenizer/chat policy, validator, and step constructor.
2. Move each architecture into its own ASDF component.
3. Extract reusable dense-attention, SwiGLU, MoE, and recurrent block
   components with explicit shape contracts.
4. Add descriptor tests that validate required metadata and tensors before
   running a forward pass.

**Exit criterion:** adding an architecture registers one descriptor and module
without editing the central generation function.

## 4. Introduce one accelerator backend protocol

**Evidence**

- NPU and GPU duplicate FFI declarations, session structures, conditions, and
  execution wrappers (`llambda.lisp:54-122`, `232-330`).
- GPU loading aliases NPU library state, and shared bridge operations retain
  NPU names (`llambda.lisp:124-230`).
- Projection registration, rollback, setup, and cleanup are duplicated
  (`llambda.lisp:1984-2057`, `2142-2332`).
- GPU cache generation calls helpers named for NPU
  (`llambda.lisp:2092-2209`).

**Why this is debt**

The two backends implement the same lifecycle independently, so fixes to
validation, fallback, cleanup, or cache identity can land in only one path.
The shared DLL/runtime is hidden behind two global variables, making adapter
selection and multi-device support difficult to reason about or test.

**Remediation**

1. Define an accelerator descriptor/protocol for load, probe, create, run,
   close, cache representation, and condition translation.
2. Store model projections in one table keyed by `(backend, tensor-name)`.
3. Express GPU/NPU preference as ordered backend data rather than nested
   conditionals.
4. Inject fake descriptors in capability/fallback tests.
5. Rename shared bridge, hashing, generator, and cache helpers to
   provider-neutral terms while retaining compatibility aliases.

**Exit criterion:** adding a backend requires a descriptor and native adapter,
not another copy of projection lifecycle code.

## 5. Make inference state explicit and reentrant

**Evidence**

- Step functions close over one mutable `compute-buffer`
  (`llambda.lisp:4443-4457`, `5140-5162`, `5274-5297`, `5503-5513`).
- Scratch storage is dynamically keyed in hash tables
  (`llambda.lisp:4002-4045`).
- KV and recurrent state use architecture-specific hash-table/plist layouts
  (`llambda.lisp:3996-4000`, `4199-4213`, `4754-4766`).
- `*compute-gguf-logits*` is a hidden dynamic contract between prompt
  evaluation and all step implementations (`llambda.lisp:34`, `1189-1194`).

**Why this is debt**

A step closure is safe only for one active execution at a time, but that
constraint is not represented or enforced. Concurrent requests sharing a
closure can overwrite scratch buffers. Bare hash tables provide no model
identity, context limit, reset contract, or validation that state belongs to
the architecture consuming it.

**Remediation**

1. Introduce an `inference-context` owning scratch, KV/recurrent state,
   position, logits policy, and model identity.
2. Make architecture steps accept a context instead of closing over mutable
   scratch.
3. Provide initialize/reset/close operations and enforce context limits.
4. Allocate one context per request; add pooling only after ownership is
   explicit.

**Exit criterion:** the same model/step implementation can safely serve two
independent contexts concurrently.

## 6. Centralize GGML type descriptors

**Evidence**

Type knowledge is repeated in:

- support and naming (`llambda.lisp:1754-1775`);
- block and byte sizes (`llambda.lisp:1777-1806`);
- full-tensor loading (`llambda.lisp:1931-1948`);
- row loading and non-allocating row loading (`llambda.lisp:2946-2980`);
- dot-product/GEMV dispatch (`llambda.lisp:3528-3675`).

The `*-into` row path also falls back to allocating loaders for several types,
which weakens the non-allocating contract (`llambda.lisp:2971-2979`).

**Why this is debt**

A new quantization format can be recognized and sized while still lacking a
row loader or optimized GEMV path. These partial implementations fail late or
silently fall onto allocation-heavy generic paths.

**Remediation**

1. Define one GGML type descriptor containing tag, name, block size, byte
   size, full loader, row loader, `*-into` loader, and dot-product kernel.
2. Derive support checks and dispatch tables from the descriptor registry.
3. Test every registered type against a required capability matrix.
4. Make allocating fallback explicit rather than hidden inside an `*-into`
   function.

**Exit criterion:** registering a type fails at load time unless all required
operations are supplied.

## 7. Execute chat templates instead of guessing them

**Evidence**

- Existing prompt detection uses substring searches
  (`llambda.lisp:1309-1329`).
- The code checks that `tokenizer.chat_template` exists but emits hard-coded
  Gemma, Llama, and Qwen strings (`llambda.lisp:1331-1378`).
- The Qwen path injects a fixed system message
  (`llambda.lisp:1371-1373`).
- Stop tokens are inferred through family-specific heuristics
  (`llambda.lisp:1419-1447`).

**Why this is debt**

Template revisions, roles, escaping rules, thought channels, and model
variants can differ while retaining the same tokenizer family. The current
logic can therefore produce a syntactically valid but semantically incorrect
prompt without an obvious failure.

**Remediation**

1. Separate message-based generation from raw-prompt generation.
2. Implement or integrate the required GGUF/Jinja template subset.
3. Derive stop behavior from template/metadata configuration.
4. Retain current family-specific formatting only as a documented fallback
   with golden fixtures.

**Exit criterion:** supported models use their stored template for structured
messages, with family-specific strings covered only as fallback behavior.

## 8. Isolate runtime tuning and sampling state

**Evidence**

- GEMV defaults to a process-global 24-worker kernel and fixed row threshold
  (`llambda.lisp:35-37`, `663-687`).
- Repetition penalty finds prior occurrences with nested scans
  (`llambda.lisp:906-956`).
- Public sampling mutates a caller's logits when they already have the target
  array type (`llambda.lisp:1142-1187`).
- Temperature/softmax still allocate vocabulary-sized arrays per token
  (`llambda.lisp:866-904`, `1176-1186`).

**Why this is debt**

The worker count is tuned to one machine and a global kernel can contend with
multiple inference requests. Sampling mutation is not visible in the API
name, and repeated history scans/allocation scale poorly with longer contexts
or concurrent generation.

**Remediation**

1. Move worker count, parallel threshold, and kernel ownership into a runtime
   configuration with hardware-aware defaults and benchmark overrides.
2. Make destructive sampling APIs explicit or copy at the public boundary.
3. Add sampler state with reusable vocabulary workspaces and token-presence
   tracking.
4. Fuse candidate scaling/normalization only after measuring it against the
   current top-k implementation.

**Exit criterion:** separate runtimes can choose independent worker and
sampling policies without mutating process-global state.

## Deliberate tradeoffs that are not debt by themselves

- Windows and SBCL are explicit current platform targets. The debt is that
  unsafe implementation-specific code is not isolated, not that optimized
  platform code exists.
- `single-float` storage, `*-into` APIs, SIMD expansion macros, and persistent
  scratch buffers are appropriate for this runtime.
- `(safety 0)` in measured inner kernels is reasonable when a checked wrapper
  establishes all bounds and shape contracts. It becomes debt only when raw
  pointers or unchecked public inputs can reach those kernels directly.
- Heap-based top-k and insertion sorting of the already-small candidate set
  are intentional performance choices and should not be replaced without
  benchmarks.

## Recommended sequence

1. Add bounded mapped-region parsing and malformed-file tests.
2. Introduce explicit model/mapping/session/aligned-view ownership.
3. Add inference contexts before enabling shared-model concurrency.
4. Create architecture and GGML descriptor registries.
5. Collapse accelerator lifecycle code behind one protocol.
6. Implement metadata-driven chat templates.
7. Make runtime tuning and sampler state configurable.
