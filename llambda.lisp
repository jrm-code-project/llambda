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
(defconstant +ggml-type-f32+ 0)
(defconstant +ggml-type-f16+ 1)
(defconstant +ggml-type-bf16+ 30)
(defconstant +ggml-type-q4-k+ 12)
(defconstant +ggml-type-q6-k+ 14)

(defparameter *compute-gguf-logits* t)

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

(cffi:defcfun ("RtlMoveMemory" rtl-move-memory) :void
  (destination :pointer)
  (source :pointer)
  (length :size))

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
  (+ (cffi:mem-aref pointer :unsigned-char offset)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 1)) 8)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 2)) 16)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 3)) 24)))

(defun read-u16-le (pointer offset)
  (+ (cffi:mem-aref pointer :unsigned-char offset)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 1)) 8)))

(defun read-u64-le (pointer offset)
  (+ (cffi:mem-aref pointer :unsigned-char offset)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 1)) 8)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 2)) 16)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 3)) 24)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 4)) 32)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 5)) 40)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 6)) 48)
     (ash (cffi:mem-aref pointer :unsigned-char (+ offset 7)) 56)))

(defun unsigned-to-signed (value bit-count)
  (let ((sign-bit (ash 1 (1- bit-count)))
        (modulus (ash 1 bit-count)))
    (if (zerop (logand value sign-bit))
        value
        (- value modulus))))

(defun read-octets (pointer offset length)
  (let ((octets (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (index length octets)
      (declare (fixnum index))
      (setf (aref octets index)
            (cffi:mem-aref pointer :unsigned-char (+ offset index))))))

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

(declaim (ftype (function (t fixnum) single-float) read-fp16-le)
         (ftype (function (t fixnum) single-float) read-bf16-le)
         (ftype (function (t fixnum) fixnum) read-s8)
         (inline read-fp16-le read-bf16-le read-s8))

(defun read-fp16-le (pointer offset)
  (the single-float
       (fp16-to-single-float (read-u16-le pointer offset))))

(defun read-s8 (pointer offset)
  (the fixnum
       (unsigned-to-signed (cffi:mem-aref pointer :unsigned-char offset) 8)))

(defun ensure-single-float-array (vector)
  (if (typep vector '(simple-array single-float (*)))
      vector
      (make-array (length vector)
                  :element-type 'single-float
                  :initial-contents vector)))

(defun sum-square-elements (vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) vector))
  (let ((sum 0.0f0)
        (length (length vector)))
    (declare (single-float sum)
             (fixnum length))
    (dotimes (index length (the single-float sum))
      (declare (fixnum index))
      (incf sum (* (aref vector index) (aref vector index))))))

(defun sum-square-elements-range (vector start count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) vector)
           (fixnum start count))
  (let ((sum 0.0f0))
    (declare (single-float sum))
    (dotimes (index count (the single-float sum))
      (declare (fixnum index))
      (let ((vector-index (+ start index)))
        (declare (fixnum vector-index))
        (incf sum (* (aref vector vector-index)
                     (aref vector vector-index)))))))

(defun max-single-float-element (vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) vector))
  (let ((length (length vector)))
    (declare (fixnum length))
    (unless (plusp length)
      (error "Cannot compute maximum of empty vector."))
    (let ((maximum (aref vector 0)))
      (declare (single-float maximum))
      (dotimes (index (1- length) (the single-float maximum))
        (declare (fixnum index))
        (let ((value (aref vector (1+ index))))
          (declare (single-float value))
          (when (> value maximum)
            (setf maximum value)))))))

