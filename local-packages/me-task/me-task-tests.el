;;; me-task-tests.el --- Tests for me-task -*- lexical-binding: t -*-

;; Run:  make test

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'me-task)

(defconst me-task-tests--template
  ":PROPERTIES:\n:ID:       {{ID}}\n:TASK_SOURCE: {{SOURCE_ID}}\n:END:\n#+title: {{TITLE}}\n#+filetags: :task:{{PROFILE}}:\n#+date: {{DATE}}\n\n#+BEGIN: columnview :id \"{{SOURCE_ID}}\" :skip-empty-rows t :format \"%ITEM(Task) %TODO(Estado) %TASK_REF(ID) %TASK_TYPE(Tipo) %DEADLINE(Prazo) %TASK_MR(MR)\"\n#+END:\n\n* Task\n* Contexto IA\n* MR\n* Log\n"
  "A task template with every placeholder.")

(defmacro me-task-tests--with-root (org-text &rest body)
  "Run BODY in a temp org root whose agenda/work.org holds ORG-TEXT.
`me/org-file' is stubbed to resolve under the root, the template is in
place, and point starts at the first heading of work.org."
  (declare (indent 1))
  `(let* ((root (make-temp-file "me-task" t))
          (me/org-directory root)
          (org-id-locations-file (expand-file-name "ids" root))
          (org-id-locations nil)
          (org-inhibit-startup t)
          (work (expand-file-name "agenda/work.org" root)))
     (unwind-protect
         (cl-letf (((symbol-function 'me/org-file)
                    (lambda (rel) (expand-file-name rel root))))
           (make-directory (expand-file-name "agenda" root) t)
           (make-directory (expand-file-name "roam/resources" root) t)
           (with-temp-file (expand-file-name me/task-template-file root)
             (insert me-task-tests--template))
           (with-temp-file work (insert ,org-text))
           (let ((org-agenda-files (list work)))
             (find-file work)
             (goto-char (point-min))
             (re-search-forward "^\\*+ ")
             ,@body))
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p root (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory root t))))

(defun me-task-tests--task-files (root)
  "Task files under ROOT."
  (directory-files-recursively (expand-file-name "roam/projects" root) "\\.org\\'"))

(ert-deftest me-task-slug-strips-accents-and-punctuation ()
  (should (equal (me/task--slug "Política de retentativa na Yuno (ação)")
                 "politica-de-retentativa-na-yuno-acao"))
  (should (equal (me/task--slug "[payments-hub] Endpoint  X!") "payments-hub-endpoint-x")))

(ert-deftest me-task-file-p-matches-only-task-files ()
  (should (me/task-file-p "/o/roam/projects/acme/tasks/2026-01-01-a.org"))
  (should-not (me/task-file-p "/o/roam/projects/acme/notes/a.org"))
  (should-not (me/task-file-p "/o/agenda/work.org"))
  (should-not (me/task-file-p nil)))

(ert-deftest me-task-open-creates-file-from-template ()
  (me-task-tests--with-root
      "#+PROPERTY: TASK_PROFILE acme\n* Inbox\n** TODO [#A] Política X :tag:\nDEADLINE: <2030-01-02 Wed>\n"
    (re-search-forward "Política")
    (me/task-open)
    (let ((file buffer-file-name)
          (text (buffer-string)))
      (should (me/task-file-p file))
      (should (string-suffix-p "-politica-x.org" file))
      (should (string-match-p "^#\\+title: Política X$" text))
      (should (string-match-p "^#\\+filetags: :task:acme:$" text))
      (should-not (string-match-p "{{" text))
      (should (string-match-p "| Política X +| TODO +|" text))
      (should (string-match-p "2030-01-02" text))
      (with-current-buffer (find-buffer-visiting work)
        (re-search-backward "Política")
        (should (org-entry-get nil "ID"))
        (should (equal (me/org-file (org-entry-get nil "TASK_FILE")) file))
        (should (string-match-p (regexp-quote (org-entry-get nil "ID")) text))
        (should-not (buffer-modified-p))))))

(ert-deftest me-task-open-twice-reuses-the-file ()
  (me-task-tests--with-root "#+PROPERTY: TASK_PROFILE acme\n* TODO One\n"
    (me/task-open)
    (let ((first buffer-file-name))
      (with-current-buffer (find-buffer-visiting work)
        (org-todo "DONE")
        (save-buffer)
        (me/task-open))
      (should (equal buffer-file-name first))
      (should (= 1 (length (me-task-tests--task-files root))))
      (should (string-match-p "| One +| DONE +|" (buffer-string))))))

(ert-deftest me-task-open-without-profile-errors ()
  (me-task-tests--with-root "* TODO One\n"
    (should-error (me/task-open) :type 'user-error)
    (should-not (file-directory-p (expand-file-name "roam/projects" root)))
    (should-not (org-entry-get nil "TASK_FILE"))))

(ert-deftest me-task-open-missing-file-errors ()
  (me-task-tests--with-root
      "#+PROPERTY: TASK_PROFILE acme\n* TODO One\n:PROPERTIES:\n:TASK_FILE: roam/projects/acme/tasks/gone.org\n:END:\n"
    (should-error (me/task-open) :type 'user-error)
    (should-not (file-directory-p (expand-file-name "roam/projects" root)))))

(ert-deftest me-task-agenda-match-lists-only-unsent-tasks ()
  (me-task-tests--with-root
      "* TODO plain\n* TODO unsent\n:PROPERTIES:\n:TASK_FILE: a.org\n:END:\n* TODO sent\n:PROPERTIES:\n:TASK_FILE: b.org\n:TASK_REF: ID-1\n:END:\n* DONE closed\n:PROPERTIES:\n:TASK_FILE: c.org\n:END:\n"
    (should (equal (org-map-entries (lambda () (org-get-heading t t t t))
                                    "TASK_FILE={.+}-TASK_REF={.+}/!" 'file)
                   '("unsent")))))

(provide 'me-task-tests)
;;; me-task-tests.el ends here
