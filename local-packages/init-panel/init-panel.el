;;; init-panel.el --- Read your init as a panel: folding, icons, notes -*- lexical-binding: t -*-

;; Author: Mahatmus
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines, convenience, faces
;; URL: https://github.com/mahatmus-tech/emacs

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; A reading mode for configuration files written as a comment outline:
;;
;;   ;;; Section                 or   ;;; ------------------- Section
;;   ;;;; Subsection             or   ;;;; -                  Subsection
;;   (setq foo t) ;> why this is here
;;                ;.  continuation of the note
;;   (setq bar t) ;> [fix]: C-c w reopens `my-workspaces' after a theme change
;;
;; `init-panel-mode' turns that into a panel, in any Emacs 29+, with
;; no dependencies:
;;
;;   - folds the file to its sections with the built-in `outline-minor-mode'
;;     (`outline-default-state', `outline-minor-mode-cycle');
;;   - draws section rules with box-drawing lines, section names with
;;     level faces, and an icon per section picked from its name;
;;   - aligns every `;>' / `;.' note at a drawn column (no padding to type,
;;     no alignment noise in diffs) — or, optionally, in the right margin;
;;   - decorates notes and plain comments: keys (`C-c w', `M-x foo') in the
;;     key face, `[tag]' prefixes as badges, symbol names as links to their
;;     documentation; `;;' and `;' get quiet glyphs of their own;
;;   - shows an icon for the kind of each top-level form (package, setting,
;;     hook, binding…) in the left margin, plus a "you are here" marker on
;;     the heading of the section and subsection point is in;
;;   - summarizes a folded `use-package' with the keywords it contains;
;;   - keeps a `Section › Subsection' breadcrumb in the header line and
;;     feeds `imenu' / `which-function-mode';
;;   - silences on-the-fly checker text at end of line while reading;
;;   - `init-panel-focus' edits one block in an indirect buffer over the
;;     panel (child frame, or a window in a terminal): no copy, no sync.
;;
;; Every visual is a `defcustom' and degrades to plain text when the
;; display can't show a glyph (`char-displayable-p').  Icons default to
;; Nerd Font codepoints; without such a font you get `◆', `◇' and ASCII.
;;
;; The mode keeps its keymap empty.  Suggested bindings, in your init:
;;
;;   (define-key init-panel-mode-map (kbd "C-c C-t") #'init-panel-show-headings)
;;   (define-key init-panel-mode-map (kbd "C-c C-s") #'init-panel-fold-subsections)
;;   (define-key init-panel-mode-map (kbd "C-c C-y") #'init-panel-fold)
;;   (define-key init-panel-mode-map (kbd "C-c C-o") #'init-panel-focus)

;;; Code:

(require 'outline)
(require 'eldoc)
(require 'subr-x)
(require 'seq)
(require 'imenu)

(defgroup init-panel nil
  "Read comment-outlined files as a panel: folding, icons, notes."
  :group 'outlines
  :prefix "init-panel-")

;;;; Options: notes

(defcustom init-panel-style 'column
  "Where notes are shown.
`column' keeps them in the text, aligned to `init-panel-column' (a
comment column that is drawn, not typed).  `margin' moves them to the
window's right margin — on a wide window that puts them far from the
code, which is why `column' is the default."
  :type '(choice (const column) (const margin)))

(defcustom init-panel-column 70
  "Column notes are aligned to in `column' style."
  :type 'integer)

(defcustom init-panel-column-auto nil
  "In `column' style, push the column right past the widest visible code line.
Off by default: a fixed column reads as a steady second column; auto
avoids the rare overlap at the cost of the column moving while scrolling."
  :type 'boolean)

(defcustom init-panel-margin-width 'auto
  "Right margin width in `margin' style.
`auto' derives it from the window width and the widest visible code line
\(bounded by `init-panel-margin-min' and `init-panel-margin-max');
an integer is a fixed width; a float between 0 and 1 is a fraction of the
window's total width."
  :type '(choice (const auto) integer float))

(defcustom init-panel-margin-min 24
  "Below this width (in `auto' mode) the margin collapses to zero."
  :type 'integer)

(defcustom init-panel-margin-max 60
  "Widest margin `auto' mode will use."
  :type 'integer)

(defcustom init-panel-min-code-width 60
  "Columns always reserved for code before the margin is sized (`auto')."
  :type 'integer)

(defcustom init-panel-eldoc nil
  "When to echo the note of the form at point through eldoc.
nil never (notes are already visible inline in `column' style), `always'
regardless of style — useful when long lines push a note off-screen."
  :type '(choice (const nil) (const always)))

(defcustom init-panel-raw-at-point nil
  "When non-nil, the line under point is shown exactly as typed.
Off by default: glyphs and the drawn column don't get in the way of
editing, and markers flickering back to `;>' on every line change reads
worse than leaving them rendered."
  :type 'boolean)

;;;; Options: headings and rules

(defcustom init-panel-heading-column 70
  "Visual column where a heading's name starts when the rule is drawn.
Only used for headings written without typed dashes (`;;; Name')."
  :type 'integer)

(defcustom init-panel-rule-chars '((1 . "─") (2 . "╌"))
  "Character used to draw the rule of each heading level.
Typed dashes are displayed with it; missing dashes are drawn with it.
Falls back to the typed text when the display can't show the character."
  :type '(alist :key-type integer :value-type string))

(defcustom init-panel-glyph-alist
  '((";;;" . "◆") (";;;;" . "◇") (";>" . "→") (";." . "↳") (";;" . "▎") (";" . "·"))
  "Marker → glyph shown instead of it, when the display can render it.
Heading markers are further replaced by `init-panel-section-icons'.
`;;' is a prose comment on its own line, `;' an inline remark after code
\(see `init-panel-prose-comments')."
  :type '(alist :key-type string :value-type string))

(defcustom init-panel-prose-comments t
  "Render plain comments too: glyph for `;;' / `;', keys, badges and links.
Prose comments keep their place and face; only the marker is replaced and
the text gets the same decorations as notes."
  :type 'boolean)

(defcustom init-panel-section-icons
  '(("tip\\|help\\|note\\|readme" . "")                        ; lightbulb
    ("bootstrap\\|boot\\|startup\\|init" . "")                 ; rocket
    ("core\\|general\\|basic\\|default" . "")                  ; microchip
    ("stabil\\|fix\\|bug\\|compat" . "")                       ; shield
    ("visual\\|theme\\|ui\\|look\\|appearance\\|face" . "")    ; paint brush
    ("edit" . "")                                              ; pencil
    ("complet\\|minibuffer" . "")                              ; magic wand
    ("file\\|dired" . "")                                      ; folder
    ("project\\|workspace" . "")                               ; briefcase
    ("terminal\\|shell" . "")                                  ; terminal
    ("version control\\|git\\|magit\\|vc" . "")                ; git
    ("infra\\|docker\\|container\\|cloud" . "")                ; docker
    ("language\\|lang\\|lsp\\|clojure\\|lisp\\|markup" . "")   ; code
    ("org" . "")                                               ; org-mode
    ("key\\|bind" . "")                                        ; keyboard
    ("package\\|straight\\|elpa\\|melpa" . "")                 ; cubes
    ("perf\\|gc\\|speed" . "")                                 ; bolt
    ("navigat\\|window\\|tab" . "")                            ; sitemap
    ("setting\\|config\\|option" . "")                         ; cog
    ("warning\\|log" . "")                                     ; eye
    ("load" . "")                                              ; download
    ("web\\|html\\|css\\|js" . "")                             ; cube
    ("usab" . ""))                                             ; sliders
  "Heading name regexp (case-insensitive) → icon shown as its marker.
First match wins.  Defaults are Nerd Font codepoints (written as \\u escapes
so any editor preserves them); on a display that can't show them the
`;;;' / `;;;;' glyphs from `init-panel-glyph-alist' are used instead."
  :type '(alist :key-type regexp :value-type string))

(defcustom init-panel-kind-margin t
  "Show an icon for the kind of each top-level form in the left margin."
  :type 'boolean)

(defcustom init-panel-kind-icons
  '(("use-package\\|package-install\\|straight-use-package" . "")           ; package
    ("setq\\|setopt\\|setq-default\\|setq-local\\|customize-set-variable" . "") ; cog
    ("add-hook\\|remove-hook" . "\U000f06e2")                                     ; hook
    ("keymap-\\|global-set-key\\|define-key\\|bind-key\\|key-chord" . "")   ; keyboard
    ("advice-add\\|advice-remove\\|define-advice" . "")                     ; medkit
    ("load\\|require\\|autoload" . "")                                      ; download
    ("defun\\|defmacro\\|cl-defun\\|defalias\\|define-minor-mode" . "")     ; method
    ("defvar\\|defcustom\\|defconst\\|defface\\|defvar-local" . "")         ; variable
    ("with-eval-after-load\\|eval-after-load\\|run-with" . "")              ; clock
    ("push\\|add-to-list\\|dolist\\|dotimes\\|mapc" . "")                   ; list
    ("let\\|when\\|unless\\|if\\|progn\\|condition-case" . "")              ; code
    ("[a-z-]+-mode\\'" . ""))                                               ; sliders
  "Regexp on the head symbol of a top-level form → icon for the left margin.
First match wins; forms with no match get no icon.  Defaults are Nerd Font
codepoints written as \\u escapes."
  :type '(alist :key-type regexp :value-type string))

(defcustom init-panel-section-guide 'marker
  "How the left margin shows where point is.
`marker' puts `init-panel-marker-char' on the heading lines of the section
and subsection that contain point (a \"you are here\" pointer); `bar' draws
`init-panel-guide-char' on every line of the current section; nil shows
nothing (the header line still names the section)."
  :type '(choice (const marker) (const bar) (const nil)))

(defcustom init-panel-marker-char "▸"
  "Character placed on the current section's heading lines in `marker' style."
  :type 'string)

(defcustom init-panel-guide-char "│"
  "Character of the section bar in `bar' style."
  :type 'string)

;;;; Options: decorations and orientation

(defcustom init-panel-highlight-keys t
  "Show key descriptions inside notes (`C-c w', `M-x foo') in the key face."
  :type 'boolean)

(defcustom init-panel-tag-faces
  '(("fix" . init-panel-tag-fix)
    ("bug" . init-panel-tag-fix)
    ("hack" . init-panel-tag-hack)
    ("perf" . init-panel-tag-perf)
    ("todo" . init-panel-tag-todo)
    ("wip" . init-panel-tag-todo)
    ("emacs[0-9]*" . init-panel-tag-version)
    ("deprecated" . init-panel-tag-hack))
  "Regexp on a `[tag]' word at the start of a note → face of the badge.
Tags with no match use `init-panel-tag'."
  :type '(alist :key-type regexp :value-type face))

(defcustom init-panel-link-symbols t
  "Turn symbol names inside notes into links to their documentation.
Backquoted names (`foo') always link; bare names only when they contain
`-' or `/' and name a bound function, variable or face."
  :type 'boolean)

(defcustom init-panel-package-index t
  "List `use-package' names under \"Packages\" in imenu."
  :type 'boolean)

(defcustom init-panel-highlight-targets t
  "Show the first argument of every top-level form in `init-panel-target'.
The variable of a `setq', the hook of an `add-hook', the key of a binding…
so what each line is about stands out from the form and its value."
  :type 'boolean)

(defcustom init-panel-fold-summary t
  "Show which keywords a folded `use-package' form contains."
  :type 'boolean)

(defcustom init-panel-header-line 'point
  "Show a `Section › Subsection' breadcrumb in the header line.
`point' names the section point is in (matches the margin marker);
`window-start' names the section of the first visible line; nil hides it."
  :type '(choice (const point) (const window-start) (const nil)))

(defcustom init-panel-quiet-diagnostics t
  "Hide on-the-fly checker text at end of line while the mode is on.
Fringe indicators stay.  Currently applies to Flymake."
  :type 'boolean)

(defcustom init-panel-ellipsis " ⬎"
  "Text shown at the end of a folded heading."
  :type 'string)

(defcustom init-panel-use-buttons nil
  "Value given to `outline-minor-mode-use-buttons' while the mode is on.
`in-margins' competes with the kind icons for the left margin."
  :type '(choice (const nil) (const t) (const insert) (const in-margins)))

;;;; Faces

(defface init-panel-section
  '((t :inherit outline-1 :weight bold))
  "Face of a level-1 heading name.")

(defface init-panel-subsection
  '((t :inherit outline-2))
  "Face of a level-2 heading name.")

(defface init-panel-rule
  '((t :inherit shadow))
  "Face of a heading's rule (typed dashes or drawn line).")

(defface init-panel-note
  '((t :inherit font-lock-comment-face))
  "Face of a note's text.")

(defface init-panel-marker
  '((t :inherit font-lock-function-name-face :weight bold))
  "Face of the `;>' note marker (or its glyph).
An accent, so the marker stands apart from the gray note text.")

(defface init-panel-marker-continuation
  '((t :inherit font-lock-type-face))
  "Face of the `;.' continuation marker (or its glyph).")

(defface init-panel-marker-prose
  '((t :inherit font-lock-comment-delimiter-face :weight bold))
  "Face of the `;;' / `;' prose comment markers (or their glyphs).
Quieter than the note markers: prose is context, notes are the point.")

(defface init-panel-tag
  '((t :inherit shadow :box (:line-width (-1 . -1)) :weight bold))
  "Face of a `[tag]' badge with no specific face.")

(defface init-panel-tag-fix
  '((t :inherit (warning init-panel-tag)))
  "Badge face for `[fix]' / `[bug]'.")

(defface init-panel-tag-hack
  '((t :inherit (error init-panel-tag)))
  "Badge face for `[hack]' / `[deprecated]'.")

(defface init-panel-tag-perf
  '((t :inherit (success init-panel-tag)))
  "Badge face for `[perf]'.")

(defface init-panel-tag-todo
  '((t :inherit (font-lock-warning-face init-panel-tag)))
  "Badge face for `[todo]' / `[wip]'.")

(defface init-panel-tag-version
  '((t :inherit (font-lock-constant-face init-panel-tag)))
  "Badge face for `[emacsNN]'.")

(defface init-panel-link
  '((t :inherit font-lock-constant-face :underline t))
  "Face of a symbol link inside a note.")

(defface init-panel-target
  '((t :inherit font-lock-constant-face :weight bold))
  "Face of a top-level form's first argument, the thing the line is about.
The package in `(use-package NAME', the variable in `(setq VAR', the hook
in `(add-hook HOOK', the key in `(keymap-global-set KEY'.")

(defface init-panel-package
  '((t :inherit init-panel-target))
  "Face of the name in `(use-package NAME' (a kind of target).")

(defface init-panel-kind
  '((t :inherit font-lock-comment-delimiter-face))
  "Face of the form-kind icons in the left margin.")

(defface init-panel-guide
  '((t :inherit outline-1))
  "Face of the section guide bar in the left margin.")

(defface init-panel-summary
  '((t :inherit shadow :slant italic))
  "Face of a folded form's keyword summary.")

(defface init-panel-header
  '((t :inherit header-line :weight bold))
  "Face of the breadcrumb in the header line.")

;;;; Buffer state

(defvar-local init-panel--heading-re nil
  "Regexp for heading lines.
Groups: 1 prefix, 2 the space after it, 3 dashes, 4 gap, 5 name.
A name can't end in `-', which keeps the `;;; file.el --- … -*-' header out.")

(defvar-local init-panel--note-re nil
  "Regexp for note lines: 1 code, 2 gap, 3 marker and text, 4 marker, 5 text.")

(defvar-local init-panel--glyphs nil
  "Marker → glyph alist filtered by `char-displayable-p' for this buffer.")

(defvar-local init-panel--point-line nil
  "Beginning of the line that holds point; that line is rendered as typed.")

(defvar-local init-panel--inline nil
  "Non-nil while `margin' style has no room and notes fall back to `column'.")

(defvar-local init-panel--column nil
  "Effective note column for this buffer (see `init-panel-column-auto').")

(defvar-local init-panel--section-bounds nil
  "(BEG . END) markers of the region between the headings around point.
For `bar' style this is the level-1 section; for `marker' style the span
between the previous and the next heading of any level.")

(defvar-local init-panel--marked-headings nil
  "Line-beginning positions of the heading lines to mark in `marker' style.")

(defvar-local init-panel--display-table nil)
(defvar-local init-panel--saved-header-line nil)
(defvar-local init-panel--left-margin-set nil)

(defvar init-panel--scroll-timer nil)

(defvar init-panel-mode)

(defcustom init-panel-margin-cells 4
  "Left margin width in default-face columns: marker, a space, and the icon.
Nerd Font icons are double-width in non-Mono variants, hence 4."
  :type 'integer)

(defvar init-panel-link-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'init-panel-describe-at-point)
    (define-key map [mouse-1] #'init-panel-describe-at-point)
    (define-key map [follow-link] 'mouse-face)
    map)
  "Keymap active on symbol links inside notes.")

;;;; Helpers

(defun init-panel--comment ()
  "The comment starter of this buffer, trimmed (\";\" for Lisp)."
  (let ((c (string-trim (or comment-start ";"))))
    (if (string-empty-p c) ";" c)))

(defun init-panel--build-regexps ()
  "Set the heading and note regexps from the buffer's comment syntax."
  (let ((c (regexp-quote (init-panel--comment))))
    (setq init-panel--heading-re
          (concat "^\\(" c c c c "?\\)\\( \\)\\(-*\\)\\([ \t]*\\)\\(\\S-\\(?:.*[^-]\\)?\\)$"))
    (setq init-panel--note-re
          (concat "^\\(.*?\\)\\([ \t]*\\)\\(\\(" c "[>.]\\)\\(.*\\)\\)$"))))

(defun init-panel--displayable-p (string)
  "Non-nil when every character of STRING can be shown on this display."
  (seq-every-p #'char-displayable-p string))

(defun init-panel--marker-face (marker)
  "Face for MARKER: note, continuation or prose."
  (let ((k (init-panel--marker-key marker)))
    (cond ((equal k ";>") 'init-panel-marker)
          ((equal k ";.") 'init-panel-marker-continuation)
          (t 'init-panel-marker-prose))))

(defun init-panel--marker-key (marker)
  "Canonical key of MARKER in `init-panel-glyph-alist' (normalized to `;')."
  (let ((c (init-panel--comment)))
    (if (equal c ";") marker (string-replace c ";" marker))))

(defun init-panel--build-glyphs ()
  "Keep only the glyphs the current display can show."
  (setq init-panel--glyphs
        (seq-filter (lambda (pair) (init-panel--displayable-p (cdr pair)))
                    init-panel-glyph-alist)))

(defun init-panel--glyph (marker)
  "Glyph for MARKER, or MARKER itself when it can't be displayed."
  (or (cdr (assoc (init-panel--marker-key marker) init-panel--glyphs)) marker))

(defun init-panel--rule-char (level)
  "Rule character for LEVEL, or nil when it can't be displayed."
  (let ((ch (cdr (assq level init-panel-rule-chars))))
    (and ch (init-panel--displayable-p ch) ch)))

(defun init-panel--icon-for (name table)
  "First displayable icon in TABLE whose regexp matches NAME (case-insensitive)."
  (let ((case-fold-search t))
    (seq-some (lambda (pair)
                (and (string-match-p (car pair) name)
                     (init-panel--displayable-p (cdr pair))
                     (cdr pair)))
              table)))

(defun init-panel--current-line-p (pos)
  "Non-nil when POS is on the line that holds point and that line must stay raw."
  (and init-panel-raw-at-point
       init-panel--point-line
       (save-excursion (goto-char pos)
                       (= (line-beginning-position) init-panel--point-line))))

(defun init-panel--heading-level ()
  "Level (1 or 2) of the heading in the current match data."
  (if (= (- (match-end 1) (match-beginning 1)) (length (init-panel--comment) )) 1
    (if (= (- (match-end 1) (match-beginning 1)) (* 3 (length (init-panel--comment)))) 1 2)))

;;;; Font-lock: headings

(defun init-panel--search-heading (limit)
  "Font-lock matcher for heading lines up to LIMIT."
  (re-search-forward init-panel--heading-re limit t))

(defun init-panel--heading-face ()
  "Name face for the heading in the current match data."
  (if (= (init-panel--heading-level) 1) 'init-panel-section 'init-panel-subsection))

(defun init-panel--heading-marker-props ()
  "Face and icon/glyph for a heading's comment prefix (group 1)."
  (let* ((marker (match-string-no-properties 1))
         (face (init-panel--heading-face))
         (icon (or (init-panel--icon-for (match-string-no-properties 5) init-panel-section-icons)
                   (init-panel--glyph marker))))
    (if (or (init-panel--current-line-p (match-beginning 1)) (equal icon marker))
        face
      (list 'face face 'display icon))))

(defun init-panel--heading-space-props ()
  "Draw a rule on the space after the prefix (group 2) when no dashes were typed."
  (let ((rule (init-panel--rule-char (init-panel--heading-level))))
    (if (or (> (match-end 3) (match-beginning 3))
            (not rule)
            (init-panel--current-line-p (match-beginning 2)))
        'init-panel-rule
      (list 'face 'init-panel-rule
            'display (concat " " (make-string (max 1 (- init-panel-heading-column 3)) (aref rule 0)) " ")))))

(defun init-panel--heading-dashes-props ()
  "Display typed dashes (group 3) with the level's rule character."
  (let ((rule (init-panel--rule-char (init-panel--heading-level)))
        (len (- (match-end 3) (match-beginning 3))))
    (if (or (zerop len) (not rule) (init-panel--current-line-p (match-beginning 3)))
        'init-panel-rule
      (list 'face 'init-panel-rule 'display (make-string len (aref rule 0))))))

(defun init-panel--heading-gap-props ()
  "Extend a level-2 typed rule (`;;;; -   Name') across the gap (group 4)."
  (let ((rule (init-panel--rule-char 2))
        (len (- (match-end 4) (match-beginning 4))))
    (if (or (< len 2) (not rule)
            (/= (init-panel--heading-level) 2)
            (zerop (- (match-end 3) (match-beginning 3)))
            (init-panel--current-line-p (match-beginning 4)))
        'init-panel-rule
      (list 'face 'init-panel-rule 'display (concat (make-string (1- len) (aref rule 0)) " ")))))

;;;; Font-lock: notes

(defun init-panel--search-note (limit)
  "Font-lock matcher for note lines up to LIMIT.
Skips markers inside strings or other comments."
  (let (found)
    (while (and (not found) (re-search-forward init-panel--note-re limit t))
      (let ((state (save-excursion (syntax-ppss (match-beginning 3)))))
        (when (and (not (nth 3 state)) (not (nth 4 state)))
          (setq found t))))
    found))

(defun init-panel--in-margin-p ()
  "Non-nil when notes currently go to the margin in this buffer."
  (and (eq init-panel-style 'margin) (not init-panel--inline)))

(defconst init-panel--key-re
  (concat
   "\\("
   ;; M-x command (before the chord branch, which would stop at M-x)
   "M-x [[:alnum:]_/:-]+"
   ;; a chord: modifiers + one key (a char, a word, or <named>), then up to
   ;; four more keys that are chords or single characters (C-x o o o)
   "\\|\\(?:[CMSsHA]-\\)+\\(?:<[[:alnum:]-]+>\\|[[:alnum:]_-]+\\|[^][ \t()`'\"]\\)"
   "\\(?: \\(?:\\(?:[CMSsHA]-\\)+\\(?:<[[:alnum:]-]+>\\|[[:alnum:]_-]+\\|[^][ \t()`'\"]\\)"
   "\\|TAB\\|RET\\|SPC\\|DEL\\|ESC\\|<[[:alnum:]-]+>\\|[^][ \t,;()`'\".:]\\)\\)\\{0,4\\}"
   ;; named keys
   "\\|<\\(?:f[0-9]+\\|return\\|tab\\|backtab\\|escape\\|delete\\|backspace\\|insert\\|home\\|end\\|prior\\|next"
   "\\|up\\|down\\|left\\|right\\|menu\\|mouse-[0-9]\\|wheel-\\(?:up\\|down\\)\\)>"
   "\\|TAB\\|RET\\|SPC\\|DEL\\|ESC"
   "\\)")
  "Regexp for key descriptions inside a note; group 1 is the key text.
Matches are only kept when `init-panel--key-isolated-p' says the text stands
alone: a chord must start at a word edge (so `has-agenda-view' is not a
Super chord), a trailing word is not swallowed as a key, and a key name
inside a longer word (RET inside SECRET) does not count.")

(defun init-panel--key-isolated-p (beg end)
  "Non-nil when the key text between BEG and END is a whole word."
  (and (or (= beg (point-min))
           (not (string-match-p "[[:alnum:]_/<>-]" (string (char-before beg)))))
       (or (= end (point-max))
           (not (string-match-p "[[:alnum:]_/-]" (string (char-after end)))))))

(defconst init-panel--tag-re "[ \t]*\\(\\[\\([a-zA-Z][a-zA-Z0-9-]*\\)\\]:?\\)"
  "Regexp for a `[tag]:' prefix at the start of a note.")

(defconst init-panel--backquote-re "`\\([^`' \t]+\\)'"
  "Regexp for a backquoted symbol inside a note.")

(defconst init-panel--bare-symbol-re "\\_<\\([a-zA-Z][a-zA-Z0-9]*[-/][a-zA-Z0-9/-]*[a-zA-Z0-9*?!]\\)\\_>"
  "Regexp for a bare identifier-looking token inside a note.")

(defun init-panel--tag-face (tag)
  "Badge face for TAG."
  (let ((case-fold-search t))
    (or (seq-some (lambda (pair) (and (string-match-p (concat "\\`" (car pair) "\\'") tag) (cdr pair)))
                  init-panel-tag-faces)
        'init-panel-tag)))

(defun init-panel--link-symbol (token)
  "The symbol TOKEN names, when it is documented, else nil."
  (let ((sym (intern-soft token)))
    (and sym (or (fboundp sym) (boundp sym) (facep sym)) sym)))

(defun init-panel--link-props (sym)
  "Text properties that make a note token a link to SYM."
  (list 'mouse-face 'highlight
        'keymap init-panel-link-map
        'help-echo (format "RET, mouse-1: describe %s" sym)
        'init-panel-symbol sym))

(defun init-panel--decorate (beg end)
  "Add key, tag and link decorations to the note text between BEG and END.
Only adds properties; the caller has already applied the base face."
  (save-excursion
    (save-match-data
      (goto-char beg)
      (when (and (looking-at init-panel--tag-re) (< (match-end 1) end))
        (add-face-text-property (match-beginning 1) (match-end 1)
                                (init-panel--tag-face (match-string-no-properties 2))))
      (when init-panel-highlight-keys
        (goto-char beg)
        (while (re-search-forward init-panel--key-re end t)
          (let ((kb (match-beginning 1)) (ke (match-end 1)))
            ;; trim trailing single-char "keys" that ran into a word (C-c C-r in);
            ;; a lone capital (C-c W) stays a key — the rare "C-c C show" reads
            ;; wrong, but guessing would drop real bindings
            (while (and (> ke (+ kb 3))
                        (not (init-panel--key-isolated-p kb ke))
                        (eq (char-after (- ke 2)) ?\s))
              (setq ke (- ke 2)))
            (when (init-panel--key-isolated-p kb ke)
              (add-face-text-property kb ke (if (facep 'help-key-binding) 'help-key-binding 'bold))
              (goto-char ke)))))
      (when init-panel-link-symbols
        (goto-char beg)
        (while (re-search-forward init-panel--backquote-re end t)
          (when-let* ((sym (or (init-panel--link-symbol (match-string-no-properties 1))
                               (intern (match-string-no-properties 1)))))
            (add-face-text-property (match-beginning 1) (match-end 1) 'init-panel-link)
            (add-text-properties (match-beginning 1) (match-end 1) (init-panel--link-props sym))))
        (goto-char beg)
        (while (re-search-forward init-panel--bare-symbol-re end t)
          (unless (get-text-property (match-beginning 1) 'init-panel-symbol)
            (when-let* ((sym (init-panel--link-symbol (match-string-no-properties 1))))
              (add-face-text-property (match-beginning 1) (match-end 1) 'init-panel-link)
              (add-text-properties (match-beginning 1) (match-end 1) (init-panel--link-props sym)))))))))

(defun init-panel--note-string (text)
  "Render TEXT (marker and note) as the decorated string shown in the margin.
Callers inside font-lock must wrap this in `save-match-data'."
  (let* ((marker (substring text 0 2))
         (body (string-trim (substring text 2)))
         (glyph (propertize (init-panel--glyph marker) 'face (init-panel--marker-face marker))))
    (with-temp-buffer
      (insert (propertize body 'face 'init-panel-note))
      (init-panel--decorate (point-min) (point-max))
      (concat glyph " " (buffer-string)))))

(defun init-panel--note-gap-props ()
  "Stretch the whitespace before a note (group 2) up to the note column."
  (let ((beg (match-beginning 2)) (end (match-end 2)))
    (if (or (= beg end)
            (init-panel--in-margin-p)
            (init-panel--current-line-p beg)
            (>= (save-excursion (goto-char beg) (current-column))
                (or init-panel--column init-panel-column)))
        nil
      (list 'face nil                                                ; (N . width): N times the face's font width, so
            'display `(space :align-to (,(or init-panel--column init-panel-column) . width))))))

(defun init-panel--note-props ()
  "Group 3 (marker and text): the margin display in `margin' style, else a face."
  (if (or (not (init-panel--in-margin-p))
          (init-panel--current-line-p (match-beginning 3)))
      'init-panel-note
    (let ((text (match-string-no-properties 3)))
      (list 'face 'init-panel-note
            'display `((margin right-margin)
                       ,(save-match-data (init-panel--note-string text)))))))

(defun init-panel--note-marker-props ()
  "Group 4 (the marker): its glyph in `column' style."
  (let* ((marker (match-string-no-properties 4))
         (face (init-panel--marker-face marker)))
    (if (or (init-panel--in-margin-p)
            (init-panel--current-line-p (match-beginning 4))
            (equal (init-panel--glyph marker) marker))
        face
      (list 'face face 'display (init-panel--glyph marker)))))

(defun init-panel--note-decorate-props ()
  "Final highlighter of a note: decorate the text (group 5) as a side effect."
  (unless (or (init-panel--in-margin-p)
              (init-panel--current-line-p (match-beginning 5)))
    (init-panel--decorate (match-beginning 5) (match-end 5)))
  nil)

(defun init-panel--search-prose (limit)
  "Font-lock matcher for `;;' / `;' comments up to LIMIT.
Group 1 is the marker (one or two comment chars), group 2 the text.
Headings (3+ chars), notes and autoload cookies are left to their own rules."
  (when init-panel-prose-comments
    (let ((c (regexp-quote (init-panel--comment))) found)
      (while (and (not found)
                  (re-search-forward (concat "\\(" c "+\\)\\(?:[ \t]+\\|$\\)\\(.*\\)$") limit t))
        (let* ((beg (match-beginning 1))
               (len (- (match-end 1) beg))
               (state (save-excursion (syntax-ppss beg))))              ; syntax-ppss moves point: unguarded, a
          (when (and (<= len 2)                                            ; rejected match is re-found forever
                     (not (nth 3 state)) (not (nth 4 state))
                     (not (string-match-p "\\`[>.]" (match-string-no-properties 2))))
            (setq found t))))
      found)))

(defun init-panel--prose-marker-props ()
  "Glyph for a prose comment's marker (group 1)."
  (let* ((marker (match-string-no-properties 1))
         (face (init-panel--marker-face marker)))
    (if (or (init-panel--current-line-p (match-beginning 1))
            (equal (init-panel--glyph marker) marker))
        face
      (list 'face face 'display (init-panel--glyph marker)))))

(defun init-panel--prose-decorate-props ()
  "Decorate a prose comment's text (group 2) as a side effect."
  (unless (init-panel--current-line-p (match-beginning 2))
    (init-panel--decorate (match-beginning 2) (match-end 2)))
  nil)

(defconst init-panel--target-re
  "^([^ \t\n()]+[ \t]+\\(?:#?'\\)?\\(\"[^\"\n]*\"\\|[^ \t\n()\"']+\\)"
  "Regexp for a top-level form's first argument (group 1): a symbol or string.
A quote or #' prefix is skipped; a list argument does not match.")

(defun init-panel--search-target (limit)
  "Font-lock matcher for the first argument of top-level forms up to LIMIT."
  (and init-panel-highlight-targets
       (re-search-forward init-panel--target-re limit t)))

(defvar init-panel--keywords
  '((init-panel--search-heading
     (1 (init-panel--heading-marker-props) t)
     (2 (init-panel--heading-space-props) t)
     (3 (init-panel--heading-dashes-props) t)
     (4 (init-panel--heading-gap-props) t)
     (5 (init-panel--heading-face) t))
    (init-panel--search-note
     (2 (init-panel--note-gap-props) t)
     (3 (init-panel--note-props) t)
     (4 (init-panel--note-marker-props) t)
     (5 'init-panel-note t)
     (5 (init-panel--note-decorate-props) append))
    (init-panel--search-target
     (1 'init-panel-target prepend))
    (init-panel--search-prose
     (1 (init-panel--prose-marker-props) t)
     (2 (init-panel--prose-decorate-props) append)))
  "Font-lock keywords added by `init-panel-mode'.")

;;;; Links

(defun init-panel-describe-at-point (&optional event)
  "Describe the symbol linked at point (or at EVENT's position)."
  (interactive (list last-nonmenu-event))
  (let* ((pos (if (and event (mouse-event-p event)) (posn-point (event-start event)) (point)))
         (sym (get-text-property pos 'init-panel-symbol)))
    (if sym (describe-symbol sym)
      (user-error "No symbol link here"))))

;;;; Point tracking (line under point is rendered as typed)

(defun init-panel--flush-line (pos)
  "Ask font-lock to redo the line at POS."
  (when (and pos (<= (point-min) pos (point-max)))
    (save-excursion
      (goto-char pos)
      (font-lock-flush (line-beginning-position) (line-end-position)))))

(defun init-panel--track-point ()
  "Refontify the lines point left and entered."
  (let ((line (line-beginning-position)))
    (unless (eql line init-panel--point-line)
      (let ((old init-panel--point-line))
        (setq init-panel--point-line line)
        (init-panel--flush-line old)
        (init-panel--flush-line line)))))

;;;; Left margin: kind icons and section guide (jit-lock)

(defun init-panel--kind-icon-at-bol ()
  "Icon for the top-level form starting at point (bol), or nil."
  (and init-panel-kind-margin
       (looking-at "(\\([^ \t\n()]+\\)")
       (init-panel--icon-for (match-string-no-properties 1) init-panel-kind-icons)))

(defun init-panel--in-section-p (pos)
  "Non-nil when POS is inside the cached section bounds."
  (let ((b init-panel--section-bounds))
    (and b (<= (car b) pos) (< pos (cdr b)))))

(defun init-panel--guide-cell (bol)
  "The guide cell for the line starting at BOL, or nil."
  (pcase init-panel-section-guide
    ('bar (and (init-panel--in-section-p bol)
               (init-panel--displayable-p init-panel-guide-char)
               (propertize init-panel-guide-char 'face 'init-panel-guide)))
    ('marker (and (memq bol init-panel--marked-headings)
                  (init-panel--displayable-p init-panel-marker-char)
                  (propertize init-panel-marker-char 'face 'init-panel-guide)))))

(defun init-panel--margin-string (pos)
  "Margin string for the line at POS, or nil when it would be blank."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (let* ((guide (init-panel--guide-cell (point)))
           (icon (and (not (looking-at-p (concat "[ \t]*" (regexp-quote (init-panel--comment)))))
                      (init-panel--kind-icon-at-bol))))
      (when (or guide icon)
        (concat (or guide " ") " " (if icon (propertize icon 'face 'init-panel-kind) " "))))))

(defun init-panel--jit-margin (beg end)
  "Refresh the overlays of the left margin between BEG and END (jit-lock)."
  (when (or init-panel-kind-margin init-panel-section-guide)
    (save-excursion
      (goto-char beg)
      (setq beg (line-beginning-position))
      (goto-char end)
      (setq end (line-end-position))
      (remove-overlays beg (min (1+ end) (point-max)) 'init-panel-margin t)
      (goto-char beg)
      (while (< (point) end)
        (when-let* ((str (init-panel--margin-string (point))))
          (let ((ov (make-overlay (point) (point))))
            (overlay-put ov 'init-panel-margin t)
            (overlay-put ov 'before-string
                         (propertize " " 'display `((margin left-margin) ,str)))))
        (forward-line 1)))
    `(jit-lock-bounds ,beg . ,end)))

(defun init-panel--section-bounds-at (pos)
  "(BEG . END) markers of the level-1 section containing POS, or nil."
  (save-excursion
    (goto-char pos)
    (end-of-line)
    (let ((c (regexp-quote (init-panel--comment))))
      (when (re-search-backward (concat "^" c "\\{3\\} ") nil t)
        (when (looking-at init-panel--heading-re)
          (let ((beg (point)))
            (forward-line 1)
            (cons (copy-marker beg)
                  (copy-marker (if (re-search-forward (concat "^" c "\\{3\\} ") nil t)
                                   (line-beginning-position)
                                 (point-max))))))))))

(defun init-panel--item-bounds-at (pos)
  "Span between the headings around POS, and the heading lines to mark.
Returns ((BEG . END) . MARKED): BEG is the previous heading of any level,
END the next one; MARKED lists that heading's line start and, for a
subsection, its section's too."
  (save-excursion
    (goto-char pos)
    (end-of-line)
    (let ((c (regexp-quote (init-panel--comment))) beg end marked)
      (when (re-search-backward (concat "^" c "\\{3,4\\} ") nil t)
        (when (looking-at init-panel--heading-re)
          (setq beg (point))
          (push beg marked)
          (when (= (init-panel--heading-level) 2)
            (save-excursion
              (when (and (re-search-backward (concat "^" c "\\{3\\} ") nil t)
                         (looking-at init-panel--heading-re))
                (push (point) marked))))
          (forward-line 1)
          (setq end (if (re-search-forward (concat "^" c "\\{3,4\\} ") nil t)
                        (line-beginning-position)
                      (point-max)))
          (cons (cons (copy-marker beg) (copy-marker end)) marked))))))

(defun init-panel--refresh-visible-margins ()
  "Recompute margin overlays for every window showing this buffer."
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (init-panel--jit-margin (window-start w) (window-end w t))))

(defun init-panel--locate-point ()
  "Recompute the cached bounds (and marked headings) for point."
  (pcase init-panel-section-guide
    ('bar (setq init-panel--section-bounds (init-panel--section-bounds-at (point))
                init-panel--marked-headings nil))
    ('marker (let ((r (init-panel--item-bounds-at (point))))
               (setq init-panel--section-bounds (car r)
                     init-panel--marked-headings (cdr r))))
    (_ (setq init-panel--section-bounds nil init-panel--marked-headings nil))))

(defun init-panel--guide-update ()
  "Move the section guide/marker when point left the cached region."
  (when (and init-panel-section-guide
             (not (init-panel--in-section-p (point))))
    (init-panel--locate-point)
    (init-panel--refresh-visible-margins)))

;;;; Folded summaries

(defun init-panel--form-keywords (beg end)
  "The form-level `:keyword's between BEG and END, in order, without duplicates.
Only keywords at the shallowest indentation count, so `:map' inside a
`:bind' block is not reported."
  (save-excursion
    (goto-char beg)
    (let (found)
      (while (re-search-forward "^\\([ \t]*\\)\\(:[a-z-]+\\)" end t)
        (push (cons (- (match-end 1) (match-beginning 1))
                    (substring (match-string-no-properties 2) 1))
              found))
      (when found
        (let ((min (apply #'min (mapcar #'car found))) kws)
          (dolist (f (nreverse found) (nreverse kws))
            (when (and (= (car f) min) (not (member (cdr f) kws)))
              (push (cdr f) kws))))))))

(defun init-panel--refresh-summaries (&rest _)
  "Add a keyword summary after every folded `use-package' line, remove the rest."
  (when (and init-panel-mode init-panel-fold-summary)
    (remove-overlays nil nil 'init-panel-summary t)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^(use-package[ \t]" nil t)
        (let ((eol (line-end-position)))
          (when (invisible-p eol)
            (let* ((end (max eol (or (ignore-errors (scan-sexps (line-beginning-position) 1)) eol)))
                   (kws (init-panel--form-keywords eol end)))
              (when kws
                (let ((ov (make-overlay eol eol)))
                  (overlay-put ov 'init-panel-summary t)
                  (overlay-put ov 'after-string
                               (propertize (concat " " (string-join kws " ")) 'face 'init-panel-summary)))))))))))

;;;; Margin (right, `margin' style)

(defun init-panel--code-width (window)
  "Widest code column among the lines visible in WINDOW.
Comment-only lines are ignored; on note lines only the code before the
marker counts."
  (with-current-buffer (window-buffer window)
    (save-excursion
      (let ((end (window-end window t)) (width 0))
        (goto-char (window-start window))
        (while (< (point) end)
          (unless (looking-at-p (concat "[ \t]*" (regexp-quote (init-panel--comment))))
            (if (looking-at init-panel--note-re)
                (goto-char (match-end 1))
              (end-of-line)
              (skip-chars-backward " \t"))
            (setq width (max width (current-column))))
          (forward-line 1))
        width))))

(defun init-panel--margin-width (window)
  "Right margin width WINDOW should have for its buffer, 0 to collapse."
  (with-current-buffer (window-buffer window)
    (cond
     ((integerp init-panel-margin-width) init-panel-margin-width)
     ((floatp init-panel-margin-width)
      (round (* init-panel-margin-width (window-total-width window))))
     (t (let* ((available (+ (window-body-width window)
                             (or (cdr (window-margins window)) 0)))
               (code (max (init-panel--code-width window) init-panel-min-code-width))
               (room (- available code 1)))
          (if (< room init-panel-margin-min) 0
            (min room init-panel-margin-max)))))))

(defun init-panel--left-margin (window)
  "Left margin WINDOW should have: ours, or a wider one someone else set.
Not scaled with `text-scale-mode': margin glyphs don't grow with the
buffer text, so a fixed width keeps them next to the line numbers."
  (let ((current (or (car (window-margins window)) 0)))
    (if (or init-panel-kind-margin init-panel-section-guide)
        (max current init-panel-margin-cells)
      (and (> current 0) current))))

(defun init-panel--apply-layout (window)
  "Apply the note column, left margin and right margin WINDOW's buffer needs."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      (when init-panel-mode
        (let* ((flush nil)
               (left (init-panel--left-margin window))
               (right (if (eq init-panel-style 'margin)
                          (let ((w (init-panel--margin-width window))) (and (> w 0) w))
                        nil))
               (margins (window-margins window)))
          (unless (and (eql (car margins) left) (eql (cdr margins) right))
            (set-window-margins window left right))
          (when left (setq init-panel--left-margin-set t))
          (if (eq init-panel-style 'margin)
              (unless (eq (null right) init-panel--inline)
                (setq init-panel--inline (null right) flush t))
            (let ((col (if init-panel-column-auto
                           (max init-panel-column (1+ (init-panel--code-width window)))
                         init-panel-column)))
              (unless (eql col init-panel--column)
                (setq init-panel--column col flush t))))
          (when flush (font-lock-flush)))))))

(defun init-panel--reset-margins (window)
  "Drop the margins `init-panel-mode' gave WINDOW."
  (when (window-live-p window)
    (set-window-margins window (and (not init-panel--left-margin-set) (car (window-margins window))) nil)))

(defun init-panel--refresh-windows (&optional frame-or-window)
  "Recompute margins for every window showing an `init-panel-mode' buffer.
FRAME-OR-WINDOW limits the windows to one frame (a window names its frame)."
  (let ((frame (if (windowp frame-or-window) (window-frame frame-or-window) frame-or-window)))
    (dolist (w (window-list frame 'nomini))
      (when (buffer-local-value 'init-panel-mode (window-buffer w))
        (init-panel--apply-layout w)))))

(defun init-panel--on-scroll (window _start)
  "Reapply WINDOW's layout shortly after a scroll (never inside redisplay)."
  (when (and (not init-panel--scroll-timer)
             (buffer-local-value 'init-panel-mode (window-buffer window)))
    (setq init-panel--scroll-timer
          (run-at-time 0.1 nil
                       (lambda ()
                         (setq init-panel--scroll-timer nil)
                         (init-panel--apply-layout window))))))

(defun init-panel-toggle-style ()
  "Switch this buffer between `column' and `margin' note styles."
  (interactive)
  (setq-local init-panel-style (if (eq init-panel-style 'margin) 'column 'margin))
  (init-panel--refresh-windows)
  (font-lock-flush)
  (message "init-panel: %s style" init-panel-style))

;;;; Eldoc

(defun init-panel--note-at-point ()
  "The notes attached to the top-level form around point, joined, or nil."
  (save-excursion
    (let ((end (progn (ignore-errors (end-of-defun)) (point)))
          (beg (progn (ignore-errors (beginning-of-defun)) (point)))
          notes)
      (when (< beg end)
        (goto-char beg)
        (while (re-search-forward init-panel--note-re end t)
          (let ((state (save-excursion (syntax-ppss (match-beginning 3)))))
            (unless (or (nth 3 state) (nth 4 state))
              (push (string-trim (match-string-no-properties 5)) notes))))
        (when notes (string-join (nreverse notes) " "))))))

(defun init-panel--eldoc (callback &rest _)
  "Eldoc function: pass the note of the form at point to CALLBACK.
Only when `init-panel-eldoc' is `always'."
  (when (eq init-panel-eldoc 'always)
    (when-let* ((note (init-panel--note-at-point)))
      (funcall callback note :thing "note" :face 'init-panel-note))))

;;;; Navigation: imenu, which-function, header line

(defun init-panel--heading-name ()
  "Name of the comment heading on the current line, or nil."
  (save-excursion
    (beginning-of-line)
    (and (looking-at init-panel--heading-re)
         (match-string-no-properties 5))))

(defun init-panel--section-path (&optional pos)
  "`Section › Subsection' path of the heading enclosing POS (default: point)."
  (save-excursion
    (when pos (goto-char pos))
    (let (names)
      (when (ignore-errors (outline-back-to-heading t) t)
        (when-let* ((name (init-panel--heading-name))) (push name names))
        (while (ignore-errors (outline-up-heading 1 t) t)
          (when-let* ((name (init-panel--heading-name))) (push name names))))
      (when names (string-join names " › ")))))

(defun init-panel--current-section ()
  "`add-log-current-defun-function' for `which-function-mode'."
  (init-panel--section-path))

(defun init-panel--imenu-index ()
  "Build the imenu index with folding suspended.
`imenu-default-create-index-function' skips invisible definitions, which
in a folded panel is most of them."
  (let ((buffer-invisibility-spec nil))
    (imenu-default-create-index-function)))

(defun init-panel--header ()
  "Breadcrumb for the section point is in (see `init-panel-header-line')."
  (when-let* ((path (init-panel--section-path
                     (if (eq init-panel-header-line 'window-start)
                         (window-start (get-buffer-window (current-buffer)))
                       (point)))))
    (propertize (concat " " path) 'face 'init-panel-header)))

;;;; Normalizing the source

(defun init-panel--normalize-line (last-marker-col)
  "Normalize the current line in place; return the note marker column or nil.
Headings lose their typed rule; a note gets exactly one space before its
marker, or, when the line has no code, is indented to LAST-MARKER-COL so
continuations line up under the note above."
  (let ((bol (line-beginning-position)) (eol (line-end-position)))
    (cond
     ((progn (goto-char bol) (looking-at init-panel--heading-re))
      (when (or (> (match-end 3) (match-beginning 3)) (> (- (match-end 4) (match-beginning 4)) 0))
        (replace-match (concat (match-string 1) " " (match-string 5)) t t))
      nil)
     ((and (progn (goto-char bol) (looking-at init-panel--note-re))
           (let ((st (save-excursion (syntax-ppss (match-beginning 3)))))
             (not (or (nth 3 st) (nth 4 st)))))
      (let* ((code (string-trim-right (match-string 1)))
             (note (match-string 3))
             (col (if (string-empty-p code) (or last-marker-col 0) (1+ (length code)))))
        (delete-region bol eol)
        (insert (if (string-empty-p code) (make-string col ?\s) (concat code " ")) note)
        col))
     (t last-marker-col))))

(defun init-panel-normalize-region (beg end)
  "Strip typed layout between BEG and END: heading rules and note padding.
The panel draws both, so the file only needs the markers.  Returns the
number of lines changed."
  (interactive "r")
  (unless init-panel--heading-re (init-panel--build-regexps))
  (let ((changed 0) last-col (end (copy-marker end)))
    (save-excursion
      (goto-char beg)
      (beginning-of-line)
      (while (< (point) end)
        (let ((before (buffer-substring (line-beginning-position) (line-end-position))))
          (setq last-col (init-panel--normalize-line last-col))
          (unless (equal before (buffer-substring (line-beginning-position) (line-end-position)))
            (setq changed (1+ changed))))
        (forward-line 1)))
    (set-marker end nil)
    changed))

(defun init-panel-normalize-buffer ()
  "Strip the typed layout from the whole buffer.
See `init-panel-normalize-region'."
  (interactive)
  (let ((n (init-panel-normalize-region (point-min) (point-max))))
    (message "init-panel: %d line%s normalized" n (if (= n 1) "" "s"))
    n))

;;;; Focus: edit one block in an indirect buffer, over the panel

(defcustom init-panel-focus-frame t
  "Show the focus buffer in a child frame on graphical displays.
Otherwise (and always on text terminals) it opens in a window below."
  :type 'boolean)

(defcustom init-panel-focus-max-height 40
  "Most lines a focus frame or window will take."
  :type 'integer)

(defvar-local init-panel--focus-base nil
  "The panel buffer a focus buffer was opened from.")

(defvar init-panel-focus-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'init-panel-focus-close)
    (define-key map (kbd "C-c C-k") #'init-panel-focus-close)
    map)
  "Keymap of `init-panel-focus-mode'.")

(define-minor-mode init-panel-focus-mode
  "Editing one block of a panel in its own buffer; \\[init-panel-focus-close] returns."
  :lighter " focus"
  :keymap init-panel-focus-mode-map)

(defun init-panel--focus-bounds ()
  "(BEG . END) of the block around point: a heading's subtree or a top-level form.
A form's trailing note continuations (code-less `;.' lines) are included."
  (save-excursion
    (beginning-of-line)
    (if (looking-at init-panel--heading-re)
        (let ((beg (point)))
          (outline-end-of-subtree)
          (cons beg (min (point-max) (1+ (point)))))
      (let* ((end (progn (ignore-errors (end-of-defun)) (point)))
             (beg (progn (ignore-errors (beginning-of-defun)) (point))))
        (goto-char end)
        (while (and (< (point) (point-max))
                    (looking-at (concat "^[ \t]*" (regexp-quote (init-panel--comment)) "[>.]")))
          (forward-line 1))
        (cons beg (point))))))

(defun init-panel--focus-buffer (beg end)
  "An indirect buffer of the current buffer, narrowed to BEG..END, ready to edit."
  (let* ((base (current-buffer))
         (title (string-trim (buffer-substring-no-properties beg (min end (line-end-position)))))
         (name (generate-new-buffer-name (format "*focus: %s*" (truncate-string-to-width title 40 nil nil "…"))))
         (clone (make-indirect-buffer base name t)))
    (with-current-buffer clone
      (narrow-to-region beg end)
      (goto-char (point-min))
      (when (bound-and-true-p outline-minor-mode) (outline-show-all))
      (when (bound-and-true-p init-panel-header-line)
        (setq header-line-format (propertize (format " %s — C-c C-c to return" title) 'face 'init-panel-header)))
      (setq init-panel--focus-base base)
      (init-panel-focus-mode 1))
    clone))

(defun init-panel--focus-show (clone lines)
  "Display CLONE, sized for LINES, in a child frame or a window below."
  (let ((height (min init-panel-focus-max-height (+ lines 2))))
    (if (and init-panel-focus-frame (display-graphic-p))
        (let* ((parent (selected-frame))
               (pw (frame-width parent))
               (width (max 60 (min (- pw 8) 120)))
               (frame (make-frame `((parent-frame . ,parent)
                                    (name . ,(buffer-name clone))
                                    (undecorated . t)
                                    (minibuffer . nil)
                                    (width . ,width) (height . ,height)
                                    (left . ,(* (frame-char-width parent) (max 0 (/ (- pw width) 2))))
                                    (top . ,(* (frame-char-height parent) 3))
                                    (internal-border-width . 2)
                                    (vertical-scroll-bars . nil)
                                    (menu-bar-lines . 0) (tool-bar-lines . 0) (tab-bar-lines . 0)
                                    (init-panel-focus . t)))))
          (set-window-buffer (frame-root-window frame) clone)
          (set-window-dedicated-p (frame-root-window frame) t)
          (select-frame-set-input-focus frame))
      (pop-to-buffer clone `((display-buffer-below-selected) (window-height . ,height))))))

(defun init-panel-focus ()
  "Edit the block at point in its own buffer, over the folded panel.
The block is the section under a heading, or the top-level form around
point.  The buffer is indirect: edits land in the file immediately, undo
is shared, nothing is copied back.  \\[init-panel-focus-close] returns."
  (interactive)
  (unless init-panel--heading-re (init-panel--build-regexps))
  (let* ((bounds (init-panel--focus-bounds))
         (lines (count-lines (car bounds) (cdr bounds)))
         (clone (init-panel--focus-buffer (car bounds) (cdr bounds))))
    (init-panel--focus-show clone lines)
    clone))

(defun init-panel-focus-close ()
  "Close the focus buffer and go back to the panel it came from."
  (interactive)
  (let* ((clone (current-buffer))
         (base init-panel--focus-base)
         (frame (selected-frame)))
    (if (frame-parameter frame 'init-panel-focus)
        (progn (delete-frame frame) (kill-buffer clone))
      (let ((win (get-buffer-window clone)))
        (kill-buffer clone)
        (when (and win (window-live-p win) (not (eq win (frame-root-window))))
          (delete-window win))))
    (when (buffer-live-p base)
      (pop-to-buffer-same-window base))))

;;;; Commands

(defun init-panel-fold ()
  "Fold the buffer back to its top-level sections (the open-file state)."
  (interactive)
  (outline-hide-sublevels 1))

(defun init-panel-fold-subsections ()
  "Show sections and subsections only; hide every form."
  (interactive)
  (outline-hide-sublevels 2))

(defun init-panel-show-headings ()
  "Show every heading, sections, subsections and top-level forms, and nothing else."
  (interactive)
  (outline-show-only-headings))

(defvar init-panel-mode-map (make-sparse-keymap)
  "Keymap for `init-panel-mode', empty on purpose.
Bind what you like: `init-panel-show-headings',
`init-panel-fold-subsections' and `init-panel-fold' are the candidates.")

;;;; Mode

(defun init-panel--enable ()
  "Turn the panel on in the current buffer."
  (init-panel--build-regexps)
  (init-panel--build-glyphs)
  (setq init-panel--point-line (and init-panel-raw-at-point (line-beginning-position)))
  ;; native outline: folded to sections, TAB/S-TAB cycling, heading faces
  (setq-local outline-default-state 1)
  (setq-local outline-minor-mode-cycle t)
  (setq-local outline-minor-mode-highlight 'override)
  (setq-local outline-minor-mode-use-buttons init-panel-use-buttons)
  (when outline-minor-mode (outline-minor-mode -1))
  (outline-minor-mode 1)
  ;; fold ellipsis
  (setq init-panel--display-table (or buffer-display-table (make-display-table)))
  (set-display-table-slot init-panel--display-table 'selective-display
                          (string-to-vector init-panel-ellipsis))
  (setq buffer-display-table init-panel--display-table)
  ;; rendering — add keywords first: with font-lock on, that re-runs
  ;; `font-lock-set-defaults', which resets the managed-props list
  (font-lock-add-keywords nil init-panel--keywords 'append)
  (make-local-variable 'font-lock-extra-managed-props)
  (dolist (prop '(display keymap mouse-face help-echo init-panel-symbol))
    (unless (memq prop font-lock-extra-managed-props)
      (push prop font-lock-extra-managed-props)))
  (when init-panel-raw-at-point
    (add-hook 'post-command-hook #'init-panel--track-point nil t))
  ;; left margin (kind icons + guide) and section tracking
  (init-panel--locate-point)
  (when (or init-panel-kind-margin init-panel-section-guide)
    (jit-lock-register #'init-panel--jit-margin))
  (when init-panel-section-guide
    (add-hook 'post-command-hook #'init-panel--guide-update nil t))
  ;; folded summaries
  (when init-panel-fold-summary                                    ; obsolete since 29.1 with no replacement, still run by outline-flag-region
    (with-suppressed-warnings ((obsolete outline-view-change-hook))
      (add-hook 'outline-view-change-hook #'init-panel--refresh-summaries nil t)))
  ;; layout (note column, margins), per window
  (setq init-panel--column nil)
  (add-hook 'window-size-change-functions #'init-panel--refresh-windows)
  (add-hook 'window-buffer-change-functions #'init-panel--refresh-windows)
  (add-hook 'window-scroll-functions #'init-panel--on-scroll)
  (init-panel--refresh-windows)
  ;; eldoc, imenu, which-function, header line
  (add-hook 'eldoc-documentation-functions #'init-panel--eldoc nil t)
  (let ((c (regexp-quote (init-panel--comment)))
        (name "\\(\\S-\\(?:.*[^-]\\)?\\)$"))
    (setq-local imenu-generic-expression
                (append `(("Section" ,(concat "^" c "\\{3\\} -*[ \t]*" name) 1)
                          ("Subsection" ,(concat "^" c "\\{4\\} -*[ \t]*" name) 1))
                        (and init-panel-package-index
                             '(("Packages" "^(use-package[ \t]+\\([^ \t\n()]+\\)" 1)))
                        imenu-generic-expression)))
  (setq-local imenu-create-index-function #'init-panel--imenu-index)
  (setq-local add-log-current-defun-function #'init-panel--current-section)
  (when init-panel-header-line
    (setq init-panel--saved-header-line header-line-format)
    (setq header-line-format '(:eval (init-panel--header))))
  ;; quiet diagnostics
  (when (and init-panel-quiet-diagnostics (boundp 'flymake-show-diagnostics-at-end-of-line))
    (setq-local flymake-show-diagnostics-at-end-of-line nil)
    (when (bound-and-true-p flymake-mode)
      (flymake-mode -1)
      (flymake-mode 1)))
  (font-lock-flush)
  (init-panel--refresh-summaries))

(defun init-panel--disable ()
  "Turn the panel off and restore the buffer."
  (font-lock-remove-keywords nil init-panel--keywords)
  (remove-hook 'post-command-hook #'init-panel--track-point t)
  (remove-hook 'post-command-hook #'init-panel--guide-update t)
  (with-suppressed-warnings ((obsolete outline-view-change-hook))
    (remove-hook 'outline-view-change-hook #'init-panel--refresh-summaries t))
  (remove-hook 'eldoc-documentation-functions #'init-panel--eldoc t)
  (jit-lock-unregister #'init-panel--jit-margin)
  (remove-overlays nil nil 'init-panel-margin t)
  (remove-overlays nil nil 'init-panel-summary t)
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (init-panel--reset-margins w))
  (setq init-panel--left-margin-set nil)
  (unless (seq-some (lambda (b) (and (not (eq b (current-buffer)))
                                     (buffer-local-value 'init-panel-mode b)))
                    (buffer-list))
    (remove-hook 'window-size-change-functions #'init-panel--refresh-windows)
    (remove-hook 'window-buffer-change-functions #'init-panel--refresh-windows)
    (remove-hook 'window-scroll-functions #'init-panel--on-scroll))
  (when init-panel-header-line
    (setq header-line-format init-panel--saved-header-line))
  (when (local-variable-p 'flymake-show-diagnostics-at-end-of-line)
    (kill-local-variable 'flymake-show-diagnostics-at-end-of-line)
    (when (bound-and-true-p flymake-mode)
      (flymake-mode -1)
      (flymake-mode 1)))
  (kill-local-variable 'imenu-generic-expression)
  (kill-local-variable 'imenu-create-index-function)
  (kill-local-variable 'add-log-current-defun-function)
  (kill-local-variable 'outline-default-state)
  (kill-local-variable 'outline-minor-mode-cycle)
  (kill-local-variable 'outline-minor-mode-highlight)
  (kill-local-variable 'outline-minor-mode-use-buttons)
  (outline-minor-mode -1)
  (font-lock-flush))

;;;###autoload
(define-minor-mode init-panel-mode
  "Read a comment-outlined file as a panel: folding, icons, aligned notes.
See the Commentary in init-panel.el for the file conventions."
  :lighter " ⁝"
  :keymap init-panel-mode-map
  (if init-panel-mode (init-panel--enable) (init-panel--disable)))

(provide 'init-panel)
;;; init-panel.el ends here
