(prefer-coding-system 'utf-8)
(setq ruby-insert-encoding-magic-comment nil)
(require 'package)
(add-to-list 'package-archives
	     '("melpa" . "http://melpa.milkbox.net/packages/") t)
(package-initialize)

(setq default-tab-width 1)
(setq-default indent-tabs-mode nil)
(show-paren-mode 1)
(setq-default show-trailing-whitespace t)
(column-number-mode t)

(setq highlight-indentation-offset 2)

(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                js3-mode-hook
                html-mode-hook
                yaml-mode))
  (add-hook hook 'highlight-indentation-current-column-mode)
  (add-hook hook 'projectile-rails-mode))

(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                js3-mode-hook
                html-mode-hook
                java-mode
                scala-mode
                text-mode))
  (add-hook hook 'auto-complete-mode))

