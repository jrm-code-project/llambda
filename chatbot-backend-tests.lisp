(defpackage #:llambda/chatbot-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:llambda/chatbot-tests)

(def-suite llambda-chatbot-suite)

(in-suite llambda-chatbot-suite)

(test backend-registration
  (is (eq (gethash :llambda chatbot:*chat-backends*)
          #'llambda/chatbot:llambda-chat-backend-handler)))

(test backend-turn
  (let* ((bot (make-instance 'chatbot::chatbot
                             :backend :llambda
                             :model "D:/models/local.gguf"
                             :system-instruction #("Be concise." "Stay accurate.")))
         (conversation
           (make-instance
            'chatbot::conversation
            :chatbot bot
            :messages '((("role" . "user") ("content" . "Earlier question"))
                        (("role" . "assistant") ("content" . "Earlier answer")))))
         (callback-text nil)
         (captured-model nil)
         (captured-arguments nil)
         (llambda/chatbot::*llambda-generate-response-function*
           (lambda (model &rest arguments)
             (setf captured-model model
                   captured-arguments arguments)
             (funcall (getf arguments :callback) "local response")
             (values nil nil '(1) "local response" nil))))
    (let ((result
            (llambda/chatbot:llambda-chat-backend-handler
             "New question"
             :bot bot
             :conversation conversation
             :callback (lambda (text)
                         (setf callback-text text))
             :effective-generation-config
             '(:temperature 0.25f0 :top-p 0.8f0 :top-k 12))))
      (is (string= "D:/models/local.gguf" captured-model))
      (is (search "System: Be concise." (getf captured-arguments :prompt)))
      (is (search "User: Earlier question" (getf captured-arguments :prompt)))
      (is (search "Assistant: Earlier answer" (getf captured-arguments :prompt)))
      (is (search "User: New question" (getf captured-arguments :prompt)))
      (is (= 0.25f0 (getf captured-arguments :temperature)))
      (is (= 0.8f0 (getf captured-arguments :top-p)))
      (is (= 12 (getf captured-arguments :top-k)))
      (is (string= "local response" callback-text))
      (is (string= "local response" (chatbot::chat-turn-result-text result)))
      (is (equal "assistant"
                 (cdr (assoc "role"
                             (car (last (chatbot::chat-turn-result-messages result)))
                             :test #'string=)))))))

(test backend-turn-uses-sampling-defaults-for-nil-config
  (let* ((bot (make-instance 'chatbot::chatbot
                             :backend :llambda
                             :model "D:/models/local.gguf"))
         (conversation (make-instance 'chatbot::conversation :chatbot bot))
         (captured-arguments nil)
         (llambda/chatbot::*llambda-generate-response-function*
           (lambda (model &rest arguments)
             (declare (ignore model))
             (setf captured-arguments arguments)
             (values nil nil nil "response" nil))))
    (llambda/chatbot:llambda-chat-backend-handler
     "prompt"
     :bot bot
     :conversation conversation
     :effective-generation-config '(:temperature nil :top-p nil :top-k nil))
    (is (= 1.0f0 (getf captured-arguments :temperature)))
    (is (= 0.95f0 (getf captured-arguments :top-p)))
    (is (= 40 (getf captured-arguments :top-k)))))

(test backend-rejects-attachments
  (let* ((bot (make-instance 'chatbot::chatbot
                             :backend :llambda
                             :model "D:/models/local.gguf"))
         (conversation (make-instance 'chatbot::conversation :chatbot bot)))
    (signals error
      (llambda/chatbot:llambda-chat-backend-handler
       "prompt"
       :bot bot
       :conversation conversation
       :file-attachments '(:unsupported)))))

(defun run-tests ()
  (let ((result (run 'llambda-chatbot-suite)))
    (explain! result)
    (results-status result)))
