(in-package #:llambda)

(cffi:define-foreign-library kernel32
  (t (:default "kernel32")))

(cffi:use-foreign-library kernel32)

(cffi:define-foreign-library llambda-npu
  (:windows (:default "llambda_npu")))

(cffi:defctype handle :pointer)
(cffi:defctype dword :uint32)

(defconstant +generic-read+ #x80000000)
(defconstant +file-share-read+ #x00000001)
(defconstant +file-map-read+ #x00000004)
(defconstant +open-existing+ 3)
(defconstant +file-attribute-normal+ #x00000080)
(defconstant +page-readonly+ #x00000002)
(defconstant +error-already-exists+ 183)
(defconstant +qk-k+ 256)
(defconstant +k-scale-size+ 12)
(defconstant +q6-k-scale-count+ 16)
(defconstant +ggml-type-f32+ 0)
(defconstant +ggml-type-f16+ 1)
(defconstant +ggml-type-q5-0+ 6)
(defconstant +ggml-type-q8-0+ 8)
(defconstant +ggml-type-bf16+ 30)
(defconstant +ggml-type-q4-k+ 12)
(defconstant +ggml-type-q5-k+ 13)
(defconstant +ggml-type-q6-k+ 14)
(defconstant +default-top-k+ 40)
(defconstant +default-top-p+ 0.95f0)

(defparameter *compute-gguf-logits* t)
(defparameter *gemv-worker-count* 24)
(defparameter *gemv-min-parallel-rows* 96)
(defparameter *gemv-kernel* nil)
(defparameter *gpt2-unicode-byte-table* nil)
(defparameter *gpt2-byte-unicode-table* nil)
(defparameter *npu-library* nil)
(defparameter *gpu-library* nil)
(defparameter *npu-runtime-library* nil)
(defparameter *mapped-regions* nil)

(cffi:defcfun ("SetDllDirectoryW" %set-dll-directory) :boolean
  (pathname :pointer))
(cffi:defcfun ("GetDllDirectoryW" %get-dll-directory) dword
  (buffer-length dword)
  (buffer :pointer))
(cffi:defcfun ("MoveFileExW" %move-file-ex) :boolean
  (existing-path :pointer)
  (new-path :pointer)
  (flags dword))

(cffi:defcfun ("llambda_npu_probe" %npu-probe) :int)
(cffi:defcfun ("llambda_npu_bridge_version" %npu-bridge-version) :string)
(cffi:defcfun ("llambda_npu_runtime_version" %npu-runtime-version) :string)
(cffi:defcfun ("llambda_npu_last_error" %npu-last-error) :string)
(cffi:defcfun ("llambda_npu_sha256" %npu-sha256) :int
  (data :pointer)
  (data-size :size)
  (output :pointer)
  (output-size :size))
(cffi:defcfun ("llambda_npu_session_create" %npu-session-create) :int
  (model-path :string)
  (cache-dir :string)
  (cache-key :string)
  (result :pointer))
(cffi:defcfun ("llambda_npu_session_destroy" %npu-session-destroy) :void
  (session :pointer))
(cffi:defcfun ("llambda_npu_session_input_element_count"
               %npu-session-input-element-count) :size
  (session :pointer))
(cffi:defcfun ("llambda_npu_session_output_element_count"
               %npu-session-output-element-count) :size
  (session :pointer))
(cffi:defcfun ("llambda_npu_session_run" %npu-session-run) :int
  (session :pointer)
  (input :pointer)
  (input-element-count :size)
  (output :pointer)
  (output-element-count :size))
(cffi:defcfun ("llambda_gpu_probe" %gpu-probe) :int)
(cffi:defcfun ("llambda_gpu_session_create" %gpu-session-create) :int
  (model-path :string)
  (result :pointer))
(cffi:defcfun ("llambda_gpu_session_destroy" %gpu-session-destroy) :void
  (session :pointer))
(cffi:defcfun ("llambda_gpu_session_input_element_count"
               %gpu-session-input-element-count) :size
  (session :pointer))
(cffi:defcfun ("llambda_gpu_session_output_element_count"
               %gpu-session-output-element-count) :size
  (session :pointer))
(cffi:defcfun ("llambda_gpu_session_run" %gpu-session-run) :int
  (session :pointer)
  (input :pointer)
  (input-element-count :size)
  (output :pointer)
  (output-element-count :size))

(defstruct (npu-session (:constructor %make-npu-session))
  pointer
  input-element-count
  output-element-count)

(defstruct (gpu-session (:constructor %make-gpu-session))
  pointer
  input-element-count
  output-element-count)

(define-condition npu-backend-error (simple-error) ())
(define-condition gpu-backend-error (simple-error) ())

(defun npu-backend-error (format-control &rest format-arguments)
  (error 'npu-backend-error
         :format-control format-control
         :format-arguments format-arguments))

(defun gpu-backend-error (format-control &rest format-arguments)
  (error 'gpu-backend-error
         :format-control format-control
         :format-arguments format-arguments))

(defun default-npu-library-pathname ()
  (asdf:system-relative-pathname
   :llambda
   #P"native/build/Release/llambda_npu.dll"))

(defun default-gpu-library-pathname ()
  (asdf:system-relative-pathname
   :llambda
   #P"native/build-gpu/Release/llambda_npu.dll"))

(defun load-npu-backend (&optional (pathname (default-npu-library-pathname)))
  (or *npu-library*
      (let* ((native-pathname (uiop:native-namestring pathname))
             (directory (uiop:pathname-directory-pathname pathname))
             (native-directory (uiop:native-namestring directory))
             (runtime-pathname (merge-pathnames #P"onnxruntime.dll" directory)))
        (unless (probe-file runtime-pathname)
          (error "ONNX Runtime was not found beside the NPU bridge at ~a."
                 runtime-pathname))
        (cffi:with-foreign-object (previous-directory :uint16 32768)
          (let* ((previous-length
                   (%get-dll-directory 32768 previous-directory))
                 (previous-value
                   (and (plusp previous-length)
                        (cffi:foreign-string-to-lisp
                         previous-directory
                         :count previous-length
                         :encoding :utf-16le))))
            (when (>= previous-length 32768)
              (error "The existing DLL search directory exceeds 32767 characters."))
            (unwind-protect
                (progn
                  (cffi:with-foreign-string
                      (directory-pointer native-directory :encoding :utf-16le)
                    (unless (%set-dll-directory directory-pointer)
                      (error "SetDllDirectoryW failed for ~a."
                             native-directory)))
                  (setf *npu-runtime-library*
                        (cffi:load-foreign-library
                         (uiop:native-namestring runtime-pathname)))
                  (setf *npu-library*
                        (cffi:load-foreign-library native-pathname))
                  (setf *gpu-library* *npu-library*))
              (if previous-value
                  (cffi:with-foreign-string
                      (previous-pointer previous-value :encoding :utf-16le)
                    (unless (%set-dll-directory previous-pointer)
                      (error "Unable to restore the DLL search directory.")))
                  (unless (%set-dll-directory (cffi:null-pointer))
                    (error "Unable to restore the default DLL search path.")))))))))

(defun load-gpu-backend (&optional (pathname (default-gpu-library-pathname)))
  (or *gpu-library*
      (progn
        (if *npu-library*
            (setf *gpu-library* *npu-library*)
            (load-npu-backend pathname))
        *gpu-library*)))

(defun require-npu-backend ()
  (unless *npu-library*
    (npu-backend-error
     "The NPU backend is not loaded. Call LOAD-NPU-BACKEND first.")))

(defun npu-backend-available-p ()
  (require-npu-backend)
  (let ((result (%npu-probe)))
    (cond ((= result 1) t)
          ((zerop result) nil)
          (t (npu-backend-error
              "NPU backend probe failed: ~a" (%npu-last-error))))))

(defun require-gpu-backend ()
  (unless *gpu-library*
    (gpu-backend-error
     "The GPU backend is not loaded. Call LOAD-GPU-BACKEND first.")))

(defun gpu-backend-available-p ()
  (require-gpu-backend)
  (let ((result (%gpu-probe)))
    (cond ((= result 1) t)
          ((zerop result) nil)
          (t (gpu-backend-error
              "GPU backend probe failed: ~a" (%npu-last-error))))))

(defun gpu-backend-runtime-version ()
  (require-gpu-backend)
  (or (%npu-runtime-version)
      (gpu-backend-error
       "Unable to query ONNX Runtime: ~a" (%npu-last-error))))

(defun npu-backend-runtime-version ()
  (require-npu-backend)
  (or (%npu-runtime-version)
      (npu-backend-error
       "Unable to query ONNX Runtime: ~a" (%npu-last-error))))

(defun npu-bridge-version ()
  (require-npu-backend)
  (or (%npu-bridge-version)
      (npu-backend-error
       "Unable to query the NPU bridge version: ~a"
       (%npu-last-error))))

(defun check-npu-status (status operation)
  (unless (zerop status)
    (npu-backend-error "~a failed: ~a" operation (%npu-last-error))))

(defun make-npu-session (model-path &key cache-directory cache-key)
  (require-npu-backend)
  (cffi:with-foreign-object (result :pointer)
    (check-npu-status
     (%npu-session-create
      (uiop:native-namestring model-path)
      (if cache-directory
          (uiop:native-namestring cache-directory)
          "")
      (or cache-key "")
      result)
     "NPU session creation")
    (let ((pointer (cffi:mem-ref result :pointer)))
      (%make-npu-session
       :pointer pointer
       :input-element-count (%npu-session-input-element-count pointer)
       :output-element-count (%npu-session-output-element-count pointer)))))

(defun close-npu-session (session)
  (let ((pointer (npu-session-pointer session)))
    (unless (cffi:null-pointer-p pointer)
      (%npu-session-destroy pointer)
      (setf (npu-session-pointer session) (cffi:null-pointer))))
  nil)

(defun run-npu-session-into (dest session input)
  (unless (= (length input) (npu-session-input-element-count session))
    (error "NPU input length ~d does not match session input length ~d."
           (length input)
           (npu-session-input-element-count session)))
  (unless (= (length dest) (npu-session-output-element-count session))
    (error "NPU output length ~d does not match session output length ~d."
           (length dest)
           (npu-session-output-element-count session)))
  (cffi:with-pointer-to-vector-data (input-pointer input)
    (cffi:with-pointer-to-vector-data (output-pointer dest)
      (handler-case
          (check-npu-status
           (%npu-session-run (npu-session-pointer session)
                             input-pointer
                             (length input)
                             output-pointer
                             (length dest))
           "NPU inference")
        (npu-backend-error (condition)
          (error condition))
        (error (condition)
          (npu-backend-error
           "NPU bridge invocation failed: ~a" condition)))))
  dest)

(defun check-gpu-status (status operation)
  (unless (zerop status)
    (gpu-backend-error "~a failed: ~a" operation (%npu-last-error))))

(defun make-gpu-session (model-path)
  (require-gpu-backend)
  (cffi:with-foreign-object (result :pointer)
    (check-gpu-status
     (%gpu-session-create (uiop:native-namestring model-path) result)
     "GPU session creation")
    (let ((pointer (cffi:mem-ref result :pointer)))
      (%make-gpu-session
       :pointer pointer
       :input-element-count (%gpu-session-input-element-count pointer)
       :output-element-count (%gpu-session-output-element-count pointer)))))

(defun close-gpu-session (session)
  (let ((pointer (gpu-session-pointer session)))
    (unless (cffi:null-pointer-p pointer)
      (%gpu-session-destroy pointer)
      (setf (gpu-session-pointer session) (cffi:null-pointer))))
  nil)

(defun run-gpu-session-into (dest session input)
  (unless (= (length input) (gpu-session-input-element-count session))
    (error "GPU input length ~d does not match session input length ~d."
           (length input)
           (gpu-session-input-element-count session)))
  (unless (= (length dest) (gpu-session-output-element-count session))
    (error "GPU output length ~d does not match session output length ~d."
           (length dest)
           (gpu-session-output-element-count session)))
  (cffi:with-pointer-to-vector-data (input-pointer input)
    (cffi:with-pointer-to-vector-data (output-pointer dest)
      (handler-case
          (check-gpu-status
           (%gpu-session-run (gpu-session-pointer session)
                             input-pointer
                             (length input)
                             output-pointer
                             (length dest))
           "GPU inference")
        (gpu-backend-error (condition)
          (error condition))
        (error (condition)
          (gpu-backend-error
           "GPU bridge invocation failed: ~a" condition)))))
  dest)

(defun single-float-to-bf16-bits (value)
  #+sbcl
  (let* ((bits (sb-kernel::single-float-bits value))
         (rounding-bias (+ #x7fff (ldb (byte 1 16) bits))))
    (ldb (byte 16 16) (+ bits rounding-bias)))
  #-sbcl
  (error "BF16 projection export currently requires SBCL."))

(defun write-bf16-le (stream value)
  (let ((bits (single-float-to-bf16-bits value)))
    (write-byte (ldb (byte 8 0) bits) stream)
    (write-byte (ldb (byte 8 8) bits) stream)))

(defun write-f32-le (stream value)
  #+sbcl
  (let ((bits (sb-kernel::single-float-bits value)))
    (dotimes (byte-index 4)
      (write-byte (ldb (byte 8 (* byte-index 8)) bits) stream)))
  #-sbcl
  (declare (ignore stream value))
  #-sbcl
  (error "Float32 projection export currently requires SBCL."))

(defun default-npu-model-generator-pathname ()
  (asdf:system-relative-pathname
   :llambda
   #P"native/generate-matmul-model.py"))

(defun replace-file-atomically (source destination)
  (cffi:with-foreign-string
      (source-pointer (uiop:native-namestring source) :encoding :utf-16le)
    (cffi:with-foreign-string
        (destination-pointer
         (uiop:native-namestring destination)
         :encoding :utf-16le)
      (unless (%move-file-ex source-pointer destination-pointer #x9)
        (error "MoveFileExW failed while replacing ~a." destination))))
  destination)

(defun export-model-accelerator-projection
    (model tensor-name onnx-path
     &key
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname))
       (weight-format :bfloat16))
  (unless (member weight-format '(:bfloat16 :float32))
    (error "Unknown accelerator projection weight format ~s." weight-format))
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (dimensions (getf tensor-info :dimensions)))
    (unless (= 2 (length dimensions))
      (error "Accelerator projection export requires a two-dimensional tensor, not ~s."
             dimensions))
    (let* ((column-count (tensor-column-count tensor-info))
           (row-count (tensor-row-count tensor-info))
           (row (make-array column-count :element-type 'single-float))
           (raw-path
             (merge-pathnames
              (make-pathname
               :name (format nil "llambda-weights-~d-~d"
                             (get-universal-time)
                             (random most-positive-fixnum))
               :type (ecase weight-format
                       (:bfloat16 "bf16")
                       (:float32 "f32")))
              (uiop:temporary-directory)))
           (temporary-onnx-path
             (make-pathname
              :name (format nil "~a-~d"
                            (or (pathname-name onnx-path) "projection")
                            (random most-positive-fixnum))
              :type "onnx.tmp"
              :defaults onnx-path))
           (command-prefix
             (if (listp python-command)
                 python-command
                 (list python-command))))
      (ensure-directories-exist onnx-path)
      (unwind-protect
          (progn
            (with-open-file
                (stream raw-path
                        :direction :output
                        :if-exists :supersede
                        :element-type '(unsigned-byte 8))
              (dotimes (row-index row-count)
                (load-gguf-tensor-row-into
                 row
                 (gguf-model-mapping model)
                 tensor-info
                 row-index)
                (dotimes (column-index column-count)
                  (ecase weight-format
                    (:bfloat16
                     (write-bf16-le stream (aref row column-index)))
                    (:float32
                     (write-f32-le stream (aref row column-index)))))))
            (uiop:run-program
             (append command-prefix
                     (list (uiop:native-namestring generator-path)
                           (uiop:native-namestring temporary-onnx-path)
                           "--rows" (write-to-string row-count)
                           "--columns" (write-to-string column-count)
                           "--dtype" (ecase weight-format
                                       (:bfloat16 "bfloat16")
                                       (:float32 "float32"))
                           "--weights" (uiop:native-namestring raw-path)))
             :output *standard-output*
             :error-output *error-output*)
            (replace-file-atomically temporary-onnx-path onnx-path)
            onnx-path)
        (when (probe-file raw-path)
          (delete-file raw-path))
        (when (probe-file temporary-onnx-path)
          (delete-file temporary-onnx-path))))))

(defun export-model-npu-projection
    (model tensor-name onnx-path &rest arguments)
  (apply #'export-model-accelerator-projection
        model tensor-name onnx-path arguments))

(defun export-model-gpu-projection
    (model tensor-name onnx-path &rest arguments)
  (unless (getf arguments :weight-format)
    (setf arguments (append arguments '(:weight-format :float32))))
  (apply #'export-model-accelerator-projection
        model tensor-name onnx-path arguments))
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

(cffi:defcfun ("GetFileSizeEx" get-file-size-ex) :boolean
  (file handle)
  (file-size :pointer))

(cffi:defcfun ("GetLastError" get-last-error) dword)

(defstruct (mapped-region
            (:constructor make-mapped-region (pointer byte-length)))
  pointer
  byte-length)

(defun invalid-handle-p (handle)
  (= (cffi:pointer-address handle)
     (1- (ash 1 (* 8 (cffi:foreign-type-size :pointer))))))

(defun file-handle-byte-length (file-handle)
  (cffi:with-foreign-object (file-size :int64)
    (unless (get-file-size-ex file-handle file-size)
      (error "GetFileSizeEx failed."))
    (let ((byte-length (cffi:mem-ref file-size :int64)))
      (when (minusp byte-length)
        (error "GetFileSizeEx returned a negative file size: ~d." byte-length))
      byte-length)))

(defun find-mapped-region (pointer)
  (let ((address (cffi:pointer-address pointer)))
    (find address
          *mapped-regions*
          :key (lambda (region)
                 (cffi:pointer-address (mapped-region-pointer region)))
          :test #'=)))

(defun require-mapped-region (pointer operation)
  (or (find-mapped-region pointer)
      (error "~a requires a pointer supplied by CALL-WITH-MAPPED-FILE."
             operation)))

(defun ensure-mapped-range (region offset byte-length description)
  (unless (and (integerp offset) (not (minusp offset)))
    (error "~a has invalid byte offset ~s." description offset))
  (unless (and (integerp byte-length) (not (minusp byte-length)))
    (error "~a has invalid byte length ~s." description byte-length))
  (let ((region-length (mapped-region-byte-length region)))
    (unless (and (<= offset region-length)
                 (<= byte-length (- region-length offset)))
      (error "~a byte range [~d, ~d) exceeds mapped file length ~d."
             description
             offset
             (+ offset byte-length)
             region-length)))
  offset)

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
  (let* ((file-byte-length (file-handle-byte-length file-handle))
         (mapping-byte-length
           (+ (ash maximum-size-high 32) maximum-size-low))
         (effective-mapping-byte-length
           (if (zerop mapping-byte-length)
               file-byte-length
               mapping-byte-length))
         (file-offset (+ (ash file-offset-high 32) file-offset-low))
         (view-byte-length
           (if (zerop number-of-bytes-to-map)
               (- effective-mapping-byte-length file-offset)
               number-of-bytes-to-map)))
    (unless (<= file-offset effective-mapping-byte-length)
      (error "Mapped file offset ~d exceeds mapping length ~d."
             file-offset
             effective-mapping-byte-length))
    (unless (and (not (minusp view-byte-length))
                 (<= view-byte-length
                     (- effective-mapping-byte-length file-offset)))
      (error "Mapped view length ~d at offset ~d exceeds mapping length ~d."
             view-byte-length
             file-offset
             effective-mapping-byte-length))
    (let* ((mapping-handle (create-file-mapping file-handle
                                               mapping-attributes
                                               protect
                                               maximum-size-high
                                               maximum-size-low
                                               name))
           (mapping-already-exists-p
             (and (not (cffi:null-pointer-p name))
                  (= (get-last-error) +error-already-exists+))))
      (when (cffi:null-pointer-p mapping-handle)
        (error "CreateFileMappingW failed."))
      (when mapping-already-exists-p
        (close-handle mapping-handle)
        (error "CALL-WITH-MAPPED-FILE refuses an existing named mapping because its byte length cannot be verified."))
      (unwind-protect
          (let ((mapping (map-view-of-file mapping-handle
                                           desired-access
                                           file-offset-high
                                           file-offset-low
                                           number-of-bytes-to-map)))
            (when (cffi:null-pointer-p mapping)
              (error "MapViewOfFile failed."))
            (unwind-protect
                (let ((*mapped-regions*
                        (cons (make-mapped-region mapping view-byte-length)
                              *mapped-regions*)))
                  (funcall receiver mapping))
              (unless (unmap-view-of-file mapping)
                (error "UnmapViewOfFile failed."))))
        (unless (close-handle mapping-handle)
          (error "CloseHandle failed for file mapping object."))))))

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

(declaim (ftype (function (t fixnum) fixnum) read-u8)
         (ftype (function (t fixnum) single-float) read-fp16-le)
         (ftype (function (t fixnum) single-float) read-bf16-le)
         (ftype (function (t fixnum) fixnum) read-s8)
         (ftype (function (fixnum) single-float) fixnum-single-float)
         (inline read-u8 read-fp16-le read-bf16-le read-s8 fixnum-single-float))

(defun read-u8 (pointer offset)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (fixnum offset))
  (the fixnum
       (cffi:mem-aref pointer :unsigned-char offset)))

(defun read-fp16-le (pointer offset)
  (the single-float
       (fp16-to-single-float (read-u16-le pointer offset))))

(defun read-s8 (pointer offset)
  (the fixnum
       (unsigned-to-signed (cffi:mem-aref pointer :unsigned-char offset) 8)))

(defun fixnum-single-float (value)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (fixnum value))
  (the single-float
       (float value 1.0f0)))

(defun ensure-single-float-array (vector)
  (if (typep vector '(simple-array single-float (*)))
      vector
      (make-array (length vector)
                  :element-type 'single-float
                  :initial-contents vector)))

(declaim (ftype (function () t) ensure-gemv-kernel)
         (ftype (function (fixnum) boolean) parallel-gemv-row-count-p)
         (ftype (function (fixnum) fixnum) parallel-gemv-part-count)
         (inline parallel-gemv-row-count-p parallel-gemv-part-count))

(defun ensure-gemv-kernel ()
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0)))
  (unless (and *gemv-kernel*
               (let ((lparallel:*kernel* *gemv-kernel*))
                 (= (the fixnum (lparallel:kernel-worker-count))
                    (the fixnum *gemv-worker-count*))))
    (when *gemv-kernel*
      (let ((lparallel:*kernel* *gemv-kernel*))
        (lparallel:end-kernel :wait t)))
    (setf *gemv-kernel*
          (lparallel:make-kernel *gemv-worker-count* :name "llambda-gemv")))
  *gemv-kernel*)

(defun close-gemv-runtime ()
  "Stop and release the process-global GEMV worker kernel, if one exists.

The caller must ensure that no inference request is using the kernel."
  (when *gemv-kernel*
    (let ((kernel *gemv-kernel*))
      (let ((lparallel:*kernel* kernel))
        (lparallel:end-kernel :wait t))
      (setf *gemv-kernel* nil)))
  nil)

(defun parallel-gemv-row-count-p (row-count)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (fixnum row-count))
  (the boolean
       (>= row-count (the fixnum *gemv-min-parallel-rows*))))

(defun parallel-gemv-part-count (row-count)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (fixnum row-count))
  (the fixnum
       (min row-count
            (the fixnum *gemv-worker-count*))))

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

(defun sigmoid (value)
  (coerce (/ 1.0d0 (+ 1.0d0 (exp (- value)))) 'single-float))

(defun softplus (value)
  (let ((x (coerce value 'single-float)))
    (if (> x 20.0f0)
        x
        (coerce (log (+ 1.0d0 (exp x))) 'single-float))))

(defun relu-squared (value)
  (let ((x (max 0.0f0 (coerce value 'single-float))))
    (* x x)))

(defun apply-silu (vector)
  (map 'vector #'silu vector))

(defun apply-silu-into (dest vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (unless (= (length dest) (length vector))
    (error "APPLY-SILU destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (dotimes (index (length vector) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (silu (aref vector index)))))

(defun apply-sigmoid-into (dest vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (unless (= (length dest) (length vector))
    (error "APPLY-SIGMOID destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (dotimes (index (length vector) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (sigmoid (aref vector index)))))

(defun apply-relu-squared-into (dest vector)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector))
  (unless (= (length dest) (length vector))
    (error "APPLY-RELU-SQUARED destination length ~d does not match vector length ~d."
           (length dest)
           (length vector)))
  (dotimes (index (length vector) dest)
    (declare (fixnum index))
    (setf (aref dest index)
          (relu-squared (aref vector index)))))

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

(defun apply-repetition-penalty (logits history &optional (penalty 1.15f0))
  (declare (type (simple-array single-float (*)) logits)
           (single-float penalty)
           (optimize (speed 3) (safety 1)))
  (when (<= penalty 0.0f0)
    (error "PENALTY must be positive, got ~a." penalty))
  (labels ((penalize-token-id (token-id)
             (declare (fixnum token-id))
             (unless (< -1 token-id (length logits))
               (error "History token id ~d is out of bounds for logits length ~d."
                       token-id
                       (length logits)))
             (let ((logit (aref logits token-id)))
               (declare (single-float logit))
               (cond
                  ((> logit 0.0f0)
                   (setf (aref logits token-id)
                         (coerce (/ logit penalty) 'single-float)))
                  ((< logit 0.0f0)
                   (setf (aref logits token-id)
                         (coerce (* logit penalty) 'single-float)))))))
    (etypecase history
      (null logits)
      (list
       (do ((cell history (cdr cell)))
           ((endp cell) logits)
         (let ((token-id (car cell))
               (seen-earlier-p nil))
           (declare (fixnum token-id))
           (do ((earlier history (cdr earlier)))
               ((eq earlier cell))
             (when (= (the fixnum (car earlier)) token-id)
               (setf seen-earlier-p t)
               (return)))
           (unless seen-earlier-p
             (penalize-token-id token-id)))))
      (vector
       (let ((history-length (length history)))
         (declare (fixnum history-length))
         (dotimes (index history-length logits)
           (declare (fixnum index))
           (let ((token-id (aref history index))
                  (seen-earlier-p nil))
             (declare (fixnum token-id))
             (dotimes (earlier-index index)
               (declare (fixnum earlier-index))
               (when (= (the fixnum (aref history earlier-index)) token-id)
                  (setf seen-earlier-p t)
                  (return)))
             (unless seen-earlier-p
               (penalize-token-id token-id)))))))))

(defun apply-top-k-with-workspace (logits k heap)
  (declare (type (simple-array single-float (*)) logits)
           (type (simple-array single-float (*)) heap)
           (fixnum k)
           (optimize (speed 3) (safety 1)))
  (let ((length (length logits)))
    (declare (fixnum length))
    (when (< k 0)
      (error "TOP-K must be non-negative, got ~d." k))
    (when (or (zerop k)
             (>= k length))
      (return-from apply-top-k-with-workspace logits))
    (unless (<= k (length heap))
      (error "TOP-K workspace length ~d is too small for k = ~d."
             (length heap)
             k))
    (let ((masked-logit -1.0f30))
      (declare (single-float masked-logit))
      (replace heap logits :end1 k :end2 k)
      (labels ((heapify-down (start-index)
                (declare (fixnum start-index))
                (let ((value (aref heap start-index))
                      (index start-index))
                  (declare (single-float value)
                           (fixnum index))
                  (loop
                    (let ((left-child (1+ (* 2 index))))
                      (declare (fixnum left-child))
                      (when (>= left-child k)
                        (return))
                      (let* ((right-child (1+ left-child))
                             (smaller-child
                              (if (and (< right-child k)
                                       (< (aref heap right-child)
                                          (aref heap left-child)))
                                  right-child
                                  left-child)))
                        (declare (fixnum right-child smaller-child))
                        (when (<= value (aref heap smaller-child))
                          (return))
                        (setf (aref heap index) (aref heap smaller-child)
                              index smaller-child))))
                  (setf (aref heap index) value)))
              (build-min-heap ()
                (do ((index (floor (- k 2) 2) (1- index)))
                    ((minusp index))
                  (declare (fixnum index))
                  (heapify-down index))))
        (build-min-heap)
        (do ((index k (1+ index)))
            ((>= index length))
          (declare (fixnum index))
          (let ((value (aref logits index)))
            (declare (single-float value))
            (when (> value (aref heap 0))
             (setf (aref heap 0) value)
             (heapify-down 0))))
        (let ((cutoff (aref heap 0)))
          (declare (single-float cutoff))
          (dotimes (index length logits)
            (declare (fixnum index))
            (when (< (aref logits index) cutoff)
             (setf (aref logits index) masked-logit))))))))

(defun apply-top-k (logits k)
  (declare (type (simple-array single-float (*)) logits)
           (fixnum k)
           (optimize (speed 3) (safety 1)))
  (if (or (zerop k)
          (>= k (length logits)))
      logits
      (apply-top-k-with-workspace logits
                                 k
                                 (make-array k :element-type 'single-float))))

(defun apply-top-p-with-workspace (logits p temperature logit-workspace index-workspace)
  (declare (type (simple-array single-float (*)) logits logit-workspace)
           (type (simple-array fixnum (*)) index-workspace)
           (single-float p temperature)
           (optimize (speed 3) (safety 1)))
  (when (or (<= p 0.0f0) (> p 1.0f0))
    (error "TOP-P must satisfy 0.0 < p <= 1.0, got ~a." p))
  (when (<= temperature 0.0f0)
    (error "TEMPERATURE must be positive, got ~a." temperature))
  (when (= p 1.0f0)
    (return-from apply-top-p-with-workspace logits))
  (let ((masked-logit -1.0f30)
        (active-count 0))
    (declare (single-float masked-logit)
             (fixnum active-count))
    (dotimes (index (length logits))
      (declare (fixnum index))
      (let ((value (aref logits index)))
        (declare (single-float value))
        (when (> value masked-logit)
          (when (>= active-count (length logit-workspace))
            (error "TOP-P workspace length ~d is too small for active count > ~d."
                  (length logit-workspace)
                  (length logit-workspace)))
          (setf (aref logit-workspace active-count) value
               (aref index-workspace active-count) index)
          (incf active-count))))
    (when (<= active-count 1)
      (return-from apply-top-p-with-workspace logits))
    ;; K is already small after top-k, so insertion sort is cheap and allocation-free.
    (do ((index 1 (1+ index)))
        ((>= index active-count))
      (declare (fixnum index))
      (let ((value (aref logit-workspace index))
            (token-index (aref index-workspace index))
            (insert-index index))
        (declare (single-float value)
                (fixnum token-index insert-index))
        (loop
          (when (zerop insert-index)
            (return))
          (when (>= (aref logit-workspace (1- insert-index)) value)
            (return))
          (setf (aref logit-workspace insert-index)
               (aref logit-workspace (1- insert-index))
               (aref index-workspace insert-index)
               (aref index-workspace (1- insert-index)))
          (decf insert-index))
        (setf (aref logit-workspace insert-index) value
             (aref index-workspace insert-index) token-index)))
    (let* ((max-scaled (/ (aref logit-workspace 0) temperature))
           (sum-exps 0.0f0))
      (declare (single-float max-scaled sum-exps))
      (dotimes (index active-count)
        (declare (fixnum index))
        (incf sum-exps
             (coerce
              (exp (- (/ (aref logit-workspace index) temperature)
                      max-scaled))
              'single-float)))
      (let ((cumulative-probability 0.0f0)
            (cutoff (aref logit-workspace (1- active-count))))
        (declare (single-float cumulative-probability cutoff))
        (dotimes (index active-count)
          (declare (fixnum index))
          (incf cumulative-probability
               (coerce
                (/ (exp (- (/ (aref logit-workspace index) temperature)
                           max-scaled))
                   sum-exps)
                'single-float))
          (when (>= cumulative-probability p)
            (setf cutoff (aref logit-workspace index))
            (return)))
        (dotimes (index (length logits) logits)
          (declare (fixnum index))
          (when (< (aref logits index) cutoff)
            (setf (aref logits index) masked-logit)))))))

(defun apply-top-p (logits p &optional (temperature 1.0f0))
  (declare (type (simple-array single-float (*)) logits)
           (single-float p temperature)
           (optimize (speed 3) (safety 1)))
  (let ((length (length logits)))
    (apply-top-p-with-workspace logits
                               p
                               temperature
                               (make-array length :element-type 'single-float)
                               (make-array length :element-type 'fixnum))))

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
                                      history
                                      (repetition-penalty 1.15f0)
                                      (top-k +default-top-k+)
                                      (top-p +default-top-p+)
                                      (temperature 1.0)
                                      top-k-workspace
                                      top-p-logit-workspace
                                      top-p-index-workspace
                                      random-value
                                      (random-state *random-state*))
  (declare (single-float repetition-penalty))
  (let* ((effective-top-k (or top-k +default-top-k+))
        (raw-top-p (or top-p +default-top-p+))
        (effective-top-p
          (if (realp raw-top-p)
              (coerce raw-top-p 'single-float)
              (error "TOP-P must be a real number or NIL, got ~s." top-p)))
        (effective-logits (if (typep logits '(simple-array single-float (*)))
                              logits
                              (ensure-single-float-array logits))))
    (declare (type (simple-array single-float (*)) effective-logits))
    (unless (and (typep effective-top-k 'fixnum)
                 (not (minusp effective-top-k)))
      (error "TOP-K must be a nonnegative fixnum or NIL, got ~s." top-k))
    (unless (and (< 0.0f0 effective-top-p)
                 (<= effective-top-p 1.0f0))
      (error "TOP-P must satisfy 0.0 < p <= 1.0, got ~s." top-p))
    (when history
      (apply-repetition-penalty effective-logits history repetition-penalty))
    (if top-k-workspace
        (apply-top-k-with-workspace
         effective-logits effective-top-k top-k-workspace)
        (apply-top-k effective-logits effective-top-k))
    (if (and top-p-logit-workspace top-p-index-workspace)
        (apply-top-p-with-workspace effective-logits
                                    effective-top-p
                                    temperature
                                    top-p-logit-workspace
                                    top-p-index-workspace)
        (apply-top-p effective-logits effective-top-p temperature))
    (sample-from-probabilities
     (softmax (apply-temperature effective-logits temperature))
     :random-value random-value
     :random-state random-state)))

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
                             history
                             (repetition-penalty 1.15f0)
                             (top-k +default-top-k+)
                             (top-p +default-top-p+)
                             (temperature 1.0)
                             top-k-workspace
                             top-p-logit-workspace
                             top-p-index-workspace
                             random-value
                             (random-state *random-state*))
  (let* ((token-id (sample-token-id-from-logits logits
                                               :history history
                                               :repetition-penalty repetition-penalty
                                               :top-k top-k
                                               :top-p top-p
                                               :temperature temperature
                                               :top-k-workspace top-k-workspace
                                               :top-p-logit-workspace top-p-logit-workspace
                                               :top-p-index-workspace top-p-index-workspace
                                               :random-value random-value
                                               :random-state random-state))
         (token-text (detokenize-token-id kv-pairs token-id)))
    (values token-id token-text)))

(defun gpt2-tokenizer-p (kv-pairs)
  (string= (or (tokenizer-model kv-pairs) "")
          "gpt2"))

(defun generate-token-loop (kv-pairs initial-logits step-function kv-cache
                             &key
                               eos-token-id
                               stop-token-ids
                               (start-position 0)
                               (repetition-penalty 1.15f0)
                               (top-k +default-top-k+)
                              (top-p +default-top-p+)
                              (temperature 1.0)
                              (max-tokens 256)
                              random-values
                              callback
                              (stream *standard-output*)
                              (random-state *random-state*))
  (let ((effective-top-k (or top-k +default-top-k+))
        (current-logits initial-logits)
        (generated-token-ids '())
        (top-k-workspace nil)
        (top-p-logit-workspace nil)
        (top-p-index-workspace nil)
        (effective-stop-token-ids
         (remove-duplicates (remove nil (append stop-token-ids
                                                (when eos-token-id
                                                  (list eos-token-id))))
                            :test #'=)))
    (unless (and (typep effective-top-k 'fixnum)
                (not (minusp effective-top-k)))
      (error "TOP-K must be a nonnegative fixnum or NIL, got ~s." top-k))
    (let ((workspace-size
           (max 1 (if (zerop effective-top-k)
                      (length initial-logits)
                      effective-top-k))))
      (declare (fixnum workspace-size))
      (setf top-k-workspace
           (make-array workspace-size :element-type 'single-float)
           top-p-logit-workspace
           (make-array workspace-size :element-type 'single-float)
           top-p-index-workspace
           (make-array workspace-size :element-type 'fixnum)))
    (dotimes (decode-index max-tokens)
      (declare (fixnum decode-index))
      (multiple-value-bind (token-id token-text)
         (decode-next-token kv-pairs
                             current-logits
                             :history generated-token-ids
                             :repetition-penalty repetition-penalty
                             :top-k effective-top-k
                             :top-p top-p
                             :temperature temperature
                             :top-k-workspace top-k-workspace
                             :top-p-logit-workspace top-p-logit-workspace
                             :top-p-index-workspace top-p-index-workspace
                             :random-value (when random-values
                                             (pop random-values))
                             :random-state random-state)
        (when (member token-id effective-stop-token-ids :test #'=)
          (return))
        (push token-id generated-token-ids)
        (unless (gpt2-tokenizer-p kv-pairs)
          (write-string token-text stream)
          (when callback
            (funcall callback token-text)))
        (setf current-logits
              (funcall step-function
                       token-id
                       (+ start-position decode-index)
                       kv-cache))))
    (let* ((ordered-token-ids (nreverse generated-token-ids))
           (generated-text
            (if (gpt2-tokenizer-p kv-pairs)
                (detokenize-token-ids kv-pairs ordered-token-ids stream)
                (detokenize-token-ids kv-pairs ordered-token-ids (make-broadcast-stream)))))
      (when (and callback (gpt2-tokenizer-p kv-pairs))
        (funcall callback generated-text))
      (values ordered-token-ids generated-text current-logits))))

(defun gemma4-chat-prompt-p (prompt)
  (or (search "<|turn>" prompt)
      (search "<turn|>" prompt)
      (search "<bos>" prompt)))

(defun llama3-tokenizer-p (kv-pairs)
  (and (string= (or (tokenizer-model kv-pairs) "") "gpt2")
       (string= (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.pre") "")
                "llama-bpe")))

(defun qwen2-tokenizer-p (kv-pairs)
  (and (string= (or (tokenizer-model kv-pairs) "") "gpt2")
       (string= (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.pre") "")
                "qwen2")))

(defun llama3-chat-prompt-p (prompt)
  (or (search "<|begin_of_text|>" prompt)
      (search "<|start_header_id|>" prompt)))

(defun qwen2-chat-prompt-p (prompt)
  (search "<|im_start|>" prompt))

(defun gemma4-chat-template-uses-channel-p (chat-template)
  (when chat-template
    (let* ((model-turn-index (search "<|turn>model" chat-template :from-end t))
           (tail (and model-turn-index
                      (subseq chat-template
                              model-turn-index
                              (min (length chat-template)
                                   (+ model-turn-index 256))))))
      (and tail
           (search "<|channel>thought" tail)
           (search "<channel|>" tail)))))

(defun maybe-prepare-prompt-for-generation (kv-pairs prompt add-bos
                                          &key
                                            use-thought-channel)
  (let ((chat-template (gguf-kv-value-or-nil kv-pairs "tokenizer.chat_template")))
    (cond
      ((and (string= (or (tokenizer-model kv-pairs) "") "gemma4")
            chat-template
            (not (gemma4-chat-prompt-p prompt)))
       (values (if (and use-thought-channel
                        (gemma4-chat-template-uses-channel-p chat-template))
                   (format nil "<bos><|turn>user~%~a<turn|>~%<|turn>model~%<|channel>thought~%<channel|>"
                           prompt)
                   (format nil "<bos><|turn>user~%~a<turn|>~%<|turn>model~%"
                           prompt))
              nil))
      ((and (llama3-tokenizer-p kv-pairs)
            chat-template
            (not (llama3-chat-prompt-p prompt)))
       (values (format nil
                      "<|begin_of_text|><|start_header_id|>user<|end_header_id|>~%~%~a<|eot_id|><|start_header_id|>assistant<|end_header_id|>~%~%"
                      prompt)
              nil))
      ((and (llama3-tokenizer-p kv-pairs)
            (search "<|begin_of_text|>" prompt))
       (values prompt nil))
      ((and (qwen2-tokenizer-p kv-pairs)
            chat-template
            (not (qwen2-chat-prompt-p prompt)))
       (values (format nil
                       "<|im_start|>system~%You are a helpful assistant.<|im_end|>~%<|im_start|>user~%~a<|im_end|>~%<|im_start|>assistant~%"
                       prompt)
               nil))
      ((qwen2-tokenizer-p kv-pairs)
       (values prompt nil))
      (t
       (values prompt add-bos)))))

(defun generate-from-prompt (kv-pairs prompt step-function kv-cache
                              &key
                                (add-bos t)
                                use-thought-channel
                                eos-token-id
                                (repetition-penalty 1.15f0)
                                (top-k +default-top-k+)
                                (top-p +default-top-p+)
                                (temperature 1.0)
                                (max-tokens 256)
                                random-values
                                callback
                                (stream *standard-output*)
                                (random-state *random-state*))
  (multiple-value-bind (prepared-prompt effective-add-bos)
      (maybe-prepare-prompt-for-generation kv-pairs
                                          prompt
                                          add-bos
                                          :use-thought-channel use-thought-channel)
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
                           :repetition-penalty repetition-penalty
                           :top-k top-k
                           :top-p top-p
                           :temperature temperature
                           :max-tokens max-tokens
                           :random-values random-values
                           :callback callback
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
    (when (llama3-tokenizer-p kv-pairs)
      (let ((token-id-table (tokenizer-token-id-table kv-pairs)))
        (dolist (token '("<|eot_id|>" "<|end_of_text|>"))
          (multiple-value-bind (token-id presentp)
              (gethash token token-id-table)
            (when presentp
              (push token-id stop-token-ids))))))
    (when (qwen2-tokenizer-p kv-pairs)
      (let ((token-types (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.token_type"))
            (token-id 0))
        (when token-types
          (dolist (token-type token-types)
            (when (and (integerp token-type)
                       (<= 3 token-type))
              (push token-id stop-token-ids))
            (incf token-id)))))
    (nreverse (remove-duplicates stop-token-ids :test #'=))))

(defun generate-gguf-response (pathname
                              &key
                                 (prompt "Hello, How are you?")
                                 step-function
                                 kv-cache
                                 eos-token-id
                                 use-thought-channel
                                 (repetition-penalty 1.15f0)
                                 (top-k +default-top-k+)
                                 (top-p +default-top-p+)
                                 (temperature 1.0)
                                 (max-tokens 256)
                                 random-values
                                 (use-npu nil)
                                 npu-tensor-names
                                 npu-layer-indices
                                 (npu-projection-roles
                                   '(:attention-query
                                     :attention-key
                                     :attention-value
                                     :attention-output
                                     :ffn-gate
                                     :ffn-up
                                     :ffn-down))
                                 (npu-cache-directory
                                   (default-npu-cache-directory))
                                 (npu-python-command '("python"))
                                 (use-gpu nil)
                                 gpu-tensor-names
                                 gpu-layer-indices
                                 (gpu-projection-roles
                                   '(:attention-query
                                     :attention-key
                                     :attention-value
                                     :attention-output
                                     :ffn-gate
                                     :ffn-up
                                     :ffn-down))
                                 (gpu-cache-directory
                                   (default-gpu-cache-directory))
                                 (gpu-python-command '("python"))
                                 callback
                                 print-metadata
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
                                         (cond
                                           ((string= architecture "gemma4")
                                            (load-gemma4-model mapping kv-pairs tensor-infos))
                                           ((string= architecture "nemotron_h_moe")
                                            (load-nemotron-h-moe-model mapping kv-pairs tensor-infos))
                                           ((string= architecture "qwen3next")
                                            (load-qwen3next-model mapping kv-pairs tensor-infos))
                                           ((string= architecture "llama")
                                            (load-llama-model mapping kv-pairs tensor-infos))
                                           ((string= architecture "qwen2")
                                            (load-qwen2-model mapping kv-pairs tensor-infos))
                                           (t nil))))
                             (npu-requested-p
                               (and use-npu
                                    (or npu-tensor-names
                                        npu-layer-indices)))
                             (gpu-requested-p
                               (and use-gpu
                                    (or gpu-tensor-names
                                        gpu-layer-indices)))
                             (effective-step-function (or step-function
                                                          (and model
                                                               (case (intern (string-upcase architecture)
                                                                             :keyword)
                                                                 (:GEMMA4 (make-gemma4-step-function model))
                                                                 (:NEMOTRON_H_MOE (make-nemotron-h-moe-step-function model))
                                                                 (:QWEN3NEXT (make-qwen3next-step-function model))
                                                                 (:LLAMA (make-llama-step-function model))
                                                                 (:QWEN2 (make-qwen2-step-function model))
                                                                 (otherwise nil)))))
                             (effective-kv-cache (or kv-cache (make-hash-table)))
                             (effective-eos-token-id
                              (or eos-token-id (resolve-eos-token-id kv-pairs))))
                        (unwind-protect
                            (progn
                             (when (and use-npu (not npu-requested-p))
                               (warn "NPU acceleration was requested without any usable projections; continuing on the CPU."))
                             (when npu-requested-p
                               (if model
                                   (try-enable-model-npu-projections
                                    model
                                    npu-tensor-names
                                    :layer-indices npu-layer-indices
                                    :projection-roles npu-projection-roles
                                    :cache-directory npu-cache-directory
                                    :python-command npu-python-command)
                                   (warn "NPU acceleration requires the built-in model loader; continuing on the CPU.")))
                             (when (and use-gpu (not gpu-requested-p))
                               (warn "GPU acceleration was requested without any usable projections; continuing without GPU acceleration."))
                             (when gpu-requested-p
                               (if model
                                   (try-enable-model-gpu-projections
                                    model
                                    gpu-tensor-names
                                    :layer-indices gpu-layer-indices
                                    :projection-roles gpu-projection-roles
                                    :cache-directory gpu-cache-directory
                                    :python-command gpu-python-command)
                                   (warn "GPU acceleration requires the built-in model loader; continuing without GPU acceleration.")))
                             (when print-metadata
                               (format stream "Model: ~a~%" pathname)
                               (format stream "Architecture: ~a~%" architecture)
                               (format stream "Prompt: ~a~%Response: " prompt))
                             (unless effective-step-function
                               (error
                                "Cannot run prompt against ~a yet: GGUF metadata loaded (~a, ~d tensors), but tensor loading and the real forward-pass step function are not implemented."
                                pathname
                                architecture
                                (getf header :tensor-count)))
                             (multiple-value-bind
                                   (generated-ids generated-text last-logits)
                                 (generate-from-prompt
                                  kv-pairs
                                  prompt
                                  effective-step-function
                                  effective-kv-cache
                                  :use-thought-channel use-thought-channel
                                  :eos-token-id effective-eos-token-id
                                  :repetition-penalty repetition-penalty
                                  :top-k top-k
                                  :top-p top-p
                                  :temperature temperature
                                  :max-tokens max-tokens
                                  :random-values random-values
                                  :callback callback
                                  :stream stream
                                  :random-state random-state)
                               (when print-metadata
                                 (terpri stream))
                               (values header
                                       kv-pairs
                                       generated-ids
                                       generated-text
                                       last-logits)))
                          (when model
                            (close-model model))))))))

(defun test-gguf-file-response (pathname &rest arguments)
  (apply #'generate-gguf-response pathname :print-metadata t arguments))

(defun test-llm-response (kv-pairs step-function kv-cache
                           &key
                             use-thought-channel
                             eos-token-id
                             (repetition-penalty 1.15f0)
                             (top-k +default-top-k+)
                             (top-p +default-top-p+)
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
                              :use-thought-channel use-thought-channel
                              :eos-token-id eos-token-id
                              :repetition-penalty repetition-penalty
                              :top-k top-k
                              :top-p top-p
                              :temperature temperature
                              :max-tokens max-tokens
                              :random-values random-values
                              :stream stream
                              :random-state random-state)
      (terpri stream)
      (values generated-ids generated-text last-logits))))

(defun test-gemma4-e2b-it-response (&key
                                      (stream *standard-output*)
                                      use-thought-channel
                                      (repetition-penalty 1.15f0)
                                      (top-k +default-top-k+)
                                      (top-p +default-top-p+)
                                      (temperature 1.0)
                                      (max-tokens 256)
                                      random-values
                                      (random-state *random-state*))
  (test-gguf-file-response
   #P"D:/Models/lmstudio-community/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-Q4_K_M.gguf"
   :prompt "<bos><|turn>user
Write a haiku about a hacker drinking coffee.<turn|>
<|turn>model
"
:use-thought-channel use-thought-channel
:repetition-penalty repetition-penalty
:top-k top-k
:top-p top-p
:temperature temperature
:max-tokens max-tokens
:random-values random-values
:stream stream
   :random-state random-state))

(defun gguf-read-u32-le (region offset description)
  (ensure-mapped-range region offset 4 description)
  (read-u32-le (mapped-region-pointer region) offset))

(defun gguf-read-u64-le (region offset description)
  (ensure-mapped-range region offset 8 description)
  (read-u64-le (mapped-region-pointer region) offset))

(defun gguf-read-octets (region offset length description)
  (ensure-mapped-range region offset length description)
  (unless (<= length array-dimension-limit)
    (error "~a length ~d exceeds the Lisp array dimension limit."
           description
           length))
  (read-octets (mapped-region-pointer region) offset length))

(defun gguf-value-minimum-byte-size (type-tag)
  (case type-tag
    ((0 1 7) 1)
    ((2 3) 2)
    ((4 5 6) 4)
    ((8 10 11 12) 8)
    (9 12)
    (otherwise
     (error "Unsupported GGUF metadata value type: ~a." type-tag))))

(defun ensure-gguf-count-fits
    (region offset count minimum-byte-size description)
  (unless (and (integerp count) (not (minusp count)))
    (error "~a has invalid count ~s." description count))
  (let ((remaining (- (mapped-region-byte-length region) offset)))
    (unless (and (not (minusp remaining))
                (<= count (floor remaining minimum-byte-size)))
      (error "~a count ~d cannot fit in the ~d mapped bytes remaining."
             description
             count
             (max remaining 0))))
  count)

(defun read-gguf-string (region offset)
  (let* ((length (gguf-read-u64-le region offset "GGUF string length"))
         (start (+ offset 8))
         (end (+ start length)))
    (values (octets-to-utf8-string
             (gguf-read-octets region start length "GGUF string"))
            end)))

(defun read-gguf-value (region offset type-tag)
  (let ((pointer (mapped-region-pointer region)))
  (case type-tag
    (0 (ensure-mapped-range region offset 1 "GGUF uint8 metadata value")
       (values (cffi:mem-aref pointer :unsigned-char offset)
               (+ offset 1)))
    (1 (ensure-mapped-range region offset 1 "GGUF int8 metadata value")
       (values (unsigned-to-signed
                (cffi:mem-aref pointer :unsigned-char offset)
                8)
               (+ offset 1)))
    (2 (ensure-mapped-range region offset 2 "GGUF uint16 metadata value")
       (values (read-u16-le pointer offset)
               (+ offset 2)))
    (3 (ensure-mapped-range region offset 2 "GGUF int16 metadata value")
       (values (unsigned-to-signed (read-u16-le pointer offset) 16)
               (+ offset 2)))
    (4 (values (gguf-read-u32-le region offset "GGUF uint32 metadata value")
               (+ offset 4)))
    (5 (values (unsigned-to-signed
               (gguf-read-u32-le region offset "GGUF int32 metadata value")
               32)
               (+ offset 4)))
    (6 (ensure-mapped-range region offset 4 "GGUF float32 metadata value")
       (values (cffi:mem-ref (cffi:inc-pointer pointer offset) :float)
               (+ offset 4)))
    (7 (ensure-mapped-range region offset 1 "GGUF boolean metadata value")
       (values (not (zerop (cffi:mem-aref pointer :unsigned-char offset)))
               (+ offset 1)))
    (8 (read-gguf-string region offset))
    (9 (let ((element-type
               (gguf-read-u32-le region offset
                                "GGUF metadata array element type"))
             (length
               (gguf-read-u64-le region (+ offset 4)
                                "GGUF metadata array length"))
             (cursor (+ offset 12))
             (values '()))
         (when (= element-type 9)
           (error "Nested GGUF metadata arrays are unsupported."))
         (ensure-gguf-count-fits
          region
          cursor
          length
          (gguf-value-minimum-byte-size element-type)
          "GGUF metadata array")
         (loop repeat length
               do
           (multiple-value-bind (element next-cursor)
               (read-gguf-value region cursor element-type)
             (push element values)
             (setf cursor next-cursor)))
         (values (nreverse values) cursor)))
    (10 (values (gguf-read-u64-le region offset "GGUF uint64 metadata value")
                (+ offset 8)))
    (11 (values (unsigned-to-signed
                (gguf-read-u64-le region offset "GGUF int64 metadata value")
                64)
                (+ offset 8)))
    (12 (ensure-mapped-range region offset 8 "GGUF float64 metadata value")
        (values (cffi:mem-ref (cffi:inc-pointer pointer offset) :double)
                (+ offset 8)))
    (otherwise
     (error "Unsupported GGUF metadata value type: ~a." type-tag)))))

(defun read-gguf-header (mapped-file)
  (let* ((region (require-mapped-region mapped-file "READ-GGUF-HEADER"))
         (magic
           (map 'string
               #'code-char
               (gguf-read-octets region 0 4 "GGUF magic"))))
    (unless (string= magic "GGUF")
      (error "Invalid GGUF magic: ~s." magic))
    (list :magic magic
          :version (gguf-read-u32-le region 4 "GGUF version")
          :tensor-count (gguf-read-u64-le region 8 "GGUF tensor count")
          :metadata-kv-count
          (gguf-read-u64-le region 16 "GGUF metadata count")
          :header-size 24)))

(defun read-gguf-metadata-section (mapped-file)
  (let* ((region
           (require-mapped-region mapped-file "READ-GGUF-METADATA-SECTION"))
         (header (read-gguf-header mapped-file))
         (cursor (getf header :header-size))
         (metadata-kv-count (getf header :metadata-kv-count))
         (pairs '()))
    (ensure-gguf-count-fits
     region cursor metadata-kv-count 13 "GGUF metadata")
    (loop repeat metadata-kv-count
          do
      (multiple-value-bind (key key-end)
          (read-gguf-string region cursor)
        (let ((type-tag
               (gguf-read-u32-le region key-end
                                 "GGUF metadata value type")))
          (multiple-value-bind (value next-cursor)
              (read-gguf-value region (+ key-end 4) type-tag)
            (push (cons key value) pairs)
            (setf cursor next-cursor)))))
    (values (nreverse pairs) cursor)))

(defun read-gguf-kv-pairs (mapped-file)
  (nth-value 0 (read-gguf-metadata-section mapped-file)))

(defun align-offset (offset alignment)
  (* alignment (ceiling offset alignment)))

(defun gguf-alignment (kv-pairs)
  (let ((alignment
          (or (gguf-kv-value-or-nil kv-pairs "general.alignment")
              32)))
    (unless (and (integerp alignment)
                 (plusp alignment)
                 (zerop (logand alignment (1- alignment))))
      (error "GGUF alignment must be a positive power of two, got ~s."
             alignment))
    alignment))

(defun supported-ggml-type-p (type-tag)
  (member type-tag
          (list +ggml-type-f32+
                +ggml-type-f16+
                +ggml-type-q5-0+
                +ggml-type-q8-0+
                +ggml-type-bf16+
                +ggml-type-q4-k+
                +ggml-type-q5-k+
                +ggml-type-q6-k+)))

(defun ggml-type-name (type-tag)
  (case type-tag
    (#.+ggml-type-f32+ :f32)
    (#.+ggml-type-f16+ :f16)
    (#.+ggml-type-q5-0+ :q5-0)
    (#.+ggml-type-q8-0+ :q8-0)
    (#.+ggml-type-bf16+ :bf16)
    (#.+ggml-type-q4-k+ :q4-k)
    (#.+ggml-type-q5-k+ :q5-k)
    (#.+ggml-type-q6-k+ :q6-k)
    (otherwise (intern (format nil "TYPE-~D" type-tag) :keyword))))

(defun ggml-type-block-size (type-tag)
  (case type-tag
    ((#.+ggml-type-f32+ #.+ggml-type-f16+ #.+ggml-type-bf16+) 1)
    ((#.+ggml-type-q5-0+ #.+ggml-type-q8-0+) 32)
    (#.+ggml-type-q4-k+ +qk-k+)
    (#.+ggml-type-q5-k+ +qk-k+)
    (#.+ggml-type-q6-k+ +qk-k+)
    (otherwise (error "Unsupported GGML tensor type tag ~a." type-tag))))

(defun ggml-type-size (type-tag)
  (case type-tag
    (#.+ggml-type-f32+ 4)
    (#.+ggml-type-f16+ 2)
    (#.+ggml-type-q5-0+ (+ 2 4 16))
    (#.+ggml-type-q8-0+ (+ 2 32))
    (#.+ggml-type-bf16+ 2)
    (#.+ggml-type-q4-k+ (+ 4 +k-scale-size+ (/ +qk-k+ 2)))
    (#.+ggml-type-q5-k+ (+ 4 +k-scale-size+ (/ +qk-k+ 8) (/ +qk-k+ 2)))
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
  (let* ((region
           (require-mapped-region mapped-file "READ-GGUF-TENSOR-INFOS"))
         (header (read-gguf-header mapped-file))
         (tensor-count (getf header :tensor-count)))
    (multiple-value-bind (kv-pairs cursor)
        (read-gguf-metadata-section mapped-file)
      (let ((tensor-infos '()))
        (ensure-gguf-count-fits
         region cursor tensor-count 24 "GGUF tensor info")
        (loop repeat tensor-count
              do
          (multiple-value-bind (name name-end)
              (read-gguf-string region cursor)
            (let* ((dimension-count
                     (gguf-read-u32-le region name-end
                                      "GGUF tensor dimension count"))
                   (dimension-cursor (+ name-end 4)))
              (unless (<= 1 dimension-count 4)
                (error "Tensor ~s has invalid dimension count ~d; GGUF permits 1 through 4."
                       name
                       dimension-count))
              (ensure-mapped-range
               region
               dimension-cursor
               (+ (* dimension-count 8) 12)
               "GGUF tensor dimensions, type, and offset")
              (let* ((dimensions (let ((dimensions '()))
                                 (dotimes (dimension-index dimension-count (nreverse dimensions))
                                   (declare (fixnum dimension-index))
                                   (push (gguf-read-u64-le
                                          region
                                          (+ dimension-cursor
                                             (* dimension-index 8))
                                          "GGUF tensor dimension")
                                         dimensions))))
                   (type-cursor (+ dimension-cursor (* dimension-count 8)))
                   (type-tag
                     (gguf-read-u32-le region type-cursor
                                      "GGUF tensor type"))
                   (offset
                     (gguf-read-u64-le region (+ type-cursor 4)
                                      "GGUF tensor offset"))
                   (next-cursor (+ type-cursor 12))
                   (element-count (reduce #'* dimensions :initial-value 1))
                   (byte-size (when (supported-ggml-type-p type-tag)
                                (ggml-tensor-byte-size type-tag element-count))))
                (unless (every #'plusp dimensions)
                  (error "Tensor ~s has non-positive dimensions ~s."
                         name
                         dimensions))
                (push (list :name name
                            :dimension-count dimension-count
                            :dimensions dimensions
                            :type-tag type-tag
                            :type-name (ggml-type-name type-tag)
                            :offset offset
                            :element-count element-count
                            :byte-size byte-size)
                      tensor-infos)
                (setf cursor next-cursor)))))
        (let ((tensor-data-start (align-offset cursor (gguf-alignment kv-pairs))))
          (when tensor-infos
            (ensure-mapped-range
             region tensor-data-start 0 "GGUF tensor data start"))
          (mapcar (lambda (tensor-info)
                    (let* ((data-offset
                             (+ tensor-data-start
                                (getf tensor-info :offset)))
                           (byte-size (getf tensor-info :byte-size)))
                      (ensure-mapped-range
                       region
                       data-offset
                       (or byte-size 0)
                       (format nil "GGUF tensor ~s"
                               (getf tensor-info :name)))
                      (append tensor-info
                              (list :data-offset data-offset
                                    :data-end
                                    (and byte-size
                                         (+ data-offset byte-size))))))
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
         (byte-size (getf tensor-info :byte-size))
         (tensor-pointer (cffi:inc-pointer mapped-file
                                           (getf tensor-info :data-offset))))
    (let ((region (find-mapped-region mapped-file)))
      (when (and region byte-size)
        (ensure-mapped-range
         region
         (getf tensor-info :data-offset)
         byte-size
         (format nil "GGUF tensor ~s" (getf tensor-info :name)))))
    (case type-tag
      (#.+ggml-type-f32+ (load-f32-tensor tensor-pointer element-count))
      (#.+ggml-type-f16+ (load-f16-tensor tensor-pointer element-count))
      (#.+ggml-type-q5-0+ (dequantize-q5-0 tensor-pointer element-count))
      (#.+ggml-type-q8-0+ (dequantize-q8-0 tensor-pointer element-count))
      (#.+ggml-type-bf16+ (load-bf16-tensor tensor-pointer element-count))
      (#.+ggml-type-q4-k+ (dequantize-q4-k-m tensor-pointer element-count))
      (#.+ggml-type-q5-k+ (dequantize-q5-k tensor-pointer element-count))
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
  output-tensor-name
  (npu-projections (make-hash-table :test #'equal))
  (gpu-projections (make-hash-table :test #'equal))
  (closed-p nil))

(defun ensure-model-open (model operation)
  (when (gguf-model-closed-p model)
    (error "~a cannot use a closed GGUF model." operation))
  model)

(defun register-model-npu-projection
    (model tensor-name onnx-path &key cache-directory cache-key)
  (ensure-model-open model "REGISTER-MODEL-NPU-PROJECTION")
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (projections (gguf-model-npu-projections model)))
    (when (gethash tensor-name projections)
      (error "Tensor ~s already has an NPU projection." tensor-name))
    (let ((session (make-npu-session onnx-path
                                     :cache-directory cache-directory
                                     :cache-key cache-key)))
      (unwind-protect
          (progn
            (unless (= (tensor-column-count tensor-info)
                       (npu-session-input-element-count session))
              (error "NPU input size does not match tensor ~s." tensor-name))
            (unless (= (tensor-row-count tensor-info)
                       (npu-session-output-element-count session))
              (error "NPU output size does not match tensor ~s." tensor-name))
            (setf (gethash tensor-name projections) session)
            (setf session nil))
        (when session
          (close-npu-session session)))))
  model)

(defun unregister-model-npu-projection (model tensor-name)
  (let* ((projections (gguf-model-npu-projections model))
         (session (gethash tensor-name projections)))
    (when session
      (remhash tensor-name projections)
      (close-npu-session session)))
  model)

(defun clear-model-npu-projections (model)
  (maphash (lambda (tensor-name session)
             (declare (ignore tensor-name))
             (close-npu-session session))
           (gguf-model-npu-projections model))
  (clrhash (gguf-model-npu-projections model))
  model)

(defun register-model-gpu-projection (model tensor-name onnx-path)
  (ensure-model-open model "REGISTER-MODEL-GPU-PROJECTION")
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (projections (gguf-model-gpu-projections model)))
    (when (gethash tensor-name projections)
      (error "Tensor ~s already has a GPU projection." tensor-name))
    (let ((session (make-gpu-session onnx-path)))
      (unwind-protect
          (progn
            (unless (= (tensor-column-count tensor-info)
                       (gpu-session-input-element-count session))
              (error "GPU input size does not match tensor ~s." tensor-name))
            (unless (= (tensor-row-count tensor-info)
                       (gpu-session-output-element-count session))
              (error "GPU output size does not match tensor ~s." tensor-name))
            (setf (gethash tensor-name projections) session)
            (setf session nil))
        (when session
          (close-gpu-session session)))))
  model)

(defun unregister-model-gpu-projection (model tensor-name)
  (let* ((projections (gguf-model-gpu-projections model))
         (session (gethash tensor-name projections)))
    (when session
      (remhash tensor-name projections)
      (close-gpu-session session)))
  model)

(defun clear-model-gpu-projections (model)
  (maphash (lambda (tensor-name session)
             (declare (ignore tensor-name))
             (close-gpu-session session))
           (gguf-model-gpu-projections model))
  (clrhash (gguf-model-gpu-projections model))
  model)

(defun close-model (model)
  "Release accelerator sessions and cached tensors owned by MODEL.

The GGUF mapping is borrowed from the surrounding WITH-MAPPED-FILE scope and
is invalidated here, but its handle remains owned by that scope."
  (unless (gguf-model-closed-p model)
    (clear-model-gpu-projections model)
    (clear-model-npu-projections model)
    (let ((tensor-cache (gguf-model-tensor-cache model)))
      (when tensor-cache
        (clrhash tensor-cache)))
    (setf (gguf-model-mapping model) nil
          (gguf-model-closed-p model) t))
  model)

(defun tensor-content-sha256 (model tensor-info)
  (require-npu-backend)
  (let ((byte-size (getf tensor-info :byte-size))
        (data-offset (getf tensor-info :data-offset)))
    (unless (and byte-size data-offset)
      (error "Tensor ~s does not have mapped byte-size and offset metadata."
             (getf tensor-info :name)))
    (cffi:with-foreign-object (output :char 65)
      (check-npu-status
       (%npu-sha256
        (cffi:inc-pointer (gguf-model-mapping model) data-offset)
        byte-size
        output
        65)
       "Tensor SHA-256")
      (cffi:foreign-string-to-lisp output :encoding :ascii))))

(defun byte-vector-sha256 (octets)
  (cffi:with-foreign-object (output :char 65)
    (cffi:with-pointer-to-vector-data (input octets)
      (check-npu-status
       (%npu-sha256 input (length octets) output 65)
       "Byte vector SHA-256"))
    (cffi:foreign-string-to-lisp output :encoding :ascii)))

(defun file-sha256 (pathname)
  (with-open-file (stream pathname :element-type '(unsigned-byte 8))
    (let* ((length (file-length stream))
           (octets (make-array length :element-type '(unsigned-byte 8))))
      (unless (= length (read-sequence octets stream))
        (error "Unable to read all bytes from ~a." pathname))
      (byte-vector-sha256 octets))))

(defun default-npu-cache-directory ()
  (let ((base (or (uiop:getenv "LOCALAPPDATA")
                  (uiop:native-namestring (uiop:temporary-directory)))))
    (merge-pathnames #P"llambda/npu-cache/"
                     (uiop:ensure-directory-pathname base))))

(defun default-gpu-cache-directory ()
  (default-npu-cache-directory))

(defun npu-cache-component (value)
  (map 'string
       (lambda (character)
         (if (or (alphanumericp character)
                 (char= character #\-)
                 (char= character #\.))
             character
             #\-))
       value))

(defun model-npu-projection-cache-key
    (model tensor-info generator-path &key (weight-format :bfloat16))
  (format nil "bridge-~a-generator-~a-ort-~a-weights-~(~a~)-ggml-~d-~{~d~^-~}-~a"
          (npu-cache-component (npu-bridge-version))
          (file-sha256 generator-path)
          (npu-cache-component (npu-backend-runtime-version))
          weight-format
          (getf tensor-info :type-tag)
          (getf tensor-info :dimensions)
          (tensor-content-sha256 model tensor-info)))

(defun model-npu-projection-cache-pathnames
    (model tensor-name &optional (cache-directory
                                  (default-npu-cache-directory))
                              (generator-path
                                (default-npu-model-generator-pathname))
     &key (weight-format :bfloat16))
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (cache-key
           (model-npu-projection-cache-key
            model tensor-info generator-path
            :weight-format weight-format))
         (root (uiop:ensure-directory-pathname cache-directory))
         (projection-directory
           (merge-pathnames
            (make-pathname :directory `(:relative ,cache-key))
            root)))
    (values (merge-pathnames #P"projection.onnx" projection-directory)
            root
            cache-key)))

(defun ensure-model-npu-projection
    (model tensor-name
     &key
       (cache-directory (default-npu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (when (gethash tensor-name (gguf-model-npu-projections model))
    (return-from ensure-model-npu-projection (values model nil t)))
  (multiple-value-bind (onnx-path provider-cache-directory cache-key)
      (model-npu-projection-cache-pathnames
       model tensor-name cache-directory generator-path)
    (let ((reused-p (not (null (probe-file onnx-path)))))
      (unless reused-p
        (export-model-npu-projection
         model tensor-name onnx-path
         :python-command python-command
         :generator-path generator-path))
      (register-model-npu-projection
       model tensor-name onnx-path
       :cache-directory provider-cache-directory
       :cache-key cache-key)
      (values model onnx-path reused-p))))

(defun enable-model-npu-projections
    (model tensor-names
     &key
       (cache-directory (default-npu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (let ((added-tensor-names '())
        (completed-p nil))
    (unwind-protect
        (progn
          (dolist (tensor-name tensor-names)
            (unless (gethash tensor-name
                             (gguf-model-npu-projections model))
              (ensure-model-npu-projection
               model tensor-name
               :cache-directory cache-directory
               :python-command python-command
               :generator-path generator-path)
              (push tensor-name added-tensor-names)))
          (setf completed-p t)
          model)
      (unless completed-p
        (dolist (tensor-name added-tensor-names)
          (unregister-model-npu-projection model tensor-name))))))

(defun ensure-model-gpu-projection
    (model tensor-name
     &key
       (cache-directory (default-gpu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (when (gethash tensor-name (gguf-model-gpu-projections model))
    (return-from ensure-model-gpu-projection (values model nil t)))
  (multiple-value-bind (onnx-path provider-cache-directory cache-key)
      (model-npu-projection-cache-pathnames
       model tensor-name cache-directory generator-path
       :weight-format :float32)
    (declare (ignore provider-cache-directory cache-key))
    (let ((reused-p (not (null (probe-file onnx-path)))))
      (unless reused-p
        (export-model-gpu-projection
          model tensor-name onnx-path
          :python-command python-command
          :generator-path generator-path))
      (register-model-gpu-projection model tensor-name onnx-path)
      (values model onnx-path reused-p))))

(defun enable-model-gpu-projections
    (model tensor-names
     &key
       (cache-directory (default-gpu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (let ((added-tensor-names '())
        (completed-p nil))
    (unwind-protect
        (progn
           (dolist (tensor-name tensor-names)
             (unless (gethash tensor-name
                              (gguf-model-gpu-projections model))
               (ensure-model-gpu-projection
                model tensor-name
                :cache-directory cache-directory
                :python-command python-command
                :generator-path generator-path)
               (push tensor-name added-tensor-names)))
           (setf completed-p t)
           model)
      (unless completed-p
        (dolist (tensor-name added-tensor-names)
           (unregister-model-gpu-projection model tensor-name))))))

(defun call-with-npu-setup-fallback (setup-function)
  (handler-case
      (funcall setup-function)
    (error (condition)
      (warn "NPU setup failed; continuing on the CPU: ~a" condition)
      nil)))

(defun call-with-gpu-setup-fallback (setup-function)
  (handler-case
      (funcall setup-function)
    (error (condition)
      (warn "GPU setup failed; continuing without GPU acceleration: ~a"
            condition)
      nil)))

(defun try-enable-model-npu-projections
    (model tensor-names
     &key
       layer-indices
       (projection-roles
         '(:attention-query
           :attention-key
           :attention-value
           :attention-output
           :ffn-gate
           :ffn-up
           :ffn-down))
       (cache-directory (default-npu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (call-with-npu-setup-fallback
   (lambda ()
     (let ((resolved-tensor-names
             (remove-duplicates
              (append tensor-names
                      (when layer-indices
                        (model-npu-layer-projection-names
                         model
                         layer-indices
                         :roles projection-roles)))
              :test #'equal)))
       (unless resolved-tensor-names
         (npu-backend-error
          "NPU acceleration was requested without any projections."))
     (unless *npu-library*
       (load-npu-backend))
     (unless (npu-backend-available-p)
       (npu-backend-error "NPU acceleration is unavailable."))
     (enable-model-npu-projections
      model
      resolved-tensor-names
      :cache-directory cache-directory
      :python-command python-command
      :generator-path generator-path)
       t))))

(defun try-enable-model-gpu-projections
    (model tensor-names
     &key
       layer-indices
       (projection-roles
         '(:attention-query
           :attention-key
           :attention-value
           :attention-output
           :ffn-gate
           :ffn-up
           :ffn-down))
       (cache-directory (default-gpu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (call-with-gpu-setup-fallback
   (lambda ()
     (let ((resolved-tensor-names
             (remove-duplicates
              (append tensor-names
                      (when layer-indices
                        (model-npu-layer-projection-names
                         model
                         layer-indices
                         :roles projection-roles)))
              :test #'equal)))
       (unless resolved-tensor-names
         (gpu-backend-error
          "GPU acceleration was requested without any projections."))
       (unless *gpu-library*
         (load-gpu-backend))
       (unless (gpu-backend-available-p)
         (gpu-backend-error "GPU acceleration is unavailable."))
       (enable-model-gpu-projections
        model
        resolved-tensor-names
        :cache-directory cache-directory
        :python-command python-command
        :generator-path generator-path)
       t))))

(defparameter +npu-projection-role-suffixes+
  '((:attention-query . "attn_q.weight")
    (:attention-key . "attn_k.weight")
    (:attention-value . "attn_v.weight")
    (:attention-output . "attn_output.weight")
    (:ffn-gate . "ffn_gate.weight")
    (:ffn-up . "ffn_up.weight")
    (:ffn-down . "ffn_down.weight")))

(defun model-npu-layer-projection-names
    (model layer-indices
     &key
       (roles '(:attention-query
                :attention-key
                :attention-value
                :attention-output
                :ffn-gate
                :ffn-up
                :ffn-down)))
  (let ((names '()))
    (dolist (layer-index layer-indices)
      (unless (and (integerp layer-index)
                   (<= 0 layer-index)
                   (< layer-index (gguf-model-layer-count model)))
        (error "Layer index ~s is invalid for a ~d-layer model."
               layer-index
               (gguf-model-layer-count model)))
      (dolist (role roles)
        (let ((suffix (cdr (assoc role +npu-projection-role-suffixes+))))
          (unless suffix
            (error "Unknown NPU projection role ~s." role))
          (let ((tensor-name (format nil "blk.~d.~a" layer-index suffix)))
            (unless (gguf-model-tensor-info model tensor-name)
              (error "Model architecture ~a has no ~s projection in layer ~d."
                     (gguf-model-architecture model)
                     role
                     layer-index))
            (push tensor-name names)))))
    (nreverse names)))

(defun enable-model-npu-layer-projections
    (model layer-indices
     &key
       (roles '(:attention-query
                :attention-key
                :attention-value
                :attention-output
                :ffn-gate
                :ffn-up
                :ffn-down))
       (cache-directory (default-npu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (enable-model-npu-projections
   model
   (model-npu-layer-projection-names model layer-indices :roles roles)
   :cache-directory cache-directory
   :python-command python-command
   :generator-path generator-path))

(defun model-gpu-layer-projection-names (model layer-indices &key roles)
  (if roles
      (model-npu-layer-projection-names model layer-indices :roles roles)
      (model-npu-layer-projection-names model layer-indices)))

(defun enable-model-gpu-layer-projections
    (model layer-indices
     &key
       (roles '(:attention-query
                :attention-key
                :attention-value
                :attention-output
                :ffn-gate
                :ffn-up
                :ffn-down))
       (cache-directory (default-gpu-cache-directory))
       (python-command '("python"))
       (generator-path (default-npu-model-generator-pathname)))
  (enable-model-gpu-projections
   model
   (model-gpu-layer-projection-names model layer-indices :roles roles)
   :cache-directory cache-directory
   :python-command python-command
   :generator-path generator-path))

(defun make-tensor-info-table (tensor-infos)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (tensor-info tensor-infos table)
      (setf (gethash (getf tensor-info :name) table)
            tensor-info))))

(defun gguf-model-tensor-info (model tensor-name &optional requiredp)
  (ensure-model-open model "GGUF-MODEL-TENSOR-INFO")
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

(defun vector-add-scaled-in-place (dest source scale)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest source))
  (unless (= (length dest) (length source))
    (error "VECTOR-ADD-SCALED-IN-PLACE destination length ~d does not match source length ~d."
           (length dest)
           (length source)))
  (let ((scale (coerce scale 'single-float)))
    (declare (single-float scale))
    (dotimes (index (length dest) dest)
      (declare (fixnum index))
      (incf (aref dest index)
            (* scale (aref source index))))))

(defun vector-add-bias-in-place (dest bias)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest bias))
  (unless (= (length dest) (length bias))
    (error "VECTOR-ADD-BIAS-IN-PLACE destination length ~d does not match bias length ~d."
           (length dest)
           (length bias)))
  (dotimes (index (length dest) dest)
    (declare (fixnum index))
    (incf (aref dest index)
          (aref bias index))))

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

(defun normalize-vector-chunks-with-chunk-weights-into (dest vector chunk-count weights
                                                             &key (epsilon 1.0e-6))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector weights)
           (fixnum chunk-count))
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
  (unless (= (length dest) (length vector) (length weights))
    (error "NORMALIZE-VECTOR-CHUNKS-WITH-CHUNK-WEIGHTS-INTO requires destination, vector, and weight lengths to match."))
  (unless (zerop (mod (length vector) chunk-count))
    (error "Vector length ~d is not divisible by chunk count ~d."
           (length vector)
           chunk-count))
  (let ((chunk-size (/ (length vector) chunk-count))
        (epsilon (coerce epsilon 'single-float)))
    (declare (fixnum chunk-size)
             (single-float epsilon))
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
                   (aref weights (+ start index))
                   scale)))))))

(defun l2-normalize-vector-chunks-into (dest vector chunk-count &key (epsilon 1.0e-6))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector)
           (fixnum chunk-count))
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
  (unless (= (length dest) (length vector))
    (error "L2-NORMALIZE-VECTOR-CHUNKS destination length ~d does not match vector length ~d."
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
    (dotimes (chunk-index chunk-count dest)
      (declare (fixnum chunk-index))
      (let* ((start (* chunk-index chunk-size))
             (sum-square (sum-square-elements-range vector start chunk-size))
             (scale (/ (sqrt (+ sum-square epsilon)))))
        (declare (fixnum start)
                 (single-float sum-square scale))
        (dotimes (index chunk-size)
          (declare (fixnum index))
          (setf (aref dest (+ start index))
                (* (aref vector (+ start index))
                   scale)))))))

(defun gated-normalize-vector-chunks-into (dest vector gate chunk-count weight &key (epsilon 1.0e-6))
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array single-float (*)) dest vector gate weight)
           (fixnum chunk-count))
  (unless (= (length dest) (length vector) (length gate))
    (error "GATED-NORMALIZE-VECTOR-CHUNKS requires destination, vector, and gate lengths to match."))
  (unless (plusp chunk-count)
    (error "CHUNK-COUNT must be positive, got ~a." chunk-count))
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
                   (silu (aref gate (+ start index)))
                   scale)))))))

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

(defun make-layer-tensor-path (layer-index suffix)
  (format nil "blk.~d.~a" layer-index suffix))

(defun gguf-model-layer-uses-swa-p (model layer-index)
  (let ((pattern (gguf-model-sliding-pattern model)))
    (and pattern (nth layer-index pattern))))

(defun gguf-model-layer-kv-head-count (model layer-index)
  (let ((kv-head-count (gguf-model-kv-head-count model)))
    (typecase kv-head-count
      (list
       (or (nth layer-index kv-head-count)
           (error "Model is missing KV head count for layer ~d." layer-index)))
      (fixnum kv-head-count)
      (integer kv-head-count)
      (t
       (error "Unsupported KV head count metadata ~s for layer ~d."
              kv-head-count
              layer-index)))))

(defun gguf-model-layer-ffn-size (model layer-index)
  (let ((ffn-size (gguf-model-ffn-size model)))
    (typecase ffn-size
      (list
       (or (nth layer-index ffn-size)
           (error "Model is missing FFN size for layer ~d." layer-index)))
      (fixnum ffn-size)
      (integer ffn-size)
      (null 0)
      (t
       (error "Unsupported FFN size metadata ~s for layer ~d."
              ffn-size
              layer-index)))))

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
  (let* ((tensor (gguf-model-load-tensor model tensor-name))
         (tensor-info (gguf-model-tensor-info model tensor-name t)))
    (unless (= 1 (length (getf tensor-info :dimensions)))
      (error "Tensor ~s is not a vector tensor." tensor-name))
    tensor))

(defun gguf-model-load-tensor (model tensor-name)
  (or (gguf-model-cached-tensor model tensor-name)
      (let ((tensor-info (gguf-model-tensor-info model tensor-name t)))
        (setf (gguf-model-cached-tensor model tensor-name)
              (load-gguf-tensor (gguf-model-mapping model) tensor-info)))))

(defun gguf-model-load-scalar-tensor (model tensor-name)
  (let ((tensor (gguf-model-load-vector-tensor model tensor-name)))
    (unless (= 1 (length tensor))
      (error "Tensor ~s is not a scalar tensor." tensor-name))
    (aref tensor 0)))

(defun tensor-depth-count (tensor-info)
  (the fixnum
       (or (third (getf tensor-info :dimensions)) 1)))

(defun tensor-flat-row-count (tensor-info)
  (the fixnum
       (* (tensor-row-count tensor-info)
          (tensor-depth-count tensor-info))))

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
      (#.+ggml-type-q5-0+ (dequantize-q5-0 row-pointer column-count))
      (#.+ggml-type-q8-0+ (dequantize-q8-0 row-pointer column-count))
      (#.+ggml-type-bf16+ (load-bf16-tensor row-pointer column-count))
      (#.+ggml-type-q4-k+ (dequantize-q4-k-m row-pointer column-count))
      (#.+ggml-type-q5-k+ (dequantize-q5-k row-pointer column-count))
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
      (#.+ggml-type-q5-0+ (replace dest (dequantize-q5-0 row-pointer column-count)))
      (#.+ggml-type-q8-0+ (replace dest (dequantize-q8-0 row-pointer column-count)))
      (#.+ggml-type-bf16+ (load-bf16-tensor-into dest row-pointer column-count))
      (#.+ggml-type-q5-k+ (replace dest (dequantize-q5-k row-pointer column-count)))
      (otherwise
       (replace dest (load-gguf-tensor-row mapping tensor-info row-index))))
    dest))

(defun dequantize-q5-0 (quantized-pointer element-count)
  (unless (zerop (mod element-count 32))
    (error "Q5_0 dequantization requires ELEMENT-COUNT to be a multiple of 32."))
  (let* ((block-size (+ 2 4 16))
         (block-count (/ element-count 32))
         (result (make-array element-count :element-type 'single-float)))
    (dotimes (block-index block-count result)
      (let* ((block-offset (* block-index block-size))
             (d (read-fp16-le quantized-pointer block-offset))
             (qh (read-u32-le quantized-pointer (+ block-offset 2)))
             (qs-base (+ block-offset 6))
             (result-base (* block-index 32)))
        (declare (single-float d)
                 (fixnum block-offset qh qs-base result-base))
        (dotimes (pair-index 16)
          (declare (fixnum pair-index))
          (let* ((packed (read-u8 quantized-pointer (+ qs-base pair-index)))
                 (xh-0 (if (logbitp pair-index qh) #x10 0))
                 (xh-1 (if (logbitp (+ pair-index 16) qh) #x10 0))
                 (q0 (- (logior (logand packed #x0F) xh-0) 16))
                 (q1 (- (logior (ash packed -4) xh-1) 16)))
            (declare (fixnum packed xh-0 xh-1 q0 q1))
            (setf (aref result (+ result-base pair-index))
                  (coerce (* d q0) 'single-float))
            (setf (aref result (+ result-base 16 pair-index))
                  (coerce (* d q1) 'single-float))))))))

(defun dequantize-q8-0 (quantized-pointer element-count)
  (unless (zerop (mod element-count 32))
    (error "Q8_0 dequantization requires ELEMENT-COUNT to be a multiple of 32."))
  (let* ((block-size (+ 2 32))
         (block-count (/ element-count 32))
         (result (make-array element-count :element-type 'single-float)))
    (dotimes (block-index block-count result)
      (let* ((block-offset (* block-index block-size))
             (d (read-fp16-le quantized-pointer block-offset))
             (qs-base (+ block-offset 2))
             (result-base (* block-index 32)))
        (declare (single-float d)
                 (fixnum block-offset qs-base result-base))
        (dotimes (lane 32)
          (declare (fixnum lane))
          (setf (aref result (+ result-base lane))
                (coerce (* d (read-s8 quantized-pointer (+ qs-base lane)))
                        'single-float)))))))

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

(defun dot-product-with-q5-0-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (unless (zerop (mod element-count 32))
    (error "Q5_0 dot product requires ELEMENT-COUNT to be a multiple of 32."))
  (let ((sum 0.0f0)
        (block-size (+ 2 4 16))
        (block-count (/ element-count 32)))
    (declare (single-float sum)
            (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float sum))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
            (d (read-fp16-le pointer block-offset))
            (qh (read-u32-le pointer (+ block-offset 2)))
            (qs-base (+ block-offset 6))
            (vector-base (* block-index 32)))
        (declare (single-float d)
                (fixnum block-offset qh qs-base vector-base))
        (dotimes (pair-index 16)
          (declare (fixnum pair-index))
          (let* ((packed (read-u8 pointer (+ qs-base pair-index)))
                (xh-0 (if (logbitp pair-index qh) #x10 0))
                (xh-1 (if (logbitp (+ pair-index 16) qh) #x10 0))
                (q0 (- (logior (logand packed #x0F) xh-0) 16))
                (q1 (- (logior (ash packed -4) xh-1) 16)))
           (declare (fixnum packed xh-0 xh-1 q0 q1))
           (incf sum
                 (* d
                    (+ (* q0 (aref vector (+ vector-base pair-index)))
                       (* q1 (aref vector (+ vector-base 16 pair-index))))))))))))

(defun dot-product-with-q8-0-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (unless (zerop (mod element-count 32))
    (error "Q8_0 dot product requires ELEMENT-COUNT to be a multiple of 32."))
  (let ((sum 0.0f0)
        (block-size (+ 2 32))
        (block-count (/ element-count 32)))
    (declare (single-float sum)
            (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float sum))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
            (d (read-fp16-le pointer block-offset))
            (qs-base (+ block-offset 2))
            (vector-base (* block-index 32)))
        (declare (single-float d)
                (fixnum block-offset qs-base vector-base))
        (dotimes (lane 32)
          (declare (fixnum lane))
          (incf sum
               (* d
                  (read-s8 pointer (+ qs-base lane))
                  (aref vector (+ vector-base lane)))))))))

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

(defmacro q4-low-quant (packed)
  `(the fixnum (logand ,packed #x0F)))

(defmacro q4-high-quant (packed)
  `(the fixnum (ash ,packed -4)))

(defmacro q6-quant-1 (packed-low packed-top)
  `(the fixnum
        (- (logior (logand ,packed-low #x0F)
                   (ash (logand ,packed-top #x03) 4))
           32)))

(defmacro q6-quant-2 (packed-high packed-top)
  `(the fixnum
        (- (logior (logand ,packed-high #x0F)
                   (ash (logand (ash ,packed-top -2) #x03) 4))
           32)))

(defmacro q6-quant-3 (packed-low packed-top)
  `(the fixnum
        (- (logior (ash ,packed-low -4)
                   (ash (logand (ash ,packed-top -4) #x03) 4))
           32)))

(defmacro q6-quant-4 (packed-high packed-top)
  `(the fixnum
        (- (logior (ash ,packed-high -4)
                   (ash (logand (ash ,packed-top -6) #x03) 4))
           32)))

(defmacro zero-f32.8 ()
  `(make-f32.8 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0 0.0f0))

(defmacro broadcast-f32.8 (value)
  `(make-f32.8 ,value ,value ,value ,value ,value ,value ,value ,value))

(defmacro expand-q4-k-body (pointer qs-base vector vector-base delta0 offset0 delta1 offset1 sum)
  (let ((forms '()))
    (dotimes (group 4
                   `(let ((delta0-vector (broadcast-f32.8 ,delta0))
                          (offset0-vector (broadcast-f32.8 ,offset0))
                          (delta1-vector (broadcast-f32.8 ,delta1))
                          (offset1-vector (broadcast-f32.8 ,offset1)))
                      (declare (type f32.8 delta0-vector offset0-vector
                                     delta1-vector offset1-vector))
                      ,@(nreverse forms)))
      (let ((lane-base (* group 8)))
        (push
         `(let* ((packed0 (read-u8 ,pointer (+ ,qs-base ,lane-base 0)))
                (packed1 (read-u8 ,pointer (+ ,qs-base ,lane-base 1)))
                (packed2 (read-u8 ,pointer (+ ,qs-base ,lane-base 2)))
                (packed3 (read-u8 ,pointer (+ ,qs-base ,lane-base 3)))
                (packed4 (read-u8 ,pointer (+ ,qs-base ,lane-base 4)))
                (packed5 (read-u8 ,pointer (+ ,qs-base ,lane-base 5)))
                (packed6 (read-u8 ,pointer (+ ,qs-base ,lane-base 6)))
                (packed7 (read-u8 ,pointer (+ ,qs-base ,lane-base 7)))
                (low-weights
                  (f32.8-
                   (f32.8*
                    (make-f32.8
                     (fixnum-single-float (q4-low-quant packed0))
                     (fixnum-single-float (q4-low-quant packed1))
                     (fixnum-single-float (q4-low-quant packed2))
                     (fixnum-single-float (q4-low-quant packed3))
                     (fixnum-single-float (q4-low-quant packed4))
                     (fixnum-single-float (q4-low-quant packed5))
                     (fixnum-single-float (q4-low-quant packed6))
                     (fixnum-single-float (q4-low-quant packed7)))
                    delta0-vector)
                   offset0-vector))
                (high-weights
                  (f32.8-
                   (f32.8*
                    (make-f32.8
                     (fixnum-single-float (q4-high-quant packed0))
                     (fixnum-single-float (q4-high-quant packed1))
                     (fixnum-single-float (q4-high-quant packed2))
                     (fixnum-single-float (q4-high-quant packed3))
                     (fixnum-single-float (q4-high-quant packed4))
                     (fixnum-single-float (q4-high-quant packed5))
                     (fixnum-single-float (q4-high-quant packed6))
                     (fixnum-single-float (q4-high-quant packed7)))
                    delta1-vector)
                   offset1-vector))
                (activations-low (f32.8-aref ,vector (+ ,vector-base ,lane-base)))
                (activations-high (f32.8-aref ,vector (+ ,vector-base 32 ,lane-base))))
            (declare (fixnum packed0 packed1 packed2 packed3 packed4 packed5 packed6 packed7)
                    (type f32.8 low-weights high-weights activations-low activations-high))
            (setf ,sum
                 (f32.8-fmadd high-weights
                              activations-high
                              (f32.8-fmadd low-weights activations-low ,sum))))
         forms)))))

(defmacro expand-q6-k-group (pointer ql-base qh-base vector-base start-lane
                             delta1 delta2 delta3 delta4 vector sum)
  (let ((forms '()))
    (dotimes (group 2
                   `(let ((delta1-vector (broadcast-f32.8 ,delta1))
                          (delta2-vector (broadcast-f32.8 ,delta2))
                          (delta3-vector (broadcast-f32.8 ,delta3))
                          (delta4-vector (broadcast-f32.8 ,delta4)))
                      (declare (type f32.8 delta1-vector delta2-vector
                                     delta3-vector delta4-vector))
                      ,@(nreverse forms)))
      (let ((lane-base (+ start-lane (* group 8))))
        (push
         `(let* ((packed-low0 (read-u8 ,pointer (+ ,ql-base ,lane-base 0)))
                (packed-low1 (read-u8 ,pointer (+ ,ql-base ,lane-base 1)))
                (packed-low2 (read-u8 ,pointer (+ ,ql-base ,lane-base 2)))
                (packed-low3 (read-u8 ,pointer (+ ,ql-base ,lane-base 3)))
                (packed-low4 (read-u8 ,pointer (+ ,ql-base ,lane-base 4)))
                (packed-low5 (read-u8 ,pointer (+ ,ql-base ,lane-base 5)))
                (packed-low6 (read-u8 ,pointer (+ ,ql-base ,lane-base 6)))
                (packed-low7 (read-u8 ,pointer (+ ,ql-base ,lane-base 7)))
                (packed-high0 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 0)))
                (packed-high1 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 1)))
                (packed-high2 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 2)))
                (packed-high3 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 3)))
                (packed-high4 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 4)))
                (packed-high5 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 5)))
                (packed-high6 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 6)))
                (packed-high7 (read-u8 ,pointer (+ ,ql-base 32 ,lane-base 7)))
                (packed-top0 (read-u8 ,pointer (+ ,qh-base ,lane-base 0)))
                (packed-top1 (read-u8 ,pointer (+ ,qh-base ,lane-base 1)))
                (packed-top2 (read-u8 ,pointer (+ ,qh-base ,lane-base 2)))
                (packed-top3 (read-u8 ,pointer (+ ,qh-base ,lane-base 3)))
                (packed-top4 (read-u8 ,pointer (+ ,qh-base ,lane-base 4)))
                (packed-top5 (read-u8 ,pointer (+ ,qh-base ,lane-base 5)))
                (packed-top6 (read-u8 ,pointer (+ ,qh-base ,lane-base 6)))
                (packed-top7 (read-u8 ,pointer (+ ,qh-base ,lane-base 7)))
                (weights1
                  (f32.8*
                   (make-f32.8
                    (fixnum-single-float (q6-quant-1 packed-low0 packed-top0))
                    (fixnum-single-float (q6-quant-1 packed-low1 packed-top1))
                    (fixnum-single-float (q6-quant-1 packed-low2 packed-top2))
                    (fixnum-single-float (q6-quant-1 packed-low3 packed-top3))
                    (fixnum-single-float (q6-quant-1 packed-low4 packed-top4))
                    (fixnum-single-float (q6-quant-1 packed-low5 packed-top5))
                    (fixnum-single-float (q6-quant-1 packed-low6 packed-top6))
                    (fixnum-single-float (q6-quant-1 packed-low7 packed-top7)))
                   delta1-vector))
                (weights2
                  (f32.8*
                   (make-f32.8
                    (fixnum-single-float (q6-quant-2 packed-high0 packed-top0))
                    (fixnum-single-float (q6-quant-2 packed-high1 packed-top1))
                    (fixnum-single-float (q6-quant-2 packed-high2 packed-top2))
                    (fixnum-single-float (q6-quant-2 packed-high3 packed-top3))
                    (fixnum-single-float (q6-quant-2 packed-high4 packed-top4))
                    (fixnum-single-float (q6-quant-2 packed-high5 packed-top5))
                    (fixnum-single-float (q6-quant-2 packed-high6 packed-top6))
                    (fixnum-single-float (q6-quant-2 packed-high7 packed-top7)))
                   delta2-vector))
                (weights3
                  (f32.8*
                   (make-f32.8
                    (fixnum-single-float (q6-quant-3 packed-low0 packed-top0))
                    (fixnum-single-float (q6-quant-3 packed-low1 packed-top1))
                    (fixnum-single-float (q6-quant-3 packed-low2 packed-top2))
                    (fixnum-single-float (q6-quant-3 packed-low3 packed-top3))
                    (fixnum-single-float (q6-quant-3 packed-low4 packed-top4))
                    (fixnum-single-float (q6-quant-3 packed-low5 packed-top5))
                    (fixnum-single-float (q6-quant-3 packed-low6 packed-top6))
                    (fixnum-single-float (q6-quant-3 packed-low7 packed-top7)))
                   delta3-vector))
                (weights4
                  (f32.8*
                   (make-f32.8
                    (fixnum-single-float (q6-quant-4 packed-high0 packed-top0))
                    (fixnum-single-float (q6-quant-4 packed-high1 packed-top1))
                    (fixnum-single-float (q6-quant-4 packed-high2 packed-top2))
                    (fixnum-single-float (q6-quant-4 packed-high3 packed-top3))
                    (fixnum-single-float (q6-quant-4 packed-high4 packed-top4))
                    (fixnum-single-float (q6-quant-4 packed-high5 packed-top5))
                    (fixnum-single-float (q6-quant-4 packed-high6 packed-top6))
                    (fixnum-single-float (q6-quant-4 packed-high7 packed-top7)))
                   delta4-vector))
                (activations1 (f32.8-aref ,vector (+ ,vector-base ,lane-base)))
                (activations2 (f32.8-aref ,vector (+ ,vector-base 32 ,lane-base)))
                (activations3 (f32.8-aref ,vector (+ ,vector-base 64 ,lane-base)))
                (activations4 (f32.8-aref ,vector (+ ,vector-base 96 ,lane-base))))
            (declare (fixnum packed-low0 packed-low1 packed-low2 packed-low3
                            packed-low4 packed-low5 packed-low6 packed-low7
                            packed-high0 packed-high1 packed-high2 packed-high3
                            packed-high4 packed-high5 packed-high6 packed-high7
                            packed-top0 packed-top1 packed-top2 packed-top3
                            packed-top4 packed-top5 packed-top6 packed-top7)
                    (type f32.8 weights1 weights2 weights3 weights4
                                  activations1 activations2 activations3 activations4))
            (setf ,sum
                 (f32.8-fmadd weights4
                              activations4
                              (f32.8-fmadd weights3
                                           activations3
                                           (f32.8-fmadd weights2
                                                        activations2
                                                        (f32.8-fmadd weights1
                                                                     activations1
                                                                     ,sum))))))
         forms)))))

(declaim (ftype (function (t fixnum fixnum) (values fixnum fixnum &optional))
              get-scale-min-k4-at)
         (inline get-scale-min-k4-at))

(defun get-scale-min-k4-at (pointer scale-base index)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (fixnum scale-base index))
  (let ((byte0 (read-u8 pointer (+ scale-base index)))
        (byte4 (read-u8 pointer (+ scale-base 4 index))))
    (declare (fixnum byte0 byte4))
    (if (< index 4)
        (values (logand byte0 63)
               (logand byte4 63))
        (values (logior (logand byte4 #x0F)
                       (ash (ash (logand (read-u8 pointer
                                                  (+ scale-base (- index 4)))
                                         #xC0)
                                 -6)
                            4))
               (logior (ash byte4 -4)
                       (ash (ash (logand (read-u8 pointer
                                                  (+ scale-base index))
                                         #xC0)
                                 -6)
                            4))))))

(defun dot-product-with-q4-k-m-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
          (type (simple-array single-float (*)) vector)
          (fixnum row-offset element-count))
  (unless (zerop (mod element-count +qk-k+))
    (error "Q4_K_M dot product requires ELEMENT-COUNT to be a multiple of ~d."
          +qk-k+))
  (let ((sum (zero-f32.8))
        (block-size (+ 4 +k-scale-size+ (/ +qk-k+ 2)))
        (block-count (/ element-count +qk-k+)))
    (declare (type f32.8 sum)
            (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float (f32.8-horizontal+ sum)))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
            (d (read-fp16-le pointer block-offset))
            (dmin (read-fp16-le pointer (+ block-offset 2)))
            (scale-base (+ block-offset 4))
            (qs-base (+ block-offset 4 +k-scale-size+))
            (vector-base (* block-index +qk-k+)))
        (declare (single-float d dmin)
                (fixnum scale-base qs-base vector-base))
        (macrolet ((accumulate-body (scale-index0 scale-index1 qs-offset vector-offset)
                    `(multiple-value-bind (scale0 min0)
                         (get-scale-min-k4-at pointer scale-base ,scale-index0)
                       (multiple-value-bind (scale1 min1)
                           (get-scale-min-k4-at pointer scale-base ,scale-index1)
                         (let ((delta0 (* d (fixnum-single-float scale0)))
                               (offset0 (* dmin (fixnum-single-float min0)))
                               (delta1 (* d (fixnum-single-float scale1)))
                               (offset1 (* dmin (fixnum-single-float min1))))
                           (declare (single-float delta0 offset0 delta1 offset1))
                           (expand-q4-k-body pointer
                                             (+ qs-base ,qs-offset)
                                             vector
                                             (+ vector-base ,vector-offset)
                                             delta0
                                             offset0
                                             delta1
                                             offset1
                                             sum))))))
          (accumulate-body 0 1 0 0)
          (accumulate-body 2 3 32 64)
          (accumulate-body 4 5 64 128)
          (accumulate-body 6 7 96 192))))))

(defun dot-product-with-q4-k-m-tensor-row (row-pointer vector element-count)
  (dot-product-with-q4-k-m-tensor-data row-pointer 0 vector element-count))

(defun dot-product-with-q5-k-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (unless (zerop (mod element-count +qk-k+))
    (error "Q5_K dot product requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let ((sum 0.0f0)
        (block-size (+ 4 +k-scale-size+ (/ +qk-k+ 8) (/ +qk-k+ 2)))
        (block-count (/ element-count +qk-k+)))
    (declare (single-float sum)
             (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float sum))
      (declare (fixnum block-index))
      (let* ((block-offset (+ row-offset (* block-index block-size)))
             (d (read-fp16-le pointer block-offset))
             (dmin (read-fp16-le pointer (+ block-offset 2)))
             (scale-base (+ block-offset 4))
             (qh-base (+ scale-base +k-scale-size+))
             (qs-base (+ qh-base (/ +qk-k+ 8)))
             (vector-base (* block-index +qk-k+))
             (u1 1)
             (u2 2)
             (is 0))
        (declare (single-float d dmin)
                 (fixnum scale-base qh-base qs-base vector-base u1 u2 is))
        (dotimes (group-index 4)
          (declare (fixnum group-index))
          (multiple-value-bind (sc0 m0)
              (get-scale-min-k4-at pointer scale-base is)
            (multiple-value-bind (sc1 m1)
                (get-scale-min-k4-at pointer scale-base (1+ is))
              (let ((delta0 (* d (fixnum-single-float sc0)))
                    (offset0 (* dmin (fixnum-single-float m0)))
                    (delta1 (* d (fixnum-single-float sc1)))
                    (offset1 (* dmin (fixnum-single-float m1))))
                (declare (single-float delta0 offset0 delta1 offset1))
                (dotimes (lane 32)
                  (declare (fixnum lane))
                  (let* ((packed (cffi:mem-aref pointer :unsigned-char (+ qs-base lane)))
                         (high-bits (cffi:mem-aref pointer :unsigned-char (+ qh-base lane)))
                         (q0 (+ (logand packed #x0F)
                                (if (logtest u1 high-bits) 16 0)))
                         (q1 (+ (ash packed -4)
                                (if (logtest u2 high-bits) 16 0))))
                    (declare (fixnum packed high-bits q0 q1))
                    (incf sum (* (aref vector (+ vector-base lane))
                                 (- (* delta0 q0) offset0)))
                    (incf sum (* (aref vector (+ vector-base lane 32))
                                 (- (* delta1 q1) offset1)))))
                (incf qs-base 32)
                (incf vector-base 64)
                (incf is 2)
                (setf u1 (ash u1 2)
                      u2 (ash u2 2))))))))))

(defun dot-product-with-q5-k-tensor-row (row-pointer vector element-count)
  (dot-product-with-q5-k-tensor-data row-pointer 0 vector element-count))

(defun dot-product-with-q6-k-tensor-data (pointer row-offset vector element-count)
  (declare (optimize (speed 3) (safety 0) (debug 0) (space 0))
           (type (simple-array single-float (*)) vector)
           (fixnum row-offset element-count))
  (unless (zerop (mod element-count +qk-k+))
    (error "Q6_K dot product requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let ((sum (zero-f32.8))
        (block-size (+ 2 +q6-k-scale-count+ (* 3 (/ +qk-k+ 4))))
        (block-count (/ element-count +qk-k+)))
    (declare (type f32.8 sum)
             (fixnum block-size block-count))
    (dotimes (block-index block-count (the single-float (f32.8-horizontal+ sum)))
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
                 (delta1 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 0)))))
                 (delta2 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 2)))))
                 (delta3 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 4)))))
                 (delta4 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 6))))))
            (declare (fixnum chunk-ql-base chunk-qh-base chunk-scale-base chunk-vector-base)
              (single-float delta1 delta2 delta3 delta4))
            (expand-q6-k-group pointer
                        chunk-ql-base
                        chunk-qh-base
                        chunk-vector-base
                        0
                        delta1
                        delta2
                        delta3
                        delta4
                        vector
                        sum)
            (let ((delta1 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 1)))))
                  (delta2 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 3)))))
                  (delta3 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 5)))))
                  (delta4 (* d (fixnum-single-float (read-s8 pointer (+ chunk-scale-base 7))))))
              (declare (single-float delta1 delta2 delta3 delta4))
              (expand-q6-k-group pointer
                          chunk-ql-base
                          chunk-qh-base
                          chunk-vector-base
                          16
                          delta1
                          delta2
                          delta3
                          delta4
                          vector
                          sum))))))))

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
      (#.+ggml-type-q5-k+
       (dot-product-with-q5-k-tensor-data mapping row-offset vector column-count))
      (#.+ggml-type-q6-k+
       (dot-product-with-q6-k-tensor-data mapping row-offset vector column-count))
      (otherwise
       (dot-product vector
                    (load-gguf-tensor-row mapping tensor-info row-index))))))

(defun %gguf-model-matrix-vector-multiply-into (dest mapping tensor-info vector start-row row-count)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) dest vector)
          (fixnum start-row row-count))
  (let* ((flat-row-count (tensor-flat-row-count tensor-info))
        (column-count (tensor-column-count tensor-info))
        (type-tag (getf tensor-info :type-tag))
        (row-byte-size (tensor-row-byte-size tensor-info))
        (row-offset (+ (getf tensor-info :data-offset)
                       (* start-row row-byte-size))))
    (declare (fixnum flat-row-count column-count type-tag row-byte-size row-offset))
    (unless (= (length dest) row-count)
      (error "Destination length ~d does not match row count ~d for tensor ~s."
            (length dest)
            row-count
           (getf tensor-info :name)))
    (unless (= (length vector) column-count)
      (error "Vector length ~d does not match tensor row width ~d for tensor ~s."
            (length vector)
            column-count
            (getf tensor-info :name)))
    (unless (<= (+ start-row row-count) flat-row-count)
      (error "Requested row range [~d, ~d) exceeds flattened row count ~d for tensor ~s."
            start-row
            (+ start-row row-count)
            flat-row-count
            (getf tensor-info :name)))
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
      (#.+ggml-type-q5-0+
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-q5-0-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-q8-0+
      (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-q8-0-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-bf16+
      (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-bf16-tensor-data mapping row-offset vector column-count))
        (incf row-offset row-byte-size)))
      (#.+ggml-type-q4-k+
       (if (parallel-gemv-row-count-p row-count)
          (let ((parts (parallel-gemv-part-count row-count))
                (lparallel:*kernel* (ensure-gemv-kernel)))
            (declare (fixnum parts))
            (lparallel:pdotimes (row-index row-count dest parts)
              (declare (fixnum row-index))
              (setf (aref dest row-index)
                    (dot-product-with-q4-k-m-tensor-data
                     mapping
                     (+ row-offset (* row-index row-byte-size))
                     vector
                     column-count))))
          (dotimes (row-index row-count dest)
            (declare (fixnum row-index))
            (setf (aref dest row-index)
                  (dot-product-with-q4-k-m-tensor-data mapping row-offset vector column-count))
            (incf row-offset row-byte-size))))
      (#.+ggml-type-q5-k+
       (if (parallel-gemv-row-count-p row-count)
          (let ((parts (parallel-gemv-part-count row-count))
                (lparallel:*kernel* (ensure-gemv-kernel)))
            (declare (fixnum parts))
            (lparallel:pdotimes (row-index row-count dest parts)
              (declare (fixnum row-index))
              (setf (aref dest row-index)
                    (dot-product-with-q5-k-tensor-data
                     mapping
                     (+ row-offset (* row-index row-byte-size))
                     vector
                     column-count))))
          (dotimes (row-index row-count dest)
            (declare (fixnum row-index))
            (setf (aref dest row-index)
                  (dot-product-with-q5-k-tensor-data mapping row-offset vector column-count))
            (incf row-offset row-byte-size))))
      (#.+ggml-type-q6-k+
       (if (parallel-gemv-row-count-p row-count)
          (let ((parts (parallel-gemv-part-count row-count))
                (lparallel:*kernel* (ensure-gemv-kernel)))
            (declare (fixnum parts))
            (lparallel:pdotimes (row-index row-count dest parts)
              (declare (fixnum row-index))
              (setf (aref dest row-index)
                    (dot-product-with-q6-k-tensor-data
                     mapping
                     (+ row-offset (* row-index row-byte-size))
                     vector
                     column-count))))
          (dotimes (row-index row-count dest)
            (declare (fixnum row-index))
            (setf (aref dest row-index)
                  (dot-product-with-q6-k-tensor-data mapping row-offset vector column-count))
            (incf row-offset row-byte-size))))
      (otherwise
       (dotimes (row-index row-count dest)
        (declare (fixnum row-index))
        (setf (aref dest row-index)
              (dot-product-with-tensor-row mapping tensor-info (+ start-row row-index) vector)))))))

(defun call-with-npu-runtime-fallback
    (npu-function cpu-function disable-function tensor-name)
  (handler-case
      (funcall npu-function)
    (npu-backend-error (condition)
      (funcall disable-function)
      (warn "NPU projection ~s failed and was disabled; recomputing on the CPU: ~a"
            tensor-name
            condition)
      (funcall cpu-function))))

(defun call-with-gpu-runtime-fallback
    (gpu-function cpu-function disable-function tensor-name)
  (handler-case
      (funcall gpu-function)
    (gpu-backend-error (condition)
      (funcall disable-function)
      (warn "GPU projection ~s failed and was disabled; using the next available backend: ~a"
            tensor-name
            condition)
      (funcall cpu-function))))

(defun gguf-model-matrix-vector-multiply-into (dest model tensor-name vector)
  (declare (optimize (speed 3) (safety 0))
          (type (simple-array single-float (*)) dest vector))
  (flet ((run-on-cpu ()
           (let* ((tensor-info
                    (gguf-model-tensor-info model tensor-name t))
                  (row-count (tensor-row-count tensor-info)))
             (%gguf-model-matrix-vector-multiply-into
              dest
              (gguf-model-mapping model)
              tensor-info
              vector
              0
              row-count))))
    (labels ((run-on-npu-or-cpu ()
               (let ((npu-session
                       (gethash tensor-name
                                (gguf-model-npu-projections model))))
                 (if npu-session
                     (call-with-npu-runtime-fallback
                      (lambda ()
                        (run-npu-session-into dest npu-session vector))
                      #'run-on-cpu
                      (lambda ()
                        (unregister-model-npu-projection model tensor-name))
                      tensor-name)
                     (run-on-cpu)))))
      (let ((gpu-session
              (gethash tensor-name (gguf-model-gpu-projections model))))
        (if gpu-session
            (call-with-gpu-runtime-fallback
             (lambda ()
               (run-gpu-session-into dest gpu-session vector))
             #'run-on-npu-or-cpu
             (lambda ()
               (unregister-model-gpu-projection model tensor-name))
             tensor-name)
            (run-on-npu-or-cpu))))))

(defun gguf-model-matrix-vector-multiply (model tensor-name vector)
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (row-count (tensor-row-count tensor-info)))
    (gguf-model-matrix-vector-multiply-into
     (make-array row-count :element-type 'single-float)
     model
     tensor-name
     vector)))

(defun max-absolute-vector-difference (left right)
  (unless (= (length left) (length right))
    (error "Cannot compare vectors with lengths ~d and ~d."
           (length left)
           (length right)))
  (let ((maximum 0.0f0))
    (dotimes (index (length left) maximum)
      (setf maximum
            (max maximum
                 (abs (- (aref left index) (aref right index))))))))

(defun benchmark-matrix-vector-function
    (backend function output baseline row-count column-count
     warmup-runs timed-runs)
  (dotimes (run warmup-runs)
    (declare (ignore run))
    (funcall function))
  (let* ((start (get-internal-real-time))
         (operations (* 2 row-count column-count)))
    (dotimes (run timed-runs)
      (declare (ignore run))
      (funcall function))
    (let* ((ticks (- (get-internal-real-time) start))
           (seconds (max (/ (coerce ticks 'double-float)
                            internal-time-units-per-second)
                         (/ 1.0d0 internal-time-units-per-second)))
           (seconds-per-run (/ seconds timed-runs)))
      (list :backend backend
            :available-p t
            :milliseconds-per-run (* 1000.0d0 seconds-per-run)
            :gflops (/ operations seconds-per-run 1.0d9)
            :speedup-vs-cpu nil
            :max-absolute-error
            (if baseline
                (max-absolute-vector-difference output baseline)
                0.0f0)))))

(defun print-projection-benchmark-results
    (stream tensor-name row-count column-count warmup-runs timed-runs results)
  (let* ((cpu-result
           (find :cpu results :key (lambda (result)
                                     (getf result :backend))))
         (cpu-milliseconds
           (and cpu-result
                (getf cpu-result :milliseconds-per-run))))
    (format stream
            "~&Projection ~s (~d x ~d), ~d warmup and ~d timed runs~%"
            tensor-name row-count column-count warmup-runs timed-runs)
    (format stream "~12a ~12a ~12a ~10a ~14a~%"
            "Backend" "ms/run" "GFLOP/s" "speedup" "max abs error")
    (dolist (result results)
      (if (getf result :available-p)
          (let ((speedup
                  (and cpu-milliseconds
                       (/ cpu-milliseconds
                          (getf result :milliseconds-per-run)))))
            (when speedup
              (setf (getf result :speedup-vs-cpu) speedup))
            (format stream "~12a ~12,3f ~12,3f ~9,2fx ~14,6g~%"
                    (string-upcase (symbol-name (getf result :backend)))
                    (getf result :milliseconds-per-run)
                    (getf result :gflops)
                    (or speedup 0.0d0)
                    (getf result :max-absolute-error)))
          (format stream "~12a ~12a ~12a ~10a ~14a~%"
                  (string-upcase (symbol-name (getf result :backend)))
                  "unavailable"
                  "-"
                  "-"
                  "-"))))
  (finish-output stream)
  results)

(defun benchmark-gguf-projection-backends
    (pathname tensor-name
     &key
       (warmup-runs 3)
       (timed-runs 20)
       (use-npu t)
       (use-gpu t)
       (npu-cache-directory (default-npu-cache-directory))
       (gpu-cache-directory (default-gpu-cache-directory))
       (npu-python-command '("python"))
       (gpu-python-command '("python"))
       (stream *standard-output*))
  (unless (and (integerp warmup-runs) (not (minusp warmup-runs)))
    (error "WARMUP-RUNS must be a nonnegative integer, not ~s." warmup-runs))
  (unless (and (integerp timed-runs) (plusp timed-runs))
    (error "TIMED-RUNS must be a positive integer, not ~s." timed-runs))
  (call-with-file
   pathname
   (lambda (handle)
     (with-mapped-file (mapping handle)
       (let* ((header (read-gguf-header mapping))
              (kv-pairs (read-gguf-kv-pairs mapping))
              (tensor-infos (read-gguf-tensor-infos mapping))
              (model (make-gguf-model
                      :mapping mapping
                      :kv-pairs kv-pairs
                      :tensor-infos tensor-infos
                      :tensor-info-table (make-tensor-info-table tensor-infos)))
              (tensor-info (gguf-model-tensor-info model tensor-name t))
              (dimensions (getf tensor-info :dimensions)))
         (declare (ignore header))
         (unless (= 2 (length dimensions))
           (error "Projection benchmark requires a two-dimensional tensor, not ~s."
                  dimensions))
         (let* ((column-count (tensor-column-count tensor-info))
                (row-count (tensor-row-count tensor-info))
                (input (make-array column-count :element-type 'single-float))
                (cpu-output
                  (make-array row-count :element-type 'single-float))
                (npu-output
                  (make-array row-count :element-type 'single-float))
                (gpu-output
                  (make-array row-count :element-type 'single-float))
                (npu-active-p nil)
                (gpu-active-p nil))
           (dotimes (index column-count)
             (setf (aref input index)
                   (coerce (- (/ (mod (+ (* index 17) 11) 257) 128.0)
                              1.0)
                           'single-float)))
           (when use-npu
             (setf npu-active-p
                   (try-enable-model-npu-projections
                    model
                    (list tensor-name)
                    :cache-directory npu-cache-directory
                    :python-command npu-python-command)))
           (when use-gpu
             (setf gpu-active-p
                   (try-enable-model-gpu-projections
                    model
                    (list tensor-name)
                    :cache-directory gpu-cache-directory
                    :python-command gpu-python-command)))
           (unwind-protect
               (let* ((cpu-result
                        (benchmark-matrix-vector-function
                         :cpu
                         (lambda ()
                           (%gguf-model-matrix-vector-multiply-into
                            cpu-output mapping tensor-info input 0 row-count))
                         cpu-output nil row-count column-count
                         warmup-runs timed-runs))
                      (results (list cpu-result)))
                 (when use-npu
                   (let ((session
                           (gethash tensor-name
                                    (gguf-model-npu-projections model))))
                     (push
                      (if session
                          (handler-case
                              (benchmark-matrix-vector-function
                               :npu
                               (lambda ()
                                 (run-npu-session-into
                                  npu-output session input))
                               npu-output cpu-output row-count column-count
                               warmup-runs timed-runs)
                            (npu-backend-error (condition)
                              (unregister-model-npu-projection
                               model tensor-name)
                              (list :backend :npu
                                    :available-p nil
                                    :error (princ-to-string condition))))
                          (list :backend :npu :available-p nil))
                      results)))
                 (when use-gpu
                   (let ((session
                           (gethash tensor-name
                                    (gguf-model-gpu-projections model))))
                     (push
                      (if session
                          (handler-case
                              (benchmark-matrix-vector-function
                               :gpu
                               (lambda ()
                                 (run-gpu-session-into
                                  gpu-output session input))
                               gpu-output cpu-output row-count column-count
                               warmup-runs timed-runs)
                            (gpu-backend-error (condition)
                              (unregister-model-gpu-projection
                               model tensor-name)
                              (list :backend :gpu
                                    :available-p nil
                                    :error (princ-to-string condition))))
                          (list :backend :gpu :available-p nil))
                      results)))
                 (print-projection-benchmark-results
                  stream tensor-name row-count column-count
                  warmup-runs timed-runs (nreverse results)))
             (when gpu-active-p
               (clear-model-gpu-projections model))
             (when npu-active-p
               (clear-model-npu-projections model)))))))))

(defun gguf-model-expert-matrix-vector-multiply-into (dest model tensor-name expert-index vector)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) dest vector)
           (fixnum expert-index))
  (let* ((tensor-info (gguf-model-tensor-info model tensor-name t))
         (rows-per-expert (tensor-row-count tensor-info))
         (expert-count (tensor-depth-count tensor-info)))
    (declare (fixnum rows-per-expert expert-count))
    (unless (= 3 (length (getf tensor-info :dimensions)))
      (error "Tensor ~s is not an expert tensor." tensor-name))
    (unless (and (<= 0 expert-index) (< expert-index expert-count))
      (error "Expert index ~d is out of range for tensor ~s with ~d experts."
             expert-index
             tensor-name
             expert-count))
    (%gguf-model-matrix-vector-multiply-into dest
                                             (gguf-model-mapping model)
                                             tensor-info
                                             vector
                                             (* expert-index rows-per-expert)
                                             rows-per-expert)))

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
  (fixnum-vectors (make-hash-table :test #'eq))
  (chunk-views (make-hash-table :test #'eq)))

(defun compute-buffer-vector (buffer key length)
  (let ((vector (gethash key (compute-buffer-vectors buffer))))
    (unless (and vector (= (length vector) length))
      (setf vector (make-array length :element-type 'single-float)
            (gethash key (compute-buffer-vectors buffer)) vector))
    vector))

(defun compute-buffer-fixnum-vector (buffer key length)
  (let ((vector (gethash key (compute-buffer-fixnum-vectors buffer))))
    (unless (and vector (= (length vector) length))
      (setf vector (make-array length :element-type 'fixnum)
            (gethash key (compute-buffer-fixnum-vectors buffer)) vector))
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

(defun qwen3next-full-attention-layer-p (model layer-index)
  (not (null (gguf-model-tensor-info model
                                     (make-layer-tensor-name layer-index "attn_q")
                                     nil))))

(defun qwen3next-recurrent-layer-p (model layer-index)
  (not (null (gguf-model-tensor-info model
                                     (make-layer-tensor-name layer-index "attn_qkv")
                                     nil))))

(defun ensure-qwen3next-recurrent-layer-cache (kv-cache layer-index channel-count kernel-size
                                                        head-count state-size)
  (let ((entry (gethash layer-index kv-cache))
        (conv-state-length (* channel-count kernel-size))
        (state-length (* head-count state-size state-size)))
    (declare (fixnum channel-count kernel-size head-count state-size
                     conv-state-length state-length))
    (unless (and entry
                 (= (length (getf entry :conv-state)) conv-state-length)
                 (= (length (getf entry :state)) state-length))
      (setf entry (list :conv-state (make-array conv-state-length
                                                :element-type 'single-float
                                                :initial-element 0.0f0)
                        :state (make-array state-length
                                           :element-type 'single-float
                                           :initial-element 0.0f0))
            (gethash layer-index kv-cache) entry))
    entry))

(defun qwen3next-causal-conv1d-step-into (dest current-input conv-state conv-weight kernel-size)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) dest current-input conv-state conv-weight)
           (fixnum kernel-size))
  (unless (= (length dest) (length current-input))
    (error "QWEN3NEXT-CAUSAL-CONV1D-STEP destination length ~d does not match input length ~d."
           (length dest)
           (length current-input)))
  (let* ((channel-count (length current-input))
         (expected-state-length (* channel-count kernel-size)))
    (declare (fixnum channel-count expected-state-length))
    (unless (= (length conv-state) expected-state-length)
      (error "Convolution state length ~d does not match expected length ~d."
             (length conv-state)
             expected-state-length))
    (unless (= (length conv-weight) expected-state-length)
      (error "Convolution weight length ~d does not match expected length ~d."
             (length conv-weight)
             expected-state-length))
    (dotimes (channel-index channel-count dest)
      (declare (fixnum channel-index))
      (let* ((base (* channel-index kernel-size))
             (new-value (aref current-input channel-index))
             (sum 0.0f0))
        (declare (fixnum base)
                 (single-float new-value sum))
        (dotimes (tap-index (1- kernel-size))
          (declare (fixnum tap-index))
          (setf (aref conv-state (+ base tap-index))
                (aref conv-state (+ base tap-index 1))))
        (setf (aref conv-state (+ base (1- kernel-size))) new-value)
        (dotimes (tap-index kernel-size)
          (declare (fixnum tap-index))
          (incf sum
                (* (aref conv-state (+ base tap-index))
                   (aref conv-weight (+ base tap-index)))))
        (setf (aref dest channel-index)
              (silu sum))))))

(defun select-top-k-logits-into (top-indices top-logits logits count)
  (declare (optimize (speed 3) (safety 2))
           (type (simple-array fixnum (*)) top-indices)
           (type (simple-array single-float (*)) top-logits logits)
           (fixnum count))
  (unless (= (length top-indices) count (length top-logits))
    (error "SELECT-TOP-K-LOGITS-INTO requires buffers of length ~d." count))
  (dotimes (index count)
    (declare (fixnum index))
    (setf (aref top-indices index) -1
          (aref top-logits index) most-negative-single-float))
  (dotimes (logit-index (length logits))
    (declare (fixnum logit-index))
    (let ((value (aref logits logit-index)))
      (declare (single-float value))
      (when (> value (aref top-logits (1- count)))
        (let ((insert-index (1- count)))
          (declare (fixnum insert-index))
          (loop while (and (> insert-index 0)
                           (> value (aref top-logits (1- insert-index))))
                do (setf (aref top-logits insert-index)
                         (aref top-logits (1- insert-index))
                         (aref top-indices insert-index)
                         (aref top-indices (1- insert-index)))
                   (decf insert-index))
          (setf (aref top-logits insert-index) value
                (aref top-indices insert-index) logit-index)))))
  top-indices)

(defun qwen3next-dense-ffn-into (dest model layer-index input compute-buffer)
  (declare (type (simple-array single-float (*)) dest input))
  (let* ((gate-length (tensor-row-count
                       (gguf-model-tensor-info model
                                               (make-layer-tensor-name layer-index "ffn_gate")
                                               t)))
         (up-length (tensor-row-count
                     (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "ffn_up")
                                             t)))
         (gate (compute-buffer-vector compute-buffer :qwen-dense-gate gate-length))
         (up (compute-buffer-vector compute-buffer :qwen-dense-up up-length)))
    (gguf-model-matrix-vector-multiply-into gate
                                            model
                                            (make-layer-tensor-name layer-index "ffn_gate")
                                            input)
    (gguf-model-matrix-vector-multiply-into up
                                            model
                                            (make-layer-tensor-name layer-index "ffn_up")
                                            input)
    (apply-silu-into gate gate)
    (vector-elementwise-multiply-into gate gate up)
    (gguf-model-matrix-vector-multiply-into dest
                                            model
                                            (make-layer-tensor-name layer-index "ffn_down")
                                            gate)))

(defun qwen3next-moe-into (dest model layer-index input compute-buffer)
  (declare (type (simple-array single-float (*)) dest input))
  (let ((router-info (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "ffn_gate_inp")
                                             nil)))
    (if (null router-info)
        (qwen3next-dense-ffn-into dest model layer-index input compute-buffer)
        (let* ((expert-count (tensor-row-count router-info))
               (top-k (min expert-count
                           (or (gguf-kv-value-or-nil (gguf-model-kv-pairs model)
                                                     "qwen3next.expert_used_count")
                               10)))
               (expert-hidden-size
                (tensor-row-count
                 (gguf-model-tensor-info model
                                         (make-layer-tensor-name layer-index "ffn_gate_exps")
                                         t)))
               (shared-hidden-size
                (tensor-row-count
                 (gguf-model-tensor-info model
                                         (make-layer-tensor-name layer-index "ffn_gate_shexp")
                                         t)))
               (router-logits (compute-buffer-vector compute-buffer :qwen-router-logits expert-count))
               (top-indices (compute-buffer-fixnum-vector compute-buffer :qwen-top-indices top-k))
               (top-logits (compute-buffer-vector compute-buffer :qwen-top-logits top-k))
               (top-probabilities (compute-buffer-vector compute-buffer :qwen-top-probabilities top-k))
               (expert-gate (compute-buffer-vector compute-buffer :qwen-expert-gate expert-hidden-size))
               (expert-up (compute-buffer-vector compute-buffer :qwen-expert-up expert-hidden-size))
               (expert-down (compute-buffer-vector compute-buffer :qwen-expert-down (length dest)))
               (shared-gate (compute-buffer-vector compute-buffer :qwen-shared-gate shared-hidden-size))
               (shared-up (compute-buffer-vector compute-buffer :qwen-shared-up shared-hidden-size))
               (shared-down (compute-buffer-vector compute-buffer :qwen-shared-down (length dest)))
               (shared-gate-weight
                (gguf-model-load-vector-tensor model
                                               (make-layer-tensor-name
                                                layer-index
                                                "ffn_gate_inp_shexp"))))
          (declare (fixnum expert-count top-k expert-hidden-size shared-hidden-size))
          (fill dest 0.0f0)
          (gguf-model-matrix-vector-multiply-into router-logits
                                                  model
                                                  (make-layer-tensor-name layer-index "ffn_gate_inp")
                                                  input)
          (select-top-k-logits-into top-indices top-logits router-logits top-k)
          (let ((weight-sum 0.0f0))
            (declare (single-float weight-sum))
            (dotimes (selected-index top-k)
              (declare (fixnum selected-index))
              (let ((weight (sigmoid (aref top-logits selected-index))))
                (declare (single-float weight))
                (setf (aref top-probabilities selected-index) weight)
                (incf weight-sum weight)))
            (unless (plusp weight-sum)
              (error "Qwen3Next layer ~d router produced non-positive top-k weight sum."
                     layer-index))
            (dotimes (selected-index top-k)
              (declare (fixnum selected-index))
              (setf (aref top-probabilities selected-index)
                    (/ (aref top-probabilities selected-index) weight-sum))))
          (dotimes (selected-index top-k)
            (declare (fixnum selected-index))
            (let ((expert-index (aref top-indices selected-index))
                  (expert-weight (aref top-probabilities selected-index)))
              (declare (fixnum expert-index)
                       (single-float expert-weight))
              (gguf-model-expert-matrix-vector-multiply-into expert-gate
                                                             model
                                                             (make-layer-tensor-name
                                                              layer-index
                                                              "ffn_gate_exps")
                                                             expert-index
                                                             input)
              (gguf-model-expert-matrix-vector-multiply-into expert-up
                                                             model
                                                             (make-layer-tensor-name
                                                              layer-index
                                                              "ffn_up_exps")
                                                             expert-index
                                                             input)
              (apply-silu-into expert-gate expert-gate)
              (vector-elementwise-multiply-into expert-gate expert-gate expert-up)
              (gguf-model-expert-matrix-vector-multiply-into expert-down
                                                             model
                                                             (make-layer-tensor-name
                                                              layer-index
                                                              "ffn_down_exps")
                                                             expert-index
                                                             expert-gate)
              (vector-add-scaled-in-place dest expert-down expert-weight)))
          (let ((shared-weight (sigmoid (dot-product shared-gate-weight input))))
            (declare (single-float shared-weight))
            (gguf-model-matrix-vector-multiply-into shared-gate
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_gate_shexp")
                                                    input)
            (gguf-model-matrix-vector-multiply-into shared-up
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_up_shexp")
                                                    input)
            (apply-silu-into shared-gate shared-gate)
            (vector-elementwise-multiply-into shared-gate shared-gate shared-up)
            (gguf-model-matrix-vector-multiply-into shared-down
                                                    model
                                                    (make-layer-tensor-name layer-index "ffn_down_shexp")
                                                    shared-gate)
            (vector-add-scaled-in-place dest shared-down shared-weight))))))

(defun load-qwen3next-model (mapping kv-pairs tensor-infos)
  (let ((architecture (gguf-kv-value kv-pairs "general.architecture")))
    (unless (string= architecture "qwen3next")
      (error "LOAD-QWEN3NEXT-MODEL only supports general.architecture = \"qwen3next\", got ~s."
             architecture))
    (let ((tensor-info-table (make-tensor-info-table tensor-infos)))
      (make-gguf-model
       :mapping mapping
       :kv-pairs kv-pairs
       :tensor-infos tensor-infos
       :tensor-info-table tensor-info-table
       :tensor-cache (make-hash-table :test #'equal)
       :architecture architecture
       :hidden-size (gguf-kv-value kv-pairs "qwen3next.embedding_length")
       :layer-count (gguf-kv-value kv-pairs "qwen3next.block_count")
       :head-count (gguf-kv-value kv-pairs "qwen3next.attention.head_count")
       :kv-head-count (gguf-kv-value kv-pairs "qwen3next.attention.head_count_kv")
       :ffn-size (gguf-kv-value-or-nil kv-pairs "qwen3next.feed_forward_length")
       :norm-epsilon (gguf-kv-value kv-pairs "qwen3next.attention.layer_norm_rms_epsilon")
       :rope-base (gguf-kv-value kv-pairs "qwen3next.rope.freq_base")
       :rope-dimension (gguf-kv-value kv-pairs "qwen3next.rope.dimension_count")
       :output-tensor-name (if (gethash "output.weight" tensor-info-table)
                               "output.weight"
                               "token_embd.weight")))))

(defun make-qwen3next-step-function (model)
  (let ((head-count (gguf-model-head-count model))
        (kv-head-count (gguf-model-kv-head-count model))
        (hidden-size (gguf-model-hidden-size model))
        (norm-epsilon (gguf-model-norm-epsilon model))
        (rope-dimension (gguf-model-rope-dimension model))
        (rope-base (gguf-model-rope-base model))
        (compute-buffer (make-compute-buffer)))
    (lambda (token-id position kv-cache)
      (let* ((input-embedding (compute-buffer-vector compute-buffer :qwen-input-embedding hidden-size))
             (x (compute-buffer-vector compute-buffer :qwen-x hidden-size))
             (attn-norm (compute-buffer-vector compute-buffer :qwen-attn-norm hidden-size))
             (ffn-input (compute-buffer-vector compute-buffer :qwen-ffn-input hidden-size))
             (mixer-output (compute-buffer-vector compute-buffer :qwen-mixer-output hidden-size))
             (ffn-output (compute-buffer-vector compute-buffer :qwen-ffn-output hidden-size)))
        (gguf-model-token-row-into input-embedding model "token_embd.weight" token-id)
        (replace x input-embedding)
        (dotimes (layer-index (gguf-model-layer-count model))
          (declare (fixnum layer-index))
          (rms-norm-into attn-norm
                         x
                         (gguf-model-load-vector-tensor
                          model
                          (make-layer-tensor-name layer-index "attn_norm"))
                         :epsilon norm-epsilon)
          (cond
            ((qwen3next-full-attention-layer-p model layer-index)
             (let* ((q-and-gate-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "attn_q")
                                              t)))
                    (k-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "attn_k")
                                              t)))
                    (v-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "attn_v")
                                              t)))
                    (q-length (/ q-and-gate-length 2))
                    (q-and-gate (compute-buffer-vector compute-buffer
                                                       :qwen-full-q-and-gate
                                                       q-and-gate-length))
                    (q (compute-buffer-vector compute-buffer :qwen-full-q q-length))
                    (gate (compute-buffer-vector compute-buffer :qwen-full-gate q-length))
                    (k (compute-buffer-vector compute-buffer :qwen-full-k k-length))
                    (v (compute-buffer-vector compute-buffer :qwen-full-v v-length))
                    (context (compute-buffer-vector compute-buffer :qwen-full-context q-length))
                    (q-heads nil)
                    (k-heads nil)
                    (v-heads nil))
               (declare (fixnum q-and-gate-length k-length v-length q-length))
               (gguf-model-matrix-vector-multiply-into q-and-gate
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_q")
                                                       attn-norm)
               (replace q q-and-gate :start2 0 :end2 q-length)
               (replace gate q-and-gate :start2 q-length)
               (gguf-model-matrix-vector-multiply-into k
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_k")
                                                       attn-norm)
               (gguf-model-matrix-vector-multiply-into v
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_v")
                                                       attn-norm)
               (normalize-vector-chunks-into q
                                             q
                                             head-count
                                             (gguf-model-load-vector-tensor
                                              model
                                              (make-layer-tensor-name layer-index "attn_q_norm"))
                                             :epsilon norm-epsilon)
               (normalize-vector-chunks-into k
                                             k
                                             kv-head-count
                                             (gguf-model-load-vector-tensor
                                              model
                                              (make-layer-tensor-name layer-index "attn_k_norm"))
                                             :epsilon norm-epsilon)
               (setf q-heads (compute-buffer-chunks compute-buffer :qwen-full-q-heads q head-count)
                     k-heads (compute-buffer-chunks compute-buffer :qwen-full-k-heads k kv-head-count)
                     v-heads (compute-buffer-chunks compute-buffer :qwen-full-v-heads v kv-head-count))
               (dotimes (head-index head-count)
                 (declare (fixnum head-index))
                 (apply-rope-head-in-place (aref q-heads head-index)
                                           position
                                           rope-dimension
                                           rope-base))
               (dotimes (head-index kv-head-count)
                 (declare (fixnum head-index))
                 (apply-rope-head-in-place (aref k-heads head-index)
                                           position
                                           rope-dimension
                                           rope-base))
               (vector-scale-into q q (/ (sqrt (/ q-length head-count))))
               (compute-gemma4-attention-into context
                                              compute-buffer
                                              model
                                              layer-index
                                              layer-index
                                              position
                                              q-heads
                                              k-heads
                                              v-heads
                                              kv-cache)
               (apply-sigmoid-into gate gate)
               (vector-elementwise-multiply-into context context gate)
               (gguf-model-matrix-vector-multiply-into mixer-output
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_output")
                                                       context)))
            ((qwen3next-recurrent-layer-p model layer-index)
             (let* ((mixed-qkv-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "attn_qkv")
                                              t)))
                    (gate-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "attn_gate")
                                              t)))
                    (ba-length
                     (tensor-row-count
                      (gguf-model-tensor-info model
                                              (make-layer-tensor-name layer-index "ssm_ba")
                                              t)))
                    (mixed-qkv (compute-buffer-vector compute-buffer
                                                      :qwen-recurrent-mixed-qkv
                                                      mixed-qkv-length))
                    (conv-qkv (compute-buffer-vector compute-buffer
                                                     :qwen-recurrent-conv-qkv
                                                     mixed-qkv-length))
                    (gate (compute-buffer-vector compute-buffer :qwen-recurrent-gate gate-length))
                    (ba (compute-buffer-vector compute-buffer :qwen-recurrent-ba ba-length))
                    (q-length (/ mixed-qkv-length 4))
                    (k-length q-length)
                    (v-length (* 2 q-length))
                    (q (compute-buffer-vector compute-buffer :qwen-recurrent-q q-length))
                    (k (compute-buffer-vector compute-buffer :qwen-recurrent-k k-length))
                    (v (compute-buffer-vector compute-buffer :qwen-recurrent-v v-length))
                    (ssm-a (gguf-model-load-vector-tensor model (make-layer-tensor-path layer-index "ssm_a")))
                    (ssm-dt-bias
                     (gguf-model-load-vector-tensor model
                                                    (make-layer-tensor-path layer-index "ssm_dt.bias")))
                    (ssm-norm
                     (gguf-model-load-vector-tensor model
                                                    (make-layer-tensor-name layer-index "ssm_norm")))
                    (conv-weight
                     (gguf-model-load-tensor model
                                             (make-layer-tensor-name layer-index "ssm_conv1d")))
                    (kernel-size (tensor-column-count
                                  (gguf-model-tensor-info model
                                                          (make-layer-tensor-name
                                                           layer-index
                                                           "ssm_conv1d")
                                                          t)))
                    (recurrent-head-count (length ssm-a))
                    (state-size (length ssm-norm))
                    (q-head-count (/ q-length state-size))
                    (cache (ensure-qwen3next-recurrent-layer-cache kv-cache
                                                                  layer-index
                                                                  mixed-qkv-length
                                                                  kernel-size
                                                                  recurrent-head-count
                                                                  state-size))
                    (conv-state (getf cache :conv-state))
                    (recurrent-state (getf cache :state))
                    (kv-mem (compute-buffer-vector compute-buffer :qwen-recurrent-kv-mem state-size))
                    (delta (compute-buffer-vector compute-buffer :qwen-recurrent-delta state-size))
                    (gated-output (compute-buffer-vector compute-buffer
                                                         :qwen-recurrent-gated-output
                                                         gate-length))
                    (query-scale (/ (sqrt state-size))))
               (declare (fixnum mixed-qkv-length gate-length ba-length q-length k-length v-length
                                kernel-size recurrent-head-count state-size q-head-count)
                        (single-float query-scale))
               (unless (zerop (mod recurrent-head-count q-head-count))
                 (error "Qwen3Next recurrent head count ~d is not divisible by q/k head count ~d."
                        recurrent-head-count
                        q-head-count))
               (gguf-model-matrix-vector-multiply-into mixed-qkv
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_qkv")
                                                       attn-norm)
               (gguf-model-matrix-vector-multiply-into gate
                                                       model
                                                       (make-layer-tensor-name layer-index "attn_gate")
                                                       attn-norm)
               (gguf-model-matrix-vector-multiply-into ba
                                                       model
                                                       (make-layer-tensor-name layer-index "ssm_ba")
                                                       attn-norm)
               (qwen3next-causal-conv1d-step-into conv-qkv
                                                  mixed-qkv
                                                  conv-state
                                                  conv-weight
                                                  kernel-size)
               (replace q conv-qkv :start2 0 :end2 q-length)
               (replace k conv-qkv :start2 q-length :end2 (+ q-length k-length))
               (replace v conv-qkv :start2 (+ q-length k-length) :end2 mixed-qkv-length)
               (l2-normalize-vector-chunks-into q q q-head-count :epsilon norm-epsilon)
               (l2-normalize-vector-chunks-into k k q-head-count :epsilon norm-epsilon)
               (fill gated-output 0.0f0)
               (dotimes (head-index recurrent-head-count)
                 (declare (fixnum head-index))
                 (let* ((q-head-index (mod head-index q-head-count))
                        (q-start (* q-head-index state-size))
                        (k-start q-start)
                        (v-start (* head-index state-size))
                        (state-offset (* head-index state-size state-size))
                        (beta (sigmoid (aref ba head-index)))
                        (decay
                         (coerce
                          (exp (* (aref ssm-a head-index)
                                  (log (+ 1.0d0
                                          (exp (+ (aref ba (+ recurrent-head-count head-index))
                                                  (aref ssm-dt-bias head-index)))))))
                          'single-float)))
                   (declare (fixnum q-head-index q-start k-start v-start state-offset)
                            (single-float beta decay))
                   (fill kv-mem 0.0f0)
                   (dotimes (state-row state-size)
                     (declare (fixnum state-row))
                     (let* ((state-row-offset (+ state-offset (* state-row state-size)))
                            (k-value (aref k (+ k-start state-row))))
                       (declare (fixnum state-row-offset)
                                (single-float k-value))
                       (dotimes (state-column state-size)
                         (declare (fixnum state-column))
                         (let* ((state-index (+ state-row-offset state-column))
                                (decayed-value (* (aref recurrent-state state-index) decay)))
                           (declare (fixnum state-index)
                                    (single-float decayed-value))
                           (setf (aref recurrent-state state-index) decayed-value)
                           (incf (aref kv-mem state-column)
                                 (* decayed-value k-value))))))
                   (dotimes (state-column state-size)
                     (declare (fixnum state-column))
                     (setf (aref delta state-column)
                           (* beta
                              (- (aref v (+ v-start state-column))
                                 (aref kv-mem state-column)))))
                   (dotimes (state-column state-size)
                     (declare (fixnum state-column))
                     (setf (aref gated-output (+ v-start state-column)) 0.0f0))
                   (dotimes (state-row state-size)
                     (declare (fixnum state-row))
                     (let* ((state-row-offset (+ state-offset (* state-row state-size)))
                            (k-value (aref k (+ k-start state-row)))
                            (q-value (* (aref q (+ q-start state-row)) query-scale)))
                       (declare (fixnum state-row-offset)
                                (single-float k-value q-value))
                       (dotimes (state-column state-size)
                         (declare (fixnum state-column))
                         (let* ((state-index (+ state-row-offset state-column))
                                (updated-value (+ (aref recurrent-state state-index)
                                                  (* k-value (aref delta state-column)))))
                           (declare (fixnum state-index)
                                    (single-float updated-value))
                           (setf (aref recurrent-state state-index) updated-value)
                           (incf (aref gated-output (+ v-start state-column))
                                 (* updated-value q-value)))))))
               (gated-normalize-vector-chunks-into gated-output
                                                   gated-output
                                                   gate
                                                   recurrent-head-count
                                                   ssm-norm
                                                   :epsilon norm-epsilon)
               (gguf-model-matrix-vector-multiply-into mixer-output
                                                       model
                                                       (make-layer-tensor-name layer-index "ssm_out")
                                                       gated-output))))
            (t
             (error "Qwen3Next layer ~d has neither full-attention nor recurrent tensors."
                    layer-index)))
          (vector-add-into x x mixer-output)
          (rms-norm-into ffn-input
                         x
                         (gguf-model-load-vector-tensor
                          model
                          (make-layer-tensor-name layer-index "post_attention_norm"))
                         :epsilon norm-epsilon)
          (qwen3next-moe-into ffn-output model layer-index ffn-input compute-buffer)
          (vector-add-into x x ffn-output))
        (when *compute-gguf-logits*
          (gguf-model-matrix-vector-multiply
           model
           (gguf-model-output-tensor-name model)
           (rms-norm-into (compute-buffer-vector compute-buffer :qwen-output-norm hidden-size)
                          x
                          (gguf-model-load-vector-tensor model "output_norm.weight")
                          :epsilon norm-epsilon)))))))

(defun nemotron-h-moe-recurrent-layer-p (model layer-index)
  (and (zerop (gguf-model-layer-kv-head-count model layer-index))
       (zerop (gguf-model-layer-ffn-size model layer-index))))

(defun nemotron-h-moe-attention-layer-p (model layer-index)
  (and (plusp (gguf-model-layer-kv-head-count model layer-index))
       (zerop (gguf-model-layer-ffn-size model layer-index))))

(defun nemotron-h-moe-ffn-layer-p (model layer-index)
  (and (zerop (gguf-model-layer-kv-head-count model layer-index))
       (plusp (gguf-model-layer-ffn-size model layer-index))))

(defun ensure-nemotron-h-moe-recurrent-layer-cache (kv-cache layer-index channel-count kernel-size state-length)
  (let ((entry (gethash layer-index kv-cache))
        (conv-state-length (* channel-count (1- kernel-size))))
    (declare (fixnum channel-count kernel-size state-length conv-state-length))
    (unless (and entry
                 (= (length (getf entry :conv-state)) conv-state-length)
                 (= (length (getf entry :state)) state-length))
      (setf entry (list :conv-state (make-array conv-state-length
                                                :element-type 'single-float
                                                :initial-element 0.0f0)
                        :state (make-array state-length
                                           :element-type 'single-float
                                           :initial-element 0.0f0))
            (gethash layer-index kv-cache) entry))
    entry))

(defun nemotron-h-moe-causal-conv1d-step-into (dest current-input conv-state conv-weight conv-bias kernel-size)
  (declare (optimize (speed 3) (safety 0))
           (type (simple-array single-float (*)) dest current-input conv-state conv-weight conv-bias)
           (fixnum kernel-size))
  (unless (= (length dest) (length current-input) (length conv-bias))
    (error "NEMOTRON-H-MOE-CAUSAL-CONV1D-STEP-INTO requires destination, input, and bias lengths to match."))
  (let* ((channel-count (length current-input))
         (state-width (1- kernel-size))
         (expected-state-length (* channel-count state-width))
         (expected-weight-length (* channel-count kernel-size)))
    (declare (fixnum channel-count state-width expected-state-length expected-weight-length))
    (unless (= (length conv-state) expected-state-length)
      (error "Convolution state length ~d does not match expected length ~d."
             (length conv-state)
             expected-state-length))
    (unless (= (length conv-weight) expected-weight-length)
      (error "Convolution weight length ~d does not match expected length ~d."
             (length conv-weight)
             expected-weight-length))
    (dotimes (channel-index channel-count dest)
      (declare (fixnum channel-index))
      (let* ((state-base (* channel-index state-width))
             (weight-base (* channel-index kernel-size))
             (current-value (aref current-input channel-index))
             (sum (aref conv-bias channel-index)))
        (declare (fixnum state-base weight-base)
                 (single-float current-value sum))
        (dotimes (tap-index state-width)
          (declare (fixnum tap-index))
          (incf sum
                (* (aref conv-state (+ state-base tap-index))
                   (aref conv-weight (+ weight-base tap-index)))))
        (incf sum (* current-value
                     (aref conv-weight (+ weight-base state-width))))
        (dotimes (tap-index (max 0 (1- state-width)))
          (declare (fixnum tap-index))
          (setf (aref conv-state (+ state-base tap-index))
                (aref conv-state (+ state-base tap-index 1))))
        (when (plusp state-width)
          (setf (aref conv-state (+ state-base (1- state-width))) current-value))
        (setf (aref dest channel-index)
              (silu sum))))))

(defun nemotron-h-moe-ffn-into (dest model layer-index input compute-buffer
                                     expert-top-k expert-weight-scale expert-weights-normalized-p)
  (declare (type (simple-array single-float (*)) dest input)
           (fixnum layer-index expert-top-k)
           (single-float expert-weight-scale))
  (let ((router-info (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "ffn_gate_inp")
                                             nil)))
    (unless router-info
      (error "Nemotron-H MoE layer ~d is missing router tensor." layer-index))
    (let* ((expert-count (tensor-row-count router-info))
           (top-k (min expert-count expert-top-k))
           (router-logits (compute-buffer-vector compute-buffer :nemotron-router-logits expert-count))
           (top-indices (compute-buffer-fixnum-vector compute-buffer :nemotron-top-indices top-k))
           (top-logits (compute-buffer-vector compute-buffer :nemotron-top-logits top-k))
           (top-weights (compute-buffer-vector compute-buffer :nemotron-top-weights top-k))
           (router-bias (gguf-model-load-vector-tensor model
                                                       (make-layer-tensor-path layer-index "exp_probs_b.bias")))
           (latent-down-info (gguf-model-tensor-info model
                                                     (make-layer-tensor-name layer-index "ffn_latent_down")
                                                     nil))
           (latent-up-info (gguf-model-tensor-info model
                                                   (make-layer-tensor-name layer-index "ffn_latent_up")
                                                   nil))
           (expert-input (if latent-down-info
                             (compute-buffer-vector compute-buffer
                                                    :nemotron-expert-input
                                                    (tensor-row-count latent-down-info))
                             input))
           (expert-hidden-size
            (tensor-row-count
             (gguf-model-tensor-info model
                                     (make-layer-tensor-name layer-index "ffn_up_exps")
                                     t)))
           (moe-output (if latent-up-info
                           (compute-buffer-vector compute-buffer
                                                  :nemotron-moe-output
                                                  (tensor-column-count latent-up-info))
                           dest))
           (expert-up (compute-buffer-vector compute-buffer :nemotron-expert-up expert-hidden-size))
           (expert-down (compute-buffer-vector compute-buffer :nemotron-expert-down (length moe-output)))
           (shared-up-info (gguf-model-tensor-info model
                                                   (make-layer-tensor-name layer-index "ffn_up_shexp")
                                                   nil))
           (shared-down-info (gguf-model-tensor-info model
                                                     (make-layer-tensor-name layer-index "ffn_down_shexp")
                                                     nil))
           (shared-up (and shared-up-info
                           (compute-buffer-vector compute-buffer
                                                  :nemotron-shared-up
                                                  (tensor-row-count shared-up-info))))
           (shared-down (and shared-down-info
                             (compute-buffer-vector compute-buffer
                                                    :nemotron-shared-down
                                                    (tensor-row-count shared-down-info)))))
      (declare (fixnum expert-count top-k expert-hidden-size))
      (when latent-down-info
        (gguf-model-matrix-vector-multiply-into expert-input
                                                model
                                                (make-layer-tensor-name layer-index "ffn_latent_down")
                                                input))
      (gguf-model-matrix-vector-multiply-into router-logits
                                              model
                                              (make-layer-tensor-name layer-index "ffn_gate_inp")
                                              input)
      (vector-add-bias-in-place router-logits router-bias)
      (select-top-k-logits-into top-indices top-logits router-logits top-k)
      (let ((weight-sum 0.0f0))
        (declare (single-float weight-sum))
        (dotimes (selected-index top-k)
          (declare (fixnum selected-index))
          (let ((weight (sigmoid (aref top-logits selected-index))))
            (declare (single-float weight))
            (setf (aref top-weights selected-index) weight)
            (incf weight-sum weight)))
        (when expert-weights-normalized-p
          (unless (plusp weight-sum)
            (error "Nemotron-H MoE layer ~d router produced non-positive top-k weight sum."
                   layer-index))
          (dotimes (selected-index top-k)
            (declare (fixnum selected-index))
            (setf (aref top-weights selected-index)
                  (/ (aref top-weights selected-index) weight-sum)))))
      (dotimes (selected-index top-k)
        (declare (fixnum selected-index))
        (setf (aref top-weights selected-index)
              (* expert-weight-scale (aref top-weights selected-index))))
      (fill moe-output 0.0f0)
      (dotimes (selected-index top-k)
        (declare (fixnum selected-index))
        (let ((expert-index (aref top-indices selected-index))
              (expert-weight (aref top-weights selected-index)))
          (declare (fixnum expert-index)
                   (single-float expert-weight))
          (gguf-model-expert-matrix-vector-multiply-into expert-up
                                                         model
                                                         (make-layer-tensor-name layer-index "ffn_up_exps")
                                                         expert-index
                                                         expert-input)
          (apply-relu-squared-into expert-up expert-up)
          (gguf-model-expert-matrix-vector-multiply-into expert-down
                                                         model
                                                         (make-layer-tensor-name layer-index "ffn_down_exps")
                                                         expert-index
                                                         expert-up)
          (vector-add-scaled-in-place moe-output expert-down expert-weight)))
      (if latent-up-info
          (gguf-model-matrix-vector-multiply-into dest
                                                  model
                                                  (make-layer-tensor-name layer-index "ffn_latent_up")
                                                  moe-output)
          (replace dest moe-output))
      (when (and shared-up shared-down)
        (gguf-model-matrix-vector-multiply-into shared-up
                                                model
                                                (make-layer-tensor-name layer-index "ffn_up_shexp")
                                                input)
        (apply-relu-squared-into shared-up shared-up)
        (gguf-model-matrix-vector-multiply-into shared-down
                                                model
                                                (make-layer-tensor-name layer-index "ffn_down_shexp")
                                                shared-up)
        (vector-add-bias-in-place dest shared-down)))))

(defun nemotron-h-moe-attention-into (dest model layer-index input position compute-buffer kv-cache
                                           head-count rope-dimension rope-base)
  (declare (type (simple-array single-float (*)) dest input)
           (fixnum layer-index position head-count rope-dimension))
  (let* ((kv-head-count (gguf-model-layer-kv-head-count model layer-index))
         (q-length (tensor-row-count
                    (gguf-model-tensor-info model
                                            (make-layer-tensor-name layer-index "attn_q")
                                            t)))
         (k-length (tensor-row-count
                    (gguf-model-tensor-info model
                                            (make-layer-tensor-name layer-index "attn_k")
                                            t)))
         (v-length (tensor-row-count
                    (gguf-model-tensor-info model
                                            (make-layer-tensor-name layer-index "attn_v")
                                            t)))
         (head-dimension (/ q-length head-count))
         (q (compute-buffer-vector compute-buffer :nemotron-q q-length))
         (k (compute-buffer-vector compute-buffer :nemotron-k k-length))
         (v (compute-buffer-vector compute-buffer :nemotron-v v-length))
         (context (compute-buffer-vector compute-buffer :nemotron-context q-length))
         (q-heads nil)
         (k-heads nil)
         (v-heads nil))
    (declare (fixnum kv-head-count q-length k-length v-length head-dimension))
    (gguf-model-matrix-vector-multiply-into q
                                            model
                                            (make-layer-tensor-name layer-index "attn_q")
                                            input)
    (gguf-model-matrix-vector-multiply-into k
                                            model
                                            (make-layer-tensor-name layer-index "attn_k")
                                            input)
    (gguf-model-matrix-vector-multiply-into v
                                            model
                                            (make-layer-tensor-name layer-index "attn_v")
                                            input)
    (setf q-heads (compute-buffer-chunks compute-buffer :nemotron-q-heads q head-count)
          k-heads (compute-buffer-chunks compute-buffer :nemotron-k-heads k kv-head-count)
          v-heads (compute-buffer-chunks compute-buffer :nemotron-v-heads v kv-head-count))
    (dotimes (head-index head-count)
      (declare (fixnum head-index))
      (apply-rope-head-in-place (aref q-heads head-index)
                                position
                                rope-dimension
                                rope-base))
    (dotimes (head-index kv-head-count)
      (declare (fixnum head-index))
      (apply-rope-head-in-place (aref k-heads head-index)
                                position
                                rope-dimension
                                rope-base))
    (vector-scale-into q q (/ (sqrt head-dimension)))
    (compute-gemma4-attention-into context
                                   compute-buffer
                                   model
                                   layer-index
                                   layer-index
                                   position
                                   q-heads
                                   k-heads
                                   v-heads
                                   kv-cache)
    (gguf-model-matrix-vector-multiply-into dest
                                            model
                                            (make-layer-tensor-name layer-index "attn_output")
                                            context)))

(defun nemotron-h-moe-recurrent-into (dest model layer-index input compute-buffer kv-cache
                                           ssm-inner-size ssm-state-size ssm-group-count
                                           ssm-head-count norm-epsilon)
  (declare (type (simple-array single-float (*)) dest input)
           (fixnum layer-index ssm-inner-size ssm-state-size ssm-group-count ssm-head-count)
           (single-float norm-epsilon))
  (let* ((kernel-size
          (gguf-kv-value (gguf-model-kv-pairs model)
                         "nemotron_h_moe.ssm.conv_kernel"))
         (channel-count (+ ssm-inner-size (* 2 ssm-group-count ssm-state-size)))
         (head-dimension (/ ssm-inner-size ssm-head-count))
         (heads-per-group (/ ssm-head-count ssm-group-count))
         (state-length (* ssm-inner-size ssm-state-size))
         (projected-length (+ (* 2 ssm-inner-size) (* 2 ssm-group-count ssm-state-size) ssm-head-count))
         (projected (compute-buffer-vector compute-buffer :nemotron-ssm-projected projected-length))
         (z (compute-buffer-vector compute-buffer :nemotron-ssm-z ssm-inner-size))
         (conv-input (compute-buffer-vector compute-buffer :nemotron-ssm-conv-input channel-count))
         (conv-output (compute-buffer-vector compute-buffer :nemotron-ssm-conv-output channel-count))
         (x (compute-buffer-vector compute-buffer :nemotron-ssm-x ssm-inner-size))
         (b (compute-buffer-vector compute-buffer :nemotron-ssm-b (* ssm-group-count ssm-state-size)))
         (c (compute-buffer-vector compute-buffer :nemotron-ssm-c (* ssm-group-count ssm-state-size)))
         (dt (compute-buffer-vector compute-buffer :nemotron-ssm-dt ssm-head-count))
         (y (compute-buffer-vector compute-buffer :nemotron-ssm-y ssm-inner-size))
         (gated (compute-buffer-vector compute-buffer :nemotron-ssm-gated ssm-inner-size))
         (ssm-a (gguf-model-load-tensor model (make-layer-tensor-path layer-index "ssm_a")))
         (ssm-d (gguf-model-load-tensor model (make-layer-tensor-path layer-index "ssm_d")))
         (ssm-dt-bias (gguf-model-load-vector-tensor model (make-layer-tensor-path layer-index "ssm_dt.bias")))
         (ssm-norm (gguf-model-load-tensor model (make-layer-tensor-name layer-index "ssm_norm")))
         (conv-weight (gguf-model-load-tensor model (make-layer-tensor-name layer-index "ssm_conv1d")))
         (conv-bias (gguf-model-load-vector-tensor model (make-layer-tensor-path layer-index "ssm_conv1d.bias")))
         (cache (ensure-nemotron-h-moe-recurrent-layer-cache kv-cache
                                                             layer-index
                                                             channel-count
                                                             kernel-size
                                                             state-length))
         (conv-state (getf cache :conv-state))
         (recurrent-state (getf cache :state)))
    (declare (fixnum kernel-size channel-count head-dimension heads-per-group state-length projected-length))
    (gguf-model-matrix-vector-multiply-into projected
                                            model
                                            (make-layer-tensor-name layer-index "ssm_in")
                                            input)
    (replace z projected :start2 0 :end2 ssm-inner-size)
    (replace conv-input projected
             :start2 ssm-inner-size
             :end2 (+ ssm-inner-size channel-count))
    (replace dt projected
             :start2 (+ (* 2 ssm-inner-size) (* 2 ssm-group-count ssm-state-size))
             :end2 projected-length)
    (nemotron-h-moe-causal-conv1d-step-into conv-output
                                            conv-input
                                            conv-state
                                            conv-weight
                                            conv-bias
                                            kernel-size)
    (replace x conv-output :start2 0 :end2 ssm-inner-size)
    (replace b conv-output
             :start2 ssm-inner-size
             :end2 (+ ssm-inner-size (* ssm-group-count ssm-state-size)))
    (replace c conv-output
             :start2 (+ ssm-inner-size (* ssm-group-count ssm-state-size))
             :end2 channel-count)
    (dotimes (head-index ssm-head-count)
      (declare (fixnum head-index))
      (let* ((group-index (floor head-index heads-per-group))
             (group-base (* group-index ssm-state-size))
             (head-base (* head-index head-dimension))
             (dt-softplus (softplus (+ (aref dt head-index)
                                       (aref ssm-dt-bias head-index))))
             (decay (coerce (exp (* dt-softplus (aref ssm-a head-index))) 'single-float))
             (d-value (aref ssm-d head-index)))
        (declare (fixnum group-index group-base head-base)
                 (single-float dt-softplus decay d-value))
        (dotimes (dim-index head-dimension)
          (declare (fixnum dim-index))
          (let* ((x-index (+ head-base dim-index))
                 (state-base (+ (* head-base ssm-state-size)
                                (* dim-index ssm-state-size)))
                 (x-value (aref x x-index))
                 (x-dt (* x-value dt-softplus))
                 (sum 0.0f0))
            (declare (fixnum x-index state-base)
                     (single-float x-value x-dt sum))
            (dotimes (state-index ssm-state-size)
              (declare (fixnum state-index))
              (let* ((offset (+ state-base state-index))
                     (updated-state (+ (* (aref recurrent-state offset) decay)
                                       (* (aref b (+ group-base state-index)) x-dt))))
                (declare (fixnum offset)
                         (single-float updated-state))
                (setf (aref recurrent-state offset) updated-state)
                (incf sum (* updated-state
                             (aref c (+ group-base state-index))))))
            (setf (aref y x-index)
                  (+ sum (* x-value d-value))))))
    (dotimes (index ssm-inner-size)
      (declare (fixnum index))
      (setf (aref gated index)
            (* (silu (aref z index))
               (aref y index))))
    (normalize-vector-chunks-with-chunk-weights-into y
                                                     gated
                                                     ssm-group-count
                                                     ssm-norm
                                                     :epsilon norm-epsilon)
    (gguf-model-matrix-vector-multiply-into dest
                                            model
                                            (make-layer-tensor-name layer-index "ssm_out")
                                            y))))

(defun load-nemotron-h-moe-model (mapping kv-pairs tensor-infos)
  (let ((architecture (gguf-kv-value kv-pairs "general.architecture")))
    (unless (string= architecture "nemotron_h_moe")
      (error "LOAD-NEMOTRON-H-MOE-MODEL only supports general.architecture = \"nemotron_h_moe\", got ~s."
             architecture))
    (let ((tensor-info-table (make-tensor-info-table tensor-infos)))
      (make-gguf-model
       :mapping mapping
       :kv-pairs kv-pairs
       :tensor-infos tensor-infos
       :tensor-info-table tensor-info-table
       :tensor-cache (make-hash-table :test #'equal)
       :architecture architecture
       :hidden-size (gguf-kv-value kv-pairs "nemotron_h_moe.embedding_length")
       :layer-count (gguf-kv-value kv-pairs "nemotron_h_moe.block_count")
       :head-count (gguf-kv-value kv-pairs "nemotron_h_moe.attention.head_count")
       :kv-head-count (gguf-kv-value kv-pairs "nemotron_h_moe.attention.head_count_kv")
       :ffn-size (gguf-kv-value kv-pairs "nemotron_h_moe.feed_forward_length")
       :norm-epsilon (gguf-kv-value kv-pairs "nemotron_h_moe.attention.layer_norm_rms_epsilon")
       :rope-base (gguf-kv-value kv-pairs "nemotron_h_moe.rope.freq_base")
       :rope-dimension (gguf-kv-value kv-pairs "nemotron_h_moe.rope.dimension_count")
       :output-tensor-name (if (gethash "output.weight" tensor-info-table)
                               "output.weight"
                               "token_embd.weight")))))

(defun make-nemotron-h-moe-step-function (model)
  (let ((head-count (gguf-model-head-count model))
        (hidden-size (gguf-model-hidden-size model))
        (norm-epsilon (gguf-model-norm-epsilon model))
        (rope-dimension (gguf-model-rope-dimension model))
        (rope-base (gguf-model-rope-base model))
        (ssm-inner-size (gguf-kv-value (gguf-model-kv-pairs model) "nemotron_h_moe.ssm.inner_size"))
        (ssm-state-size (gguf-kv-value (gguf-model-kv-pairs model) "nemotron_h_moe.ssm.state_size"))
        (ssm-group-count (gguf-kv-value (gguf-model-kv-pairs model) "nemotron_h_moe.ssm.group_count"))
        (ssm-head-count (gguf-kv-value (gguf-model-kv-pairs model) "nemotron_h_moe.ssm.time_step_rank"))
        (expert-top-k (gguf-kv-value (gguf-model-kv-pairs model) "nemotron_h_moe.expert_used_count"))
        (expert-weight-scale
         (coerce (or (gguf-kv-value-or-nil (gguf-model-kv-pairs model) "nemotron_h_moe.expert_weights_scale")
                     1.0f0)
                 'single-float))
        (expert-weights-normalized-p
         (not (null (gguf-kv-value-or-nil (gguf-model-kv-pairs model) "nemotron_h_moe.expert_weights_norm"))))
        (compute-buffer (make-compute-buffer)))
    (lambda (token-id position kv-cache)
      (let* ((input-embedding (compute-buffer-vector compute-buffer :nemotron-input-embedding hidden-size))
             (x (compute-buffer-vector compute-buffer :nemotron-x hidden-size))
             (block-input (compute-buffer-vector compute-buffer :nemotron-block-input hidden-size))
             (block-output (compute-buffer-vector compute-buffer :nemotron-block-output hidden-size)))
        (gguf-model-token-row-into input-embedding model "token_embd.weight" token-id)
        (replace x input-embedding)
        (dotimes (layer-index (gguf-model-layer-count model))
          (declare (fixnum layer-index))
          (rms-norm-into block-input
                         x
                         (gguf-model-load-vector-tensor
                          model
                          (make-layer-tensor-name layer-index "attn_norm"))
                         :epsilon norm-epsilon)
          (cond
            ((nemotron-h-moe-recurrent-layer-p model layer-index)
             (nemotron-h-moe-recurrent-into block-output
                                            model
                                            layer-index
                                            block-input
                                            compute-buffer
                                            kv-cache
                                            ssm-inner-size
                                            ssm-state-size
                                            ssm-group-count
                                            ssm-head-count
                                            norm-epsilon))
            ((nemotron-h-moe-attention-layer-p model layer-index)
             (nemotron-h-moe-attention-into block-output
                                            model
                                            layer-index
                                            block-input
                                            position
                                            compute-buffer
                                            kv-cache
                                            head-count
                                            rope-dimension
                                            rope-base))
            ((nemotron-h-moe-ffn-layer-p model layer-index)
             (nemotron-h-moe-ffn-into block-output
                                      model
                                      layer-index
                                      block-input
                                      compute-buffer
                                      expert-top-k
                                      expert-weight-scale
                                      expert-weights-normalized-p))
            (t
             (error "Nemotron-H MoE layer ~d has unsupported block pattern: kv-head-count=~s, ffn-size=~s."
                    layer-index
                    (gguf-model-layer-kv-head-count model layer-index)
                    (gguf-model-layer-ffn-size model layer-index))))
          (vector-add-into x x block-output))
        (when *compute-gguf-logits*
          (gguf-model-matrix-vector-multiply
           model
           (gguf-model-output-tensor-name model)
           (rms-norm-into (compute-buffer-vector compute-buffer :nemotron-output-norm hidden-size)
                          x
                          (gguf-model-load-vector-tensor model "output_norm.weight")
                          :epsilon norm-epsilon)))))))

(defun load-qwen2-model (mapping kv-pairs tensor-infos)
  (let ((architecture (gguf-kv-value kv-pairs "general.architecture")))
    (unless (string= architecture "qwen2")
      (error "LOAD-QWEN2-MODEL only supports general.architecture = \"qwen2\", got ~s."
             architecture))
    (let* ((tensor-info-table (make-tensor-info-table tensor-infos))
           (hidden-size (gguf-kv-value kv-pairs "qwen2.embedding_length"))
           (head-count (gguf-kv-value kv-pairs "qwen2.attention.head_count")))
      (make-gguf-model
       :mapping mapping
       :kv-pairs kv-pairs
       :tensor-infos tensor-infos
       :tensor-info-table tensor-info-table
       :tensor-cache (make-hash-table :test #'equal)
       :architecture architecture
       :hidden-size hidden-size
       :layer-count (gguf-kv-value kv-pairs "qwen2.block_count")
       :head-count head-count
       :kv-head-count (gguf-kv-value kv-pairs "qwen2.attention.head_count_kv")
       :ffn-size (gguf-kv-value kv-pairs "qwen2.feed_forward_length")
       :norm-epsilon (gguf-kv-value kv-pairs "qwen2.attention.layer_norm_rms_epsilon")
       :rope-base (gguf-kv-value kv-pairs "qwen2.rope.freq_base")
       :rope-dimension (or (gguf-kv-value-or-nil kv-pairs "qwen2.rope.dimension_count")
                           (/ hidden-size head-count))
       :output-tensor-name (if (gethash "output.weight" tensor-info-table)
                               "output.weight"
                               "token_embd.weight")))))

(defun load-llama-model (mapping kv-pairs tensor-infos)
  (let ((architecture (gguf-kv-value kv-pairs "general.architecture")))
    (unless (string= architecture "llama")
      (error "LOAD-LLAMA-MODEL only supports general.architecture = \"llama\", got ~s."
             architecture))
    (let ((tensor-info-table (make-tensor-info-table tensor-infos)))
      (make-gguf-model
       :mapping mapping
       :kv-pairs kv-pairs
       :tensor-infos tensor-infos
       :tensor-info-table tensor-info-table
       :tensor-cache (make-hash-table :test #'equal)
       :architecture architecture
       :hidden-size (gguf-kv-value kv-pairs "llama.embedding_length")
       :layer-count (gguf-kv-value kv-pairs "llama.block_count")
       :head-count (gguf-kv-value kv-pairs "llama.attention.head_count")
       :kv-head-count (gguf-kv-value kv-pairs "llama.attention.head_count_kv")
       :ffn-size (gguf-kv-value kv-pairs "llama.feed_forward_length")
       :norm-epsilon (gguf-kv-value kv-pairs "llama.attention.layer_norm_rms_epsilon")
       :rope-base (gguf-kv-value kv-pairs "llama.rope.freq_base")
       :rope-dimension (gguf-kv-value kv-pairs "llama.rope.dimension_count")
       :output-tensor-name (if (gethash "output.weight" tensor-info-table)
                              "output.weight"
                              "token_embd.weight")))))

(defun make-llama-step-function (model &key qkv-bias-p)
  (let* ((head-count (gguf-model-head-count model))
         (kv-head-count (gguf-model-kv-head-count model))
         (hidden-size (gguf-model-hidden-size model))
         (head-size (/ hidden-size head-count))
         (norm-epsilon (gguf-model-norm-epsilon model))
         (rope-dimension (gguf-model-rope-dimension model))
         (rope-base (gguf-model-rope-base model))
         (rope-factors (when (gguf-model-tensor-info model "rope_freqs.weight" nil)
                         (gguf-model-load-vector-tensor model "rope_freqs.weight")))
         (attention-scale (coerce (/ (sqrt head-size)) 'single-float))
         (compute-buffer (make-compute-buffer)))
    (unless (zerop (mod hidden-size head-count))
      (error "Llama hidden size ~d is not divisible by head count ~d."
             hidden-size
             head-count))
    (unless (zerop (mod head-count kv-head-count))
      (error "Llama head count ~d is not divisible by KV head count ~d."
             head-count
             kv-head-count))
    (lambda (token-id position kv-cache)
      (let ((input-embedding
              (compute-buffer-vector compute-buffer :llama-input-embedding hidden-size))
            (x (compute-buffer-vector compute-buffer :llama-x hidden-size)))
        (gguf-model-token-row-into input-embedding model "token_embd.weight" token-id)
        (replace x input-embedding)
        (dotimes (layer-index (gguf-model-layer-count model))
          (let* ((attn-input
                   (compute-buffer-vector compute-buffer :llama-attn-input hidden-size))
                 (q-length
                   (tensor-row-count
                    (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "attn_q")
                                           t)))
                 (k-length
                   (tensor-row-count
                    (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "attn_k")
                                           t)))
                 (v-length
                   (tensor-row-count
                    (gguf-model-tensor-info model
                                           (make-layer-tensor-name layer-index "attn_v")
                                           t)))
                 (q (compute-buffer-vector compute-buffer :llama-q q-length))
                 (k (compute-buffer-vector compute-buffer :llama-k k-length))
                 (v (compute-buffer-vector compute-buffer :llama-v v-length))
                 (q-heads (compute-buffer-chunks compute-buffer :llama-q-heads q head-count))
                 (k-heads (compute-buffer-chunks compute-buffer :llama-k-heads k kv-head-count))
                 (v-heads (compute-buffer-chunks compute-buffer :llama-v-heads v kv-head-count))
                 (attention-context
                   (compute-buffer-vector compute-buffer :llama-attention-context q-length))
                 (attention-output
                   (compute-buffer-vector compute-buffer :llama-attention-output hidden-size))
                 (ffn-input
                   (compute-buffer-vector compute-buffer :llama-ffn-input hidden-size))
                 (ffn-gate
                   (compute-buffer-vector compute-buffer
                                         :llama-ffn-gate
                                         (gguf-model-layer-ffn-size model layer-index)))
                 (ffn-up
                   (compute-buffer-vector compute-buffer
                                         :llama-ffn-up
                                         (gguf-model-layer-ffn-size model layer-index)))
                 (ffn-down
                   (compute-buffer-vector compute-buffer :llama-ffn-down hidden-size)))
            (unless (= (length (aref q-heads 0))
                       (length (aref k-heads 0))
                       (length (aref v-heads 0))
                       head-size)
              (error "Llama layer ~d has incompatible Q/K/V head dimensions." layer-index))
            (rms-norm-into attn-input
                          x
                          (gguf-model-load-vector-tensor
                           model
                           (make-layer-tensor-name layer-index "attn_norm"))
                          :epsilon norm-epsilon)
            (gguf-model-matrix-vector-multiply-into
             q model (make-layer-tensor-name layer-index "attn_q") attn-input)
            (gguf-model-matrix-vector-multiply-into
             k model (make-layer-tensor-name layer-index "attn_k") attn-input)
            (gguf-model-matrix-vector-multiply-into
             v model (make-layer-tensor-name layer-index "attn_v") attn-input)
            (when qkv-bias-p
              (vector-add-into
               q q
               (gguf-model-load-vector-tensor
                model
                (make-layer-tensor-path layer-index "attn_q.bias")))
              (vector-add-into
               k k
               (gguf-model-load-vector-tensor
                model
                (make-layer-tensor-path layer-index "attn_k.bias")))
              (vector-add-into
               v v
               (gguf-model-load-vector-tensor
                model
                (make-layer-tensor-path layer-index "attn_v.bias"))))
            (dotimes (head-index head-count)
              (apply-rope-head-in-place (aref q-heads head-index)
                                       position
                                       rope-dimension
                                       rope-base
                                       rope-factors))
            (dotimes (head-index kv-head-count)
              (apply-rope-head-in-place (aref k-heads head-index)
                                       position
                                       rope-dimension
                                       rope-base
                                       rope-factors))
            (vector-scale-into q q attention-scale)
            (compute-gemma4-attention-into attention-context
                                          compute-buffer
                                          model
                                          layer-index
                                          layer-index
                                          position
                                          q-heads
                                          k-heads
                                          v-heads
                                          kv-cache)
            (gguf-model-matrix-vector-multiply-into
             attention-output
             model
             (make-layer-tensor-name layer-index "attn_output")
             attention-context)
            (vector-add-into x x attention-output)
            (rms-norm-into ffn-input
                          x
                          (gguf-model-load-vector-tensor
                           model
                           (make-layer-tensor-name layer-index "ffn_norm"))
                          :epsilon norm-epsilon)
            (gguf-model-matrix-vector-multiply-into
             ffn-gate model (make-layer-tensor-name layer-index "ffn_gate") ffn-input)
            (gguf-model-matrix-vector-multiply-into
             ffn-up model (make-layer-tensor-name layer-index "ffn_up") ffn-input)
            (apply-silu-into ffn-gate ffn-gate)
            (vector-elementwise-multiply-into ffn-gate ffn-gate ffn-up)
            (gguf-model-matrix-vector-multiply-into
             ffn-down model (make-layer-tensor-name layer-index "ffn_down") ffn-gate)
            (vector-add-into x x ffn-down)))
        (when *compute-gguf-logits*
          (gguf-model-matrix-vector-multiply
           model
           (gguf-model-output-tensor-name model)
           (rms-norm-into (compute-buffer-vector compute-buffer
                                                :llama-output-norm
                                                hidden-size)
                          x
                          (gguf-model-load-vector-tensor model "output_norm.weight")
                          :epsilon norm-epsilon)))))))

(defun make-qwen2-step-function (model)
  (unless (string= (gguf-model-architecture model) "qwen2")
    (error "MAKE-QWEN2-STEP-FUNCTION requires a qwen2 model, got ~s."
           (gguf-model-architecture model)))
  (make-llama-step-function model :qkv-bias-p t))

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
                 (kv-head-count
                  (gguf-model-layer-kv-head-count model layer-index))
                 (k-length
                  (when uses-own-kv-p
                    (tensor-row-count
                     (gguf-model-tensor-info model
                                             (make-layer-tensor-name layer-index "attn_k")
                                             t))))
                 (v-length
                  (when uses-own-kv-p
                    (let ((v-tensor-info
                            (gguf-model-tensor-info model
                                                    (make-layer-tensor-name layer-index "attn_v")
                                                    nil)))
                      (if v-tensor-info
                          (tensor-row-count v-tensor-info)
                          k-length))))
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
              (let ((v-tensor-name (make-layer-tensor-name layer-index "attn_v")))
                (if (gguf-model-tensor-info model v-tensor-name nil)
                    (gguf-model-matrix-vector-multiply-into v
                                                            model
                                                            v-tensor-name
                                                            attn-norm)
                    (replace v k))))
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

(defun dequantize-q5-k (quantized-pointer element-count)
  "Dequantize GGML q5_K blocks into a simple array of single floats."
  (unless (zerop (mod element-count +qk-k+))
    (error "Q5_K dequantization requires ELEMENT-COUNT to be a multiple of ~d."
           +qk-k+))
  (let* ((block-size (+ 4 +k-scale-size+ (/ +qk-k+ 8) (/ +qk-k+ 2)))
         (block-count (/ element-count +qk-k+))
         (result (make-array element-count :element-type 'single-float)))
    (dotimes (block-index block-count result)
      (declare (fixnum block-index))
      (let* ((block-offset (* block-index block-size))
             (d (read-fp16-le quantized-pointer block-offset))
             (dmin (read-fp16-le quantized-pointer (+ block-offset 2)))
             (scales-pointer (cffi:inc-pointer quantized-pointer (+ block-offset 4)))
             (qh-pointer (cffi:inc-pointer quantized-pointer (+ block-offset 4 +k-scale-size+)))
             (qs-pointer (cffi:inc-pointer quantized-pointer
                                           (+ block-offset 4 +k-scale-size+ (/ +qk-k+ 8))))
             (result-base (* block-index +qk-k+))
             (u1 1)
             (u2 2)
             (scale-index 0))
        (declare (single-float d dmin)
                 (fixnum result-base u1 u2 scale-index))
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
                    (let ((packed (cffi:mem-aref qs-pointer :unsigned-char (+ q-base lane)))
                          (high-bits (cffi:mem-aref qh-pointer :unsigned-char (+ q-base lane))))
                      (declare (fixnum packed high-bits))
                      (setf (aref result (+ result-base chunk-base lane))
                            (coerce (- (* delta0
                                           (+ (logand packed #x0F)
                                              (if (logtest u1 high-bits) 16 0)))
                                        offset0)
                                    'single-float))
                      (setf (aref result (+ result-base chunk-base 32 lane))
                            (coerce (- (* delta1
                                           (+ (ash packed -4)
                                              (if (logtest u2 high-bits) 16 0)))
                                        offset1)
                                    'single-float))))
                  (incf scale-index 2)
                  (setf u1 (ash u1 2)
                        u2 (ash u2 2)))))))))))

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

(defun normalize-token-text (kv-pairs token)
  (let ((tokenizer-model (or (tokenizer-model kv-pairs) "")))
    (cond
      ((string= tokenizer-model "gpt2")
       (substitute #\Space (code-char #x0120) token))
      (t
       (substitute #\Space (code-char #x2581) token)))))

(defun raw-token-text (kv-pairs token-id)
  (let* ((tokens (gguf-kv-value kv-pairs "tokenizer.ggml.tokens"))
         (token-count (length tokens)))
    (unless (and (integerp token-id)
                 (<= 0 token-id)
                 (< token-id token-count))
      (error "Token id ~a is out of range for tokenizer with ~d tokens."
             token-id
             token-count))
    (nth token-id tokens)))

(defun make-gpt2-unicode-byte-table ()
  (let ((table (make-hash-table :test #'eql))
        (extra-code-point 256))
    (flet ((register-byte (byte code-point)
             (setf (gethash (code-char code-point) table) byte)))
      (mapc (lambda (byte)
              (register-byte byte byte))
            (append (loop for value from 33 to 126 collect value)
                    (loop for value from 161 to 172 collect value)
                    (loop for value from 174 to 255 collect value)))
      (dotimes (byte 256 table)
        (unless (or (<= 33 byte 126)
                    (<= 161 byte 172)
                    (<= 174 byte 255))
          (register-byte byte extra-code-point)
          (incf extra-code-point))))))

(defun gpt2-unicode-byte-table ()
  (or *gpt2-unicode-byte-table*
      (setf *gpt2-unicode-byte-table*
            (make-gpt2-unicode-byte-table))))

(defun gpt2-byte-unicode-table ()
  (or *gpt2-byte-unicode-table*
      (setf *gpt2-byte-unicode-table*
            (let ((table (make-array 256 :element-type 'character)))
             (maphash (lambda (character octet)
                        (setf (aref table octet) character))
                      (gpt2-unicode-byte-table))
             table))))

(defun gpt2-token-string-to-octets (token-string)
  (let ((table (gpt2-unicode-byte-table))
        (octets (make-array (length token-string) :element-type '(unsigned-byte 8))))
    (dotimes (index (length token-string) octets)
      (declare (fixnum index))
      (let* ((character (char token-string index))
             (octet (gethash character table)))
        (unless octet
          (error "No GPT2 byte mapping found for character ~s in token ~s."
                 character
                 token-string))
        (setf (aref octets index) octet)))))

(defun detokenize-token-id (kv-pairs token-id)
  (normalize-token-text kv-pairs (raw-token-text kv-pairs token-id)))

(defun detokenize-token-ids (kv-pairs token-ids &optional (stream *standard-output*))
  (let ((text (if (gpt2-tokenizer-p kv-pairs)
                  (let ((octet-list '()))
                    (dolist (token-id token-ids)
                      (let ((token-octets (gpt2-token-string-to-octets
                                           (raw-token-text kv-pairs token-id))))
                        (map nil (lambda (octet)
                                   (push octet octet-list))
                             token-octets)))
                    (octets-to-utf8-string
                     (coerce (nreverse octet-list) '(simple-array (unsigned-byte 8) (*)))))
                  (with-output-to-string (buffer)
                    (dolist (token-id token-ids)
                      (write-string (detokenize-token-id kv-pairs token-id) buffer))))))
    (write-string text stream)
    text))

(defun normalize-prompt-for-tokenization (prompt &optional kv-pairs)
  (let ((space-replacement
         (if (string= (or (and kv-pairs (tokenizer-model kv-pairs)) "")
                     "gpt2")
            (code-char #x0120)
            (code-char #x2581))))
  (map 'string
       (lambda (character)
         (if (char= character #\Space)
             space-replacement
             character))
       prompt)))

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

(defun make-base-token-pieces (kv-pairs prompt token-table)
  (map 'list
       (lambda (character)
         (let* ((token (string character))
                (entry (gethash token token-table)))
           (unless entry
             (error "No base token found for character ~s." token))
           (cons (car entry) token)))
       (normalize-prompt-for-tokenization prompt kv-pairs)))

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
        (normalized-prompt (normalize-prompt-for-tokenization prompt kv-pairs))
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

(defun tokenize-gpt2-text-fragment (fragment token-id-table bpe-rank-table
                                    pre-tokenizer)
  (labels ((letter-p (character)
             (alpha-char-p character))
           (number-p (character)
             (not (null (digit-char-p character))))
           (symbol-p (character)
             (and (not (member character '(#\Space #\Tab #\Newline #\Return #\Page)))
                  (not (letter-p character))
                  (not (number-p character))))
           (consume-while (start predicate)
             (let ((cursor start))
               (loop while (and (< cursor (length fragment))
                                (funcall predicate (char fragment cursor)))
                     do (incf cursor))
               cursor))
           (matching-contraction-end (start)
             (when (char= (char fragment start) #\')
               (dolist (suffix '("'re" "'ve" "'ll" "'s" "'t" "'m" "'d"))
                 (let ((end (+ start (length suffix))))
                   (when (and (<= end (length fragment))
                              (string-equal suffix fragment
                                            :start2 start
                                            :end2 end))
                     (return end))))))
           (split-pre-tokens ()
             (let ((segments '())
                   (cursor 0)
                   (fragment-length (length fragment)))
               (flet ((emit (end)
                        (push (subseq fragment cursor end) segments)
                        (setf cursor end)))
                 (loop while (< cursor fragment-length)
                       do (let* ((character (char fragment cursor))
                                 (contraction-end
                                   (matching-contraction-end cursor)))
                            (cond
                              (contraction-end
                               (emit contraction-end))
                              ((letter-p character)
                               (emit (consume-while cursor #'letter-p)))
                              ((and (not (member character '(#\Newline #\Return)))
                                    (not (letter-p character))
                                    (not (number-p character))
                                    (< (1+ cursor) fragment-length)
                                    (letter-p (char fragment (1+ cursor))))
                               (emit (consume-while (1+ cursor) #'letter-p)))
                              ((number-p character)
                               (let ((number-end (consume-while cursor #'number-p)))
                                 (emit (if (string= pre-tokenizer "qwen2")
                                           (1+ cursor)
                                           (min number-end (+ cursor 3))))))
                              ((or (symbol-p character)
                                   (and (char= character #\Space)
                                        (< (1+ cursor) fragment-length)
                                        (symbol-p (char fragment (1+ cursor)))))
                               (let* ((symbol-start (if (char= character #\Space)
                                                        (1+ cursor)
                                                        cursor))
                                      (symbol-end (consume-while symbol-start #'symbol-p))
                                      (end (consume-while
                                            symbol-end
                                            (lambda (ch)
                                              (member ch '(#\Newline #\Return))))))
                                 (emit end)))
                              ((member character '(#\Space #\Tab #\Newline #\Return #\Page))
                               (let* ((run-end
                                       (consume-while
                                        cursor
                                        (lambda (ch)
                                          (member ch
                                                  '(#\Space #\Tab #\Newline #\Return #\Page)))))
                                      (last-newline
                                       (position-if
                                        (lambda (ch)
                                          (member ch '(#\Newline #\Return)))
                                        fragment
                                        :start cursor
                                        :end run-end
                                        :from-end t)))
                                 (cond
                                   (last-newline
                                    (emit (1+ last-newline)))
                                   ((= run-end fragment-length)
                                    (emit run-end))
                                   ((> (- run-end cursor) 1)
                                    (emit (1- run-end)))
                                   (t
                                    (emit run-end)))))
                              (t
                               (emit (1+ cursor)))))))
               (nreverse segments)))
           (tokenize-pre-token (pre-token)
             (let* ((byte-unicode-table (gpt2-byte-unicode-table))
                    (pieces
                      (map 'list
                           (lambda (octet)
                             (string (aref byte-unicode-table octet)))
                           (utf8-string-to-octets pre-token))))
               (do ()
                   (nil)
                 (let ((merge-index (find-best-bpe-merge pieces bpe-rank-table)))
                   (unless merge-index
                     (return))
                   (setf pieces (merge-string-pieces pieces merge-index))))
               (mapcar (lambda (piece)
                         (multiple-value-bind (token-id presentp)
                             (gethash piece token-id-table)
                           (unless presentp
                             (error "No GPT2 token found for byte-encoded piece ~s."
                                    piece))
                           token-id))
                       pieces))))
    (let ((token-ids '()))
      (dolist (pre-token (split-pre-tokens) token-ids)
        (setf token-ids
              (nconc token-ids (tokenize-pre-token pre-token)))))))

(defun tokenize-gpt2-prompt (kv-pairs prompt)
  (let ((token-id-table (tokenizer-token-id-table kv-pairs))
        (bpe-rank-table (tokenizer-merge-rank-table kv-pairs))
        (special-tokens (tokenizer-special-tokens kv-pairs))
        (token-ids '())
        (cursor 0)
        (fragment-start 0)
        (prompt-length (length prompt))
        (pre-tokenizer (or (gguf-kv-value-or-nil kv-pairs "tokenizer.ggml.pre")
                           "")))
    (labels ((append-fragment (start end)
               (when (< start end)
                 (setf token-ids
                       (nconc token-ids
                              (tokenize-gpt2-text-fragment
                               (subseq prompt start end)
                               token-id-table
                               bpe-rank-table
                               pre-tokenizer))))))
      (loop while (< cursor prompt-length)
            for special-token = (find-matching-special-token prompt cursor special-tokens)
            do (if special-token
                   (progn
                     (append-fragment fragment-start cursor)
                     (multiple-value-bind (token-id presentp)
                         (gethash special-token token-id-table)
                       (unless presentp
                         (error "Special token ~s missing from token id table."
                                special-token))
                       (setf token-ids (nconc token-ids (list token-id))))
                     (incf cursor (length special-token))
                     (setf fragment-start cursor))
                   (incf cursor)))
      (append-fragment fragment-start prompt-length))
    token-ids))

(defun tokenize-greedy-token-prompt (kv-pairs prompt)
  (let* ((token-table (tokenizer-entry-table kv-pairs))
        (pieces (make-base-token-pieces kv-pairs prompt token-table)))
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
         (tokenizer-model (or (tokenizer-model kv-pairs) ""))
         (token-ids (cond
                      ((string= tokenizer-model "gemma4")
                       (tokenize-gemma4-prompt kv-pairs prompt))
                      ((string= tokenizer-model "gpt2")
                       (tokenize-gpt2-prompt kv-pairs prompt))
                      (t
                       (tokenize-greedy-token-prompt kv-pairs prompt)))))
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

(defstruct (aligned-tensor-mapping
            (:constructor %make-aligned-tensor-mapping
                (&key tensors views mapping-handle file-handle)))
  tensors
  views
  mapping-handle
  file-handle
  (closed-p nil))

(defstruct (aligned-tensor-view
            (:constructor %make-aligned-tensor-view
                (&key mapping pointer length element-type)))
  mapping
  pointer
  length
  element-type)

(defun ensure-aligned-tensor-view-open (tensor)
  (let ((mapping (aligned-tensor-view-mapping tensor)))
    (when (or (null mapping)
              (aligned-tensor-mapping-closed-p mapping)
              (cffi:null-pointer-p (aligned-tensor-view-pointer tensor)))
      (error "The aligned tensor view is closed.")))
  tensor)

(defun aligned-tensor-view-ref (tensor index)
  "Read one element from an open aligned tensor view."
  (ensure-aligned-tensor-view-open tensor)
  (unless (and (integerp index)
               (<= 0 index)
               (< index (aligned-tensor-view-length tensor)))
    (error "Aligned tensor index ~s is outside [0, ~d)."
           index
           (aligned-tensor-view-length tensor)))
  (ecase (aligned-tensor-view-element-type tensor)
    (:single-float
     (cffi:mem-aref
      (aligned-tensor-view-pointer tensor) :float index))
    (:unsigned-byte-8
     (cffi:mem-aref
      (aligned-tensor-view-pointer tensor) :unsigned-char index))))

(defun aligned-tensor-view-dot-product (left right)
  "Compute a dot product directly from two open aligned float tensor views."
  (ensure-aligned-tensor-view-open left)
  (ensure-aligned-tensor-view-open right)
  (unless (and (eq :single-float (aligned-tensor-view-element-type left))
               (eq :single-float (aligned-tensor-view-element-type right)))
    (error "Aligned tensor dot products require single-float views."))
  (let ((length (aligned-tensor-view-length left)))
    (unless (= length (aligned-tensor-view-length right))
      (error "Aligned tensor lengths do not match: ~d and ~d."
             length
             (aligned-tensor-view-length right)))
    (let ((left-pointer (aligned-tensor-view-pointer left))
          (right-pointer (aligned-tensor-view-pointer right))
          (sum 0.0f0))
      (declare (single-float sum)
               (optimize (speed 3) (safety 0)))
      (dotimes (index length sum)
        (setf sum
              (+ sum
                 (* (cffi:mem-aref left-pointer :float index)
                    (cffi:mem-aref right-pointer :float index))))))))

(defun close-aligned-tensor-mapping (mapping)
  "Invalidate tensor views and release every native resource owned by MAPPING.

The operation is idempotent. Extracted tensor views reject access before their
backing views are unmapped."
  (check-type mapping aligned-tensor-mapping)
  (unless (aligned-tensor-mapping-closed-p mapping)
    (setf (aligned-tensor-mapping-closed-p mapping) t)
    (dolist (tensor (aligned-tensor-mapping-tensors mapping))
      (setf (aligned-tensor-view-pointer tensor) (cffi:null-pointer)
            (aligned-tensor-view-mapping tensor) nil))
    (setf (aligned-tensor-mapping-tensors mapping) nil))
  (when (or (aligned-tensor-mapping-views mapping)
            (aligned-tensor-mapping-mapping-handle mapping)
            (aligned-tensor-mapping-file-handle mapping))
    (let ((failed-views '())
          (first-error nil))
      (dolist (view (aligned-tensor-mapping-views mapping))
        (unless (unmap-view-of-file view)
          (push view failed-views)
          (unless first-error
            (setf first-error
                  (make-condition
                   'simple-error
                   :format-control "UnmapViewOfFile failed for an aligned tensor view.")))))
      (setf (aligned-tensor-mapping-views mapping) (nreverse failed-views))
      (let ((mapping-handle
              (aligned-tensor-mapping-mapping-handle mapping)))
        (when mapping-handle
          (if (close-handle mapping-handle)
              (setf (aligned-tensor-mapping-mapping-handle mapping) nil)
              (unless first-error
                (setf first-error
                      (make-condition
                       'simple-error
                       :format-control "CloseHandle failed for an aligned tensor mapping."))))))
      (let ((file-handle (aligned-tensor-mapping-file-handle mapping)))
        (when file-handle
          (if (close-handle file-handle)
              (setf (aligned-tensor-mapping-file-handle mapping) nil)
              (unless first-error
                (setf first-error
                      (make-condition
                       'simple-error
                       :format-control "CloseHandle failed for an aligned tensor file."))))))
      (when first-error
        (error first-error))))
  mapping)

(defun report-aligned-tensor-cleanup-failure (condition)
  (format *error-output*
          "~&WARNING: Aligned tensor cleanup also failed: ~a~%"
          condition)
  (finish-output *error-output*))

(defun call-with-aligned-tensor-mapping
    (gguf-pathname temp-pathname receiver)
  "Call RECEIVER with an aligned tensor mapping and always close it afterward."
  (let ((mapping
          (map-gguf-tensors-to-aligned-arrays gguf-pathname temp-pathname))
        (completed-p nil))
    (unwind-protect
        (multiple-value-prog1
            (funcall receiver mapping)
          (setf completed-p t))
      (handler-case
          (close-aligned-tensor-mapping mapping)
        (error (cleanup-condition)
          (if completed-p
              (error cleanup-condition)
              (report-aligned-tensor-cleanup-failure
               cleanup-condition)))))))

(defmacro with-aligned-tensor-mapping
    ((mapping gguf-pathname temp-pathname) &body body)
  `(call-with-aligned-tensor-mapping
    ,gguf-pathname
    ,temp-pathname
    (lambda (,mapping)
      ,@body)))

(defun %map-gguf-tensors-to-aligned-arrays
    (gguf-pathname temp-pathname owner-receiver)
  "Copy GGUF tensors into 64KB-aligned mapped chunks.

Returns an ALIGNED-TENSOR-MAPPING that owns opaque zero-copy tensor views,
mapped views, the mapping handle, and the file handle. Call
CLOSE-ALIGNED-TENSOR-MAPPING when done, or prefer
WITH-ALIGNED-TENSOR-MAPPING."
  (let ((generic-write #x40000000)
        (create-always 2)
        (page-readwrite #x00000004)
        (file-map-write #x00000002))
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
            (let ((native-temp-path
                    (uiop:native-namestring temp-pathname))
                  (temp-handle nil)
                  (temp-mapping-handle nil)
                  (mapping nil)
                  (completed-p nil))
              (unwind-protect
                  (cffi:with-foreign-string
                      (temp-name-ptr native-temp-path :encoding :utf-16le)
                    (setf temp-handle
                          (create-file temp-name-ptr
                                       (logior +generic-read+ generic-write)
                                       +file-share-read+
                                       (cffi:null-pointer)
                                       create-always
                                       +file-attribute-normal+
                                       (cffi:null-pointer)))
                    (when (invalid-handle-p temp-handle)
                      (setf temp-handle nil)
                      (error "CreateFileW failed for temporary file ~a."
                             native-temp-path))
                    (setf mapping
                          (%make-aligned-tensor-mapping
                           :tensors nil
                           :views nil
                           :mapping-handle nil
                           :file-handle temp-handle))
                    (funcall owner-receiver mapping)
                    (unless (zerop total-temp-size)
                      (setf temp-mapping-handle
                            (create-file-mapping
                             temp-handle
                             (cffi:null-pointer)
                             page-readwrite
                             (ash total-temp-size -32)
                             (logand total-temp-size #xFFFFFFFF)
                             (cffi:null-pointer)))
                      (when (cffi:null-pointer-p temp-mapping-handle)
                        (setf temp-mapping-handle nil)
                        (error "CreateFileMappingW failed for temporary file."))
                      (setf (aligned-tensor-mapping-mapping-handle mapping)
                            temp-mapping-handle))
                    (dolist (layout temp-layout)
                      (let* ((info (getf layout :info))
                             (byte-size (getf layout :byte-size))
                             (required-size (getf layout :required-size))
                             (target-offset (getf layout :target-offset))
                             (temp-view
                               (map-view-of-file
                                temp-mapping-handle
                                file-map-write
                                (ash target-offset -32)
                                (logand target-offset #xFFFFFFFF)
                                required-size)))
                        (when (cffi:null-pointer-p temp-view)
                          (error "MapViewOfFile failed at offset #x~X for size ~D."
                                 target-offset required-size))
                        (push temp-view
                              (aligned-tensor-mapping-views mapping))
                        (let* ((is-f32
                                 (= (getf info :type-tag)
                                    +ggml-type-f32+))
                               (tensor-pointer
                                 (cffi:inc-pointer temp-view 16))
                               (tensor-length
                                 (if is-f32
                                     (getf info :element-count)
                                     byte-size)))
                          (rtl-move-memory
                           tensor-pointer
                           (cffi:inc-pointer
                            gguf-mapping
                            (getf info :data-offset))
                           byte-size)
                          (push
                           (%make-aligned-tensor-view
                            :mapping mapping
                            :pointer tensor-pointer
                            :length tensor-length
                            :element-type
                            (if is-f32
                                :single-float
                                :unsigned-byte-8))
                           (aligned-tensor-mapping-tensors mapping)))))
                    (setf (aligned-tensor-mapping-tensors mapping)
                          (nreverse
                           (aligned-tensor-mapping-tensors mapping))
                          completed-p t)
                    mapping)
                (unless completed-p
                  (handler-case
                      (when mapping
                        (close-aligned-tensor-mapping mapping))
                    (error (cleanup-condition)
                      (report-aligned-tensor-cleanup-failure
                       cleanup-condition))))))))))))

(defun map-gguf-tensors-to-aligned-arrays (gguf-pathname temp-pathname)
  "Create an owning mapping of opaque zero-copy tensor views."
  (let ((mapping nil)
        (completed-p nil))
    (unwind-protect
        (multiple-value-prog1
            (%map-gguf-tensors-to-aligned-arrays
             gguf-pathname
             temp-pathname
             (lambda (owner)
               (setf mapping owner)))
          (setf completed-p t))
      (unless completed-p
        (when mapping
          (handler-case
              (close-aligned-tensor-mapping mapping)
            (error (cleanup-condition)
              (report-aligned-tensor-cleanup-failure
               cleanup-condition))))))))

(defun hello-message ()
  "Return the default startup message for llambda."
  "llambda ready.")

(defun main ()
  (format t "~a~%" (hello-message)))
