;;; init.el --- Mahatmus Emacs Configuration -*- lexical-binding: t; init-panel: t -*-
;;; Tips
;;;; Navigation
;; TAB    on heading  → cycle that section (hide → children → expand)
;; S-TAB  on heading  → cycle the whole buffer (all → headings → top-level)
;; C-c C-t            → show every heading and top-level form (table of contents)
;; C-c C-s            → sections + subsections only
;; C-c C-y            → collapse all (back to open-file state)
;; C-c C-o            → edit the block at point in a popup over the panel; C-c C-c returns
;; M-g o / M-g i      → jump to a heading or a package by name (consult-outline / imenu)
;; RET on a note link → describe that symbol; [fix]/[perf]/[hack]/[todo] are badges
;; C-c w              → open a tab per repo in me/workspace-default-repos
;; C-c e              → open init.el (this file)
;;;; Conventions
;; ;;; Name    section (level 1, shown collapsed on open) — init-panel draws the rule and icon
;; ;;;; Name   subsection (level 2)
;; ;> text     note after a form, one space before it — init-panel draws the column; explains WHY, not what
;; ;. text     continuation of the note above, or a sub-item inside a block
;; [fix]:      note prefix for a workaround (also [perf] [hack] [todo] [wip] [emacsNN])
;; M-;         comment or uncomment region (rebound below, see Keybinds)
;; functions live in custom.el (loaded first); init.el only wires them
;;;; Packages
;; :straight (not :ensure) — all packages managed by straight.el
;; :demand t   load immediately, overrides use-package-always-defer t
;; :after X    loads after X, but only with a :hook/:bind/:commands/:demand
;;             trigger — :after alone never loads anything under always-defer
;;; Bootstrap
;;;; Loading
(load (expand-file-name "custom.el" user-emacs-directory)) ;> custom functions
(load (expand-file-name "local.el" user-emacs-directory) ;> gitignored — personal values override the
      'noerror 'nomessage) ;. generic defaults from custom.el; absence is fine, see README
(setq custom-file (expand-file-name ;> keep the Custom-generated block out of init.el
                   "custom-set.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage) ;> safe-local-variable-values etc.; untracked (/custom-set.el in .gitignore), so approvals made on this machine stay on it
(add-hook 'emacs-startup-hook ;> restore file-name-handler-alist after startup
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)) ;. 16MB — sane value until gcmh takes over (after-init)
            (setq file-name-handler-alist me/file-name-handler-alist-backup)))
