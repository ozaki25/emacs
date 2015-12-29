(prefer-coding-system 'utf-8)
(setq ruby-insert-encoding-magic-comment nil)
(require 'package)
(add-to-list 'package-archives
	     '("melpa" . "http://melpa.milkbox.net/packages/") t)
(package-initialize)

(setq default-tab-width 2)
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
                ts-mode-hook
                sgml-mode-hook
                yaml-mode-hook
                json-mode-hook))
  (add-hook hook 'highlight-indentation-current-column-mode)
  (add-hook hook 'projectile-rails-mode))

(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                js3-mode-hook
                ts-mode-hook
                sgml-mode-hook
                yaml-mode-hook
                json-mode-hook
                jsx-mode-hook
                java-mode-hook
                scala-mode-hook
                text-mode-hook))
  (add-hook hook 'auto-complete-mode))

