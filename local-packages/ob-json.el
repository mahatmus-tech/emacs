;;; ob-json.el --- jq-backed babel executor and json-ts highlighting -*- lexical-binding: t -*-

;;; Commentary:

;; Org Babel support for JSON blocks: C-c C-c pretty-prints the body through
;; jq, and the block is edited and highlighted with `json-ts-mode'.
;; Needs the jq binary and the tree-sitter JSON grammar; install the grammar
;; once with (treesit-install-language-grammar 'json).

;;; Code:

(require 'org-src) ;> org-src-lang-modes lives there; a no-op under init.el (:after org)

(defvar me/ob-json-grammar-url "https://github.com/tree-sitter/tree-sitter-json" ;> grammar source for treesit-language-source-alist below
  "Repository `treesit-install-language-grammar' clones for the JSON grammar.")

(defun org-babel-execute:json (body _params) ;> the hook name Org Babel looks up for a json block
  "Pretty-print BODY with jq."
  (org-babel-eval "jq -M" body))

(with-eval-after-load 'treesit ;> the alist only exists once treesit.el loads
  (add-to-list 'treesit-language-source-alist
               (list 'json me/ob-json-grammar-url))) ;. list, not quote: the URL is a variable

(add-to-list 'org-src-lang-modes '("json" . json-ts)) ;> json-ts-mode (built-in) edits and highlights the block

(provide 'ob-json)
;;; ob-json.el ends here
