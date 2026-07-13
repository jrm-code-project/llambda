  # llambda.lisp

  **A Bare-Metal, Multi-Threaded, AVX2-Accelerated LLM Inference Engine in Pure
Common Lisp.**

  `llambda.lisp` is an independent, zero-dependency (beyond `sb-simd` and
`lparallel`) inference engine for running quantized Large Language Models
directly from `.gguf` files.

  It does not wrap `llama.cpp`. It does not call out to external C or C++
libraries. It reads the raw weights, unpacks the 4-bit/6-bit nibbles, constructs
the transformer architecture, and executes the forward pass natively within
SBCL.

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
*   **Gemma4 Support:** Full support for Gemma4 architectures, including BPE tokenization, proper instruction-tuning chat templates (`<bos><|turn>user...`), and explicit tool-calling channel overrides. 
*   **Llama 3.1 Support:** Native grouped-query attention, scaled RoPE, byte-level BPE, and instruct chat-template handling for Llama 3.1 GGUF models.

  ## Requirements

*   **SBCL:** You must run a modern SBCL compiled with SIMD support. 
*   **Hardware:** An x86_64 CPU with AVX2 instruction set support. Multi-core processors heavily recommended to prevent memory-bus starvation.
*   **Dependencies:** `sb-simd`, `lparallel`.

  ## Quickstart

```lisp
(ql:quickload :llambda)

;; Load a model and run an end-to-end inference pass
(llambda:test-gguf-file-response 
  "D:/path/to/your/model/gemma-4-E4B-it-Q4_K_M.gguf" 
  "Write a haiku about a hacker drinking coffee."
  :top-k 40 
  :top-p 0.90 
  :repetition-penalty 1.15)
```

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
*   [x] Qwen3Next and Nemotron-H MoE inference
*   [x] Llama 3.1 architecture and instruct tokenization

  ## Author **Joe Marshall**

  ## License
  MIT License. See [LICENSE](LICENSE) for details.
  
  ## Contributions
  Contributions are welcome! Please submit pull requests or open
  issues for bug reports and feature requests.
  
