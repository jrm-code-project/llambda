(in-package #:llambda)

(register-architecture
 "qwen2"
 #'load-qwen2-model
 #'make-qwen2-step-function
 :replace t
 :tokenizer-policy :qwen
 :required-metadata-keys
 '("qwen2.embedding_length"
   "qwen2.block_count"
   "qwen2.attention.head_count"
   "qwen2.attention.head_count_kv"
   "qwen2.feed_forward_length"
   "qwen2.attention.layer_norm_rms_epsilon"
   "qwen2.rope.freq_base")
 :required-tensor-groups
 '(("token_embd.weight")
   ("output_norm.weight")
   ("output.weight" "token_embd.weight")))
