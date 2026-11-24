;;; me-task.el --- Task files for Org agenda headings -*- lexical-binding: t -*-

;; Author: Mahatmus
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: outlines, tools
;; URL: https://github.com/mahatmus-tech/emacs

;; This file is not part of GNU Emacs.
;; It is licensed like the rest of this configuration (MIT), see LICENSE.

;;; Commentary:

;; A task is an agenda heading; its state, deadline and TASK_* properties
;; live there.  `me/task-open' gives the heading a task file under
;; roam/projects/<company>/tasks/, built from one shared template, where the
;; task text, the AI context, the MR description and the log are kept.
;; The company comes from the agenda file's "#+PROPERTY: TASK_PROFILE" line.
;;
;; The `org-task' Claude skill writes the same files from the same template,
;; so the layout is defined once, in `me/task-template-file'.
;;
;; The package expects the host configuration to define `me/org-directory'
;; and `me/org-file'; see custom.el in this repository.

;;; Code:

(require 'org)
(require 'org-id)
(require 'ucs-normalize)

(defvar me/org-directory)
(declare-function me/org-file "custom" (relative))

(defvar me/task-template-file "roam/resources/task-template.org" ;> the task file skeleton, relative to `me/org-directory'; shared with the org-task skill
  "Template of a task file, relative to `me/org-directory'.
Its placeholders are {{ID}}, {{SOURCE_ID}}, {{TITLE}}, {{PROFILE}} and {{DATE}}.")

(defvar me/task-directory-format "roam/projects/%s/tasks/" ;> where task files go, relative to `me/org-directory'; %s is the TASK_PROFILE value
  "Directory of a company's task files, relative to `me/org-directory'.
The %s is replaced by the company, the value of TASK_PROFILE.")

(defun me/task--slug (title)
  "Return TITLE as a file name slug.
Lowercase, diacritics removed, every other run of characters as one hyphen."
  (let* ((s (ucs-normalize-NFD-string (downcase title)))
         (s (replace-regexp-in-string "[̀-ͯ]" "" s))
         (s (replace-regexp-in-string "[^a-z0-9]+" "-" s)))
    (string-trim s "-+" "-+")))

(defun me/task-file-p (&optional file)
  "Return non-nil when FILE is a task file.
FILE defaults to the file the current buffer visits."
  (let ((file (or file buffer-file-name)))
    (and file
         (string-match-p "/roam/projects/[^/]+/tasks/[^/]+\\.org\\'" file)
         t)))

(defun me/task--create ()
  "Create the task file of the heading at point and return its absolute path.
Give the heading an ID and a TASK_FILE property, and save its buffer."
  (let* ((profile (or (org-entry-get nil "TASK_PROFILE" t)
                      (user-error "No TASK_PROFILE: add \"#+PROPERTY: TASK_PROFILE <company>\" to this file")))
         (title (org-get-heading t t t t))
         (rel (concat (format me/task-directory-format profile)
                      (format-time-string "%Y-%m-%d") "-" (me/task--slug title) ".org"))
         (file (me/org-file rel)))
    (when (file-exists-p file)
      (user-error "Task file already exists: %s" rel))
    (let ((source-id (org-id-get-create)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert-file-contents (me/org-file me/task-template-file))
        (dolist (pair `(("{{ID}}" . ,(org-id-new))
                        ("{{SOURCE_ID}}" . ,source-id)
                        ("{{TITLE}}" . ,title)
                        ("{{PROFILE}}" . ,profile)
                        ("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))))
          (goto-char (point-min))
          (while (search-forward (car pair) nil t)
            (replace-match (cdr pair) t t))))
      (org-entry-put nil "TASK_FILE" rel)
      (save-buffer)
      file)))

;;;###autoload
(defun me/task-open ()
  "Open the task file of the heading at point, creating it when missing.
Work on an Org heading and on the task under point in an agenda buffer.
Refresh the summary table of the task file after opening it."
  (interactive)
  (let* ((marker (cond ((derived-mode-p 'org-agenda-mode)
                        (or (org-get-at-bol 'org-hd-marker)
                            (user-error "No task on this line")))
                       ((derived-mode-p 'org-mode) (point-marker))
                       (t (user-error "Not in an Org or agenda buffer"))))
         (file (org-with-point-at marker
                 (org-back-to-heading t)
                 (let ((rel (org-entry-get nil "TASK_FILE")))
                   (if rel (me/org-file rel) (me/task--create))))))
    (unless (file-exists-p file)
      (user-error "TASK_FILE points to a missing file: %s" file))
    (find-file file)
    (ignore-errors (org-update-all-dblocks))
    (when (buffer-modified-p)
      (save-buffer))))

(provide 'me-task)
;;; me-task.el ends here
