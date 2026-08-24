;;; ob-json.el --- Mahatmus Emacs Configuration Fork -*- lexical-binding: t -*-
;;;; -                                                                   Settings
(provide 'ob-json)

(defvar ts-json-lib-url
  "https://github.com/tree-sitter/tree-sitter-json")

(defun org-babel-execute:json (body params)                           ;> Use JQ wrapper
  (org-babel-eval "jq -M" body))

(with-eval-after-load 'treesit                                        ;> grammar installed once via (treesit-install-language-grammar 'json)
  (add-to-list 'treesit-language-source-alist                         ;. the var only exists once treesit.el loads (not at ob-json load time)
               (list 'json ts-json-lib-url)))                         ;. list, not quote — the URL is a variable; quoted it was an unevaluated symbol
(add-to-list 'org-src-lang-modes '("json" . json-ts))                 ;> json-ts-mode (built-in) handles editing/highlighting the babel block.