;;;; Package Manager
(defvar bootstrap-version)
(let ((bootstrap-file ;> install package manager
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))
(setq straight-cache-autoloads t) ;> cache all autoloads into one file instead of one per package
(straight-use-package 'use-package) ;> use-package macro
(setq-default straight-use-package-by-default t) ;> set straight as default package manager
(setq straight-check-for-modifications ;> only check when explicitly requested, not on every startup
      '(check-on-save find-when-checking))
(setq use-package-always-defer t) ;> defer all packages by default; add :demand t to override
;;;; Warnings
(setq warning-suppress-log-types '((comp) (emacs))) ;> keep native-compilation and eager-macroexpand warnings out of *Warnings* history
(setq warning-suppress-types '((comp) (emacs))) ;> and out of the popup
(setq native-comp-async-report-warnings-errors 'silent) ;> log async native-comp warnings without popping *Warnings*
                                                        ;. valid values are t/nil/silent; 'errors-only acted as t
;;; Core
;;;; IDE
(add-hook 'after-init-hook #'column-number-mode) ;> show column number in modeline
(add-hook 'after-init-hook #'global-display-line-numbers-mode) ;> line numbers in every buffer
(setq-default truncate-lines t) ;> set truncate lines
(setq-default truncate-partial-width-windows t) ;> set truncate lines in split windows
(setq-default display-line-numbers-width 3) ;> reserve 3 chars for line number gutter
(setq visible-bell nil) ;> disable visual bell
(setq frame-title-format nil) ;> clean frame title
(setq text-scale-mode-step 1.1) ;> small increments when zoom font size
;;;; Usability
(add-hook 'after-init-hook #'save-place-mode) ;> remember last cursor position in buffer
(add-hook 'after-init-hook #'auto-save-visited-mode) ;> auto-save directly to the visited file
(add-hook 'after-init-hook #'global-auto-revert-mode) ;> auto-revert buffers on disk changes
(setq use-short-answers t) ;> accept y/n instead of yes/no
(set-charset-priority 'unicode) ;> set UTF-8 as default
(prefer-coding-system 'utf-8-unix) ;> set UTF-8 as default
(dolist (target '(STRING TEXT COMPOUND_TEXT text/plain)) ;> [fix]: clipboard encoding between emacs-wayland and chrome-wayland
  (setq selection-converter-alist ;. drops the ambiguous ICCCM targets (Latin-1)
        (assq-delete-all target selection-converter-alist))) ;. so Chrome can't grab the wrong (non-UTF-8) one
;;;; UI
(blink-cursor-mode -1) ;> Steady cursor
(setq ring-bell-function 'ignore) ;> silence all error bells
(setq custom-safe-themes t) ;> trust all themes without prompt
(setq initial-scratch-message "") ;> empty scratch buffer on startup
(setq initial-major-mode 'text-mode) ;> start scratch in text-mode
;;;; Navigation
(add-hook 'after-init-hook #'xterm-mouse-mode) ;> enable mouse support in terminal
(add-hook 'after-init-hook #'pixel-scroll-precision-mode) ;> per-pixel smooth scrolling on pgtk/Wayland — touchpad no longer jumps by lines
(add-hook 'after-init-hook #'repeat-mode) ;> C-x o o o, C-x t o o: repeat a prefix command's last key without the prefix
(setq help-window-select t) ;> auto-select help windows on open
(setq scroll-conservatively 101) ;> smooth scrolling, no jump
(setq scroll-preserve-screen-position t) ;> keep the point in the same place while scrolling
(setq mouse-wheel-progressive-speed nil) ;> [fix]: cursor jumping with mouse-wheel scroll
                                         ;. constant scroll amount per notch, no
                                         ;. acceleration triggering point relocation
(setopt mouse-wheel-tilt-scroll t) ;> sideways wheel/touchpad motion scrolls horizontally
(setopt mouse-wheel-flip-direction t) ;> with it, content follows the finger
;;;; Windows
(use-package winner ;> undo/redo window layout changes
  :straight (:type built-in)
  :hook (after-init . winner-mode)
  :init
  (setq winner-dont-bind-my-keys t) ;. its C-c <left>/<right> would fight paredit's slurp/barf
  :bind (("C-x w u" . winner-undo) ;. C-x w is Emacs 30's window prefix map
         ("C-x w r" . winner-redo))
  :config
  (defvar-keymap me/winner-repeat-map ;. C-x w u u u… via repeat-mode
    :repeat t
    "u" #'winner-undo
    "r" #'winner-redo))
;;;; Performance
(setq read-process-output-max (* 4 1024 1024)) ;> 4MB — improves LSP throughput
(add-hook 'after-init-hook #'global-so-long-mode) ;> [fix]: files with 50k-char lines (minified, logs) freeze font-lock — so-long disables it there
;;; Stability
;;;; Bug Fixes
(use-package transient ;> force straight's transient before Emacs 30 built-in (0.7.2.2 lacks transient--set-layout)
  :demand t) ;. no :straight (:type built-in): the build must come from straight, not Emacs

(use-package compat ;> load early to prevent "void function" errors
  :demand t) ;. no :straight (:type built-in): packages need a newer compat than Emacs ships
;;;; Performance
(use-package gcmh ;> intelligent GC — high threshold during work, low when idle
  :hook (after-init . gcmh-mode)
  :custom
  (gcmh-idle-delay 5)
  (gcmh-high-cons-threshold (* 256 1024 1024))
  (gcmh-low-cons-threshold  (* 16  1024 1024)))

;;; Visuals
;;;; Icons
(use-package nerd-icons) ;> glyph set behind every nerd-icons-* integration below

(use-package nerd-icons-corfu ;> kind icons in the corfu popup
  :after corfu
  :demand t ;. :after alone never loads under always-defer
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-completion ;> icons beside minibuffer candidates
  :hook (marginalia-mode . nerd-icons-completion-marginalia-setup)) ;. setup toggles the mode itself; the hook is what triggers the load

;;;; Themes
(use-package modus-themes ;> the theme family omarchy derives its colours from
  :demand t)

(use-package omarchy ;> omarchy visual themes
  :straight nil ;. local clone of omarchy.el, not a package-archive install
  :load-path "local-packages/omarchy.el" ;. the clone's directory (relative to user-emacs-directory), not a file
  :demand t
  :init
  (setq omarchy-default-theme 'modus-vivendi
        omarchy-default-font  "JetBrainsMono Nerd Font Mono"
        omarchy-font-height   me/editor-font-height) ;. any font apply by the package keeps the pinned size
  :config
  (require 'omarchy-themes) ; register bundled themes
  (dolist (entry (me/omarchy-user-theme-entries)) ;> user themes in ~/.config/omarchy/themes/ with a colors.toml, derived on the Modus base — added before init so the startup sync finds them; they win over a same-named shipped theme, as in Omarchy
    (add-to-list 'omarchy-theme-map entry))
  (omarchy-init)
  (me/set-editor-font) ;> last, so the pinned family beats the font Omarchy just synced from the desktop
  (me/save-frame-colors)) ;. rewrite frame-colors.el so the next startup pre-renders with the final font

(add-hook 'enable-theme-functions #'me/tab-bar-refresh-focus-highlight) ;> tab-bar focus border tracks any theme (any package, or none)
(add-hook 'after-init-hook #'me/tab-bar-refresh-focus-highlight) ;. catches whatever theme startup already applied

;;;; Modeline
(use-package doom-modeline ;> compact mode line with project-relative file names
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-buffer-file-name-style 'relative-to-project)
  (doom-modeline-bar-width 0))
;;;; Outline
(use-package init-panel ;> read this config as a panel — on only in files whose first line says init-panel: t
  :straight (:host github :repo "mahatmus-tech/init-panel") ;. own repository: README and tests live there
  :hook (hack-local-variables . init-panel-maybe-enable) ;. autoloads on the first visited file; enables only where init-panel: t
  :init
  (put 'init-panel 'safe-local-variable #'booleanp) ;. [fix]: must exist before any file is visited or Emacs drops the var as unsafe (autoloads only arrive with the first command)
  :bind (:map init-panel-mode-map
              ("C-c C-t" . init-panel-show-headings) ;. every heading and top-level form (table of contents)
              ("C-c C-s" . init-panel-fold-subsections) ;. sections + subsections only
              ("C-c C-y" . init-panel-fold) ;. back to the open-file state: top-level sections only
              ("C-c C-o" . init-panel-focus))) ;. edit the section or form at point in a popup (indirect buffer); C-c C-c returns
;;;; Code
(use-package rainbow-delimiters ;> colorize parentheses by nesting depth
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package paren-face ;> dim parentheses to reduce visual noise
  :hook (emacs-lisp-mode . paren-face-mode))

(use-package highlight-defined ;> colorize defined emacs symbols by type
  :hook (emacs-lisp-mode . highlight-defined-mode))
;;; Editing
;;;; Settings
(setq show-paren-context-when-offscreen 'overlay) ;> [fix]: show the matching paren's line in an overlay when it is off-screen
                                                  ;. 'child-frame crashes Emacs (GTK widget-disposal bug), so the overlay is the only safe value
(add-hook 'after-init-hook #'electric-pair-mode) ;> auto-close delimiters
(add-hook 'after-init-hook #'delete-selection-mode) ;> delete selection on type
(setq-default tab-width 2) ;> default tab display width
(setq-default indent-tabs-mode nil) ;> spaces over tabs
(setq-default fill-column 100) ;> line wrap width
(setq kill-do-not-save-duplicates t) ;> consecutive identical kills collapse — cleaner consult-yank-pop
(setq save-interprogram-paste-before-kill t) ;> clipboard text from other apps lands in the kill-ring before the next kill overwrites it
(add-hook 'prog-mode-hook #'hs-minor-mode) ;> enable code folding in all programming modes (C-c @ C-h)
;;;; Packages
(use-package no-littering ;> runtime files go to var/ and etc/ instead of the config directory
  :demand t
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))
        backup-directory-alist
        `((".*" . ,(no-littering-expand-var-file-name "backup/")))))

(use-package dumb-jump ;> jump to definitions in buffers with no LSP or CIDER session
  :custom
  (dumb-jump-prefer-searcher 'rg)
  (xref-show-definitions-function #'consult-xref)
  (xref-show-xrefs-function #'consult-xref) ;. references (M-?) through consult too, not the *xref* buffer
  :hook (xref-backend-functions . dumb-jump-xref-activate)
  :config
  (setq xref-backend-functions (delete 'etags--xref-backend xref-backend-functions))) ;. disable etags as fallback

(use-package sudo-edit) ;> save root-owned files, such as the system Hyprland config, from Emacs
(use-package multiple-cursors ;> edit several places at once
  :commands (mc/edit-lines
             mc/mark-next-like-this
             mc/mark-previous-like-this
             mc/mark-all-like-this)
  :bind (("M-S-<up>"   . mc/mark-previous-lines)
         ("M-S-<down>" . mc/mark-next-lines))
  :custom
  (mc/always-repeat-command nil)
  (mc/always-run-for-all nil))
;;; Completion
;;;; Settings
(add-hook 'after-init-hook #'context-menu-mode) ;> enable right-click context menu
(setq enable-recursive-minibuffers t) ;> allow opening minibuffers from within minibuffers
(setq read-extended-command-predicate ;> hide M-x commands that don't work in current mode
      #'command-completion-default-include-p)
(setq minibuffer-prompt-properties ;> prevent cursor from entering the minibuffer prompt
      '(read-only t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode) ;> activate cursor-intangible to enforce the above
(keymap-unset minibuffer-local-completion-map "SPC") ;> unbind minibuffer-complete-word: conflicts with orderless space separator
;;;; Packages
(use-package corfu ;> completion with a small completion popup
  :custom
  (corfu-auto t)          ; trigger completion while typing
  (corfu-auto-delay 0.2)  ; delay before popup appears
  (corfu-auto-prefix 2)   ; minimum prefix length
  (corfu-quit-no-match 'separator)
  :hook ((after-init . global-corfu-mode)
         (after-init . corfu-history-mode) ;. sort candidates by history; registers corfu-history with savehist itself
         (after-init . corfu-popupinfo-mode))) ;. doc/signature popup beside the candidate (M-h toggles)

(use-package orderless ;> completion style with flexible candidate filtering
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-category-defaults nil)   ; no per-category style defaults: orderless everywhere
  (completion-pcm-leading-wildcard t)) ; Emacs 31: partial-completion behaves like substring

(use-package consult ;> enhanced search and navigation commands
  :bind (("C-s"     . consult-line)        ; search lines in buffer
         ("C-x b"   . consult-buffer)      ; switch buffer
         ("M-y"     . consult-yank-pop)    ; browse kill-ring
         ("C-x C-r" . consult-recent-file) ; recent files
         ("M-g g"   . consult-goto-line)   ; go to line
         ("M-g i"   . consult-imenu)       ; jump to symbol in buffer
         ("M-g o"   . consult-outline)     ; jump to heading
         ("M-g m"   . consult-mark)        ; jump to marker
         ("M-g f"   . consult-flymake))    ; jump to diagnostic
  :custom
  (consult-narrow-key "<"))                ; prefix key to narrow source in consult-buffer

(use-package vertico ;> vertical minibuffer completion UI
  :custom
  (vertico-cycle t)
  :hook (after-init . vertico-mode))

(use-package vertico-directory ;> better path navigation in file prompts
  :after vertico
  :straight (:type built-in)
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

(use-package savehist ;> persist history over emacs restarts. vertico sorts by history position
  :hook ((after-init . savehist-mode)
         (savehist-save . me/savehist-strip-kill-ring)) ;. [fix]: keep the history file readable — see custom.el
  :custom
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring))) ;. kill-ring survives restarts

(use-package marginalia ;> add annotation to minibuffer completions
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle)) ;. cycle annotation detail in the minibuffer
  :hook (after-init . marginalia-mode))

(use-package embark ;> minibuffer actions and context menu
  :bind
  (("C-." . embark-act)         ; actions on the thing at point or the candidate
   ("C-;" . embark-dwim)        ; the default action, no menu
   ("C-h B" . embark-bindings)) ; searchable replacement for `describe-bindings'
  :init
  (setq prefix-help-command #'embark-prefix-help-command) ;. C-h after a prefix key opens a searchable list of its bindings
  (add-hook 'context-menu-functions #'embark-context-menu 100) ;. embark actions in the right-click menu (context-menu-mode is on above)
  :config
  (add-to-list 'display-buffer-alist ;. no mode line in embark's collect buffers
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

(use-package embark-consult ;> integrates embark with consult
  :after (embark consult) ;. embark requires it itself once consult is loaded
  :hook (embark-collect-mode . consult-preview-at-point-mode))
;;; Files
;;;; Settings
(setq backup-by-copying t) ;> don't clobber symlinks on save
(setq create-lockfiles nil) ;> no .# lock files
(setq history-length 500) ;> minibuffer history entries to keep
;;;; Packages
(use-package recentf ;> track recently opened files — backs consult-recent-file (C-x C-r)
  :straight (:type built-in)
  :hook (after-init . recentf-mode)
  :custom
  (recentf-max-saved-items 200)) ;. default 20 is too few to be useful

(use-package dired ;> emacs file explorer
  :straight (:type built-in)
  :config
  (setq dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")
  (setq dired-dwim-target t) ;. copy/move defaults to the other visible dired (side panel ↔ C-c f)
  (put 'dired-find-alternate-file 'disabled nil)) ;. enable the command: it opens a file in place of the dired buffer, so `dirvish-side' does not stack another one

(use-package dirvish ;> dired with a side panel, previews and attribute columns
  :hook ((after-init . dirvish-override-dired-mode)
         (after-init . dirvish-side-follow-mode)) ;. side panel tracks the current buffer's file (what treemacs-follow-mode did)
  :custom
  (dirvish-quick-access-entries ; It's a custom option, `setq' won't work
   '(("h" "~/"                          "Home")
     ("d" "~/Downloads/"                "Downloads")))
  :config
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index)))
  (setq dirvish-attributes           ; The order *MATTERS* for some attributes
        '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size)
        dirvish-side-attributes
        '(vc-state nerd-icons collapse full-name-tip)) ;. hover tooltip for names cut off by the panel width — custom.el
  (setq dirvish-large-directory-threshold 20000) ;. open large directory (over 20000 files) asynchronously with `fd' command
  (advice-add 'dirvish-side-root-conf :after ;> [fix]: no room for the gutter in a 35-col sidebar
              (lambda (buffer)
                (with-current-buffer buffer (display-line-numbers-mode -1))))
  (advice-add 'dirvish-side--auto-jump :after #'me/dirvish-side-auto-jump-defer) ;. [fix]: panel index goes stale after find-file — see custom.el
  (advice-add 'dirvish-winbuf-change-h :before #'me/dirvish-side-restamp-tab) ;. [fix]: closing an earlier tab strands later tabs' panels — see custom.el
  (advice-add 'dirvish--new :around #'me/dirvish-side-unfix-width) ;. [fix]: panel width is draggable — see custom.el
  :bind
  (("C-c f" . dirvish)
   ("C-c F" . dirvish-side) ;. focus the visible side panel from any window; toggles it away from inside
   :map dirvish-mode-map ;. inherits `dired-mode-map', so dired bindings can be adjusted here
   (";"   . dired-up-directory)
   ("?"   . dirvish-dispatch) ;. cheatsheet of every dirvish command
   ("a"   . dirvish-setup-menu) ;. attribute settings: `t' toggles mtime, `f' full frame
   ("f"   . dirvish-file-info-menu) ;. file info
   ("o"   . dirvish-quick-access) ;. jump to `dirvish-quick-access-entries'
   ("s"   . dirvish-quicksort) ;. sort the listing
   ("r"   . dirvish-history-jump) ;. recently visited directories
   ("l"   . dirvish-ls-switches-menu) ;. ls flags
   ("v"   . dirvish-vc-menu) ;. version control commands
   ("*"   . dirvish-mark-menu)
   ("y"   . dirvish-yank-menu)
   ("N"   . dirvish-narrow)
   ("^"   . dirvish-history-last)
   ("TAB" . dirvish-subtree-toggle)
   ("RET" . me/dirvish-side-open-or-expand) ;. in the side panel only: expand directories in place instead of a new dired buffer (custom.el)
   ("<mouse-1>" . me/dirvish-mouse-open-or-expand) ;. same, for a mouse click
   ("<mouse-2>" . me/dirvish-mouse-open-or-expand) ;. [fix]: dired's follow-link convention turns a real mouse-1 click on a filename into mouse-2 — see the function's docstring
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)
   ("M-e" . dirvish-emerge-menu)))

;;; Projects
(use-package project ;> project.el: root detection behind the C-c p commands and tabspaces
  :straight (:type built-in) ;. the ELPA clone straight fetched was shadowing Emacs 30's own
  :bind (("C-c p f" . project-find-file)
         ("C-c p p" . project-switch-project)
         ("C-c p b" . consult-project-buffer)
         ("C-c p s" . consult-ripgrep)
         ("C-c p r" . project-query-replace-regexp))
  :config
  (setq project-vc-ignores '("*.gz" "*.zip" "*.tar" "*.tar.gz" "*.tgz"
                              "*.bz2" "*.xz" "*.jar" "*.class" "*.elc"))
  (setq project-kill-buffer-conditions
        '(buffer-file-name
          (and (major-mode . fundamental-mode) "\\`[^ ]")
          (and (derived-mode . special-mode)
               (not (major-mode . help-mode))
               (not (derived-mode . gnus-mode))
               (not (derived-mode . magit-mode)))
          (derived-mode . compilation-mode)
          (derived-mode . dired-mode)
          (derived-mode . diff-mode)
          (derived-mode . comint-mode)
          (derived-mode . eshell-mode)
          (derived-mode . change-log-mode))))

(use-package tabspaces ;> buffer isolation per tab
  :hook (after-init . tabspaces-mode)
  :custom
  (tabspaces-use-filtered-buffers-as-default t)
  (tabspaces-default-tab "dotfiles")
  (tabspaces-remove-to-default nil)
  (tabspaces-include-buffers '("*scratch*" "*Messages*" "*Warnings*" "*straight-process*" "*Async-native-compile-log*"))
  (tabspaces-session-auto-restore nil) ;. saved on exit (kill-emacs-hook) to var/tabspaces-session.eld, restored only on demand (C-c W):
                                       ;. Emacs also opens one-off system files — those launches must not drag the last session in
  (tabspaces-session-project-session-store nil) ;. one global file — 'project (default) would drop .<repo>-tabspaces-session.el inside every repo
  :bind (("C-c W" . tabspaces-restore-session) ;. C-c w builds the default workspaces, C-c W brings back last session's tabs
         ("C-x t 0" . tabspaces-kill-buffers-close-workspace)) ;. isolated tabspace: closing it kills its exclusive buffers too
  :config
  (tabspaces-register-buffer-kind 'skip ;. ghostel/claude terminals: saved as no-ops, never restored
                                  #'me/tabspaces-skip-terminal-record #'ignore)
  (tabspaces-register-buffer-kind 'dirvish-side ;. side panels: stored as a dir, rebuilt per tab after the restore loop
                                  #'me/tabspaces-side-panel-record #'me/tabspaces-side-panel-defer)
  (advice-add 'tabspaces--load-session-file :after #'me/tabspaces-strip-window-states) ;. window-state-put + dirvish side windows = "Attempt to delete main window"
  (advice-add 'tabspaces-restore-session :after #'me/tabspaces-restore-side-panels))

(with-eval-after-load 'consult ;> buffer list per tab
  (setq consult-source-buffer (plist-put consult-source-buffer :hidden t))
  (add-to-list 'consult-buffer-sources 'me/consult-source-tabspaces-buffer)) ;. the source itself is defined in custom.el (Tabspaces)

;;; Terminal
(use-package ghostel ;> terminal on ghostty's VT engine; renders claude's TUI cleanest
  :custom
  (ghostel-module-directory
   (expand-file-name "var/ghostel/" user-emacs-directory)) ;. native module outside straight's tree — a rebuild would delete it while loaded
  (ghostel-module-auto-install 'download)) ;. prebuilt binary from github releases on first use, no zig toolchain or prompt

(use-package claude-code-ide    ;> Claude Code with MCP + multi-session support
  :straight
  (:type git :host github :repo "manzaltu/claude-code-ide.el")
  :bind
  ("C-c k" . claude-code-ide-menu)
  :custom
  (claude-code-ide-terminal-backend 'ghostel) ;. eat's rendering was broken enough to be unusable; ghostel is the only terminal now
  (claude-code-ide-buffer-name-function
      (lambda (directory)
        (if directory
            (format "claude: %s" (file-name-nondirectory (directory-file-name directory)))
          "claude: global")))
  :config
  (claude-code-ide-emacs-tools-setup)
  (add-hook 'ghostel-mode-hook ;. remove number lines in claude buffers
            (lambda ()
              (when (string-prefix-p "claude:" (buffer-name))
                (display-line-numbers-mode -1)))))

;;; Version Control
(use-package magit-section ;> section engine of the *Dashboard* buffer (C-c D) — already installed as a magit dependency
  :commands magit-section-mode) ;. autoload only: `me/dashboard' requires it on first use

(use-package magit ;> git porcelain
  :commands (magit-status magit-dispatch)
  :hook (magit-status-sections-hook . magit-insert-worktrees)
  :init
  (setq auth-sources '("~/.authinfo"))
  (setq epg-pinentry-mode 'loopback)
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1)
  (setq magit-show-long-lines-warning nil) ;. defvar, not defcustom: must be nil before magit loads; silences the >50k-char-line notice
  )

(use-package forge ;> merge requests and issues via magit (gitlab)
  :after magit
  :custom
  (forge-owned-accounts me/forge-owned-accounts) ;. gitlab/github groups — set in local.el (gitignored, see local.el.example)
  (forge-topic-list-limit '(60 . 0)) ;. 60 open MRs, hides closed ones
  (forge-pull-notifications nil))

(use-package pr-review ;> inline PR/MR comments via forge (experimental gitlab support)
  :straight (:host github :repo "blahgeek/emacs-pr-review")
  :after forge
  :custom
  (pr-review-forges-alist '(("gitlab.com" . (gitlab "gitlab.com/api/v4" nil))))
  (pr-review-ghub-auth-name 'forge) ;. reuses the same ~/.authinfo entry as forge (any auth-source login works)
  :bind (:map forge-topic-mode-map
         ("C-c C-r" . me/pr-review-forge-at-point))) ;. custom.el (Version Control): the topic at point, or prompt outside one

(use-package ediff ;> ediff window fix for wayland
  :straight (:type built-in)
  :config
  (setq ediff-window-setup-function 'ediff-setup-windows-plain)
  (setq ediff-split-window-function 'split-window-horizontally)
  (add-hook 'ediff-prepare-buffer-hook
            (lambda ()
              (electric-pair-local-mode -1)
              (when (bound-and-true-p paredit-mode)
                (paredit-mode -1)))))

;;; Infrastructure
;;;; Docker
(use-package docker ;> containers, images and compose from Emacs
  :bind ("C-c d" . docker-compose)) ;. the compose transient ships here (docker-compose.el), not in a yaml major mode
(use-package dockerfile-ts-mode ;> tree-sitter Dockerfile mode (built-in) — no dockerfile-mode package needed
  :straight (:type built-in)
  :mode "\\(?:Dockerfile\\(?:\\..*\\)?\\|\\.[Dd]ockerfile\\)\\'") ;. the regexp the mode would register itself — but only on load, which never happens under always-defer

;;; Languages
;;;; Settings
(use-package flymake ;> on-the-fly syntax checking — built-in, eglot feeds it directly
  :straight (:type built-in)
  :hook ((prog-mode . flymake-mode)
         (emacs-lisp-mode . me/flymake-elisp-setup)) ;. no checkdoc noise, byte-compiler sees the full load-path
  :custom
  (flymake-show-diagnostics-at-end-of-line 'short)) ;. most severe diagnostic inline at eol (Emacs 30) — no hover needed
(use-package treesit ;> built-in tree-sitter (Emacs 30); the *-ts-modes need compiled grammars
  :straight (:type built-in)
  :config ;. runs on treesit load — the var doesn't exist before that; install-language-grammar loads it first
  (dolist (g '((yaml       . ("https://github.com/ikatyang/tree-sitter-yaml" "v0.5.0"))
               (dockerfile . ("https://github.com/camdencheek/tree-sitter-dockerfile" "v0.2.0"))))
    (add-to-list 'treesit-language-source-alist g))) ;. build once with M-x treesit-install-language-grammar (git + cc) into tree-sitter/; json comes from ob-json.el
;;;; Clojure
(use-package clojure-mode) ;> clojure mode — kept as CIDER's dependency and fallback
(use-package clojure-ts-mode ;> tree-sitter clojure mode (Emacs 30+); clojure-mode stays as CIDER's dependency
  :init ;. remap natively: the package only remaps on load, which never happens under always-defer
  (dolist (m '((clojure-mode       . clojure-ts-mode) ;. nothing loads at startup — the first .clj opened autoloads the mode
               (clojurescript-mode . clojure-ts-clojurescript-mode)
               (clojurec-mode      . clojure-ts-clojurec-mode)
               (edn-mode           . clojure-ts-mode)))
    (add-to-list 'major-mode-remap-alist m))) ;. grammars (clojure, regex, markdown-inline) auto-build on first load — needs cc
(use-package cider ;> Clojure REPL: jack-in or connect, inline eval, docs
  :after clojure-mode
  :commands (cider-jack-in cider-connect cider-connect-clj cider-connect-cljs)
  :init
  (setq
   cider-preferred-build-tool 'clojure-cli ;. Uses clj/deps.edn when jack-in can't detect the build tool from context
   cider-show-error-buffer 'only-in-repl ;. Shows error details only inside the REPL buffer; won't pop up a separate *cider-error* window
   cider-auto-jump-to-error nil ;. Doesn't move point to the error location in source when an error occurs
   cider-connection-message-fn #'cider-random-tip ;. Displays a random CIDER tip in the REPL on connect instead of the default welcome message
   cider-font-lock-dynamically nil ;. Disables dynamic font-locking of var names/macros from the running REPL (avoids slowdowns in large codebases)
   cider-prompt-for-symbol nil ;. Uses the symbol at point directly for docs/lookup commands instead of prompting to confirm
   cider-use-xref t ;. Enables xref integration so M-. / M-, use CIDER's backend for find-definition and go-back
   cider-repl-display-help-banner nil ;. Hides the keyboard shortcut help banner that normally appears at the top of new REPL buffers
   cider-print-fn 'fipp ;. Uses fipp for pretty-printing REPL results instead of the default pprint
   cider-result-overlay-position 'at-eol ;. Places inline eval result overlays at end-of-line rather than after the closing paren
   cider-overlays-use-font-lock t ;. Applies syntax highlighting to inline result overlays
   cider-repl-buffer-size-limit 500000 ;. Caps the REPL buffer at 500KB; older output is trimmed to prevent unbounded growth
   cider-repl-history-file (no-littering-expand-var-file-name "cider-repl-history") ;. Persists REPL input history across sessions (var/, like all other state)
   cider-repl-history-size 2000 ;. Keeps up to 2000 entries in that history
   cider-save-file-on-load t)) ;. Automatically saves the buffer to disk before loading it into the REPL

(use-package eglot ;> native LSP client
  :straight (:type built-in)
  :hook ((clojure-mode clojure-ts-mode) . eglot-ensure)
  :custom
  (eglot-autoshutdown t)
  (eglot-confirm-server-edits nil) ;. renamed in eglot 1.16 (Emacs 30); old name is obsolete
  (eglot-connect-timeout 120)
  (eglot-events-buffer-config '(:size 0 :format full))) ;. no 2MB JSON-RPC log per server — debug only; raise :size when needed

(use-package eglot-booster ;> speed up eglot JSON parsing via native binary
  :straight (:host github :repo "jdtsmith/eglot-booster")
  :after eglot
  :demand t ;. :after alone never loads under always-defer
  :config (eglot-booster-mode))

(use-package paredit ;> structural editing for Lisps and Clojure
  :hook ((clojure-mode emacs-lisp-mode lisp-mode lisp-interaction-mode
                       scheme-mode clojurescript-mode clojurec-mode cider-repl-mode
                       clojure-ts-mode) ;. covers clojure-ts-clojurescript/clojurec-mode — they derive from it
         . enable-paredit-mode)
  :bind (:map paredit-mode-map ;. mode-local, so paredit commands stay out of other buffers
         ("C-c C-."     . paredit-backward-slurp-sexp)
         ("C-c C-,"     . paredit-backward-barf-sexp)
         ("C-c <left>"  . paredit-forward-slurp-sexp)
         ("C-c <right>" . paredit-forward-barf-sexp))
  :config
  (advice-add 'enable-paredit-mode :around
              (lambda (orig &rest args)
                (unless (save-excursion
                          (goto-char (point-min))
                          (re-search-forward "^<<<<<<< " nil t))
                  (apply orig args)))))

;;;; Markup
(use-package markdown-mode ;> markdown editing; README.md opens in gfm-mode
  :mode ("README\\.md\\'" . gfm-mode)
  :bind (:map markdown-mode-map
              ("C-c C-e" . markdown-do)))
(use-package yaml-ts-mode ;> tree-sitter YAML (built-in) for every .yml/.yaml, compose files included
  :straight (:type built-in)
  :mode "\\.ya?ml\\'") ;. the mode only registers itself on load (never, under always-defer); docker-compose-mode was dropped —
                       ;. its yaml-mode parent and this entry fought over auto-mode-alist, and its capf only knew compose v1–v3 keys
;;;; Awk
(add-hook 'awk-mode-hook ;> awk: 2-space indent with spaces, like everything else here
          (lambda ()
            (setq tab-width 2)
            (setq indent-tabs-mode nil)))
;;;; Web
(setq-default js-indent-level 2) ;> javascript indent width
(setq-default css-indent-offset 2) ;> css indent width
;;;; Ledger
(use-package ledger-mode ;> plain-text accounting driven by hledger
  :mode "\\.journal\\'" ;. hledger journals; rules/csv files stay in their own modes
  :custom
  (ledger-binary-path "hledger") ;. reports and checks run hledger, not ledger; LEDGER_FILE (environment.d) picks the root journal
  (ledger-mode-should-check-version nil) ;. the version probe only understands ledger's output
  (ledger-report-auto-width nil) ;. hledger has no --columns flag
  (ledger-report-use-native-highlighting nil) ;. ledger-only --color/--prepend-format flags
  (ledger-reports '(("bal" "%(binary) bal") ;. no %(ledger-file): hledger reads LEDGER_FILE, so a report run from any one journal still sees the whole ledger
                    ("reg" "%(binary) reg")
                    ("is -M" "%(binary) is -M"))))
(use-package hledger-mode ;> [wip]: one-session trial against ledger-mode (M-x hledger-mode on a .journal); keep the winner, drop the other
  :straight (:host github :repo "narendraj9/hledger-mode")
  :commands (hledger-mode hledger-run-command)) ;. no :mode on purpose — ledger-mode owns .journal until the trial decides
;;; Org
;;;; Settings
(use-package org ;> org settings
  :straight (:type built-in) ;. Emacs 30 ships 9.7 stable; straight's default recipe tracks the 10.0-pre main branch
  :custom
  ;; Usability
  (org-confirm-babel-evaluate #'me/org-babel-confirm-p) ;. no prompt for files under the org root or this config; everything else asks (custom.el, Org)
  (org-startup-folded nil)
  (org-src-fontify-natively t) ;. highlight source blocks with their language's mode
  (org-src-tab-acts-natively t) ;. TAB in a source block indents as the language's mode would
  (org-startup-with-inline-images t) ;. Auto-display inline images (ob-mermaid)
  ;; Edit settings
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-fold-catch-invisible-edits 'show-and-error) ;. current name since Org 9.6; the pre-fold name is an obsolete alias
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  ;; Styling
  (org-startup-indented t)
  (org-ellipsis " ⬎")
  (org-hide-emphasis-markers t)
  (org-pretty-entities t)
  (org-use-sub-superscripts nil)
  (org-agenda-tags-column 0)
  (org-agenda-show-tags t)
  ;; Files
  (org-directory me/org-directory) ;. custom.el default ~/org; the real root comes from local.el
  ;; TODO keywords — Todoist-like workflow
  (org-todo-keywords
   '((sequence "INBOX(i)" "TODO(t)" "NEXT(n)" "WAIT(w@/!)" "|" "DONE(d!)" "CANCELED(c@)")))
  (org-todo-keyword-faces
   '(("INBOX"    . (:foreground "#8888aa" :weight bold))
     ("TODO"     . (:foreground "#5577aa" :weight bold))
     ("NEXT"     . (:foreground "#dd8844" :weight bold))
     ("WAIT"     . (:foreground "#888888" :weight bold))
     ("DONE"     . (:foreground "#44aa44" :weight bold))
     ("CANCELED" . (:foreground "#aa4444" :weight bold :strike-through t))))
  ;; Logging
  (org-log-done 'time)
  (org-log-into-drawer t)
  (org-log-redeadline 'note)
  (org-log-reschedule 'note)
  ;; Priorities: [#A]=P1, [#B]=P2, [#C]=P3, none=P4
  (org-priority-highest ?A)
  (org-priority-default ?C)
  (org-priority-lowest  ?C)
  ;; Context tags (like Todoist labels)
  (org-tag-alist
   '((:startgroup . nil)
     ("@work"     . ?w)
     ("@home"     . ?h)
     ("@computer" . ?c)
     ("@phone"    . ?p)
     ("@errand"   . ?e)
     (:endgroup . nil)
     ("recurring" . ?r)
     ("milestone" . ?m) ;. marks a milestone heading (progress + deadline); the Dashboard view and dashboard.org read it
     ("someday"   . ?s)
     ("urgent"    . ?u)))
  (org-tags-exclude-from-inheritance '("milestone")) ;. a task under a milestone is not itself a milestone
  ;; Agenda display
  (org-agenda-span 'day)
  (org-agenda-start-on-weekday nil)
  (org-deadline-warning-days 3)
  (org-agenda-skip-scheduled-if-done t)
  (org-agenda-skip-deadline-if-done t)
  (org-agenda-include-deadlines t)
  (org-agenda-block-separator ?─)
  (org-agenda-time-grid
   '((daily today require-timed)
     (800 1000 1200 1400 1600 1800 2000)
     " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"))
  ;; Capture templates — "i"/"t" here; "e"/"E" (one per me/gcal-calendars entry, see
  ;; me/gcal-capture-entries) and one per me/org-agenda-categories item appended
  (org-capture-templates
   (append
    `(("i" "Inbox — quick add" entry
       (file ,(me/org-file "agenda/inbox.org")) ;. a (file …) target takes a string, not a form — hence the backquote
       "* INBOX %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
       :empty-lines 1)
      ("t" "Task with deadline" entry
       (file ,(me/org-file "agenda/inbox.org"))
       "* INBOX %?\nDEADLINE: %^{Deadline}t\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
       :empty-lines 1))
    (me/gcal-capture-entries) ;. org-gcal's layout: calendar-id property + :org-gcal: drawer; C-c G on it publishes
    (me/org-agenda-capture-entries)))
  ;; Refile targets — one per me/org-agenda-categories item, plus someday.org
  (org-refile-targets (me/org-agenda-refile-entries))
  (org-refile-use-outline-path 'file)
  (org-refile-allow-creating-parent-nodes 'confirm)
  (org-outline-path-complete-in-steps nil)
  (org-refile-target-verify-function (lambda () (not (org-get-todo-state))))
  ;; Habits
  (org-habit-show-habits-only-for-today t)
  (org-habit-graph-column 50)
  ;; Custom agenda views — "W"/"H" (one per me/org-agenda-categories item with has-agenda-view) spliced in below
  (org-agenda-custom-commands
   (append
    '(("d" "Today"
       ((agenda "" ((org-agenda-span 'day)
                    (org-agenda-sorting-strategy '(priority-down category-keep time-up))))
        (todo "NEXT"
              ((org-agenda-overriding-header "Next Actions")
               (org-agenda-sorting-strategy '(priority-down category-keep))))
        (todo "INBOX"
              ((org-agenda-overriding-header "Inbox — needs review")))))
      ("u" "Upcoming (7 days)"
       ((agenda "" ((org-agenda-span 7)
                    (org-agenda-start-on-weekday nil)
                    (org-agenda-sorting-strategy '(priority-down time-up category-keep)))))))
    (me/org-agenda-view-entries)
    (me/org-agenda-dashboard-entries) ;. "D": milestones by deadline, active tasks grouped by outline path, one block per cross-cutting tag
    '(("I" "Inbox Review"
       ((todo "INBOX"
              ((org-agenda-overriding-header "All unprocessed inbox items")
               (org-agenda-sorting-strategy '(ts-up priority-down))))))
      ("A" "All Active"
       ((todo "TODO|NEXT|WAIT"
              ((org-agenda-overriding-header "All active tasks")
               (org-agenda-sorting-strategy '(priority-down todo-state-up category-keep))))))
      ("P" "Priority P1 [#A]"
       ((todo "TODO|NEXT"
              ((org-agenda-overriding-header "P1 — Urgent [#A]")
               (org-agenda-skip-function
                '(org-agenda-skip-entry-if 'notregexp "\\[#A\\]")))))))))
  :config
  (setq org-agenda-files ;. every .org under agenda/ (gcal-*.org included); nil when the root doesn't exist yet
        (let ((dir (me/org-file "agenda")))
          (when (file-directory-p dir)
            (directory-files-recursively dir "\\`[^#].*\\.org\\'"))))
  ;; Babel
  (org-babel-do-load-languages ;. [fix]: a function, not a variable, so it must be called from :config (as ob-mermaid does below); in :custom use-package would set it as an option and never call it
   'org-babel-load-languages
   '((clojure . t)
     (shell . t)))) ;. shell blocks run hledger reports in the ledger notes

;;;; Packages
(use-package org-modern ;> modern looks for Org buffers
  :after org
  :hook
  (org-mode . org-modern-mode)
  (org-agenda-finalize . org-modern-agenda))

(use-package me-dashboard ;> project dashboard: milestones, risk, burn-up — buffer (C-c D), HTML block and agenda view D
  :straight nil ;. local package — local-packages/me-dashboard
  :load-path "local-packages/me-dashboard" ;. the package directory, not the file
  :commands (me/dashboard me/dashboard-export me/org-agenda-dashboard-entries
             me/org-agenda-dashboard-setup me/org-agenda-toggle-group
             me/org-agenda-milestone-prefix org-dblock-write:me-dashboard)) ;. autoloads only: nothing loads until C-c D, the first agenda or an export

(use-package org-super-agenda ;> grouped agenda: section headers from category, tag and outline path
  :after org
  :hook ((org-agenda-mode . org-super-agenda-mode) ;. global mode; first agenda buffer is the right moment to load it
         (org-agenda-finalize . me/org-agenda-dashboard-setup)) ;. outline folding in the Dashboard buffer only (custom.el)
  :config
  (keymap-set org-super-agenda-header-map "TAB" #'me/org-agenda-toggle-group) ;. header map is only live on group header lines, so task lines keep their keys
  (keymap-set org-super-agenda-header-map "<tab>" #'me/org-agenda-toggle-group)) ;. GUI frames send <tab>, which the copied agenda map binds on its own

(use-package org-habit ;> habit consistency graphs in the agenda
  :straight (:type built-in)
  :after org
  :demand t) ;. the require registers habits with org-agenda; nothing else triggers it

(use-package calendar ;> built-in calendar — only the holiday list is ours
  :straight (:type built-in)
  :custom
  (calendar-holidays ;. brazilian national holidays; the stock list is US-centric (calfw shows these in the cells)
   '((holiday-fixed 1 1 "Ano Novo")
     (holiday-easter-etc -47 "Carnaval")
     (holiday-easter-etc -2 "Sexta-feira Santa")
     (holiday-fixed 4 21 "Tiradentes")
     (holiday-fixed 5 1 "Dia do Trabalho")
     (holiday-easter-etc 60 "Corpus Christi")
     (holiday-fixed 9 7 "Independência")
     (holiday-fixed 10 12 "Nossa Senhora Aparecida")
     (holiday-fixed 11 2 "Finados")
     (holiday-fixed 11 15 "Proclamação da República")
     (holiday-fixed 11 20 "Consciência Negra")
     (holiday-fixed 12 25 "Natal"))))

(use-package calfw ;> calendar views (month/2-week/week/day) in a buffer; v2.0 is the haji-ali rewrite (calfw- prefix)
  :commands (calfw-open-calendar-buffer)) ;. opened through me/calendar (C-c C) — sources come from me/org-agenda-categories

(use-package calfw-org) ;> org-agenda entries (scheduled/deadline/timestamps) as calfw items; install only —
                        ;. me/calendar requires it and wraps its collector (me/calendar--org-source, custom.el)

(use-package calfw-blocks ;> time-block day/week views — events drawn as blocks sized by duration, like a GUI calendar
  :straight (:host github :repo "haji-ali/calfw-blocks" ;. not on MELPA; calfw's maintainer's fork of ml729/calfw-blocks
             :branch "develop") ;. master stopped in 2025-10 and overrides calfw--render-toolbar with the pre-2.0 arity (month view dies)
  :custom ;. its calfw-blocks-org.el is NOT loaded: it advises calfw-org-get-timerange with the wrong arity
  (calfw-blocks-initial-visible-time '(7 0))) ;. scroll so the day starts at 07:00 (hours outside 9–17 shrink to one line)

(use-package org-gcal ;> two-way Google Calendar ↔ org: events land in gcal-*.org, so they show up under C-c a and C-c C
  :commands (org-gcal-sync
             org-gcal-fetch
             org-gcal-post-at-point
             org-gcal-delete-at-point)
  :bind (("C-c g" . org-gcal-sync) ;. pull + push managed entries; never automatic — the first run per calendar opens the browser for OAuth
         ("C-c G" . org-gcal-post-at-point)) ;. publish the org entry at point (a captured "e" event) to its calendar
  :init
  (with-eval-after-load 'oauth2-auto (me/gcal-load-credentials)) ;. org-gcal.el requires oauth2-auto first and registers the provider from the id/secret in its last form; this is the only hook that runs in between, whatever command autoloads it
  (setq plstore-cache-passphrase-for-symmetric-encryption t) ;. no GPG key here, so plstore encrypts tokens symmetrically: one passphrase prompt per session, not per token refresh
  :custom ;. plstore's variable is a plain defvar, which is why it is set in :init and not here
  (org-gcal-fetch-file-alist ;. (calendar-id . file) from me/gcal-calendars (custom.el); token store + cache dirs are set by no-littering
   (mapcar (lambda (c) (cons (car c) (cadr c))) me/gcal-calendars))
  (org-gcal-cancelled-todo-keyword "CANCELED")) ;. our keyword has one L; the default "CANCELLED" isn't in org-todo-keywords

(use-package org-roam ;> linked notes under roam/ with a backlinks buffer
  :after org
  :custom
  (org-roam-directory (file-truename (me/org-file "roam"))) ;. roam/ under the org root (me/org-directory, set in local.el)
  (org-roam-node-display-template
   (concat "${title:*} " (propertize "${tags:40}" 'face 'org-tag)))
  (org-roam-capture-templates ;. work-specific entries (employer name/repo) live in me/roam-work-templates, local.el
   (append
    '(("d" "Default" plain "%?"
       :target (file+head "resources/${slug}.org"
                          ":PROPERTIES:\n:ID: %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: \n#+date: %<%Y-%m-%d>\n")
       :unnarrowed t
       :finalize me/org-roam-capture-finalize) ;. lands in the new note and refreshes dirvish-side; :jump-to-captured alone jumps too late for dirvish-side-follow-mode
      ("l" "Aprendizado" plain "%?"
       :target (file+head "resources/learn/${slug}.org"
                          ":PROPERTIES:\n:ID: %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :learning:\n#+date: %<%Y-%m-%d>\n")
       :unnarrowed t
       :finalize me/org-roam-capture-finalize)
      ("p" "Pessoal" plain "%?"
       :target (file+head "resources/home/${slug}.org"
                          ":PROPERTIES:\n:ID: %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :personal:\n#+date: %<%Y-%m-%d>\n")
       :unnarrowed t
       :finalize me/org-roam-capture-finalize)
      ("r" "Receita" plain
       "* Ingredientes\n%?\n\n* Modo de preparo\n"
       :target (file+head "resources/home/cooking/${slug}.org"
                          ":PROPERTIES:\n:ID: %(org-id-new)\n:END:\n#+title: ${title}\n#+filetags: :personal:cooking:\n#+date: %<%Y-%m-%d>\n")
       :unnarrowed t
       :finalize me/org-roam-capture-finalize))
    me/roam-work-templates))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture))
  :config (org-roam-db-autosync-mode))

(use-package org-re-reveal ;> export org to reveal.js (HTML5) presentations
  :after org
  :demand t) ;. must load eagerly to register the backend with org-export
(use-package ob-json ;> json source blocks: C-c C-c pretty-prints through jq, json-ts-mode highlights
  :straight nil ;. local file under local-packages/
  :load-path "local-packages" ;. the directory (relative to user-emacs-directory) — naming the .el file breaks require
  :demand t ;. registers org-babel-execute:json and the src mode before the first org file opens
  :after org)
(use-package ob-mermaid ;> execute org babel mermaid
  :after org
  :demand t ;. load immediately after org (required to register the babel backend)
  :custom
  (ob-mermaid-cli-path me/mermaid-cli-path) ;. [fix]: mermaid-cli 11.x strips spaces inside multi-word node labels under htmlLabels:false, 10.9.1 does not; pin a 10.9.1 binary in local.el (see local.el.example) when the system mmdc is 11.x
  (ob-mermaid-default-config-file ;. htmlLabels:false — labels as plain SVG text, no foreignObject
   (expand-file-name "mermaid-config-emacs.json" user-emacs-directory))
  :config
  (setq org-babel-default-header-args:mermaid ;. theme, background, and system chromium (mmdc couldn't find its own chrome-headless-shell)
        `((:results . "file") (:exports . "results") ;. ob-mermaid.el's own defaults — without these, Org drops the result and never inserts the image
          (:theme . "dark") (:background-color . "transparent")
          (:puppeteer-config-file . ,(expand-file-name "mermaid-puppeteer-config.json" user-emacs-directory))))
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((mermaid . t)
     (scheme . t))))
(use-package htmlize ;> colours source blocks for ox-html (inline-css output)
  :after org
  :demand t)
(use-package ox-html ;> HTML export; the theme comes from each file's #+HTML_THEME keyword
  :straight (:type built-in)
  :after (org htmlize)
  :demand t
  :custom
  (org-html-htmlize-output-type 'inline-css) ;. inline-style code highlighting — survives clients/CMS that strip <style>
  (org-html-validation-link nil) ;. remove the "Validate XHTML" link from the footer
  (org-html-postamble nil) ;. remove "Created by Org/Emacs" from the footer
  (org-html-doctype "html5")
  (org-html-html5-fancy t) ;. semantic <section>/<figure>
  (org-export-with-toc nil)
  (org-export-with-section-numbers nil) ;. external clients rarely want "1.2.3" numbering
  (org-html-toplevel-hlevel 2)
  (org-html-head-include-default-style nil) ;. swap ox-html's default light CSS for the theme selected via #+HTML_THEME
  :config
  ;; me/org-html-apply-theme and me/org-html-inline-images live in custom.el;
  ;; this block just wires them into the export pipeline.
  (add-hook 'org-export-before-processing-functions
            #'me/org-html-apply-theme) ;. pick CSS/postamble from the file's #+HTML_THEME keyword (see ox-html-themes/)
  (add-to-list 'org-export-filter-final-output-functions
               #'me/org-html-inline-images))
;;; Keybinds
;;;; Settings
(keymap-global-set "C-c w"   'me/setup-workspaces) ;> open a tab for each repo in me/workspace-default-repos
(keymap-global-set "C-c o"   'me/open-project-workspace) ;> open a new repo in an isolated tab (magit + dirvish side panel)
(keymap-global-set "C-c t"   'me/open-terminal) ;> terminal rooted at the project
(keymap-global-set "C-c r"   'me/claude-review-branch) ;> claude code-review current branch
(keymap-global-set "M-;"     'comment-or-uncomment-region) ;> comment and uncomment lines
(keymap-global-set "C-c a"   'org-agenda) ;> agenda views
(keymap-global-set "C-c c"   'org-capture) ;> capture templates
(keymap-global-set "C-c D"   'me/dashboard) ;> project dashboard buffer: milestones, risk, burn-up (C-c a D is the task list)
(keymap-global-set "C-c C"   'me/calendar) ;> calfw week calendar of every agenda file (C-c c is capture)
(keymap-global-set "C-c e"   'me/open-config) ;> open init.el
(keymap-global-set "C-g"     'me/keyboard-quit-dwim) ;> closes minibuffer even when unfocused
(keymap-global-set "C-x t 2" 'me/new-scratch-tab) ;> new tab on *scratch*
;;;; Packages
(use-package which-key ;> display available keybindings in popup
  :straight (:type built-in)
  :hook (after-init . which-key-mode)
  :custom
  (which-key-side-window-location 'bottom)
  (which-key-sort-order #'which-key-key-order-alpha)
  (which-key-add-column-padding 1)
  (which-key-min-display-lines 6)
  (which-key-side-window-slot -10)
  (which-key-side-window-max-height 0.25)
  (which-key-idle-delay 0.8)
  (which-key-max-description-length 25)
  (which-key-separator " → "))
