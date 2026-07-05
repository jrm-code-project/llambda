(defpackage #:llambda
  (:use #:cl)
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
           #:map-view-of-file
           #:main
           #:print-gguf-file
           #:read-gguf-header
           #:read-gguf-kv-pairs
           #:rms-norm
           #:sample-from-probabilities
           #:sample-token-id-from-logits
           #:silu
           #:softmax
           #:test-llm-response
           #:tokenize-prompt
           #:unmap-view-of-file
           #:vector-matrix-multiply
           #:with-file-handle
           #:with-mapped-file))
