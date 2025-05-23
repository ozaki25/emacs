;;; inflections-autoloads.el --- automatically extracted autoloads
;;
;;; Code:
(add-to-list 'load-path (or (file-name-directory #$) (car load-path)))

;;;### (autoloads nil "inflections" "inflections.el" (23156 20823
;;;;;;  637823 891000))
;;; Generated autoloads from inflections.el

(autoload 'inflection-singularize-string "inflections" "\
Return the singularized version of STR.

\(fn STR)" nil nil)

(define-obsolete-function-alias 'singularize-string 'inflection-singularize-string)

(autoload 'inflection-pluralize-string "inflections" "\
Return the pluralized version of STR.

\(fn STR)" nil nil)

(define-obsolete-function-alias 'pluralize-string 'inflection-pluralize-string)

;;;***

;; Local Variables:
;; version-control: never
;; no-byte-compile: t
;; no-update-autoloads: t
;; End:
;;; inflections-autoloads.el ends here
