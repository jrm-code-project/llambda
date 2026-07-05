(in-package #:llambda)

(cffi:define-foreign-library kernel32
  (t (:default "kernel32")))

(cffi:use-foreign-library kernel32)

(cffi:defctype handle :pointer)
(cffi:defctype dword :uint32)

(defconstant +generic-read+ #x80000000)
(defconstant +file-share-read+ #x00000001)
(defconstant +file-map-read+ #x00000004)
(defconstant +open-existing+ 3)
(defconstant +file-attribute-normal+ #x00000080)
(defconstant +page-readonly+ #x00000002)
(defconstant +qk-k+ 256)
(defconstant +k-scale-size+ 12)
(defconstant +q6-k-scale-count+ 16)

(cffi:defcfun ("CreateFileW" create-file) handle
  (file-name :pointer)
  (desired-access dword)
  (share-mode dword)
  (security-attributes :pointer)
  (creation-disposition dword)
  (flags-and-attributes dword)
  (template-file handle))

(cffi:defcfun ("CloseHandle" close-handle) :boolean
  (object handle))

(cffi:defcfun ("CreateFileMappingW" create-file-mapping) handle
  (file handle)
  (mapping-attributes :pointer)
  (protect dword)
  (maximum-size-high dword)
  (maximum-size-low dword)
  (name :pointer))

(cffi:defcfun ("MapViewOfFile" map-view-of-file) :pointer
  (file-mapping-object handle)
  (desired-access dword)
  (file-offset-high dword)
  (file-offset-low dword)
  (number-of-bytes-to-map :size))

(cffi:defcfun ("UnmapViewOfFile" unmap-view-of-file) :boolean
  (base-address :pointer))

(defun invalid-handle-p (handle)
  (= (cffi:pointer-address handle)
     (1- (ash 1 (* 8 (cffi:foreign-type-size :pointer))))))

(defun call-with-file (pathname receiver
                       &key
                         (desired-access +generic-read+)
                         (share-mode +file-share-read+)
                         (security-attributes (cffi:null-pointer))
                         (creation-disposition +open-existing+)
                         (flags-and-attributes +file-attribute-normal+)
                         (template-file (cffi:null-pointer)))
  (let ((native-path (uiop:native-namestring pathname)))
    (cffi:with-foreign-string (file-name native-path :encoding :utf-16le)
      (let ((handle (create-file file-name
                                 desired-access
                                 share-mode
                                 security-attributes
                                 creation-disposition
                                 flags-and-attributes
                                 template-file)))
        (when (invalid-handle-p handle)
          (error "CreateFileW failed for ~a." native-path))
        (unwind-protect
            (funcall receiver handle)
          (unless (close-handle handle)
            (error "CloseHandle failed for ~a." native-path)))))))

(defun call-with-mapped-file (file-handle receiver
                              &key
                                (mapping-attributes (cffi:null-pointer))
                                (protect +page-readonly+)
                                (maximum-size-high 0)
                                (maximum-size-low 0)
                                (name (cffi:null-pointer))
                                (desired-access +file-map-read+)
                                (file-offset-high 0)
                                (file-offset-low 0)
                                (number-of-bytes-to-map 0))
  (let ((mapping-handle (create-file-mapping file-handle
                                             mapping-attributes
                                             protect
                                             maximum-size-high
                                             maximum-size-low
                                             name)))
    (when (cffi:null-pointer-p mapping-handle)
      (error "CreateFileMappingW failed."))
    (unwind-protect
        (let ((mapping (map-view-of-file mapping-handle
                                         desired-access
                                         file-offset-high
                                         file-offset-low
                                         number-of-bytes-to-map)))
          (when (cffi:null-pointer-p mapping)
            (error "MapViewOfFile failed."))
          (unwind-protect
              (funcall receiver mapping)
            (unless (unmap-view-of-file mapping)
              (error "UnmapViewOfFile failed."))))
      (unless (close-handle mapping-handle)
        (error "CloseHandle failed for file mapping object.")))))

(defmacro with-file-handle ((handle pathname) &body body)
  `(call-with-file ,pathname
                   (lambda (,handle)
                     ,@body)))

(defmacro with-mapped-file ((mapping file-handle) &body body)
  `(call-with-mapped-file ,file-handle
                          (lambda (,mapping)
                            ,@body)))

(defun read-u32-le (pointer offset)
  (loop for index from 0 below 4
        for byte = (cffi:mem-aref pointer :unsigned-char (+ offset index))
        sum (ash byte (* 8 index))))

(defun read-u16-le (pointer offset)
  (loop for index from 0 below 2
        for byte = (cffi:mem-aref pointer :unsigned-char (+ offset index))
        sum (ash byte (* 8 index))))

(defun read-u64-le (pointer offset)
  (loop for index from 0 below 8
        for byte = (cffi:mem-aref pointer :unsigned-char (+ offset index))
        sum (ash byte (* 8 index))))

(defun unsigned-to-signed (value bit-count)
  (let ((sign-bit (ash 1 (1- bit-count)))
        (modulus (ash 1 bit-count)))
    (if (zerop (logand value sign-bit))
        value
        (- value modulus))))

(defun read-octets (pointer offset length)
  (let ((octets (make-array length :element-type '(unsigned-byte 8))))
    (loop for index from 0 below length
          do (setf (aref octets index)
                   (cffi:mem-aref pointer :unsigned-char (+ offset index))))
    octets))

(defun octets-to-utf8-string (octets)
  #+sbcl
  (sb-ext:octets-to-string octets :external-format :utf-8)
  #-sbcl
  (coerce (map 'list #'code-char octets) 'string))

(defun fp16-to-single-float (bits)
  (let* ((sign (if (logbitp 15 bits) -1.0f0 1.0f0))
         (exponent (ldb (byte 5 10) bits))
         (fraction (ldb (byte 10 0) bits)))
    (cond
      ((zerop exponent)
       (if (zerop fraction)
           (* sign 0.0f0)
           (coerce (* sign
                      (scale-float (/ fraction 1024.0d0) -14))
                   'single-float)))
      ((= exponent 31)
       (error "Unsupported fp16 special value: ~x." bits))
      (t
       (coerce (* sign
                  (scale-float (+ 1.0d0 (/ fraction 1024.0d0))
                               (- exponent 15)))
               'single-float)))))

(defun read-fp16-le (pointer offset)
  (fp16-to-single-float (read-u16-le pointer offset)))

(defun rms-norm (vector weight &key (epsilon 1.0e-5))
  (let ((length (length vector)))
    (unless (= length (length weight))
      (error "RMS-NORM requires VECTOR and WEIGHT to have the same length."))
    (let ((mean-square (/ (loop for value across vector
                                sum (* value value))
                          length)))
      (let ((scale (/ (sqrt (+ mean-square epsilon)))))
        (map 'vector
             (lambda (value scale-weight)
               (coerce (* value scale-weight scale) 'single-float))
             vector
             weight)))))

(defun vector-matrix-multiply (vector matrix row-count column-count)
  (unless (= (length vector) column-count)
    (error "VECTOR length ~d does not match COLUMN-COUNT ~d."
           (length vector)
           column-count))
  (unless (= (length matrix) (* row-count column-count))
    (error "MATRIX length ~d does not match ROW-COUNT x COLUMN-COUNT = ~d."
           (length matrix)
           (* row-count column-count)))
  (let ((result (make-array row-count :element-type 'single-float)))
    (dotimes (row row-count result)
      (let ((sum 0.0f0)
            (row-offset (* row column-count)))
        (dotimes (column column-count)
          (incf sum (* (aref vector column)
                       (aref matrix (+ row-offset column)))))
        (setf (aref result row) (coerce sum 'single-float))))))

(defun silu (value)
  (coerce (/ value (+ 1.0d0 (exp (- value)))) 'single-float))

(defun apply-silu (vector)
  (map 'vector #'silu vector))

(defun apply-rope (vector position &key (rope-dimension (length vector)) (theta-base 10000.0d0))
  (unless (evenp rope-dimension)
    (error "ROPE-DIMENSION must be even, got ~d." rope-dimension))
  (unless (<= rope-dimension (length vector))
    (error "ROPE-DIMENSION ~d exceeds vector length ~d."
           rope-dimension
           (length vector)))
  (let ((result (copy-seq vector)))
    (loop for index from 0 below rope-dimension by 2
          for pair-index from 0
          do (let* ((theta (/ position
                              (expt theta-base (/ (* 2 pair-index) rope-dimension))))
                    (cos-theta (cos theta))
                    (sin-theta (sin theta))
                    (x0 (aref vector index))
                    (x1 (aref vector (1+ index))))
               (setf (aref result index)
                     (coerce (- (* x0 cos-theta) (* x1 sin-theta))
                             'single-float))
               (setf (aref result (1+ index))
                     (coerce (+ (* x0 sin-theta) (* x1 cos-theta))
                             'single-float))))
    result))

(defun apply-temperature (logits temperature)
  (when (<= temperature 0)
    (error "TEMPERATURE must be positive, got ~a." temperature))
  (map 'vector
       (lambda (logit)
         (coerce (/ logit temperature) 'single-float))
       logits))

(defun softmax (logits)
  (let* ((max-logit (loop for logit across logits maximize logit))
         (shifted-exps (map 'vector
                            (lambda (logit)
                              (coerce (exp (- logit max-logit)) 'single-float))
                            logits))
         (sum-exps (loop for value across shifted-exps sum value)))
    (map 'vector
         (lambda (value)
           (coerce (/ value sum-exps) 'single-float))
         shifted-exps)))

(defun sample-from-probabilities (probabilities
                                  &key
                                    random-value
                                    (random-state *random-state*))
  (let ((roll (or random-value (random 1.0 random-state))))
    (unless (and (<= 0.0 roll) (< roll 1.0))
      (error "RANDOM-VALUE must satisfy 0.0 <= value < 1.0, got ~a." roll))
    (let ((running-total 0.0f0)
          (last-index (1- (length probabilities))))
      (loop for probability across probabilities
            for index from 0
            do (incf running-total probability)
               (when (<= roll running-total)
                 (return index))
            finally (return last-index)))))

(defun sample-token-id-from-logits (logits
                                    &key
                                      (temperature 1.0)
                                      random-value
                                      (random-state *random-state*))
  (sample-from-probabilities
   (softmax (apply-temperature logits temperature))
   :random-value random-value
   :random-state random-state))

(defun evaluate-prompt (token-ids step-function kv-cache)
  (unless token-ids
    (error "EVALUATE-PROMPT requires at least one token id."))
  (let ((last-logits nil))
    (loop for token-id in token-ids
          for position from 0
          do (setf last-logits
                   (funcall step-function token-id position kv-cache)))
    last-logits))

(defun decode-next-token (kv-pairs logits
                           &key
                             (temperature 1.0)
                             random-value
                             (random-state *random-state*))
  (let* ((token-id (sample-token-id-from-logits logits
                                                :temperature temperature
                                                :random-value random-value
                                                :random-state random-state))
         (token-text (detokenize-token-id kv-pairs token-id)))
    (values token-id token-text)))

(defun generate-token-loop (kv-pairs initial-logits step-function kv-cache
                             &key
                               eos-token-id
                               (start-position 0)
                               (temperature 1.0)
                               (max-tokens 256)
                               random-values
                               (stream *standard-output*)
                               (random-state *random-state*))
  (let ((current-logits initial-logits)
        (generated-token-ids '())
        (generated-text ""))
    (loop for decode-index from 0 below max-tokens
          do (multiple-value-bind (token-id token-text)
                 (decode-next-token kv-pairs
                                    current-logits
                                    :temperature temperature
                                    :random-value (when random-values
                                                    (pop random-values))
                                    :random-state random-state)
               (when (and eos-token-id
                          (= token-id eos-token-id))
                 (return))
               (write-string token-text stream)
               (push token-id generated-token-ids)
               (setf generated-text (concatenate 'string generated-text token-text))
               (setf current-logits
                     (funcall step-function
                              token-id
                              (+ start-position decode-index)
                              kv-cache))))
    (values (nreverse generated-token-ids) generated-text current-logits)))

(defun generate-from-prompt (kv-pairs prompt step-function kv-cache
                              &key
                                (add-bos t)
                                eos-token-id
                                (temperature 1.0)
                                (max-tokens 256)
                                random-values
                                (stream *standard-output*)
                                (random-state *random-state*))
  (let* ((token-ids (tokenize-prompt kv-pairs prompt :add-bos add-bos))
         (prompt-logits (evaluate-prompt token-ids step-function kv-cache)))
    (generate-token-loop kv-pairs
                         prompt-logits
                         step-function
                         kv-cache
                         :eos-token-id eos-token-id
                         :start-position (length token-ids)
                         :temperature temperature
                         :max-tokens max-tokens
                         :random-values random-values
                         :stream stream
                         :random-state random-state)))

(defun test-llm-response (kv-pairs step-function kv-cache
                           &key
                             eos-token-id
                             (temperature 1.0)
                             (max-tokens 256)
                             random-values
                             (stream *standard-output*)
                             (random-state *random-state*))
  (let ((prompt "Hello, how are you?"))
    (format stream "Prompt: ~a~%Response: " prompt)
    (multiple-value-bind (generated-ids generated-text last-logits)
        (generate-from-prompt kv-pairs
                              prompt
                              step-function
                              kv-cache
                              :eos-token-id eos-token-id
                              :temperature temperature
                              :max-tokens max-tokens
                              :random-values random-values
                              :stream stream
                              :random-state random-state)
      (terpri stream)
      (values generated-ids generated-text last-logits))))

(defun read-gguf-string (pointer offset)
  (let* ((length (read-u64-le pointer offset))
         (start (+ offset 8))
         (end (+ start length)))
    (values (octets-to-utf8-string (read-octets pointer start length))
            end)))

(defun read-gguf-value (pointer offset type-tag)
  (case type-tag
    (0 (values (cffi:mem-aref pointer :unsigned-char offset)
               (+ offset 1)))
    (1 (values (unsigned-to-signed
                (cffi:mem-aref pointer :unsigned-char offset)
                8)
               (+ offset 1)))
    (2 (values (read-u16-le pointer offset)
               (+ offset 2)))
    (3 (values (unsigned-to-signed (read-u16-le pointer offset) 16)
               (+ offset 2)))
    (4 (values (read-u32-le pointer offset)
               (+ offset 4)))
    (5 (values (unsigned-to-signed (read-u32-le pointer offset) 32)
               (+ offset 4)))
    (6 (values (cffi:mem-ref (cffi:inc-pointer pointer offset) :float)
               (+ offset 4)))
    (7 (values (not (zerop (cffi:mem-aref pointer :unsigned-char offset)))
               (+ offset 1)))
    (8 (read-gguf-string pointer offset))
    (9 (let ((element-type (read-u32-le pointer offset))
             (length (read-u64-le pointer (+ offset 4)))
             (cursor (+ offset 12))
             (values '()))
         (dotimes (index length)
           (multiple-value-bind (element next-cursor)
               (read-gguf-value pointer cursor element-type)
             (push element values)
             (setf cursor next-cursor)))
         (values (nreverse values) cursor)))
    (10 (values (read-u64-le pointer offset)
                (+ offset 8)))
    (11 (values (unsigned-to-signed (read-u64-le pointer offset) 64)
                (+ offset 8)))
    (12 (values (cffi:mem-ref (cffi:inc-pointer pointer offset) :double)
                (+ offset 8)))
    (otherwise
     (error "Unsupported GGUF metadata value type: ~a." type-tag))))

(defun read-gguf-header (mapped-file)
  (let ((magic (coerce (loop for index from 0 below 4
                             collect (code-char
                                      (cffi:mem-aref mapped-file :unsigned-char index)))
                       'string)))
    (unless (string= magic "GGUF")
      (error "Invalid GGUF magic: ~s." magic))
    (list :magic magic
          :version (read-u32-le mapped-file 4)
          :tensor-count (read-u64-le mapped-file 8)
          :metadata-kv-count (read-u64-le mapped-file 16)
          :header-size 24)))

(defun read-gguf-kv-pairs (mapped-file)
  (let* ((header (read-gguf-header mapped-file))
         (cursor (getf header :header-size))
         (metadata-kv-count (getf header :metadata-kv-count))
         (pairs '()))
    (dotimes (index metadata-kv-count (nreverse pairs))
      (multiple-value-bind (key key-end)
          (read-gguf-string mapped-file cursor)
        (let ((type-tag (read-u32-le mapped-file key-end)))
          (multiple-value-bind (value next-cursor)
              (read-gguf-value mapped-file (+ key-end 4) type-tag)
            (push (cons key value) pairs)
            (setf cursor next-cursor)))))))

(defun gguf-kv-value (kv-pairs key)
  (let ((entry (assoc key kv-pairs :test #'string=)))
    (unless entry
      (error "Missing GGUF metadata key ~s." key))
    (cdr entry)))

(defun gguf-kv-value-or-nil (kv-pairs key)
  (cdr (assoc key kv-pairs :test #'string=)))

(defun tokenizer-entry-table (kv-pairs)
  (let* ((tokens (gguf-kv-value kv-pairs "tokenizer.ggml.tokens"))
         (scores (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.scores")
                     (make-list (length tokens) :initial-element 0.0f0))))
    (unless (= (length tokens) (length scores))
      (error "Tokenizer token and score arrays have different lengths."))
    (let ((table (make-hash-table :test #'equal)))
      (loop for token in tokens
            for score in scores
            for token-id from 0
            do (setf (gethash token table)
                     (cons token-id score)))
      table)))

(defun get-scale-min-k4 (index scales-pointer)
  (let ((byte0 (cffi:mem-aref scales-pointer :unsigned-char index))
        (byte4 (cffi:mem-aref scales-pointer :unsigned-char (+ index 4))))
    (if (< index 4)
        (values (logand byte0 63)
                (logand byte4 63))
        (values (logior (logand byte4 #x0F)
                        (ash (ash (logand (cffi:mem-aref scales-pointer
                                                         :unsigned-char
                                                         (- index 4))
                                          #xC0)
                                  -6)
                             4))
                (logior (ash byte4 -4)
                        (ash (ash (logand (cffi:mem-aref scales-pointer
                                                         :unsigned-char
                                                         index)
                                          #xC0)
                                  -6)
                             4))))))

(defun dequantize-q4-k-m (quantized-pointer element-count)
  "Dequantize GGML q4_K blocks, the block format used by Q4_K_M model tensors."
  (unless (zerop (mod element-count +qk-k+))
    (error "Q4_K_M dequantization requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let* ((block-size (+ 4 +k-scale-size+ (/ +qk-k+ 2)))
         (block-count (/ element-count +qk-k+))
         (result (make-array element-count :element-type 'single-float)))
    (dotimes (block-index block-count result)
      (let* ((block-offset (* block-index block-size))
             (d (read-fp16-le quantized-pointer block-offset))
             (dmin (read-fp16-le quantized-pointer (+ block-offset 2)))
             (scales-pointer (cffi:inc-pointer quantized-pointer (+ block-offset 4)))
             (qs-pointer (cffi:inc-pointer quantized-pointer
                                           (+ block-offset 4 +k-scale-size+)))
             (result-base (* block-index +qk-k+))
             (scale-index 0))
        (loop for j from 0 below +qk-k+ by 64
              for q-base from 0 by 32
              do (multiple-value-bind (scale0 min0)
                     (get-scale-min-k4 scale-index scales-pointer)
                   (multiple-value-bind (scale1 min1)
                       (get-scale-min-k4 (1+ scale-index) scales-pointer)
                     (let ((delta0 (* d scale0))
                           (offset0 (* dmin min0))
                           (delta1 (* d scale1))
                           (offset1 (* dmin min1)))
                       (dotimes (l 32)
                         (let ((packed (cffi:mem-aref qs-pointer
                                                      :unsigned-char
                                                      (+ q-base l))))
                           (setf (aref result (+ result-base j l))
                                 (coerce (- (* delta0 (logand packed #x0F))
                                            offset0)
                                         'single-float))
                           (setf (aref result (+ result-base j 32 l))
                                 (coerce (- (* delta1 (ash packed -4))
                                            offset1)
                                         'single-float)))))
                     (incf scale-index 2))))))))

(defun read-s8 (pointer offset)
  (unsigned-to-signed (cffi:mem-aref pointer :unsigned-char offset) 8))

(defun dequantize-q6-k (quantized-pointer element-count)
  "Dequantize GGML q6_K blocks into a simple array of single floats."
  (unless (zerop (mod element-count +qk-k+))
    (error "Q6_K dequantization requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let* ((block-size (+ 2
                        +q6-k-scale-count+
                        (* 3 (/ +qk-k+ 4))))
         (block-count (/ element-count +qk-k+))
         (result (make-array element-count :element-type 'single-float)))
    (dotimes (block-index block-count result)
      (let* ((block-offset (* block-index block-size))
             (d (read-fp16-le quantized-pointer block-offset))
             (ql-pointer (cffi:inc-pointer quantized-pointer (+ block-offset 2)))
             (qh-pointer (cffi:inc-pointer quantized-pointer
                                           (+ block-offset 2 (/ +qk-k+ 2))))
             (scales-pointer (cffi:inc-pointer quantized-pointer
                                               (+ block-offset
                                                  2
                                                  (/ +qk-k+ 2)
                                                  (/ +qk-k+ 4))))
             (result-base (* block-index +qk-k+)))
        (loop for chunk-base from 0 below +qk-k+ by 128
              for ql-base from 0 by 64
              for qh-base from 0 by 32
              for scale-base from 0 by 8
              do (dotimes (l 32)
                   (let* ((scale-index (truncate l 16))
                          (packed-low (cffi:mem-aref ql-pointer
                                                     :unsigned-char
                                                     (+ ql-base l)))
                          (packed-high (cffi:mem-aref ql-pointer
                                                      :unsigned-char
                                                      (+ ql-base 32 l)))
                          (packed-top (cffi:mem-aref qh-pointer
                                                     :unsigned-char
                                                     (+ qh-base l)))
                          (q1 (- (logior (logand packed-low #x0F)
                                         (ash (logand packed-top #x03) 4))
                                 32))
                          (q2 (- (logior (logand packed-high #x0F)
                                         (ash (logand (ash packed-top -2) #x03) 4))
                                 32))
                          (q3 (- (logior (ash packed-low -4)
                                         (ash (logand (ash packed-top -4) #x03) 4))
                                 32))
                          (q4 (- (logior (ash packed-high -4)
                                         (ash (logand (ash packed-top -6) #x03) 4))
                                 32))
                          (scale1 (read-s8 scales-pointer (+ scale-base scale-index 0)))
                          (scale2 (read-s8 scales-pointer (+ scale-base scale-index 2)))
                          (scale3 (read-s8 scales-pointer (+ scale-base scale-index 4)))
                          (scale4 (read-s8 scales-pointer (+ scale-base scale-index 6))))
                     (setf (aref result (+ result-base chunk-base l))
                           (coerce (* d scale1 q1) 'single-float))
                     (setf (aref result (+ result-base chunk-base 32 l))
                           (coerce (* d scale2 q2) 'single-float))
                     (setf (aref result (+ result-base chunk-base 64 l))
                           (coerce (* d scale3 q3) 'single-float))
                     (setf (aref result (+ result-base chunk-base 96 l))
                           (coerce (* d scale4 q4) 'single-float)))))))))

(defun normalize-sentencepiece-token (token)
  (substitute #\Space (code-char #x2581) token))

(defun detokenize-token-id (kv-pairs token-id)
  (let* ((tokens (gguf-kv-value kv-pairs "tokenizer.ggml.tokens"))
         (token-count (length tokens)))
    (unless (and (integerp token-id)
                 (<= 0 token-id)
                 (< token-id token-count))
      (error "Token id ~a is out of range for tokenizer with ~d tokens."
             token-id
             token-count))
    (normalize-sentencepiece-token (nth token-id tokens))))

(defun detokenize-token-ids (kv-pairs token-ids &optional (stream *standard-output*))
  (let ((text (with-output-to-string (buffer)
                (dolist (token-id token-ids)
                  (write-string (detokenize-token-id kv-pairs token-id) buffer)))))
    (write-string text stream)
    text))

(defun normalize-prompt-for-tokenization (prompt)
  (substitute (code-char #x2581) #\Space prompt))

(defun make-base-token-pieces (prompt token-table)
  (loop for character across (normalize-prompt-for-tokenization prompt)
        for token = (string character)
        for entry = (gethash token token-table)
        unless entry
          do (error "No base token found for character ~s." token)
        collect (cons (car entry) token)))

(defun find-best-token-merge (pieces token-table)
  (let ((best-index nil)
        (best-id nil)
        (best-token nil)
        (best-score nil)
        (index 0))
    (loop for current on pieces
          while (cdr current)
          do (let* ((left (car current))
                    (right (cadr current))
                    (candidate (concatenate 'string (cdr left) (cdr right)))
                    (entry (gethash candidate token-table)))
               (when entry
                 (let ((score (cdr entry)))
                   (when (or (null best-score)
                             (> score best-score))
                     (setf best-index index
                           best-id (car entry)
                           best-token candidate
                           best-score score)))))
             (incf index))
    (values best-index best-id best-token)))

(defun merge-token-pieces (pieces merge-index merged-id merged-token)
  (let ((prefix '())
        (suffix pieces)
        (index 0))
    (loop while (< index merge-index)
          do (push (car suffix) prefix)
             (setf suffix (cdr suffix))
             (incf index))
    (setf suffix (cddr suffix))
    (nconc (nreverse prefix)
           (list (cons merged-id merged-token))
           suffix)))

(defun resolve-bos-token-id (kv-pairs)
  (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.bos_token_id")
      (gguf-kv-value-or-nil kv-pairs "general.bos_token_id")))

(defun default-add-bos-p (kv-pairs)
  (let ((value (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.add_bos_token")
                   (gguf-kv-value-or-nil kv-pairs "general.add_bos_token"))))
    (and value t)))

(defun tokenize-prompt (kv-pairs prompt &key (add-bos nil add-bos-p))
  (let* ((token-table (tokenizer-entry-table kv-pairs))
         (pieces (make-base-token-pieces prompt token-table))
         (include-bos (if add-bos-p
                          add-bos
                          (default-add-bos-p kv-pairs))))
    (loop
      (multiple-value-bind (merge-index merged-id merged-token)
          (find-best-token-merge pieces token-table)
        (unless merge-index
          (return))
        (setf pieces (merge-token-pieces pieces
                                         merge-index
                                         merged-id
                                         merged-token))))
    (let ((token-ids (mapcar #'car pieces)))
      (if include-bos
          (let ((bos-token-id (resolve-bos-token-id kv-pairs)))
            (unless bos-token-id
              (error "Requested BOS token, but no BOS token id is present in metadata."))
            (cons bos-token-id token-ids))
          token-ids))))

(defun string-array-value-p (value)
  (and (listp value)
       (every #'stringp value)))

(defun print-gguf-file (pathname &optional (stream *standard-output*))
  (call-with-file pathname
                  (lambda (handle)
                    (with-mapped-file (mapping handle)
                      (let ((header (read-gguf-header mapping))
                            (kv-pairs (read-gguf-kv-pairs mapping)))
                        (format stream "GGUF file: ~a~%" pathname)
                        (format stream "Header:~%")
                        (format stream "  Magic: ~a~%" (getf header :magic))
                        (format stream "  Version: ~d~%" (getf header :version))
                        (format stream "  Tensor count: ~d~%"
                                (getf header :tensor-count))
                        (format stream "  Metadata KV count: ~d~%"
                                (getf header :metadata-kv-count))
                        (format stream "Metadata:~%")
                        (dolist (pair kv-pairs)
                          (format stream "  ~a: ~a~%"
                                  (car pair)
                                  (if (string-array-value-p (cdr pair))
                                      "<array of strings>"
                                      (format nil "~s" (cdr pair)))))
                        (values header kv-pairs))))))

(defun hello-message ()
  "Return the default startup message for llambda."
  "llambda ready.")

(defun main ()
  (format t "~a~%" (hello-message)))
