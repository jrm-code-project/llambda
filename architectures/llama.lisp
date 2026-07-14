(in-package #:llambda)

(register-architecture
 "llama"
 #'load-llama-model
 #'make-llama-step-function
 :replace t
 :tokenizer-policy :llama
 :required-metadata-keys
 '("llama.embedding_length"
   "llama.block_count"
   "llama.attention.head_count"
   "llama.attention.head_count_kv"
   "llama.feed_forward_length"
   "llama.attention.layer_norm_rms_epsilon"
   "llama.rope.freq_base"
   "llama.rope.dimension_count")
 :required-tensor-groups
 '(("token_embd.weight")
   ("output_norm.weight")
   ("output.weight" "token_embd.weight")))
