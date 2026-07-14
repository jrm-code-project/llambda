  # llambda.lisp

  **A Bare-Metal, Multi-Threaded, AVX2-Accelerated LLM Inference Engine in Pure
Common Lisp.**

  `llambda.lisp` is an independent, zero-dependency (beyond `sb-simd` and
`lparallel`) inference engine for running quantized Large Language Models
directly from `.gguf` files.

  The default CPU path does not wrap `llama.cpp` or call an external inference
runtime. It reads the raw weights, unpacks the 4-bit/6-bit nibbles, constructs
the transformer architecture, and executes the forward pass natively within
SBCL. Experimental, opt-in accelerator paths use a small C++ bridge to ONNX
Runtime with DirectML for GPUs and AMD's VitisAI execution provider for NPUs.

  ## Why?

  Because the industry has succumbed to the dogma that C++ is the only path to
bare-metal AI inference. `llambda.lisp` exists to prove that properly
architected, aggressively typed, and hardware-aware Common Lisp can achieve
C-level throughput without sacrificing the interactive, REPL-driven elegance of
Lisp.

  ## Features & Architecture

*   **Native GGUF Parsing:** Directly ingests and parses `Q4_K_M` and `Q6_K` quantized tensors from disk.
*   **AVX2 / FMA Acceleration:** The core GEMV (Matrix-Vector Multiplication) bottleneck is pulverized using SBCL's `sb-simd`. Unrolled `f32.8` vectors, unaligned loads (`VMOVUPS`), and packed Fused Multiply-Add (`VFMADD213PS`) instructions are emitted natively by the Lisp compiler.
*   **Multi-Threaded Execution:** The outer loop of the GEMV processing is fully parallelized via `lparallel`, saturating modern multi-core memory buses (e.g., 24-core Ryzen processors) with isolated, lock-free writes.
*   **Zero-Drift KV Cache:** Safe, shared-KV reuse and perfectly aligned RoPE scaling. Exact-logit replay tests against fresh un-cached generations yield a `max_diff` of `0.0`.
*   **Advanced Sampling:** Built-in Top-K, Top-P (Nucleus), and repetition penalties executing in-place with zero heap allocation in the hot path.
*   **Experimental Ryzen AI NPU backend:** Fixed-shape ONNX projections can replace selected CPU matrix-vector operations through an optional CFFI bridge. The CPU implementation remains the mandatory default and fallback.
*   **Experimental DirectML GPU backend:** Selected projections can run on DirectML-capable AMD, Intel, or NVIDIA GPUs. Routing is always GPU, then NPU, then CPU.

### Supported architectures

Architecture selection uses the GGUF `general.architecture` metadata value.

| GGUF architecture | Supported model family and execution path |
| --- | --- |
| `gemma4` | Gemma 4 base/instruct models with sliding/global attention, shared KV layers, Gemma BPE, and chat formatting |
| `llama` | Llama 3.1 layouts with grouped-query attention, scaled RoPE, SwiGLU, byte-level BPE, and instruct formatting |
| `qwen2` | Dense Qwen2 models with grouped-query attention, Q/K/V biases, SwiGLU, Qwen2 byte-level BPE, and ChatML formatting |
| `qwen3next` | Qwen3Next hybrid attention/recurrent models with dense or routed MoE feed-forward layers |
| `nemotron_h_moe` | Nemotron-H MoE hybrid attention/recurrent models with routed and shared experts |

  ## Requirements

*   **SBCL:** You must run a modern SBCL compiled with SIMD support. 
*   **Operating System:** The current file-mapping layer requires Windows and uses `CreateFileMappingW`/`MapViewOfFile`. Porting it to Unix should be straightforward by replacing the small Windows-specific file and mapping layer with `open`/`mmap` equivalents.
*   **Hardware:** An x86_64 CPU with AVX2 instruction set support. Multi-core processors heavily recommended to prevent memory-bus starvation.
*   **Dependencies:** `sb-simd`, `lparallel`.

### Optional DirectML GPU backend

