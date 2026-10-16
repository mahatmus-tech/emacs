;;; me-dashboard.el --- Project dashboard over Org agenda files -*- lexical-binding: t -*-

;; Author: Mahatmus
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6") (magit-section "3.3"))
;; Keywords: outlines, calendar, tools
;; URL: https://github.com/mahatmus-tech/emacs

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A dashboard for Org agenda files organized as areas, projects, fronts
;; and milestones.  One model (`me/dashboard-data') feeds three views:
;;
;;   - `me/dashboard': a `magit-section' buffer with SVG progress bars,
;;     a milestone timeline and a burn-up sparkline per project;
;;   - an HTML block, written by the `me-dashboard' dynamic block and
;;     exported by `me/dashboard-export';
;;   - the "D" agenda view, from `me/org-agenda-dashboard-entries'.
;;
;; The package expects the host configuration to define `me/org-directory',
;; `me/org-file' and the `me/org-agenda-category-*' functions (they map
;; categories to files); see custom.el in this repository.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'svg)
(require 'magit-section)

(defgroup me-dashboard nil
  "Project dashboard over Org agenda files."
  :group 'org
  :prefix "me/dashboard-")

(defvar me/org-directory)
(declare-function me/org-file "custom" (relative))
(declare-function me/org-agenda--categories "custom" ())
(declare-function me/org-agenda-category-children "custom" (key))
(declare-function me/org-agenda-category-for-file "custom" (file))

(defvar me/org-agenda-crosscutting-tags nil ;> tags that cut across projects (e.g. one shared by two workstreams) — the Dashboard view gets a block each
  "Empty by default — set in `local.el' (gitignored, see local.el.example).")

(defun me/org-milestone-progress () ;> (done . total) over the TODO-state headings below the heading at point
  "Return (DONE . TOTAL) for TODO descendants of the heading at point."
  (let ((stats (me/dashboard--subtree-stats)))
    (cons (nth 0 stats) (nth 1 stats))))

(defun me/dashboard--finished-p (done total) ;> true when there is work and all of it is done
  "Return non-nil when DONE of TOTAL tasks means finished."
  (and (> total 0) (= done total)))

(defun me/org-milestone--date (property) ;> PROPERTY of the heading at point as "YYYY-MM-DD", nil when unset or unparsable
  "Return the date in the org timestamp property PROPERTY of the entry at point."
  (when-let* ((value (org-entry-get nil property)))
    (when (string-match org-ts-regexp-both value)
      (format-time-string "%F" (org-time-string-to-time (match-string 0 value))))))

;; Name of the front that collects tasks with no level-1 parent.
(defconst me/dashboard--loose-label "Loose tasks")

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
  "Return TEXT stripped of its [n/m] / [n%] cookie, org links (label kept)
and properties."
  (let ((plain (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" ;. [[url][label]] → label
                                         (substring-no-properties text))))
    (string-trim (replace-regexp-in-string "\\[[0-9]*\\(?:/[0-9]*\\|%\\)\\]" ""
                                           (replace-regexp-in-string "\\[\\[\\([^]]*\\)\\]\\]" "\\1" plain)))))

(defun me/dashboard--title () ;> heading at point without TODO keyword, tags, cookie or text properties
  "Return the clean title of the heading at point."
  (me/dashboard--clean (org-get-heading t t t t)))

