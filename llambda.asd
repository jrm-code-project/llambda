(asdf:defsystem #:llambda
  :description "LLM hacks"
  :version "0.1.0"
  :license "MIT"
  :serial t
  :depends-on (#:cffi #:sb-simd #:lparallel)
  :in-order-to ((test-op (test-op "llambda/tests")))
  :components ((:file "package")
               (:file "llambda")))

(asdf:defsystem #:llambda/tests
  :depends-on (#:llambda #:fiveam)
  :serial t
  :components ((:file "tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call '#:llambda/tests '#:run-tests)))