The GPU backend uses ONNX Runtime's DirectML execution provider to dispatch
D3D12 compute shaders on Windows. ONNX Runtime CPU execution-provider fallback
is disabled for GPU sessions, so an unsupported graph fails GPU setup and
continues through llambda's explicit NPU/CPU fallback rather than being
reported as GPU work. Build the native bridge against an ONNX Runtime
distribution that includes DirectML. `ORT_ROOT` may be passed directly to
CMake; the Ryzen AI installation remains the default when it is not specified:

```powershell
.\native\build-npu.ps1 `
  -Backend GPU `
  -OrtRoot "C:\path\to\onnxruntime-directml"
```

GPU builds are written to `native\build-gpu` so they cannot overwrite the
Ryzen AI build in `native\build`.

Load and probe DirectML from Lisp with:

```lisp
(llambda:load-gpu-backend)
(llambda:gpu-backend-available-p)
(llambda:gpu-backend-runtime-version)
```

GPU acceleration is strictly opt-in. The high-level inference API accepts
`:use-gpu t` together with either `:gpu-tensor-names` or bounded
`:gpu-layer-indices` and `:gpu-projection-roles`. Both accelerator paths share
the content-addressed cache machinery, with BF16 graphs for VitisAI and
float32 graphs for DirectML.

```lisp
(llambda:test-gguf-file-response
  #P"D:/path/to/model.gguf"
  :use-gpu t
  :gpu-layer-indices '(0)
  :gpu-projection-roles '(:attention-key))
```

If DirectML, a compatible GPU, graph conversion, or session setup is
unavailable, llambda warns and continues on the CPU. A runtime GPU failure
disables only that tensor's GPU session and tries an enabled NPU session before
recomputing on the CPU. When both accelerators are enabled for a tensor, llambda
tries the GPU first, then the NPU, and finally the CPU.

### Optional AMD Ryzen AI NPU backend

The experimental backend currently targets Ryzen AI Software 1.7.1 and its
ONNX Runtime VitisAI execution provider. Building it requires Visual Studio
C++ tools and CMake:

```powershell
.\native\build-npu.ps1
.\native\build\Release\llambda_npu_smoke.exe `
  "C:\Program Files\RyzenAI\1.7.1\quicktest\test_model.onnx" 3 20
```

Load and probe the bridge from Lisp with:

```lisp
(llambda:load-npu-backend)
(llambda:npu-backend-available-p)
(llambda:npu-backend-runtime-version)
```

`register-model-npu-projection` associates a tensor name with a fixed-shape
ONNX model containing the corresponding weights. The ONNX model must accept
one float32 input and produce one float32 output with dimensions matching the
GGUF tensor. `clear-model-npu-projections` releases all sessions.

The repository includes `native/generate-matmul-model.py` for synthetic BF16
benchmarks. `export-model-npu-projection` dequantizes one mapped GGUF matrix to
a temporary BF16 stream and invokes that generator to create a persistent ONNX
projection. For example, pass
`:python-command '("conda" "run" "-n" "ryzen-ai-dunce" "python")` when ONNX is
installed in the Ryzen AI Conda environment. The resulting ONNX file can then
be passed to `register-model-npu-projection`.

`ensure-model-npu-projection` automates export and registration. It hashes the
packed GGUF tensor with SHA-256 and caches the generated ONNX graph under
`%LOCALAPPDATA%\llambda\npu-cache` by tensor content, dimensions, GGML type,
bridge version, generator SHA-256, and ONNX Runtime version. A changed tensor,
generator, or runtime therefore cannot silently reuse an incompatible graph.
Exports replace their destination atomically only after ONNX generation
succeeds. `enable-model-npu-projections` does the same for an explicit list of
tensor names and rolls back sessions it added if any conversion or compilation
fails.

`model-npu-layer-projection-names` selects Q/K/V, attention-output, and
feed-forward projections by layer and role while validating that the
architecture actually contains each tensor. `test-gguf-file-response` accepts
either `:npu-tensor-names` or bounded `:npu-layer-indices` plus
`:npu-projection-roles`.

NPU use in the high-level inference path is strictly opt-in and additionally
requires `:use-npu t`. Supplying projection names without that flag has no
effect and does not load the bridge. If the bridge, ONNX Runtime, VitisAI
provider, NPU hardware, conversion, or session setup is unavailable, llambda
warns and continues entirely on the CPU. If a registered projection fails
during inference, llambda removes that session, recomputes the operation on the
CPU, and leaves the remaining model usable. Low-level setup APIs remain
fail-fast so callers can diagnose configuration problems.

