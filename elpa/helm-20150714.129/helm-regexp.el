;;; helm-regexp.el --- In buffer regexp searching and replacement for helm. -*- lexical-binding: t -*-

;; Copyright (C) 2012 ~ 2015 Thierry Volpiatto <thierry.volpiatto@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'cl-lib)
(require 'helm)
(require 'helm-utils)
(require 'helm-plugin)


(defgroup helm-regexp nil
  "Regexp related Applications and libraries for Helm."
  :group 'helm)

(defcustom helm-moccur-always-search-in-current nil
  "Helm multi occur always search in current buffer when non--nil."
  :group 'helm-regexp
  :type 'boolean)

(defcustom helm-moccur-use-ioccur-style-keys t
  "Similar to `helm-grep-use-ioccur-style-keys' but for multi occur."
  :group 'helm-regexp
  :type 'boolean)

(defcustom helm-moccur-auto-update-on-resume nil
  "Allow auto updating helm-(m)occur buffer when outdated.
noask => Always update without asking
nil   => Don't update but signal buffer needs update
never => Never update and do not signal buffer needs update
Any other non--nil value update after confirmation."
  :group 'helm-regexp
  :type '(radio :tag "Allow auto updating helm-(m)occur buffer when outdated."
          (const :tag "Always update without asking" noask)
          (const :tag "Never update and do not signal buffer needs update" never)
          (const :tag "Don't update but signal buffer needs update" nil)
          (const :tag "Update after confirmation" t)))

(defcustom helm-source-multi-occur-actions
  '(("Go to Line" . helm-moccur-goto-line)
    ("Goto line other window" . helm-moccur-goto-line-ow)
    ("Goto line new frame" . helm-moccur-goto-line-of))
  "Actions for helm-occur and helm-moccur."
  :group 'helm-regexp
  :type '(alist :key-type string :value-type function))


(defface helm-moccur-buffer
    '((t (:foreground "DarkTurquoise" :underline t)))
  "Face used to highlight moccur buffer names."
  :group 'helm-regexp)

(defface helm-resume-need-update
    '((t (:background "red")))
  "Face used to flash moccur buffer when it needs update."
  :group 'helm-regexp)


(defvar helm-moccur-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "M-<down>") 'helm-goto-next-file)
    (define-key map (kbd "M-<up>")   'helm-goto-precedent-file)
    (define-key map (kbd "C-w")      'helm-yank-text-at-point)
    (define-key map (kbd "C-c ?")    'helm-moccur-help)
    (define-key map (kbd "C-c o")    'helm-moccur-run-goto-line-ow)
    (define-key map (kbd "C-c C-o")  'helm-moccur-run-goto-line-of)
    (define-key map (kbd "C-x C-s")  'helm-moccur-run-save-buffer)
    (when helm-moccur-use-ioccur-style-keys
      (define-key map (kbd "<right>")  'helm-execute-persistent-action)
      (define-key map (kbd "<left>")   'helm-moccur-run-default-action))
    (delq nil map))
  "Keymap used in Moccur source.")


(defvar helm-build-regexp-history nil)
(defun helm-query-replace-regexp (_candidate)
  "Query replace regexp from `helm-regexp'.
With a prefix arg replace only matches surrounded by word boundaries,
i.e Don't replace inside a word, regexp is surrounded with \\bregexp\\b."
  (let ((regexp helm-input))
    (apply 'query-replace-regexp
           (helm-query-replace-args regexp))))

(defun helm-kill-regexp-as-sexp (_candidate)
  "Kill regexp in a format usable in lisp code."
  (helm-regexp-kill-new
   (prin1-to-string helm-input)))

(defun helm-kill-regexp (_candidate)
  "Kill regexp as it is in `helm-pattern'."
  (helm-regexp-kill-new helm-input))

(defun helm-query-replace-args (regexp)
  "create arguments of `query-replace-regexp' action in `helm-regexp'."
  (let ((region-only (helm-region-active-p)))
    (list
     regexp
     (query-replace-read-to regexp
                            (format "Query replace %sregexp %s"
                                    (if helm-current-prefix-arg "word " "")
                                    (if region-only "in region " ""))
                            t)
     helm-current-prefix-arg
     (when region-only (region-beginning))
     (when region-only (region-end)))))

(defvar helm-source-regexp
  (helm-build-in-buffer-source "Regexp Builder"
    :init (lambda ()
            (helm-init-candidates-in-buffer
                'global (with-temp-buffer
                          (insert-buffer-substring helm-current-buffer)
                          (buffer-string))))
    :get-line #'helm-regexp-get-line
    :persistent-action #'helm-regexp-persistent-action
    :persistent-help "Show this line"
    :multiline t
    :matchplugin nil
    :requires-pattern 2
    :mode-line "Press TAB to select action."
    :action '(("Kill Regexp as sexp" . helm-kill-regexp-as-sexp)
              ("Query Replace Regexp (C-u Not inside word.)"
               . helm-query-replace-regexp)
              ("Kill Regexp" . helm-kill-regexp))))

(defun helm-regexp-get-line (s e)
  (let ((matches (match-data))
        (line    (buffer-substring s e)))
    (propertize
     (cl-loop with ln = (format "%5d: %s" (1- (line-number-at-pos s)) line)
           for i from 0 to (1- (/ (length matches) 2))
           concat (format "\n         %s'%s'" (format "Group %d: " i)
                          (match-string i))
           into ln1
           finally return (concat ln ln1))
     'helm-realvalue s)))

(defun helm-regexp-persistent-action (pt)
  (helm-goto-char pt)
  (helm-highlight-current-line))

(defun helm-regexp-kill-new (input)
  (kill-new input)
  (message "Killed: %s" input))

(defun helm-quote-whitespace (candidate)
  "Quote whitespace, if some, in string CANDIDATE."
  (replace-regexp-in-string " " "\\\\ " candidate))


;;; Occur
;;
;;
(defvar helm-source-occur nil)
(defun helm-occur-init-source ()
  (unless helm-source-occur
    (setq helm-source-occur
          (helm-make-source "Occur" 'helm-source-multi-occur))))


;;; Multi occur
;;
;;

;; Internal
(defvar helm-multi-occur-buffer-list nil)
(defvar helm-multi-occur-buffer-tick nil)
(defun helm-moccur-init ()
  "Create the initial helm multi occur buffer."
  (helm-init-candidates-in-buffer
      'global
    (cl-loop with buffers = (helm-attr 'moccur-buffers)
             for buf in buffers
             for bufstr = (with-current-buffer buf (buffer-string))
             do (add-text-properties
                 0 (length bufstr)
                 `(buffer-name ,(buffer-name (get-buffer buf)))
                 bufstr)
             concat bufstr)))

(defun helm-moccur--next-or-previous-char ()
  (save-excursion
    (or (re-search-forward "^." nil t)
        (re-search-backward "^." nil t))))

(defun helm-moccur-get-line (beg end)
  "Format line for `helm-source-moccur'."
  (prog1
      (format "%s:%d:%s"
              (get-text-property (if (= beg end)
                                     (helm-moccur--next-or-previous-char)
                                     beg)
                                 'buffer-name)
              (save-restriction
                (narrow-to-region (or (previous-single-property-change
                                       (point) 'buffer-name) 1)
                                  (or (next-single-property-change
                                       (if (= beg end)
                                           (helm-moccur--next-or-previous-char)
                                           (point))
                                       'buffer-name)
                                      (point-max)))
                (line-number-at-pos beg))
              ;; When matching empty line, use empty string
              ;; to allow saving and modifying with wgrep.
              (if (= beg end) "" (buffer-substring beg end)))
    ;; When matching empty line, forward char ("\n")
    ;; to not be blocked forever here.
    (when (= beg end) (forward-char 1))))

(cl-defun helm-moccur-action (candidate
                              &optional (method (quote buffer)) mark)
  "Jump to CANDIDATE with METHOD.
arg METHOD can be one of buffer, buffer-other-window, buffer-other-frame."
  (require 'helm-grep)
  (let* ((split (helm-grep-split-line candidate))
         (buf (car split))
         (lineno (string-to-number (nth 1 split)))
         (split-pat (helm-mp-split-pattern helm-input)))
    (cl-case method
      (buffer              (switch-to-buffer buf))
      (buffer-other-window (switch-to-buffer-other-window buf))
      (buffer-other-frame  (switch-to-buffer-other-frame buf)))
    (helm-goto-line lineno)
    ;; Move point to the nearest matching regexp from bol.
    (cl-loop for reg in split-pat
          when (save-excursion
                 (condition-case _err
                     (re-search-forward reg (point-at-eol) t)
                   (invalid-regexp nil)))
          collect (match-beginning 0) into pos-ls
          finally (when pos-ls (goto-char (apply #'min pos-ls))))
    (when mark
      (set-marker (mark-marker) (point))
      (push-mark (point) 'nomsg))))

(defun helm-moccur-persistent-action (candidate)
  (helm-moccur-goto-line candidate)
  (helm-highlight-current-line))

(defun helm-moccur-goto-line (candidate)
  "From multi occur, switch to buffer and go to nth 1 CANDIDATE line."
  (helm-moccur-action
   candidate 'buffer (or current-prefix-arg         ; persistent.
                         helm-current-prefix-arg))) ; exit.

(defun helm-moccur-goto-line-ow (candidate)
  "Go to CANDIDATE line in other window.
Same as `helm-moccur-goto-line' but go in other window."
  (helm-moccur-action
   candidate 'buffer-other-window
   (or current-prefix-arg         ; persistent.
       helm-current-prefix-arg))) ; exit.

(defun helm-moccur-goto-line-of (candidate)
  "Go to CANDIDATE line in new frame.
Same as `helm-moccur-goto-line' but go in new frame."
  (helm-moccur-action
   candidate 'buffer-other-frame
   (or current-prefix-arg         ; persistent.
       helm-current-prefix-arg))) ; exit.

(defun helm-moccur-run-goto-line-ow ()
  "Run goto line other window action from `helm-source-moccur'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-moccur-goto-line-ow)))

(defun helm-moccur-run-goto-line-of ()
  "Run goto line new frame action from `helm-source-moccur'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-moccur-goto-line-of)))

(defun helm-moccur-run-default-action ()
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-moccur-goto-line)))

(defvar helm-source-moccur nil)
(defclass helm-source-multi-occur (helm-source-in-buffer)
  ((init :initform (lambda ()
                     (require 'helm-grep)
                     (helm-moccur-init)))
   (filter-one-by-one :initform 'helm-moccur-filter-one-by-one)
   (get-line :initform helm-moccur-get-line)
   (nohighlight :initform t)
   (migemo :initform t)
   (action :initform 'helm-source-multi-occur-actions)
   (persistent-action :initform 'helm-moccur-persistent-action)
   (persistent-help :initform "Go to line")
   (resume :initform 'helm-moccur-resume-fn)
   (candidate-number-limit :initform 9999)
   (help-message :initform 'helm-moccur-help-message)
   (keymap :initform helm-moccur-map)
   (history :initform 'helm-grep-history)
   (requires-pattern :initform 2)))

(defun helm-moccur-resume-fn ()
  (with-helm-buffer
    (let (new-tick-ls buffer-is-modified)
      (set (make-local-variable 'helm-multi-occur-buffer-list)
           (cl-loop for b in helm-multi-occur-buffer-list
                    when (buffer-live-p (get-buffer b))
                    collect b))
      (setq buffer-is-modified (/= (length helm-multi-occur-buffer-list)
                                   (length (helm-attr 'moccur-buffers))))
      (helm-attrset 'moccur-buffers helm-multi-occur-buffer-list)
      (setq new-tick-ls (cl-loop for b in helm-multi-occur-buffer-list
                                 collect (buffer-chars-modified-tick (get-buffer b))))
      (when buffer-is-modified
        (setq helm-multi-occur-buffer-tick new-tick-ls))
      (cl-assert (> (length helm-multi-occur-buffer-list) 0) nil
                 "helm-resume error: helm-(m)occur buffer list is empty")
      (unless (eq helm-moccur-auto-update-on-resume 'never)
        (when (or buffer-is-modified
                  (cl-loop for b in helm-multi-occur-buffer-list
                           for new-tick = (buffer-chars-modified-tick (get-buffer b))
                           for tick in helm-multi-occur-buffer-tick
                           thereis (/= tick new-tick)))
          (helm-aif helm-moccur-auto-update-on-resume
              (when (or (eq it 'noask)
                        (y-or-n-p "Helm (m)occur Buffer outdated, update? "))
                (run-with-idle-timer 0.1 nil (lambda ()
                                               (with-helm-buffer
                                                 (helm-force-update)
                                                 (message "Helm (m)occur Buffer have been udated")
                                                 (sit-for 1) (message nil))))
                (unless buffer-is-modified (setq helm-multi-occur-buffer-tick new-tick-ls)))
            (run-with-idle-timer 0.1 nil (lambda ()
                                           (with-helm-buffer
                                             (let ((ov (make-overlay (save-excursion
                                                                       (goto-char (point-min))
                                                                       (forward-line 1)
                                                                       (point))
                                                                     (point-max))))
                                               (overlay-put ov 'face 'helm-resume-need-update)
                                               (sit-for 0.3) (delete-overlay ov)
                                               (message "[Helm occur Buffer outdated (C-c C-u to update)]")))))
            (unless buffer-is-modified
              (with-helm-after-update-hook
                (setq helm-multi-occur-buffer-tick new-tick-ls)
                (message "Helm (m)occur Buffer have been udated")))))))))

(defun helm-moccur-filter-one-by-one (candidate)
  "`filter-one-by-one' function for `helm-source-moccur'."
  (require 'helm-grep)
  (let* ((split  (helm-grep-split-line candidate))
         (buf    (car split))
         (lineno (nth 1 split))
         (str    (nth 2 split)))
    (cons (concat (propertize
                   buf
                   'face 'helm-moccur-buffer
                   'help-echo (buffer-file-name
                               (get-buffer buf))
                   'buffer-name buf)
                  ":"
                  (propertize lineno 'face 'helm-grep-lineno)
                  ":"
                  (helm-grep-highlight-match str t))
          candidate)))

(defun helm-multi-occur-1 (buffers &optional input)
  "Main function to call `helm-source-moccur' with BUFFERS list."
  (let ((bufs (if helm-moccur-always-search-in-current
                  (cons
                   ;; will become helm-current-buffer later.
                   (buffer-name (current-buffer))
                   (remove helm-current-buffer buffers))
                  buffers)))
    (unless helm-source-moccur
      (setq helm-source-moccur
            (helm-make-source "Moccur" 'helm-source-multi-occur)))
    (helm-attrset 'moccur-buffers bufs helm-source-moccur)
    (helm-set-local-variable 'helm-multi-occur-buffer-list bufs)
    (helm-set-local-variable
     'helm-multi-occur-buffer-tick
     (cl-loop for b in bufs
              collect (buffer-chars-modified-tick (get-buffer b)))))
  (helm :sources 'helm-source-moccur
        :buffer "*helm multi occur*"
        :history 'helm-grep-history
        :keymap helm-moccur-map
        :input input
        :truncate-lines t))

(defun helm-moccur-run-save-buffer ()
  "Run moccur save results action from `helm-moccur'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-moccur-save-results)))


;;; helm-moccur-mode
;;
;;
(defvar helm-moccur-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")      'helm-moccur-mode-goto-line)
    (define-key map (kbd "C-o")      'helm-moccur-mode-goto-line-ow)
    (define-key map (kbd "<C-down>") 'helm-moccur-mode-goto-line-ow-forward)
    (define-key map (kbd "<C-up>")   'helm-moccur-mode-goto-line-ow-backward)
    (define-key map (kbd "<M-down>") 'helm-gm-next-file)
    (define-key map (kbd "<M-up>")   'helm-gm-precedent-file)
    (define-key map (kbd "M-n")      'helm-moccur-mode-goto-line-ow-forward)
    (define-key map (kbd "M-p")      'helm-moccur-mode-goto-line-ow-backward)
    (define-key map (kbd "M-N")      'helm-gm-next-file)
    (define-key map (kbd "M-P")      'helm-gm-precedent-file)
    map))

(defun helm-moccur-mode-goto-line ()
  (interactive)
  (helm-aif (get-text-property (point) 'helm-realvalue)
    (helm-moccur-goto-line it)))

(defun helm-moccur-mode-goto-line-ow ()
  (interactive)
  (helm-aif (get-text-property (point) 'helm-realvalue)
    (helm-moccur-goto-line-ow it)))

(defun helm-moccur-mode-goto-line-ow-forward-1 (arg)
  (condition-case nil
      (progn
        (save-selected-window
          (helm-moccur-mode-goto-line-ow)
          (recenter))
        (forward-line arg))
    (error nil)))

(defun helm-moccur-mode-goto-line-ow-forward ()
  (interactive)
  (helm-moccur-mode-goto-line-ow-forward-1 1))

(defun helm-moccur-mode-goto-line-ow-backward ()
  (interactive)
  (helm-moccur-mode-goto-line-ow-forward-1 -1))

(defun helm-moccur-save-results (_candidate)
  "Save helm moccur results in a `helm-moccur-mode' buffer."
  (let ((buf "*hmoccur*")
        new-buf)
    (when (get-buffer buf)
      (setq new-buf (helm-read-string "OccurBufferName: " buf))
      (cl-loop for b in (helm-buffer-list)
            when (and (string= new-buf b)
                      (not (y-or-n-p
                            (format "Buffer `%s' already exists overwrite? "
                                    new-buf))))
            do (setq new-buf (helm-read-string "OccurBufferName: " "*hmoccur ")))
      (setq buf new-buf))
    (with-current-buffer (get-buffer-create buf)
      (setq buffer-read-only t)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "-*- mode: helm-moccur -*-\n\n"
                (format "Moccur Results for `%s':\n\n" helm-input))
        (save-excursion
          (insert (with-current-buffer helm-buffer
                    (goto-char (point-min)) (forward-line 1)
                    (buffer-substring (point) (point-max))))))
      (helm-moccur-mode) (pop-to-buffer buf))
    (message "Helm Moccur Results saved in `%s' buffer" buf)))

;;;###autoload
(define-derived-mode helm-moccur-mode
    special-mode "helm-moccur"
    "Major mode to provide actions in helm moccur saved buffer.

Special commands:
\\{helm-moccur-mode-map}"
    (set (make-local-variable 'helm-multi-occur-buffer-list)
         (with-helm-buffer helm-multi-occur-buffer-list))
    (set (make-local-variable 'revert-buffer-function)
         #'helm-moccur-mode--revert-buffer-function))

(defun helm-moccur-mode--revert-buffer-function (&optional _ignore-auto _noconfirm)
  (goto-char (point-min))
  (let (pattern)
    (when (re-search-forward "^Moccur Results for `\\(.*\\)'" nil t)
      (setq pattern (match-string 1))
      (forward-line 0)
      (when (re-search-forward "^$" nil t)
        (forward-line 1))
      (let ((inhibit-read-only t)
            (buffer (current-buffer))
            (buflst helm-multi-occur-buffer-list))
        (delete-region (point) (point-max))
        (message "Reverting buffer...")
        (save-excursion
          (with-temp-buffer
            (insert
             "\n"
             (cl-loop for buf in buflst
                      for bufstr = (or (and (buffer-live-p (get-buffer buf))
                                            (with-current-buffer buf
                                              (buffer-string)))
                                       "")
                      unless (string= bufstr "")
                      do (add-text-properties
                          0 (length bufstr)
                          `(buffer-name ,(buffer-name (get-buffer buf)))
                          bufstr)
                      concat bufstr)
             "\n")
            (goto-char (point-min))
            (cl-loop while (re-search-forward pattern nil t)
                     for line = (helm-moccur-get-line (point-at-bol) (point-at-eol))
                     when line
                     do (with-current-buffer buffer
                          (insert
                           (propertize
                            (car (helm-moccur-filter-one-by-one line))
                            'helm-realvalue line)
                           "\n")))))
        (message "Reverting buffer done")))))


;;; Predefined commands
;;
;;

;;;###autoload
(defun helm-regexp ()
  "Preconfigured helm to build regexps.
`query-replace-regexp' can be run from there against found regexp."
  (interactive)
  (save-restriction
    (when (and (helm-region-active-p)
               ;; Don't narrow to region if buffer is already narrowed.
               (not (helm-current-buffer-narrowed-p (current-buffer))))
      (narrow-to-region (region-beginning) (region-end)))
    (helm :sources helm-source-regexp
          :buffer "*helm regexp*"
          :prompt "Regexp: "
          :history 'helm-build-regexp-history)))

;;;###autoload
(defun helm-occur ()
  "Preconfigured helm for Occur."
  (interactive)
  (helm-occur-init-source)
  (let ((bufs (list (buffer-name (current-buffer)))))
    (helm-attrset 'moccur-buffers bufs helm-source-occur)
    (helm-set-local-variable 'helm-multi-occur-buffer-list bufs)
    (helm-set-local-variable
     'helm-multi-occur-buffer-tick
     (cl-loop for b in bufs
              collect (buffer-chars-modified-tick (get-buffer b)))))
  (helm :sources 'helm-source-occur
        :buffer "*helm occur*"
        :history 'helm-grep-history
        :preselect (and (memq 'helm-source-occur helm-sources-using-default-as-input)
                        (format "%s:%d:" (regexp-quote (buffer-name))
                                (line-number-at-pos (point))))
        :truncate-lines t))

;;;###autoload
(defun helm-occur-from-isearch ()
  "Invoke `helm-occur' from isearch."
  (interactive)
  (let ((input (if isearch-regexp
                   isearch-string
                 (regexp-quote isearch-string)))
        (bufs (list (buffer-name (current-buffer)))))
    (isearch-exit)
    (helm-occur-init-source)
    (helm-attrset 'moccur-buffers bufs helm-source-occur)
    (helm-set-local-variable 'helm-multi-occur-buffer-list bufs)
    (helm-set-local-variable
     'helm-multi-occur-buffer-tick
     (cl-loop for b in bufs
              collect (buffer-chars-modified-tick (get-buffer b))))
    (helm :sources 'helm-source-occur
          :buffer "*helm occur*"
          :history 'helm-grep-history
          :input input
          :truncate-lines t)))

;;;###autoload
(defun helm-multi-occur (buffers)
  "Preconfigured helm for multi occur.

  BUFFERS is a list of buffers to search through.
With a prefix arg, reverse the behavior of
`helm-moccur-always-search-in-current'.
The prefix arg can be set before calling `helm-multi-occur'
or during the buffer selection."
  (interactive (list (helm-comp-read
                      "Buffers: " (helm-buffer-list)
                      :marked-candidates t)))
  (let ((helm-moccur-always-search-in-current
         (if (or current-prefix-arg
                 helm-current-prefix-arg)
             (not helm-moccur-always-search-in-current)
           helm-moccur-always-search-in-current)))
    (helm-multi-occur-1 buffers)))

;;;###autoload
(defun helm-multi-occur-from-isearch (&optional _arg)
  "Invoke `helm-multi-occur' from isearch.

With a prefix arg, reverse the behavior of
`helm-moccur-always-search-in-current'.
The prefix arg can be set before calling
`helm-multi-occur-from-isearch' or during the buffer selection."
  (interactive "p")
  (let (buf-list
        helm-moccur-always-search-in-current
        (input (if isearch-regexp
                   isearch-string
                 (regexp-quote isearch-string))))
    (isearch-exit)
    (setq buf-list (helm-comp-read "Buffers: "
                                   (helm-buffer-list)
                                   :name "Occur in buffer(s)"
                                   :marked-candidates t))
    (setq helm-moccur-always-search-in-current
          (if (or current-prefix-arg
                  helm-current-prefix-arg)
              (not helm-moccur-always-search-in-current)
            helm-moccur-always-search-in-current))
    (helm-multi-occur-1 buf-list input)))


(provide 'helm-regexp)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-regexp.el ends here
