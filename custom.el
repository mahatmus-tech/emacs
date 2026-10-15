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

(defvar me/org-agenda-categories ;> (key label file has-agenda-view face [parent]) — file is relative to me/org-directory; drives capture
  '(("w" "Work"  "agenda/work.org"  t   font-lock-function-name-face) ;. templates, refile targets, per-category agenda views, and the calendar source color
    ("h" "Home"  "agenda/home.org"  t   font-lock-string-face) ;. (a face, so it follows the theme)
    ("l" "Learn" "agenda/learn.org" nil font-lock-type-face))) ;. parent = key of another entry: a project under an area (the area's view then spans its children)

(defun me/org-agenda--categories () ;> the category list, validated: every parent key must name an entry
  "Return `me/org-agenda-categories', signaling a `user-error' on a dangling parent."
  (dolist (cat me/org-agenda-categories me/org-agenda-categories)
    (let ((parent (nth 5 cat)))
      (when (and parent (not (assoc parent me/org-agenda-categories)))
        (user-error "Agenda category \"%s\": parent key \"%s\" matches no entry" (nth 1 cat) parent)))))

(defun me/org-agenda-category-children (key) ;> entries whose parent is KEY
  "Return the category entries whose parent is KEY."
  (seq-filter (lambda (cat) (equal (nth 5 cat) key)) (me/org-agenda--categories)))

(defun me/org-agenda-category-files (key) ;> absolute files of category KEY plus its children — what an area's view covers
  "Return the files of the category with KEY followed by those of its children."
  (let ((cat (assoc key (me/org-agenda--categories))))
    (mapcar (lambda (c) (me/org-file (nth 2 c)))
            (cons cat (me/org-agenda-category-children key)))))

(defun me/org-agenda-category-for-file (file) ;> the category entry owning FILE, nil for inbox.org, someday.org, gcal-*.org…
  "Return the category entry whose file is FILE, or nil."
  (let ((file (expand-file-name file)))
    (seq-find (lambda (cat) (file-equal-p file (me/org-file (nth 2 cat))))
              (me/org-agenda--categories))))

(defun me/org-agenda-capture-entries () ;> one "<Label> task" capture template per category
  "Build an `org-capture-templates' entry for each `me/org-agenda-categories' item."
  (let (result)
    (dolist (cat (me/org-agenda--categories) (nreverse result))
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
    (dolist (cat (me/org-agenda--categories))
      (push (cons (me/org-file (nth 2 cat)) '(:maxlevel . 2)) result))
    (append (nreverse result)
            (list (cons (me/org-file "agenda/someday.org") '(:maxlevel . 1))))))

(defun me/org-agenda-view-entries () ;> one "<Label> tasks" agenda view per category flagged with has-agenda-view
  "Build `org-agenda-custom-commands' entries for categories that want a dedicated view.
An area's view spans its own file and its children's files."
  (let (result)
    (dolist (cat (me/org-agenda--categories) (nreverse result))
      (when (nth 3 cat)
        (let ((key (upcase (nth 0 cat)))
              (label (nth 1 cat))
              (files (me/org-agenda-category-files (nth 0 cat))))
          (push
           (list key label
                 (list
                  (list 'todo "TODO|NEXT|WAIT"
                        (list
                         (list 'org-agenda-files (list 'quote files))
                         (list 'org-agenda-overriding-header (format "%s tasks" label))
                         '(org-agenda-sorting-strategy '(priority-down todo-state-up))))))
           result))))))

(defvar me/org-agenda-crosscutting-tags nil ;> tags that cut across projects (e.g. one shared by two brokers) — the Dashboard view gets a block each
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/org-milestone-progress () ;> (done . total) over the TODO-state headings below the heading at point
  "Return (DONE . TOTAL) for the descendants of the heading at point with a TODO state."
  (let ((level (org-current-level)) (done 0) (total 0))
    (org-map-entries
     (lambda ()
       (when (> (org-current-level) level)
         (when-let* ((state (org-get-todo-state)))
           (cl-incf total)
           (when (member state org-done-keywords) (cl-incf done)))))
     nil 'tree)
    (cons done total)))

(defun me/org-milestone--date (property) ;> PROPERTY of the heading at point as "YYYY-MM-DD", nil when unset or unparsable
  "Return the date in the org timestamp property PROPERTY of the entry at point."
  (when-let* ((value (org-entry-get nil property)))
    (when (string-match org-ts-regexp-both value)
      (format-time-string "%F" (org-time-string-to-time (match-string 0 value))))))

(defvar me/org-sprint-start nil ;> "YYYY-MM-DD" of a sprint's first day (a Monday) — sprints last 14 days; set in local.el
  "Nil by default: the dashboard then omits the sprint band and the sprint counts.")

(defvar me/dashboard-history-file "agenda/dashboard-history.csv" ;> daily done/total per project, relative to `me/org-directory'; nil disables the snapshot
  "Append-only CSV with the header date,project,done,total,closed14.")

(defvar me/dashboard-today nil ;> "YYYY-MM-DD" standing in for today — lets tests simulate another day; nil means the real date
  "When non-nil, the dashboard treats this date as today.")

(defun me/dashboard--today () ;> today as "YYYY-MM-DD", honouring `me/dashboard-today'
  "Return today's date string."
  (or me/dashboard-today (format-time-string "%F")))

(defun me/dashboard--day-number (date) ;> "YYYY-MM-DD" → absolute day number (arithmetic on dates)
  "Return the absolute day number of DATE, a \"YYYY-MM-DD\" string."
  (time-to-days (date-to-time (concat date " 00:00"))))

(defun me/dashboard--day-string (number) ;> absolute day number → "YYYY-MM-DD"
  "Return the \"YYYY-MM-DD\" string of the absolute day NUMBER."
  (require 'calendar)
  (pcase-let ((`(,month ,day ,year) (calendar-gregorian-from-absolute number)))
    (format "%04d-%02d-%02d" year month day)))

(defun me/dashboard--sprint-range () ;> (first . last) day of the sprint containing today, rolled from `me/org-sprint-start'; nil when unset
  "Return the current 14-day sprint as (START . END) date strings, or nil."
  (when me/org-sprint-start
    (let* ((anchor (me/dashboard--day-number me/org-sprint-start))
           (today (me/dashboard--day-number (me/dashboard--today)))
           (first (+ anchor (* 14 (max 0 (floor (- today anchor) 14))))))
      (cons (me/dashboard--day-string first) (me/dashboard--day-string (+ first 13))))))

(defun me/dashboard--clean (text) ;> TEXT without statistics cookie or text properties
  "Return TEXT stripped of its [n/m] / [n%] cookie, org links (label kept) and properties."
  (let ((plain (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" ;. [[url][label]] → label
                                         (substring-no-properties text))))
    (string-trim (replace-regexp-in-string "\\[[0-9]*\\(?:/[0-9]*\\|%\\)\\]" ""
                                           (replace-regexp-in-string "\\[\\[\\([^]]*\\)\\]\\]" "\\1" plain)))))

(defun me/dashboard--title () ;> heading at point without TODO keyword, tags, cookie or text properties
  "Return the clean title of the heading at point."
  (me/dashboard--clean (org-get-heading t t t t)))

(defun me/dashboard--subtree-stats () ;> (done total earliest-closed-date) over the TODO descendants of the heading at point
  "Return (DONE TOTAL EARLIEST) for the descendants of the heading at point with a TODO state."
  (let ((level (org-current-level)) (done 0) (total 0) earliest)
    (org-map-entries
     (lambda ()
       (when (> (org-current-level) level)
         (when-let* ((state (org-get-todo-state)))
           (cl-incf total)
           (when (member state org-done-keywords)
             (cl-incf done)
             (when-let* ((closed (me/org-milestone--date "CLOSED")))
               (when (or (null earliest) (string< closed earliest)) (setq earliest closed)))))))
     nil 'tree)
    (list done total earliest)))

(defun me/dashboard--scan-file (file) ;> one pass over FILE: counts, fronts, milestones, next action, active tasks
  "Return a plist describing the org FILE for the dashboard.
Keys: :done :total :closed14 :closed-sprint :wait :next :fronts :milestones :tasks."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (let* ((today (me/dashboard--today))
            (since (me/dashboard--day-string (- (me/dashboard--day-number today) 13)))
            (sprint (me/dashboard--sprint-range))
            (done 0) (total 0) (closed14 0) (closed-sprint 0) (wait 0)
            next fronts front loose milestones tasks)
       (org-map-entries
        (lambda ()
          (let* ((level (org-current-level))
                 (state (org-get-todo-state))
                 (title (me/dashboard--title))
                 (path (mapcar #'me/dashboard--clean (org-get-outline-path))))
            (when (= level 1)
              (setq front (list title 0 0 (point-marker)))
              (push front fronts))
            (when state
              (let ((donep (member state org-done-keywords)))
                (cl-incf total)
                (when donep (cl-incf done))
                (cond ((> level 1) ;. counts toward the front it sits under
                       (cl-incf (nth 2 front))
                       (when donep (cl-incf (nth 1 front))))
                      (t ;. a level-1 task: no children to group, so it joins "Loose tasks"
                       (unless loose (setq loose (list "Loose tasks" 0 0 nil)))
                       (cl-incf (nth 2 loose))
                       (when donep (cl-incf (nth 1 loose)))))
                (when donep
                  (when-let* ((closed (me/org-milestone--date "CLOSED")))
                    (unless (string< closed since) (cl-incf closed14))
                    (when (and sprint (not (string< closed (car sprint))) (not (string< (cdr sprint) closed)))
                      (cl-incf closed-sprint))))
                (when (equal state "WAIT") (cl-incf wait))
                (when (and (equal state "NEXT") (null next))
                  (setq next (list :title title :marker (point-marker))))
                (when (member state '("TODO" "NEXT" "WAIT"))
                  (push (list :state state
                              :priority (nth 3 (org-heading-components))
                              :title title :path path :file file
                              :tags (mapcar #'substring-no-properties (org-get-tags))
                              :marker (point-marker))
                        tasks))))
            (when (member "milestone" (org-get-tags nil t)) ;. local tag: no dependence on inheritance settings
              (pcase-let ((`(,mdone ,mtotal ,earliest) (me/dashboard--subtree-stats)))
                (push (list :title title :file file :path path
                            :front (and (> level 1) (car path)) ;. nil when the milestone is itself a front
                            :deadline (me/org-milestone--date "DEADLINE")
                            :start (or (me/org-milestone--date "START") earliest
                                       (me/org-milestone--date "CREATED"))
                            :done mdone :total mtotal :marker (point-marker))
                      milestones)))))
        nil)
       (list :done done :total total :closed14 closed14 :closed-sprint closed-sprint
             :wait wait :next next
             :fronts (seq-filter (lambda (f) (> (nth 2 f) 0))
                                 (append (nreverse fronts) (and loose (list loose))))
             :milestones (nreverse milestones) :tasks (nreverse tasks))))))

(defun me/dashboard--risk (milestone closed14) ;> late / risk / ok / done / nil (undated) for a milestone given its project's 14-day closed count
  "Return the risk state of MILESTONE, a plist with :deadline :done :total."
  (let ((deadline (plist-get milestone :deadline))
        (remaining (- (plist-get milestone :total) (plist-get milestone :done))))
    (cond ((me/org-milestone-finished-p milestone) 'done)
          ((null deadline) nil)
          ((string< deadline (me/dashboard--today)) 'late)
          (t (let ((days (max 1 (- (me/dashboard--day-number deadline)
                                   (me/dashboard--day-number (me/dashboard--today))))))
               (if (> remaining (* (/ closed14 14.0) days)) 'risk 'ok))))))

(defun me/dashboard--project (label file &rest props) ;> scan FILE and wrap it as a project plist labelled LABEL; nil when the file is missing
  "Return a project plist for FILE, or nil when it is missing or has nothing to show."
  (when (file-exists-p file)
    (let* ((scan (me/dashboard--scan-file file))
           (closed14 (plist-get scan :closed14))
           (milestones (mapcar (lambda (m)
                                 (append m (list :project label :risk (me/dashboard--risk m closed14))))
                               (plist-get scan :milestones))))
      (when (or (> (plist-get scan :total) 0) milestones)
        (append (list :label label :file file) props (plist-put (copy-sequence scan) :milestones milestones))))))

(defun me/dashboard--history-rows () ;> parsed history file as a list of (date project done total), oldest first; nil when disabled or missing
  "Return the rows of `me/dashboard-history-file' without its header."
  (when me/dashboard-history-file
    (let ((file (me/org-file me/dashboard-history-file)))
      (when (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (let (rows)
            (dolist (line (cdr (split-string (buffer-string) "\n" t)))
              (let ((f (split-string line ",")))
                (when (>= (length f) 4)
                  (push (list (nth 0 f) (nth 1 f)
                              (string-to-number (nth 2 f)) (string-to-number (nth 3 f)))
                        rows))))
            (nreverse rows)))))))

(defun me/dashboard--snapshot (areas) ;> append today's done/total/closed14 row for each project of AREAS that has none yet
  "Append one history row per project for today unless that project already has one."
  (when me/dashboard-history-file
    (let* ((file (me/org-file me/dashboard-history-file))
           (today (me/dashboard--today))
           (seen (mapcar #'cadr (seq-filter (lambda (r) (equal (car r) today))
                                            (me/dashboard--history-rows))))
           (lines nil))
      (dolist (area areas)
        (dolist (p (plist-get area :projects))
          (let ((label (replace-regexp-in-string "," " " (plist-get p :label))))
            (unless (member label seen)
              (push (format "%s,%s,%d,%d,%d\n" today label (plist-get p :done)
                            (plist-get p :total) (plist-get p :closed14))
                    lines)))))
      (when lines
        (make-directory (file-name-directory file) t)
        (unless (file-exists-p file)
          (write-region "date,project,done,total,closed14\n" nil file nil 'silent))
        (write-region (apply #'concat (nreverse lines)) nil file t 'silent)))))

(defun me/dashboard--history (project) ;> last 30 days of (date done total) for PROJECT, deduped by date, oldest first
  "Return the burn-up series of PROJECT (a label) from the snapshot file."
  (let ((label (replace-regexp-in-string "," " " project))
        (by-date nil))
    (dolist (r (me/dashboard--history-rows))
      (when (equal (nth 1 r) label)
        (setf (alist-get (nth 0 r) by-date nil nil #'equal) (list (nth 2 r) (nth 3 r)))))
    (last (sort by-date (lambda (a b) (string< (car a) (car b)))) 30)))

(defun me/dashboard-data () ;> the whole dashboard model: areas → projects → fronts, milestones, signals; one scan feeds buffer and HTML
  "Return (:areas AREAS :today DATE :sprint RANGE). Each area is (:label :projects)."
  (let (areas listed)
    (dolist (cat (me/org-agenda--categories))
      (unless (nth 5 cat) ;; top-level entries are the areas
        (let* ((children (me/org-agenda-category-children (nth 0 cat)))
               (own (me/org-file (nth 2 cat)))
               projects)
          (dolist (child children)
            (let ((file (me/org-file (nth 2 child))))
              (push file listed)
              (when-let* ((p (me/dashboard--project (nth 1 child) file :area (nth 1 cat))))
                (push p projects))))
          (push own listed)
          (when-let* ((p (me/dashboard--project (if children (format "%s (general)" (nth 1 cat)) (nth 1 cat))
                                                own :area (nth 1 cat) :own t)))
            (push p projects))
          (when projects
            (push (list :label (nth 1 cat) :projects (nreverse projects)) areas)))))
    (let (others)
      (dolist (file (org-agenda-files)) ;; files outside the category list (inbox, someday…)
        (unless (seq-find (lambda (l) (file-equal-p l file)) listed)
          (when-let* ((p (me/dashboard--project
                          (with-current-buffer (find-file-noselect file)
                            (org-with-wide-buffer (org-get-category (point-min))))
                          file :area nil)))
            (push p others))))
      (when others
        (push (list :label "Other" :projects (nreverse others) :other t) areas)))
    (setq areas (nreverse areas))
    (me/dashboard--snapshot areas)
    (list :areas areas :today (me/dashboard--today) :sprint (me/dashboard--sprint-range))))

(defun me/org-milestones () ;> every :milestone: heading as a plist, earliest deadline first — flattened from `me/dashboard-data'
  "Return the milestones of the dashboard model, earliest deadline first, undated last.
Each is a plist (:title :file :area :project :path :deadline :start :done
:total :marker :risk); dates are \"YYYY-MM-DD\" strings or nil."
  (let (result)
    (dolist (area (plist-get (me/dashboard-data) :areas))
      (dolist (project (plist-get area :projects))
        (dolist (m (plist-get project :milestones))
          (push (append (list :area (plist-get project :area)
                              :project (and (not (plist-get project :own)) (plist-get m :project)))
                        m)
                result))))
    (sort (nreverse result)
          (lambda (a b)
            (let ((da (plist-get a :deadline)) (db (plist-get b :deadline)))
              (cond ((and da db) (string< da db))
                    (da t)))))))

;; ---- dashboard SVG renderers: each returns an `svg' object, shared by the buffer (`svg-image') and the HTML block (`svg-print')

(defconst me/dashboard-risk-colors ;> fixed state colours — readable on both the light and the BP dark theme
  '((done . "#6ac4a0") (ok . "#7cb8e8") (risk . "#f0b35a") (late . "#ef7a7a"))
  "Alist from risk state to its hex colour.")

(defun me/dashboard--palette (&optional html) ;> (:fg :track :grid) colours; HTML output uses currentColor so the theme decides
  "Return the neutral colours: from the current theme for an image, theme-relative for HTML."
  (if html
      '(:fg "currentColor" :track "#8884" :grid "#8883")
    (let ((dark (eq (frame-parameter nil 'background-mode) 'dark)))
      (list :fg (face-foreground 'default nil t)
            :track (if dark "#2a2a2a" "#e0e0e0") :grid (if dark "#303030" "#dddddd")))))

(defun me/dashboard--bar-svg (done total width height color &optional track) ;> pill bar filled to DONE/TOTAL; TOTAL 0 draws only the track
  "Return an svg of a WIDTH×HEIGHT progress bar in COLOR over TRACK."
  (require 'svg)
  (let ((svg (svg-create width height))
        (fraction (if (> total 0) (/ (float done) total) 0.0)))
    (svg-rectangle svg 0 0 width height :rx (/ height 2.0) :fill (or track "#8884"))
    (when (> fraction 0)
      (svg-rectangle svg 0 0 (max (* fraction width) height) height
                     :rx (/ height 2.0) :fill color))
    svg))

(defun me/dashboard--ring-svg (done total size color &optional track fg) ;> donut with the percentage in the middle
  "Return an svg ring of SIZE px showing DONE/TOTAL in COLOR."
  (require 'svg)
  (let* ((svg (svg-create size size))
         (c (/ size 2.0)) (r (- c 5)) (len (* 2 float-pi r))
         (fraction (if (> total 0) (/ (float done) total) 0.0)))
    (svg-circle svg c c r :fill "none" :stroke (or track "#8884") :stroke-width 7)
    (when (> fraction 0)
      (svg-circle svg c c r :fill "none" :stroke color :stroke-width 7
                  :stroke-dasharray (format "%.2f %.2f" (* len fraction) len)
                  :stroke-linecap "round" :transform (format "rotate(-90 %s %s)" c c)))
    (svg-text svg (format "%d%%" (round (* 100 fraction)))
              :x c :y (+ c (/ size 12.0)) :text-anchor "middle" :font-size (/ size 4.2)
              :font-weight "600" :fill (or fg "currentColor"))
    svg))

(defun me/dashboard--date-label (day) ;> absolute day number → "d/m"
  "Return DAY (absolute day number) as d/m."
  (let ((s (me/dashboard--day-string day)))
    (format "%d/%d" (string-to-number (substring s 8)) (string-to-number (substring s 5 7)))))

(defun me/dashboard--timeline-range (milestones today) ;> (LO . HI) absolute days a timeline of MILESTONES spans: earliest start (clamped to 60 days back) −3, latest deadline +5
  "Return the day-number range shared by every timeline drawn from MILESTONES."
  (let* ((today-n (me/dashboard--day-number today))
         (rows (seq-filter (lambda (m) (plist-get m :deadline)) milestones))
         (starts (mapcar (lambda (m) (me/dashboard--day-number (or (plist-get m :start) (plist-get m :deadline)))) rows))
         (ends (mapcar (lambda (m) (me/dashboard--day-number (plist-get m :deadline))) rows)))
    (cons (- (max (- today-n 60) (apply #'min today-n starts)) 3)
          (+ (apply #'max today-n ends) 5))))

(defun me/dashboard--timeline-svg (milestones width today &optional sprint colors range) ;> one bar per dated unfinished milestone, start→deadline, filled by progress; nil when none
  "Return the timeline svg of MILESTONES (plists with :title :start :deadline :done :total :risk).
TODAY and the SPRINT (START . END) are date strings; COLORS is a `me/dashboard--palette' plist;
RANGE is a (LO . HI) day-number span from `me/dashboard--timeline-range', so several charts share one scale."
  (require 'svg)
  (let ((rows (seq-filter (lambda (m) (and (plist-get m :deadline)
                                           (not (eq (plist-get m :risk) 'done))))
                          milestones)))
    (when rows
      (let* ((colors (or colors (me/dashboard--palette)))
             (fg (plist-get colors :fg)) (grid (plist-get colors :grid))
             (today-n (me/dashboard--day-number today))
             (edge (- today-n 60)) ;. left clamp: older starts get cut at 60 days back
             (day (lambda (date) (me/dashboard--day-number date)))
             (range (or range (me/dashboard--timeline-range rows today)))
             (lo (car range)) (hi (cdr range))
             (left (+ 24 (* 8.8 (min 34 (apply #'max (mapcar (lambda (m) (length (plist-get m :title))) rows))))))
             (right 90) (row-h 30) (top 28)
             (height (+ top (* (length rows) row-h) 16))
             (svg (svg-create width height))
             (x (lambda (n) (+ left (* (/ (float (- n lo)) (- hi lo)) (- width left right))))))
        (when sprint ;. translucent band for the current sprint
          (let ((x0 (funcall x (max lo (funcall day (car sprint)))))
                (x1 (funcall x (min hi (1+ (funcall day (cdr sprint)))))))
            (when (> x1 x0)
              (svg-rectangle svg x0 (- top 8) (- x1 x0) (- height top -4 12)
                             :fill (cdr (assq 'ok me/dashboard-risk-colors))
                             :opacity 0.12))))
        (cl-loop for n from lo to hi
                 when (= (mod n 7) 1) ;. Mondays
                 do (svg-line svg (funcall x n) (- top 8) (funcall x n) (- height 12) :stroke grid)
                 and do (svg-text svg (me/dashboard--date-label n)
                                  :x (+ (funcall x n) 3) :y (- top 12) :fill fg :opacity 0.7 :font-size 13))
        (cl-loop for m in rows for i from 0
                 do (let* ((y (+ top (* i row-h)))
                           (risk (plist-get m :risk))
                           (color (cdr (assq (or risk 'ok) me/dashboard-risk-colors)))
                           (title (plist-get m :title))
                           (x1 (funcall x (funcall day (plist-get m :deadline))))
                           (start (plist-get m :start))
                           (start-n (and start (funcall day start)))
                           (x0 (and start-n (funcall x (max lo start-n))))
                           (total (plist-get m :total)))
                      (svg-text svg (if (> (length title) 34) (concat (substring title 0 33) "…") title)
                                :x (- left 10) :y (+ y 15) :text-anchor "end" :fill fg :font-size 14)
                      (when (and x0 (> x1 x0))
                        (svg-rectangle svg x0 (+ y 4) (- x1 x0) 14 :rx 4 :fill color :opacity 0.25)
                        (when (and (> total 0) (> (plist-get m :done) 0))
                          (svg-rectangle svg x0 (+ y 4) (* (- x1 x0) (/ (float (plist-get m :done)) total))
                                         14 :rx 4 :fill color))
                        (when (< start-n edge) ;. clamped: mark the cut
                          (svg-line svg x0 (+ y 2) x0 (+ y 20) :stroke fg :stroke-width 2)))
                      (svg-path svg `((moveto ((,x1 . ,(+ y 3)))) (lineto ((,(+ x1 8) . ,(+ y 11))))
                                      (lineto ((,x1 . ,(+ y 19)))) (lineto ((,(- x1 8) . ,(+ y 11))))
                                      (closepath))
                                :fill color)
                      (svg-text svg (format "%d/%d%s" (plist-get m :done) total
                                            (pcase risk ('risk " · at risk") ('late " · late") (_ "")))
                                :x (+ x1 14) :y (+ y 15) :fill color :font-size 13)))
        (let ((tx (funcall x today-n)))
          (svg-line svg tx (- top 8) tx (- height 12) :stroke "#ef7a7a" :stroke-dasharray "3 3")
          (svg-text svg "today" :x (+ tx 3) :y (- height 2) :fill "#ef7a7a" :font-size 13))
        svg))))

(defun me/dashboard--sparkline-svg (series &optional width height color colors) ;> done (solid) over total (thin) from SERIES of (date done total); nil under 2 points
  "Return a burn-up sparkline svg of SERIES, or nil when it has fewer than two points."
  (when (>= (length series) 2)
    (require 'svg)
    (let* ((width (or width 100)) (height (or height 24))
           (colors (or colors (me/dashboard--palette)))
           (svg (svg-create width height))
           (days (mapcar (lambda (p) (me/dashboard--day-number (car p))) series))
           (d0 (car days)) (span (max 1 (- (car (last days)) d0)))
           (peak (max 1 (apply #'max (mapcar #'caddr series))))
           (pt (lambda (n v) (cons (+ 1 (* (/ (float (- n d0)) span) (- width 2)))
                                   (- height 1 (* (/ (float v) peak) (- height 2)))))))
      (svg-polyline svg (cl-mapcar (lambda (n p) (funcall pt n (caddr p))) days series)
                    :fill "none" :stroke (plist-get colors :fg) :stroke-width 1 :opacity 0.5)
      (svg-polyline svg (cl-mapcar (lambda (n p) (funcall pt n (cadr p))) days series)
                    :fill "none" :stroke (or color (cdr (assq 'done me/dashboard-risk-colors)))
                    :stroke-width 2)
      svg)))

;; ---- dashboard totals and cross-cutting groups: one definition for the buffer and the HTML block

(defun me/dashboard--projects (data) ;> flat list of every project plist of DATA
  "Return all the projects of the dashboard DATA, area by area."
  (mapcan (lambda (a) (copy-sequence (plist-get a :projects))) (plist-get data :areas)))

(defun me/dashboard--totals (projects) ;> header numbers for PROJECTS: open / at-risk-or-late milestones, closed in sprint, waiting, projects without NEXT
  "Return a plist (:open :risk :sprint :wait :no-next) summing PROJECTS."
  (let ((open 0) (risk 0) (sprint 0) (wait 0) (no-next 0))
    (dolist (p projects)
      (cl-incf sprint (plist-get p :closed-sprint))
      (cl-incf wait (plist-get p :wait))
      (unless (or (plist-get p :next) (null (plist-get p :area))) (cl-incf no-next)) ;. files outside the areas (inbox) are not projects
      (dolist (m (plist-get p :milestones))
        (unless (eq (plist-get m :risk) 'done) (cl-incf open))
        (when (memq (plist-get m :risk) '(risk late)) (cl-incf risk))))
    (list :open open :risk risk :sprint sprint :wait wait :no-next no-next)))

(defun me/dashboard--crosscutting (data) ;> alist TAG → active tasks of every project carrying TAG, in `me/org-agenda-crosscutting-tags' order
  "Return ((TAG . TASKS) ...) for the cross-cutting tags that have tasks."
  (let ((projects (me/dashboard--projects data)) result)
    (dolist (tag me/org-agenda-crosscutting-tags)
      (let (tasks)
        (dolist (p projects)
          (dolist (task (plist-get p :tasks))
            (when (member tag (plist-get task :tags))
              (push (append (list :project (plist-get p :label)) task) tasks))))
        (when tasks (push (cons tag (nreverse tasks)) result))))
    (nreverse result)))

(defun me/dashboard--days-left (deadline) ;> whole days from today to DEADLINE, negative when past
  "Return the days between today and the \"YYYY-MM-DD\" DEADLINE."
  (- (me/dashboard--day-number deadline) (me/dashboard--day-number (me/dashboard--today))))

;; ---- dashboard buffer (magit-section + svg.el)

(defvar magit-root-section) ;. package variables the section wrapper below binds; declared so `let' binds them dynamically
(defvar magit-insert-section--current)
(defvar magit-insert-section--oldroot)
(defvar magit-insert-section--parent)

(defvar-local me/dashboard--targets nil ;> buffer-local hash: section value (string) → marker or file, read by RET
  "Where each dashboard row jumps to.")

(defun me/dashboard--section (type value hide body) ;> `magit-insert-section' without the macro — custom.el loads before magit exists, so macros here would never expand
  "Insert a section of TYPE and VALUE, running the function BODY to fill it."
  (let* ((obj (magit-insert-section--create type value hide))
         (magit-insert-section--current obj)
         (magit-insert-section--oldroot
          (or magit-insert-section--oldroot
              (and (not magit-insert-section--parent)
                   (prog1 magit-root-section (setq magit-root-section obj)))))
         (magit-insert-section--parent obj))
    (catch 'cancel-section
      (funcall body)
      (magit-insert-section--finish obj))
    obj))

(defun me/dashboard--image (svg) ;> a one-character string showing SVG inline
  "Return a space displaying the svg object SVG as an image."
  (propertize " " 'display (svg-image svg :ascent 'center)))

(defun me/dashboard--risk-face (risk) ;> face for a risk state
  "Return the face used for the risk state RISK."
  (pcase risk ('late 'error) ('risk 'warning) ('done 'shadow) (_ 'success)))

(defun me/dashboard--risk-color (risk) ;> hex colour for a risk state (ok when nil)
  "Return the bar colour of RISK."
  (cdr (assq (or risk 'ok) me/dashboard-risk-colors)))

(defun me/dashboard--target (key target) ;> remember where the row KEY jumps to; returns KEY so it doubles as the section value
  "Store TARGET under KEY in the buffer's jump table and return KEY."
  (when target (puthash key target me/dashboard--targets))
  key)

(defconst me/dashboard-bar-column 48 ;> text column where every front/milestone bar starts — :align-to keeps it straight whatever the glyph widths
  "Column of the progress bars in the dashboard buffer.")

(defun me/dashboard--align (column) ;> a space that stretches to COLUMN
  "Return a space string displayed up to COLUMN."
  (propertize " " 'display `(space :align-to ,column)))

(defun me/dashboard--bar-image (done total color &optional height) ;> bar image, 120 px wide
  "Return the inline bar of DONE/TOTAL in COLOR."
  (me/dashboard--image
   (me/dashboard--bar-svg done total 120 (or height 10) color (plist-get (me/dashboard--palette) :track))))

(defun me/dashboard--line (indent title done total color &optional tail face) ;> "  title ····· [bar]  13/21  tail", bar at a fixed column
  "Return a row string: TITLE, a progress bar in COLOR at the bar column, DONE/TOTAL, then TAIL."
  (concat (make-string indent ?\s)
          (propertize (truncate-string-to-width title (- me/dashboard-bar-column indent 2) nil nil "…")
                      'face (or face 'default) 'font-lock-face (or face 'default))
          (me/dashboard--align me/dashboard-bar-column)
          (me/dashboard--bar-image done total color)
          (format " %3d/%-3d" done total)
          (if tail (concat "  " tail) "")))

(defun me/dashboard--head-line (indent label face done total color stats) ;> area/project heading: coloured name, bar right after it, then the numbers
  "Return a heading string: LABEL in FACE, a bar for DONE/TOTAL, then STATS."
  (concat (make-string indent ?\s)
          (propertize label 'face face 'font-lock-face face)
          "  "
          (when color (concat (me/dashboard--bar-image done total color 12) " "))
          (propertize (format "%d/%d" done total) 'face 'default 'font-lock-face 'default)
          (propertize (concat "  " stats) 'face 'shadow 'font-lock-face 'shadow)))

(defface me/dashboard-area '((t :inherit font-lock-function-name-face :weight bold)) ;> area names, blue in the mock-up
  "Face of area headings in the dashboard buffer.")

(defface me/dashboard-project '((t :inherit font-lock-keyword-face :weight bold)) ;> project names, pink in the mock-up
  "Face of project headings in the dashboard buffer.")

(defun me/dashboard--milestone-line (m indent) ;> milestone row: ◆ title, bar, deadline, days left, risk
  "Return the buffer row for the milestone plist M."
  (let* ((risk (plist-get m :risk))
         (deadline (plist-get m :deadline))
         (left (and deadline (me/dashboard--days-left deadline)))
         (tail (concat (if deadline (format "%s · %s" (substring deadline 5)
                                            (cond ((< left 0) (format "%dd late" (- left)))
                                                  (t (format "%dd left" left))))
                         "no deadline")
                       (pcase risk ('risk " · AT RISK") ('late " · LATE") ('done " · done") (_ "")))))
    (me/dashboard--line indent (concat "◆ " (plist-get m :title))
                        (plist-get m :done) (plist-get m :total)
                        (me/dashboard--risk-color risk)
                        (propertize tail 'face (me/dashboard--risk-face risk)))))

(defun me/dashboard--insert-project (project) ;> project section: signals, next action, fronts with their milestones
  "Insert the section of PROJECT."
  (let* ((label (plist-get project :label))
         (key (me/dashboard--target (format "project|%s" label) (plist-get project :file)))
         (done (plist-get project :done)) (total (plist-get project :total))
         (milestones (plist-get project :milestones))
         (fronts (plist-get project :fronts))
         (placed nil))
    (me/dashboard--section
     'project key nil
     (lambda ()
       (magit-insert-heading
         (me/dashboard--head-line
          2 label 'me/dashboard-project done total (me/dashboard--risk-color nil)
          (format "14d: %d · sprint: %d · waiting: %d"
                  (plist-get project :closed14) (plist-get project :closed-sprint) (plist-get project :wait))))
       (if-let* ((next (plist-get project :next)))
           (me/dashboard--section
            'next (me/dashboard--target (format "next|%s" label) (plist-get next :marker)) nil
            (lambda ()
              (insert "    " (propertize "NEXT" 'face 'success) " "
                      (plist-get next :title) "\n")))
         (when (plist-get project :area)
           (insert (propertize "    no NEXT defined\n" 'face 'shadow))))
       (dolist (front fronts)
         (let* ((name (nth 0 front))
                (ms (seq-filter (lambda (m) (equal (plist-get m :front) name)) milestones))
                (self (seq-find (lambda (m) (and (null (plist-get m :front))
                                                 (equal (plist-get m :title) name)))
                                milestones))) ;. a front that is itself a milestone shows as one row
           (setq placed (append placed ms (and self (list self))))
           (me/dashboard--section
            'front (me/dashboard--target (format "front|%s|%s" label name) (nth 3 front)) nil
            (lambda ()
              (magit-insert-heading
                (if self
                    (me/dashboard--milestone-line self 4)
                  (me/dashboard--line 4 name (nth 1 front) (nth 2 front)
                                      (if (and (> (nth 2 front) 0) (= (nth 1 front) (nth 2 front)))
                                          (cdr (assq 'done me/dashboard-risk-colors))
                                        "#8a8f98"))))
              (dolist (m ms)
                (me/dashboard--section
                 'milestone (me/dashboard--target (format "ms|%s|%s|%s" label name (plist-get m :title))
                                                  (plist-get m :marker))
                 nil
                 (lambda () (insert (me/dashboard--milestone-line m 6) "\n"))))))))
       (dolist (m (seq-remove (lambda (m) (memq m placed)) milestones)) ;. milestones that are themselves a front
         (me/dashboard--section
          'milestone (me/dashboard--target (format "ms|%s||%s" label (plist-get m :title)) (plist-get m :marker))
          nil
          (lambda () (insert (me/dashboard--milestone-line m 4) "\n"))))
       (when-let* ((series (me/dashboard--sparkline-svg (me/dashboard--history label))))
         (insert "    " (propertize "burn-up " 'face 'shadow) (me/dashboard--image series) "\n"))))))

(defun me/dashboard--insert-header (data) ;> totals line and sprint line at the top of the buffer
  "Insert the title and totals of DATA."
  (let ((totals (me/dashboard--totals (me/dashboard--projects data)))
        (sprint (plist-get data :sprint)))
    (insert (propertize "Dashboard" 'face 'bold) "  "
            (propertize (plist-get data :today) 'face 'shadow)
            (if sprint (format "   sprint %s → %s" (car sprint) (cdr sprint)) "")
            "\n"
            (propertize
             (format "open milestones %d · at risk or late %d · closed in sprint %d · waiting %d · no next action %d\n\n"
                     (plist-get totals :open) (plist-get totals :risk) (plist-get totals :sprint)
                     (plist-get totals :wait) (plist-get totals :no-next))
             'face 'shadow))))

(defun me/dashboard--insert-timeline (data) ;> timeline image plus the undated milestones listed underneath
  "Insert the timeline section of DATA."
  (let* ((milestones (mapcan (lambda (p) (copy-sequence (plist-get p :milestones)))
                             (me/dashboard--projects data)))
         (image (me/dashboard--timeline-svg milestones 880 (plist-get data :today) (plist-get data :sprint)))
         (undated (seq-filter (lambda (m) (and (null (plist-get m :deadline))
                                               (not (eq (plist-get m :risk) 'done))))
                              milestones)))
    (when (or image undated)
      (me/dashboard--section
       'timeline "timeline" nil
       (lambda ()
         (magit-insert-heading (propertize "Timeline" 'face 'me/dashboard-area 'font-lock-face 'me/dashboard-area))
         (when image (insert "  " (me/dashboard--image image) "\n"))
         (dolist (m undated)
           (insert (propertize "  no deadline: " 'face 'shadow) (plist-get m :title) "\n"))
         (insert "\n"))))))

(defun me/dashboard--insert-crosscutting (data) ;> one section per cross-cutting tag listing its active tasks
  "Insert the cross-cutting tag sections of DATA."
  (dolist (group (me/dashboard--crosscutting data))
    (me/dashboard--section
     'tag (format "tag|%s" (car group)) nil
     (lambda ()
       (magit-insert-heading (propertize (format "#%s" (car group)) 'face 'bold)
                             (propertize (format "  %d tasks" (length (cdr group))) 'face 'shadow))
       (dolist (task (cdr group))
         (me/dashboard--section
          'task (me/dashboard--target (format "task|%s|%s" (car group) (plist-get task :title))
                                      (plist-get task :marker))
          nil
          (lambda ()
            (insert (format "    %-5s %s " (plist-get task :state) (plist-get task :title))
                    (propertize (format "(%s)" (plist-get task :project)) 'face 'shadow) "\n"))))
       (insert "\n")))))

(defun me/dashboard-refresh () ;> rebuild the buffer from the current files; folds and point survive
  "Rebuild the dashboard in the current buffer."
  (interactive)
  (let* ((inhibit-read-only t)
         (ident (and (magit-current-section) (magit-section-ident (magit-current-section))))
         (data (me/dashboard-data)))
    (clrhash me/dashboard--targets)
    (erase-buffer)
    (me/dashboard--section
     'dashboard nil nil
     (lambda ()
       (me/dashboard--insert-header data)
       (me/dashboard--insert-timeline data)
       (dolist (area (plist-get data :areas))
         (let ((projects (plist-get area :projects)))
           (me/dashboard--section
            'area (format "area|%s" (plist-get area :label)) nil
            (lambda ()
              (magit-insert-heading
                (me/dashboard--head-line
                 0 (plist-get area :label) 'me/dashboard-area
                 (apply #'+ (mapcar (lambda (p) (plist-get p :done)) projects))
                 (apply #'+ (mapcar (lambda (p) (plist-get p :total)) projects)) nil
                 (format "14d: %d · sprint: %d · waiting: %d"
                         (apply #'+ (mapcar (lambda (p) (plist-get p :closed14)) projects))
                         (apply #'+ (mapcar (lambda (p) (plist-get p :closed-sprint)) projects))
                         (apply #'+ (mapcar (lambda (p) (plist-get p :wait)) projects)))))
              (mapc #'me/dashboard--insert-project projects)
              (insert "\n")))))
       (me/dashboard--insert-crosscutting data)))
    (let ((pos (point-min))) ;; font-lock refontifies this buffer from `font-lock-face', so mirror every plain `face'
      (while (< pos (point-max))
        (let ((next (next-single-property-change pos 'face nil (point-max)))
              (face (get-text-property pos 'face)))
          (when (and face (not (get-text-property pos 'font-lock-face)))
            (put-text-property pos next 'font-lock-face face))
          (setq pos next))))
    (goto-char (point-min))
    (when-let* ((section (and ident (magit-get-section ident))))
      (goto-char (oref section start)))))

(defun me/dashboard-visit () ;> RET: open the org heading (or file) behind the row in the other window
  "Show the org heading of the dashboard row at point in another window."
  (interactive)
  (let* ((section (magit-current-section))
         (target (and section (gethash (oref section value) me/dashboard--targets))))
    (cond ((markerp target)
           (pop-to-buffer (marker-buffer target))
           (widen)
           (goto-char target)
           (org-fold-show-context 'agenda)
           (recenter))
          ((stringp target) (find-file-other-window target))
          (t (user-error "Nothing to visit here")))))

(define-derived-mode me/dashboard-mode magit-section-mode "Dashboard" ;> read-only panel of projects, milestones and risk
  "Major mode of the `*Dashboard*' buffer."
  (setq-local me/dashboard--targets (make-hash-table :test 'equal)))

(keymap-set me/dashboard-mode-map "g" #'me/dashboard-refresh)
(keymap-set me/dashboard-mode-map "RET" #'me/dashboard-visit)
(keymap-set me/dashboard-mode-map "e" #'me/dashboard-export)
(keymap-set me/dashboard-mode-map "q" #'quit-window)

(defun me/dashboard () ;> open (or refresh) the *Dashboard* buffer
  "Show the project dashboard."
  (interactive)
  (require 'magit-section)
  (require 'svg)
  (let ((buffer (get-buffer-create "*Dashboard*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'me/dashboard-mode) (me/dashboard-mode))
      (me/dashboard-refresh))
    (pop-to-buffer-same-window buffer)))

(defun me/org-milestone-finished-p (milestone) ;> true when it has TODO descendants and every one is done
  "Return non-nil when MILESTONE (a plist from `me/org-milestones') is finished."
  (let ((total (plist-get milestone :total)))
    (and (> total 0) (= (plist-get milestone :done) total))))

(defun me/org-agenda-group-key (item) ;> org-super-agenda :auto-map key: "Area / Project / outline path" of the agenda ITEM
  "Return the group header for agenda ITEM, from its file's category and outline path."
  (when-let* ((marker (get-text-property 0 'org-marker item)))
    (with-current-buffer (marker-buffer marker)
      (org-with-wide-buffer
       (goto-char marker)
       (let* ((cat (me/org-agenda-category-for-file (buffer-file-name (org-base-buffer (current-buffer)))))
              (parent (and cat (assoc (nth 5 cat) (me/org-agenda--categories))))
              (head (cond (parent (list (nth 1 parent) (nth 1 cat)))
                          (cat (list (nth 1 cat)))
                          (t (list (org-get-category))))))
         (mapconcat #'identity (append head (org-get-outline-path)) " / "))))))

(defun me/org-agenda-skip-finished-milestone () ;> agenda skip function: hide a milestone whose TODO descendants are all done
  "Return the next heading's position when the milestone at point is finished, else nil."
  (let ((progress (me/org-milestone-progress)))
    (when (and (> (cdr progress) 0) (= (car progress) (cdr progress)))
      (save-excursion (or (outline-next-heading) (point-max))))))

(defun me/org-agenda-milestone-prefix () ;> %(…) prefix for milestone lines: "done/total  dd/mm", "—" when undated
  "Return \"DONE/TOTAL DEADLINE\" for the milestone heading at point."
  (let ((progress (me/org-milestone-progress))
        (deadline (me/org-milestone--date "DEADLINE")))
    (format "%2d/%-2d %s" (car progress) (cdr progress)
            (if deadline
                (format-time-string "%d/%m" (date-to-time (concat deadline " 00:00")))
              "  —  "))))

(defun me/org-agenda-toggle-group () ;> TAB on a super-agenda group header: hide/show the task lines under it
  "Collapse or expand the group whose header line is at point."
  (interactive)
  (if (save-excursion (forward-line 1) (invisible-p (point)))
      (outline-show-subtree)
    (outline-hide-subtree)))

(defun me/org-agenda-dashboard-setup () ;> finalize hook: outline folding in the Dashboard buffer only (agenda redo resets it)
  "Enable header folding when the current agenda buffer is the Dashboard."
  (when (equal (buffer-name) "*Org Agenda: Dashboard*")
    (setq-local outline-regexp "^ [^ ]" ;. a group header is the only line starting with exactly one space
                outline-level (lambda () 1))
    (outline-minor-mode 1)))

(defun me/org-agenda-dashboard-entries () ;> the "D" Dashboard entry of org-agenda-custom-commands, as a one-element list
  "Build the Dashboard `org-agenda-custom-commands' entry.
Blocks: upcoming milestones, active tasks grouped by outline path, and one
block per tag in `me/org-agenda-crosscutting-tags'."
  (list
   `("D" "Dashboard"
     ((tags "milestone"
            ((org-agenda-overriding-header "Upcoming milestones")
             (org-agenda-skip-function 'me/org-agenda-skip-finished-milestone)
             (org-agenda-sorting-strategy '(ts-up))
             (org-agenda-prefix-format '((tags . "  %-10:c %(me/org-agenda-milestone-prefix) ")))))
      (todo "TODO|NEXT|WAIT"
            ((org-agenda-overriding-header "Active tasks")
             (org-super-agenda-groups '((:auto-map me/org-agenda-group-key)))
             (org-agenda-sorting-strategy '(priority-down todo-state-up))))
      ,@(mapcar (lambda (tag)
                  `(tags-todo ,tag
                              ((org-agenda-overriding-header ,(format "Tag: %s" tag))
                               (org-super-agenda-groups nil))))
                me/org-agenda-crosscutting-tags))
     ((org-agenda-buffer-name "*Org Agenda: Dashboard*")))))

;; ---- dashboard HTML block: `#+BEGIN: me-dashboard' emits one export block from the same model as the buffer

(defun me/dashboard--html-svg (svg) ;> SVG object → inline <svg> markup (no file written)
  "Return the XML text of the svg object SVG."
  (with-temp-buffer (svg-print svg) (buffer-string)))

(defun me/dashboard--esc (text) ;> HTML-escape TEXT
  "Return TEXT escaped for HTML."
  (xml-escape-string (or text "")))

(defconst me/dashboard-html-style ;> scoped under .me-dashboard so it coexists with the export theme; colours inherit from the theme
  ".me-dashboard{--line:#8884;--soft:#8881;--ok:#7cb8e8;--done:#6ac4a0;--risk:#f0b35a;--late:#ef7a7a}
.me-dashboard [hidden]{display:none!important}
.me-dashboard svg{vertical-align:middle;max-width:100%}
.me-dashboard .md-filter{margin:0 0 1rem;display:flex;flex-wrap:wrap;gap:1rem;font-size:.9em}
.me-dashboard .md-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:.75rem;margin-bottom:1.5rem}
.me-dashboard .md-kpi{border:1px solid var(--line);background:var(--soft);border-radius:8px;padding:.6rem .8rem}
.me-dashboard .md-kpi b{display:block;font-size:1.7em;line-height:1.1}
.me-dashboard .md-kpi small{opacity:.7}
.me-dashboard .md-area>h2{margin:1.5rem 0 .5rem}
.me-dashboard .md-card{border:1px solid var(--line);background:var(--soft);border-radius:10px;padding:.8rem 1rem;margin:0 0 1rem}
.me-dashboard .md-head{display:flex;gap:1rem;align-items:center}
.me-dashboard .md-head h3{margin:0}
.me-dashboard .md-sig{font-size:.85em;opacity:.75}
.me-dashboard .md-next{margin:.5rem 0;font-size:.9em}
.me-dashboard .md-warn{color:var(--risk)}
.me-dashboard .md-row{display:grid;grid-template-columns:minmax(10rem,1fr) 170px 4.5rem minmax(7rem,auto);gap:.6rem;align-items:center;padding:.15rem 0;font-size:.92em}
.me-dashboard details>summary{cursor:pointer}
.me-dashboard details.md-front>summary.md-row{list-style:none}
.me-dashboard details.md-front>summary.md-row::before{content:'▸';position:absolute;margin-left:-1rem;opacity:.5}
.me-dashboard details.md-front[open]>summary.md-row::before{content:'▾'}
.me-dashboard .md-badge{border-radius:99px;padding:0 .5rem;font-size:.8em;border:1px solid currentColor}
.me-dashboard .md-risk{color:var(--risk)}.me-dashboard .md-late{color:var(--late)}
.me-dashboard .md-ok{color:var(--ok)}.me-dashboard .md-done{color:var(--done)}
.me-dashboard ul.md-tasks{list-style:none;margin:.3rem 0 .6rem 1rem;padding:0;font-size:.88em}
.me-dashboard ul.md-tasks li{padding:.1rem 0}
.me-dashboard .md-st{display:inline-block;min-width:3.2rem;opacity:.7;font-size:.85em}
.me-dashboard .md-path{opacity:.55;font-size:.85em}
.me-dashboard .md-timeline{margin:0 0 1rem;overflow-x:auto}"
  "CSS of the dashboard export block.")

(defconst me/dashboard-html-script ;> area filter: unticking an area hides its [data-area] elements and recomputes the KPI totals from the visible cards
  "(function(){document.querySelectorAll('.me-dashboard').forEach(function(r){
var boxes=r.querySelectorAll('.md-filter input');
function upd(){var on={},t={open:0,risk:0,sprint:0,wait:0,nonext:0};
boxes.forEach(function(b){on[b.value]=b.checked});
r.querySelectorAll('[data-area]').forEach(function(e){e.hidden=!on[e.dataset.area]});
r.querySelectorAll('.md-card').forEach(function(c){if(!c.hidden)for(var k in t)t[k]+=+c.dataset[k]});
for(var k in t){var e=r.querySelector('[data-total=\"'+k+'\"]');if(e)e.textContent=t[k]}}
boxes.forEach(function(b){b.addEventListener('change',upd)});upd()})})();"
  "Inline script of the dashboard export block.")

(defun me/dashboard--html-tasks (tasks) ;> <ul> of active TASKS with state, priority and the outline path below the front
  "Return the HTML list of TASKS."
  (concat "<ul class=\"md-tasks\">"
          (mapconcat
           (lambda (task)
             (let ((rest (cdr (plist-get task :path))))
               (format "<li data-area=\"%s\"><span class=\"md-st\">%s</span>%s%s%s</li>"
                       (me/dashboard--esc (plist-get task :area))
                       (plist-get task :state)
                       (if (plist-get task :priority) (format "[#%c] " (plist-get task :priority)) "")
                       (me/dashboard--esc (plist-get task :title))
                       (if rest (format " <span class=\"md-path\">%s</span>"
                                        (me/dashboard--esc (mapconcat #'identity rest " › ")))
                         ""))))
           tasks "")
          "</ul>"))

(defun me/dashboard--html-row (title done total color tail) ;> grid row: title, bar, done/total, tail
  "Return the contents of one progress row."
  (concat (format "<span>%s</span>" title)
          (me/dashboard--html-svg (me/dashboard--bar-svg done total 160 10 color))
          (format "<span>%d/%d</span>" done total)
          (format "<span>%s</span>" (or tail ""))))

(defun me/dashboard--html-deadline (m) ;> "10-16 · 3d left [at risk]" for milestone M
  "Return the deadline, days left and risk badge of the milestone plist M as HTML."
  (let* ((risk (plist-get m :risk)) (deadline (plist-get m :deadline))
         (left (and deadline (me/dashboard--days-left deadline))))
    (format "%s%s"
            (if deadline (format "%s · %s" (me/dashboard--esc (substring deadline 5))
                                 (if (< left 0) (format "%dd late" (- left)) (format "%dd left" left)))
              "no deadline")
            (pcase risk
              ('risk " <span class=\"md-badge md-risk\">at risk</span>")
              ('late " <span class=\"md-badge md-late\">late</span>")
              ('done " <span class=\"md-badge md-done\">done</span>")
              (_ "")))))

(defun me/dashboard--html-milestone (m) ;> milestone row with deadline, days left and risk badge
  "Return the HTML row of the milestone plist M."
  (format "<div class=\"md-row\">%s</div>"
          (me/dashboard--html-row
           (concat "◆ " (me/dashboard--esc (plist-get m :title)))
           (plist-get m :done) (plist-get m :total) (me/dashboard--risk-color (plist-get m :risk))
           (me/dashboard--html-deadline m))))

(defun me/dashboard--html-project (project) ;> one card: ring, signals, next action, rows, sparkline, task lists
  "Return the HTML card of PROJECT."
  (let* ((label (plist-get project :label))
         (area (or (plist-get project :area) "Other"))
         (done (plist-get project :done)) (total (plist-get project :total))
         (milestones (plist-get project :milestones))
         (worst (cond ((seq-find (lambda (m) (eq (plist-get m :risk) 'late)) milestones) 'late)
                      ((seq-find (lambda (m) (eq (plist-get m :risk) 'risk)) milestones) 'risk)
                      ((and (> total 0) (= done total)) 'done)))
         (totals (me/dashboard--totals (list project)))
         (colors (me/dashboard--palette t))
         (tasks (mapcar (lambda (task) (append (list :area area) task)) (plist-get project :tasks)))
         (placed nil))
    (concat
     (format "<article class=\"md-card\" data-area=\"%s\" data-open=\"%d\" data-risk=\"%d\" data-sprint=\"%d\" data-wait=\"%d\" data-nonext=\"%d\">\n"
             (me/dashboard--esc area) (plist-get totals :open) (plist-get totals :risk)
             (plist-get totals :sprint) (plist-get totals :wait) (plist-get totals :no-next))
     (format "<div class=\"md-head\">%s<div><h3>%s</h3><div class=\"md-sig\">closed in 14d %d · in sprint %d · waiting %d</div></div></div>\n"
             (me/dashboard--html-svg (me/dashboard--ring-svg done total 64 (me/dashboard--risk-color worst)
                                                             (plist-get colors :track) "currentColor"))
             (me/dashboard--esc label)
             (plist-get project :closed14) (plist-get project :closed-sprint) (plist-get project :wait))
     (cond ((plist-get project :next)
            (format "<div class=\"md-next\">next: %s</div>\n" (me/dashboard--esc (plist-get (plist-get project :next) :title))))
           ((plist-get project :area) "<div class=\"md-next md-warn\">no next action</div>\n")
           (t ""))
     (mapconcat
      (lambda (front)
        (let* ((name (nth 0 front))
               (ms (seq-filter (lambda (m) (equal (plist-get m :front) name)) milestones))
               (self (seq-find (lambda (m) (and (null (plist-get m :front)) (equal (plist-get m :title) name))) milestones))
               (mine (seq-filter (lambda (task) (equal (or (car (plist-get task :path)) "Loose tasks") name)) tasks))
               (row (and self (plist-get self :title))))
          (setq placed (append placed ms (and self (list self))))
          (concat
           (if mine
               (format "<details class=\"md-front\"><summary class=\"md-row\">%s</summary>%s</details>\n"
                       (me/dashboard--html-row (me/dashboard--esc (or row name)) (nth 1 front) (nth 2 front)
                                               (me/dashboard--risk-color (and self (plist-get self :risk)))
                                               (and self (me/dashboard--html-deadline self)))
                       (me/dashboard--html-tasks mine))
             (format "<div class=\"md-row\">%s</div>\n"
                     (me/dashboard--html-row (me/dashboard--esc name) (nth 1 front) (nth 2 front)
                                             (me/dashboard--risk-color nil) nil)))
           (mapconcat (lambda (m) (concat (me/dashboard--html-milestone m) "\n")) ms ""))))
      (plist-get project :fronts) "")
     (mapconcat (lambda (m) (concat (me/dashboard--html-milestone m) "\n"))
                (seq-remove (lambda (m) (memq m placed)) milestones) "")
     (if-let* ((series (me/dashboard--sparkline-svg (me/dashboard--history label) 160 28 nil colors)))
         (format "<div class=\"md-sig\">burn-up %s</div>\n" (me/dashboard--html-svg series))
       "")
     (if tasks
         (format "<details><summary>Active tasks (%d)</summary>%s</details>\n" (length tasks)
                 (mapconcat
                  (lambda (group)
                    (format "<h4>%s</h4>%s" (me/dashboard--esc (car group)) (me/dashboard--html-tasks (cdr group))))
                  (let (groups)
                    (dolist (task tasks)
                      (let* ((front (or (car (plist-get task :path)) "Loose tasks"))
                             (cell (assoc front groups)))
                        (if cell (setcdr cell (append (cdr cell) (list task)))
                          (setq groups (append groups (list (list front task)))))))
                    groups)
                  ""))
       "")
     "</article>\n")))

(defun me/dashboard--html (data) ;> the whole export block body for DATA
  "Return the HTML of the dashboard DATA."
  (let* ((areas (plist-get data :areas))
         (projects (me/dashboard--projects data))
         (totals (me/dashboard--totals projects))
         (today (plist-get data :today))
         (sprint (plist-get data :sprint))
         (colors (me/dashboard--palette t))
         (all (mapcan (lambda (p) (copy-sequence (plist-get p :milestones))) projects))
         (range (and (seq-find (lambda (m) (plist-get m :deadline)) all)
                     (me/dashboard--timeline-range all today))))
    (concat
     (format "<div class=\"me-dashboard\">\n<style>%s</style>\n" me/dashboard-html-style)
     (format "<p class=\"md-sig\">%s%s</p>\n" today
             (if sprint (format " · sprint %s → %s" (car sprint) (cdr sprint)) ""))
     "<div class=\"md-filter\">"
     (mapconcat (lambda (a) (format "<label><input type=\"checkbox\" value=\"%s\" checked> %s</label>"
                                    (me/dashboard--esc (plist-get a :label)) (me/dashboard--esc (plist-get a :label))))
                areas "")
     "</div>\n<div class=\"md-kpis\">"
     (mapconcat (lambda (k) (format "<div class=\"md-kpi\"><b data-total=\"%s\">%d</b><small>%s</small></div>"
                                    (car k) (plist-get totals (nth 1 k)) (nth 2 k)))
                '(("open" :open "open milestones") ("risk" :risk "at risk or late")
                  ("sprint" :sprint "closed in sprint") ("wait" :wait "waiting")
                  ("nonext" :no-next "no next action"))
                "")
     "</div>\n"
     (mapconcat
      (lambda (area)
        (let* ((label (plist-get area :label))
               (ms (mapcan (lambda (p) (copy-sequence (plist-get p :milestones))) (plist-get area :projects)))
               (image (me/dashboard--timeline-svg ms 880 today sprint colors range)))
          (format "<section class=\"md-area\" data-area=\"%s\"><h2>%s</h2>\n%s%s</section>\n"
                  (me/dashboard--esc label) (me/dashboard--esc label)
                  (if image (format "<div class=\"md-timeline\">%s</div>\n" (me/dashboard--html-svg image)) "")
                  (mapconcat #'me/dashboard--html-project (plist-get area :projects) ""))))
      areas "")
     (mapconcat
      (lambda (group)
        (format "<section><h2>#%s</h2>%s</section>\n" (me/dashboard--esc (car group))
                (me/dashboard--html-tasks
                 (mapcar (lambda (task)
                           (let ((p (seq-find (lambda (p) (equal (plist-get p :label) (plist-get task :project))) projects)))
                             (append (list :area (or (plist-get p :area) "Other")) task)))
                         (cdr group)))))
      (me/dashboard--crosscutting data) "")
     (format "<script>%s</script>\n</div>" me/dashboard-html-script))))

(defun org-dblock-write:me-dashboard (_params) ;> dynamic block: the dashboard as one export block (KPIs, timelines, project cards, task lists, area filter)
  "Write the dashboard HTML into the dynamic block at point."
  (require 'svg)
  (insert "#+begin_export html\n" (me/dashboard--html (me/dashboard-data)) "\n#+end_export\n"))

(defun me/dashboard-export () ;> update the dashboard.org block and export it to HTML (same as C-c C-e h h there)
  "Refresh the dynamic block of the dashboard document and export it."
  (interactive)
  (with-current-buffer (find-file-noselect (me/org-file "agenda/dashboard.org"))
    (org-update-all-dblocks)
    (save-buffer)
    (let ((out (org-html-export-to-html)))
      (message "Dashboard exported to %s" out)
      out)))

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
                   (append (mapcar (lambda (c) (list (nth 1 c) (me/org-file (nth 2 c)) (nth 4 c))) (me/org-agenda--categories))
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
