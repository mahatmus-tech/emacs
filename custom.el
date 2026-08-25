;;; custom.el --- Mahatmus Emacs Configuration -*- lexical-binding: t -*-
;;; ------------------------------------------------------------------- Outline
;;;; -                                                                   Functions
(defun me/elisp-outline-setup ()                                      ;> personal outline minor mode
  "Enable outline navigation and visual aids for Emacs Lisp files."
  (outline-minor-mode 1)
  (outline-hide-sublevels 1)
  (setq comment-column 70)
  (setq display-fill-column-indicator-column 70)
  (display-fill-column-indicator-mode 1)

  ;; fold ellipsis — match org-mode ⬎
  (unless buffer-display-table
    (setq buffer-display-table (make-display-table)))
  (set-display-table-slot buffer-display-table 'selective-display
                          (string-to-vector " ⬎"))

  ;; 1. Ensure the list isn't nil before injecting
  (unless (boundp 'prettify-symbols-alist)
    (setq prettify-symbols-alist nil))

  ;; 2. Inject heading and inline-arrow symbols
  (add-to-list 'prettify-symbols-alist '(";;;" . ?◆))
  (add-to-list 'prettify-symbols-alist '(";;;;" . ?◇))
  (add-to-list 'prettify-symbols-alist '(";>" . ?→))
  (add-to-list 'prettify-symbols-alist '(";." . ?↳))  

  ;; 3. Exception so the visual engine matches exactly ";>"
  (setq-local prettify-symbols-compose-predicate
              (lambda (start end match)
                (or (string= match ";>")
                    (string= match ";.")
                    (string= match ";;;")
                    (string= match ";;;;")
                    (prettify-symbols-default-compose-p start end match))))

  ;; 4. Dim heading dashes
  (font-lock-add-keywords nil
                          '(("^;;; \\(-+\\)"  1 'shadow t)
                            ("^;;;; \\(-\\)"  1 'shadow t))
                          'append)

  ;; 5. Activate the visual engine
  (run-at-time 0.05 nil (lambda ()
                          (prettify-symbols-mode 1)
                          (font-lock-flush))))

(defun me/outline-tab-dwim ()                                         ;> outline cycle function
  "Cycle outline if on a heading, otherwise run the default indent command."
  (interactive)
  (if (outline-on-heading-p)
      (outline-cycle)
    (indent-for-tab-command)))

(defun me/outline-backtab-dwim ()                                     ;> collapse current heading only
  "Collapse the current heading's subtree. If not on a heading, go up first."
  (interactive)
  (save-excursion
    (unless (outline-on-heading-p)
      (outline-back-to-heading))
    (outline-hide-subtree)))

(defun me/outline-cycle-reverse ()                                    ;> reverse outline cycle
  "Cycle outline visibility in reverse (show → headings → hide)."
  (interactive)
  (outline-cycle)
  (outline-cycle))

(defun outline-copy-visible (beg end)                                 ;> copy helper
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

;;;; -                                                                   Keybindings
(with-eval-after-load 'outline                                        ;> set TAB/S-TAB outline bindings
  (define-key outline-minor-mode-map (kbd "TAB")       #'me/outline-tab-dwim)
  (define-key outline-minor-mode-map (kbd "<backtab>") #'me/outline-cycle-reverse)
  (define-key outline-minor-mode-map (kbd "C-c C-t")   #'outline-show-only-headings)
  (define-key outline-minor-mode-map (kbd "C-c C-y")   (lambda () (interactive) (outline-hide-sublevels 1))))
;;; ------------------------------------------------------------------- Utils
(defun me/keyboard-quit-dwim ()                                       ;> smart C-g: closes minibuffer even when unfocused
  (interactive)
  (cond
   ((region-active-p)                      (keyboard-quit))
   ((derived-mode-p 'completion-list-mode) (delete-completion-window))
   ((> (minibuffer-depth) 0)               (abort-recursive-edit))
   (t                                      (keyboard-quit))))

(defun me/flymake-elisp-setup ()                                      ;> flymake for elisp: no checkdoc, full load-path
  "Tune Flymake's Emacs Lisp backends: drop checkdoc, inherit `load-path'."
  (remove-hook 'flymake-diagnostic-functions #'elisp-flymake-checkdoc t)
  (setq-local elisp-flymake-byte-compile-load-path (cons "./" load-path)))

(defun me/open-config ()                                              ;> shortcut to init.el
  "Open init.el in the current window."
  (interactive)
  (find-file (expand-file-name "init.el" user-emacs-directory)))

(defun me/save-frame-colors (&rest _)                                 ;> persist theme colors for next startup
  "Write current theme's frame params to frame-colors.el."
  (when (display-graphic-p)                                           ;> skip in batch/TTY — font param would be "tty"
    (let ((bg     (face-background 'default    nil t))
          (fg     (face-foreground 'default    nil t))
          (cursor (face-background 'cursor     nil t))
          (border (face-background 'border     nil t))
          (mouse  (frame-parameter nil 'mouse-color))
          (font   (frame-parameter nil 'font))
          (alpha  (frame-parameter nil 'alpha-background))
          (file   (expand-file-name "frame-colors.el" user-emacs-directory)))
      (when (and bg fg
                 (not (string-prefix-p "unspecified" bg))  ;> skip terminal pseudo-colors
                 (not (string-prefix-p "unspecified" fg)))
        (with-temp-file file
          (insert ";; -*- lexical-binding: t; -*-\n")                 ;. [fix]: Emacs 31 warns on `load' without this cookie
          (insert (format "(add-to-list 'default-frame-alist '(background-color . %S))\n" bg))
          (insert (format "(add-to-list 'default-frame-alist '(foreground-color . %S))\n" fg))
          (when cursor (insert (format "(add-to-list 'default-frame-alist '(cursor-color     . %S))\n" cursor)))
          (when border (insert (format "(add-to-list 'default-frame-alist '(border-color     . %S))\n" border)))
          (when mouse  (insert (format "(add-to-list 'default-frame-alist '(mouse-color      . %S))\n" mouse)))
          (when font   (insert (format "(add-to-list 'default-frame-alist '(font             . %S))\n" font)))
          (when alpha  (insert (format "(add-to-list 'default-frame-alist '(alpha-background . %S))\n" alpha))))))))

(advice-add 'load-theme :after #'me/save-frame-colors)                ;> pre render last theme to avoid flash

(defun me/new-scratch-tab ()                                          ;> new tab with scrach buffer 
  (interactive)
  (tab-bar-new-tab)
  (scratch-buffer))
;;; ------------------------------------------------------------------- Workspace
(defvar me/workspace-default-repos                                    ;> repos auto-opened by me/setup-workspaces
  '("~/repos/dotfiles/"))                                              ;. add your own repos in local.el (gitignored, see local.el.example)

(defvar me/forge-owned-accounts nil                                   ;> feeds forge-owned-accounts (Version Control section, init.el)
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/open-repo-workspace (repo-dir)                              ;> shared logic: tabspace + magit + dirvish side panel for one repo
  "Open REPO-DIR in its own tabspace, named after the repo directory.
Shows a Magit status buffer with a Dirvish side panel rooted at the repo.
Returns the tabspace name."
  (let* ((root (file-name-as-directory (expand-file-name repo-dir)))
         (name (file-name-nondirectory (directory-file-name root)))
         (new? (not (member name (tabspaces--list-tabspaces)))))      ;. a fresh tab still carries the buffer inherited from tab-new below
    (when (file-directory-p root)
      (tabspaces-switch-or-create-workspace name)
      (delete-other-windows)                                         ;> the side window survives: no-delete-other-windows
      (let ((default-directory root))
        (magit-status-setup-buffer root)                             ;> main window
        (save-selected-window                                        ;> dirvish-side selects its window; keep focus on magit
          (dirvish-side root)))                                      ;. sessions are per tab (dirvish--scopes), so each workspace keeps its own panel
      (when new?                                                      ;. [fix]: tabspaces--tab-post-open-function resets the buffer-list right after
        (tabspaces-reset-buffer-list)))                               ;. tab-new, before magit/dirvish-side replace the inherited buffer — that
                                                                      ;. buffer stays "local" forever unless the reset runs again once we're done
    name))

(defun me/setup-workspaces ()                                         ;> personal workspace main function
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

(defun me/open-project-workspace (project-dir)                        ;> open a new repo in an isolated tab (Magit + Dirvish side panel)
  "Open PROJECT-DIR in a new tabspace with magit and a dirvish side panel."
  (interactive (list (read-directory-name "Repo: " "~/repos/")))
  (require 'dirvish-side)
  (require 'magit)
  (let ((name (me/open-repo-workspace project-dir)))
    (message "Workspace: %s" name)))

(defvar tabspaces--session-list)                                      ;> declared only — defined by tabspaces, used inside the functions below
(defvar me/tabspaces--restored-side-panels nil                        ;> (tab-name . dir) pairs queued while a tabspaces session restores
  "Dirvish side panels to rebuild once `tabspaces-restore-session' has recreated the tabs.")

(defun me/tabspaces-side-panel-record (buffer)                        ;> session save: a dirvish side panel is stored as its directory only
  "Return a tabspaces session record for BUFFER when it is a dirvish side panel, else nil."
  (with-current-buffer buffer
    (when (and (derived-mode-p 'dired-mode)
               (string-prefix-p " *SIDE :: " (buffer-name)))          ;. dirvish-side names its buffers like this (dirvish-side-root-conf)
      (list :kind 'dirvish-side :dir default-directory))))

(defun me/tabspaces-side-panel-defer (record)                         ;> session restore: queue the panel — the tab's windows aren't final yet
  "Queue RECORD's side panel for `me/tabspaces-restore-side-panels'.  Returns nil: no buffer now."
  (push (cons (alist-get 'name (tab-bar--current-tab)) (plist-get record :dir))
        me/tabspaces--restored-side-panels)
  nil)

(defun me/tabspaces-restore-side-panels (&rest _)                     ;> after restore: rebuild the queued panels once the command loop is back
  "Schedule `me/tabspaces--rebuild-side-panels' for the queued side panels.
A timer rather than a direct call: at startup the restore runs inside `after-init-hook',
where `dirvish-side' only yields a plain dired buffer (no session, no data, sentinel errors)."
  (when me/tabspaces--restored-side-panels
    (run-at-time 0 nil #'me/tabspaces--rebuild-side-panels)))

(defun me/tabspaces--rebuild-side-panels ()                           ;> one fresh dirvish-side per tab that had one, then land on the first tab
  "Recreate the dirvish side panels queued during `tabspaces-restore-session'."
  (require 'dirvish-side)
  (let ((tabs (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar-tabs))))
    (pcase-dolist (`(,tab . ,dir) (nreverse me/tabspaces--restored-side-panels))
      (when (and (member tab tabs) (file-directory-p dir))            ;. switching to an unknown tab name would create it
        (tab-bar-switch-to-tab tab)
        (save-selected-window (dirvish-side dir))))                   ;. same call me/open-repo-workspace makes; keeps focus on the main window
    (setq me/tabspaces--restored-side-panels nil)
    (let ((first (cadr (car tabspaces--session-list))))               ;. restore ends on the last saved tab; C-c w lands on the first repo
      (when (member first tabs) (tab-bar-switch-to-tab first)))))

(defun me/dirvish-side-resync (win file)                             ;> deferred half of me/dirvish-side-auto-jump-defer — see there
  "Reposition WIN on FILE and refresh the panel, called from the command loop."
  (when (window-live-p win)
    (with-selected-window win
      (if dirvish-side-auto-expand
          (dirvish-subtree-expand-to file)
        (dired-goto-file file))
      (dirvish--redisplay))))

(defun me/dirvish-side-auto-jump-defer (&rest _)                     ;> [fix]: dirvish-side--auto-jump moves point before the command loop resumes
  "Schedule `me/dirvish-side-resync' for the file just opened, deferred to the command loop.
`:after' advice on `dirvish-side--auto-jump' (init.el, dirvish :config).
Run from `buffer-list-update-hook', that function's own goto/expand leaves the
panel's point on the right file but its displayed index/highlight goes stale —
same class of bug as the after-init-hook case in gotchas.md (dirvish-side ops
run synchronously outside the command loop don't fully take effect); same fix."
  (when-let* ((win (dirvish-side--session-visible-p))
              (file buffer-file-name))
    (run-at-time 0 nil #'me/dirvish-side-resync win file)))

(defun me/tabspaces-skip-terminal-record (buffer)                     ;> session save: terminals (eat, ghostel, claude) would only come back as empty shells
  "Return a no-op session record for BUFFER when it is a terminal, else nil."
  (with-current-buffer buffer
    (when (derived-mode-p 'eat-mode 'ghostel-mode)
      (list :kind 'skip :name (buffer-name)))))

(defun me/tabspaces-strip-window-states (&rest _)                     ;> session restore: buffers only — saved layouts fight dirvish's side windows
  "Drop the window-state of every tab in `tabspaces--session-list' so only buffers are restored,
then make the first saved tab the current one so the restore loop starts there: reuse it if it
exists, rename a pristine startup tab, or open a fresh tab next to whatever is being edited."
  (dolist (tab tabspaces--session-list)
    (when (cddr tab) (setcar (cddr tab) nil)))
  (when-let* ((first (cadr (car tabspaces--session-list)))
              (names (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar-tabs))))
    (cond ((member first names) (tab-bar-switch-to-tab first))        ;. the loop parks a placeholder buffer in the current tab first — keep it out of the user's tab
          ((and (= 1 (length names))                                  ;. fresh Emacs still on *scratch*: otherwise the initial tab is left behind with the placeholder
                (equal (buffer-name (window-buffer)) "*scratch*"))    ;. window-buffer, not current-buffer — a server/minibuffer call must still see the real tab
           (tab-bar-rename-tab first))
          (t (let ((tab-bar-new-tab-choice "*scratch*")) (tab-bar-new-tab));. Emacs opened on a file: leave that tab alone
             (tab-bar-rename-tab first)))))

(defun me/open-terminal ()                                            ;> bash terminal at project root
  (interactive)
  (let ((buf (eat-project)))
    (with-current-buffer buf
      (rename-buffer (format "term: %s"
                             (file-name-nondirectory
                              (directory-file-name default-directory)))
                     t))))

(defun me/claude-review-branch ()                                     ;> code review of the current branch via claude
  "Open Claude Code and send /code-review for the current branch."
  (interactive)
  (claude-code-ide)
  (run-at-time 2 nil
               (lambda ()
                 (claude-code-ide-send-prompt "/code-review"))))

;;; ------------------------------------------------------------------- Org
(defvar me/org-agenda-categories                                      ;> (key label file has-agenda-view face) — drives capture templates, refile targets, per-category agenda views,
  '(("w" "Work"  "~/repos/dotfiles/org/agenda/work.org"  t   font-lock-function-name-face) ;. and the calendar source color (a face, so it follows the theme)
    ("h" "Home"  "~/repos/dotfiles/org/agenda/home.org"  t   font-lock-string-face)
    ("l" "Learn" "~/repos/dotfiles/org/agenda/learn.org" nil font-lock-type-face)))

(defun me/org-agenda-capture-entries ()                               ;> one "<Label> task" capture template per category
  "Build an `org-capture-templates' entry for each `me/org-agenda-categories' item."
  (let (result)
    (dolist (cat me/org-agenda-categories (nreverse result))
      (let ((key (nth 0 cat))
            (label (nth 1 cat))
            (file (nth 2 cat)))
        (push
         (list key (format "%s task" label) 'entry
               (list 'file+headline file "Inbox")
               "* INBOX %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
               :empty-lines 1)
         result)))))

(defun me/org-agenda-refile-entries ()                                ;> refile target per category, plus the someday.org catch-all
  "Build `org-refile-targets' entries for each `me/org-agenda-categories' item."
  (let (result)
    (dolist (cat me/org-agenda-categories)
      (push (cons (nth 2 cat) '(:maxlevel . 2)) result))
    (append (nreverse result)
            '(("~/repos/dotfiles/org/agenda/someday.org" :maxlevel . 1)))))

(defun me/org-agenda-view-entries ()                                  ;> one "<Label> tasks" agenda view per category flagged with has-agenda-view
  "Build `org-agenda-custom-commands' entries for categories that want a dedicated view."
  (let (result)
    (dolist (cat me/org-agenda-categories (nreverse result))
      (when (nth 3 cat)
        (let ((key (upcase (nth 0 cat)))
              (label (nth 1 cat))
              (file (nth 2 cat)))
          (push
           (list key label
                 (list
                  (list 'todo "TODO|NEXT|WAIT"
                        (list
                         (list 'org-agenda-files (list 'quote (list file)))
                         (list 'org-agenda-overriding-header (format "%s tasks" label))
                         '(org-agenda-sorting-strategy '(priority-down todo-state-up))))))
           result))))))

(defvar me/gcal-calendars nil                                         ;> (calendar-id file label face) — one Google calendar ↔ one org file; drives org-gcal-fetch-file-alist
  "Empty by default — set in `local.el' (gitignored, see local.el.example).") ;. and its calfw source color, and the generated gcal capture templates (me/gcal-capture-entries)

(defvar me/roam-work-templates nil                                    ;> spliced into org-roam-capture-templates (Org → Packages, init.el)
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/gcal-load-credentials ()                                    ;> org-gcal's OAuth client id/secret come from ~/.authinfo (machine org-gcal login ID password SECRET)
  "Set `org-gcal-client-id' and `org-gcal-client-secret' from `auth-sources'."
  (let ((entry (car (auth-source-search :host "org-gcal" :max 1 :require '(:user :secret)))))
    (unless entry
      (user-error "No \"machine org-gcal login <client-id> password <secret>\" line in %s" auth-sources))
    (setq org-gcal-client-id (plist-get entry :user)                  ;. set before org-gcal.el loads: its last form registers the oauth2-auto provider from these
          org-gcal-client-secret (auth-info-password entry))))

(defun me/gcal-capture-entries ()                                     ;> one "Event — Google Calendar (<label>)" capture template per me/gcal-calendars entry
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

(defun me/calendar-sources ()                                         ;> one calfw source per category and per Google calendar (its face color) + a grey one for the rest
  "Build the `calfw-source' list for `me/calendar' from `me/org-agenda-categories' and `me/gcal-calendars'."
  (let ((rest (mapcar #'expand-file-name (org-agenda-files)))
        sources)
    (pcase-dolist (`(,label ,file ,face)
                   (append (mapcar (lambda (c) (list (nth 1 c) (nth 2 c) (nth 4 c))) me/org-agenda-categories)
                           (mapcar (lambda (c) (list (nth 2 c) (nth 1 c) (nth 3 c))) me/gcal-calendars)))
      (setq file (expand-file-name file))
      (setq rest (delete file rest))
      (push (me/calendar--org-source (list file) label (me/calendar--color face))
            sources))
    (when rest                                                        ;. inbox.org, someday.org… — anything dated there still shows up
      (push (me/calendar--org-source rest "Other"
                                     (me/calendar--color 'font-lock-comment-face))
            sources))
    (nreverse sources)))

(defun me/calendar--color (face)                                      ;> FACE's foreground as a color string; calfw needs a real color, not nil/unspecified
  "Return the foreground color of FACE, falling back to gray in -nw/batch."
  (let ((color (face-foreground face nil t)))
    (if (and (stringp color) (color-defined-p color)) color "gray50")))

(defun me/calendar--org-source (files name color)                     ;> [fix]: calfw-org-create-source, but items are calfw-event structs — calfw-blocks
  "Return a calfw source over org FILES whose items are `calfw-event's." ;. (built against maccalfw) calls calfw-event-start-date on every item and dies on
  (make-calfw-source                                                  ;. the plain strings calfw-org yields ("wrong-type-argument calfw-event")
   :name name :color color
   :data (lambda (begin end)
           (me/calendar--org-events
            (calfw-org--schedule-period-to-calendar files begin end)))))

(defun me/calendar--org-events (contents)                             ;> ((date item…)… (periods (begin end item)…)) → (event… (periods event…))
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

(defun me/calendar--org-event (item date &optional end-date)          ;> one agenda ITEM (propertized string) as a calfw-event on DATE
  "Build a `calfw-event' from agenda ITEM; times come from its text properties."
  (let* ((tod (calfw-org--tp item 'time-of-day))                      ;. hhmm integer when the timestamp has a time, else nil (all-day)
         (minutes (calfw-org--tp item 'duration))                     ;. set for <… 10:00-11:30> ranges
         (start (and tod (list (/ tod 100) (% tod 100))))
         (end (and start
                   (if minutes
                       (let ((m (+ (* 60 (car start)) (cadr start) (round minutes))))
                         (list (/ m 60) (% m 60)))
                     start))))                                        ;. end = start is blocks' "no end": it then draws calfw-blocks-default-event-length (1 h)
    (make-calfw-event :title item :start-date date :start-time start  ;. title keeps the string's props (org-marker…), so RET can still jump to the entry
                      :end-date (or end-date date) :end-time end)))    ;. never nil: blocks' all-day deduction does date arithmetic on it

(defun me/calendar ()                                                 ;> weekly time-block calendar of every agenda file, color per category
  "Open the calfw calendar on the block-week view."
  (interactive)
  (require 'calfw-org)                                                ;. the agenda collector; calfw-blocks requires calfw only
  (require 'calfw-blocks)                                             ;. block views register on load
  (calfw-open-calendar-buffer
   :contents-sources (me/calendar-sources)
   :view 'block-week                                                  ;. default sorter (calfw-sorter-start-time) already orders events by start time
   :custom-map (let ((map (make-sparse-keymap)))                      ;. calfw reparents this map onto calfw-calendar-mode-map, so no keymap-parent tricks here
                 (define-key map (kbd "RET") #'calfw-org-onclick)     ;. jump to the org entry — blocks drop the per-item text keymap that used to do it
                 (define-key map [mouse-1] #'calfw-org-onclick)
                 (define-key map (kbd "q") #'bury-buffer)
                 (define-key map (kbd "SPC") #'calfw-org-open-agenda-day) ;. that day's org-agenda
                 map)))

;;; ------------------------------------------------------------------- Org HTML Export
(defvar me/ox-html-themes-dir                                         ;> where per-theme CSS/asset folders live
  (expand-file-name "ox-html-themes/" user-emacs-directory))

(defvar me/ox-html-theme-alist                                        ;> registry: theme name -> (css-file . postamble-logo-file-or-nil)
  `(("default" . (,(expand-file-name "default/style.css" me/ox-html-themes-dir) . nil))) ;. add your own themes in local.el (gitignored, see local.el.example)
  "Selectable HTML export themes. Pick one per file with `#+HTML_THEME: NAME'.")

(defun me/org-html--file-to-data-uri (file)
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

(defun me/org-html--css-block (file)                                  ;> reads FILE and wraps its contents in a <style> tag
  "Return FILE's contents wrapped in an HTML <style> block, or nil if unreadable."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (format "<style>\n%s\n</style>" (buffer-string)))))

(defun me/org-html-inline-images (text backend _info)                 ;> inlines local images (e.g. ob-mermaid output) as base64 — keeps the exported HTML a single self-contained file
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

(defun me/org-html-apply-theme (backend)                              ;> reads #+HTML_THEME (defaults to "default") and sets org-html-head/org-html-postamble from the registry
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
