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

(asdf:defsystem #:llambda/chatbot
  :description "Chatbot backend adapter for native llambda GGUF inference"
  :depends-on (#:llambda #:chatbot)
  :serial t
  :components ((:file "chatbot-backend")))

(asdf:defsystem #:llambda/chatbot-tests
  :depends-on (#:llambda/chatbot #:fiveam)
  :serial t
  :components ((:file "chatbot-backend-tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call '#:llambda/chatbot-tests '#:run-tests)
               (error "llambda chatbot backend tests failed."))))
