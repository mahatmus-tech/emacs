;; -*- lexical-binding: t; -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-fold-catch-invisible-edits 'show-and-error nil nil "Customized with use-package org")
 '(safe-local-variable-values
   '((elisp-lint-indent-specs (describe . 1) (it . 1) (thread-first . 0) (cl-flet . 1) (cl-flet* . 1)
                              (org-element-map . defun) (org-roam-dolist-with-progress . 2)
                              (org-roam-with-temp-buffer . 1) (org-with-point-at . 1)
                              (magit-insert-section . defun) (magit-section-case . 0)
                              (org-roam-with-file . 2))
     (elisp-lint-ignored-validators "byte-compile" "package-lint")
     (eval progn
           (defun hermes-open-dev-user nil
             (interactive)
             (let ((root (locate-dominating-file default-directory "deps.edn")))
               (when root (find-file (expand-file-name "dev/user.clj" root)))))
           (local-set-key (kbd "C-c j r") #'hermes-open-dev-user))
     (eval progn
           (defun cider-send-go nil (interactive) (cider-interactive-eval "(do (ns user) (go))"))
           (defun cider-send-halt nil
             (interactive) (cider-interactive-eval "(do (ns user) (halt))"))
           (defun cider-send-reset nil
             (interactive) (cider-interactive-eval "(do (ns user) (reset))"))
           (defun cider-send-reload nil
             (interactive) (cider-interactive-eval "(do (ns user) (reload))"))
           (defun cider-send-reload-tests nil
             (interactive) (cider-interactive-eval "(do (ns user) (reload-tests))"))
           (local-set-key (kbd "C-c j g") #'cider-send-go)
           (local-set-key (kbd "C-c j h") #'cider-send-halt)
           (local-set-key (kbd "C-c j r") #'cider-send-reset)
           (local-set-key (kbd "C-c j l") #'cider-send-reload)
           (local-set-key (kbd "C-c j t") #'cider-send-reload-tests))
     (eval progn (make-variable-buffer-local 'cider-jack-in-nrepl-middlewares)
           (add-to-list 'cider-jack-in-nrepl-middlewares "flow-storm.nrepl.middleware/middleware")
           (defun cider-send-go nil (interactive) (cider-interactive-eval "(do (ns user) (go))"))
           (defun cider-send-halt nil
             (interactive) (cider-interactive-eval "(do (ns user) (halt))"))
           (defun cider-send-reset nil
             (interactive) (cider-interactive-eval "(do (ns user) (reset))"))
           (defun cider-send-reload nil
             (interactive) (cider-interactive-eval "(do (ns user) (reload))"))
           (defun cider-send-reload-tests nil
             (interactive) (cider-interactive-eval "(do (ns user) (reload-tests))"))
           (local-set-key (kbd "C-c j g") #'cider-send-go)
           (local-set-key (kbd "C-c j h") #'cider-send-halt)
           (local-set-key (kbd "C-c j r") #'cider-send-reset)
           (local-set-key (kbd "C-c j l") #'cider-send-reload)
           (local-set-key (kbd "C-c j t") #'cider-send-reload-tests))
     (cider-ns-refresh-after-fn . "user/go") (cider-ns-refresh-before-fn . "user/halt")
     (eval progn (make-variable-buffer-local 'cider-jack-in-nrepl-middlewares)
           (add-to-list 'cider-jack-in-nrepl-middlewares
                        "shadow.cljs.devtools.server.nrepl/middleware"))
     (eval progn
           (defun cider-send-reset nil
             "Send commands to CIDER to restart the development environment." (interactive)
             (cider-interactive-eval "(do (ns user) (reset))"))
           (defun cider-send-reload nil
             "Send commands to CIDER to reload the development environment." (interactive)
             (cider-interactive-eval "(do (ns user) (reload))"))
           (defun cider-send-reload-tests nil
             "Send commands to CIDER to reload test namespaces." (interactive)
             (cider-interactive-eval "(do (ns user) (reload-tests))"))
           (defun cider-send-go nil
             "Send commands to CIDER to start the system." (interactive)
             (cider-interactive-eval "(do (ns user) (go))"))))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
