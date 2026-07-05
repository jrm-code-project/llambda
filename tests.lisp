(defpackage #:llambda/tests
  (:use #:cl #:fiveam)
  (:import-from #:llambda #:call-with-file
                          #:call-with-mapped-file
                          #:close-handle
                          #:create-file
                          #:hello-message
                          #:map-view-of-file
                          #:read-gguf-header
                          #:unmap-view-of-file
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
  (is (fboundp 'create-file))
  (is (fboundp 'close-handle))
  (is (fboundp 'map-view-of-file))
  (is (fboundp 'read-gguf-header))
  (is (fboundp 'unmap-view-of-file))
  (is (macro-function 'with-file-handle))
  (is (macro-function 'with-mapped-file)))

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

(defun run-tests ()
  (let ((result (run 'llambda-suite)))
    (explain! result)
    (unless (results-status result)
      (error "llambda test run failed."))
    result))
