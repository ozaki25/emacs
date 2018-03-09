(prefer-coding-system 'utf-8)
(setq ruby-insert-encoding-magic-comment nil)
(add-to-list 'load-path "~/.emacs.d/elpa")
(require 'package)
(add-to-list 'package-archives
	     '("melpa" . "http://melpa.milkbox.net/packages/") t)
(package-initialize)
(require 'git-complete)

(setq default-tab-width 2)
(setq-default indent-tabs-mode nil)
(show-paren-mode 1)
(setq-default show-trailing-whitespace t)
(column-number-mode t)
(setq js-indent-level 2)
(setq highlight-indentation-offset 2)

(add-to-list 'auto-mode-alist '(".*\\.js\\'" . rjsx-mode))
(add-hook 'js2-mode-hook (lambda () (setq js2-basic-offset 2)))
(setq-default js2-strict-trailing-comma-warning nil)
(setq-default js2-strict-missing-semi-warning nil)

(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                js-mode-hook
                js2-mode-hook
                js3-mode-hook
                typescript-mode-hook
                sgml-mode-hook
                yaml-mode-hook
                json-mode-hook))
  (add-hook hook 'highlight-indentation-current-column-mode)
  (add-hook hook 'projectile-rails-mode))

(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                js-mode-hook
                js2-mode-hook
                js3-mode-hook
                typescript-mode-hook
                sgml-mode-hook
                yaml-mode-hook
                json-mode-hook
                jsx-mode-hook
                java-mode-hook
                scala-mode-hook
                text-mode-hook))
  (add-hook hook 'auto-complete-mode))

(add-hook 'typescript-mode-hook
          (lambda ()
            (tide-setup)
            (flycheck-mode t)))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(markdown-list-indent-width 10))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
