(in-package #:llambda)

(defstruct (architecture-descriptor
            (:constructor %make-architecture-descriptor
                (&key name loader step-constructor validator
                      tokenizer-policy required-metadata-keys
                      required-tensor-groups)))
  (name (error "Architecture name is required.")
        :type string
        :read-only t)
  (loader (error "Architecture loader is required.")
          :type function
          :read-only t)
  (step-constructor (error "Architecture step constructor is required.")
                    :type function
                    :read-only t)
  (validator nil :type (or null function) :read-only t)
  (tokenizer-policy :generic :read-only t)
  (required-metadata-keys nil :type list :read-only t)
  (required-tensor-groups nil :type list :read-only t))

(defvar *architecture-descriptors*
  (make-hash-table :test #'equal))

(defun register-architecture
    (name loader step-constructor
     &key validator (tokenizer-policy :generic)
       required-metadata-keys required-tensor-groups replace)
  "Register one immutable architecture descriptor under its raw GGUF name.
REPLACE permits idempotent reloads of built-in architecture modules."
  (unless (and (stringp name) (plusp (length name)))
    (error "Architecture name must be a non-empty string, got ~s." name))
  (unless (functionp loader)
    (error "Architecture ~s loader is not a function." name))
  (unless (functionp step-constructor)
    (error "Architecture ~s step constructor is not a function." name))
  (when (and (gethash name *architecture-descriptors*)
             (not replace))
    (error "Architecture ~s is already registered." name))
  (let ((descriptor
          (%make-architecture-descriptor
           :name name
           :loader loader
           :step-constructor step-constructor
           :validator validator
           :tokenizer-policy tokenizer-policy
           :required-metadata-keys required-metadata-keys
           :required-tensor-groups required-tensor-groups)))
    (setf (gethash name *architecture-descriptors*) descriptor)
    descriptor))

(defun find-architecture-descriptor (name &optional requiredp)
  (let ((descriptor
          (and name (gethash name *architecture-descriptors*))))
    (when (and requiredp (null descriptor))
      (error "Unsupported GGUF architecture ~s. Supported architectures: ~{~a~^, ~}."
             name
             (supported-architecture-names)))
    descriptor))

(defun supported-architecture-names ()
  (sort (loop for name being the hash-keys of *architecture-descriptors*
              collect name)
        #'string<))

(defun architecture-name-from-kv-pairs (kv-pairs)
  (cdr (assoc "general.architecture" kv-pairs :test #'string=)))

(defun architecture-descriptor-for-kv-pairs (kv-pairs &optional requiredp)
  (find-architecture-descriptor
   (architecture-name-from-kv-pairs kv-pairs)
   requiredp))

(defun validate-architecture-inputs
    (descriptor kv-pairs tensor-infos)
  (let ((name (architecture-descriptor-name descriptor)))
    (unless (string= name
                     (or (architecture-name-from-kv-pairs kv-pairs) ""))
      (error "Architecture descriptor ~s cannot load general.architecture ~s."
             name
             (architecture-name-from-kv-pairs kv-pairs)))
    (dolist (key
             (architecture-descriptor-required-metadata-keys descriptor))
      (unless (assoc key kv-pairs :test #'string=)
        (error "Architecture ~s is missing required GGUF metadata ~s."
               name
               key)))
    (dolist (alternatives
             (architecture-descriptor-required-tensor-groups descriptor))
      (unless (some (lambda (tensor-name)
                      (find tensor-name
                            tensor-infos
                            :key (lambda (tensor-info)
                                   (getf tensor-info :name))
                            :test #'string=))
                    alternatives)
        (error "Architecture ~s requires one of tensors ~{~s~^, ~}."
               name
               alternatives)))
    (let ((validator (architecture-descriptor-validator descriptor)))
      (when validator
        (funcall validator kv-pairs tensor-infos))))
  descriptor)

(defun load-architecture-model
    (descriptor mapping kv-pairs tensor-infos)
  (validate-architecture-inputs descriptor kv-pairs tensor-infos)
  (funcall (architecture-descriptor-loader descriptor)
           mapping
           kv-pairs
           tensor-infos))

(defun make-architecture-step-function (descriptor model)
  (funcall (architecture-descriptor-step-constructor descriptor) model))
