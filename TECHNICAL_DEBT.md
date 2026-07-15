# Technical debt

This register covers the highest-impact debt in `llambda.lisp`. It is ordered
by risk, not by ease of cleanup. It is not a list of style complaints or a
request to replace the specialized numeric kernels.

## Snapshot

- `llambda.lisp` contains 7,972 lines and 364 `defun` forms.
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
| 2 | P0 | Native resource ownership and forged arrays lacked a safe lifecycle (**addressed 2026-07-14**) | Dangling arrays, leaked views/handles/sessions, and SBCL-version fragility |
| 3 | P1 | Architecture dispatch was centralized (**addressed 2026-07-14**) | Adding or changing a model family required edits to multiple coupled dispatch sites |
| 4 | P1 | Accelerator lifecycle was duplicated (**addressed 2026-07-14**) | Backend behavior could drift and another provider would multiply code paths |
| 5 | P1 | Inference state was implicit and step functions were non-reentrant (**addressed 2026-07-14**) | Concurrent or interleaved use could corrupt scratch or architecture-specific state |
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

**Status: Addressed on 2026-07-14.** Aligned tensors are now opaque foreign
views owned by an `aligned-tensor-mapping`; the public path no longer forges
Lisp array headers. Closing the owner invalidates every tensor view before
unmapping and is idempotent. Scoped call/with APIs preserve non-local exits and
the primary failure. Models and the GEMV worker kernel also have explicit close
operations, and high-level generation closes its model after accelerator setup
or inference.

**Evidence**

- GEMV kernel shutdown is explicit at `llambda.lisp:758-768`.
- Model ownership and idempotent accelerator/cache cleanup are represented at
  `llambda.lisp:2174-2199` and `2283-2298`.
- Opaque aligned tensor owners and views are defined at
  `llambda.lisp:6881-6944`.
- Idempotent invalidation/cleanup and scoped ownership are implemented at
  `llambda.lisp:6946-7025`.
- Aligned mapping acquisition transfers all handles and views into one owner
  and cleans up on every non-local exit (`llambda.lisp:7027-7176`).

**Original risk**

The code exposes objects whose validity depends on external handles remaining
open, but the ownership relationship is not represented by the type system or
API. The forged arrays are especially hazardous: using one after unmapping is
a native-memory error, while SBCL layout changes can invalidate the forging
logic even when callers clean up correctly.

**Implemented remediation**

1. Added idempotent `close-model`, `close-aligned-tensor-mapping`, and
   `close-gemv-runtime` operations.
2. Replaced the aligned-mapping plist with a structure that owns its tensor
   views, mapped views, mapping handle, file handle, and validity state.
3. Replaced forged Lisp arrays with opaque checked foreign-storage views while
   retaining zero-copy access and direct float dot products.
4. Added `call-with-aligned-tensor-mapping` and
   `with-aligned-tensor-mapping`; view access is invalidated before unmapping,
   and cleanup does not replace a primary non-local exit.
5. Kept lifecycle deterministic rather than relying on finalizers.

**Exit criterion met:** every native handle, mapped view, accelerator session,
worker pool, and aligned tensor mapping has a documented owner and explicit
idempotent close path. Model mappings remain intentionally borrowed from the
surrounding `with-mapped-file` scope and are invalidated by `close-model`.

## 3. Replace central architecture dispatch with descriptors

**Status: Addressed on 2026-07-14.** Architecture selection now uses an
immutable descriptor registered by a dedicated ASDF architecture component.
Each descriptor owns its loader, step constructor, tokenizer policy, required
metadata, required tensor alternatives, and optional validator. Model setup
performs one registry lookup and validates the descriptor contract before
loading; token and layer hot paths contain no registry lookup or generic
dispatch.

**Evidence**

- The descriptor protocol, registry, and pre-load contract validation are in
  `architecture.lisp`.
- Built-in registrations are isolated under `architectures/` and loaded as
  separate ASDF components by `llambda.asd`.
- `generate-gguf-response` resolves a descriptor once and uses its loader and
  step constructor (`llambda.lisp:1558-1695`).
- Prompt and stop-token behavior consume the registered tokenizer policy
  (`llambda.lisp:1424-1556`).
- Registry, duplicate registration, required metadata, required tensor, loader,
  validator, and step-constructor behavior are covered in
  `tests.lisp:371-438`.

**Original debt**

Adding an architecture requires synchronized edits to loader dispatch, step
dispatch, metadata extraction, tensor naming, tokenizer/chat behavior, and a
shared structure. The loader and step registries can diverge. Common dense
attention, FFN, normalization, and cache behavior is embedded inside large
functions instead of being composed from validated components.

**Implemented remediation**

1. Define an architecture descriptor containing metadata schema, loader,
   tokenizer/chat policy, validator, and step constructor.
2. Isolated each built-in registration in its own ASDF architecture component.
3. Centralized descriptor contract validation before loader execution.
4. Routed prompt preparation and stop-token selection through the descriptor's
   tokenizer policy.
5. Added focused descriptor registration and validation tests.

The specialized forward-pass implementations and shared `gguf-model` remain in
`llambda.lisp`. Moving those large forms or adding abstraction inside their hot
paths was intentionally excluded because it would not improve the exit
criterion and would create unnecessary performance risk. Existing shared
attention, MoE selection, normalization, and compute-buffer helpers continue to
be reused directly.

