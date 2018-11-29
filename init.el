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

(add-to-list 'auto-mode-alist '("\\.ts$" . typescript-mode))
(add-to-list 'auto-mode-alist '("\\.jst$" . html-mode))

(add-to-list 'auto-mode-alist '(".*\\.js\\'" . rjsx-mode))
(add-hook 'css-mode-hook (lambda () (setq css-indent-offset 2)))
(add-hook 'js2-mode-hook (lambda () (setq js2-basic-offset 2)))
(add-hook 'js2-mode-hook (lambda () (setq js2-strict-missing-semi-warning nil)))
(setq-default js2-strict-trailing-comma-warning nil)

(setq highlight-indentation-offset 2)
(dolist (hook '(ruby-mode-hook
                coffee-mode-hook
                haml-mode-hook
                erb-mode-hook
                scala-mode-hook
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
                css-mode-hook
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

;(require 'flycheck)
;(add-to-list 'auto-mode-alist '("\\.js\\'" . js2-jsx-mode))
;(flycheck-add-mode 'javascript-eslint 'js2-jsx-mode)
;(add-hook 'js2-jsx-mode-hook 'flycheck-mode)

(add-hook 'typescript-mode-hook
          (lambda ()
            (tide-setup)
            (flycheck-mode t)
))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   (quote
    (less-css-mode yaml-mode tss tide scss-mode scheme-complete scala-mode2 sass-mode robe rjsx-mode python-mode projectile-rails markdown-preview-eww markdown-mode jsx-mode js2-refactor js-auto-beautify jekyll-modes jade-mode highlight-indentation helm groovy-mode git-commit flymd eslint-fix company coffee-mode auto-indent-mode ac-js2 ac-inf-ruby ac-html-bootstrap ac-html))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
