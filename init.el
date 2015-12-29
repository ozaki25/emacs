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
(setq highlight-indentation-current-column-mode)

(setq-default auto-complete-mode)
