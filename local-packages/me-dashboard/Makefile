EMACS    ?= emacs
PKG      := me-dashboard
# Extra -L flags for dependencies that are not on the default load path,
# e.g. LOADPATH="-L ~/.emacs.d/straight/build/magit-section".
LOADPATH ?=

.PHONY: test compile checkdoc clean

test:
	$(EMACS) -Q --batch -L . $(LOADPATH) -l ert -l $(PKG)-tests.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . $(LOADPATH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(PKG).el
	rm -f $(PKG).elc

checkdoc:
	@out=$$($(EMACS) -Q --batch --eval '(checkdoc-file "$(PKG).el")' 2>&1); \
	  echo "$$out"; \
	  if echo "$$out" | grep -q '^$(PKG).el:[0-9]'; then exit 1; fi

clean:
	rm -f *.elc
