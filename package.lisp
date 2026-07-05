(defpackage #:llambda
  (:use #:cl)
  (:export #:call-with-file
           #:call-with-mapped-file
           #:close-handle
           #:create-file
           #:hello-message
           #:map-view-of-file
           #:main
           #:read-gguf-header
           #:unmap-view-of-file
           #:with-file-handle
           #:with-mapped-file))
