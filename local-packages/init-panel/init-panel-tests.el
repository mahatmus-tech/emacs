;;; init-panel-tests.el --- Tests for init-panel -*- lexical-binding: t -*-

;; Run:  emacs -Q --batch -L . -l ert -l init-panel-tests.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'init-panel)

(defconst init-panel-tests--elisp "\
;;; init.el --- test file -*- lexical-binding: t -*-
;;; ------------------------------------------------------------------- Core
;;;; -                                                                   Settings
(setq ring-bell-function 'ignore) ;> silence all error bells
(setq-default truncate-lines t)                                       ;> [fix]: C-x o o o keeps `find-file' and find-file happy
                                                                      ;. continuation line
(add-hook 'after-init-hook #'column-number-mode) ;> hook target
(keymap-global-set \"C-c w\" 'ignore) ;> key target
(load (expand-file-name \"custom.el\" user-emacs-directory)) ;> list argument, no target
(add-hook 'enable-theme-functions #'a-very-long-function-name-that-passes-column-seventy) ;> wide line
;; TAB on heading → cycle; see `describe-symbol' and M-x foo
;;;###autoload
(defun test-fn () \"Doc.\" (message \"C-c d\")) ; inline remark
;;; Files
;;;; Packages
(use-package winner ;> undo/redo window layout
  :hook (after-init . winner-mode)
  :bind ((\"C-x w u\" . winner-undo)
         :map foo-map
         (\"x\" . y))
  :custom
  (winner-dont-bind-my-keys t))
(use-package nerd-icons)
")

(defconst init-panel-tests--sh "\
### Section One
#### Sub One
export FOO=1 #> why foo
export BAR=2 #> [perf]: bar is fast
# plain remark about C-c w
")

(defmacro init-panel-tests--with-buffer (mode text &rest body)
  "Run BODY in a fontified MODE buffer holding TEXT with `init-panel-mode' on."
  (declare (indent 2))
  `(with-temp-buffer
     (insert ,text)
     (,mode)
     (font-lock-mode 1)
     (cl-letf (((symbol-function 'init-panel--displayable-p) (lambda (_) t)))
       (init-panel-mode 1)
       (font-lock-ensure)
       ,@body)))

(defun init-panel-tests--goto (needle)
  "Move to the beginning of the line containing NEEDLE."
  (goto-char (point-min))
  (search-forward needle)
  (beginning-of-line))

(defun init-panel-tests--prop (needle offset prop)
  "PROP at OFFSET from the start of the line containing NEEDLE."
  (init-panel-tests--goto needle)
  (get-text-property (+ (point) offset) prop))

(defun init-panel-tests--faces (needle offset)
  "Faces (as a list) at OFFSET from the start of the line containing NEEDLE."
  (let ((f (init-panel-tests--prop needle offset 'face)))
    (if (listp f) f (list f))))

(defun init-panel-tests--margin-string (needle)
  "Margin string of the overlay on the line containing NEEDLE."
  (init-panel-tests--goto needle)
  (let ((ov (seq-find (lambda (o) (overlay-get o 'init-panel-margin))
                      (overlays-in (point) (1+ (point))))))
    (and ov (cadr (get-text-property 0 'display (overlay-get ov 'before-string))))))

;;;; Headings

(ert-deftest init-panel-heading-level-faces ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (should (memq 'init-panel-section (init-panel-tests--faces ";;; ---" 72)))
    (should (memq 'init-panel-subsection (init-panel-tests--faces ";;;; -" 73)))))

(ert-deftest init-panel-heading-rules ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (let ((d (init-panel-tests--prop ";;; ---" 6 'display)))
      (should (stringp d))
      (should (= (length d) 67))
      (should (string-prefix-p "───" d)))
    (should (equal (init-panel-tests--prop ";;;; -" 5 'display) "╌"))
    (should (string-prefix-p "╌╌" (init-panel-tests--prop ";;;; -" 7 'display)))))

(ert-deftest init-panel-heading-dashless-rule ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (let ((d (init-panel-tests--prop ";;; Files" 3 'display)))
      (should (stringp d))
      (should (string-match-p "\\`[ ]─+ \\'" d)))))

(ert-deftest init-panel-heading-icons-and-fallback ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (should (equal (init-panel-tests--prop ";;; ---" 0 'display)
                   (cdr (assoc "core\\|general\\|basic\\|default" init-panel-section-icons))))
    (should (equal (init-panel-tests--prop ";;; Files" 0 'display)
                   (cdr (assoc "file\\|dired" init-panel-section-icons))))
    (should (null (init-panel-tests--prop ";;; init.el ---" 0 'display)))))

(ert-deftest init-panel-glyphs-degrade-to-text ()
  (with-temp-buffer
    (insert init-panel-tests--elisp)
    (emacs-lisp-mode)
    (font-lock-mode 1)
    (cl-letf (((symbol-function 'init-panel--displayable-p) (lambda (_) nil)))
      (init-panel-mode 1)
      (font-lock-ensure)
      (should (null (init-panel-tests--prop ";;; ---" 0 'display)))
      (should (null (init-panel-tests--prop ";;; ---" 6 'display)))
      (init-panel-tests--goto "(setq ring-bell-function")
      (re-search-forward ";>")
      (should (null (get-text-property (- (point) 2) 'display))))))

;;;; Notes

(ert-deftest init-panel-note-column-and-glyph ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "(setq ring-bell-function")
    (re-search-forward ";>")
    (should (equal (get-text-property (- (point) 3) 'display)
                   `(space :align-to (,init-panel-column . width))))
    (should (equal (get-text-property (- (point) 2) 'display) "→"))
    (should (memq 'init-panel-note (let ((f (get-text-property (1- (line-end-position)) 'face))) (if (listp f) f (list f)))))
    (init-panel-tests--goto ";. continuation")
    (re-search-forward ";\\.")
    (should (equal (get-text-property (- (point) 2) 'display) "↳"))))

(ert-deftest init-panel-note-wide-line-not-stretched ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "wide line")
    (re-search-forward ";>")
    (should (null (get-text-property (- (point) 3) 'display)))
    (should (equal (get-text-property (- (point) 2) 'display) "→"))))

(ert-deftest init-panel-note-decorations ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "[fix]: C-x o o o")
    (re-search-forward "\\[fix\\]")
    (should (memq 'init-panel-tag-fix (let ((f (get-text-property (- (point) 2) 'face))) (if (listp f) f (list f)))))
    (re-search-forward "C-x o")
    (should (memq 'help-key-binding (let ((f (get-text-property (- (point) 3) 'face))) (if (listp f) f (list f)))))
    (re-search-forward "`find-file'")
    (should (eq (get-text-property (- (point) 3) 'init-panel-symbol) 'find-file))
    (should (get-text-property (- (point) 3) 'keymap))
    (re-search-forward "and find-file")
    (should (eq (get-text-property (- (point) 2) 'init-panel-symbol) 'find-file))
    (re-search-forward "happy")
    (should (null (get-text-property (- (point) 2) 'init-panel-symbol)))))

(ert-deftest init-panel-link-follows ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "`find-file'")
    (re-search-forward "`find-file'")
    (backward-char 3)
    (should (eq (key-binding (kbd "RET")) 'init-panel-describe-at-point))
    (init-panel-describe-at-point)
    (should (get-buffer "*Help*"))))

;;;; Targets and prose

(ert-deftest init-panel-targets ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (should (memq 'init-panel-target (init-panel-tests--faces "(setq ring-bell" 6)))
    (should (memq 'init-panel-target (init-panel-tests--faces "(add-hook 'after-init" 11)))
    (should (memq 'init-panel-target (init-panel-tests--faces "(keymap-global-set" 20)))
    (should (memq 'init-panel-target (init-panel-tests--faces "(use-package winner" 13)))
    (should-not (memq 'init-panel-target (init-panel-tests--faces "(load (expand-file-name" 7)))))

(ert-deftest init-panel-prose-comments ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (should (equal (init-panel-tests--prop ";; TAB on heading" 0 'display) "▎"))
    (should (memq 'help-key-binding (init-panel-tests--faces ";; TAB on heading" 3)))
    (init-panel-tests--goto ";; TAB on heading")
    (re-search-forward "`describe-symbol'")
    (should (eq (get-text-property (- (point) 3) 'init-panel-symbol) 'describe-symbol))
    (should (null (init-panel-tests--prop ";;;###autoload" 0 'display)))
    (init-panel-tests--goto "; inline remark")
    (re-search-forward "; inline")
    (should (equal (get-text-property (- (point) 8) 'display) "·"))
    (re-search-forward "C-c d" nil t)
    (init-panel-tests--goto "(defun test-fn")
    (search-forward "\"C-c d\"")
    (should (null (get-text-property (- (point) 3) 'display)))))

;;;; Left margin

(ert-deftest init-panel-kind-icons-in-margin ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (let ((init-panel-section-guide nil))
      (init-panel--locate-point)
      (init-panel--jit-margin (point-min) (point-max))
      (should (string-suffix-p (cdr (assoc "use-package\\|package-install\\|straight-use-package" init-panel-kind-icons))
                               (init-panel-tests--margin-string "(use-package winner")))
      (should (string-suffix-p (cdr (assoc "add-hook\\|remove-hook" init-panel-kind-icons))
                               (init-panel-tests--margin-string "(add-hook 'after-init")))
      (should (null (init-panel-tests--margin-string ";;; ---"))))))

(ert-deftest init-panel-section-marker ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (let ((init-panel-section-guide 'marker))
      (init-panel-tests--goto "(setq ring-bell-function")
      (setq init-panel--section-bounds nil)
      (init-panel--guide-update)
      (init-panel--jit-margin (point-min) (point-max))
      (should (string-prefix-p init-panel-marker-char (init-panel-tests--margin-string ";;; ---")))
      (should (string-prefix-p init-panel-marker-char (init-panel-tests--margin-string ";;;; -")))
      (should-not (string-prefix-p init-panel-marker-char (or (init-panel-tests--margin-string ";;; Files") " ")))
      (init-panel-tests--goto "(use-package winner")
      (init-panel--guide-update)
      (init-panel--jit-margin (point-min) (point-max))
      (should (string-prefix-p init-panel-marker-char (init-panel-tests--margin-string ";;; Files")))
      (should-not (string-prefix-p init-panel-marker-char (or (init-panel-tests--margin-string ";;; ---") " "))))))

;;;; Folding, summaries, navigation

(ert-deftest init-panel-fold-states ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-fold)
    (init-panel-tests--goto ";;;; -")
    (should (invisible-p (point)))
    (init-panel-fold-subsections)
    (should-not (invisible-p (point)))
    (init-panel-tests--goto "(setq ring-bell")
    (should (invisible-p (point)))
    (init-panel-show-headings)
    (should-not (invisible-p (point)))
    (outline-show-all)))

(ert-deftest init-panel-fold-summary ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (outline-show-all)
    (init-panel-tests--goto "(use-package winner")
    (outline-hide-subtree)
    (let ((ov (seq-find (lambda (o) (overlay-get o 'init-panel-summary))
                        (overlays-in (line-end-position) (1+ (line-end-position))))))
      (should ov)
      (should (equal (substring-no-properties (overlay-get ov 'after-string)) " hook bind custom")))
    (outline-show-subtree)
    (should (null (seq-filter (lambda (o) (overlay-get o 'init-panel-summary))
                              (overlays-in (point-min) (point-max)))))))

(ert-deftest init-panel-header-and-imenu ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "(setq ring-bell")
    (should (equal (substring-no-properties (init-panel--header)) " Core › Settings"))
    (should (equal (init-panel--current-section) "Core › Settings"))
    (require 'imenu)
    (let ((idx (imenu--make-index-alist t)))
      (should (assoc "Section" idx))
      (should (equal (mapcar #'car (cdr (assoc "Packages" idx))) '("winner" "nerd-icons"))))))

;;;; Other comment syntax

(ert-deftest init-panel-hash-comments ()
  (init-panel-tests--with-buffer sh-mode init-panel-tests--sh
    (should (memq 'init-panel-section (init-panel-tests--faces "### Section One" 4)))
    (should (memq 'init-panel-subsection (init-panel-tests--faces "#### Sub One" 5)))
    (init-panel-tests--goto "export FOO")
    (re-search-forward "#>")
    (should (equal (get-text-property (- (point) 2) 'display) "→"))
    (should (equal (get-text-property (- (point) 3) 'display)
                   `(space :align-to (,init-panel-column . width))))
    (init-panel-tests--goto "export BAR")
    (re-search-forward "\\[perf\\]")
    (should (memq 'init-panel-tag-perf (let ((f (get-text-property (- (point) 2) 'face))) (if (listp f) f (list f)))))
    (should (equal (init-panel-tests--prop "# plain remark" 0 'display) "·"))
    (should (memq 'help-key-binding (init-panel-tests--faces "# plain remark" 21)))))

;;;; Normalizing

(defconst init-panel-tests--padded "\
;;; ------------------------------------------------------------------- Core
;;;; -                                                                   Settings
(setq ring-bell-function 'ignore)                                     ;> silence all error bells
(setq mouse-wheel-progressive-speed nil)                              ;> [fix]: cursor jumping with mouse-wheel scroll
                                                                      ;. constant scroll amount per notch
(use-package winner                                                   ;> undo/redo window layout changes
  :hook (after-init . winner-mode))                                   ;. after the frame is up
;; a prose line with a ;> inside stays as it is
(setq x \";> not a note\")
")

(ert-deftest init-panel-normalize ()
  (with-temp-buffer
    (insert init-panel-tests--padded)
    (emacs-lisp-mode)
    (init-panel--build-regexps)
    (should (= (init-panel-normalize-buffer) 7))
    (should (equal (buffer-string) "\
;;; Core
;;;; Settings
(setq ring-bell-function 'ignore) ;> silence all error bells
(setq mouse-wheel-progressive-speed nil) ;> [fix]: cursor jumping with mouse-wheel scroll
                                         ;. constant scroll amount per notch
(use-package winner ;> undo/redo window layout changes
  :hook (after-init . winner-mode)) ;. after the frame is up
;; a prose line with a ;> inside stays as it is
(setq x \";> not a note\")
"))
    ;; idempotent
    (should (= (init-panel-normalize-buffer) 0))))

(ert-deftest init-panel-imenu-sees-folded-entries ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-fold)
    (require 'imenu)
    (setq imenu--index-alist nil)
    (let ((idx (imenu--make-index-alist t)))
      (should (equal (mapcar #'car (cdr (assoc "Packages" idx))) '("winner" "nerd-icons")))
      (should (equal (mapcar #'car (cdr (assoc "Subsection" idx))) '("Settings" "Packages"))))))

;;;; Focus

(ert-deftest init-panel-focus-bounds ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel-tests--goto "(setq-default truncate-lines t)")
    (let ((b (init-panel--focus-bounds)))
      (should (string-prefix-p "(setq-default truncate-lines" (buffer-substring-no-properties (car b) (cdr b))))
      (should (string-match-p ";\\. continuation line\n\\'" (buffer-substring-no-properties (car b) (cdr b)))))
    (init-panel-tests--goto ";;; Files")
    (let ((b (init-panel--focus-bounds)))
      (should (= (car b) (line-beginning-position)))
      (should (= (cdr b) (point-max))))))

(ert-deftest init-panel-focus-indirect-edit ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (let ((init-panel-focus-frame nil) (base (current-buffer)))
      (init-panel-tests--goto "(setq ring-bell-function")
      (let* ((clone (init-panel-focus)))
        (should (buffer-live-p clone))
        (should (eq (buffer-base-buffer clone) base))
        (with-current-buffer clone
          (should init-panel-focus-mode)
          (should (= (point-min) (line-beginning-position)))
          (should (string-prefix-p "(setq ring-bell-function" (buffer-substring-no-properties (point-min) (point-max))))
          (goto-char (point-max))
          (insert ";; edited in focus\n")
          (init-panel-focus-close))
        (should-not (buffer-live-p clone))
        (should (eq (current-buffer) base))
        (should (string-match-p ";; edited in focus" (buffer-string)))))))

;;;; Teardown

(ert-deftest init-panel-disable-restores-buffer ()
  (init-panel-tests--with-buffer emacs-lisp-mode init-panel-tests--elisp
    (init-panel--jit-margin (point-min) (point-max))
    (init-panel-mode -1)
    (font-lock-ensure)
    (should (null (next-single-property-change (point-min) 'display)))
    (should (null (next-single-property-change (point-min) 'keymap)))
    (should (null (seq-filter (lambda (o) (or (overlay-get o 'init-panel-margin) (overlay-get o 'init-panel-summary)))
                              (overlays-in (point-min) (point-max)))))
    (should (null header-line-format))
    (should-not outline-minor-mode)))

(provide 'init-panel-tests)
;;; init-panel-tests.el ends here
