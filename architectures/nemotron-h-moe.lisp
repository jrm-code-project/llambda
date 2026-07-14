(in-package #:llambda)

(register-architecture
 "nemotron_h_moe"
 #'load-nemotron-h-moe-model
 #'make-nemotron-h-moe-step-function
 :replace t
 :tokenizer-policy :qwen
 :required-metadata-keys
 '("nemotron_h_moe.embedding_length"
   "nemotron_h_moe.block_count"
   "nemotron_h_moe.attention.head_count"
   "nemotron_h_moe.attention.head_count_kv"
   "nemotron_h_moe.feed_forward_length"
   "nemotron_h_moe.attention.layer_norm_rms_epsilon"
   "nemotron_h_moe.rope.freq_base"
   "nemotron_h_moe.rope.dimension_count"
   "nemotron_h_moe.ssm.inner_size"
   "nemotron_h_moe.ssm.state_size"
   "nemotron_h_moe.ssm.group_count"
   "nemotron_h_moe.ssm.time_step_rank"
   "nemotron_h_moe.ssm.conv_kernel"
   "nemotron_h_moe.expert_used_count")
 :required-tensor-groups
 '(("token_embd.weight")
   ("output_norm.weight")
   ("output.weight" "token_embd.weight")))
