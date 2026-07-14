(in-package #:llambda)

(register-architecture
 "gemma4"
 #'load-gemma4-model
 #'make-gemma4-step-function
 :replace t
 :tokenizer-policy :gemma4
 :required-metadata-keys
 '("gemma4.embedding_length"
   "gemma4.block_count"
   "gemma4.attention.head_count"
   "gemma4.attention.head_count_kv"
   "gemma4.feed_forward_length"
   "gemma4.attention.layer_norm_rms_epsilon"
   "gemma4.attention.sliding_window"
   "gemma4.rope.freq_base"
   "gemma4.rope.freq_base_swa"
   "gemma4.rope.dimension_count"
   "gemma4.rope.dimension_count_swa")
 :required-tensor-groups
 '(("token_embd.weight")
   ("output_norm.weight")
   ("rope_freqs.weight")
   ("output.weight" "token_embd.weight")))
