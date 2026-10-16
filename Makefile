# Checks for the whole configuration; `make check` is the one to run.
EMACS ?= emacs
# Packages the local packages need at compile time; override in CI.
LOADPATH ?= $(foreach d,$(wildcard straight/build/*/),-L $(abspath $(d)))
PACKAGES := me-dashboard

.PHONY: check check-parens check-init check-packages

check: check-parens check-init check-packages

# Read every top-level form: catches unbalanced parentheses early.
check-parens:
	$(EMACS) -Q --batch --eval '(dolist (f (list "early-init.el" "custom.el" "init.el")) (with-temp-buffer (insert-file-contents f) (set-syntax-table emacs-lisp-mode-syntax-table) (condition-case e (while (progn (forward-comment (buffer-size)) (not (eobp))) (read (current-buffer))) (error (message "%s: %S" f e) (kill-emacs 1)))))'

# Start the whole configuration in batch mode; it must finish without error.
check-init:
	$(EMACS) --batch -l early-init.el -l init.el --eval '(message "INIT OK")' 2>&1 | tee /tmp/init-check.log | tail -5
	@grep -q '^INIT OK' /tmp/init-check.log

# Byte-compile (warnings are errors), checkdoc and ERT for each local package.
check-packages:
	@for p in $(PACKAGES); do \
	  $(MAKE) -C local-packages/$$p test compile checkdoc LOADPATH="$(LOADPATH)" || exit 1; \
	done
	@rm -f local-packages/*/*.elc
