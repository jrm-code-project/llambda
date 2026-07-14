(in-package #:llambda)

(register-accelerator-backend
 (make-accelerator-backend
  :name :npu
  :display-name "NPU"
  :priority 20
  :initialization-priority 10
  :load-function #'load-npu-backend
  :available-p-function #'npu-backend-available-p
  :runtime-version-function #'npu-backend-runtime-version
  :bridge-version-function #'npu-bridge-version
  :make-session-function #'make-npu-session
  :close-session-function #'close-npu-session
  :run-session-function #'run-npu-session-into
  :session-input-element-count-function #'npu-session-input-element-count
  :session-output-element-count-function #'npu-session-output-element-count
  :error-p-function (lambda (condition)
                      (typep condition 'npu-backend-error))
  :signal-error-function #'npu-backend-error
  :default-cache-directory-function #'default-npu-cache-directory
  :export-projection-function #'export-model-npu-projection
  :weight-format :bfloat16
  :foreign-data-sha256-function #'foreign-data-sha256
  :byte-vector-sha256-function #'byte-vector-sha256)
 :replace t)
