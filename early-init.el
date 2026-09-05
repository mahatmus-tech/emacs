;;; early-init.el --- Mahatmus Emacs Configuration -*- lexical-binding: t -*-
;;; ------------------------------------------------------------------- Visuals
(setq inhibit-startup-screen t)                                       ;> disables start-up splash screen
(setq inhibit-startup-message t)                                      ;> disables start-up message
(setq frame-inhibit-implied-resize t)                                 ;> prevents resizing frame on UI elements changes
(tooltip-mode -1)                                                     ;> disable tooltips
(tool-bar-mode -1)                                                    ;> disable tool bar
(menu-bar-mode -1)                                                    ;> disable menu bar
(scroll-bar-mode -1)                                                  ;> disable scroll bar
(set-fringe-mode 10)                                                  ;> set fringe size
(let ((colors                                                         ;> load last theme colors
       (expand-file-name "frame-colors.el" user-emacs-directory)))
  (when (file-exists-p colors) (load colors nil t)))
;;; ------------------------------------------------------------------- Performance
(setq package-enable-at-startup nil)                                  ;> disable built-in package.el, straight handles everything
(setq site-run-file nil)                                              ;> disable search in load-path for site-start.el
(setq load-prefer-newer t)                                            ;> [fix]: an edited .el must beat a stale sibling .elc — a July ob-json.elc
                                                                      ;. silently shadowed the August source for weeks
(setq gc-cons-threshold most-positive-fixnum)                         ;> maximize gc threshold during startup
(setq gc-cons-percentage 0.6)                                         ;> defer GC more aggressively during startup
(defvar me/file-name-handler-alist-backup file-name-handler-alist)    ;> save file-name-handler-alist for post-startup restore
(setq file-name-handler-alist nil)                                    ;> skip handler lookups during startup for faster load
