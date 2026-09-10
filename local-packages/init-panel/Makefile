EMACS ?= emacs
PKG   := init-panel

.PHONY: test compile checkdoc lint clean

test:
	$(EMACS) -Q --batch -L . -l ert -l $(PKG)-tests.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(PKG).el
	rm -f $(PKG).elc

checkdoc:
	$(EMACS) -Q --batch --eval '(checkdoc-file "$(PKG).el")'

lint:
	$(EMACS) -Q --batch -L . -l package-lint -f package-lint-batch-and-exit $(PKG).el

clean:
	rm -f *.elc
