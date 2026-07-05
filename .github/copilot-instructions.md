# Copilot instructions for `llambda`

## Repository state

- `README.md` describes the repository as **"LLM hacks"**.
- The current Lisp bootstrap consists of `llambda.asd`, `package.lisp`, `llambda.lisp`, and `tests.lisp`.

## Build, test, and lint

- There is no separate lint setup committed yet.
- Run the full test suite with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:test-system :llambda)'`
- Run the single `hello-message` test with:
  `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-asd #P"D:/repositories/llambda/llambda.asd")' --eval '(asdf:load-system :llambda/tests)' --eval '(let ((result (fiveam:run (quote llambda/tests::hello-message)))) (fiveam:explain! result) (unless (fiveam:results-status result) (error "single test failed")))'`

## High-level architecture

- `llambda.asd` is the top-level ASDF definition. The main `llambda` system uses `:serial t` to load `package.lisp` before `llambda.lisp`.
- `llambda/tests` is a separate ASDF system that depends on `llambda` and `fiveam`, loads `tests.lisp`, and is invoked by `asdf:test-system`.
- `package.lisp` defines the public package surface, `llambda.lisp` holds runtime code, and `tests.lisp` contains the FiveAM suite and the exported `run-tests` entrypoint used by ASDF.

## Key conventions

- Treat Lisp-family compiled artifacts as generated files. `.gitignore` excludes `*.FASL`, `*.fasl`, `*.lisp-temp`, `*.dfsl`, `*.pfsl`, and architecture-specific variants such as `*.d64fsl`, `*.p64fsl`, `*.lx64fsl`, `*.lx32fsl`, `*.dx64fsl`, `*.dx32fsl`, `*.fx64fsl`, `*.fx32fsl`, `*.sx64fsl`, `*.sx32fsl`, `*.wx64fsl`, and `*.wx32fsl`.
- Keep public API exports in `package.lisp`; tests should import those symbols instead of reaching into implementation details.
- Add future tests to the separate `llambda/tests` ASDF system instead of the main runtime system.
