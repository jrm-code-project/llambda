(in-package #:llambda)

(register-accelerator-backend
 (make-accelerator-backend
  :name :gpu
  :display-name "GPU"
  :priority 10
  :initialization-priority 20
  :load-function #'load-gpu-backend
  :available-p-function #'gpu-backend-available-p
  :runtime-version-function #'gpu-backend-runtime-version
  :bridge-version-function #'npu-bridge-version
  :make-session-function
  (lambda (model-path &key cache-directory cache-key)
    (declare (ignore cache-directory cache-key))
    (make-gpu-session model-path))
  :close-session-function #'close-gpu-session
  :run-session-function #'run-gpu-session-into
  :session-input-element-count-function #'gpu-session-input-element-count
  :session-output-element-count-function #'gpu-session-output-element-count
  :error-p-function (lambda (condition)
                      (typep condition 'gpu-backend-error))
  :signal-error-function #'gpu-backend-error
  :default-cache-directory-function #'default-gpu-cache-directory
  :export-projection-function #'export-model-gpu-projection
  :weight-format :float32
  :foreign-data-sha256-function #'foreign-data-sha256
  :byte-vector-sha256-function #'byte-vector-sha256)
 :replace t)
