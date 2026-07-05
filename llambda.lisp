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

(defun read-u64-le (pointer offset)
  (loop for index from 0 below 8
        for byte = (cffi:mem-aref pointer :unsigned-char (+ offset index))
        sum (ash byte (* 8 index))))

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

(defun hello-message ()
  "Return the default startup message for llambda."
  "llambda ready.")

(defun main ()
  (format t "~a~%" (hello-message)))