**Exit criterion met:** adding an architecture requires one registration module
and ASDF component, without editing `generate-gguf-response` or adding dispatch
inside inference hot paths.

## 4. Introduce one accelerator backend protocol

**Status: Addressed on 2026-07-14.** Accelerator providers now register
immutable descriptors that own loading, capability probes, session operations,
error translation, cache representation, export behavior, hashing, and separate
initialization/execution priorities. DirectML and VitisAI are thin adapters over
the shared native bridge.

**Evidence**

- The descriptor protocol and reload-safe registry are in `accelerator.lisp`.
- DirectML and VitisAI registrations are isolated in
  `accelerators/directml.lisp` and `accelerators/vitisai.lisp`.
- Model-owned bindings use one tensor-indexed, priority-ordered projection
  store (`llambda.lisp:2217-2429`).
- Registration, rollback, caching, enablement, setup fallback, runtime fallback,
  and cleanup are provider-neutral (`llambda.lisp:2276-2849`,
  `4185-4267`).
- Fake descriptors exercise capability failure, cache independence, priority,
  runtime fallback, descriptor replacement, per-binding disablement, and
  cleanup (`tests.lisp:523-673`).

**Original debt**

The two backends implement the same lifecycle independently, so fixes to
validation, fallback, cleanup, or cache identity can land in only one path.
The shared DLL/runtime is hidden behind two global variables, making adapter
selection and multi-device support difficult to reason about or test.

**Implemented remediation**

1. Defined a descriptor and registry for provider operations and policy.
2. Replaced separate GPU/NPU tables with one tensor-to-binding-vector store,
   avoiding tuple allocation and reducing the CPU path to one hash lookup.
3. Made execution priority data-driven as GPU, NPU, CPU. Initialization uses a
   separate NPU-before-GPU priority because both providers share one DLL and the
   NPU-capable build also exposes DirectML.
4. Consolidated projection registration, cache identity, export, rollback,
   setup, runtime fallback, and cleanup.
5. Moved SHA-256 operations behind descriptors so custom backends do not depend
   on the NPU bridge.
6. Retained all exported GPU- and NPU-named APIs as compatibility wrappers.
7. Added fake-provider tests plus real DirectML/VitisAI capability and
   projection benchmarks.

Provider-specific CFFI declarations, native session wrappers, and conditions
remain intentionally inside the native adapters. They represent actual ABI
differences rather than duplicated model lifecycle.

**Exit criterion met:** adding a backend requires a descriptor and native
adapter, not another copy of projection lifecycle or inference-routing code.

## 5. Make inference state explicit and reentrant

**Status: Addressed on 2026-07-14.** Each request now uses an explicit
`inference-context` that owns architecture state, compute and sampling
workspaces, position, context limit, logits policy, and lifecycle state.
Architecture step closures no longer capture mutable compute buffers. Separate
contexts can execute concurrently against one model and step implementation,
while legacy hash-table callers retain source compatibility.

**Evidence**

- Context ownership, validation, reset, close, scoped use, and legacy adaptation
  are implemented at `llambda.lisp:48-68` and `2409-2588`.
- Prompt evaluation and token generation use context-owned position, logits
  policy, and sampling workspaces (`llambda.lisp:1317-1498`).
- Qwen3Next, Nemotron-H, Llama/Qwen2, and Gemma4 steps resolve context-owned
  scratch and state once per token (`llambda.lisp:5411-6715`).
- Model tensor-cache publication and accelerator binding updates use locked
  copy-on-write snapshots, while successful reads remain lock-free
  (`llambda.lisp:2611-2783`, `3810-3850`).
- Lifecycle, independent threaded contexts, cache publication, deferred session
  retirement, cleanup failure, and compatibility behavior are covered in
  `tests.lisp`.

**Original debt**

A step closure is safe only for one active execution at a time, but that
constraint is not represented or enforced. Concurrent requests sharing a
closure can overwrite scratch buffers. Bare hash tables provide no model
identity, context limit, reset contract, or validation that state belongs to
the architecture consuming it.

**Implemented remediation**

1. Introduced an `inference-context` owning scratch, KV/recurrent state,
   position, logits policy, and model identity.
2. Made architecture steps accept a context instead of closing over mutable
   scratch.
3. Added initialize/reset/close operations and enforced context limits.
4. Allocated one context per request; pooling remains deferred until ownership is
   explicit.

Model tensor data and accelerator sessions remain shared and model-owned.
Cache misses and accelerator mutations publish immutable table snapshots;
failed or removed sessions are retired only after active contexts drain.
Shared accelerator sessions serialize provider runs because DirectML sessions
do not support concurrent execution. Locks and registry lookups remain outside
layer and quantized inner loops, and the CPU path remains lock-free.

Against commit `e908599`, a paired warmed benchmark measured a 20-token Gemma4
prompt at 29.44 seconds versus 30.18 seconds, and six decoded tokens at 10.66
seconds versus 10.68 seconds. Allocation was effectively unchanged (109.00 MB
prompt and 69.33 MB decode in both revisions).

**Exit criterion met:** the same model and step implementation safely serve two
independent contexts concurrently, with no measured inference regression.

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