(defun rms-norm-into (dest vector weight &key (epsilon 1.0e-5))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector weight))
  (let ((length (length vector)))
    (unless (= length (length weight))
      (error "RMS-NORM requires VECTOR and WEIGHT to have the same length."))
    (unless (= length (length dest))
      (error "RMS-NORM destination length ~d does not match vector length ~d."
             (length dest)
             length))
    (let* ((epsilon (coerce epsilon 'single-float))
           (mean-square (/ (sum-square-elements vector) length))
           (scale (/ (sqrt (+ mean-square epsilon)))))
      (declare (single-float epsilon mean-square scale)
               (fixnum length))
      (dotimes (index length dest)
        (declare (fixnum index))
        (setf (aref dest index)
              (* (aref vector index)
                 (aref weight index)
                 scale))))))

(defun rms-norm (vector weight &key (epsilon 1.0e-5))
  (let ((vector (ensure-single-float-array vector))
        (weight (ensure-single-float-array weight)))
    (rms-norm-into (make-array (length vector) :element-type 'single-float)
                   vector
                   weight
                   :epsilon epsilon)))

(defun vector-matrix-multiply-into (dest vector matrix row-count column-count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector matrix)
           (fixnum row-count column-count))
  (unless (= (length vector) column-count)
    (error "VECTOR length ~d does not match COLUMN-COUNT ~d."
           (length vector)
           column-count))
  (unless (= (length matrix) (* row-count column-count))
    (error "MATRIX length ~d does not match ROW-COUNT x COLUMN-COUNT = ~d."
           (length matrix)
           (* row-count column-count)))
  (unless (= (length dest) row-count)
    (error "Destination length ~d does not match ROW-COUNT ~d."
           (length dest)
           row-count))
  (dotimes (row row-count dest)
    (declare (fixnum row))
    (let ((sum 0.0f0)
          (row-offset (* row column-count)))
      (declare (single-float sum)
               (fixnum row-offset))
      (dotimes (column column-count)
        (declare (fixnum column))
        (incf sum (* (aref vector column)
                     (aref matrix (+ row-offset column)))))
      (setf (aref dest row) sum))))

(defun vector-matrix-multiply (vector matrix row-count column-count)
  (let ((vector (ensure-single-float-array vector))
        (matrix (ensure-single-float-array matrix)))
    (vector-matrix-multiply-into (make-array row-count :element-type 'single-float)
                                 vector
                                 matrix
                                 row-count
                                 column-count)))

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
  (let* ((result (copy-seq vector))
         (pair-count (/ rope-dimension 2)))
    (declare (fixnum pair-count))
    (dotimes (pair-index pair-count result)
      (declare (fixnum pair-index))
      (let* ((index (* pair-index 2))
             (theta (/ position
                       (expt theta-base (/ (* 2 pair-index) rope-dimension))))
             (cos-theta (cos theta))
             (sin-theta (sin theta))
             (x0 (aref vector index))
             (x1 (aref vector (1+ index))))
        (declare (fixnum index))
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
  (let* ((logits (ensure-single-float-array logits))
         (max-logit (max-single-float-element logits))
         (shifted-exps (make-array (length logits) :element-type 'single-float)))
    (declare (single-float max-logit)
             (type (simple-array single-float (*)) logits shifted-exps))
    (map-into shifted-exps
              (lambda (logit)
                (declare (single-float logit))
                (coerce (exp (- logit max-logit)) 'single-float))
              logits)
    (let ((sum-exps (reduce #'+ shifted-exps :initial-value 0.0f0)))
      (declare (single-float sum-exps))
      (map-into shifted-exps
                (lambda (value)
                  (declare (single-float value))
                  (coerce (/ value sum-exps) 'single-float))
                shifted-exps))))

(defun sample-from-probabilities (probabilities
                                  &key
                                    random-value
                                    (random-state *random-state*))
  (let ((roll (or random-value (random 1.0 random-state))))
    (unless (and (<= 0.0 roll) (< roll 1.0))
      (error "RANDOM-VALUE must satisfy 0.0 <= value < 1.0, got ~a." roll))
    (let ((running-total 0.0f0)
          (length (length probabilities)))
      (declare (single-float running-total)
               (fixnum length))
      (let ((last-index (1- length)))
        (declare (fixnum last-index))
        (dotimes (index length last-index)
          (declare (fixnum index))
          (incf running-total (aref probabilities index))
          (when (<= roll running-total)
            (return index)))))))

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
  (let ((last-logits nil)
        (last-position (1- (length token-ids))))
    (declare (fixnum last-position))
    (let ((position 0))
      (declare (fixnum position))
      (dolist (token-id token-ids last-logits)
        (let ((*compute-gguf-logits* (= position last-position)))
         (setf last-logits
               (funcall step-function token-id position kv-cache)))
        (incf position)))))

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
                               stop-token-ids
                               (start-position 0)
                               (temperature 1.0)
                               (max-tokens 256)
                               random-values
                               (stream *standard-output*)
                               (random-state *random-state*))
  (let ((current-logits initial-logits)
        (generated-token-ids '())
        (generated-text "")
        (effective-stop-token-ids
         (remove-duplicates (remove nil (append stop-token-ids
                                                (when eos-token-id
                                                  (list eos-token-id))))
                            :test #'=)))
    (dotimes (decode-index max-tokens)
      (declare (fixnum decode-index))
      (multiple-value-bind (token-id token-text)
          (decode-next-token kv-pairs
                             current-logits
                             :temperature temperature
                             :random-value (when random-values
                                             (pop random-values))
                             :random-state random-state)
        (when (member token-id effective-stop-token-ids :test #'=)
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

(defun gemma4-chat-prompt-p (prompt)
  (or (search "<|turn>" prompt)
      (search "<turn|>" prompt)
      (search "<bos>" prompt)))

(defun maybe-prepare-prompt-for-generation (kv-pairs prompt add-bos)
  (if (and (string= (or (tokenizer-model kv-pairs) "")
                   "gemma4")
          (gguf-kv-value-or-nil kv-pairs "tokenizer.chat_template")
          (not (gemma4-chat-prompt-p prompt)))
      (values (format nil "<bos><|turn>user~%~a<turn|>~%<|turn>model~%" prompt)
             nil)
      (values prompt add-bos)))

(defun generate-from-prompt (kv-pairs prompt step-function kv-cache
                              &key
                                (add-bos t)
                                eos-token-id
                                (temperature 1.0)
                                (max-tokens 256)
                                random-values
                                (stream *standard-output*)
                                (random-state *random-state*))
  (multiple-value-bind (prepared-prompt effective-add-bos)
      (maybe-prepare-prompt-for-generation kv-pairs prompt add-bos)
    (let* ((token-ids (tokenize-prompt kv-pairs prepared-prompt :add-bos effective-add-bos))
           (stop-token-ids (resolve-stop-token-ids kv-pairs eos-token-id))
           (prompt-logits (evaluate-prompt token-ids step-function kv-cache)))
      (generate-token-loop kv-pairs
                           prompt-logits
                           step-function
                           kv-cache
                           :eos-token-id eos-token-id
                           :stop-token-ids stop-token-ids
                           :start-position (length token-ids)
                           :temperature temperature
                           :max-tokens max-tokens
                           :random-values random-values
                           :stream stream
                           :random-state random-state))))

(defun resolve-eos-token-id (kv-pairs)
  (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.eos_token_id")
      (gguf-kv-value-or-nil kv-pairs "general.eos_token_id")))

(defun resolve-stop-token-ids (kv-pairs &optional eos-token-id)
  (let ((stop-token-ids (remove nil (list eos-token-id))))
    (when (and (string= (or (tokenizer-model kv-pairs) "")
                        "gemma4")
               (gguf-kv-value-or-nil kv-pairs "tokenizer.chat_template"))
      (let ((turn-end-token-id (gethash "<turn|>" (tokenizer-token-id-table kv-pairs))))
        (when turn-end-token-id
          (push turn-end-token-id stop-token-ids))))
    (nreverse (remove-duplicates stop-token-ids :test #'=))))

(defun test-gguf-file-response (pathname
                               &key
                                 (prompt "Hello, How are you?")
                                 step-function
                                 kv-cache
                                 eos-token-id
                                 (temperature 1.0)
                                 (max-tokens 256)
                                 random-values
                                 (stream *standard-output*)
                                 (random-state *random-state*))
  (call-with-file pathname
                  (lambda (handle)
                    (with-mapped-file (mapping handle)
                      (let* ((header (read-gguf-header mapping))
                             (kv-pairs (read-gguf-kv-pairs mapping))
                             (tensor-infos (read-gguf-tensor-infos mapping))
                             (architecture
                              (or (gguf-kv-value-or-nil kv-pairs "general.architecture")
                                  "unknown"))
                             (model (and (null step-function)
                                        (string= architecture "gemma4")
                                        (load-gemma4-model mapping kv-pairs tensor-infos)))
                             (effective-step-function (or step-function
                                                         (and model
                                                              (make-gemma4-step-function
                                                               model))))
                             (effective-kv-cache (or kv-cache (make-hash-table)))
                             (effective-eos-token-id
                              (or eos-token-id (resolve-eos-token-id kv-pairs))))
                        (format stream "Model: ~a~%" pathname)
                        (format stream "Architecture: ~a~%" architecture)
                        (format stream "Prompt: ~a~%Response: " prompt)
                        (unless effective-step-function
                          (error
                           "Cannot run prompt against ~a yet: GGUF metadata loaded (~a, ~d tensors), but tensor loading and the real forward-pass step function are not implemented."
                           pathname
                           architecture
                           (getf header :tensor-count)))
                        (multiple-value-bind (generated-ids generated-text last-logits)
                            (generate-from-prompt kv-pairs
                                                 prompt
                                                 effective-step-function
                                                 effective-kv-cache
                                                 :eos-token-id effective-eos-token-id
                                                 :temperature temperature
                                                 :max-tokens max-tokens
                                                 :random-values random-values
                                                 :stream stream
                                                 :random-state random-state)
                          (terpri stream)
                          (values header
                                 kv-pairs
                                 generated-ids
                                 generated-text
                                 last-logits)))))))

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
  (let ((magic (map 'string #'code-char (read-octets mapped-file 0 4))))
    (unless (string= magic "GGUF")
      (error "Invalid GGUF magic: ~s." magic))
    (list :magic magic
          :version (read-u32-le mapped-file 4)
          :tensor-count (read-u64-le mapped-file 8)
          :metadata-kv-count (read-u64-le mapped-file 16)
          :header-size 24)))

(defun read-gguf-metadata-section (mapped-file)
  (let* ((header (read-gguf-header mapped-file))
         (cursor (getf header :header-size))
         (metadata-kv-count (getf header :metadata-kv-count))
         (pairs '()))
    (dotimes (index metadata-kv-count)
      (multiple-value-bind (key key-end)
          (read-gguf-string mapped-file cursor)
        (let ((type-tag (read-u32-le mapped-file key-end)))
          (multiple-value-bind (value next-cursor)
              (read-gguf-value mapped-file (+ key-end 4) type-tag)
            (push (cons key value) pairs)
            (setf cursor next-cursor)))))
    (values (nreverse pairs) cursor)))

(defun read-gguf-kv-pairs (mapped-file)
  (nth-value 0 (read-gguf-metadata-section mapped-file)))

(defun align-offset (offset alignment)
  (* alignment (ceiling offset alignment)))

(defun gguf-alignment (kv-pairs)
  (or (gguf-kv-value-or-nil kv-pairs "general.alignment")
      32))

(defun supported-ggml-type-p (type-tag)
  (member type-tag
          (list +ggml-type-f32+
                +ggml-type-f16+
                +ggml-type-bf16+
                +ggml-type-q4-k+
                +ggml-type-q6-k+)))

(defun ggml-type-name (type-tag)
  (case type-tag
    (#.+ggml-type-f32+ :f32)
    (#.+ggml-type-f16+ :f16)
    (#.+ggml-type-bf16+ :bf16)
    (#.+ggml-type-q4-k+ :q4-k)
    (#.+ggml-type-q6-k+ :q6-k)
    (otherwise (intern (format nil "TYPE-~D" type-tag) :keyword))))

(defun ggml-type-block-size (type-tag)
  (case type-tag
    ((#.+ggml-type-f32+ #.+ggml-type-f16+ #.+ggml-type-bf16+) 1)
    (#.+ggml-type-q4-k+ +qk-k+)
    (#.+ggml-type-q6-k+ +qk-k+)
    (otherwise (error "Unsupported GGML tensor type tag ~a." type-tag))))

(defun ggml-type-size (type-tag)
  (case type-tag
    (#.+ggml-type-f32+ 4)
    (#.+ggml-type-f16+ 2)
    (#.+ggml-type-bf16+ 2)
    (#.+ggml-type-q4-k+ (+ 4 +k-scale-size+ (/ +qk-k+ 2)))
    (#.+ggml-type-q6-k+ (+ 2 +q6-k-scale-count+ (* 3 (/ +qk-k+ 4))))
    (otherwise (error "Unsupported GGML tensor type tag ~a." type-tag))))

(defun ggml-tensor-byte-size (type-tag element-count)
  (let ((block-size (ggml-type-block-size type-tag)))
    (unless (zerop (mod element-count block-size))
      (error "Tensor element count ~d is not a multiple of block size ~d for type ~a."
             element-count
             block-size
             (ggml-type-name type-tag)))
    (* (/ element-count block-size)
       (ggml-type-size type-tag))))

(defun read-gguf-tensor-infos (mapped-file)
  (let* ((header (read-gguf-header mapped-file))
         (tensor-count (getf header :tensor-count)))
    (multiple-value-bind (kv-pairs cursor)
        (read-gguf-metadata-section mapped-file)
      (let ((tensor-infos '()))
        (dotimes (index tensor-count)
          (multiple-value-bind (name name-end)
              (read-gguf-string mapped-file cursor)
            (let* ((dimension-count (read-u32-le mapped-file name-end))
                   (dimension-cursor (+ name-end 4))
                   (dimensions (let ((dimensions '()))
                                 (dotimes (dimension-index dimension-count (nreverse dimensions))
                                   (declare (fixnum dimension-index))
                                   (push (read-u64-le mapped-file
                                                      (+ dimension-cursor
                                                         (* dimension-index 8)))
                                         dimensions))))
                   (type-cursor (+ dimension-cursor (* dimension-count 8)))
                   (type-tag (read-u32-le mapped-file type-cursor))
                   (offset (read-u64-le mapped-file (+ type-cursor 4)))
                   (next-cursor (+ type-cursor 12))
                   (element-count (reduce #'* dimensions :initial-value 1))
                   (byte-size (when (supported-ggml-type-p type-tag)
                                (ggml-tensor-byte-size type-tag element-count))))
              (push (list :name name
                          :dimension-count dimension-count
                          :dimensions dimensions
                          :type-tag type-tag
                          :type-name (ggml-type-name type-tag)
                          :offset offset
                          :element-count element-count
                          :byte-size byte-size)
                    tensor-infos)
              (setf cursor next-cursor))))
        (let ((tensor-data-start (align-offset cursor (gguf-alignment kv-pairs))))
          (mapcar (lambda (tensor-info)
                    (append tensor-info
                            (list :data-offset (+ tensor-data-start
                                                  (getf tensor-info :offset)))))
                  (nreverse tensor-infos)))))))

(defun find-gguf-tensor-info (tensor-infos tensor-name)
  (find tensor-name tensor-infos :test #'string= :key (lambda (tensor-info)
                                                        (getf tensor-info :name))))

(defun load-f32-tensor-into (dest tensor-pointer element-count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest)
           (fixnum element-count))
  (unless (= (length dest) element-count)
    (error "Destination length ~d does not match element count ~d."
           (length dest)
           element-count))
  (dotimes (index element-count dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (cffi:mem-aref tensor-pointer :float index))))

(defun load-f32-tensor (tensor-pointer element-count)
  (load-f32-tensor-into (make-array element-count :element-type 'single-float)
                        tensor-pointer
                        element-count))

(defun load-f16-tensor-into (dest tensor-pointer element-count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest)
           (fixnum element-count))
  (unless (= (length dest) element-count)
    (error "Destination length ~d does not match element count ~d."
           (length dest)
           element-count))
  (dotimes (index element-count dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (read-fp16-le tensor-pointer (* index 2)))))

(defun load-f16-tensor (tensor-pointer element-count)
  (load-f16-tensor-into (make-array element-count :element-type 'single-float)
                        tensor-pointer
                        element-count))

(defun bf16-to-single-float (bits)
  (let* ((sign (if (logbitp 15 bits) -1.0f0 1.0f0))
         (exponent (ldb (byte 8 7) bits))
         (fraction (ldb (byte 7 0) bits)))
    (cond
      ((zerop exponent)
       (if (zerop fraction)
           (* sign 0.0f0)
           (coerce (* sign
                      (scale-float (/ fraction 128.0d0) -126))
                   'single-float)))
      ((= exponent 255)
       (error "Unsupported bf16 special value: ~x." bits))
      (t
       (coerce (* sign
                  (scale-float (+ 1.0d0 (/ fraction 128.0d0))
                               (- exponent 127)))
               'single-float)))))

(defun read-bf16-le (pointer offset)
  (the single-float
       (bf16-to-single-float (read-u16-le pointer offset))))

(defun load-bf16-tensor-into (dest tensor-pointer element-count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest)
           (fixnum element-count))
  (unless (= (length dest) element-count)
    (error "Destination length ~d does not match element count ~d."
           (length dest)
           element-count))
  (dotimes (index element-count dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (read-bf16-le tensor-pointer (* index 2)))))

(defun load-bf16-tensor (tensor-pointer element-count)
  (load-bf16-tensor-into (make-array element-count :element-type 'single-float)
                         tensor-pointer
                         element-count))

(defun load-gguf-tensor (mapped-file tensor-info)
  (let* ((type-tag (getf tensor-info :type-tag))
         (element-count (getf tensor-info :element-count))
         (tensor-pointer (cffi:inc-pointer mapped-file
                                           (getf tensor-info :data-offset))))
    (case type-tag
      (#.+ggml-type-f32+ (load-f32-tensor tensor-pointer element-count))
      (#.+ggml-type-f16+ (load-f16-tensor tensor-pointer element-count))
      (#.+ggml-type-bf16+ (load-bf16-tensor tensor-pointer element-count))
      (#.+ggml-type-q4-k+ (dequantize-q4-k-m tensor-pointer element-count))
      (#.+ggml-type-q6-k+ (dequantize-q6-k tensor-pointer element-count))
      (otherwise
       (error "Tensor ~s has unsupported GGML type tag ~a."
              (getf tensor-info :name)
              type-tag)))))

(defun load-gguf-tensor-by-name (mapped-file tensor-name &optional tensor-infos)
  (let* ((resolved-tensor-infos (or tensor-infos (read-gguf-tensor-infos mapped-file)))
         (tensor-info (find-gguf-tensor-info resolved-tensor-infos tensor-name)))
    (unless tensor-info
      (error "Unable to find GGUF tensor named ~s." tensor-name))
    (values (load-gguf-tensor mapped-file tensor-info)
            tensor-info)))

(defstruct gguf-model
  mapping
  kv-pairs
  tensor-infos
  tensor-info-table
  tensor-cache
  architecture
  hidden-size
  layer-count
  head-count
  kv-head-count
  ffn-size
  norm-epsilon
  sliding-window
  sliding-pattern
  rope-base
  rope-base-swa
  rope-dimension
  rope-dimension-swa
  shared-kv-layers
  per-layer-embedding-size
  final-logit-softcap
  output-tensor-name)

(defun make-tensor-info-table (tensor-infos)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (tensor-info tensor-infos table)
      (setf (gethash (getf tensor-info :name) table)
            tensor-info))))

(defun gguf-model-tensor-info (model tensor-name &optional requiredp)
  (let ((tensor-info (gethash tensor-name (gguf-model-tensor-info-table model))))
    (when (and requiredp (null tensor-info))
      (error "Model is missing required tensor ~s." tensor-name))
    tensor-info))

(defun tensor-column-count (tensor-info)
  (the fixnum
       (first (getf tensor-info :dimensions))))

(defun tensor-row-count (tensor-info)
  (the fixnum
       (or (second (getf tensor-info :dimensions)) 1)))

(defun tensor-row-byte-size (tensor-info)
  (the fixnum
       (ggml-tensor-byte-size (getf tensor-info :type-tag)
                              (tensor-column-count tensor-info))))

(defun vector-add-into (dest left right)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest left right))
  (unless (= (length left) (length right))
    (error "VECTOR-ADD requires vectors of equal length."))
  (unless (= (length dest) (length left))
    (error "VECTOR-ADD destination length ~d does not match operand length ~d."
           (length dest)
           (length left)))
  (dotimes (index (length left) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (+ (aref left index) (aref right index)))))

(defun vector-add (left right)
  (let ((left (ensure-single-float-array left))
        (right (ensure-single-float-array right)))
    (vector-add-into (make-array (length left) :element-type 'single-float)
                     left
                     right)))

(defun vector-scale-into (dest vector scale)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (unless (= (length dest) (length vector))
    (error "VECTOR-SCALE destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (let ((scale (coerce scale 'single-float)))
    (declare (single-float scale))
    (dotimes (index (length vector) dest)
      (declare (fixnum index))
      (setf (aref dest index)
            (* (aref vector index) scale)))))

(defun vector-scale (vector scale)
  (let ((vector (ensure-single-float-array vector)))
    (vector-scale-into (make-array (length vector) :element-type 'single-float)
                       vector
                       scale)))

(defun vector-elementwise-multiply-into (dest left right)
  (declare (optimize (speed 3) (safety 2))
           (type (array single-float (*)) dest left right))
  (unless (= (length left) (length right))
    (error "VECTOR-ELEMENTWISE-MULTIPLY requires vectors of equal length."))
  (unless (= (length dest) (length left))
    (error "VECTOR-ELEMENTWISE-MULTIPLY destination length ~d does not match operand length ~d."
           (length dest)
           (length left)))
  (dotimes (index (length left) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (* (aref left index) (aref right index)))))

(defun vector-elementwise-multiply (left right)
  (let ((left (ensure-single-float-array left))
        (right (ensure-single-float-array right)))
    (vector-elementwise-multiply-into
     (make-array (length left) :element-type 'single-float)
     left
     right)))

(defun dot-product (left right)
  (declare (type (vector single-float) left right))
  (unless (= (length left) (length right))
    (error "DOT-PRODUCT requires vectors of equal length."))
  (let ((sum 0.0f0))
    (declare (single-float sum)
             (optimize (speed 3) (safety 0)))
    (dotimes (index (length left) (coerce sum 'single-float))
      (declare (fixnum index))
      (incf sum (* (aref left index) (aref right index))))))

(defun forged-dot-product (left right)
  "A highly optimized dot-product specialized for forged complex-vectors.
It extracts the underlying simple arrays once before entering the loop to eliminate all runtime dispatch overhead."
  (declare (type (vector single-float) left right))
  (let ((left-simple (if (typep left 'simple-array) left (sb-kernel:%array-data left)))
        (right-simple (if (typep right 'simple-array) right (sb-kernel:%array-data right))))
    (declare (type (simple-array single-float (*)) left-simple right-simple))
    (unless (= (length left-simple) (length right-simple))
      (error "FORGED-DOT-PRODUCT requires vectors of equal length."))
    (let ((sum 0.0f0))
      (declare (single-float sum)
               (optimize (speed 3) (safety 0)))
      (dotimes (index (length left-simple) (coerce sum 'single-float))
        (declare (fixnum index))
        (incf sum (* (aref left-simple index) (aref right-simple index)))))))

(defun split-vector-into-chunks (vector chunk-count)
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
  (unless (zerop (mod (length vector) chunk-count))
    (error "Vector length ~d is not divisible by chunk count ~d."
           (length vector)
           chunk-count))
  (let ((chunk-size (/ (length vector) chunk-count))
        (chunks '()))
    (declare (fixnum chunk-size))
    (dotimes (chunk-index chunk-count (nreverse chunks))
      (declare (fixnum chunk-index))
      (let ((offset (* chunk-index chunk-size)))
        (declare (fixnum offset))
        (push (subseq vector offset (+ offset chunk-size)) chunks)))))

(defun join-vector-chunks-into (dest chunks)
  (let* ((chunk-count (length chunks))
         (chunk-size (if (plusp chunk-count) (length (elt chunks 0)) 0)))
    (unless (= (length dest) (* chunk-count chunk-size))
      (error "JOIN-VECTOR-CHUNKS destination length ~d does not match total chunk size ~d."
             (length dest)
             (* chunk-count chunk-size)))
    (dotimes (chunk-index chunk-count)
      (declare (fixnum chunk-index))
      (let ((chunk (elt chunks chunk-index)))
        (unless (= (length chunk) chunk-size)
          (error "JOIN-VECTOR-CHUNKS requires equally sized chunks."))
        (dotimes (index chunk-size)
          (declare (fixnum index))
          (setf (aref dest (+ (* chunk-index chunk-size) index))
                (aref chunk index)))))
    dest))

(defun join-vector-chunks (chunks)
  (let* ((chunk-count (length chunks))
         (chunk-size (if (plusp chunk-count) (length (elt chunks 0)) 0)))
    (join-vector-chunks-into
     (make-array (* chunk-count chunk-size) :element-type 'single-float)
     chunks)))

(defun rms-norm-unweighted-into (dest vector &key (epsilon 1.0e-6))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (let ((length (length vector)))
    (unless (= (length dest) length)
      (error "RMS-NORM-UNWEIGHTED destination length ~d does not match vector length ~d."
             (length dest)
             length))
    (let* ((epsilon (coerce epsilon 'single-float))
           (mean-square (/ (sum-square-elements vector) length))
           (scale (/ (sqrt (+ mean-square epsilon)))))
      (declare (single-float epsilon mean-square scale)
               (fixnum length))
      (dotimes (index length dest)
        (declare (fixnum index))
        (setf (aref dest index)
              (* (aref vector index) scale))))))

(defun rms-norm-unweighted (vector &key (epsilon 1.0e-6))
  (let ((vector (ensure-single-float-array vector)))
    (rms-norm-unweighted-into (make-array (length vector) :element-type 'single-float)
                              vector
                              :epsilon epsilon)))

(defun gelu (value)
  (let* ((x (coerce value 'double-float))
         (inner (* 0.7978845608028654d0
                   (+ x (* 0.044715d0 x x x)))))
    (coerce (* 0.5d0 x (+ 1.0d0 (tanh inner))) 'single-float)))

(defun apply-gelu-into (dest vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (unless (= (length dest) (length vector))
    (error "APPLY-GELU destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (dotimes (index (length vector) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (gelu (aref vector index)))))

(defun apply-gelu (vector)
  (let ((vector (ensure-single-float-array vector)))
    (apply-gelu-into (make-array (length vector) :element-type 'single-float)
                     vector)))

(defun normalize-vector-chunks-into (dest vector chunk-count weight &key (epsilon 1.0e-6))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector weight)
           (fixnum chunk-count))
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
  (unless (= (length dest) (length vector))
    (error "NORMALIZE-VECTOR-CHUNKS destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (unless (zerop (mod (length vector) chunk-count))
    (error "Vector length ~d is not divisible by chunk count ~d."
           (length vector)
           chunk-count))
  (let ((chunk-size (/ (length vector) chunk-count))
        (epsilon (coerce epsilon 'single-float)))
    (declare (fixnum chunk-size)
             (single-float epsilon))
    (unless (= (length weight) chunk-size)
      (error "Weight length ~d does not match chunk size ~d."
             (length weight)
             chunk-size))
    (dotimes (chunk-index chunk-count dest)
      (declare (fixnum chunk-index))
      (let* ((start (* chunk-index chunk-size))
             (mean-square (/ (sum-square-elements-range vector start chunk-size)
                             chunk-size))
             (scale (/ (sqrt (+ mean-square epsilon)))))
        (declare (fixnum start)
                 (single-float mean-square scale))
        (dotimes (index chunk-size)
          (declare (fixnum index))
          (setf (aref dest (+ start index))
                (* (aref vector (+ start index))
                   (aref weight index)
                   scale)))))))

(defun normalize-vector-chunks (vector chunk-count weight &key (epsilon 1.0e-6))
  (let ((vector (ensure-single-float-array vector))
        (weight (ensure-single-float-array weight)))
    (normalize-vector-chunks-into
     (make-array (length vector) :element-type 'single-float)
     vector
     chunk-count
     weight
     :epsilon epsilon)))

(defun apply-rope-head (head position rope-dimension theta-base &optional freq-factors)
  (let ((result (copy-seq head)))
    (apply-rope-head-in-place result
                              position
                              rope-dimension
                              theta-base
                              freq-factors)))

(defun apply-rope-head-in-place (head position rope-dimension theta-base &optional freq-factors)
  (declare (optimize (speed 3) (safety 2))
           (type (array single-float (*)) head)
           (fixnum rope-dimension))
  (let* ((factor-limit (if freq-factors
                           (* 2 (length freq-factors))
                           rope-dimension))
         (effective-dimension (min rope-dimension
                                   factor-limit
                                   (length head)))
         (even-dimension (* 2 (floor effective-dimension 2)))
         (pair-count (/ even-dimension 2)))
    (declare (fixnum factor-limit effective-dimension even-dimension pair-count))
    (dotimes (pair-index pair-count head)
      (declare (fixnum pair-index))
      (let* ((index (* pair-index 2))
             (factor (if (and freq-factors (< pair-index (length freq-factors)))
                         (coerce (aref freq-factors pair-index) 'double-float)
                         1.0d0))
             (angle (if (> factor 1.0d20)
                        0.0d0
                        (/ position
                           (* factor
                              (expt theta-base
                                    (/ (* 2 pair-index) even-dimension))))))
             (cos-angle (cos angle))
             (sin-angle (sin angle))
             (x0 (aref head index))
             (x1 (aref head (1+ index))))
        (declare (fixnum index)
                 (double-float factor angle cos-angle sin-angle)
                 (single-float x0 x1))
        (setf (aref head index)
              (coerce (- (* x0 cos-angle) (* x1 sin-angle)) 'single-float))
        (setf (aref head (1+ index))
              (coerce (+ (* x0 sin-angle) (* x1 cos-angle)) 'single-float))))))

(defun make-layer-tensor-name (layer-index suffix)
  (format nil "blk.~d.~a.weight" layer-index suffix))

(defun make-optional-layer-tensor-name (layer-index suffix)
  (format nil "blk.~d.~a.weight" layer-index suffix))

(defun gguf-model-layer-uses-swa-p (model layer-index)
  (let ((pattern (gguf-model-sliding-pattern model)))
    (and pattern (nth layer-index pattern))))

(defun gguf-model-kv-layer-count (model)
  (let ((shared-kv-layers (or (gguf-model-shared-kv-layers model) 0)))
    (declare (fixnum shared-kv-layers))
    (- (gguf-model-layer-count model) shared-kv-layers)))

(defun gguf-model-layer-kv-source-index (model layer-index)
  (let ((kv-layer-count (gguf-model-kv-layer-count model)))
    (declare (fixnum kv-layer-count layer-index))
    (if (< layer-index kv-layer-count)
        layer-index
        (let ((source-index (- kv-layer-count
                               (if (gguf-model-layer-uses-swa-p model layer-index)
                                   2
                                   1))))
          (declare (fixnum source-index))
          (when (minusp source-index)
            (error "Shared-KV source index underflow for layer ~d with kv-layer-count ~d."
                   layer-index
                   kv-layer-count))
          source-index))))

(defun gguf-model-cached-tensor (model tensor-name)
  (gethash tensor-name (gguf-model-tensor-cache model)))

(defun (setf gguf-model-cached-tensor) (value model tensor-name)
  (setf (gethash tensor-name (gguf-model-tensor-cache model))
        value))

(defun gguf-model-load-vector-tensor (model tensor-name)
  (or (gguf-model-cached-tensor model tensor-name)
      (let ((tensor-info (gguf-model-tensor-info model tensor-name t)))
        (unless (= 1 (length (getf tensor-info :dimensions)))
          (error "Tensor ~s is not a vector tensor." tensor-name))
        (setf (gguf-model-cached-tensor model tensor-name)
              (load-gguf-tensor (gguf-model-mapping model) tensor-info)))))

(defun gguf-model-load-scalar-tensor (model tensor-name)
  (let ((tensor (gguf-model-load-vector-tensor model tensor-name)))
    (unless (= 1 (length tensor))
      (error "Tensor ~s is not a scalar tensor." tensor-name))
    (aref tensor 0)))

(defun tensor-row-pointer (mapping tensor-info row-index)
  (let ((row-count (tensor-row-count tensor-info)))
    (unless (and (<= 0 row-index) (< row-index row-count))
      (error "Row index ~d is out of range for tensor ~s with ~d rows."
             row-index
             (getf tensor-info :name)
             row-count))
    (cffi:inc-pointer mapping
                      (+ (getf tensor-info :data-offset)
                         (* row-index (tensor-row-byte-size tensor-info))))))

(defun load-gguf-tensor-row (mapping tensor-info row-index)
  (let* ((column-count (tensor-column-count tensor-info))
         (row-pointer (tensor-row-pointer mapping tensor-info row-index)))
    (case (getf tensor-info :type-tag)
      (#.+ggml-type-f32+ (load-f32-tensor row-pointer column-count))
      (#.+ggml-type-f16+ (load-f16-tensor row-pointer column-count))
      (#.+ggml-type-bf16+ (load-bf16-tensor row-pointer column-count))
      (#.+ggml-type-q4-k+ (dequantize-q4-k-m row-pointer column-count))
      (#.+ggml-type-q6-k+ (dequantize-q6-k row-pointer column-count))
      (otherwise
       (error "Tensor ~s has unsupported row-loading type tag ~a."
              (getf tensor-info :name)
              (getf tensor-info :type-tag))))))

(defun load-gguf-tensor-row-into (dest mapping tensor-info row-index)
  (let* ((column-count (tensor-column-count tensor-info))
         (row-pointer (tensor-row-pointer mapping tensor-info row-index)))
    (unless (= (length dest) column-count)
      (error "Destination length ~d does not match tensor row width ~d for tensor ~s."
             (length dest)
             column-count
             (getf tensor-info :name)))
    (case (getf tensor-info :type-tag)
      (#.+ggml-type-f32+ (load-f32-tensor-into dest row-pointer column-count))
      (#.+ggml-type-f16+ (load-f16-tensor-into dest row-pointer column-count))
      (#.+ggml-type-bf16+ (load-bf16-tensor-into dest row-pointer column-count))
      (otherwise
       (replace dest (load-gguf-tensor-row mapping tensor-info row-index))))
    dest))

(defun dot-product-with-f16-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (let ((sum 0.0f0))
    (declare (single-float sum))
    (dotimes (index element-count (the single-float sum))
      (declare (fixnum index)
               (optimize (speed 3) (safety 0)))
      (incf sum (* (aref vector index)
                   (read-fp16-le pointer (+ row-offset (* index 2))))))))

(defun dot-product-with-f16-tensor-row (row-pointer vector element-count)
  (dot-product-with-f16-tensor-data row-pointer 0 vector element-count))

(defun dot-product-with-bf16-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (let ((sum 0.0f0))
    (declare (single-float sum))
    (dotimes (index element-count (the single-float sum))
      (declare (fixnum index))
      (incf sum (* (aref vector index)
                   (read-bf16-le pointer (+ row-offset (* index 2))))))))

(defun dot-product-with-f32-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (let ((sum 0.0f0)
        (row-float-offset (ash row-offset -2)))
    (declare (single-float sum)
             (fixnum row-float-offset))
    (dotimes (index element-count (the single-float sum))
      (declare (fixnum index))
      (incf sum (* (aref vector index)
                   (cffi:mem-aref pointer :float (+ row-float-offset index)))))))

(declaim (ftype (function (t fixnum fixnum) (values fixnum fixnum &optional))
                get-scale-min-k4-at)
         (ftype (function (t fixnum (simple-array single-float (*)) fixnum
                            single-float single-float single-float single-float)
                          single-float)
                dot-product-with-k-m-tensor-body)
         (inline get-scale-min-k4-at dot-product-with-k-m-tensor-body))

(defun get-scale-min-k4-at (pointer scale-base index)
  (declare (optimize (speed 3) (safety 0))
          (fixnum scale-base index))
  (let ((byte0 (cffi:mem-aref pointer :unsigned-char (+ scale-base index)))
        (byte4 (cffi:mem-aref pointer :unsigned-char (+ scale-base 4 index))))
    (declare (fixnum byte0 byte4))
    (if (< index 4)
        (values (logand byte0 63)
               (logand byte4 63))
        (values (logior (logand byte4 #x0F)
                       (ash (ash (logand (cffi:mem-aref pointer
                                                        :unsigned-char
                                                        (+ scale-base (- index 4)))
                                         #xC0)
                                 -6)
                            4))
               (logior (ash byte4 -4)
                       (ash (ash (logand (cffi:mem-aref pointer
                                                        :unsigned-char
                                                        (+ scale-base index))
                                         #xC0)
                                 -6)
                            4))))))

(defun dot-product-with-k-m-tensor-body (pointer qs-base vector vector-base
                                        delta0 offset0 delta1 offset1)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) vector)
          (fixnum qs-base vector-base)
          (single-float delta0 offset0 delta1 offset1))
  (let ((sum 0.0f0)
        (qs-index qs-base)
        (low-index vector-base)
        (high-index (+ vector-base 32))
        (remaining 32))
    (declare (single-float sum)
            (fixnum qs-index low-index high-index remaining))
    (do ()
        ((zerop remaining) (the single-float sum))
      (let* ((packed (cffi:mem-aref pointer :unsigned-char qs-index))
            (low-quant (logand packed #x0F))
            (high-quant (ash packed -4)))
        (declare (fixnum packed low-quant high-quant))
        (incf sum (* (aref vector low-index)
                    (- (* delta0 low-quant) offset0)))
        (incf sum (* (aref vector high-index)
                    (- (* delta1 high-quant) offset1))))
      (incf qs-index)
      (incf low-index)
      (incf high-index)
      (decf remaining))))

(defun dot-product-with-q4-k-m-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) vector)
          (fixnum row-offset element-count))
  (unless (zerop (mod element-count +qk-k+))
    (error "Q4_K_M dot product requires ELEMENT-COUNT to be a multiple of ~d."
          +qk-k+))
  (let ((sum 0.0f0)
       (block-size (+ 4 +k-scale-size+ (/ +qk-k+ 2)))
       (block-count (/ element-count +qk-k+)))
    (declare (single-float sum)
            (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float sum))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
            (d (read-fp16-le pointer block-offset))
            (dmin (read-fp16-le pointer (+ block-offset 2)))
            (scale-base (+ block-offset 4))
            (qs-base (+ block-offset 4 +k-scale-size+))
            (vector-base (* block-index +qk-k+)))
       (declare (single-float d dmin)
                (fixnum scale-base qs-base vector-base))
       (multiple-value-bind (scale0 min0)
           (get-scale-min-k4-at pointer scale-base 0)
         (multiple-value-bind (scale1 min1)
             (get-scale-min-k4-at pointer scale-base 1)
           (let ((delta0 (* d scale0))
                 (offset0 (* dmin min0))
                 (delta1 (* d scale1))
                 (offset1 (* dmin min1)))
             (declare (single-float delta0 offset0 delta1 offset1))
             (incf sum
                   (dot-product-with-k-m-tensor-body pointer
                                                     qs-base
                                                     vector
                                                     vector-base
                                                     delta0
                                                     offset0
                                                     delta1
                                                     offset1)))))
       (multiple-value-bind (scale0 min0)
           (get-scale-min-k4-at pointer scale-base 2)
         (multiple-value-bind (scale1 min1)
             (get-scale-min-k4-at pointer scale-base 3)
           (let ((delta0 (* d scale0))
                 (offset0 (* dmin min0))
                 (delta1 (* d scale1))
                 (offset1 (* dmin min1)))
             (declare (single-float delta0 offset0 delta1 offset1))
             (incf sum
                   (dot-product-with-k-m-tensor-body pointer
                                                     (+ qs-base 32)
                                                     vector
                                                     (+ vector-base 64)
                                                     delta0
                                                     offset0
                                                     delta1
                                                     offset1)))))
       (multiple-value-bind (scale0 min0)
           (get-scale-min-k4-at pointer scale-base 4)
         (multiple-value-bind (scale1 min1)
             (get-scale-min-k4-at pointer scale-base 5)
           (let ((delta0 (* d scale0))
                 (offset0 (* dmin min0))
                 (delta1 (* d scale1))
                 (offset1 (* dmin min1)))
             (declare (single-float delta0 offset0 delta1 offset1))
             (incf sum
                   (dot-product-with-k-m-tensor-body pointer
                                                     (+ qs-base 64)
                                                     vector
                                                     (+ vector-base 128)
                                                     delta0
                                                     offset0
                                                     delta1
                                                     offset1)))))
       (multiple-value-bind (scale0 min0)
           (get-scale-min-k4-at pointer scale-base 6)
         (multiple-value-bind (scale1 min1)
             (get-scale-min-k4-at pointer scale-base 7)
           (let ((delta0 (* d scale0))
                 (offset0 (* dmin min0))
                 (delta1 (* d scale1))
                 (offset1 (* dmin min1)))
             (declare (single-float delta0 offset0 delta1 offset1))
             (incf sum
                   (dot-product-with-k-m-tensor-body pointer
                                                     (+ qs-base 96)
                                                     vector
                                                     (+ vector-base 192)
                                                     delta0
                                                     offset0
                                                     delta1
                                                     offset1)))))))))

(defun dot-product-with-q4-k-m-tensor-row (row-pointer vector element-count)
  (dot-product-with-q4-k-m-tensor-data row-pointer 0 vector element-count))

(defun dot-product-with-q6-k-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (unless (zerop (mod element-count +qk-k+))
    (error "Q6_K dot product requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let ((sum 0.0f0)
        (block-size (+ 2 +q6-k-scale-count+ (* 3 (/ +qk-k+ 4))))
        (block-count (/ element-count +qk-k+)))
    (declare (single-float sum)
             (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float sum))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
             (d (read-fp16-le pointer (+ block-offset (- block-size 2))))
             (ql-base block-offset)
             (qh-base (+ block-offset (/ +qk-k+ 2)))
             (scale-base (+ qh-base (/ +qk-k+ 4)))
             (vector-base (* block-index +qk-k+)))
        (declare (single-float d)
                 (fixnum ql-base qh-base scale-base vector-base))
        (dotimes (chunk-index (/ +qk-k+ 128))
          (declare (fixnum chunk-index))
          (let* ((chunk-ql-base (+ ql-base (* chunk-index 64)))
                 (chunk-qh-base (+ qh-base (* chunk-index 32)))
                 (chunk-scale-base (+ scale-base (* chunk-index 8)))
                 (chunk-vector-base (+ vector-base (* chunk-index 128)))
          (delta1 (* d (read-s8 pointer (+ chunk-scale-base 0))))
          (delta2 (* d (read-s8 pointer (+ chunk-scale-base 2))))
          (delta3 (* d (read-s8 pointer (+ chunk-scale-base 4))))
          (delta4 (* d (read-s8 pointer (+ chunk-scale-base 6)))))
            (declare (fixnum chunk-ql-base chunk-qh-base chunk-scale-base chunk-vector-base)
                     (single-float delta1 delta2 delta3 delta4))
            (dotimes (lane 16)
              (declare (fixnum lane))
              (let* ((packed-low (cffi:mem-aref pointer :unsigned-char (+ chunk-ql-base lane)))
              (packed-high (cffi:mem-aref pointer :unsigned-char (+ chunk-ql-base 32 lane)))
              (packed-top (cffi:mem-aref pointer :unsigned-char (+ chunk-qh-base lane)))
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
                     (index1 (+ chunk-vector-base lane))
                     (index2 (+ index1 32))
                     (index3 (+ index1 64))
                     (index4 (+ index1 96)))
                (declare (fixnum packed-low packed-high packed-top)
                         (fixnum q1 q2 q3 q4 index1 index2 index3 index4))
                (incf sum (* (aref vector index1) (* delta1 q1)))
                (incf sum (* (aref vector index2) (* delta2 q2)))
                (incf sum (* (aref vector index3) (* delta3 q3)))
                (incf sum (* (aref vector index4) (* delta4 q4)))))
            (let ((delta1 (* d (read-s8 pointer (+ chunk-scale-base 1))))
                  (delta2 (* d (read-s8 pointer (+ chunk-scale-base 3))))
                  (delta3 (* d (read-s8 pointer (+ chunk-scale-base 5))))
                  (delta4 (* d (read-s8 pointer (+ chunk-scale-base 7)))))
              (declare (single-float delta1 delta2 delta3 delta4))
              (dotimes (lane-offset 16)
                (declare (fixnum lane-offset))
                (let* ((lane (+ 16 lane-offset))
                       (packed-low (cffi:mem-aref pointer :unsigned-char (+ chunk-ql-base lane)))
                       (packed-high (cffi:mem-aref pointer :unsigned-char (+ chunk-ql-base 32 lane)))
                       (packed-top (cffi:mem-aref pointer :unsigned-char (+ chunk-qh-base lane)))
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
                       (index1 (+ chunk-vector-base lane))
                       (index2 (+ index1 32))
                       (index3 (+ index1 64))
                       (index4 (+ index1 96)))
                  (declare (fixnum lane packed-low packed-high packed-top)
                           (fixnum q1 q2 q3 q4 index1 index2 index3 index4))
                  (incf sum (* (aref vector index1) (* delta1 q1)))
                  (incf sum (* (aref vector index2) (* delta2 q2)))
                  (incf sum (* (aref vector index3) (* delta3 q3)))
                  (incf sum (* (aref vector index4) (* delta4 q4))))))))))))

(defun dot-product-with-q6-k-tensor-row (row-pointer vector element-count)
  (dot-product-with-q6-k-tensor-data row-pointer 0 vector element-count))

(defun dot-product-with-tensor-row (mapping tensor-info row-index vector)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) vector)
          (fixnum row-index))
  (let* ((column-count (tensor-column-count tensor-info))
        (type-tag (getf tensor-info :type-tag))
        (row-offset (+ (getf tensor-info :data-offset)
                       (* row-index (tensor-row-byte-size tensor-info)))))
    (declare (fixnum column-count type-tag row-offset))
    (unless (= column-count (length vector))
      (error "Tensor row width ~d does not match vector length ~d for tensor ~s."
            column-count
            (length vector)
            (getf tensor-info :name)))
    (case type-tag
      (#.+ggml-type-f32+
       (dot-product-with-f32-tensor-data mapping row-offset vector column-count))
      (#.+ggml-type-f16+
       (dot-product-with-f16-tensor-data mapping row-offset vector column-count))
      (#.+ggml-type-bf16+
       (dot-product-with-bf16-tensor-data mapping row-offset vector column-count))
      (#.+ggml-type-q4-k+
       (dot-product-with-q4-k-m-tensor-data mapping row-offset vector column-count))
      (#.+ggml-type-q6-k+
       (dot-product-with-q6-k-tensor-data mapping row-offset vector column-count))
      (otherwise
       (dot-product vector
                    (load-gguf-tensor-row mapping tensor-info row-index))))))

(defun gguf-model-matrix-vector-multiply-into (dest model tensor-name vector)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) dest vector))
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
        (mapping (gguf-model-mapping model))
        (row-count (tensor-row-count tensor-info))
        (column-count (tensor-column-count tensor-info))
        (type-tag (getf tensor-info :type-tag))
        (row-byte-size (tensor-row-byte-size tensor-info))
        (row-offset (getf tensor-info :data-offset)))
    (declare (fixnum row-count column-count type-tag row-byte-size row-offset))
    (unless (= (length dest) row-count)
      (error "Destination length ~d does not match row count ~d for tensor ~s."
            (length dest)
            row-count
            tensor-name))
    (unless (= (length vector) column-count)
      (error "Vector length ~d does not match tensor row width ~d for tensor ~s."
            (length vector)
            column-count
            tensor-name))
    (case type-tag
      (#.+ggml-type-f32+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-f32-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-f16+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-f16-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-bf16+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-bf16-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-q4-k+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-q4-k-m-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-q6-k+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-q6-k-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (otherwise
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-tensor-row mapping tensor-info row-index vector)))))))

(defun gguf-model-matrix-vector-multiply (model tensor-name vector)
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (row-count (tensor-row-count tensor-info)))
    (gguf-model-matrix-vector-multiply-into
     (make-array row-count :element-type 'single-float)
     model
     tensor-name
     vector)))

(defun gguf-model-token-row (model tensor-name token-id)
  (let ((tensor-info (gguf-model-tensor-info model tensor-name t)))
    (load-gguf-tensor-row (gguf-model-mapping model) tensor-info token-id)))

(defun gguf-model-token-row-into (dest model tensor-name token-id)
  (let ((tensor-info (gguf-model-tensor-info model tensor-name t)))
    (load-gguf-tensor-row-into dest
                               (gguf-model-mapping model)
                               tensor-info
                               token-id)))

(defun slice-vector-chunk (vector chunk-size chunk-index)
  (let ((start (* chunk-index chunk-size)))
    (subseq vector start (+ start chunk-size))))

(defun scale-vector-in-place-copy (vector scale)
  (vector-scale vector scale))

(defun softcap-logits (logits cap)
  (if (or (null cap) (zerop cap))
      logits
      (let* ((length (length logits))
             (result (make-array length :element-type 'single-float)))
        (dotimes (index length result)
          (setf (aref result index)
                (coerce (* cap (tanh (/ (aref logits index) cap)))
                        'single-float))))))

(defun ensure-gemma4-layer-cache (kv-cache layer-index)
  (or (gethash layer-index kv-cache)
      (setf (gethash layer-index kv-cache)
            (list :keys (make-array 0 :adjustable t :fill-pointer 0)
                  :values (make-array 0 :adjustable t :fill-pointer 0)))))

(defstruct compute-buffer
  (vectors (make-hash-table :test #'eq))
  (chunk-views (make-hash-table :test #'eq)))

(defun compute-buffer-vector (buffer key length)
  (let ((vector (gethash key (compute-buffer-vectors buffer))))
    (unless (and vector (= (length vector) length))
      (setf vector (make-array length :element-type 'single-float)
            (gethash key (compute-buffer-vectors buffer)) vector))
    vector))

(defun compute-buffer-chunks (buffer key backing-vector chunk-count)
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
  (unless (zerop (mod (length backing-vector) chunk-count))
    (error "Vector length ~d is not divisible by chunk count ~d."
           (length backing-vector)
           chunk-count))
  (let ((entry (gethash key (compute-buffer-chunk-views buffer))))
    (if (and entry
             (eq (getf entry :backing-vector) backing-vector)
             (= (getf entry :chunk-count) chunk-count))
        (getf entry :views)
        (let* ((chunk-size (/ (length backing-vector) chunk-count))
               (views (make-array chunk-count)))
          (dotimes (index chunk-count)
            (setf (aref views index)
                  (make-array chunk-size
                              :element-type 'single-float
                              :displaced-to backing-vector
                              :displaced-index-offset (* index chunk-size))))
          (setf (gethash key (compute-buffer-chunk-views buffer))
                (list :backing-vector backing-vector
                      :chunk-count chunk-count
                      :views views))
          views))))

(defun copy-head-vectors (heads)
  (let* ((head-count (length heads))
         (copies (make-array head-count)))
    (dotimes (head-index head-count copies)
      (declare (fixnum head-index))
      (let* ((head (aref heads head-index))
            (copy (make-array (length head) :element-type 'single-float)))
        (replace copy head)
        (setf (aref copies head-index) copy)))))

(defun gemma4-cache-append (kv-cache layer-index key-heads value-heads)
  (let* ((layer-cache (ensure-gemma4-layer-cache kv-cache layer-index))
         (keys (getf layer-cache :keys))
         (values (getf layer-cache :values)))
    (vector-push-extend (copy-head-vectors key-heads) keys)
    (vector-push-extend (copy-head-vectors value-heads) values)
    layer-cache))

(defun softmax-into (dest logits)
  (declare (optimize (speed 3) (safety 2))
          (type (simple-array single-float (*)) dest logits))
  (unless (= (length dest) (length logits))
    (error "SOFTMAX destination length ~d does not match logits length ~d."
          (length dest)
          (length logits)))
  (let ((max-logit (max-single-float-element logits))
        (sum-exps 0.0f0))
    (declare (single-float max-logit sum-exps))
    (dotimes (index (length logits))
      (declare (fixnum index))
      (let ((value (coerce (exp (- (aref logits index) max-logit)) 'single-float)))
        (declare (single-float value))
        (setf (aref dest index) value)
        (incf sum-exps value)))
    (dotimes (index (length dest) dest)
      (declare (fixnum index))
      (setf (aref dest index)
           (coerce (/ (aref dest index) sum-exps) 'single-float)))))

(defun weighted-sum-head-into (dest probabilities per-position-values window-start kv-head-index)
  (declare (optimize (speed 3) (safety 2))
          (type (array single-float (*)) dest)
          (type (simple-array single-float (*)) probabilities)
          (fixnum window-start kv-head-index))
  (fill dest 0.0f0)
  (dotimes (score-index (length probabilities))
    (declare (fixnum score-index))
    (let* ((score (aref probabilities score-index))
           (cache-index (+ window-start score-index))
           (value-head (aref (aref per-position-values cache-index)
                             kv-head-index)))
      (declare (type (array single-float (*)) value-head)
               (single-float score)
               (fixnum cache-index))
      (dotimes (element-index (length dest))
        (declare (fixnum element-index))
        (incf (aref dest element-index)
              (* score (aref value-head element-index))))))
  dest)

(defun weighted-sum-heads (probabilities per-position-values kv-head-index)
  (let* ((head-length (length (aref (aref per-position-values 0) kv-head-index)))
         (result (make-array head-length :element-type 'single-float)))
    (weighted-sum-head-into result probabilities per-position-values 0 kv-head-index)))

(defun compute-gemma4-attention-into (dest compute-buffer model layer-index cache-layer-index
                                      position q-heads k-heads v-heads kv-cache)
  (let* ((layer-cache (if k-heads
                          (gemma4-cache-append kv-cache cache-layer-index
                                              k-heads
                                              v-heads)
                          (gethash cache-layer-index kv-cache)))
         (keys (getf layer-cache :keys))
         (values (getf layer-cache :values))
         (window-start (if (gguf-model-layer-uses-swa-p model layer-index)
                          (max 0 (1+ (- position (gguf-model-sliding-window model))))
                          0))
         (cached-key-count (- (length keys) window-start))
         (dest-heads (compute-buffer-chunks compute-buffer :attention-context-heads
                                           dest
                                           (length q-heads)))
         (scores (compute-buffer-vector compute-buffer :attention-scores cached-key-count))
         (probabilities (compute-buffer-vector compute-buffer
                                              :attention-probabilities
                                              cached-key-count)))
    (unless layer-cache
      (error "Layer ~d reuses KV cache layer ~d, but that cache is empty."
             layer-index
             cache-layer-index))
    (unless (plusp cached-key-count)
      (error "Layer ~d has no cached keys available for attention."
             layer-index))
    (let* ((kv-head-count (if k-heads
                              (length k-heads)
                              (length (aref keys 0))))
           (kv-group-size (/ (length q-heads) kv-head-count)))
      (declare (fixnum kv-head-count kv-group-size))
      (dotimes (q-index (length q-heads))
        (declare (fixnum q-index))
        (let* ((q-head (aref q-heads q-index))
               (dest-head (aref dest-heads q-index))
               (kv-head-index (floor q-index kv-group-size)))
          (dotimes (score-index cached-key-count)
            (declare (fixnum score-index))
            (setf (aref scores score-index)
                  (dot-product q-head
                               (aref (aref keys (+ window-start score-index))
                                     kv-head-index))))
          (softmax-into probabilities scores)
          (weighted-sum-head-into dest-head probabilities values window-start kv-head-index))))
    dest))

(defun compute-gemma4-attention (model layer-index position q-heads k-heads v-heads kv-cache)
  (let* ((head-length (length (aref q-heads 0)))
         (result (make-array (* (length q-heads) head-length)
                            :element-type 'single-float)))
    (compute-gemma4-attention-into result
                                  (make-compute-buffer)
                                  model
                                  layer-index
                                  layer-index
                                  position
                                  q-heads
                                  k-heads
                                  v-heads
                                  kv-cache)))

(defun maybe-layer-output-scale (model layer-index vector)
  (let ((tensor-name (make-optional-layer-tensor-name layer-index "layer_output_scale"))
        (tensor-info (gguf-model-tensor-info model
                                             (make-optional-layer-tensor-name
                                              layer-index
                                              "layer_output_scale")
                                             nil)))
    (if tensor-info
        (vector-scale-into vector
                           vector
                           (gguf-model-load-scalar-tensor model tensor-name))
        vector)))

(defun load-gemma4-model (mapping kv-pairs tensor-infos)
  (let ((architecture (gguf-kv-value kv-pairs "general.architecture")))
    (unless (string= architecture "gemma4")
      (error "LOAD-GEMMA4-MODEL only supports general.architecture = \"gemma4\", got ~s."
             architecture))
    (let ((tensor-info-table (make-tensor-info-table tensor-infos)))
      (make-gguf-model
       :mapping mapping
       :kv-pairs kv-pairs
       :tensor-infos tensor-infos
       :tensor-info-table tensor-info-table
       :tensor-cache (make-hash-table :test #'equal)
       :architecture architecture
       :hidden-size (gguf-kv-value kv-pairs "gemma4.embedding_length")
       :layer-count (gguf-kv-value kv-pairs "gemma4.block_count")
       :head-count (gguf-kv-value kv-pairs "gemma4.attention.head_count")
       :kv-head-count (gguf-kv-value kv-pairs "gemma4.attention.head_count_kv")
       :ffn-size (gguf-kv-value kv-pairs "gemma4.feed_forward_length")
       :norm-epsilon (gguf-kv-value kv-pairs "gemma4.attention.layer_norm_rms_epsilon")
       :sliding-window (gguf-kv-value kv-pairs "gemma4.attention.sliding_window")
       :sliding-pattern (gguf-kv-value-or-nil kv-pairs "gemma4.attention.sliding_window_pattern")
       :rope-base (gguf-kv-value kv-pairs "gemma4.rope.freq_base")
       :rope-base-swa (gguf-kv-value kv-pairs "gemma4.rope.freq_base_swa")
       :rope-dimension (gguf-kv-value kv-pairs "gemma4.rope.dimension_count")
       :rope-dimension-swa (gguf-kv-value kv-pairs "gemma4.rope.dimension_count_swa")
       :shared-kv-layers (or (gguf-kv-value-or-nil kv-pairs "gemma4.attention.shared_kv_layers")
                             0)
       :per-layer-embedding-size
       (or (gguf-kv-value-or-nil kv-pairs "gemma4.embedding_length_per_layer_input")
           0)
       :final-logit-softcap (gguf-kv-value-or-nil kv-pairs "gemma4.final_logit_softcapping")
       :output-tensor-name (if (gethash "output.weight" tensor-info-table)
                               "output.weight"
                               "token_embd.weight")))))

(defun build-gemma4-per-layer-inputs (model token-id input-embedding compute-buffer)
  (let ((per-layer-size (gguf-model-per-layer-embedding-size model)))
    (when (plusp per-layer-size)
      (let* ((layer-count (gguf-model-layer-count model))
             (total-size (* per-layer-size layer-count))
             (token-embedding
              (compute-buffer-vector compute-buffer :per-layer-token-embedding total-size))
             (model-projection
              (compute-buffer-vector compute-buffer :per-layer-model-projection total-size))
             (result
              (compute-buffer-vector compute-buffer :per-layer-inputs total-size))
             (projection-norm
              (gguf-model-load-vector-tensor model "per_layer_proj_norm.weight")))
        (gguf-model-token-row-into token-embedding
                                   model
                                   "per_layer_token_embd.weight"
                                   token-id)
        (vector-scale-into token-embedding token-embedding (sqrt per-layer-size))
        (gguf-model-matrix-vector-multiply-into model-projection
                                                model
                                                "per_layer_model_proj.weight"
                                                input-embedding)
        (vector-scale-into model-projection
                           model-projection
                           (/ (sqrt (gguf-model-hidden-size model))))
        (normalize-vector-chunks-into result
                                      model-projection
                                      layer-count
                                      projection-norm
                                      :epsilon (gguf-model-norm-epsilon model))
        (vector-add-into result token-embedding result)
        (vector-scale-into result result (/ (sqrt 2.0f0)))
        result))))

(defun make-gemma4-step-function (model)
  (let ((rope-factors (gguf-model-load-vector-tensor model "rope_freqs.weight"))
        (head-count (gguf-model-head-count model))
        (kv-head-count (gguf-model-kv-head-count model))
        (norm-epsilon (gguf-model-norm-epsilon model))
        (compute-buffer (make-compute-buffer)))
    (lambda (token-id position kv-cache)
      (let* ((hidden-size (gguf-model-hidden-size model))
             (input-embedding
              (compute-buffer-vector compute-buffer :input-embedding hidden-size))
             (x (compute-buffer-vector compute-buffer :x hidden-size))
             (per-layer-inputs nil))
        (gguf-model-token-row-into input-embedding model "token_embd.weight" token-id)
        (vector-scale-into input-embedding
                           input-embedding
                           (sqrt hidden-size))
        (replace x input-embedding)
        (setf per-layer-inputs (build-gemma4-per-layer-inputs model
                                                              token-id
                                                              input-embedding
                                                              compute-buffer))
        (dotimes (layer-index (gguf-model-layer-count model))
          (let* ((attn-norm
                  (compute-buffer-vector compute-buffer :attn-norm hidden-size))
                 (q-length
                  (tensor-row-count
                   (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "attn_q")
                                           t)))
                 (cache-layer-index
                  (gguf-model-layer-kv-source-index model layer-index))
                 (uses-own-kv-p (= cache-layer-index layer-index))
                 (k-length
                  (when uses-own-kv-p
                    (tensor-row-count
                     (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "attn_k")
                                             t))))
                 (v-length
                  (when uses-own-kv-p
                    (tensor-row-count
                     (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "attn_v")
                                            t))))
                 (q (compute-buffer-vector compute-buffer :q q-length))
                 (k (and uses-own-kv-p
                         (compute-buffer-vector compute-buffer :k k-length)))
                 (v (and uses-own-kv-p
                         (compute-buffer-vector compute-buffer :v v-length)))
                 (q-heads nil)
                 (k-heads nil)
                 (v-heads nil)
                 (swa-p (gguf-model-layer-uses-swa-p model layer-index))
                 (rope-dimension (if swa-p
                                     (gguf-model-rope-dimension-swa model)
                                     (gguf-model-rope-dimension model)))
                 (rope-base (if swa-p
                                (gguf-model-rope-base-swa model)
                                (gguf-model-rope-base model)))
                 (rope-source (unless swa-p rope-factors))
                 (attention-context (compute-buffer-vector compute-buffer
                                                           :attention-context
                                                           q-length))
                 (attention-output (compute-buffer-vector compute-buffer
                                                          :attention-output
                                                          hidden-size))
                 (post-attention (compute-buffer-vector compute-buffer
                                                        :post-attention
                                                        hidden-size))
                 (ffn-input (compute-buffer-vector compute-buffer :ffn-input hidden-size))
                 (ffn-gate-length
                  (tensor-row-count
                   (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "ffn_gate")
                                           t)))
                 (ffn-up-length
                  (tensor-row-count
                   (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "ffn_up")
                                           t)))
                 (ffn-gate (compute-buffer-vector compute-buffer :ffn-gate ffn-gate-length))
                 (ffn-up (compute-buffer-vector compute-buffer :ffn-up ffn-up-length))
                 (ffn-down (compute-buffer-vector compute-buffer :ffn-down hidden-size))
                 (post-ffn (compute-buffer-vector compute-buffer :post-ffn hidden-size)))
            (rms-norm-into attn-norm
                           x
                           (gguf-model-load-vector-tensor
                            model
                            (make-layer-tensor-name layer-index "attn_norm"))
                           :epsilon norm-epsilon)
            (gguf-model-matrix-vector-multiply-into q
                                                    model
                                                    (make-layer-tensor-name layer-index "attn_q")
                                                    attn-norm)
            (when uses-own-kv-p
              (gguf-model-matrix-vector-multiply-into k
                                                      model
                                                      (make-layer-tensor-name layer-index "attn_k")
                                                      attn-norm)
              (gguf-model-matrix-vector-multiply-into v
                                                      model
                                                      (make-layer-tensor-name layer-index "attn_v")
                                                      attn-norm))
            (normalize-vector-chunks-into q
                                          q
                                          head-count
                                          (gguf-model-load-vector-tensor
                                           model
                                           (make-layer-tensor-name layer-index "attn_q_norm"))
                                          :epsilon norm-epsilon)
            (when uses-own-kv-p
              (normalize-vector-chunks-into k
                                            k
                                            kv-head-count
                                            (gguf-model-load-vector-tensor
                                             model
                                             (make-layer-tensor-name layer-index "attn_k_norm"))
                                            :epsilon norm-epsilon)
              (rms-norm-unweighted-into v v :epsilon norm-epsilon))
            (setf q-heads (compute-buffer-chunks compute-buffer :q-heads q head-count))
            (when uses-own-kv-p
              (setf k-heads (compute-buffer-chunks compute-buffer :k-heads k kv-head-count))
              (setf v-heads (compute-buffer-chunks compute-buffer :v-heads v kv-head-count)))
            (dotimes (head-index (length q-heads))
              (apply-rope-head-in-place (aref q-heads head-index)
                                        position
                                        rope-dimension
                                        rope-base
                                        rope-source))
            (when uses-own-kv-p
              (dotimes (head-index (length k-heads))
                (apply-rope-head-in-place (aref k-heads head-index)
                                          position
                                          rope-dimension
                                          rope-base
                                          rope-source)))
            (compute-gemma4-attention-into attention-context
                                           compute-buffer
                                           model
                                           layer-index
                                           cache-layer-index
                                           position
                                           q-heads
                                           k-heads
                                           v-heads
                                           kv-cache)
            (gguf-model-matrix-vector-multiply-into attention-output
                                                    model
                                                    (make-layer-tensor-name layer-index "attn_output")
                                                    attention-context)
            (rms-norm-into post-attention
                           attention-output
                           (gguf-model-load-vector-tensor
                            model
                            (make-layer-tensor-name layer-index "post_attention_norm"))
                           :epsilon norm-epsilon)
            (vector-add-into x x post-attention)
            (rms-norm-into ffn-input
                           x
                           (gguf-model-load-vector-tensor
                            model
                            (make-layer-tensor-name layer-index "ffn_norm"))
                           :epsilon norm-epsilon)
            (gguf-model-matrix-vector-multiply-into ffn-gate
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_gate")
                                                    ffn-input)
            (gguf-model-matrix-vector-multiply-into ffn-up
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_up")
                                                    ffn-input)
            (apply-gelu-into ffn-gate ffn-gate)
            (vector-elementwise-multiply-into ffn-gate ffn-gate ffn-up)
            (gguf-model-matrix-vector-multiply-into ffn-down
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_down")
                                                    ffn-gate)
            (rms-norm-into post-ffn
                           ffn-down
                           (gguf-model-load-vector-tensor
                            model
                            (make-layer-tensor-name layer-index "post_ffw_norm"))
                           :epsilon norm-epsilon)
            (vector-add-into x x post-ffn)
            (when per-layer-inputs
              (let* ((ple-gate-length
                      (tensor-row-count
                       (gguf-model-tensor-info model
                                               (make-layer-tensor-name layer-index "inp_gate")
                                               t)))
                     (ple-gate (compute-buffer-vector compute-buffer :ple-gate ple-gate-length))
                     (ple-output (compute-buffer-vector compute-buffer :ple-output hidden-size))
                     (post-ple (compute-buffer-vector compute-buffer :post-ple hidden-size))
                     (per-layer-chunks (compute-buffer-chunks compute-buffer
                                                              :per-layer-input-chunks
                                                              per-layer-inputs
                                                              (gguf-model-layer-count model))))
                (gguf-model-matrix-vector-multiply-into ple-gate
                                                        model
                                                        (make-layer-tensor-name layer-index "inp_gate")
                                                        x)
                (apply-gelu-into ple-gate ple-gate)
                (vector-elementwise-multiply-into ple-gate
                                                  ple-gate
                                                  (aref per-layer-chunks layer-index))
                (gguf-model-matrix-vector-multiply-into ple-output
                                                        model
                                                        (make-layer-tensor-name layer-index "proj")
                                                        ple-gate)
                (rms-norm-into post-ple
                               ple-output
                               (gguf-model-load-vector-tensor
                                model
                                (make-layer-tensor-name layer-index "post_norm"))
                               :epsilon norm-epsilon)
                (vector-add-into x x post-ple)))
            (maybe-layer-output-scale model layer-index x)))
        (when *compute-gguf-logits*
          (softcap-logits
           (gguf-model-matrix-vector-multiply
            model
            (gguf-model-output-tensor-name model)
            (rms-norm-into (compute-buffer-vector compute-buffer :output-norm hidden-size)
                           x
                           (gguf-model-load-vector-tensor model "output_norm.weight")
                           :epsilon norm-epsilon))
           (gguf-model-final-logit-softcap model)))))))

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
      (let ((token-id 0))
        (declare (fixnum token-id))
        (mapc (lambda (token score)
                (setf (gethash token table)
                      (cons token-id score))
                (incf token-id))
              tokens
              scores))
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
        (declare (single-float d dmin)
                 (fixnum result-base scale-index))
        (dotimes (chunk-index (/ +qk-k+ 64))
          (declare (fixnum chunk-index))
          (let ((chunk-base (* chunk-index 64))
                (q-base (* chunk-index 32)))
            (declare (fixnum chunk-base q-base))
            (multiple-value-bind (scale0 min0)
                (get-scale-min-k4 scale-index scales-pointer)
              (multiple-value-bind (scale1 min1)
                  (get-scale-min-k4 (1+ scale-index) scales-pointer)
                (let ((delta0 (* d scale0))
                      (offset0 (* dmin min0))
                      (delta1 (* d scale1))
                      (offset1 (* dmin min1)))
                  (declare (single-float delta0 offset0 delta1 offset1))
                  (dotimes (lane 32)
                    (declare (fixnum lane))
                    (let ((packed (cffi:mem-aref qs-pointer :unsigned-char (+ q-base lane))))
                      (setf (aref result (+ result-base chunk-base lane))
                            (coerce (- (* delta0 (logand packed #x0F))
                                       offset0)
                                    'single-float))
                      (setf (aref result (+ result-base chunk-base 32 lane))
                            (coerce (- (* delta1 (ash packed -4))
                                       offset1)
                                    'single-float)))))
                (incf scale-index 2)))))))))

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
             (d (read-fp16-le quantized-pointer (+ block-offset (- block-size 2))))
             (ql-pointer (cffi:inc-pointer quantized-pointer block-offset))
             (qh-pointer (cffi:inc-pointer quantized-pointer
                                           (+ block-offset (/ +qk-k+ 2))))
             (scales-pointer (cffi:inc-pointer quantized-pointer
                                              (+ block-offset
                                                 (/ +qk-k+ 2)
                                                 (/ +qk-k+ 4))))
             (result-base (* block-index +qk-k+)))
        (declare (single-float d)
                 (fixnum result-base))
        (dotimes (chunk-index (/ +qk-k+ 128))
          (declare (fixnum chunk-index))
          (let ((chunk-base (* chunk-index 128))
                (ql-base (* chunk-index 64))
                (qh-base (* chunk-index 32))
                (scale-base (* chunk-index 8)))
            (declare (fixnum chunk-base ql-base qh-base scale-base))
            (dotimes (lane 32)
              (declare (fixnum lane))
              (let* ((scale-index (truncate lane 16))
                     (packed-low (cffi:mem-aref ql-pointer :unsigned-char (+ ql-base lane)))
                     (packed-high (cffi:mem-aref ql-pointer :unsigned-char (+ ql-base 32 lane)))
                     (packed-top (cffi:mem-aref qh-pointer :unsigned-char (+ qh-base lane)))
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
                (setf (aref result (+ result-base chunk-base lane))
                      (coerce (* d scale1 q1) 'single-float))
                (setf (aref result (+ result-base chunk-base 32 lane))
                      (coerce (* d scale2 q2) 'single-float))
                (setf (aref result (+ result-base chunk-base 64 lane))
                      (coerce (* d scale3 q3) 'single-float))
                (setf (aref result (+ result-base chunk-base 96 lane))
                      (coerce (* d scale4 q4) 'single-float))))))))))

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
  (map 'string
       (lambda (character)
         (if (char= character #\Space)
             (code-char #x2581)
             character))
       prompt))

(defun tokenizer-model (kv-pairs)
  (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.model"))

(defun tokenizer-token-id-table (kv-pairs)
  (let ((tokens (gguf-kv-value kv-pairs "tokenizer.ggml.tokens"))
        (table (make-hash-table :test #'equal))
        (token-id 0))
    (declare (fixnum token-id))
    (mapc (lambda (token)
           (setf (gethash token table) token-id)
           (incf token-id))
         tokens)
    table))

(defun tokenizer-special-tokens (kv-pairs)
  (let ((tokens (gguf-kv-value kv-pairs "tokenizer.ggml.tokens"))
        (token-types (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.token_type"))
        (special-tokens '()))
    (when token-types
      (mapc (lambda (token token-type)
             (when (and (integerp token-type)
                        (<= 3 token-type))
               (push token special-tokens)))
           tokens
           token-types))
    (sort special-tokens #'> :key #'length)))

(defun tokenizer-merge-rank-table (kv-pairs)
  (let ((merges (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.merges"))
        (table (make-hash-table :test #'equal)))
    (when merges
      (let ((rank 0))
        (declare (fixnum rank))
        (mapc (lambda (merge)
               (let ((separator-position (position #\Space merge :start 1)))
                 (when separator-position
                   (setf (gethash (cons (subseq merge 0 separator-position)
                                        (subseq merge (1+ separator-position)))
                                  table)
                         rank)))
               (incf rank))
             merges)))
    table))

(defun make-base-token-pieces (prompt token-table)
  (map 'list
       (lambda (character)
         (let* ((token (string character))
                (entry (gethash token token-table)))
           (unless entry
             (error "No base token found for character ~s." token))
           (cons (car entry) token)))
       (normalize-prompt-for-tokenization prompt)))

(defun split-gemma4-bpe-segments (prompt)
  (let ((segments '())
       (length (length prompt))
       (start 0))
    (declare (fixnum length start))
    (unless (zerop length)
      (let ((current-newline-p (char= #\Newline (char prompt 0))))
       (declare (boolean current-newline-p))
       (dotimes (index length)
         (declare (fixnum index))
         (let ((newline-p (char= #\Newline (char prompt index))))
           (declare (boolean newline-p))
           (unless (eq newline-p current-newline-p)
             (push (subseq prompt start index) segments)
             (setf start index
                   current-newline-p newline-p))))
       (push (subseq prompt start length) segments)))
    (nreverse segments)))

(defun string-all-newlines-p (string)
  (let ((length (length string)))
    (declare (fixnum length))
    (and (plusp length)
        (dotimes (index length t)
          (declare (fixnum index))
          (unless (char= #\Newline (char string index))
            (return nil))))))

(defun find-best-bpe-merge (pieces bpe-rank-table)
  (let ((best-index nil)
       (best-rank nil)
       (current pieces)
       (index 0))
    (declare (fixnum index))
    (do ()
       ((null (cdr current)))
      (let* ((left (car current))
            (right (cadr current))
            (rank (gethash (cons left right) bpe-rank-table)))
       (when (and rank
                  (or (null best-rank)
                      (< rank best-rank)))
         (setf best-index index
               best-rank rank)))
      (setf current (cdr current))
      (incf index))
    best-index))

(defun merge-string-pieces (pieces merge-index)
  (let ((prefix '())
       (suffix pieces))
    (dotimes (step merge-index)
      (declare (ignore step))
      (push (car suffix) prefix)
      (setf suffix (cdr suffix)))
    (let ((merged (concatenate 'string (car suffix) (cadr suffix))))
      (nconc (nreverse prefix)
            (list merged)
            (cddr suffix)))))

(defun utf8-string-to-octets (string)
  #+sbcl
  (sb-ext:string-to-octets string :external-format :utf-8)
  #-sbcl
  (error "UTF-8 byte fallback requires SBCL."))

(defun gemma4-byte-token-id (token-id-table octet)
  (gethash (format nil "<0x~2,'0X>" octet) token-id-table))

(defun tokenize-gemma4-piece (piece token-id-table)
  (let ((token-id (gethash piece token-id-table)))
    (if token-id
       (list token-id)
       (let ((byte-token-ids '()))
         (map nil
              (lambda (octet)
                (let ((byte-token-id (gemma4-byte-token-id token-id-table octet)))
                  (unless byte-token-id
                    (error "No Gemma4 byte fallback token for octet #x~2,'0X in piece ~s."
                           octet
                           piece))
                  (push byte-token-id byte-token-ids)))
              (utf8-string-to-octets piece))
         (nreverse byte-token-ids)))))

(defun tokenize-gemma4-segment (segment token-id-table bpe-rank-table)
  (let ((exact-token-id (and (string-all-newlines-p segment)
                            (gethash segment token-id-table))))
    (if exact-token-id
       (list exact-token-id)
       (let ((pieces (map 'list #'string segment)))
         (do ()
             (nil)
           (let ((merge-index (find-best-bpe-merge pieces bpe-rank-table)))
             (unless merge-index
               (return))
             (setf pieces (merge-string-pieces pieces merge-index))))
         (let ((token-ids '()))
           (dolist (piece pieces (nreverse token-ids))
             (setf token-ids (nconc (nreverse (tokenize-gemma4-piece piece token-id-table))
                                    token-ids))))))))

(defun tokenize-gemma4-text-fragment (fragment token-id-table bpe-rank-table)
  (let* ((segments (split-gemma4-bpe-segments fragment))
        (token-ids '()))
    (dolist (segment segments (nreverse token-ids))
      (setf token-ids (nconc (nreverse (tokenize-gemma4-segment segment
                                                               token-id-table
                                                               bpe-rank-table))
                            token-ids)))))

(defun find-matching-special-token (string start special-tokens)
  (find-if (lambda (token)
            (let ((end (+ start (length token))))
              (and (<= end (length string))
                   (string= token string :start2 start :end2 end))))
          special-tokens))

(defun tokenize-gemma4-prompt (kv-pairs prompt)
  (let* ((token-id-table (tokenizer-token-id-table kv-pairs))
        (bpe-rank-table (tokenizer-merge-rank-table kv-pairs))
        (special-tokens (tokenizer-special-tokens kv-pairs))
        (normalized-prompt (normalize-prompt-for-tokenization prompt))
        (token-ids '()))
    (let ((length (length normalized-prompt))
         (cursor 0)
         (fragment-start 0))
      (declare (fixnum length cursor fragment-start))
      (flet ((append-fragment-token-ids (start end)
              (unless (= start end)
                (setf token-ids
                      (nconc (nreverse (tokenize-gemma4-text-fragment
                                        (subseq normalized-prompt start end)
                                        token-id-table
                                        bpe-rank-table))
                             token-ids)))))
        (do ()
            ((>= cursor length))
          (let ((special-token (find-matching-special-token normalized-prompt
                                                           cursor
                                                           special-tokens)))
            (if special-token
               (progn
                 (append-fragment-token-ids fragment-start cursor)
                 (let ((special-token-id (gethash special-token token-id-table)))
                   (unless special-token-id
                     (error "Special token ~s missing from token id table."
                            special-token))
                   (push special-token-id token-ids))
                 (incf cursor (length special-token))
                 (setf fragment-start cursor))
               (incf cursor))))
        (append-fragment-token-ids fragment-start length)))
    (nreverse token-ids)))

(defun tokenize-greedy-token-prompt (kv-pairs prompt)
  (let* ((token-table (tokenizer-entry-table kv-pairs))
        (pieces (make-base-token-pieces prompt token-table)))
    (do ()
       (nil)
      (multiple-value-bind (merge-index merged-id merged-token)
         (find-best-token-merge pieces token-table)
       (unless merge-index
         (return))
       (setf pieces (merge-token-pieces pieces
                                        merge-index
                                        merged-id
                                        merged-token))))
    (mapcar #'car pieces)))

(defun find-best-token-merge (pieces token-table)
  (let ((best-index nil)
       (best-id nil)
       (best-token nil)
       (best-score nil)
        (index 0))
    (do ((current pieces (cdr current)))
        ((null (cdr current)))
      (let* ((left (car current))
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
    (dotimes (step merge-index)
      (declare (ignore step))
      (push (car suffix) prefix)
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
  (let* ((include-bos (if add-bos-p
                          add-bos
                          (default-add-bos-p kv-pairs)))
         (token-ids (if (string= (or (tokenizer-model kv-pairs) "")
                                 "gemma4")
                        (tokenize-gemma4-prompt kv-pairs prompt)
                        (tokenize-greedy-token-prompt kv-pairs prompt))))
    (if include-bos
        (let ((bos-token-id (resolve-bos-token-id kv-pairs)))
          (unless bos-token-id
            (error "Requested BOS token, but no BOS token id is present in metadata."))
          (cons bos-token-id token-ids))
        token-ids)))

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

(defun print-gguf-floating-point-tables (pathname &optional (stream *standard-output*))
  (call-with-file pathname
                  (lambda (handle)
                    (with-mapped-file (mapping handle)
                      (let ((tensor-infos (read-gguf-tensor-infos mapping)))
                        (format stream "Tensor Tables (* indicates page-aligned offset):~%")
                        (dolist (info tensor-infos)
                          (let ((offset (getf info :data-offset))
                                (size (getf info :byte-size))
                                (dimensions (getf info :dimensions))
                                (type-name (getf info :type-name))
                                (name (getf info :name)))
                            (format stream "  Name: ~A~:[~; *~]~%" name (zerop (mod offset 4096)))
                            (format stream "    Offset: #x~X~%" offset)
                            (if size
                                (format stream "    Size:   ~D bytes (#x~X)~%" size size)
                                (format stream "    Size:   unknown~%"))
                            (format stream "    Layout: ~S [Type: ~A]~%" dimensions type-name)))
                        tensor-infos)))))

(defun copy-tensors-to-aligned-temp-file (gguf-pathname temp-pathname)
  "Read GGUF-PATHNAME, calculate required aligned size, allocate and map TEMP-PATHNAME,
and copy all tensors into 64KB-aligned chunks, offset by 16 bytes for an SBCL array header."
  (let ((generic-write #x40000000)
        (create-always 2)
        (page-readwrite #x00000004)
        (file-map-write #x00000002)
        (sbcl-widetag-single-float #xD1)
        (sbcl-widetag-unsigned-byte-8 #x9D))
    ;; 1. Read all GGUF tensor-infos and calculate offsets & sizes
    (call-with-file gguf-pathname
      (lambda (gguf-handle)
        (with-mapped-file (gguf-mapping gguf-handle)
          (let* ((tensor-infos (read-gguf-tensor-infos gguf-mapping))
                 ;; Pre-calculate the total size and each tensor's target offset in temp file
                 (temp-layout
                  (let ((current-offset 0))
                    (mapcar (lambda (info)
                              (let* ((byte-size (or (getf info :byte-size) 0))
                                     ;; 16 bytes for SBCL array header
                                     (required-size (+ byte-size 16))
                                     ;; Align required-size to 64KB
                                     (aligned-size (* 65536 (ceiling required-size 65536)))
                                     (target-offset current-offset))
                                (setf current-offset (+ current-offset aligned-size))
                                (list :info info
                                      :byte-size byte-size
                                      :required-size required-size
                                      :target-offset target-offset)))
                            tensor-infos)))
                 (total-temp-size (if temp-layout
                                      (+ (getf (car (last temp-layout)) :target-offset)
                                         (* 65536 (ceiling (getf (car (last temp-layout)) :required-size) 65536)))
                                      0)))
            ;; 2. Create the temporary backing file
            (let ((native-temp-path (uiop:native-namestring temp-pathname)))
              (cffi:with-foreign-string (temp-name-ptr native-temp-path :encoding :utf-16le)
                (let ((temp-handle (create-file temp-name-ptr
                                                (logior +generic-read+ generic-write)
                                                +file-share-read+
                                                (cffi:null-pointer)
                                                create-always
                                                +file-attribute-normal+
                                                (cffi:null-pointer))))
                  (when (invalid-handle-p temp-handle)
                    (error "CreateFileW failed for temporary file ~a." native-temp-path))
                  (unwind-protect
                       ;; 3. Create the file mapping for the temp file
                       (let ((temp-mapping-handle (create-file-mapping temp-handle
                                                                      (cffi:null-pointer)
                                                                      page-readwrite
                                                                      (ash total-temp-size -32)
                                                                      (logand total-temp-size #xFFFFFFFF)
                                                                      (cffi:null-pointer))))
                         (when (cffi:null-pointer-p temp-mapping-handle)
                           (error "CreateFileMappingW failed for temporary file."))
                         (unwind-protect
                              ;; 4. Iterate over the tensors and copy them
                              (dolist (layout temp-layout)
                                (let* ((info (getf layout :info))
                                       (byte-size (getf layout :byte-size))
                                       (required-size (getf layout :required-size))
                                       (target-offset (getf layout :target-offset))
                                       ;; Map a view of the temp file at the specific 64KB aligned offset
                                       (temp-view (map-view-of-file temp-mapping-handle
                                                                    file-map-write
                                                                    (ash target-offset -32)
                                                                    (logand target-offset #xFFFFFFFF)
                                                                    required-size)))
                                  (when (cffi:null-pointer-p temp-view)
                                    (error "MapViewOfFile failed at offset #x~X for size ~D."
                                           target-offset required-size))
                                  (unwind-protect
                                       (progn
                                         ;; A. Write the appropriate 16-byte SBCL array header
                                         ;; (simple-array single-float (*)) or (simple-array (unsigned-byte 8) (*))
                                         (let* ((type-tag (getf info :type-tag))
                                                (is-f32 (= type-tag +ggml-type-f32+))
                                                (widetag (if is-f32
                                                             sbcl-widetag-single-float
                                                             sbcl-widetag-unsigned-byte-8))
                                                (array-length (if is-f32
                                                                  (getf info :element-count)
                                                                  byte-size)))
                                           ;; Word 0: Widetag
                                           (setf (cffi:mem-ref temp-view :uint64 0) widetag)
                                           ;; Word 1: Length (as fixnum: length * 2)
                                           (setf (cffi:mem-ref temp-view :uint64 8) (* array-length 2)))
                                         
                                         ;; B. Copy the tensor data from the mapped GGUF file
                                         (let ((gguf-tensor-ptr (cffi:inc-pointer gguf-mapping
                                                                                   (getf info :data-offset)))
                                               (temp-tensor-ptr (cffi:inc-pointer temp-view 16)))
                                           (rtl-move-memory temp-tensor-ptr
                                                            gguf-tensor-ptr
                                                            byte-size)))
                                    ;; Unmap the view of this chunk
                                    (unless (unmap-view-of-file temp-view)
                                      (error "UnmapViewOfFile failed for temporary file view.")))))
                           ;; Close temp file mapping handle
                           (close-handle temp-mapping-handle)))
                    ;; Close temp file handle
                    (close-handle temp-handle)))))
          total-temp-size))))))

(defun map-gguf-tensors-to-aligned-arrays (gguf-pathname temp-pathname)
  "Read GGUF-PATHNAME, allocate TEMP-PATHNAME, map and copy all tensors into 64KB-aligned chunks,
forge native SBCL array pointers pointing to these chunks, and return the list of forged arrays.
Returns a plist: (:arrays list-of-arrays :views views :mapping mapping-handle :file file-handle)"
  (let ((generic-write #x40000000)
        (create-always 2)
        (page-readwrite #x00000004)
        (file-map-write #x00000002)
        (sbcl-widetag-single-float #xD1)
        (sbcl-widetag-unsigned-byte-8 #x9D))
    (call-with-file gguf-pathname
      (lambda (gguf-handle)
        (with-mapped-file (gguf-mapping gguf-handle)
          (let* ((tensor-infos (read-gguf-tensor-infos gguf-mapping))
                 (temp-layout
                  (let ((current-offset 0))
                    (mapcar (lambda (info)
                              (let* ((byte-size (or (getf info :byte-size) 0))
                                     (required-size (+ byte-size 16))
                                     (aligned-size (* 65536 (ceiling required-size 65536)))
                                     (target-offset current-offset))
                                (setf current-offset (+ current-offset aligned-size))
                                (list :info info
                                      :byte-size byte-size
                                      :required-size required-size
                                      :target-offset target-offset)))
                            tensor-infos)))
                 (total-temp-size (if temp-layout
                                      (+ (getf (car (last temp-layout)) :target-offset)
                                         (* 65536 (ceiling (getf (car (last temp-layout)) :required-size) 65536)))
                                      0)))
            (let* ((native-temp-path (uiop:native-namestring temp-pathname))
                   (temp-name-ptr (cffi:foreign-alloc :uint16 :count (1+ (length native-temp-path)))))
              (dotimes (i (length native-temp-path))
                (setf (cffi:mem-aref temp-name-ptr :uint16 i)
                      (char-code (char native-temp-path i))))
              (setf (cffi:mem-aref temp-name-ptr :uint16 (length native-temp-path)) 0)
              (let ((temp-handle (create-file temp-name-ptr
                                              (logior +generic-read+ generic-write)
                                              +file-share-read+
                                              (cffi:null-pointer)
                                              create-always
                                              +file-attribute-normal+
                                              (cffi:null-pointer))))
                (cffi:foreign-free temp-name-ptr)
                (when (invalid-handle-p temp-handle)
                  (error "CreateFileW failed for temporary file ~a." native-temp-path))
                (let ((temp-mapping-handle (create-file-mapping temp-handle
                                                                (cffi:null-pointer)
                                                                page-readwrite
                                                                (ash total-temp-size -32)
                                                                (logand total-temp-size #xFFFFFFFF)
                                                                (cffi:null-pointer))))
                  (when (cffi:null-pointer-p temp-mapping-handle)
                    (close-handle temp-handle)
                    (error "CreateFileMappingW failed for temporary file."))
                  (let ((forged-arrays '())
                        (views-list '()))
                    (handler-case
                        (dolist (layout temp-layout)
                          (let* ((info (getf layout :info))
                                 (byte-size (getf layout :byte-size))
                                 (required-size (getf layout :required-size))
                                 (target-offset (getf layout :target-offset))
                                 (temp-view (map-view-of-file temp-mapping-handle
                                                              file-map-write
                                                              (ash target-offset -32)
                                                              (logand target-offset #xFFFFFFFF)
                                                              required-size)))
                            (when (cffi:null-pointer-p temp-view)
                              (error "MapViewOfFile failed at offset #x~X for size ~D."
                                     target-offset required-size))
                            (push temp-view views-list)
                            ;; A. Write the appropriate 16-byte SBCL simple-array header
                            (let* ((type-tag (getf info :type-tag))
                                   (is-f32 (= type-tag +ggml-type-f32+))
                                   (widetag (if is-f32
                                                sbcl-widetag-single-float
                                                sbcl-widetag-unsigned-byte-8))
                                   (array-length (if is-f32
                                                     (getf info :element-count)
                                                     byte-size)))
                              ;; Word 0: Widetag
                              (setf (cffi:mem-ref temp-view :uint64 0) widetag)
                              ;; Word 1: Length (as fixnum)
                              (setf (cffi:mem-ref temp-view :uint64 8) (* array-length 2))
                              
                              ;; B. Copy the tensor data from the mapped GGUF file
                              (let ((gguf-tensor-ptr (cffi:inc-pointer gguf-mapping
                                                                        (getf info :data-offset)))
                                    (temp-tensor-ptr (cffi:inc-pointer temp-view 16)))
                                (rtl-move-memory temp-tensor-ptr
                                                 gguf-tensor-ptr
                                                 byte-size))
                              
                              ;; C. Forge the Lisp complex-vector pointing to this mapped view
                              (let* ((aligned-addr (cffi:pointer-address temp-view))
                                     (arr (sb-kernel:make-array-header sb-vm:complex-vector-widetag 1))
                                     (arr-addr (- (sb-kernel:get-lisp-obj-address arr) 15))
                                     (dummy-vector (if is-f32
                                                       (make-array 1 :element-type 'single-float)
                                                       (make-array 1 :element-type '(unsigned-byte 8)))))
                                (setf (sb-kernel:%array-fill-pointer arr) array-length)
                                (setf (sb-kernel:%array-available-elements arr) array-length)
                                (sb-kernel:%set-array-dimension arr 0 array-length)
                                (setf (sb-kernel:%array-data arr) dummy-vector)
                                ;; Overwrite the data vector slot with our forged simple-array!
                                (setf (sb-sys:sap-ref-64 (sb-sys:int-sap arr-addr) (* sb-vm:array-data-slot 8))
                                      (+ aligned-addr 15))
                                (push arr forged-arrays)))))
                      (error (c)
                        ;; If anything fails, unmap everything and clean up
                        (dolist (v views-list) (unmap-view-of-file v))
                        (close-handle temp-mapping-handle)
                        (close-handle temp-handle)
                        (error c)))
                    ;; Keep the temp-mapping-handle and temp-handle open so memory remains mapped!
                    ;; We return a plist with the forged arrays and the cleanup context.
                    (list :arrays (nreverse forged-arrays)
                          :views views-list
                          :mapping temp-mapping-handle
                          :file temp-handle)))))))))))

(defun hello-message ()
  "Return the default startup message for llambda."
  "llambda ready.")

(defun main ()
  (format t "~a~%" (hello-message)))
