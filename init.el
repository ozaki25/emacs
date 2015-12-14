(set-language-environment "Japanese")
(prefer-coding-system 'utf-8)
(setq ruby-insert-encoding-magic-comment nil)

(require 'package)
(add-to-list 'package-archives
	     '("melpa" . "http://melpa.milkbox.net/packages/") t)
(package-initialize)
(unless (package-installed-p 'scala-mode2)
    (package-refresh-contents) (package-install 'scala-mode2))

(require 'coffee-mode)
(defun coffee-custom ()
  "coffee-mode-hook"
  (and (set (make-local-variable 'tab-width) 2)
       (set (make-local-variable 'coffee-tab-width) 2))
  )

(add-hook 'coffee-mode-hook
	    '(lambda() (coffee-custom)))

(require 'highlight-indentation)
(setq highlight-indentation-offset 2)
(set-face-background 'highlight-indentation-current-column-face "#ff0000")
;;(add-hook 'highlight-indentation-mode-hook 'highlight-indentation-current-column-mode)
;;(add-hook 'coffee-mode-hook 'highlight-indentation-mode)
;;(add-hook 'sass-mode-hook 'highlight-indentation-mode)
(add-hook 'coffee-mode-hook 'highlight-indentation-current-column-mode)
(add-hook 'sass-mode-hook   'highlight-indentation-current-column-mode)
(add-hook 'haml-mode-hook 'highlight-indentation-current-column-mode)

(require 'jsx-mode)
(add-to-list 'auto-mode-alist '("\\.jsx\\'" . jsx-mode))
(setq jsx-indent-level 2)
(add-hook 'jsx-mode-hook '(lambda () (electric-indent-local-mode -1)))