NPU and GPU setup are independent. Enabling both preserves working GPU
sessions if NPU setup fails and vice versa. Runtime GPU failures fall through
to an enabled NPU session before using the CPU.

```lisp
(llambda:test-gguf-file-response
  #P"D:/path/to/model.gguf"
  :use-npu t
  :npu-layer-indices '(0)
  :npu-projection-roles '(:attention-key))
```

Ryzen AI 1.7.1 recompiles the generated BF16 graph when creating a new VitisAI
session even when the ONNX conversion cache is reused. llambda therefore keeps
registered sessions alive across token steps; clearing and recreating sessions
incurs that compilation cost again.

### CPU, NPU, and GPU projection benchmark

`benchmark-gguf-projection-backends` compares the native quantized CPU GEMV
with NPU and DirectML sessions for one two-dimensional GGUF tensor. Graph
export and session compilation happen before timing. The report includes
milliseconds per run, effective GFLOP/s, speedup over CPU, and maximum absolute
output drift from the CPU result.

```lisp
(llambda:benchmark-gguf-projection-backends
  #P"D:/path/to/model.gguf"
  "blk.0.attn_k.weight"
  :warmup-runs 3
  :timed-runs 20
  :npu-python-command '("conda" "run" "-n" "ryzen-ai-dunce" "python")
  :gpu-python-command '("conda" "run" "-n" "ryzen-ai-dunce" "python"))
```

The benchmark requests both accelerators explicitly and reports an unavailable
backend without preventing the remaining measurements. Pass `:use-npu nil` or
`:use-gpu nil` to benchmark a subset. Cached projection graphs make subsequent
runs skip export.

  ## Quickstart

```lisp
(ql:quickload :llambda)

;; Load a model and run an end-to-end inference pass
(llambda:test-gguf-file-response 
  "D:/path/to/your/model/gemma-4-E4B-it-Q4_K_M.gguf" 
  "Write a haiku about a hacker drinking coffee."
  :top-k 40 
  :top-p 0.95
  :repetition-penalty 1.15)
```

### Chatbot backend plugin

Load `llambda/chatbot` after the sibling `chatbot` system. It registers
`:llambda` in chatbot's pluggable backend registry. The chatbot model value is
the local GGUF pathname:

```lisp
(asdf:load-system :llambda/chatbot)

(defparameter *local-chat*
  (chatbot:new-chat
   :backend :llambda
   :model "D:/path/to/model.gguf"))

(chatbot:chat "Write a haiku about Lisp." :conversation *local-chat*)
```

Text callbacks, conversation history, system instructions, temperature, and
top-p are supported. File attachments and tool calls are not supported.

  ## Performance & Optimization

  If you are modifying the core dot-product macros (`expand-q4-k-body`), heed
this warning: **Do not allocate in the inner loop.** The hot paths rely on
strict `(declare (optimize (speed 3) (safety 0) (debug 0) (space 0)))` policies
and zero-consing execution. If the compiler begins boxing floats or allocating
vectors on the heap, performance will catastrophically collapse.

  ## Current Status & Roadmap

*   [x] Gemma4 Base & Instruct (Verified)
*   [x] Top-K / Top-P / Rep-Pen Sampler
*   [x] AVX2/FMA `Q4_K_M` and `Q6_K` paths
*   [x] Qwen2, Qwen3Next, and Nemotron-H MoE inference
*   [x] Llama 3.1 architecture and instruct tokenization
*   [x] Optional VitisAI CFFI bridge and per-projection NPU routing
*   [x] Optional DirectML GPU bridge with GPU-to-NPU-to-CPU routing
*   [x] Per-tensor GGUF-to-BF16 ONNX export
*   [x] Automatic content-addressed NPU projection cache
*   [x] Architecture-aware projection selection and end-to-end NPU inference
*   [ ] Multi-layer performance and memory-capacity tuning

  ## Author **Joe Marshall**

  ## License
  MIT License. See [LICENSE](LICENSE) for details.
  
  ## Contributions
  Contributions are welcome! Please submit pull requests or open
  issues for bug reports and feature requests.
  
