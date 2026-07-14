(in-package #:llambda)

(defstruct (accelerator-backend
            (:constructor make-accelerator-backend
                (&key name display-name priority load-function
                      initialization-priority
                      available-p-function runtime-version-function
                      bridge-version-function make-session-function
                      close-session-function run-session-function
                      session-input-element-count-function
                      session-output-element-count-function
                      error-p-function signal-error-function
                      default-cache-directory-function
                      export-projection-function weight-format
                      foreign-data-sha256-function
                      byte-vector-sha256-function)))
  (name (error "Accelerator backend name is required.")
        :type symbol
        :read-only t)
  (display-name (error "Accelerator backend display name is required.")
                :type string
                :read-only t)
  (priority (error "Accelerator backend priority is required.")
            :type real
            :read-only t)
  (initialization-priority
   (error "Accelerator backend initialization priority is required.")
   :type real
   :read-only t)
  (load-function (error "Accelerator backend load function is required.")
                 :type function
                 :read-only t)
  (available-p-function
   (error "Accelerator backend availability function is required.")
   :type function
   :read-only t)
  (runtime-version-function
   (error "Accelerator backend runtime version function is required.")
   :type function
   :read-only t)
  (bridge-version-function
   (error "Accelerator backend bridge version function is required.")
   :type function
   :read-only t)
  (make-session-function
   (error "Accelerator backend session constructor is required.")
   :type function
   :read-only t)
  (close-session-function
   (error "Accelerator backend session close function is required.")
   :type function
   :read-only t)
  (run-session-function
   (error "Accelerator backend session run function is required.")
   :type function
   :read-only t)
  (session-input-element-count-function
   (error "Accelerator backend input size function is required.")
   :type function
   :read-only t)
  (session-output-element-count-function
   (error "Accelerator backend output size function is required.")
   :type function
   :read-only t)
  (error-p-function
   (error "Accelerator backend error predicate is required.")
   :type function
   :read-only t)
  (signal-error-function
   (error "Accelerator backend error signaler is required.")
   :type function
   :read-only t)
  (default-cache-directory-function
   (error "Accelerator backend cache directory function is required.")
   :type function
   :read-only t)
  (export-projection-function
   (error "Accelerator backend projection exporter is required.")
   :type function
   :read-only t)
  (weight-format (error "Accelerator backend weight format is required.")
                 :type symbol
                 :read-only t)
  (foreign-data-sha256-function
   (error "Accelerator backend foreign-data SHA-256 function is required.")
   :type function
   :read-only t)
  (byte-vector-sha256-function
   (error "Accelerator backend byte-vector SHA-256 function is required.")
   :type function
   :read-only t))

(defvar *accelerator-backends* (make-hash-table :test #'eq))

(defun register-accelerator-backend (backend &key replace)
  "Register BACKEND by name. REPLACE supports idempotent adapter reloads."
  (unless (accelerator-backend-p backend)
    (error "Expected an accelerator backend descriptor, got ~s." backend))
  (let ((name (accelerator-backend-name backend)))
    (when (and (gethash name *accelerator-backends*)
               (not replace))
      (error "Accelerator backend ~s is already registered." name))
    (setf (gethash name *accelerator-backends*) backend))
  backend)

(defun find-accelerator-backend (name &optional requiredp)
  (let ((backend (and name (gethash name *accelerator-backends*))))
    (when (and requiredp (null backend))
      (error "Unknown accelerator backend ~s. Registered backends: ~{~s~^, ~}."
             name
             (mapcar #'accelerator-backend-name
                     (ordered-accelerator-backends))))
    backend))

(defun ordered-accelerator-backends ()
  "Return registered backends in preferred execution order."
  (sort (loop for backend being the hash-values of *accelerator-backends*
              collect backend)
        #'<
        :key #'accelerator-backend-priority))

(defun accelerator-backend-error-p (backend condition)
  (funcall (accelerator-backend-error-p-function backend) condition))

(defun signal-accelerator-backend-error
    (backend format-control &rest format-arguments)
  (apply (accelerator-backend-signal-error-function backend)
         format-control
         format-arguments))
