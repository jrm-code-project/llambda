(defpackage #:llambda/tests
  (:use #:cl #:fiveam)
  (:import-from #:llambda #:aligned-tensor-mapping-closed-p
                          #:aligned-tensor-mapping-p
                          #:aligned-tensor-mapping-tensors
                          #:aligned-tensor-view-dot-product
                          #:aligned-tensor-view-element-type
                          #:aligned-tensor-view-length
                          #:aligned-tensor-view-p
                          #:aligned-tensor-view-ref
                          #:call-with-aligned-tensor-mapping
                          #:call-with-file
                          #:call-with-mapped-file
                          #:apply-repetition-penalty
                          #:apply-top-k
                          #:apply-top-p
                          #:apply-temperature
                          #:apply-rope
                          #:apply-silu
                          #:benchmark-gguf-projection-backends
                          #:close-aligned-tensor-mapping
                          #:close-gemv-runtime
                          #:close-handle
                          #:close-model
                          #:create-file
                          #:dequantize-q4-k-m
                          #:dequantize-q6-k
                          #:detokenize-token-id
                          #:detokenize-token-ids
                          #:decode-next-token
                          #:default-gpu-cache-directory
                          #:default-npu-cache-directory
                          #:enable-model-gpu-projections
                          #:enable-model-gpu-layer-projections
                          #:enable-model-npu-projections
                          #:enable-model-npu-layer-projections
                          #:ensure-model-gpu-projection
                          #:ensure-model-npu-projection
                          #:evaluate-prompt
                          #:export-model-gpu-projection
                          #:export-model-npu-projection
                          #:find-gguf-tensor-info
                          #:generate-from-prompt
                          #:generate-gguf-response
                          #:generate-token-loop
                          #:hello-message
                          #:load-gemma4-model
                          #:load-gpu-backend
                          #:load-llama-model
                          #:load-npu-backend
                          #:load-qwen2-model
                          #:load-gguf-tensor
                          #:load-gguf-tensor-by-name
                          #:make-gemma4-step-function
                          #:make-llama-step-function
                          #:make-qwen2-step-function
                          #:model-gpu-layer-projection-names
                          #:model-npu-layer-projection-names
                          #:gpu-backend-available-p
                          #:gpu-backend-runtime-version
                          #:npu-backend-available-p
                          #:npu-backend-runtime-version
                          #:register-model-gpu-projection
                          #:register-model-npu-projection
                          #:clear-model-gpu-projections
                          #:clear-model-npu-projections
                          #:unregister-model-gpu-projection
                          #:unregister-model-npu-projection
                          #:map-view-of-file
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
                          #:with-aligned-tensor-mapping
                          #:with-file-handle
                          #:with-mapped-file)
  (:export #:run-tests))

(in-package #:llambda/tests)

(def-suite llambda-suite
  :description "Tests for the llambda system.")

(in-suite llambda-suite)

(test hello-message
  (is (string= "llambda ready." (hello-message))))

(test windows-bindings
  (is (fboundp 'aligned-tensor-mapping-closed-p))
  (is (fboundp 'aligned-tensor-mapping-p))
  (is (fboundp 'aligned-tensor-mapping-tensors))
  (is (fboundp 'aligned-tensor-view-dot-product))
  (is (fboundp 'aligned-tensor-view-element-type))
  (is (fboundp 'aligned-tensor-view-length))
  (is (fboundp 'aligned-tensor-view-p))
  (is (fboundp 'aligned-tensor-view-ref))
  (is (fboundp 'call-with-aligned-tensor-mapping))
  (is (fboundp 'call-with-file))
  (is (fboundp 'call-with-mapped-file))
  (is (fboundp 'apply-repetition-penalty))
  (is (fboundp 'apply-top-k))
  (is (fboundp 'apply-top-p))
  (is (fboundp 'apply-temperature))
  (is (fboundp 'apply-rope))
  (is (fboundp 'apply-silu))
  (is (fboundp 'benchmark-gguf-projection-backends))
  (is (fboundp 'close-aligned-tensor-mapping))
  (is (fboundp 'close-gemv-runtime))
  (is (fboundp 'create-file))
  (is (fboundp 'close-handle))
  (is (fboundp 'close-model))
  (is (fboundp 'dequantize-q4-k-m))
  (is (fboundp 'dequantize-q6-k))
  (is (fboundp 'detokenize-token-id))
  (is (fboundp 'detokenize-token-ids))
  (is (fboundp 'decode-next-token))
  (is (fboundp 'default-gpu-cache-directory))
  (is (fboundp 'default-npu-cache-directory))
  (is (fboundp 'enable-model-gpu-projections))
  (is (fboundp 'enable-model-gpu-layer-projections))
  (is (fboundp 'enable-model-npu-projections))
  (is (fboundp 'enable-model-npu-layer-projections))
  (is (fboundp 'ensure-model-gpu-projection))
  (is (fboundp 'ensure-model-npu-projection))
  (is (fboundp 'evaluate-prompt))
  (is (fboundp 'export-model-gpu-projection))
  (is (fboundp 'export-model-npu-projection))
  (is (fboundp 'find-gguf-tensor-info))
  (is (fboundp 'generate-from-prompt))
  (is (fboundp 'generate-gguf-response))
  (is (fboundp 'generate-token-loop))
  (is (fboundp 'hello-message))
  (is (fboundp 'load-gemma4-model))
  (is (fboundp 'load-gpu-backend))
  (is (fboundp 'load-llama-model))
  (is (fboundp 'load-npu-backend))
  (is (fboundp 'load-qwen2-model))
  (is (fboundp 'load-gguf-tensor))
  (is (fboundp 'load-gguf-tensor-by-name))
  (is (fboundp 'make-gemma4-step-function))
  (is (fboundp 'make-llama-step-function))
  (is (fboundp 'make-qwen2-step-function))
  (is (fboundp 'model-gpu-layer-projection-names))
  (is (fboundp 'model-npu-layer-projection-names))
  (is (fboundp 'gpu-backend-available-p))
  (is (fboundp 'gpu-backend-runtime-version))
  (is (fboundp 'npu-backend-available-p))
  (is (fboundp 'npu-backend-runtime-version))
  (is (fboundp 'register-model-gpu-projection))
  (is (fboundp 'register-model-npu-projection))
  (is (fboundp 'clear-model-gpu-projections))
  (is (fboundp 'clear-model-npu-projections))
  (is (fboundp 'unregister-model-gpu-projection))
  (is (fboundp 'unregister-model-npu-projection))
  (is (fboundp 'map-view-of-file))
  (is (fboundp 'print-gguf-file))
  (is (fboundp 'read-gguf-header))
  (is (fboundp 'read-gguf-kv-pairs))
  (is (fboundp 'read-gguf-tensor-infos))
  (is (fboundp 'rms-norm))
  (is (fboundp 'sample-from-probabilities))
  (is (fboundp 'sample-token-id-from-logits))
  (is (fboundp 'silu))
  (is (fboundp 'softmax))
  (is (fboundp 'test-gguf-file-response))
  (is (fboundp 'test-llm-response))
  (is (fboundp 'tokenize-prompt))
  (is (fboundp 'unmap-view-of-file))
  (is (fboundp 'vector-matrix-multiply))
  (is (macro-function 'with-aligned-tensor-mapping))
  (is (macro-function 'with-file-handle))
  (is (macro-function 'with-mapped-file)))

(test forward-primitives
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon))
         (sfv (&rest values)
           (make-array (length values)
                       :element-type 'single-float
                       :initial-contents values)))
    (let ((normed (rms-norm #(3.0f0 4.0f0)
                            #(1.0f0 2.0f0)
                            :epsilon 0.0f0)))
      (is (approx= 0.84852815f0 (aref normed 0)))
      (is (approx= 2.2627418f0 (aref normed 1))))
    (let ((projected (vector-matrix-multiply #(1.0f0 2.0f0 3.0f0)
                                             #(1.0f0 0.0f0 -1.0f0
                                               0.5f0 1.0f0 0.0f0)
                                             2
                                             3)))
      (is (approx= -2.0f0 (aref projected 0)))
      (is (approx= 2.5f0 (aref projected 1))))
    (let ((dest (make-array 2 :element-type 'single-float)))
      (is (eq dest
              (llambda::vector-add-into dest (sfv 1.0f0 2.0f0) (sfv 3.0f0 4.0f0))))
      (is (approx= 4.0f0 (aref dest 0)))
      (is (approx= 6.0f0 (aref dest 1))))
    (let ((dest (make-array 2 :element-type 'single-float)))
      (is (eq dest
              (llambda::rms-norm-into dest (sfv 3.0f0 4.0f0) (sfv 1.0f0 2.0f0)
                                      :epsilon 0.0f0)))
      (is (approx= 0.84852815f0 (aref dest 0)))
      (is (approx= 2.2627418f0 (aref dest 1))))
    (let ((dest (make-array 2 :element-type 'single-float)))
      (is (eq dest
              (llambda::vector-elementwise-multiply-into
               dest (sfv 2.0f0 3.0f0) (sfv 4.0f0 5.0f0))))
      (is (approx= 8.0f0 (aref dest 0)))
      (is (approx= 15.0f0 (aref dest 1))))
    (is (approx= 1.7615942f0 (silu 2.0f0)))
    (let ((activated (apply-silu #(0.0f0 2.0f0))))
      (is (approx= 0.0f0 (aref activated 0)))
      (is (approx= 1.7615942f0 (aref activated 1))))
    (let ((rotated (apply-rope #(1.0f0 0.0f0 5.0f0 6.0f0)
                               1
                               :rope-dimension 2)))
      (is (approx= (coerce (cos 1.0d0) 'single-float) (aref rotated 0)))
      (is (approx= (coerce (sin 1.0d0) 'single-float) (aref rotated 1)))
      (is (approx= 5.0f0 (aref rotated 2)))
      (is (approx= 6.0f0 (aref rotated 3))))))

(test gemma4-shared-kv-layer-mapping
  (let ((model (llambda::make-gguf-model
                :layer-count 6
                :shared-kv-layers 2
                :sliding-pattern '(t nil t nil t nil))))
    (is (= 4 (llambda::gguf-model-kv-layer-count model)))
    (is (= 0 (llambda::gguf-model-layer-kv-source-index model 0)))
    (is (= 3 (llambda::gguf-model-layer-kv-source-index model 3)))
    (is (= 2 (llambda::gguf-model-layer-kv-source-index model 4)))
    (is (= 3 (llambda::gguf-model-layer-kv-source-index model 5)))))

(test gemma4-cache-append-copies-heads
  (let* ((kv-cache (make-hash-table))
         (key-storage (make-array 4
                                  :element-type 'single-float
                                  :initial-contents '(1.0f0 2.0f0 3.0f0 4.0f0)))
         (value-storage (make-array 4
                                    :element-type 'single-float
                                    :initial-contents '(5.0f0 6.0f0 7.0f0 8.0f0)))
         (key-heads (make-array 2 :initial-contents
                                (list (make-array 2
                                                  :element-type 'single-float
                                                  :displaced-to key-storage
                                                  :displaced-index-offset 0)
                                      (make-array 2
                                                  :element-type 'single-float
                                                  :displaced-to key-storage
                                                  :displaced-index-offset 2))))
         (value-heads (make-array 2 :initial-contents
                                  (list (make-array 2
                                                    :element-type 'single-float
                                                    :displaced-to value-storage
                                                    :displaced-index-offset 0)
                                        (make-array 2
                                                    :element-type 'single-float
                                                    :displaced-to value-storage
                                                    :displaced-index-offset 2)))))
    (llambda::gemma4-cache-append kv-cache 0 key-heads value-heads)
    (setf (aref key-storage 0) 99.0f0
          (aref key-storage 3) 88.0f0
          (aref value-storage 1) 77.0f0
          (aref value-storage 2) 66.0f0)
    (let* ((layer-cache (gethash 0 kv-cache))
           (cached-keys (getf layer-cache :keys))
           (cached-values (getf layer-cache :values))
           (cached-key-heads (aref cached-keys 0))
           (cached-value-heads (aref cached-values 0)))
      (is (= 1.0f0 (aref (aref cached-key-heads 0) 0)))
      (is (= 4.0f0 (aref (aref cached-key-heads 1) 1)))
      (is (= 6.0f0 (aref (aref cached-value-heads 0) 1)))
      (is (= 7.0f0 (aref (aref cached-value-heads 1) 0))))))

(test llama-model-loader
  (let* ((kv-pairs '(("general.architecture" . "llama")
                     ("llama.embedding_length" . 16)
                     ("llama.block_count" . 2)
                     ("llama.attention.head_count" . 4)
                     ("llama.attention.head_count_kv" . 2)
                     ("llama.feed_forward_length" . 32)
                     ("llama.attention.layer_norm_rms_epsilon" . 1.0e-5)
                     ("llama.rope.freq_base" . 500000.0)
                     ("llama.rope.dimension_count" . 4)))
         (tensor-infos '((:name "token_embd.weight")
                         (:name "output.weight")))
         (model (load-llama-model nil kv-pairs tensor-infos)))
    (is (string= "llama" (llambda::gguf-model-architecture model)))
    (is (= 16 (llambda::gguf-model-hidden-size model)))
    (is (= 2 (llambda::gguf-model-layer-count model)))
    (is (= 4 (llambda::gguf-model-head-count model)))
    (is (= 2 (llambda::gguf-model-kv-head-count model)))
    (is (= 32 (llambda::gguf-model-ffn-size model)))
    (is (hash-table-p (llambda::gguf-model-npu-projections model)))
    (is (hash-table-p (llambda::gguf-model-gpu-projections model)))
    (is (string= "output.weight"
                 (llambda::gguf-model-output-tensor-name model))))
  (let* ((kv-pairs '(("general.architecture" . "llama")
                     ("llama.embedding_length" . 16)
                     ("llama.block_count" . 1)
                     ("llama.attention.head_count" . 4)
                     ("llama.attention.head_count_kv" . 2)
                     ("llama.feed_forward_length" . 32)
                     ("llama.attention.layer_norm_rms_epsilon" . 1.0e-5)
                     ("llama.rope.freq_base" . 500000.0)
                     ("llama.rope.dimension_count" . 4)))
         (model (load-llama-model nil kv-pairs '((:name "token_embd.weight")))))
    (is (string= "token_embd.weight"
                 (llambda::gguf-model-output-tensor-name model)))))

(test qwen2-model-loader
  (let* ((kv-pairs '(("general.architecture" . "qwen2")
                     ("qwen2.embedding_length" . 16)
                     ("qwen2.block_count" . 2)
                     ("qwen2.attention.head_count" . 4)
                     ("qwen2.attention.head_count_kv" . 2)
                     ("qwen2.feed_forward_length" . 32)
                     ("qwen2.attention.layer_norm_rms_epsilon" . 1.0e-5)
                     ("qwen2.rope.freq_base" . 1000000.0)))
         (model (load-qwen2-model
                 nil
                 kv-pairs
                 '((:name "token_embd.weight")
                   (:name "output.weight")
                   (:name "blk.0.attn_k.weight")
                   (:name "blk.0.attn_output.weight")))))
    (is (string= "qwen2" (llambda::gguf-model-architecture model)))
    (is (= 16 (llambda::gguf-model-hidden-size model)))
    (is (= 4 (llambda::gguf-model-rope-dimension model)))
    (is (equal '("blk.0.attn_k.weight"
                 "blk.0.attn_output.weight")
               (model-npu-layer-projection-names
                model
                '(0)
                :roles '(:attention-key :attention-output))))
    (is (string= "output.weight"
                 (llambda::gguf-model-output-tensor-name model)))))

(test native-runtime-close-lifecycle
  (let* ((tensor-cache (make-hash-table :test #'equal))
         (model
           (llambda::make-gguf-model
            :mapping (cffi:make-pointer 1)
            :tensor-cache tensor-cache
            :npu-projections (make-hash-table :test #'equal)
            :gpu-projections (make-hash-table :test #'equal))))
    (setf (gethash "cached.weight" tensor-cache) #(1.0f0))
    (is (eq model (close-model model)))
    (is (llambda::gguf-model-closed-p model))
    (is (null (llambda::gguf-model-mapping model)))
    (is (zerop (hash-table-count tensor-cache)))
    (is (eq model (close-model model)))
    (signals error
      (register-model-npu-projection model "closed.weight" #P"closed.onnx"))
    (signals error
      (register-model-gpu-projection model "closed.weight" #P"closed.onnx")))
  (let ((llambda::*gemv-worker-count* 1))
    (is (llambda::ensure-gemv-kernel))
    (is (null (close-gemv-runtime)))
    (is (null llambda::*gemv-kernel*))
    (is (null (close-gemv-runtime)))))

(test npu-bf16-export-primitives
  (is (= #x3f80 (llambda::single-float-to-bf16-bits 1.0f0)))
  (is (= #xc000 (llambda::single-float-to-bf16-bits -2.0f0)))
  (is (= #x3f80 (llambda::single-float-to-bf16-bits 1.001f0))))

(test gpu-f32-export-primitives
  (let ((path (merge-pathnames
               #P"llambda-gpu-f32-export.bin"
               (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file (stream path
                                  :direction :output
                                  :if-exists :supersede
                                  :element-type '(unsigned-byte 8))
            (llambda::write-f32-le stream 1.0f0)
            (llambda::write-f32-le stream -2.0f0))
          (with-open-file (stream path :element-type '(unsigned-byte 8))
            (let ((bytes (make-array 8 :element-type '(unsigned-byte 8))))
              (is (= 8 (read-sequence bytes stream)))
              (is (equalp #(0 0 128 63 0 0 0 192) bytes)))))
      (when (probe-file path)
        (delete-file path)))))

(test npu-soft-fallback
  (let ((disabled-p nil))
    (handler-bind ((warning #'muffle-warning))
      (is (eq :cpu
              (llambda::call-with-npu-runtime-fallback
               (lambda ()
                 (llambda::npu-backend-error "simulated bridge failure"))
               (lambda () :cpu)
               (lambda () (setf disabled-p t))
               "test.weight")))
      (is (not (null disabled-p)))
      (is (null
           (llambda::call-with-npu-setup-fallback
            (lambda () (error "simulated missing bridge")))))
      (let ((model
              (llambda::make-gguf-model
               :architecture "test"
               :layer-count 1
               :tensor-info-table (make-hash-table :test #'equal))))
        (is (null
             (llambda::try-enable-model-npu-projections
              model
              nil
              :layer-indices '(0)
              :projection-roles '(:attention-key))))
        (is (null
             (llambda::try-enable-model-gpu-projections
              model
              nil
              :layer-indices '(0)
              :projection-roles '(:attention-key))))))))

(test gpu-priority-and-soft-fallback
  (let ((npu-disabled-p nil)
        (gpu-disabled-p nil)
        (npu-called-p nil)
        (cpu-called-p nil))
    (is (eq :gpu
            (llambda::call-with-gpu-runtime-fallback
             (lambda () :gpu)
             (lambda ()
              (setf npu-called-p t)
              :npu)
             (lambda () (setf gpu-disabled-p t))
             "test.weight")))
    (is (not npu-called-p))
    (handler-bind ((warning #'muffle-warning))
      (is (eq :npu
              (llambda::call-with-gpu-runtime-fallback
              (lambda ()
                (llambda::gpu-backend-error "simulated GPU failure"))
              (lambda ()
                (llambda::call-with-npu-runtime-fallback
                 (lambda () :npu)
                 (lambda ()
                   (setf cpu-called-p t)
                   :cpu)
                 (lambda () (setf npu-disabled-p t))
                 "test.weight"))
              (lambda () (setf gpu-disabled-p t))
              "test.weight")))
      (is (not (null gpu-disabled-p)))
      (is (not npu-disabled-p))
      (is (not cpu-called-p))
      (setf npu-disabled-p nil
            gpu-disabled-p nil)
      (is (eq :cpu
              (llambda::call-with-gpu-runtime-fallback
              (lambda ()
                (llambda::gpu-backend-error "simulated GPU failure"))
              (lambda ()
                (llambda::call-with-npu-runtime-fallback
                 (lambda ()
                   (llambda::npu-backend-error "simulated NPU failure"))
                 (lambda () :cpu)
                 (lambda () (setf npu-disabled-p t))
                 "test.weight"))
              (lambda () (setf gpu-disabled-p t))
              "test.weight")))
      (is (not (null npu-disabled-p)))
      (is (not (null gpu-disabled-p)))
      (is (null
           (llambda::call-with-gpu-setup-fallback
            (lambda () (error "simulated missing GPU bridge"))))))))

(test projection-benchmark-primitives
  (is (= 0.5f0
         (llambda::max-absolute-vector-difference
          #(1.0f0 -2.0f0 3.0f0)
          #(0.5f0 -2.25f0 3.0f0))))
  (signals error
    (llambda::max-absolute-vector-difference #(1.0f0) #(1.0f0 2.0f0)))
  (let* ((output (make-array 2
                             :element-type 'single-float
                             :initial-element 0.0f0))
         (baseline (make-array 2
                               :element-type 'single-float
                               :initial-contents '(2.0f0 4.0f0)))
         (result
           (llambda::benchmark-matrix-vector-function
            :cpu
            (lambda ()
              (setf (aref output 0) 2.0f0
                    (aref output 1) 4.0f0))
            output baseline 2 2 1 2)))
    (is (eq :cpu (getf result :backend)))
    (is (not (null (getf result :available-p))))
    (is (plusp (getf result :milliseconds-per-run)))
    (is (plusp (getf result :gflops)))
    (is (zerop (getf result :max-absolute-error)))
    (let ((text
            (with-output-to-string (stream)
              (llambda::print-projection-benchmark-results
               stream "test.weight" 2 2 1 2
               (list result
                     '(:backend :missing :available-p nil))))))
      (is (search "CPU" text))
      (is (search "MISSING" text))
      (is (search "unavailable" text))
      (is (= 1.0d0 (getf result :speedup-vs-cpu))))))

(test sampling-primitives
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon)))
    (let ((scaled (apply-temperature #(2.0f0 1.0f0 -2.0f0) 0.5f0)))
      (is (approx= 4.0f0 (aref scaled 0)))
      (is (approx= 2.0f0 (aref scaled 1)))
      (is (approx= -4.0f0 (aref scaled 2))))
    (let ((logits (make-array 4
                              :element-type 'single-float
                              :initial-contents '(2.0f0 -3.0f0 4.0f0 1.0f0))))
      (is (eq logits (apply-repetition-penalty logits '(2 1 2 1) 1.25f0)))
      (is (approx= 2.0f0 (aref logits 0)))
      (is (approx= -3.75f0 (aref logits 1)))
      (is (approx= 3.2f0 (aref logits 2)))
      (is (approx= 1.0f0 (aref logits 3))))
    (let ((logits (make-array 5
                              :element-type 'single-float
                              :initial-contents '(0.5f0 3.0f0 2.0f0 1.0f0 2.0f0))))
      (is (eq logits (apply-top-k logits 2)))
      (is (approx= -1.0f30 (aref logits 0)))
      (is (approx= 3.0f0 (aref logits 1)))
      (is (approx= 2.0f0 (aref logits 2)))
      (is (approx= -1.0f30 (aref logits 3)))
      (is (approx= 2.0f0 (aref logits 4))))
    (let ((logits (make-array 4
                              :element-type 'single-float
                              :initial-contents '(3.0f0 2.0f0 1.0f0 -1.0f30))))
      (is (eq logits (apply-top-p logits 0.60f0 1.0f0)))
      (is (approx= 3.0f0 (aref logits 0)))
      (is (approx= -1.0f30 (aref logits 1)))
      (is (approx= -1.0f30 (aref logits 2)))
      (is (approx= -1.0f30 (aref logits 3))))
    (let ((logits #(2.0f0 1.95f0 0.0f0)))
      (is (= 0 (sample-token-id-from-logits logits
                                            :top-k 0
                                            :top-p 1.0f0
                                            :temperature 1.0f0
                                            :random-value 0.45f0)))
      (let ((penalized-logits #(2.0f0 1.95f0 0.0f0)))
        (is (= 1 (sample-token-id-from-logits penalized-logits
                                              :history '(0)
                                              :repetition-penalty 1.15f0
                                              :top-k 0
                                              :top-p 1.0f0
                                              :temperature 1.0f0
                                              :random-value 0.45f0)))))
    (let ((top-k-logits #(3.0f0 2.9f0 0.1f0)))
      (is (= 1 (sample-token-id-from-logits top-k-logits
                                            :top-k 2
                                            :top-p 1.0f0
                                            :temperature 1.0f0
                                            :random-value 0.9f0))))
    (labels ((make-default-top-k-logits ()
               (make-array 50
                           :element-type 'single-float
                           :initial-contents
                           (loop for value from 50 downto 1
                                 collect (coerce value 'single-float)))))
      (is (= (sample-token-id-from-logits
              (make-default-top-k-logits)
              :top-k nil
              :top-p 1.0f0
              :temperature 1.0f0
              :random-value 0.9f0)
             (sample-token-id-from-logits
              (make-default-top-k-logits)
              :top-k 40
              :top-p 1.0f0
              :temperature 1.0f0
              :random-value 0.9f0))))
    (multiple-value-bind (token-ids text logits)
        (generate-token-loop nil
                             #(1.0f0 0.0f0)
                             (lambda (&rest arguments)
                               (declare (ignore arguments))
                               (error "Step function should not run."))
                             (make-hash-table)
                             :top-k nil
                             :max-tokens 0
                             :stream (make-broadcast-stream))
      (is (null token-ids))
      (is (string= "" text))
      (is (equalp #(1.0f0 0.0f0) logits)))
    (let ((top-p-logits #(3.0f0 2.0f0 1.0f0)))
      (is (= 0 (sample-token-id-from-logits top-p-logits
                                            :top-k 0
                                            :top-p 0.60f0
                                            :temperature 1.0f0
                                            :random-value 0.95f0))))
    (is (= (sample-token-id-from-logits
            #(3.0f0 2.0f0 1.0f0)
            :top-k 0
            :top-p nil
            :temperature 1.0f0
            :random-value 0.9f0)
           (sample-token-id-from-logits
            #(3.0f0 2.0f0 1.0f0)
            :top-k 0
            :top-p 0.95f0
            :temperature 1.0f0
            :random-value 0.9f0)))
    (let ((probs (softmax #(2.0f0 1.0f0 0.0f0))))
      (is (approx= 1.0f0 (loop for p across probs sum p)))
      (is (> (aref probs 0) (aref probs 1) (aref probs 2))))
    (is (= 0 (sample-from-probabilities #(0.7f0 0.2f0 0.1f0)
                                        :random-value 0.1f0)))
    (is (= 1 (sample-from-probabilities #(0.7f0 0.2f0 0.1f0)
                                        :random-value 0.75f0)))
    (is (= 2 (sample-from-probabilities #(0.7f0 0.2f0 0.1f0)
                                        :random-value 0.95f0)))
    (is (= 0 (sample-token-id-from-logits #(3.0f0 1.0f0 0.0f0)
                                          :top-p 1.0f0
                                          :temperature 1.0f0
                                          :random-value 0.1f0)))
    (is (= 1 (sample-token-id-from-logits #(3.0f0 1.0f0 0.0f0)
                                          :top-p 1.0f0
                                          :temperature 1.0f0
                                          :random-value 0.9f0)))))

(test call-with-file
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-test-~d"
                                                  (get-universal-time))
                                    :type "txt")
                     (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file (stream temp-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-line "llambda" stream))
          (is (eq :first
                  (call-with-file temp-path
                                  (lambda (handle)
                                    (declare (ignore handle))
                                    :first)
                                  :share-mode 0)))
          (is (eq :second
                  (call-with-file temp-path
                                  (lambda (handle)
                                    (declare (ignore handle))
                                    :second)
                                  :share-mode 0))))
      (when (probe-file temp-path)
        (delete-file temp-path)))))

(test with-file-handle
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-macro-test-~d"
                                                   (get-universal-time))
                                     :type "txt")
                     (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file (stream temp-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-line "llambda" stream))
          (is (eq :macro-first
                  (with-file-handle (handle temp-path)
                    (declare (ignore handle))
                    :macro-first)))
          (is (eq :macro-second
                  (with-file-handle (handle temp-path)
                    (declare (ignore handle))
                    :macro-second))))
      (when (probe-file temp-path)
        (delete-file temp-path)))))

(test call-with-mapped-file
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-map-test-~d"
                                                  (get-universal-time))
                                    :type "txt")
                     (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file (stream temp-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create
                                  :element-type '(unsigned-byte 8))
            (write-byte (char-code #\l) stream)
            (write-byte (char-code #\l) stream))
          (is (= (char-code #\l)
                 (call-with-file temp-path
                                 (lambda (handle)
                                   (call-with-mapped-file
                                    handle
                                    (lambda (mapping)
                                      (cffi:mem-aref mapping :unsigned-char 0))))
                                 :share-mode 0)))
          (is (= (char-code #\l)
                 (call-with-file temp-path
                                 (lambda (handle)
                                   (call-with-mapped-file
                                    handle
                                    (lambda (mapping)
                                      (cffi:mem-aref mapping :unsigned-char 1))))
                                 :share-mode 0)))
          (call-with-file
           temp-path
           (lambda (handle)
             (cffi:with-foreign-string
                 (mapping-name
                  (format nil "llambda-map-test-~d" (get-universal-time))
                  :encoding :utf-16le)
               (call-with-mapped-file
                handle
                (lambda (mapping)
                  (declare (ignore mapping))
                  (signals error
                    (call-with-mapped-file
                     handle
                     (lambda (duplicate-mapping)
                       (declare (ignore duplicate-mapping)))
                     :name mapping-name)))
                :name mapping-name)))
           :share-mode 0))
      (when (probe-file temp-path)
        (delete-file temp-path)))))

(test with-mapped-file
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-map-macro-test-~d"
                                                  (get-universal-time))
                                    :type "txt")
                     (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file (stream temp-path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create
                                  :element-type '(unsigned-byte 8))
            (write-byte (char-code #\a) stream)
            (write-byte (char-code #\b) stream))
          (is (= (char-code #\a)
                 (call-with-file temp-path
                                 (lambda (handle)
                                   (with-mapped-file (mapping handle)
                                     (cffi:mem-aref mapping :unsigned-char 0)))
                                 :share-mode 0)))
          (is (= (char-code #\b)
                 (call-with-file temp-path
                                 (lambda (handle)
                                   (with-mapped-file (mapping handle)
                                     (cffi:mem-aref mapping :unsigned-char 1)))
                                 :share-mode 0))))
      (when (probe-file temp-path)
        (delete-file temp-path)))))

(test read-gguf-header
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-gguf-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory))))
    (flet ((write-u32-le (stream value)
             (loop for index from 0 below 4
                   do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
           (write-u64-le (stream value)
             (loop for index from 0 below 8
                   do (write-byte (ldb (byte 8 (* 8 index)) value) stream))))
      (unwind-protect
          (progn
            (with-open-file (stream temp-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 17)
              (write-u64-le stream 9))
            (is (equal '(:magic "GGUF"
                         :version 3
                         :tensor-count 17
                         :metadata-kv-count 9
                         :header-size 24)
                       (call-with-file temp-path
                                       (lambda (handle)
                                         (with-mapped-file (mapping handle)
                                           (read-gguf-header mapping)))
                                       :share-mode 0))))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(test malformed-gguf-input-is-bounded
  (labels ((write-u32-le (stream value)
             (loop for index from 0 below 4
                   do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
           (write-u64-le (stream value)
             (loop for index from 0 below 8
                   do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
           (write-header (stream tensor-count metadata-count)
             (map nil
                  (lambda (character)
                    (write-byte (char-code character) stream))
                  "GGUF")
             (write-u32-le stream 3)
             (write-u64-le stream tensor-count)
             (write-u64-le stream metadata-count))
           (write-string-field (stream value)
             (let ((octets
                     #+sbcl
                     (sb-ext:string-to-octets value :external-format :utf-8)
                     #-sbcl
                     (map '(vector (unsigned-byte 8)) #'char-code value)))
               (write-u64-le stream (length octets))
               (write-sequence octets stream)))
           (fixture-error (suffix writer reader)
             (let ((path
                     (merge-pathnames
                      (make-pathname
                       :name (format nil "llambda-malformed-gguf-~a-~d"
                                     suffix
                                     (get-universal-time))
                       :type "gguf")
                      (uiop:temporary-directory))))
               (unwind-protect
                   (progn
                     (with-open-file
                         (stream path
                                 :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create
                                 :element-type '(unsigned-byte 8))
                       (funcall writer stream))
                     (handler-case
                         (call-with-file
                          path
                          (lambda (handle)
                            (with-mapped-file (mapping handle)
                              (funcall reader mapping)))
                          :share-mode 0)
                       (error (condition)
                         (princ-to-string condition))))
                 (when (probe-file path)
                   (delete-file path))))))
    (is (search
         "exceeds mapped file length"
         (fixture-error
          "header"
          (lambda (stream)
            (map nil
                 (lambda (character)
                   (write-byte (char-code character) stream))
                 "GGUF"))
          #'read-gguf-header)))
    (is (search
         "exceeds mapped file length"
         (fixture-error
          "metadata-string"
          (lambda (stream)
            (write-header stream 0 1)
            (write-u64-le stream 1024)
            (loop repeat 5 do (write-byte 0 stream)))
          #'read-gguf-kv-pairs)))
    (is (search
         "invalid dimension count"
         (fixture-error
          "dimensions"
          (lambda (stream)
            (write-header stream 1 0)
            (write-string-field stream "x")
            (write-u32-le stream 5)
            (loop repeat 20 do (write-byte 0 stream)))
          #'read-gguf-tensor-infos)))
    (is (search
         "exceeds mapped file length"
         (fixture-error
          "tensor-data"
          (lambda (stream)
            (write-header stream 1 0)
            (write-string-field stream "x")
            (write-u32-le stream 1)
            (write-u64-le stream 1)
            (write-u32-le stream 0)
            (write-u64-le stream 0)
            (loop until (zerop (mod (file-position stream) 32))
                  do (write-byte 0 stream)))
          #'read-gguf-tensor-infos)))))

(test read-gguf-kv-pairs
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-gguf-kv-test-~d"
                                                 (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory))))
    (labels ((write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-f32-le (stream value)
               #+sbcl
               (write-u32-le stream (sb-kernel::single-float-bits value))
               #-sbcl
               (error "TEST-GGUF-FILE-RESPONSE float fixture writer currently requires SBCL."))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream))))
      (unwind-protect
          (progn
            (with-open-file (stream temp-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 0)
              (write-u64-le stream 4)

              (write-string-field stream "general.architecture")
              (write-u32-le stream 8)
              (write-string-field stream "llama")

              (write-string-field stream "llama.block_count")
              (write-u32-le stream 4)
              (write-u32-le stream 32)

              (write-string-field stream "general.add_bos_token")
              (write-u32-le stream 7)
              (write-byte 1 stream)

              (write-string-field stream "test.array")
              (write-u32-le stream 9)
              (write-u32-le stream 4)
              (write-u64-le stream 2)
              (write-u32-le stream 7)
              (write-u32-le stream 8))
            (is (equal '(("general.architecture" . "llama")
                         ("llama.block_count" . 32)
                         ("general.add_bos_token" . t)
                         ("test.array" 7 8))
                       (call-with-file temp-path
                                       (lambda (handle)
                                        (with-mapped-file (mapping handle)
                                          (read-gguf-kv-pairs mapping)))
                                       :share-mode 0))))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(test print-gguf-file
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-gguf-print-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory))))
    (labels ((write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-f32-le (stream value)
               #+sbcl
               (write-u32-le stream (sb-kernel::single-float-bits value))
               #-sbcl
               (error "TEST-GGUF-FILE-RESPONSE float fixture writer currently requires SBCL."))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream))))
      (unwind-protect
          (progn
            (with-open-file (stream temp-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 17)
              (write-u64-le stream 3)

              (write-string-field stream "general.architecture")
              (write-u32-le stream 8)
              (write-string-field stream "llama")

              (write-string-field stream "llama.block_count")
              (write-u32-le stream 4)
              (write-u32-le stream 32)

              (write-string-field stream "tokenizer.ggml.tokens")
              (write-u32-le stream 9)
              (write-u32-le stream 8)
              (write-u64-le stream 2)
              (write-string-field stream "<s>")
              (write-string-field stream "</s>"))
            (let ((output (with-output-to-string (stream)
                            (print-gguf-file temp-path stream))))
              (is (search "GGUF file:" output))
              (is (search "Magic: GGUF" output))
              (is (search "Version: 3" output))
              (is (search "Tensor count: 17" output))
              (is (search "Metadata KV count: 3" output))
              (is (search "general.architecture: \"llama\"" output))
              (is (search "llama.block_count: 32" output))
              (is (search "tokenizer.ggml.tokens: <array of strings>" output))))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(test print-gguf-floating-point-tables
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-gguf-fp-print-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory))))
    (labels ((write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream)))
             (write-padding-to-alignment (stream alignment)
               (let* ((position (file-position stream))
                      (padding (mod (- alignment (mod position alignment))
                                    alignment)))
                 (loop repeat padding
                       do (write-byte 0 stream)))))
      (unwind-protect
          (progn
            (with-open-file (stream temp-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 3) ; 3 tensors
              (write-u64-le stream 1) ; 1 metadata KV

              ;; general.alignment
              (write-string-field stream "general.alignment")
              (write-u32-le stream 4)
              (write-u32-le stream 32)

              ;; Tensor 1: tensor.f32 (F32 = 0)
              (write-string-field stream "tensor.f32")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 0) ; type f32
              (write-u64-le stream 0) ; offset 0

              ;; Tensor 2: tensor.f16 (F16 = 1)
              (write-string-field stream "tensor.f16")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 1) ; type f16
              (write-u64-le stream 16) ; offset 16

              ;; Tensor 3: tensor.q4 (Q4_K = 12) - should be ignored by the FP-only printer!
              (write-string-field stream "tensor.q4")
              (write-u32-le stream 1)
              (write-u64-le stream 256) ; 256 elements
              (write-u32-le stream 12) ; type q4_k
              (write-u64-le stream 24) ; offset 24

              (write-padding-to-alignment stream 32)
              ;; data bytes
              (loop repeat 256 do (write-byte 0 stream)))
            
            (let ((output (with-output-to-string (stream)
                            (print-gguf-floating-point-tables temp-path stream))))
              ;; Check that it prints details for f32 and f16 tensors
              (is (search "tensor.f32" output))
              (is (search "tensor.f16" output))
              ;; Check that it prints Offset and Size in hexadecimal
              (is (search "Offset: #x" output))
              (is (search "Size:" output))
              ;; Check that it also prints the q4 tensor because we expanded the printer to all tensors
              (is (search "tensor.q4" output))))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(test read-gguf-tensor-infos-and-load-tensors
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon)))
    (let* ((temp-path (merge-pathnames
                       (make-pathname :name (format nil "llambda-gguf-tensors-test-~d"
                                                    (get-universal-time))
                                      :type "gguf")
                       (uiop:temporary-directory))))
      (labels ((write-u16-le (stream value)
                 (loop for index from 0 below 2
                       do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
               (write-u32-le (stream value)
                 (loop for index from 0 below 4
                       do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
               (write-u64-le (stream value)
                 (loop for index from 0 below 8
                       do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
               (write-f32-le (stream value)
                 #+sbcl
                 (write-u32-le stream (sb-kernel::single-float-bits value))
                 #-sbcl
                 (error "READ-GGUF-TENSOR-INFOS-AND-LOAD-TENSORS currently requires SBCL."))
               (write-string-field (stream value)
                 (let ((octets
                         #+sbcl
                         (sb-ext:string-to-octets value :external-format :utf-8)
                         #-sbcl
                         (map '(vector (unsigned-byte 8)) #'char-code value)))
                   (write-u64-le stream (length octets))
                   (write-sequence octets stream)))
               (write-padding-to-alignment (stream alignment)
                 (let* ((position (file-position stream))
                        (padding (mod (- alignment (mod position alignment))
                                      alignment)))
                   (loop repeat padding
                         do (write-byte 0 stream)))))
        (unwind-protect
            (progn
              (with-open-file (stream temp-path
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create
                                      :element-type '(unsigned-byte 8))
                (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
                (write-u32-le stream 3)
                (write-u64-le stream 2)
                (write-u64-le stream 1)

                (write-string-field stream "general.alignment")
                (write-u32-le stream 4)
                (write-u32-le stream 32)

                (write-string-field stream "tensor.f32")
                (write-u32-le stream 2)
                (write-u64-le stream 2)
                (write-u64-le stream 2)
                (write-u32-le stream 0)
                (write-u64-le stream 0)

                (write-string-field stream "tensor.f16")
                (write-u32-le stream 1)
                (write-u64-le stream 2)
                (write-u32-le stream 1)
                (write-u64-le stream 16)

                (write-padding-to-alignment stream 32)
                (dolist (value '(1.0f0 2.0f0 3.5f0 -4.0f0))
                  (write-f32-le stream value))
                (write-u16-le stream #x3C00)
                (write-u16-le stream #xC000))
              (call-with-file temp-path
                              (lambda (handle)
                                (with-mapped-file (mapping handle)
                                  (let* ((tensor-infos (read-gguf-tensor-infos mapping))
                                         (f32-info (find-gguf-tensor-info tensor-infos "tensor.f32"))
                                         (f16-info (find-gguf-tensor-info tensor-infos "tensor.f16")))
                                    (is (= 2 (length tensor-infos)))
                                    (is (equal '(2 2) (getf f32-info :dimensions)))
                                    (is (eq :f32 (getf f32-info :type-name)))
                                    (is (= 4 (getf f32-info :element-count)))
                                    (is (= 16 (getf f32-info :byte-size)))
                                    (is (zerop (mod (getf f32-info :data-offset) 32)))
                                    (is (= 16 (- (getf f16-info :data-offset)
                                                 (getf f32-info :data-offset))))
                                    (multiple-value-bind (f32-tensor resolved-info)
                                        (load-gguf-tensor-by-name mapping "tensor.f32" tensor-infos)
                                      (is (equal f32-info resolved-info))
                                      (is (= 4 (length f32-tensor)))
                                      (is (approx= 1.0f0 (aref f32-tensor 0)))
                                      (is (approx= 2.0f0 (aref f32-tensor 1)))
                                      (is (approx= 3.5f0 (aref f32-tensor 2)))
                                      (is (approx= -4.0f0 (aref f32-tensor 3))))
                                    (let ((f16-tensor (load-gguf-tensor mapping f16-info)))
                                      (is (= 2 (length f16-tensor)))
                                      (is (approx= 1.0f0 (aref f16-tensor 0)))
                                      (is (approx= -2.0f0 (aref f16-tensor 1)))))))
                              :share-mode 0))
          (when (probe-file temp-path)
            (delete-file temp-path)))))))

(test copy-tensors-to-aligned-temp-file-test
  (let* ((temp-gguf (merge-pathnames
                     (make-pathname :name (format nil "llambda-copy-gguf-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory)))
         (temp-backed (merge-pathnames
                       (make-pathname :name (format nil "llambda-copy-backed-test-~d"
                                                    (get-universal-time))
                                      :type "bin")
                       (uiop:temporary-directory))))
    (labels ((write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-f32-le (stream value)
               #+sbcl
               (write-u32-le stream (sb-kernel::single-float-bits value))
               #-sbcl
               (error "READ-GGUF-TENSOR-INFOS-AND-LOAD-TENSORS currently requires SBCL."))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream)))
             (write-padding-to-alignment (stream alignment)
               (let* ((position (file-position stream))
                      (padding (mod (- alignment (mod position alignment))
                                    alignment)))
                 (loop repeat padding
                       do (write-byte 0 stream)))))
      (unwind-protect
          (progn
            ;; Create a mock GGUF file with 2 tensors
            (with-open-file (stream temp-gguf
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 2) ; 2 tensors
              (write-u64-le stream 1) ; 1 metadata KV

              ;; general.alignment
              (write-string-field stream "general.alignment")
              (write-u32-le stream 4)
              (write-u32-le stream 32)

              ;; Tensor 1: tensor.f32 (F32 = 0)
              (write-string-field stream "tensor.f32")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 0) ; type f32
              (write-u64-le stream 0) ; offset 0

              ;; Tensor 2: tensor.f16 (F16 = 1)
              (write-string-field stream "tensor.f16")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 1) ; type f16
              (write-u64-le stream 16) ; offset 16

              (write-padding-to-alignment stream 32)
              ;; data bytes: 4 single-floats = 16 bytes for F32
              (dolist (val '(1.0f0 2.0f0 3.0f0 4.0f0))
                (write-f32-le stream val))
              ;; 4 half-floats = 8 bytes for F16
              (write-u32-le stream #x3C003C00)
              (write-u32-le stream #x3C003C00))

            ;; Copy tensors to the aligned temporary file
            (let ((total-size (copy-tensors-to-aligned-temp-file temp-gguf temp-backed)))
              ;; Verify total size is a multiple of 64KB (65536)
              (is (plusp total-size))
              (is (zerop (mod total-size 65536)))
              ;; Open and map the resulting temporary file to verify contents
              (call-with-file temp-backed
                              (lambda (handle)
                                (call-with-mapped-file
                                 handle
                                 (lambda (mapping)
                                   ;; Tensor 1 is at offset 0 of temp-backed
                                   ;; Header of Tensor 1 (F32 -> simple-array single-float (*)):
                                   ;; Word 0: Widetag should be #xD1
                                   ;; Word 1: Length (as fixnum) should be 4 * 2 = 8
                                   (is (= #xD1 (cffi:mem-ref mapping :uint64 0)))
                                   (is (= 8 (cffi:mem-ref mapping :uint64 8)))
                                   ;; Copied f32 tensor starts at offset 16
                                   (is (= #x3F800000 (cffi:mem-ref mapping :uint32 16))) ; 1.0f0
                                   (is (= #x40000000 (cffi:mem-ref mapping :uint32 20))) ; 2.0f0

                                   ;; Tensor 2 is at offset 65536 of temp-backed
                                   (let ((tensor2-ptr (cffi:inc-pointer mapping 65536)))
                                     ;; Header of Tensor 2 (F16 -> simple-array (unsigned-byte 8) (*)):
                                     ;; Word 0: Widetag should be #x9D
                                     ;; Word 1: Length (byte-size) as fixnum should be 8 * 2 = 16
                                     (is (= #x9D (cffi:mem-ref tensor2-ptr :uint64 0)))
                                     (is (= 16 (cffi:mem-ref tensor2-ptr :uint64 8)))
                                     ;; Copied f16 tensor starts at offset 16
                                     (is (= #x3C00 (cffi:mem-ref tensor2-ptr :uint16 16)))
                                     (is (= #x3C00 (cffi:mem-ref tensor2-ptr :uint16 18))))))
                                 :protect 4 ; PAGE_READWRITE
                                 :desired-access 2)) ; FILE_MAP_WRITE
              :ok))
        (progn
          (when (probe-file temp-gguf)
            (delete-file temp-gguf))
          (when (probe-file temp-backed)
            (delete-file temp-backed)))))))

(test map-gguf-tensors-to-aligned-arrays-test
  (let* ((temp-gguf (merge-pathnames
                     (make-pathname :name (format nil "llambda-map-gguf-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory)))
         (temp-backed (merge-pathnames
                       (make-pathname :name (format nil "llambda-map-backed-test-~d"
                                                    (get-universal-time))
                                      :type "bin")
                       (uiop:temporary-directory))))
    (labels ((write-u16-le (stream value)
               (loop for index from 0 below 2
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-f32-le (stream value)
               #+sbcl
               (write-u32-le stream (sb-kernel::single-float-bits value))
               #-sbcl
               (error "READ-GGUF-TENSOR-INFOS-AND-LOAD-TENSORS currently requires SBCL."))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream)))
             (write-padding-to-alignment (stream alignment)
               (let* ((position (file-position stream))
                      (padding (mod (- alignment (mod position alignment))
                                    alignment)))
                 (loop repeat padding
                       do (write-byte 0 stream)))))
      (unwind-protect
          (progn
            ;; Create a mock GGUF file with 2 tensors
            (with-open-file (stream temp-gguf
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 2) ; 2 tensors
              (write-u64-le stream 1) ; 1 metadata KV

              ;; general.alignment
              (write-string-field stream "general.alignment")
              (write-u32-le stream 4)
              (write-u32-le stream 32)

              ;; Tensor 1: tensor.f32 (F32 = 0)
              (write-string-field stream "tensor.f32")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 0) ; type f32
              (write-u64-le stream 0) ; offset 0

              ;; Tensor 2: tensor.f16 (F16 = 1)
              (write-string-field stream "tensor.f16")
              (write-u32-le stream 1)
              (write-u64-le stream 4) ; 4 elements
              (write-u32-le stream 1) ; type f16
              (write-u64-le stream 16) ; offset 16

              (write-padding-to-alignment stream 32)
              ;; data bytes: 4 single-floats = 16 bytes for F32
              (dolist (val '(1.5f0 2.5f0 3.5f0 4.5f0))
                (write-f32-le stream val))
              ;; 4 half-floats = 8 bytes for F16
              (write-u16-le stream #x3C00) ; 1.0f0
              (write-u16-le stream #xC000) ; -2.0f0
              (write-u16-le stream #x3C00)
              (write-u16-le stream #x3C00))

            (let ((mapping nil)
                  (tensors nil))
              (with-aligned-tensor-mapping
                  (active-mapping temp-gguf temp-backed)
                (setf mapping active-mapping
                      tensors
                      (aligned-tensor-mapping-tensors active-mapping))
                (is (aligned-tensor-mapping-p active-mapping))
                (is (not (aligned-tensor-mapping-closed-p active-mapping)))
                (is (= 2 (length tensors)))

                ;; Verify Tensor 1 (F32)
                (let ((tensor1 (first tensors)))
                  (is (aligned-tensor-view-p tensor1))
                  (is (eq :single-float
                          (aligned-tensor-view-element-type tensor1)))
                  (is (= 4 (aligned-tensor-view-length tensor1)))
                  (is (= 1.5f0 (aligned-tensor-view-ref tensor1 0)))
                  (is (= 2.5f0 (aligned-tensor-view-ref tensor1 1)))
                  (is (= 3.5f0 (aligned-tensor-view-ref tensor1 2)))
                  (is (= 4.5f0 (aligned-tensor-view-ref tensor1 3)))
                  (is (= 41.0f0
                         (aligned-tensor-view-dot-product
                          tensor1 tensor1))))

                ;; Verify Tensor 2 (F16 -> byte vector)
                (let ((tensor2 (second tensors)))
                  (is (aligned-tensor-view-p tensor2))
                  (is (eq :unsigned-byte-8
                          (aligned-tensor-view-element-type tensor2)))
                  (is (= 8 (aligned-tensor-view-length tensor2)))
                  (is (= #x00 (aligned-tensor-view-ref tensor2 0)))
                  (is (= #x3C (aligned-tensor-view-ref tensor2 1)))
                  (is (= #x00 (aligned-tensor-view-ref tensor2 2)))
                  (is (= #xC0 (aligned-tensor-view-ref tensor2 3)))))
              (is (aligned-tensor-mapping-closed-p mapping))
              (is (null (aligned-tensor-mapping-tensors mapping)))
              (dolist (tensor tensors)
                (signals error
                  (aligned-tensor-view-ref tensor 0)))
              (is (eq mapping (close-aligned-tensor-mapping mapping)))
              (is (eq mapping (close-aligned-tensor-mapping mapping))))
            (let ((failed-mapping nil)
                  (condition nil))
              (handler-case
                  (call-with-aligned-tensor-mapping
                   temp-gguf
                   temp-backed
                   (lambda (mapping)
                     (setf failed-mapping mapping)
                     (error "primary receiver failure")))
                (error (caught-condition)
                  (setf condition caught-condition)))
              (is (search "primary receiver failure"
                          (princ-to-string condition)))
              (is (aligned-tensor-mapping-closed-p failed-mapping)))
            (let ((escaped-mapping nil))
              (is (eq :escaped
                      (catch 'escape-mapping
                        (call-with-aligned-tensor-mapping
                         temp-gguf
                         temp-backed
                         (lambda (mapping)
                           (setf escaped-mapping mapping)
                           (throw 'escape-mapping :escaped))))))
              (is (aligned-tensor-mapping-closed-p escaped-mapping)))
            :ok)
        (progn
          (when (probe-file temp-gguf)
            (delete-file temp-gguf))
          (when (probe-file temp-backed)
            (delete-file temp-backed)))))))

(test dot-product-with-f16-tensor-row
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
          (< (abs (- left right)) epsilon))
         (sfv (&rest values)
          (make-array (length values)
                      :element-type 'single-float
                      :initial-contents values)))
    (let ((tensor-info '(:name "tensor.f16.matrix"
                        :dimensions (3 2)
                        :type-tag 1
                        :data-offset 0)))
      (cffi:with-foreign-object (matrix-bytes :unsigned-char 12)
        (dolist (byte/index '((#x00 0) (#x3C 1)
                             (#x00 2) (#x40 3)
                             (#x00 4) (#x42 5)
                             (#x00 6) (#xC0 7)
                             (#x00 8) (#x44 9)
                             (#x00 10) (#x45 11)))
          (setf (cffi:mem-aref matrix-bytes :unsigned-char (second byte/index))
               (first byte/index)))
        (is (approx= 14.0f0
                    (llambda::dot-product-with-tensor-row matrix-bytes
                                                          tensor-info
                                                          0
                                                          (sfv 1.0f0 2.0f0 3.0f0))))
        (is (approx= 14.0f0
                    (llambda::dot-product-with-tensor-row matrix-bytes
                                                          tensor-info
                                                          1
                                                          (sfv -1.0f0 0.5f0 2.0f0))))))))

(test dot-product-with-q4-k-tensor-row
  (flet ((approx= (left right &optional (epsilon 1.0e-4))
           (< (abs (- left right)) epsilon)))
    (let ((tensor-info '(:name "tensor.q4-k.matrix"
                        :dimensions (256 1)
                        :type-tag 12
                        :data-offset 0))
          (vector (make-array 256
                              :element-type 'single-float
                              :initial-contents
                              (loop for index below 256
                                    collect (coerce (/ (- (mod index 11) 5) 3.0)
                                                    'single-float)))))
      (cffi:with-foreign-object (block :unsigned-char 144)
        (dotimes (index 144)
          (setf (cffi:mem-aref block :unsigned-char index) 0))
        (setf (cffi:mem-aref block :unsigned-char 0) #x00
              (cffi:mem-aref block :unsigned-char 1) #x3C
              (cffi:mem-aref block :unsigned-char 2) #x00
              (cffi:mem-aref block :unsigned-char 3) #x3C)
        (dotimes (index 4)
          (setf (cffi:mem-aref block :unsigned-char (+ 4 index)) 2
                (cffi:mem-aref block :unsigned-char (+ 8 index)) 1
                (cffi:mem-aref block :unsigned-char (+ 12 index)) #x12))
        (dotimes (index 128)
          (setf (cffi:mem-aref block :unsigned-char (+ 16 index)) #x76))
        (let ((expected (llambda::dot-product (dequantize-q4-k-m block 256) vector)))
          (is (approx= expected
                       (llambda::dot-product-with-tensor-row block
                                                             tensor-info
                                                             0
                                                             vector))))))))

(test dot-product-with-q6-k-tensor-row
  (flet ((approx= (left right &optional (epsilon 1.0e-4))
           (< (abs (- left right)) epsilon)))
    (let ((tensor-info '(:name "tensor.q6-k.matrix"
                        :dimensions (256 1)
                        :type-tag 14
                        :data-offset 0))
          (vector (make-array 256
                              :element-type 'single-float
                              :initial-contents
                              (loop for index below 256
                                    collect (coerce (/ (- (mod index 13) 6) 4.0)
                                                    'single-float)))))
      (cffi:with-foreign-object (block :unsigned-char 210)
        (dotimes (index 210)
          (setf (cffi:mem-aref block :unsigned-char index) 0))
        (dotimes (index 32)
          (setf (cffi:mem-aref block :unsigned-char index) #x31
                (cffi:mem-aref block :unsigned-char (+ 32 index)) #x42
                (cffi:mem-aref block :unsigned-char (+ 64 index)) #x31
                (cffi:mem-aref block :unsigned-char (+ 96 index)) #x42))
        (dotimes (index 64)
          (setf (cffi:mem-aref block :unsigned-char (+ 128 index)) #xAA))
        (dotimes (index 16)
          (setf (cffi:mem-aref block :unsigned-char (+ 192 index)) 2))
        (setf (cffi:mem-aref block :unsigned-char 208) #x00
              (cffi:mem-aref block :unsigned-char 209) #x3C)
        (let ((expected (llambda::dot-product (dequantize-q6-k block 256) vector)))
          (is (approx= expected
                       (llambda::dot-product-with-tensor-row block
                                                             tensor-info
                                                             0
                                                             vector))))))))

(test load-gguf-tensor-quantized
  (cffi:with-foreign-object (q4-block :unsigned-char 144)
    (dotimes (index 144)
      (setf (cffi:mem-aref q4-block :unsigned-char index) 0))
    (setf (cffi:mem-aref q4-block :unsigned-char 0) #x00
          (cffi:mem-aref q4-block :unsigned-char 1) #x3C
          (cffi:mem-aref q4-block :unsigned-char 2) #x00
          (cffi:mem-aref q4-block :unsigned-char 3) #x3C)
    (dotimes (index 4)
      (setf (cffi:mem-aref q4-block :unsigned-char (+ 4 index)) 2
            (cffi:mem-aref q4-block :unsigned-char (+ 8 index)) 1
            (cffi:mem-aref q4-block :unsigned-char (+ 12 index)) #x12))
    (dotimes (index 128)
      (setf (cffi:mem-aref q4-block :unsigned-char (+ 16 index)) #x76))
    (let ((result (load-gguf-tensor q4-block
                                    '(:name "tensor.q4"
                                      :type-tag 12
                                      :element-count 256
                                      :data-offset 0))))
      (is (= 256 (length result)))
      (is (= 11.0f0 (aref result 0)))
      (is (= 13.0f0 (aref result 32)))))
  (cffi:with-foreign-object (q6-block :unsigned-char 210)
    (dotimes (index 210)
      (setf (cffi:mem-aref q6-block :unsigned-char index) 0))
    (dotimes (index 32)
      (setf (cffi:mem-aref q6-block :unsigned-char index) #x31
            (cffi:mem-aref q6-block :unsigned-char (+ 32 index)) #x42
            (cffi:mem-aref q6-block :unsigned-char (+ 64 index)) #x31
            (cffi:mem-aref q6-block :unsigned-char (+ 96 index)) #x42))
    (dotimes (index 64)
      (setf (cffi:mem-aref q6-block :unsigned-char (+ 128 index)) #xAA))
    (dotimes (index 16)
      (setf (cffi:mem-aref q6-block :unsigned-char (+ 192 index)) 2))
    (setf (cffi:mem-aref q6-block :unsigned-char 208) #x00
          (cffi:mem-aref q6-block :unsigned-char 209) #x3C)
    (let ((result (load-gguf-tensor q6-block
                                    '(:name "tensor.q6"
                                      :type-tag 14
                                      :element-count 256
                                      :data-offset 0))))
      (is (= 256 (length result)))
      (is (= 2.0f0 (aref result 0)))
      (is (= 8.0f0 (aref result 96))))))

(test load-gguf-tensor-bf16
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon)))
    (cffi:with-foreign-object (bf16-block :unsigned-char 4)
      (setf (cffi:mem-aref bf16-block :unsigned-char 0) #x80
            (cffi:mem-aref bf16-block :unsigned-char 1) #x3F
            (cffi:mem-aref bf16-block :unsigned-char 2) #x00
            (cffi:mem-aref bf16-block :unsigned-char 3) #xC0)
      (let ((result (load-gguf-tensor bf16-block
                                      '(:name "tensor.bf16"
                                        :type-tag 30
                                        :element-count 2
                                        :data-offset 0))))
        (is (= 2 (length result)))
        (is (approx= 1.0f0 (aref result 0)))
        (is (approx= -2.0f0 (aref result 1)))))))

(test dequantize-q4-k-m
  (cffi:with-foreign-object (block :unsigned-char 144)
    (dotimes (index 144)
      (setf (cffi:mem-aref block :unsigned-char index) 0))
    ;; d = 1.0, dmin = 1.0 in fp16 little-endian.
    (setf (cffi:mem-aref block :unsigned-char 0) #x00
          (cffi:mem-aref block :unsigned-char 1) #x3C
          (cffi:mem-aref block :unsigned-char 2) #x00
          (cffi:mem-aref block :unsigned-char 3) #x3C)
    ;; Eight 6-bit scales = 2, eight 6-bit mins = 1.
    (dotimes (index 4)
      (setf (cffi:mem-aref block :unsigned-char (+ 4 index)) 2
            (cffi:mem-aref block :unsigned-char (+ 8 index)) 1
            (cffi:mem-aref block :unsigned-char (+ 12 index)) #x12))
    ;; Packed quants: low nibble = 6, high nibble = 7.
    (dotimes (index 128)
      (setf (cffi:mem-aref block :unsigned-char (+ 16 index)) #x76))
    (let ((result (dequantize-q4-k-m block 256)))
      (is (= 256 (length result)))
      (is (every (lambda (value)
                   (= 11.0f0 value))
                 (subseq result 0 32)))
      (is (every (lambda (value)
                   (= 13.0f0 value))
                 (subseq result 32 64)))
      (is (every (lambda (value)
                   (= 11.0f0 value))
                 (subseq result 192 224)))
      (is (every (lambda (value)
                   (= 13.0f0 value))
                 (subseq result 224 256))))))

(test dequantize-q6-k
  (cffi:with-foreign-object (block :unsigned-char 210)
    (dotimes (index 210)
      (setf (cffi:mem-aref block :unsigned-char index) 0))
    ;; ql (128 bytes): low/high nibbles for q1=33, q2=34, q3=35, q4=36.
    (dotimes (index 32)
      (setf (cffi:mem-aref block :unsigned-char index) #x31
            (cffi:mem-aref block :unsigned-char (+ 32 index)) #x42
            (cffi:mem-aref block :unsigned-char (+ 64 index)) #x31
            (cffi:mem-aref block :unsigned-char (+ 96 index)) #x42))
    ;; qh (64 bytes): upper 2 bits for each q packed into one byte.
    (dotimes (index 64)
      (setf (cffi:mem-aref block :unsigned-char (+ 128 index)) #xAA))
    ;; 16 signed scales, all equal to 2.
    (dotimes (index 16)
      (setf (cffi:mem-aref block :unsigned-char (+ 192 index)) 2))
    ;; d = 1.0 in fp16 little-endian at end of block.
    (setf (cffi:mem-aref block :unsigned-char 208) #x00
          (cffi:mem-aref block :unsigned-char 209) #x3C)
    (let ((result (dequantize-q6-k block 256)))
      (is (= 256 (length result)))
      (is (every (lambda (value) (= 2.0f0 value))
                 (subseq result 0 32)))
      (is (every (lambda (value) (= 4.0f0 value))
                 (subseq result 32 64)))
      (is (every (lambda (value) (= 6.0f0 value))
                 (subseq result 64 96)))
      (is (every (lambda (value) (= 8.0f0 value))
                 (subseq result 96 128)))
      (is (every (lambda (value) (= 2.0f0 value))
                 (subseq result 128 160)))
      (is (every (lambda (value) (= 8.0f0 value))
                 (subseq result 224 256))))))

(test detokenize-token-ids
  (let ((kv-pairs `(("tokenizer.ggml.tokens"
                     . ("<unk>"
                        ,(format nil "~cHello" (code-char #x2581))
                        ,(format nil "~cworld" (code-char #x2581))
                        "!")))))
    (is (string= " Hello" (detokenize-token-id kv-pairs 1)))
    (is (string= " Hello world!"
                 (detokenize-token-ids kv-pairs '(1 2 3))))
    (is (string= " Hello world!"
                 (with-output-to-string (stream)
                   (detokenize-token-ids kv-pairs '(1 2 3) stream))))))

(test tokenize-prompt
  (let ((kv-pairs `(("tokenizer.ggml.tokens"
                     . ("H" "e" "y" ,(string (code-char #x2581)) "V"
                        "He" "Hey" ,(format nil "~cV" (code-char #x2581))))
                    ("tokenizer.ggml.scores"
                     . (-10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                        0.1f0 0.9f0 0.8f0))
                    ("tokenizer.ggml.bos_token_id" . 99)
                    ("tokenizer.ggml.add_bos_token" . t))))
    (is (equal '(99 6 7)
               (tokenize-prompt kv-pairs "Hey V")))
    (is (equal '(6 7)
               (tokenize-prompt kv-pairs "Hey V" :add-bos nil)))))

(test tokenize-prompt-gemma4-bpe
  (let ((kv-pairs `(("tokenizer.ggml.model" . "gemma4")
                    ("tokenizer.ggml.tokens"
                     . ("<unk>"
                        ,(string (code-char #x2581))
                        "H" "e" "l" "o"
                        "He" "Hel" "Hell" "Hello"
                        ,(format nil "~cHello" (code-char #x2581))
                        "<0xF0>" "<0x9F>" "<0x98>" "<0x80>" "<|turn>"
                        ,(format nil "~c" #\Newline)
                        ,(format nil "~c~c" #\Newline #\Newline)))
                    ("tokenizer.ggml.token_type"
                     . (1 1 1 1 1 1
                        1 1 1 1 1
                        1 1 1 1 3
                        1 1))
                    ("tokenizer.ggml.merges"
                     . ("H e"
                        "He l"
                        "Hel l"
                        "Hell o"
                        "▁ Hello"))
                    ("tokenizer.ggml.bos_token_id" . 99)
                    ("tokenizer.ggml.add_bos_token" . nil))))
    (is (equal '(99 10)
               (tokenize-prompt kv-pairs " Hello" :add-bos t)))
    (is (equal '(10)
               (tokenize-prompt kv-pairs " Hello" :add-bos nil)))
    (is (equal '(15)
               (tokenize-prompt kv-pairs "<|turn>" :add-bos nil)))
    (is (equal '(17)
               (tokenize-prompt kv-pairs (format nil "~c~c" #\Newline #\Newline)
                                :add-bos nil)))
    (is (equal '(11 12 13 14)
               (tokenize-prompt kv-pairs "😀" :add-bos nil)))))

(test tokenize-prompt-llama-bpe
  (let ((kv-pairs
          `(("tokenizer.ggml.model" . "gpt2")
            ("tokenizer.ggml.pre" . "llama-bpe")
            ("tokenizer.ggml.tokens"
             . ("H" "e" "l" "o" "He" "Hel" "Hell" "Hello"
               ,(string (code-char #x0120))
               ,(format nil "~cw" (code-char #x0120))
               ,(format nil "~cwo" (code-char #x0120))
               ,(format nil "~cwor" (code-char #x0120))
               ,(format nil "~cworl" (code-char #x0120))
               ,(format nil "~cworld" (code-char #x0120))
               "<|begin_of_text|>" "<|eot_id|>"))
            ("tokenizer.ggml.token_type"
             . (1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3))
            ("tokenizer.ggml.merges"
             . ("H e" "He l" "Hel l" "Hell o"
               "Ġ w" "Ġw o" "Ġwo r" "Ġwor l" "Ġworl d"))
            ("tokenizer.ggml.bos_token_id" . 14))))
    (is (equal '(7 13)
               (tokenize-prompt kv-pairs "Hello world" :add-bos nil)))
    (is (equal '(14 7 15)
               (tokenize-prompt
               kv-pairs
               "<|begin_of_text|>Hello<|eot_id|>"
               :add-bos nil)))))

(test tokenize-prompt-llama-number-boundaries
  (let ((kv-pairs
          '(("tokenizer.ggml.model" . "gpt2")
            ("tokenizer.ggml.pre" . "llama-bpe")
            ("tokenizer.ggml.tokens"
             . ("1" "2" "3" "4" "5" "12" "123" "1234" "12345" "45"))
            ("tokenizer.ggml.token_type" . (1 1 1 1 1 1 1 1 1 1))
            ("tokenizer.ggml.merges"
             . ("1 2" "12 3" "123 4" "1234 5" "4 5")))))
    (is (equal '(6 9)
               (tokenize-prompt kv-pairs "12345" :add-bos nil)))))

(test tokenize-prompt-qwen2-number-boundaries
  (let ((kv-pairs
          '(("tokenizer.ggml.model" . "gpt2")
            ("tokenizer.ggml.pre" . "qwen2")
            ("tokenizer.ggml.tokens"
             . ("1" "2" "3" "4" "5" "12" "123" "1234" "12345"))
            ("tokenizer.ggml.token_type" . (1 1 1 1 1 1 1 1 1))
            ("tokenizer.ggml.merges"
             . ("1 2" "12 3" "123 4" "1234 5")))))
    (is (equal '(0 1 2 3 4)
               (tokenize-prompt kv-pairs "12345" :add-bos nil)))))

(test maybe-prepare-prompt-for-generation-llama
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gpt2")
                   ("tokenizer.ggml.pre" . "llama-bpe")
                   ("tokenizer.chat_template" . "dummy"))))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation kv-pairs "Hello" t)
      (is (search "<|begin_of_text|><|start_header_id|>user<|end_header_id|>"
                 prepared-prompt))
      (is (search "Hello<|eot_id|><|start_header_id|>assistant<|end_header_id|>"
                 prepared-prompt))
      (is (null effective-add-bos)))))

(test maybe-prepare-prompt-for-generation-qwen2
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gpt2")
                    ("tokenizer.ggml.pre" . "qwen2")
                    ("tokenizer.chat_template" . "dummy"))))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation kv-pairs "Hello" t)
      (is (search "<|im_start|>system" prepared-prompt))
      (is (search (format nil "<|im_start|>user~%Hello<|im_end|>")
                  prepared-prompt))
      (is (search "<|im_start|>assistant" prepared-prompt))
      (is (null effective-add-bos)))))

(test resolve-stop-token-ids-qwen2
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gpt2")
                    ("tokenizer.ggml.pre" . "qwen2")
                    ("tokenizer.ggml.tokens"
                     . ("text" "<|endoftext|>" "<|im_start|>" "<|im_end|>"))
                    ("tokenizer.ggml.token_type" . (1 3 3 3)))))
    (is (equal '(1 2 3)
               (llambda::resolve-stop-token-ids kv-pairs)))))

(test maybe-prepare-prompt-for-generation-gemma4
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gemma4")
                    ("tokenizer.chat_template" . "dummy"))))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation kv-pairs "Hello" t)
      (is (search "<bos><|turn>user" prepared-prompt))
      (is (search "Hello<turn|>" prepared-prompt))
      (is (search "<|turn>model" prepared-prompt))
      (is (null effective-add-bos)))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation
         kv-pairs
         "<bos><|turn>user
Hello<turn|>
<|turn>model
"
         t)
      (is (search "<bos><|turn>user" prepared-prompt))
      (is (search "Hello<turn|>" prepared-prompt))
      (is (search "<|turn>model" prepared-prompt))
      (is (eq t effective-add-bos))))
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gemma4")
                   ("tokenizer.chat_template" . "<|turn>system\nstuff<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"))))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation kv-pairs "Hello" t)
      (is (search "<bos><|turn>user" prepared-prompt))
      (is (search "Hello<turn|>" prepared-prompt))
      (is (search "<|turn>model" prepared-prompt))
      (is (null (search "<|channel>thought" prepared-prompt)))
      (is (null effective-add-bos)))
    (multiple-value-bind (prepared-prompt effective-add-bos)
        (llambda::maybe-prepare-prompt-for-generation kv-pairs
                                                     "Hello"
                                                     t
                                                     :use-thought-channel t)
      (is (search "<|channel>thought" prepared-prompt))
      (is (search "<channel|>" prepared-prompt))
      (is (null effective-add-bos)))))

(test resolve-stop-token-ids-gemma4
  (let ((kv-pairs '(("tokenizer.ggml.model" . "gemma4")
                    ("tokenizer.chat_template" . "dummy")
                    ("tokenizer.ggml.tokens" . ("<eos>" "<turn|>" "Hello"))
                    ("tokenizer.ggml.token_type" . (3 3 1)))))
    (is (equal '(0 1)
               (llambda::resolve-stop-token-ids kv-pairs 0)))))

(test generation-pipeline
  (let* ((kv-pairs `(("tokenizer.ggml.tokens"
                      . ("H" "i" ,(string (code-char #x2581))
                         "e" "l" "o" "," "h" "w" "a" "r" "y" "u" "?"
                         "Hello" " world" "!"
                         "<eos>"))
                     ("tokenizer.ggml.scores"
                      . (-10.0f0 -10.0f0 -10.0f0
                         -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                         -10.0f0 -10.0f0 -10.0f0 -10.0f0
                         0.8f0 0.7f0 0.6f0 -1.0f0))
                     ("tokenizer.ggml.bos_token_id" . 42)
                     ("tokenizer.ggml.add_bos_token" . t)))
         (calls '())
         (step-function (lambda (token-id position kv-cache)
                          (declare (ignore kv-cache))
                          (push (list token-id position) calls)
                          (case token-id
                            ((42) #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 -10.0f0))
                            ((0)  #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 -10.0f0))
                            ((1)  #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 10.0f0 0.0f0 -10.0f0))
                            ((15) #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 10.0f0 -10.0f0))
                            ((16) #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                    0.0f0 0.0f0 -10.0f0 10.0f0))
                            (otherwise #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                         0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                         0.0f0 0.0f0 0.0f0 4.0f0)))))
         (kv-cache (make-hash-table))
         (callback-text '()))
    (let ((prompt-logits (evaluate-prompt '(42 0 1) step-function kv-cache)))
      (is (equal '((1 2) (0 1) (42 0)) calls))
      (is (= 10.0f0 (aref prompt-logits 15))))
    (setf calls '())
    (multiple-value-bind (generated-ids generated-text last-logits)
        (generate-token-loop kv-pairs
                             #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                               0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                               0.0f0 10.0f0 0.0f0 -10.0f0)
                             step-function
                             kv-cache
                             :eos-token-id 17
                             :start-position 2
                             :temperature 1.0f0
                             :callback (lambda (text)
                                         (push text callback-text))
                             :random-values '(0.1f0 0.1f0 0.1f0 0.1f0))
      (is (equal '(15 16) generated-ids))
      (is (string= " world!" generated-text))
      (is (equal '(" world" "!") (nreverse callback-text)))
      (is (= 10.0f0 (aref last-logits 17)))
      (is (equal '((16 3) (15 2)) calls)))
    (setf calls '())
    (multiple-value-bind (generated-ids generated-text last-logits)
        (generate-from-prompt kv-pairs
                              "Hi"
                              step-function
                              kv-cache
                              :eos-token-id 17
                              :temperature 1.0f0
                              :random-values '(0.1f0 0.1f0 0.1f0 0.1f0))
      (is (equal '(15 16) generated-ids))
      (is (string= " world!" generated-text))
      (is (= 10.0f0 (aref last-logits 17)))
      (is (equal '((16 4) (15 3) (1 2) (0 1) (42 0)) calls)))))

(test test-llm-response
  (let* ((kv-pairs `(("tokenizer.ggml.tokens"
                      . ("H" "e" "l" "o" "," ,(string (code-char #x2581))
                         "h" "w" "a" "r" "y" "u" "?"
                         "Hello" " world" "!"
                         "<eos>"))
                     ("tokenizer.ggml.scores"
                      . (-10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                         -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                         0.9f0 0.8f0 0.7f0 -1.0f0))
                     ("tokenizer.ggml.bos_token_id" . 42)
                     ("tokenizer.ggml.add_bos_token" . t)))
         (step-function (lambda (token-id position kv-cache)
                          (declare (ignore token-id position kv-cache))
                          #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                            0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                            0.0f0 10.0f0 0.0f0 -10.0f0)))
         (kv-cache (make-hash-table)))
    (let ((output (with-output-to-string (stream)
                    (multiple-value-bind (ids text logits)
                        (test-llm-response kv-pairs
                                          step-function
                                          kv-cache
                                          :eos-token-id 16
                                          :max-tokens 1
                                          :random-values '(0.1f0)
                                          :stream stream)
                      (is (equal '(14) ids))
                      (is (string= " world" text))
                      (is (= -10.0f0 (aref logits 16)))))))
      (is (search "Prompt: Hello, how are you?" output))
      (is (search "Response:  world" output)))))

(test test-gguf-file-response
  (let* ((temp-path (merge-pathnames
                     (make-pathname :name (format nil "llambda-gguf-response-test-~d"
                                                  (get-universal-time))
                                    :type "gguf")
                     (uiop:temporary-directory))))
    (labels ((write-u32-le (stream value)
               (loop for index from 0 below 4
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-u64-le (stream value)
               (loop for index from 0 below 8
                     do (write-byte (ldb (byte 8 (* 8 index)) value) stream)))
             (write-f32-le (stream value)
               #+sbcl
               (write-u32-le stream (sb-kernel::single-float-bits value))
               #-sbcl
               (error "TEST-GGUF-FILE-RESPONSE float fixture writer currently requires SBCL."))
             (write-string-field (stream value)
               (let ((octets
                       #+sbcl
                       (sb-ext:string-to-octets value :external-format :utf-8)
                       #-sbcl
                       (map '(vector (unsigned-byte 8)) #'char-code value)))
                 (write-u64-le stream (length octets))
                 (write-sequence octets stream))))
      (unwind-protect
          (progn
            (with-open-file (stream temp-path
                                    :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create
                                    :element-type '(unsigned-byte 8))
              (map nil (lambda (ch) (write-byte (char-code ch) stream)) "GGUF")
              (write-u32-le stream 3)
              (write-u64-le stream 0)
              (write-u64-le stream 6)

              (write-string-field stream "general.architecture")
              (write-u32-le stream 8)
              (write-string-field stream "llama")

              (write-string-field stream "tokenizer.ggml.tokens")
              (write-u32-le stream 9)
              (write-u32-le stream 8)
              (write-u64-le stream 17)
              (dolist (token (list "H" "e" "l" "o" "," (string (code-char #x2581))
                                   "h" "w" "a" "r" "y" "u" "?"
                                   "Hello" " world" "!" "<eos>"))
                (write-string-field stream token))

              (write-string-field stream "tokenizer.ggml.scores")
              (write-u32-le stream 9)
              (write-u32-le stream 6)
              (write-u64-le stream 17)
              (dolist (score '(-10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                               -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0 -10.0f0
                               0.9f0 0.8f0 0.7f0 -1.0f0))
                (write-f32-le stream score))

              (write-string-field stream "tokenizer.ggml.bos_token_id")
              (write-u32-le stream 4)
              (write-u32-le stream 42)

              (write-string-field stream "tokenizer.ggml.eos_token_id")
              (write-u32-le stream 4)
              (write-u32-le stream 16)

              (write-string-field stream "tokenizer.ggml.add_bos_token")
              (write-u32-le stream 7)
              (write-byte 1 stream))
            (let ((step-function (lambda (token-id position kv-cache)
                                   (declare (ignore token-id position kv-cache))
                                   #(0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                     0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0
                                     0.0f0 10.0f0 0.0f0 -10.0f0))))
              (let ((output (with-output-to-string (response-stream)
                              (multiple-value-bind (header kv-pairs ids text logits)
                                  (test-gguf-file-response temp-path
                                                           :step-function step-function
                                                           :kv-cache (make-hash-table)
                                                           :use-npu nil
                                                           :npu-tensor-names
                                                           '("missing.weight")
                                                           :use-gpu nil
                                                           :gpu-tensor-names
                                                           '("missing.weight")
                                                           :max-tokens 1
                                                           :random-values '(0.1f0)
                                                           :stream response-stream)
                                (is (equal "GGUF" (getf header :magic)))
                                (is (equal "llama"
                                           (cdr (assoc "general.architecture"
                                                       kv-pairs
                                                       :test #'string=))))
                                (is (equal '(14) ids))
                                (is (string= " world" text))
                                (is (= -10.0f0 (aref logits 16)))))))
                (is (search "Model:" output))
                (is (search "Architecture: llama" output))
                (is (search "Prompt: Hello, How are you?" output))
                (is (search "Response:  world" output))))
            (signals error
              (test-gguf-file-response temp-path
                                       :stream (make-broadcast-stream))))
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(defparameter *gemma4-e2e-model-path*
  "D:/Models/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf")

(defun normalized-e2e-output (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun plausible-e2e-output-p (text)
  (let ((trimmed (normalized-e2e-output text)))
    (and (plusp (length trimmed))
         (not (search "<|" trimmed))
         (not (search "<turn|>" trimmed)))))

(defun run-gemma4-e2e-inference (prompt &key (max-tokens 12))
  (unless (probe-file *gemma4-e2e-model-path*)
    (error "Expected Gemma4 test model missing: ~a" *gemma4-e2e-model-path*))
  (nth-value 3
             (test-gguf-file-response *gemma4-e2e-model-path*
                                      :prompt prompt
                                      :max-tokens max-tokens
                                      :temperature 0.2f0
                                      :stream (make-broadcast-stream))))

(test gemma4-e2e-colors-plausible
  (let ((text (run-gemma4-e2e-inference "List three colors, comma-separated.")))
    (is (plausible-e2e-output-p text))
    (is (>= (count #\, text) 2))
    (is (or (search "Red" text)
            (search "Blue" text)
            (search "Green" text)))))

(test gemma4-e2e-weekdays-plausible
  (let ((text (run-gemma4-e2e-inference "List two weekdays, comma-separated.")))
    (is (plausible-e2e-output-p text))
    (is (>= (count #\, text) 1))
    (is (search "day" text))))

(test gemma4-e2e-two-plus-two-plausible
  (let ((text (normalized-e2e-output
               (run-gemma4-e2e-inference "Answer with one word: What is 2 + 2?"
                                         :max-tokens 4))))
    (is (plausible-e2e-output-p text))
    (is (or (string-equal text "Four")
            (string= text "4")))))

(test gemma4-e2e-opposite-cold-plausible
  (let ((text (normalized-e2e-output
               (run-gemma4-e2e-inference "Answer with one word: opposite of cold?"
                                         :max-tokens 4))))
    (is (plausible-e2e-output-p text))
    (is (or (string-equal text "Hot")
            (string-equal text "Warm")))))

(test gemma4-e2e-sky-color-plausible
  (let ((text (normalized-e2e-output
               (run-gemma4-e2e-inference "Answer with one word: sky color on clear day?"
                                         :max-tokens 4))))
    (is (plausible-e2e-output-p text))
    (is (or (string-equal text "Blue")
            (string-equal text "Azure")))))

(defun run-tests ()
  (let ((result (run 'llambda-suite)))
    (explain! result)
    (unless (results-status result)
      (error "llambda test run failed."))
    result))