(defun me/dashboard--subtree-stats () ;> (done total earliest-closed-date) over the TODO descendants of the heading at point
  "Return (DONE TOTAL EARLIEST) for TODO descendants of the heading at point."
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
Keys: :done :total :closed14 :closed-sprint :wait :next :fronts :milestones
:tasks."
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
                (cond ((and (> level 1) front) ;. counts toward the front it sits under
                       (cl-incf (nth 2 front))
                       (when donep (cl-incf (nth 1 front))))
                      (t ;. a level-1 task, or one above the first level-1 heading: joins "Loose tasks"
                       (unless loose (setq loose (list me/dashboard--loose-label 0 0 nil)))
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
  "Return the risk state of MILESTONE, a plist with :deadline :done :total.
CLOSED14 is the project's count of tasks closed in the last 14 days."
  (let ((deadline (plist-get milestone :deadline))
        (remaining (- (plist-get milestone :total) (plist-get milestone :done))))
    (cond ((me/org-milestone-finished-p milestone) 'done)
          ((null deadline) nil)
          ((string< deadline (me/dashboard--today)) 'late)
          (t (let ((days (max 1 (- (me/dashboard--day-number deadline)
                                   (me/dashboard--day-number (me/dashboard--today))))))
               (if (> remaining (* (/ closed14 14.0) days)) 'risk 'ok))))))

(defun me/dashboard--project (label file &rest props) ;> scan FILE and wrap it as a project plist labelled LABEL; nil when the file is missing
  "Return a project plist labelled LABEL for FILE.
Return nil when FILE is missing or has nothing to show.  PROPS are extra
keys merged into the plist."
  (when (file-exists-p file)
    (let* ((scan (me/dashboard--scan-file file))
           (closed14 (plist-get scan :closed14))
           (milestones (mapcar (lambda (m)
                                 (append m (list :project label :risk (me/dashboard--risk m closed14))))
                               (plist-get scan :milestones))))
      (when (or (> (plist-get scan :total) 0) milestones)
        (append (list :label label :file file) props (plist-put (copy-sequence scan) :milestones milestones))))))

(defvar me/dashboard--rows-cache nil
  "(FILE MTIME . ROWS) of the last read of the history file.")

(defun me/dashboard--history-rows () ;> parsed history file as a list of (date project done total), oldest first; nil when disabled or missing
  "Return the rows of `me/dashboard-history-file' without its header."
  (when me/dashboard-history-file
    (let ((file (me/org-file me/dashboard-history-file)))
      (when (file-exists-p file)
        (let ((mtime (file-attribute-modification-time (file-attributes file))))
          (if (and me/dashboard--rows-cache
                   (equal (car me/dashboard--rows-cache) file)
                   (equal (cadr me/dashboard--rows-cache) mtime))
              (cddr me/dashboard--rows-cache) ;. one read per build: the file only changes when a snapshot appends
            (with-temp-buffer
              (insert-file-contents file)
              (let (rows)
                (dolist (line (cdr (split-string (buffer-string) "\n" t)))
                  (let ((f (split-string line ",")))
                    (when (>= (length f) 4)
                      (push (list (nth 0 f) (nth 1 f)
                                  (string-to-number (nth 2 f)) (string-to-number (nth 3 f)))
                            rows))))
                (setq rows (nreverse rows))
                (setq me/dashboard--rows-cache (cons file (cons mtime rows)))
                rows))))))))

(defun me/dashboard--ends-with-newline-p (file)
  "Return non-nil when FILE is empty or its last character is a newline."
  (let ((size (file-attribute-size (file-attributes file))))
    (or (zerop size)
        (with-temp-buffer
          (insert-file-contents file nil (1- size) size)
          (eq (char-after (point-min)) ?\n)))))

(defun me/dashboard--snapshot (areas) ;> append today's done/total/closed14 row for each project of AREAS that has none yet
  "Append one history row per project for today, unless it already has one.
AREAS is the list from `me/dashboard-data'.  Do nothing while
`me/dashboard-today' simulates another day."
  (when (and me/dashboard-history-file (null me/dashboard-today))
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
        (write-region (concat (and (not (me/dashboard--ends-with-newline-p file)) "\n")
                              (apply #'concat (nreverse lines)))
                      nil file t 'silent)))))

(defun me/dashboard--history (project) ;> last 30 snapshots (one per day it was opened) of (date done total) for PROJECT, oldest first
  "Return the burn-up series of PROJECT (a label) from the snapshot file."
  (let ((label (replace-regexp-in-string "," " " project))
        (by-date nil))
    (dolist (r (me/dashboard--history-rows))
      (when (equal (nth 1 r) label)
        (setf (alist-get (nth 0 r) by-date nil nil #'equal) (list (nth 2 r) (nth 3 r)))))
    (last (sort by-date (lambda (a b) (string< (car a) (car b)))) 30)))

(defun me/dashboard-data () ;> the whole dashboard model: areas → projects → fronts, milestones, signals; one scan feeds buffer and HTML
  "Return (:areas AREAS :today DATE :sprint RANGE).
Each area is a plist with :label and :projects."
  (let (areas listed)
    (dolist (cat (me/org-agenda--categories))
      (unless (nth 5 cat) ;. top-level entries are the areas
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
    (list :areas areas :today (me/dashboard--today) :sprint (me/dashboard--sprint-range))))

;; ---- dashboard SVG renderers: each returns an `svg' object, shared by the buffer (`svg-image') and the HTML block (`svg-print')

(defconst me/dashboard-risk-colors ;> fixed state colours — readable on both light and dark themes
  '((done . "#6ac4a0") (ok . "#7cb8e8") (risk . "#f0b35a") (late . "#ef7a7a"))
  "Alist from risk state to its hex colour.")

(defun me/dashboard--palette (&optional html) ;> (:fg :track :grid) colours; HTML output uses currentColor so the theme decides
  "Return the neutral colours as a plist.
With HTML non-nil they are theme-relative; otherwise they come from the
current theme."
  (if html
      '(:fg "currentColor" :track "#8884" :grid "#8883")
    (let ((dark (eq (frame-parameter nil 'background-mode) 'dark)))
      (list :fg (face-foreground 'default nil t)
            :track (if dark "#2a2a2a" "#e0e0e0") :grid (if dark "#303030" "#dddddd")))))

(defun me/dashboard--bar-svg (done total width height color &optional track) ;> pill bar filled to DONE/TOTAL; TOTAL 0 draws only the track
  "Return an svg of a WIDTH×HEIGHT progress bar in COLOR over TRACK.
The bar fills DONE of TOTAL."
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
  "Return the day-number range shared by every timeline of MILESTONES.
TODAY is a date string and extends the range."
  (let* ((today-n (me/dashboard--day-number today))
         (rows (seq-filter (lambda (m) (plist-get m :deadline)) milestones))
         (starts (mapcar (lambda (m) (me/dashboard--day-number (or (plist-get m :start) (plist-get m :deadline)))) rows))
         (ends (mapcar (lambda (m) (me/dashboard--day-number (plist-get m :deadline))) rows)))
    (cons (- (max (- today-n 60) (apply #'min today-n starts)) 3)
          (+ (apply #'max today-n ends) 5))))

(defun me/dashboard--timeline-svg (milestones width today &optional sprint colors range) ;> one bar per dated unfinished milestone, start→deadline, filled by progress; nil when none
  "Return the timeline svg of MILESTONES.
Each milestone is a plist with :title :start :deadline :done :total :risk.
WIDTH is the image width in pixels.
TODAY and the SPRINT (START . END) are date strings; COLORS is a
`me/dashboard--palette' plist; RANGE is a (LO . HI) day-number span from
`me/dashboard--timeline-range', so several charts share one scale."
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
  "Return a burn-up sparkline svg of SERIES.
Return nil when SERIES has fewer than two points.  WIDTH and HEIGHT
default to 100 and 24.  COLOR draws the line; COLORS is the palette."
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
  "Return ((TAG . TASKS) ...) for the cross-cutting tags that have tasks.
DATA is the plist from `me/dashboard-data'."
  (let ((projects (me/dashboard--projects data)) result)
    (dolist (tag me/org-agenda-crosscutting-tags)
      (let (tasks)
        (dolist (p projects)
          (dolist (task (plist-get p :tasks))
            (when (member tag (plist-get task :tags))
              (push (append (list :project (plist-get p :label)) task) tasks))))
        (when tasks (push (cons tag (nreverse tasks)) result))))
    (nreverse result)))

(defun me/dashboard--sum (projects key) ;> total of the numeric KEY over PROJECTS
  "Return the sum of KEY over the project plists PROJECTS."
  (apply #'+ (mapcar (lambda (p) (plist-get p key)) projects)))

(defun me/dashboard--front-layout (project) ;> fronts with their milestones; a front that is itself a milestone shows as one row
  "Return (ROWS . REST) for PROJECT.
Each of ROWS is (FRONT MILESTONES SELF): the milestones under FRONT and the
milestone that is the front itself, or nil.  REST lists the milestones that
no front claims."
  (let ((milestones (plist-get project :milestones)) placed rows)
    (dolist (front (plist-get project :fronts))
      (let* ((name (nth 0 front))
             (ms (seq-filter (lambda (m) (equal (plist-get m :front) name)) milestones))
             (self (seq-find (lambda (m) (and (null (plist-get m :front))
                                              (equal (plist-get m :title) name)))
                             milestones)))
        (setq placed (append placed ms (and self (list self))))
        (push (list front ms self) rows)))
    (cons (nreverse rows) (seq-remove (lambda (m) (memq m placed)) milestones))))

(defun me/dashboard--deadline-text (m) ;> "10-16 · 3d left", "10-10 · 2d late" or "no deadline"
  "Return the deadline and days left of the milestone plist M."
  (if-let* ((deadline (plist-get m :deadline)))
      (let ((left (me/dashboard--days-left deadline)))
        (format "%s · %s" (substring deadline 5)
                (if (< left 0) (format "%dd late" (- left)) (format "%dd left" left))))
    "no deadline"))

(defun me/dashboard--days-left (deadline) ;> whole days from today to DEADLINE, negative when past
  "Return the days between today and the \"YYYY-MM-DD\" DEADLINE."
  (- (me/dashboard--day-number deadline) (me/dashboard--day-number (me/dashboard--today))))

;; ---- dashboard buffer (magit-section + svg.el)

(defvar-local me/dashboard--targets nil ;> buffer-local hash: section value (string) → marker or file, read by RET
  "Where each dashboard row jumps to.")

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
  "Return the inline bar of DONE/TOTAL in COLOR, HEIGHT pixels tall."
  (me/dashboard--image
   (me/dashboard--bar-svg done total 120 (or height 10) color (plist-get (me/dashboard--palette) :track))))

(defun me/dashboard--line (indent title done total color &optional tail face) ;> "  title ····· [bar]  13/21  tail", bar at a fixed column
  "Return a row string indented by INDENT.
It holds TITLE in FACE, a progress bar in COLOR at the bar column,
DONE/TOTAL, then TAIL."
  (concat (make-string indent ?\s)
          (propertize (truncate-string-to-width title (- me/dashboard-bar-column indent 2) nil nil "…")
                      'face (or face 'default) 'font-lock-face (or face 'default))
          (me/dashboard--align me/dashboard-bar-column)
          (me/dashboard--bar-image done total color)
          (format " %3d/%-3d" done total)
          (if tail (concat "  " tail) "")))

(defun me/dashboard--head-line (indent label face done total color stats) ;> area/project heading: coloured name, bar right after it, then the numbers
  "Return a heading string indented by INDENT.
It holds LABEL in FACE, a bar for DONE/TOTAL in COLOR, then STATS."
  (concat (make-string indent ?\s)
          (propertize label 'face face 'font-lock-face face)
          "  "
          (when color (concat (me/dashboard--bar-image done total color 12) " "))
          (propertize (format "%d/%d" done total) 'face 'default 'font-lock-face 'default)
          (propertize (concat "  " stats) 'face 'shadow 'font-lock-face 'shadow)))

(defface me/dashboard-area '((t :inherit font-lock-function-name-face :weight bold)) ;> area names: the function-name colour of the theme
  "Face of area headings in the dashboard buffer."
  :group 'me-dashboard)

(defface me/dashboard-project '((t :inherit font-lock-keyword-face :weight bold)) ;> project names: the keyword colour of the theme
  "Face of project headings in the dashboard buffer."
  :group 'me-dashboard)

(defun me/dashboard--milestone-line (m indent) ;> milestone row: ◆ title, bar, deadline, days left, risk
  "Return the buffer row for the milestone plist M, indented by INDENT."
  (let* ((risk (plist-get m :risk))
         (tail (concat (me/dashboard--deadline-text m)
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
         (layout (me/dashboard--front-layout project)))
    (magit-insert-section (project key nil)
			  (magit-insert-heading
			   (me/dashboard--head-line
			    2 label 'me/dashboard-project done total (me/dashboard--risk-color nil)
			    (format "14d: %d · sprint: %d · waiting: %d"
				    (plist-get project :closed14) (plist-get project :closed-sprint) (plist-get project :wait))))
			  (if-let* ((next (plist-get project :next)))
			      (magit-insert-section (next (me/dashboard--target (format "next|%s" label) (plist-get next :marker)) nil)
						    (insert "    " (propertize "NEXT" 'face 'success) " "
							    (plist-get next :title) "\n"))
			    (when (plist-get project :area)
			      (insert (propertize "    no NEXT defined\n" 'face 'shadow))))
			  (pcase-dolist (`(,front ,ms ,self) (car layout))
			    (let ((name (nth 0 front)))
			      (magit-insert-section (front (me/dashboard--target (format "front|%s|%s" label name) (nth 3 front)) nil)
						    (magit-insert-heading
						     (if self
							 (me/dashboard--milestone-line self 4)
						       (me/dashboard--line 4 name (nth 1 front) (nth 2 front)
									   (if (me/dashboard--finished-p (nth 1 front) (nth 2 front))
									       (cdr (assq 'done me/dashboard-risk-colors))
									     "#8a8f98"))))
						    (dolist (m ms)
						      (magit-insert-section (milestone (me/dashboard--target (format "ms|%s|%s|%s" label name (plist-get m :title))
													     (plist-get m :marker))
										       nil)
									    (insert (me/dashboard--milestone-line m 6) "\n"))))))
			  (dolist (m (cdr layout)) ;. milestones that are themselves a front
			    (magit-insert-section (milestone (me/dashboard--target (format "ms|%s||%s" label (plist-get m :title))
										   (plist-get m :marker))
							     nil)
						  (insert (me/dashboard--milestone-line m 4) "\n")))
			  (when-let* ((series (me/dashboard--sparkline-svg (me/dashboard--history label))))
			    (insert "    " (propertize "burn-up " 'face 'shadow) (me/dashboard--image series) "\n")))))

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
      (magit-insert-section (timeline "timeline" nil)
			    (magit-insert-heading (propertize "Timeline" 'face 'me/dashboard-area 'font-lock-face 'me/dashboard-area))
			    (when image (insert "  " (me/dashboard--image image) "\n"))
			    (dolist (m undated)
			      (insert (propertize "  no deadline: " 'face 'shadow) (plist-get m :title) "\n"))
			    (insert "\n")))))

(defun me/dashboard--insert-crosscutting (data) ;> one section per cross-cutting tag listing its active tasks
  "Insert the cross-cutting tag sections of DATA."
  (dolist (group (me/dashboard--crosscutting data))
    (magit-insert-section (tag (format "tag|%s" (car group)) nil)
			  (magit-insert-heading (propertize (format "#%s" (car group)) 'face 'bold)
						(propertize (format "  %d tasks" (length (cdr group))) 'face 'shadow))
			  (dolist (task (cdr group))
			    (magit-insert-section (task (me/dashboard--target (format "task|%s|%s" (car group) (plist-get task :title))
									      (plist-get task :marker)) nil)
						  (insert (format "    %-5s %s " (plist-get task :state) (plist-get task :title))
							  (propertize (format "(%s)" (plist-get task :project)) 'face 'shadow) "\n")))
			  (insert "\n"))))

(defun me/dashboard-refresh (&optional data) ;> rebuild the buffer from the current files; folds and point survive
  "Rebuild the dashboard in the current buffer from DATA or a fresh scan."
  (interactive)
  (let* ((inhibit-read-only t)
         (ident (and (magit-current-section) (magit-section-ident (magit-current-section))))
         (data (or data (me/dashboard-data))))
    (clrhash me/dashboard--targets)
    (erase-buffer)
    (magit-insert-section (dashboard nil nil)
			  (me/dashboard--insert-header data)
			  (me/dashboard--insert-timeline data)
			  (dolist (area (plist-get data :areas))
			    (let ((projects (plist-get area :projects)))
			      (magit-insert-section (area (format "area|%s" (plist-get area :label)) nil)
						    (magit-insert-heading
						     (me/dashboard--head-line
						      0 (plist-get area :label) 'me/dashboard-area
						      (me/dashboard--sum projects :done) (me/dashboard--sum projects :total) nil
						      (format "14d: %d · sprint: %d · waiting: %d"
							      (me/dashboard--sum projects :closed14)
							      (me/dashboard--sum projects :closed-sprint)
							      (me/dashboard--sum projects :wait))))
						    (mapc #'me/dashboard--insert-project projects)
						    (insert "\n"))))
			  (me/dashboard--insert-crosscutting data))
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

;;;###autoload
(defun me/dashboard () ;> open (or refresh) the *Dashboard* buffer
  "Show the project dashboard."
  (interactive)
  (require 'magit-section)
  (require 'svg)
  (let ((buffer (get-buffer-create "*Dashboard*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'me/dashboard-mode) (me/dashboard-mode))
      (let ((data (me/dashboard-data)))
        (me/dashboard--snapshot (plist-get data :areas)) ;. a snapshot per day: opening the dashboard is the trigger, `g' is not
        (me/dashboard-refresh data)))
    (pop-to-buffer-same-window buffer)))

(defun me/org-milestone-finished-p (milestone) ;> true when it has TODO descendants and every one is done
  "Return non-nil when the milestone plist MILESTONE is finished."
  (me/dashboard--finished-p (plist-get milestone :done) (plist-get milestone :total)))

(defun me/org-agenda-group-key (item) ;> org-super-agenda :auto-map key: "Area / Project / outline path" of the agenda ITEM
  "Return the group header for agenda ITEM.
Built from its file's category and outline path."
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
  "Return the next heading's position if the milestone at point is finished.
Return nil otherwise."
  (let ((progress (me/org-milestone-progress)))
    (when (me/dashboard--finished-p (car progress) (cdr progress))
      (save-excursion (or (outline-next-heading) (point-max))))))

;;;###autoload
(defun me/org-agenda-milestone-prefix () ;> %(…) prefix for milestone lines: "done/total  dd/mm", "—" when undated
  "Return \"DONE/TOTAL DEADLINE\" for the milestone heading at point."
  (let ((progress (me/org-milestone-progress))
        (deadline (me/org-milestone--date "DEADLINE")))
    (format "%2d/%-2d %s" (car progress) (cdr progress)
            (if deadline
                (format-time-string "%d/%m" (date-to-time (concat deadline " 00:00")))
              "  —  "))))

;;;###autoload
(defun me/org-agenda-toggle-group () ;> TAB on a super-agenda group header: hide/show the task lines under it
  "Collapse or expand the group whose header line is at point."
  (interactive)
  (if (save-excursion (forward-line 1) (invisible-p (point)))
      (outline-show-subtree)
    (outline-hide-subtree)))

;;;###autoload
(defun me/org-agenda-dashboard-setup () ;> finalize hook: outline folding in the Dashboard buffer only (agenda redo resets it)
  "Enable header folding when the current agenda buffer is the Dashboard."
  (when (equal (buffer-name) "*Org Agenda: Dashboard*")
    (setq-local outline-regexp "^ [^ ]" ;. a group header is the only line starting with exactly one space
                outline-level (lambda () 1))
    (outline-minor-mode 1)))

;;;###autoload
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
  "Return one progress row: TITLE, bar for DONE of TOTAL in COLOR, then TAIL."
  (concat (format "<span>%s</span>" title)
          (me/dashboard--html-svg (me/dashboard--bar-svg done total 160 10 color))
          (format "<span>%d/%d</span>" done total)
          (format "<span>%s</span>" (or tail ""))))

(defun me/dashboard--html-deadline (m) ;> "10-16 · 3d left [at risk]" for milestone M
  "Return the deadline, days left and risk badge of the milestone plist M as HTML."
  (let ((risk (plist-get m :risk)))
    (format "%s%s"
            (me/dashboard--deadline-text m)
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
                      ((me/dashboard--finished-p done total) 'done)))
         (totals (me/dashboard--totals (list project)))
         (colors (me/dashboard--palette t))
         (tasks (mapcar (lambda (task) (append (list :area area) task)) (plist-get project :tasks)))
         (layout (me/dashboard--front-layout project)))
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
      (pcase-lambda (`(,front ,ms ,self))
        (let* ((name (nth 0 front))
               (mine (seq-filter (lambda (task) (equal (or (car (plist-get task :path)) me/dashboard--loose-label) name)) tasks))
               (row (and self (plist-get self :title))))
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
      (car layout) "")
     (mapconcat (lambda (m) (concat (me/dashboard--html-milestone m) "\n")) (cdr layout) "")
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
                      (let* ((front (or (car (plist-get task :path)) me/dashboard--loose-label))
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

(defvar me/dashboard-file "agenda/dashboard.org" ;> the document holding the `me-dashboard' dynamic block, relative to `me/org-directory'
  "Org file that `me/dashboard-export' updates and exports.")

(defvar me/dashboard--export-data nil
  "Model `me/dashboard-export' scanned, reused by the dynamic block it updates.")

;;;###autoload
(defun org-dblock-write:me-dashboard (_params) ;> dynamic block: the dashboard as one export block (KPIs, timelines, project cards, task lists, area filter)
  "Write the dashboard HTML into the dynamic block at point."
  (require 'svg)
  (insert "#+begin_export html\n"
          (me/dashboard--html (or me/dashboard--export-data (me/dashboard-data)))
          "\n#+end_export\n"))

;;;###autoload
(defun me/dashboard-export () ;> update the dashboard.org block and export it to HTML (same as C-c C-e h h there)
  "Refresh the dynamic block of the dashboard document and export it."
  (interactive)
  (let ((file (me/org-file me/dashboard-file)))
    (unless (file-exists-p file)
      (user-error "No dashboard document at %s" file))
    (let ((me/dashboard--export-data (me/dashboard-data)))
      (me/dashboard--snapshot (plist-get me/dashboard--export-data :areas))
      (with-current-buffer (find-file-noselect file)
        (org-update-all-dblocks)
        (save-buffer)
        (let ((out (org-html-export-to-html)))
          (message "Dashboard exported to %s" out)
          out)))))

(provide 'me-dashboard)
;;; me-dashboard.el ends here
