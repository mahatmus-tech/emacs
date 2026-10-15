;;; custom.el --- Mahatmus Emacs Configuration -*- lexical-binding: t; init-panel: t -*-
;;; Outline
(defun outline-copy-visible (beg end) ;> copy helper — folding, faces and notes come from init-panel (init.el)
  "Copy only visible text in region, skipping folded outline sections."
  (interactive "r")
  (let ((result ""))
    (while (< beg end)
      (when (get-char-property beg 'invisible)
        (setq beg (next-single-char-property-change beg 'invisible nil end)))
      (let ((next (next-single-char-property-change beg 'invisible nil end)))
        (setq result (concat result (buffer-substring beg next)))
        (setq beg next)))
    (kill-new result)
    (message "Visible region copied (%d chars)" (length result))))
;;; Utils
(defun me/keyboard-quit-dwim () ;> smart C-g: closes minibuffer even when unfocused
  "Quit like `keyboard-quit', but also abort an unfocused minibuffer.
With an active region or no minibuffer, behave exactly like C-g; in a
*Completions* window close it; otherwise abort the pending minibuffer."
  (interactive)
  (cond
   ((region-active-p)                      (keyboard-quit))
   ((derived-mode-p 'completion-list-mode) (delete-completion-window))
   ((> (minibuffer-depth) 0)               (abort-recursive-edit))
   (t                                      (keyboard-quit))))

(defun me/flymake-elisp-setup () ;> flymake for elisp: no checkdoc, full load-path
  "Tune Flymake's Emacs Lisp backends: drop checkdoc, inherit `load-path'."
  (remove-hook 'flymake-diagnostic-functions #'elisp-flymake-checkdoc t)
  (setq-local elisp-flymake-byte-compile-load-path (cons "./" load-path)))

(defun me/open-config () ;> shortcut to init.el
  "Open init.el in the current window."
  (interactive)
  (find-file (expand-file-name "init.el" user-emacs-directory)))

(defun me/save-frame-colors (&rest _) ;> persist theme colors for next startup
  "Write current theme's frame params to frame-colors.el."
  (when (display-graphic-p) ;> skip in batch/TTY — font param would be "tty"
    (let ((bg     (face-background 'default    nil t))
          (fg     (face-foreground 'default    nil t))
          (cursor (face-background 'cursor     nil t))
          (border (face-background 'border     nil t))
          (mouse  (frame-parameter nil 'mouse-color))
          (font   (frame-parameter nil 'font))
          (alpha  (frame-parameter nil 'alpha-background))
          (file   (expand-file-name "frame-colors.el" user-emacs-directory)))
      (when (and bg fg
                 (not (string-prefix-p "unspecified" bg)) ;> skip terminal pseudo-colors
                 (not (string-prefix-p "unspecified" fg)))
        (with-temp-file file
          (insert ";; -*- lexical-binding: t; -*-\n") ;. [fix]: Emacs 31 warns on `load' without this cookie
          (insert (format "(add-to-list 'default-frame-alist '(background-color . %S))\n" bg))
          (insert (format "(add-to-list 'default-frame-alist '(foreground-color . %S))\n" fg))
          (when cursor (insert (format "(add-to-list 'default-frame-alist '(cursor-color     . %S))\n" cursor)))
          (when border (insert (format "(add-to-list 'default-frame-alist '(border-color     . %S))\n" border)))
          (when mouse  (insert (format "(add-to-list 'default-frame-alist '(mouse-color      . %S))\n" mouse)))
          (when font   (insert (format "(add-to-list 'default-frame-alist '(font             . %S))\n" font)))
          (when alpha  (insert (format "(add-to-list 'default-frame-alist '(alpha-background . %S))\n" alpha))))))))

(advice-add 'load-theme :after #'me/save-frame-colors) ;> pre render last theme to avoid flash

(defun me/omarchy-read-colors (file) ;> flat `key = "#hex"` lines of an Omarchy colors.toml -> alist of strings
  "Return an alist of (KEY . VALUE) strings read from the palette FILE.
`colors.toml' is flat and string-only, so a line scan is enough."
  (with-temp-buffer
    (insert-file-contents file)
    (let (alist)
      (while (re-search-forward "^[ \t]*\\([a-z_]+\\)[ \t]*=[ \t]*\"\\([^\"]*\\)\"" nil t)
        (push (cons (match-string 1) (match-string 2)) alist))
      (nreverse alist))))

(defun me/omarchy--luminance (color) ;. cheap perceived brightness, 0..1; nil when COLOR is not parseable
  (when-let* ((rgb (color-name-to-rgb color)))
    (+ (* 0.299 (nth 0 rgb)) (* 0.587 (nth 1 rgb)) (* 0.114 (nth 2 rgb)))))

(defun me/omarchy-palette-overrides (colors) ;> colors.toml alist -> Modus palette overrides, same slot mapping Omarchy renders in Neovim
  "Return a Modus palette-overrides list built from COLORS (see `me/omarchy-read-colors').
Mapping mirrors the bundled omarchy.el Omarchy-4 themes (aether slots).  A
key missing from COLORS falls back along its chain; a slot with no value
at all is left to the Modus base."
  (let* ((light (equal (cdr (assoc "mode" colors)) "light"))
         (get (lambda (&rest keys) (seq-some (lambda (k) (cdr (assoc k colors))) keys)))
         (bg    (funcall get "background"))
         (fg    (funcall get "foreground"))
         (dbg   (funcall get "dark_background" "background"))
         (ddbg  (funcall get "darker_background" "dark_background" "background"))
         (lbg   (funcall get "lighter_background" "background"))
         (sel   (funcall get "selection"))
         (muted (funcall get "muted" "dark_foreground"))
         (accent (funcall get "accent" "blue"))
         ;; [fix]: some palettes (aether) use a foreground-like `selection'; as a region
         ;; background it makes text unreadable, so only trust it when it is nearer bg than fg
         (region (let ((ls (and sel (me/omarchy--luminance sel)))
                       (lb (and bg (me/omarchy--luminance bg)))
                       (lf (and fg (me/omarchy--luminance fg))))
                   (if (and ls lb lf (< (abs (- ls lb)) (abs (- ls lf)))) sel lbg)))
         (heading (list accent
                        (funcall get "red") (funcall get "yellow") (funcall get "yellow")
                        (funcall get "green") (funcall get "blue") (funcall get "magenta")
                        (funcall get "red") (funcall get "yellow")))
         (table
          `((,bg bg-main)
            (,dbg bg-dim bg-mode-line-inactive bg-line-number-inactive)
            (,ddbg bg-inactive)
            (,lbg bg-active border bg-hl-line bg-paren-match bg-search-lazy bg-hover
                  bg-completion bg-mode-line-active border-mode-line-active)
            (,region bg-region)
            (,fg fg-main fg-region fg-mode-line-active variable variable-use identifier
                 operator fg-line-number-active)
            (,muted fg-dim comment fg-mode-line-inactive punctuation fg-line-number-inactive)
            (,(if light (funcall get "dark_foreground") (funcall get "light_foreground")) fg-alt)
            (,(funcall get "bright_foreground" "foreground") cursor)
            (,(funcall get "bright_magenta" "magenta") keyword)
            (,(funcall get "blue") fnname fnname-call name fg-link info modeline-info)
            (,(funcall get "yellow") type warning modeline-warning bg-search-current)
            (,(funcall get "bright_yellow" "yellow") constant)
            (,(funcall get "orange" "yellow") number)
            (,(funcall get "green") string docstring)
            (,(funcall get "bright_cyan" "cyan") property)
            (,(funcall get "cyan") builtin preprocessor)
            (,(funcall get "bright_red" "red") err modeline-err)
            (,(funcall get "magenta") fg-prompt)))
         result)
    (dolist (row table)
      (when (car row)
        (dolist (slot (cdr row)) (push (list slot (car row)) result))))
    (let ((i 0))
      (dolist (h heading)
        (when h (push (list (intern (format "fg-heading-%d" i)) h) result))
        (setq i (1+ i))))
    (nreverse result)))

(defun me/omarchy-derive-theme (file) ;> load the stock Modus theme (by `mode') recolored from the Omarchy palette FILE
  "Derive and enable a theme from the Omarchy `colors.toml' FILE.
Uses the per-theme Modus overrides, never the common ones: those leak
into every bundled omarchy.el theme.  Any failure messages the reason and
enables `omarchy-default-theme' instead."
  (condition-case err
      (let ((colors (me/omarchy-read-colors file)))
        (unless (and (assoc "background" colors) (assoc "foreground" colors))
          (error "no background/foreground in palette"))
        (let* ((light (equal (cdr (assoc "mode" colors)) "light"))
               (base (if light 'modus-operandi 'modus-vivendi)))
          (set (intern (format "%s-palette-overrides" base))
               (me/omarchy-palette-overrides colors))
          (mapc #'disable-theme custom-enabled-themes)
          (load-theme base :no-confirm)
          (message "Theme set to %s derived from %s" base file)))
    (error
     (message "omarchy: cannot derive theme from %s: %s" file (error-message-string err))
     (when (bound-and-true-p omarchy-default-theme)
       (mapc #'disable-theme custom-enabled-themes)
       (load-theme omarchy-default-theme :no-confirm)))))

(defun me/omarchy-user-theme-entries () ;> (slug . thunk) for each user theme with a colors.toml, ready for `omarchy-theme-map'
  "Return `omarchy-theme-map' entries for themes in ~/.config/omarchy/themes/.
Only directories (or symlinks to them) holding a readable `colors.toml'."
  (let ((dir (expand-file-name "~/.config/omarchy/themes/")))
    (when (file-directory-p dir)
      (delq nil
            (mapcar (lambda (d)
                      (let ((f (expand-file-name "colors.toml" d)))
                        (when (file-readable-p f)
                          (cons (file-name-nondirectory d)
                                (lambda () (me/omarchy-derive-theme f))))))
                    (directory-files dir t "\\`[^.]"))))))

(defvar me/editor-font-families ;> preference order; the first one the display has wins
  '("JetBrainsMono Nerd Font Mono" "JetBrainsMono Nerd Font")
  "Editor font families, best first.  The second is what Omarchy's base font package installs.")

(defvar me/editor-font-height 120 ;> fixed size, 1/10 pt (12pt)
  "Height of the `default' face; never taken from the Omarchy desktop.")

(defun me/set-editor-font () ;> pin the default face to the configured family/height; no-op without a graphic display
  "Apply `me/editor-font-families' and `me/editor-font-height' to the `default' face.
Return the family applied, or nil.  Messages when the preferred family is
missing so the fallback is never silent."
  (when (display-graphic-p)
    (let* ((available (font-family-list))
           (family (seq-find (lambda (f) (member f available)) me/editor-font-families)))
      (cond
       ((null family)
        (message "Editor font: none of %S installed, keeping the display default" me/editor-font-families)
        nil)
       (t
        (unless (equal family (car me/editor-font-families))
          (message "Editor font: %s not installed, using %s" (car me/editor-font-families) family))
        (set-face-attribute 'default nil :family family :height me/editor-font-height)
        family)))))

(defun me/new-scratch-tab () ;> new tab with scratch buffer
  "Open a new tab showing a fresh *scratch* buffer (bound to C-x t 2)."
  (interactive)
  (tab-bar-new-tab)
  (scratch-buffer))

(defun me/savehist-strip-kill-ring () ;> [fix]: kill-ring text props (syntax-table char-tables) print as unreadable #N# and break savehist-mode (init.el, savehist)
  "Drop text properties from `kill-ring' before savehist writes it.
Entries copied out of org src blocks carry circular `syntax-table'
char-tables; the saved file then fails to read back, which aborts
`after-init-hook' and with it vertico, corfu, doom-modeline...
Hooked on `savehist-save-hook'."
  (setq kill-ring (mapcar #'substring-no-properties kill-ring)))
;;; Workspace
(defun me/tab-bar-refresh-focus-highlight (&rest _) ;> border on the focused tab tracks the active theme
  "Set `tab-bar-tab's box border color from the active `mode-line' face.
Wired in init.el to run once at startup and again on every theme change,
so the border always matches whichever theme is active — regardless of
which theme package (or none) applied it."
  (set-face-attribute 'tab-bar-tab nil
                       :box (list :line-width 2
                                  :color (face-attribute 'mode-line :background nil t))))

(defvar me/workspace-default-repos ;> repos auto-opened by me/setup-workspaces
  (list user-emacs-directory)) ;. this config itself; add your own repos in local.el (gitignored, see local.el.example)

(defvar me/forge-owned-accounts nil ;> feeds forge-owned-accounts (Version Control section, init.el)
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/open-repo-workspace (repo-dir) ;> shared logic: tabspace + magit + dirvish side panel for one repo
  "Open REPO-DIR in its own tabspace, named after the repo directory.
Shows a Magit status buffer with a Dirvish side panel rooted at the repo.
Returns the tabspace name."
  (let* ((root (file-name-as-directory (expand-file-name repo-dir)))
         (name (file-name-nondirectory (directory-file-name root)))
         (new? (not (member name (tabspaces--list-tabspaces))))) ;. a fresh tab still carries the buffer inherited from tab-new below
    (when (file-directory-p root)
      (tabspaces-switch-or-create-workspace name)
      (delete-other-windows) ;> the side window survives: no-delete-other-windows
      (let ((default-directory root))
        (magit-status-setup-buffer root) ;> main window
        (save-selected-window ;> dirvish-side selects its window; keep focus on magit
          (dirvish-side root))) ;. sessions are per tab (dirvish--scopes), so each workspace keeps its own panel
      (when new? ;. [fix]: tabspaces--tab-post-open-function resets the buffer-list right after
        (tabspaces-reset-buffer-list))) ;. tab-new, before magit/dirvish-side replace the inherited buffer — that
                                        ;. buffer stays "local" forever unless the reset runs again once we're done
    name))

(defun me/setup-workspaces () ;> personal workspace main function
  "Open a tabspace for each repo in `me/workspace-default-repos'."
  (interactive)
  (require 'dirvish-side)
  (require 'forge)
  (require 'magit)
  (let (first-name)
    (dolist (repo me/workspace-default-repos)
      (let ((name (me/open-repo-workspace repo)))
        (unless first-name (setq first-name name))))
    (when first-name (tabspaces-switch-or-create-workspace first-name))))

(defun me/open-project-workspace (project-dir) ;> open a new repo in an isolated tab (Magit + Dirvish side panel)
  "Open PROJECT-DIR in a new tabspace with magit and a dirvish side panel."
  (interactive (list (read-directory-name "Repo: " "~/repos/")))
  (require 'dirvish-side)
  (require 'magit)
  (let ((name (me/open-repo-workspace project-dir)))
    (message "Workspace: %s" name)))

(defvar tabspaces--session-list) ;> declared only — defined by tabspaces, used inside the functions below
(defvar me/tabspaces--restored-side-panels nil ;> (tab-name . dir) pairs queued while a tabspaces session restores
  "Dirvish side panels to rebuild once `tabspaces-restore-session' has recreated the tabs.")

(defun me/tabspaces-side-panel-record (buffer) ;> session save: a dirvish side panel is stored as its directory only
  "Return a tabspaces session record for BUFFER when it is a dirvish side panel, else nil."
  (with-current-buffer buffer
    (when (and (derived-mode-p 'dired-mode)
               (string-prefix-p " *SIDE :: " (buffer-name))) ;. dirvish-side names its buffers like this (dirvish-side-root-conf)
      (list :kind 'dirvish-side :dir default-directory))))

(defun me/tabspaces-side-panel-defer (record) ;> session restore: queue the panel — the tab's windows aren't final yet
  "Queue RECORD's side panel for `me/tabspaces-restore-side-panels'.  Returns nil: no buffer now."
  (push (cons (alist-get 'name (tab-bar--current-tab)) (plist-get record :dir))
        me/tabspaces--restored-side-panels)
  nil)

(defun me/tabspaces-restore-side-panels (&rest _) ;> after restore: rebuild the queued panels once the command loop is back
  "Schedule `me/tabspaces--rebuild-side-panels' for the queued side panels.
A timer rather than a direct call: at startup the restore runs inside `after-init-hook',
where `dirvish-side' only yields a plain dired buffer (no session, no data, sentinel errors)."
  (when me/tabspaces--restored-side-panels
    (run-at-time 0 nil #'me/tabspaces--rebuild-side-panels)))

(defun me/tabspaces--rebuild-side-panels () ;> one fresh dirvish-side per tab that had one, then land on the first tab
  "Recreate the dirvish side panels queued during `tabspaces-restore-session'."
  (require 'dirvish-side)
  (let ((tabs (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar-tabs))))
    (pcase-dolist (`(,tab . ,dir) (nreverse me/tabspaces--restored-side-panels))
      (when (and (member tab tabs) (file-directory-p dir)) ;. switching to an unknown tab name would create it
        (tab-bar-switch-to-tab tab)
        (save-selected-window (dirvish-side dir)))) ;. same call me/open-repo-workspace makes; keeps focus on the main window
    (setq me/tabspaces--restored-side-panels nil)
    (let ((first (cadr (car tabspaces--session-list)))) ;. restore ends on the last saved tab; C-c w lands on the first repo
      (when (member first tabs) (tab-bar-switch-to-tab first)))))

(defun me/dirvish-side-resync (win file) ;> deferred half of me/dirvish-side-auto-jump-defer — see there
  "Reposition WIN on FILE and refresh the panel, called from the command loop."
  (when (window-live-p win)
    (with-selected-window win
      (if dirvish-side-auto-expand
          (dirvish-subtree-expand-to file)
        (dired-goto-file file))
      (dirvish--redisplay))))

(defun me/dirvish-side-auto-jump-defer (&rest _) ;> [fix]: dirvish-side--auto-jump moves point before the command loop resumes
  "Schedule `me/dirvish-side-resync' for the file just opened, deferred to the command loop.
`:after' advice on `dirvish-side--auto-jump' (init.el, dirvish :config).
Run from `buffer-list-update-hook', that function's own goto/expand leaves the
panel's point on the right file but its displayed index/highlight goes stale —
same class of bug as the after-init-hook case in gotchas.md (dirvish-side ops
run synchronously outside the command loop don't fully take effect); same fix."
  (when-let* ((win (dirvish-side--session-visible-p))
              (file buffer-file-name))
    (run-at-time 0 nil #'me/dirvish-side-resync win file)))

(defun me/dirvish-side-restamp-tab (window) ;> [fix]: closing an earlier tab shifts every later tab's index, stranding the panel
  "Before `dirvish-winbuf-change-h' runs on WINDOW, refresh a dirvish-side
buffer's stamped `:tab' to the current `tab-bar--current-tab-index'.
Each tabspace owns one exclusive dirvish-side session that never migrates
between tabs, so the stale-tab branch `dirvish-winbuf-change-h' takes
is always a false positive here: it kills the panel buffer and rebuilds a
plain (non-side) dirvish session in its window, clobbering whatever else
was in that tab's layout (claude's ghostel buffer, say). `:before' advice
on `dirvish-winbuf-change-h' (init.el, dirvish :config)."
  (when-let* ((buf (window-buffer window))
              ((string-prefix-p " *SIDE :: " (buffer-name buf))))
    (with-current-buffer buf
      (dirvish-prop :tab (tab-bar--current-tab-index)))))

(defun me/dirvish-side-unfix-width (orig &rest args) ;> [fix]: dirvish pins the panel width, so dragging its border does nothing
  "Call ORIG (`dirvish--new') with ARGS, minus `:size-fixed' for side sessions.
Dirvish copies `:size-fixed' into the panel buffer's `window-size-fixed',
which makes `window-resize' refuse width changes. Dropping it leaves the
panel at `dirvish-side-width' initially but draggable afterwards. `:around'
advice on `dirvish--new' (init.el, dirvish :config)."
  (apply orig (if (eq (plist-get args :type) 'side)
                  (cl-loop for (k v) on args by #'cddr
                           unless (eq k :size-fixed) append (list k v))
                args)))

;; dirvish-define-attribute is a package macro, so it can only expand once dirvish is loaded
(with-eval-after-load 'dirvish ;> side panel: hover a truncated name to read it whole (init.el, dirvish-side-attributes)
  (dirvish-define-attribute full-name-tip
    "Put the full name in `help-echo' of a filename that does not fit the window."
    (when (and f-beg f-end)
      (if (<= (+ (or (get-text-property l-beg 'line-prefix) 0) ;. subtree indent, in columns
                 4 ;. room taken by the vc-state, icon and collapse columns (estimate)
                 (string-width f-str))
              w-width)
          (when (equal (get-text-property f-beg 'help-echo) f-str) ;. widened again: give dired's own hint back
            (put-text-property f-beg f-end 'help-echo "mouse-2: visit this file in other window"))
        (put-text-property f-beg f-end 'help-echo f-str)))
    nil))

(defun me/dirvish-side-open-or-expand () ;> RET in the side panel expands directories in place, like TAB (dirvish-mode-map, init.el)
  "In a dirvish-side session, toggle the subtree at point if it is a
directory; visit the file otherwise. Leaves fullscreen dirvish untouched."
  (interactive)
  (if-let* ((dv (dirvish-curr))
            ((eq (dv-type dv) 'side))
            (file (dired-get-filename nil t))
            ((file-directory-p file)))
      (dirvish-subtree-toggle)
    (dired-find-file)))

(defun me/dirvish-mouse-open-or-expand (event) ;> mouse version of `me/dirvish-side-open-or-expand'
  "Move point to EVENT's position, then run `me/dirvish-side-open-or-expand'.
Outside a side session, fall back to `dired-mouse-find-file-other-window'
instead: dired's `mouse-face' + `[follow-link]' convention silently turns
a real mouse-1 click on a filename into a mouse-2 event, so this is the
handler that actually runs for a click there, and fullscreen dirvish's
click-opens-in-other-window behavior must stay unaffected."
  (interactive "e")
  (mouse-set-point event)
  (if-let* ((dv (dirvish-curr))
            ((eq (dv-type dv) 'side)))
      (me/dirvish-side-open-or-expand)
    (dired-mouse-find-file-other-window event)))

(defun me/tabspaces-skip-terminal-record (buffer) ;> session save: terminals (ghostel, claude) would only come back as empty shells
  "Return a no-op session record for BUFFER when it is a terminal, else nil."
  (with-current-buffer buffer
    (when (derived-mode-p 'ghostel-mode)
      (list :kind 'skip :name (buffer-name)))))

(defun me/tabspaces-strip-window-states (&rest _) ;> session restore: buffers only — saved layouts fight dirvish's side windows
  "Drop the window-state of every tab in `tabspaces--session-list' so only buffers are restored,
then make the first saved tab the current one so the restore loop starts there: reuse it if it
exists, rename a pristine startup tab, or open a fresh tab next to whatever is being edited."
  (dolist (tab tabspaces--session-list)
    (when (cddr tab) (setcar (cddr tab) nil)))
  (when-let* ((first (cadr (car tabspaces--session-list)))
              (names (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar-tabs))))
    (cond ((member first names) (tab-bar-switch-to-tab first)) ;. the loop parks a placeholder buffer in the current tab first — keep it out of the user's tab
          ((and (= 1 (length names)) ;. fresh Emacs still on *scratch*: otherwise the initial tab is left behind with the placeholder
                (equal (buffer-name (window-buffer)) "*scratch*")) ;. window-buffer, not current-buffer — a server/minibuffer call must still see the real tab
           (tab-bar-rename-tab first))
          (t (let ((tab-bar-new-tab-choice "*scratch*")) (tab-bar-new-tab)) ;. Emacs opened on a file: leave that tab alone
             (tab-bar-rename-tab first)))))

(defun me/open-terminal (&optional arg) ;> bash terminal at project root
  "Open (or reuse) a ghostel terminal at the current project's root.
The buffer is renamed \"term: <project>\" so several projects can each keep one.
With prefix ARG (\\[universal-argument]) always start a new instance."
  (interactive "P")
  (let ((buf (ghostel-project arg)))
    (with-current-buffer buf
      (rename-buffer (format "term: %s"
                             (file-name-nondirectory
                              (directory-file-name default-directory)))
                     t))))

(defun me/claude-review-branch () ;> code review of the current branch via claude
  "Open Claude Code and send /code-review for the current branch."
  (interactive)
  (claude-code-ide)
  (run-at-time 2 nil
               (lambda ()
                 (claude-code-ide-send-prompt "/code-review"))))

(defun me/org-roam-capture-finalize () ;> :finalize for org-roam-capture-templates, see init.el
  "Switch to the captured note and refresh `dirvish-side' to track it.
`:jump-to-captured' alone jumps too late — after `org-capture-after-finalize-hook'
already ran with the pre-capture buffer restored — so `dirvish-side-follow-mode'
never sees the new file; do the switch here instead. `dired-auto-revert-buffer'
is nil, so even a correct jump reuses a stale cached listing for the target
directory (missing the just-created file) unless reverted by hand."
  (let ((target (org-capture-get :buffer)))
    (switch-to-buffer target)
    (when (fboundp 'dirvish-side--auto-jump)
      (dirvish-side--auto-jump)
      (when-let* ((win (dirvish-side--session-visible-p))
                  (file (buffer-file-name target)))
        (with-selected-window win
          (revert-buffer nil t)
          (dired-goto-file file))))))

;;; Version Control
(defun my/pr-review-forge-at-point () ;> C-c C-r in a forge topic: open that MR in pr-review, else prompt for one
  "Open the current forge pull request in pr-review.
Uses the `forge-pullreq-p' predicate and `slot-value' rather than
`cl-typep'/`oref': neither cl-lib nor eieio is loaded when this file is."
  (interactive)
  (let ((topic (forge-current-topic)))
    (if (forge-pullreq-p topic)
        (let* ((repo   (forge-get-repository topic))
               (host   (slot-value repo 'githost))
               (owner  (slot-value repo 'owner))
               (name   (slot-value repo 'name))
               (number (slot-value topic 'number)))
          (pr-review-open host owner name number))
      (call-interactively #'pr-review))))
;;; Org
(defvar me/org-directory "~/org" ;> root of every org path below (agenda/, roam/) — the real one is set in local.el
  "Org root directory. Generic default; set yours in `local.el' (gitignored, see local.el.example).")

(defun me/org-file (relative) ;> RELATIVE under me/org-directory, expanded at call time — i.e. after local.el loaded
  "Return RELATIVE expanded under `me/org-directory'."
  (expand-file-name relative me/org-directory))

(defvar me/mermaid-cli-path (executable-find "mmdc") ;> mmdc for ob-mermaid; nil falls back to ob-mermaid's own PATH lookup; pin one in local.el
  "Path to the mermaid CLI. Override in `local.el' to pin a specific version (see local.el.example).")

(defvar me/org-agenda-categories ;> (key label file has-agenda-view face) — file is relative to me/org-directory; drives capture
  '(("w" "Work"  "agenda/work.org"  t   font-lock-function-name-face) ;. templates, refile targets, per-category agenda views, and the calendar source color
    ("h" "Home"  "agenda/home.org"  t   font-lock-string-face) ;. (a face, so it follows the theme)
    ("l" "Learn" "agenda/learn.org" nil font-lock-type-face)))

(defun me/org-agenda-capture-entries () ;> one "<Label> task" capture template per category
  "Build an `org-capture-templates' entry for each `me/org-agenda-categories' item."
  (let (result)
    (dolist (cat me/org-agenda-categories (nreverse result))
      (let ((key (nth 0 cat))
            (label (nth 1 cat))
            (file (me/org-file (nth 2 cat))))
        (push
         (list key (format "%s task" label) 'entry
               (list 'file+headline file "Inbox")
               "* INBOX %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
               :empty-lines 1)
         result)))))

(defun me/org-agenda-refile-entries () ;> refile target per category, plus the someday.org catch-all
  "Build `org-refile-targets' entries for each `me/org-agenda-categories' item."
  (let (result)
    (dolist (cat me/org-agenda-categories)
      (push (cons (me/org-file (nth 2 cat)) '(:maxlevel . 2)) result))
    (append (nreverse result)
            (list (cons (me/org-file "agenda/someday.org") '(:maxlevel . 1))))))

(defun me/org-agenda-view-entries () ;> one "<Label> tasks" agenda view per category flagged with has-agenda-view
  "Build `org-agenda-custom-commands' entries for categories that want a dedicated view."
  (let (result)
    (dolist (cat me/org-agenda-categories (nreverse result))
      (when (nth 3 cat)
        (let ((key (upcase (nth 0 cat)))
              (label (nth 1 cat))
              (file (me/org-file (nth 2 cat))))
          (push
           (list key label
                 (list
                  (list 'todo "TODO|NEXT|WAIT"
                        (list
                         (list 'org-agenda-files (list 'quote (list file)))
                         (list 'org-agenda-overriding-header (format "%s tasks" label))
                         '(org-agenda-sorting-strategy '(priority-down todo-state-up))))))
           result))))))

(defvar me/gcal-calendars nil ;> (calendar-id file label face) — one Google calendar ↔ one org file; drives org-gcal-fetch-file-alist
  "Empty by default — set in `local.el' (gitignored, see local.el.example).") ;. and its calfw source color, and the generated gcal capture templates (me/gcal-capture-entries)

(defvar me/roam-work-templates nil ;> spliced into org-roam-capture-templates (Org → Packages, init.el)
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/gcal-load-credentials () ;> org-gcal's OAuth client id/secret come from ~/.authinfo (machine org-gcal login ID password SECRET)
  "Set `org-gcal-client-id' and `org-gcal-client-secret' from `auth-sources'."
  (let ((entry (car (auth-source-search :host "org-gcal" :max 1 :require '(:user :secret)))))
    (unless entry
      (user-error "No \"machine org-gcal login <client-id> password <secret>\" line in %s" auth-sources))
    (setq org-gcal-client-id (plist-get entry :user) ;. set before org-gcal.el loads: its last form registers the oauth2-auto provider from these
          org-gcal-client-secret (auth-info-password entry))))

(defun me/gcal-capture-entries () ;> one "Event — Google Calendar (<label>)" capture template per me/gcal-calendars entry
  "Build an `org-capture-templates' entry for each `me/gcal-calendars' item.
First entry is bound to \"e\", second to \"E\" — matches the two-account
\(personal/work) case this was written for; a third entry errors rather
than picking an arbitrary key."
  (let ((keys '("e" "E")) result)
    (dolist (cal me/gcal-calendars (nreverse result))
      (unless keys
        (user-error "me/gcal-capture-entries: add a capture key for a 3rd+ me/gcal-calendars entry"))
      (let ((calendar-id (nth 0 cal))
            (file (nth 1 cal))
            (label (nth 2 cal))
            (key (pop keys)))
        (push
         (list key
               (format "Event — Google Calendar (%s)" label) 'entry
               (list 'file file)
               (format "* %%^{Evento}\n:PROPERTIES:\n:calendar-id: %s\n:END:\n:org-gcal:\n%%^T\n%%?\n:END:\n" calendar-id)
               :empty-lines 1 :jump-to-captured t)
         result)))))

(defun me/calendar-sources () ;> one calfw source per category and per Google calendar (its face color) + a grey one for the rest
  "Build the `calfw-source' list for `me/calendar' from `me/org-agenda-categories' and `me/gcal-calendars'."
  (let ((rest (mapcar #'expand-file-name (org-agenda-files)))
        sources)
    (pcase-dolist (`(,label ,file ,face)
                   (append (mapcar (lambda (c) (list (nth 1 c) (me/org-file (nth 2 c)) (nth 4 c))) me/org-agenda-categories)
                           (mapcar (lambda (c) (list (nth 2 c) (nth 1 c) (nth 3 c))) me/gcal-calendars)))
      (setq file (expand-file-name file))
      (setq rest (delete file rest))
      (push (me/calendar--org-source (list file) label (me/calendar--color face))
            sources))
    (when rest ;. inbox.org, someday.org… — anything dated there still shows up
      (push (me/calendar--org-source rest "Other"
                                     (me/calendar--color 'font-lock-comment-face))
            sources))
    (nreverse sources)))

(defun me/calendar--color (face) ;> FACE's foreground as a color string; calfw needs a real color, not nil/unspecified
  "Return the foreground color of FACE, falling back to gray in -nw/batch."
  (let ((color (face-foreground face nil t)))
    (if (and (stringp color) (color-defined-p color)) color "gray50")))

(defun me/calendar--org-source (files name color) ;> [fix]: calfw-org-create-source, but items are calfw-event structs — calfw-blocks
  "Return a calfw source over org FILES whose items are `calfw-event's." ;. (built against maccalfw) calls calfw-event-start-date on every item and dies on
  (make-calfw-source ;. the plain strings calfw-org yields ("wrong-type-argument calfw-event")
   :name name :color color
   :data (lambda (begin end)
           (me/calendar--org-events
            (calfw-org--schedule-period-to-calendar files begin end)))))

(defun me/calendar--org-events (contents) ;> ((date item…)… (periods (begin end item)…)) → (event… (periods event…))
  "Convert calfw-org CONTENTS into a flat list of `calfw-event's."
  (let (events periods)
    (dolist (entry contents)
      (if (eq (car entry) 'periods)
          (dolist (period (cdr entry))
            (push (me/calendar--org-event (nth 2 period) (nth 0 period) (nth 1 period)) periods))
        (dolist (item (cdr entry))
          (if (calfw-org--tp item 'time-of-day)
              (push (me/calendar--org-event item (car entry)) events)
            (push (me/calendar--org-event item (car entry)) periods))))) ;. untimed = all-day: blocks only draws those as (one-day) periods —
                                                                         ;. the timed path divides by a nil start time
    (nconc (nreverse events) (list (cons 'periods (nreverse periods))))))

(defun me/calendar--org-event (item date &optional end-date) ;> one agenda ITEM (propertized string) as a calfw-event on DATE
  "Build a `calfw-event' from agenda ITEM; times come from its text properties."
  (let* ((tod (calfw-org--tp item 'time-of-day)) ;. hhmm integer when the timestamp has a time, else nil (all-day)
         (minutes (calfw-org--tp item 'duration)) ;. set for <… 10:00-11:30> ranges
         (start (and tod (list (/ tod 100) (% tod 100))))
         (end (and start
                   (if minutes
                       (let ((m (+ (* 60 (car start)) (cadr start) (round minutes))))
                         (list (/ m 60) (% m 60)))
                     start)))) ;. end = start is blocks' "no end": it then draws calfw-blocks-default-event-length (1 h)
    (make-calfw-event :title item :start-date date :start-time start ;. title keeps the string's props (org-marker…), so RET can still jump to the entry
                      :end-date (or end-date date) :end-time end))) ;. never nil: blocks' all-day deduction does date arithmetic on it

(defun me/calendar () ;> weekly time-block calendar of every agenda file, color per category
  "Open the calfw calendar on the block-week view."
  (interactive)
  (require 'calfw-org) ;. the agenda collector; calfw-blocks requires calfw only
  (require 'calfw-blocks) ;. block views register on load
  (calfw-open-calendar-buffer
   :contents-sources (me/calendar-sources)
   :view 'block-week ;. default sorter (calfw-sorter-start-time) already orders events by start time
   :custom-map (let ((map (make-sparse-keymap))) ;. calfw reparents this map onto calfw-calendar-mode-map, so no keymap-parent tricks here
                 (define-key map (kbd "RET") #'calfw-org-onclick) ;. jump to the org entry — blocks drop the per-item text keymap that used to do it
                 (define-key map [mouse-1] #'calfw-org-onclick)
                 (define-key map (kbd "q") #'bury-buffer)
                 (define-key map (kbd "SPC") #'calfw-org-open-agenda-day) ;. that day's org-agenda
                 map)))

;;; Org HTML Export
(defvar me/ox-html-themes-dir ;> where per-theme CSS/asset folders live
  (expand-file-name "ox-html-themes/" user-emacs-directory))

(defvar me/ox-html-theme-alist ;> registry: theme name -> (css-file . postamble-logo-file-or-nil)
  `(("default" . (,(expand-file-name "default/style.css" me/ox-html-themes-dir) . nil))) ;. add your own themes in local.el (gitignored, see local.el.example)
  "Selectable HTML export themes. Pick one per file with `#+HTML_THEME: NAME'.")

(defun me/org-html--file-to-data-uri (file) ;> image file → data: URI; mime from the extension, nil for anything else
  "Return FILE's contents as a base64 data: URI, or nil if unreadable."
  (when (file-readable-p file)
    (let* ((ext (downcase (or (file-name-extension file) "")))
           (mime (pcase ext
                   ("png"  "image/png")
                   ("jpg"  "image/jpeg")
                   ("jpeg" "image/jpeg")
                   ("gif"  "image/gif")
                   ("svg"  "image/svg+xml")
                   ("webp" "image/webp"))))
      (when mime
        (with-temp-buffer
          (insert-file-contents-literally file)
          (format "data:%s;base64,%s" mime (base64-encode-string (buffer-string) t)))))))

(defun me/org-html--css-block (file) ;> reads FILE and wraps its contents in a <style> tag
  "Return FILE's contents wrapped in an HTML <style> block, or nil if unreadable."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (format "<style>\n%s\n</style>" (buffer-string)))))

(defun me/org-html-inline-images (text backend _info) ;> inlines local images (e.g. ob-mermaid output) as base64 — keeps the exported HTML a single self-contained file
  "Replace <img src=\"local-file\"> with a base64 data URI when exporting to HTML."
  (when (org-export-derived-backend-p backend 'html)
    (replace-regexp-in-string
     "<img src=\"\\([^\"]+\\)\""
     (lambda (whole)
       (string-match "<img src=\"\\([^\"]+\\)\"" whole)
       (let* ((src (match-string 1 whole))
              (file (and (not (string-match-p "\\`\\(https?:\\|data:\\)" src))
                         (expand-file-name src))))
         (if-let* ((data-uri (and file (me/org-html--file-to-data-uri file))))
             (format "<img src=\"%s\"" data-uri)
           whole)))
     text)))

(defun me/org-html-apply-theme (backend) ;> reads #+HTML_THEME (defaults to "default") and sets org-html-head/org-html-postamble from the registry
  "Set `org-html-head' and `org-html-postamble' from the file's `#+HTML_THEME' keyword."
  (when (and (org-export-derived-backend-p backend 'html)
             (not (org-export-derived-backend-p backend 're-reveal)))
    (let* ((name  (or (cadr (assoc "HTML_THEME" (org-collect-keywords '("HTML_THEME")))) "default"))
           (theme (cdr (assoc name me/ox-html-theme-alist)))
           (css   (car theme))
           (logo  (cdr theme)))
      (setq org-html-head (or (me/org-html--css-block css) ""))
      (setq org-html-postamble
            (if-let* ((data-uri (and logo (me/org-html--file-to-data-uri logo))))
                (format "<img src=\"%s\" alt=\"%s\">" data-uri name)
              nil)))))
