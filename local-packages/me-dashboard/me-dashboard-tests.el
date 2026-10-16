;;; me-dashboard-tests.el --- Tests for me-dashboard -*- lexical-binding: t -*-

;; Run:  make test LOADPATH="-L <dir with magit-section>"

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'me-dashboard)

(defmacro me-dashboard-tests--with-config (org-text &rest body)
  "Run BODY with a temp org root holding proj.org with ORG-TEXT.
`me/org-file' and the category functions are stubbed: one area, \"Work\",
backed by proj.org.  The history file is agenda/history.csv in the root."
  (declare (indent 1))
  `(let* ((root (make-temp-file "me-dash" t))
          (me/org-directory root)
          (me/dashboard-history-file "history.csv")
          (me/dashboard-today nil)
          (me/org-sprint-start nil)
          (me/dashboard--rows-cache nil)
          (proj (expand-file-name "proj.org" root)))
     (unwind-protect
         (progn
           (with-temp-file proj (insert ,org-text))
           (let ((org-agenda-files (list proj))
                 (org-inhibit-startup t))
             (cl-letf (((symbol-function 'me/org-file)
                        (lambda (rel) (expand-file-name rel root)))
                       ((symbol-function 'me/org-agenda--categories)
                        (lambda () '(("work" "Work" "proj.org" nil nil nil))))
                       ((symbol-function 'me/org-agenda-category-children)
                        (lambda (_) nil))
                       ((symbol-function 'me/org-agenda-category-for-file)
                        (lambda (_) nil)))
               ,@body)))
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p root (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory root t))))

(defun me-dashboard-tests--areas ()
  "A one-project areas list for the snapshot tests."
  '((:label "Work" :projects ((:label "Proj" :done 1 :total 2 :closed14 0)))))

(defun me-dashboard-tests--lines (file)
  "Lines of FILE."
  (with-temp-buffer (insert-file-contents file) (split-string (buffer-string) "\n" t)))

(ert-deftest me-dashboard-tasks-above-first-heading-are-loose ()
  (me-dashboard-tests--with-config "** TODO orphan\n* Front\n** TODO inside\n"
    (let* ((data (me/dashboard-data))
           (project (car (plist-get (car (plist-get data :areas)) :projects)))
           (fronts (plist-get project :fronts)))
      (should (= (plist-get project :total) 2))
      (should (equal (assoc me/dashboard--loose-label fronts)
                     (list me/dashboard--loose-label 0 1 nil)))
      (should (equal (cdr (assoc "Front" fronts)) (list 0 1 (nth 3 (assoc "Front" fronts))))))))

(ert-deftest me-dashboard-snapshot-adds-missing-newline ()
  (me-dashboard-tests--with-config "* Front\n** TODO a\n"
    (let ((file (me/org-file me/dashboard-history-file)))
      (with-temp-file file
        (insert "date,project,done,total,closed14\n2020-01-01,Old,1,2,0"))
      (let ((me/dashboard-today nil))
        (me/dashboard--snapshot (me-dashboard-tests--areas)))
      (let ((lines (me-dashboard-tests--lines file)))
        (should (= (length lines) 3))
        (should (equal (nth 1 lines) "2020-01-01,Old,1,2,0"))
        (should (= (length (split-string (nth 2 lines) ",")) 5))))))

(ert-deftest me-dashboard-simulated-day-writes-no-row ()
  (me-dashboard-tests--with-config "* Front\n** TODO a\n"
    (let ((file (me/org-file me/dashboard-history-file))
          (me/dashboard-today "2030-01-02"))
      (me/dashboard--snapshot (me-dashboard-tests--areas))
      (should-not (file-exists-p file)))))

(ert-deftest me-dashboard-snapshot-is-once-a-day ()
  (me-dashboard-tests--with-config "* Front\n** TODO a\n"
    (let ((file (me/org-file me/dashboard-history-file)))
      (me/dashboard--snapshot (me-dashboard-tests--areas))
      (let ((n (length (me-dashboard-tests--lines file))))
        (should (= n 2))
        (me/dashboard--snapshot (me-dashboard-tests--areas))
        (should (= (length (me-dashboard-tests--lines file)) n))))))

(ert-deftest me-dashboard-data-writes-nothing ()
  (me-dashboard-tests--with-config "* Front\n** TODO a\n"
    (me/dashboard-data)
    (should-not (file-exists-p (me/org-file me/dashboard-history-file)))))

(ert-deftest me-dashboard-export-without-document-is-an-error ()
  (me-dashboard-tests--with-config "* Front\n** TODO a\n"
    (let ((me/dashboard-file "missing/dashboard.org"))
      (should-error (me/dashboard-export) :type 'user-error)
      (should-not (file-exists-p (me/org-file me/dashboard-file))))))

(ert-deftest me-dashboard-finished-predicate ()
  (should (me/dashboard--finished-p 3 3))
  (should-not (me/dashboard--finished-p 0 0))
  (should-not (me/dashboard--finished-p 2 3)))

(provide 'me-dashboard-tests)
;;; me-dashboard-tests.el ends here
