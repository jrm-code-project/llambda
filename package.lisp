(defpackage #:llambda
  (:use #:cl)
  (:import-from #:sb-simd-avx2
                #:f32.8
                #:f32.8*
                #:f32.8-
                #:f32.8-aref
                #:f32.8-horizontal+
                #:make-f32.8)
  (:import-from #:sb-simd-fma
                #:f32.8-fmadd)
  (:export #:call-with-file
           #:call-with-mapped-file
           #:apply-temperature
           #:apply-rope
           #:apply-silu
           #:close-handle
           #:create-file
           #:dequantize-q4-k-m
           #:dequantize-q6-k
           #:detokenize-token-id
           #:detokenize-token-ids
           #:decode-next-token
           #:evaluate-prompt
           #:generate-from-prompt
           #:generate-token-loop
           #:hello-message
           #:find-gguf-tensor-info
           #:load-gemma4-model
           #:load-gguf-tensor
           #:load-gguf-tensor-by-name
           #:make-gemma4-step-function
           #:map-view-of-file
           #:main
           #:print-gguf-file
           #:print-gguf-floating-point-tables
           #:copy-tensors-to-aligned-temp-file
           #:map-gguf-tensors-to-aligned-arrays
           #:forged-dot-product
           #:read-gguf-header
           #:read-gguf-kv-pairs
           #:read-gguf-tensor-infos
           #:rms-norm
           #:sample-from-probabilities
           #:sample-token-id-from-logits
           #:silu
           #:softmax
           #:test-gguf-file-response
           #:test-llm-response
           #:tokenize-prompt
           #:unmap-view-of-file
           #:vector-matrix-multiply
           #:with-file-handle
           #:with-mapped-file))
