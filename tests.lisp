(defpackage #:llambda/tests
  (:use #:cl #:fiveam)
  (:import-from #:llambda #:call-with-file
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
                          #:with-mapped-file)
  (:export #:run-tests))

(in-package #:llambda/tests)

(def-suite llambda-suite
  :description "Tests for the llambda system.")

(in-suite llambda-suite)

(test hello-message
  (is (string= "llambda ready." (hello-message))))

(test windows-bindings
  (is (fboundp 'call-with-file))
  (is (fboundp 'call-with-mapped-file))
  (is (fboundp 'apply-temperature))
  (is (fboundp 'apply-rope))
  (is (fboundp 'apply-silu))
  (is (fboundp 'create-file))
  (is (fboundp 'close-handle))
  (is (fboundp 'dequantize-q4-k-m))
  (is (fboundp 'dequantize-q6-k))
  (is (fboundp 'detokenize-token-id))
  (is (fboundp 'detokenize-token-ids))
  (is (fboundp 'decode-next-token))
  (is (fboundp 'evaluate-prompt))
  (is (fboundp 'generate-from-prompt))
  (is (fboundp 'generate-token-loop))
  (is (fboundp 'map-view-of-file))
  (is (fboundp 'print-gguf-file))
  (is (fboundp 'read-gguf-header))
  (is (fboundp 'read-gguf-kv-pairs))
  (is (fboundp 'rms-norm))
  (is (fboundp 'sample-from-probabilities))
  (is (fboundp 'sample-token-id-from-logits))
  (is (fboundp 'silu))
  (is (fboundp 'softmax))
  (is (fboundp 'test-llm-response))
  (is (fboundp 'tokenize-prompt))
  (is (fboundp 'unmap-view-of-file))
  (is (fboundp 'vector-matrix-multiply))
  (is (macro-function 'with-file-handle))
  (is (macro-function 'with-mapped-file)))

(test forward-primitives
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon)))
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

(test sampling-primitives
  (flet ((approx= (left right &optional (epsilon 1.0e-5))
           (< (abs (- left right)) epsilon)))
    (let ((scaled (apply-temperature #(2.0f0 1.0f0 -2.0f0) 0.5f0)))
      (is (approx= 4.0f0 (aref scaled 0)))
      (is (approx= 2.0f0 (aref scaled 1)))
      (is (approx= -4.0f0 (aref scaled 2))))
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
                                          :temperature 1.0f0
                                          :random-value 0.1f0)))
    (is (= 1 (sample-token-id-from-logits #(3.0f0 1.0f0 0.0f0)
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
                                 :share-mode 0))))
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
             (write-string-field (stream value)
               (write-u64-le stream (length value))
               (map nil (lambda (ch) (write-byte (char-code ch) stream)) value)))
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
             (write-string-field (stream value)
               (write-u64-le stream (length value))
               (map nil (lambda (ch) (write-byte (char-code ch) stream)) value)))
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
    ;; d = 1.0 in fp16 little-endian.
    (setf (cffi:mem-aref block :unsigned-char 0) #x00
          (cffi:mem-aref block :unsigned-char 1) #x3C)
    ;; ql (128 bytes): low/high nibbles for q1=33, q2=34, q3=35, q4=36.
    (dotimes (index 32)
      (setf (cffi:mem-aref block :unsigned-char (+ 2 index)) #x31
            (cffi:mem-aref block :unsigned-char (+ 34 index)) #x42
            (cffi:mem-aref block :unsigned-char (+ 66 index)) #x31
            (cffi:mem-aref block :unsigned-char (+ 98 index)) #x42))
    ;; qh (64 bytes): upper 2 bits for each q packed into one byte.
    (dotimes (index 64)
      (setf (cffi:mem-aref block :unsigned-char (+ 130 index)) #xAA))
    ;; 16 signed scales, all equal to 2.
    (dotimes (index 16)
      (setf (cffi:mem-aref block :unsigned-char (+ 194 index)) 2))
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
         (kv-cache (make-hash-table)))
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
                             :random-values '(0.1f0 0.1f0 0.1f0 0.1f0))
      (is (equal '(15 16) generated-ids))
      (is (string= " world!" generated-text))
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

(defun run-tests ()
  (let ((result (run 'llambda-suite)))
    (explain! result)
    (unless (results-status result)
      (error "llambda test run failed."))
    result))
