;;; ob-json.el --- jq-backed babel executor + json-ts highlighting -*- lexical-binding: t -*-
;;;; -                                                                   Settings
(require 'org-src)                                                    ;> org-src-lang-modes lives there; a no-op under init.el (:after org)

(defvar ts-json-lib-url                                              ;> grammar source for treesit-language-source-alist below
  "https://github.com/tree-sitter/tree-sitter-json")

(defun org-babel-execute:json (body params)                           ;> C-c C-c on a json block pretty-prints it through jq
  "Pretty-print BODY with jq; PARAMS are ignored."
  (org-babel-eval "jq -M" body))

(with-eval-after-load 'treesit                                        ;> grammar installed once via (treesit-install-language-grammar 'json)
  (add-to-list 'treesit-language-source-alist                         ;. the var only exists once treesit.el loads (not at ob-json load time)
               (list 'json ts-json-lib-url)))                         ;. list, not quote — the URL is a variable; quoted it was an unevaluated symbol
(add-to-list 'org-src-lang-modes '("json" . json-ts))                 ;> json-ts-mode (built-in) handles editing/highlighting the babel block

(provide 'ob-json)
;;; ob-json.el ends here
