(in-package #:llambda)

(register-architecture
 "qwen3next"
 #'load-qwen3next-model
 #'make-qwen3next-step-function
 :replace t
 :tokenizer-policy :qwen
 :required-metadata-keys
 '("qwen3next.embedding_length"
   "qwen3next.block_count"
   "qwen3next.attention.head_count"
   "qwen3next.attention.head_count_kv"
   "qwen3next.attention.layer_norm_rms_epsilon"
   "qwen3next.rope.freq_base"
   "qwen3next.rope.dimension_count")
 :required-tensor-groups
 '(("token_embd.weight")
   ("output_norm.weight")
   ("output.weight" "token_embd.weight")))
