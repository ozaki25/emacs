(prefer-coding-system 'utf-8)
(setq ruby-insert-encoding-magic-comment nil)
(require 'package)
(add-to-list 'package-archives
	     '("melpa" . "http://melpa.milkbox.net/packages/") t)
(package-initialize)

(setq default-tab-width 2)
