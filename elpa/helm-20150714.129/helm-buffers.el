;;; helm-buffers.el --- helm support for buffers. -*- lexical-binding: t -*-

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
(require 'helm-types)
(require 'helm-utils)
(require 'helm-elscreen)
(require 'helm-grep)
(require 'helm-plugin)
(require 'helm-regexp)
(require 'helm-help)

(declare-function ido-make-buffer-list "ido" (default))
(declare-function ido-add-virtual-buffers-to-list "ido")
(declare-function helm-comp-read "helm-mode")


(defgroup helm-buffers nil
  "Buffers related Applications and libraries for Helm."
  :group 'helm)

(defcustom helm-boring-buffer-regexp-list
  '("\\` " "\\*helm" "\\*helm-mode" "\\*Echo Area" "\\*Minibuf")
  "The regexp list that match boring buffers.
Buffer candidates matching these regular expression will be
filtered from the list of candidates if the
`helm-skip-boring-buffers' candidate transformer is used."
  :type  '(repeat (choice regexp))
  :group 'helm-buffers)

(defcustom helm-buffers-favorite-modes '(lisp-interaction-mode
                                         emacs-lisp-mode
                                         text-mode
                                         org-mode)
  "List of preferred mode to open new buffers with."
  :type '(repeat (choice function))
  :group 'helm-buffers)

(defcustom helm-buffer-max-length 20
  "Max length of buffer names before truncate.
When disabled (nil) use the longest buffer-name length found."
  :group 'helm-buffers
  :type  '(choice (const :tag "Disabled" nil)
           (integer :tag "Length before truncate")))

(defcustom helm-buffer-details-flag t
  "Always show details in buffer list when non--nil."
  :group 'helm-buffers
  :type 'boolean)

(defcustom helm-buffers-fuzzy-matching nil
  "Fuzzy matching buffer names when non--nil.
Only buffer names are fuzzy matched when this is enabled,
`major-mode' matching is not affected by this."
  :group 'helm-buffers
  :type 'boolean)

(defcustom helm-buffer-skip-remote-checking nil
  "Ignore checking for `file-exists-p' on remote files."
  :group 'helm-buffers
  :type 'boolean)

(defcustom helm-buffers-truncate-lines t
  "Truncate lines in `helm-buffers-list' when non--nil."
  :group 'helm-buffers
  :type 'boolean)

(defcustom helm-mini-default-sources '(helm-source-buffers-list
                                       helm-source-recentf
                                       helm-source-buffer-not-found)
  "Default sources list used in `helm-mini'."
  :group 'helm-misc
  :type '(repeat (choice symbol)))


;;; Faces
;;
;;
(defgroup helm-buffers-faces nil
  "Customize the appearance of helm-buffers."
  :prefix "helm-"
  :group 'helm-buffers
  :group 'helm-faces)

(defface helm-buffer-saved-out
    '((t (:foreground "red" :background "black")))
  "Face used for buffer files modified outside of emacs."
  :group 'helm-buffers-faces)

(defface helm-buffer-not-saved
    '((t (:foreground "Indianred2")))
  "Face used for buffer files not already saved on disk."
  :group 'helm-buffers-faces)

(defface helm-buffer-size
    '((((background dark)) :foreground "RosyBrown")
      (((background light)) :foreground "SlateGray"))
  "Face used for buffer size."
  :group 'helm-buffers-faces)

(defface helm-buffer-process
    '((t (:foreground "Sienna3")))
  "Face used for process status in buffer."
  :group 'helm-buffers-faces)

(defface helm-buffer-directory
    '((t (:foreground "DarkRed" :background "LightGray")))
  "Face used for directories in `helm-buffers-list'."
  :group 'helm-buffers-faces)

(defface helm-buffer-file
    '((t :inherit font-lock-builtin-face))
  "Face for buffer file names in `helm-buffers-list'."
  :group 'helm-buffers-faces)


;;; Buffers keymap
;;
(defvar helm-buffer-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c ?")     'helm-buffer-help)
    ;; No need to have separate command for grep and zgrep
    ;; as we don't use recursivity for buffers.
    ;; So use zgrep for both as it is capable to handle non--compressed files.
    (define-key map (kbd "M-g s")     'helm-buffer-run-zgrep)
    (define-key map (kbd "C-s")       'helm-buffers-run-multi-occur)
    (define-key map (kbd "C-c o")     'helm-buffer-switch-other-window)
    (define-key map (kbd "C-c C-o")   'helm-buffer-switch-other-frame)
    (define-key map (kbd "C-c =")     'helm-buffer-run-ediff)
    (define-key map (kbd "M-=")       'helm-buffer-run-ediff-merge)
    (define-key map (kbd "C-=")       'helm-buffer-diff-persistent)
    (define-key map (kbd "M-U")       'helm-buffer-revert-persistent)
    (define-key map (kbd "C-c d")     'helm-buffer-run-kill-persistent)
    (define-key map (kbd "M-D")       'helm-buffer-run-kill-buffers)
    (define-key map (kbd "C-x C-s")   'helm-buffer-save-persistent)
    (define-key map (kbd "C-M-%")     'helm-buffer-run-query-replace-regexp)
    (define-key map (kbd "M-%")       'helm-buffer-run-query-replace)
    (define-key map (kbd "M-m")       'helm-toggle-all-marks)
    (define-key map (kbd "M-a")       'helm-mark-all)
    (define-key map (kbd "C-]")       'helm-toggle-buffers-details)
    (define-key map (kbd "C-c a")     'helm-buffers-toggle-show-hidden-buffers)
    (define-key map (kbd "<C-M-SPC>") 'helm-buffers-mark-similar-buffers)
    map)
  "Keymap for buffer sources in helm.")

(defvar helm-buffers-ido-virtual-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c ?")   'helm-buffers-ido-virtual-help)
    (define-key map (kbd "C-c o")   'helm-ff-run-switch-other-window)
    (define-key map (kbd "C-c C-o") 'helm-ff-run-switch-other-frame)
    (define-key map (kbd "M-g s")   'helm-ff-run-grep)
    (define-key map (kbd "M-g z")   'helm-ff-run-zgrep)
    (define-key map (kbd "M-D")     'helm-ff-run-delete-file)
    (define-key map (kbd "C-c C-x") 'helm-ff-run-open-file-externally)
    map))


(defvar helm-buffers-list-cache nil)
(defvar helm-buffer-max-len-mode nil)

(defun helm-buffers-list--init ()
  ;; Issue #51 Create the list before `helm-buffer' creation.
  (setq helm-buffers-list-cache (funcall (helm-attr 'buffer-list)))
  (let ((result (cl-loop for b in helm-buffers-list-cache
                         maximize (length b) into len-buf
                         maximize (length (with-current-buffer b
                                            (symbol-name major-mode)))
                         into len-mode
                         finally return (cons len-buf len-mode))))
    (unless (default-value 'helm-buffer-max-length)
      (helm-set-local-variable 'helm-buffer-max-length (car result)))
    (unless (default-value 'helm-buffer-max-len-mode)
      (helm-set-local-variable 'helm-buffer-max-len-mode (cdr result)))))

(defclass helm-source-buffers (helm-source-sync helm-type-buffer)
  ((buffer-list
    :initarg :buffer-list
    :initform #'helm-buffer-list
    :custom function
    :documentation
    "  A function with no arguments to create buffer list.")
   (init :initform 'helm-buffers-list--init)
   (candidates :initform helm-buffers-list-cache)
   (matchplugin :initform nil)
   (match :initform 'helm-buffers-match-function)
   (persistent-action :initform 'helm-buffers-list-persistent-action)
   (resume :initform (lambda ()
                       (run-with-idle-timer
                        0.1 nil (lambda ()
                                  (with-helm-buffer
                                    (helm-force-update))))))
   (keymap :initform helm-buffer-map)
   (volatile :initform t)
   (help-message :initform 'helm-buffer-help-message)
   (persistent-help
    :initform
    "Show this buffer / C-u \\[helm-execute-persistent-action]: Kill this buffer")))

(defvar helm-source-buffers-list nil)

(defvar helm-source-buffer-not-found
  (helm-build-dummy-source
   "Create buffer"
   :action (helm-make-actions
            "Create buffer (C-u choose mode)"
            (lambda (candidate)
             (let ((mjm (or (and helm-current-prefix-arg
                                 (intern-soft (helm-comp-read
                                               "Major-mode: "
                                               helm-buffers-favorite-modes)))
                            (cl-loop for (r . m) in auto-mode-alist
                                     when (string-match r candidate)
                                     return m)))
                   (buffer (get-buffer-create candidate)))
               (if mjm
                   (with-current-buffer buffer (funcall mjm))
                   (set-buffer-major-mode buffer))
               (switch-to-buffer buffer))))))

(defvar ido-temp-list)
(defvar ido-ignored-list)
(defvar ido-process-ignore-lists)
(defvar ido-use-virtual-buffers)
(defvar ido-virtual-buffers)

(defvar helm-source-ido-virtual-buffers
  (helm-build-sync-source "Ido virtual buffers"
    :candidates (lambda ()
                  (let (ido-temp-list
                        ido-ignored-list
                        (ido-process-ignore-lists t))
                    (when ido-use-virtual-buffers
                      (ido-add-virtual-buffers-to-list)
                      ido-virtual-buffers)))
    :fuzzy-match helm-buffers-fuzzy-matching
    :keymap helm-buffers-ido-virtual-map
    :help-message 'helm-buffers-ido-virtual-help-message
    :action '(("Find file" . helm-find-many-files)
              ("Find file other window" . find-file-other-window)
              ("Find file other frame" . find-file-other-frame)
              ("Find file as root" . helm-find-file-as-root)
              ("Grep File(s) `C-u recurse'" . helm-find-files-grep)
              ("Zgrep File(s) `C-u Recurse'" . helm-ff-zgrep)
              ("View file" . view-file)
              ("Delete file(s)" . helm-delete-marked-files)
              ("Open file externally (C-u to choose)"
               . helm-open-file-externally))))


(defvar ido-use-virtual-buffers)
(defun helm-buffer-list ()
  "Return the current list of buffers.
Currently visible buffers are put at the end of the list.
See `ido-make-buffer-list' for more infos."
  (require 'ido)
  (let ((ido-process-ignore-lists t)
        ido-ignored-list
        ido-use-virtual-buffers)
    (ido-make-buffer-list nil)))

(defun helm-buffer-size (buffer)
  "Return size of BUFFER."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (helm-file-human-size
       (- (position-bytes (point-max))
          (position-bytes (point-min)))))))

(defun helm-buffer--show-details (buf-name prefix help-echo
                                  size mode dir face1 face2
                                  proc details type)
  (append
   (list
    (concat prefix
            (propertize buf-name 'face face1
                        'help-echo help-echo
                        'type type)))
   (and details
        (list size mode
              (propertize
               (if proc
                   (format "(%s %s in `%s')"
                           (process-name proc)
                           (process-status proc) dir)
                 (format "(in `%s')" dir))
               'face face2)))))

(defun helm-buffer--details (buffer &optional details)
  (let* ((mode (with-current-buffer buffer (format-mode-line mode-name)))
         (buf (get-buffer buffer))
         (size (propertize (helm-buffer-size buf)
                           'face 'helm-buffer-size))
         (proc (get-buffer-process buf))
         (dir (with-current-buffer buffer (abbreviate-file-name default-directory)))
         (file-name (helm-aif (buffer-file-name buf) (abbreviate-file-name it)))
         (name (buffer-name buf))
         (name-prefix (when (file-remote-p dir)
                        (propertize "@ " 'face 'helm-ff-prefix))))
    ;; No fancy things on remote buffers.
    (if (and name-prefix helm-buffer-skip-remote-checking)
        (helm-buffer--show-details
         name name-prefix file-name size mode dir
         'helm-buffer-file 'helm-buffer-process nil details 'filebuf)
      (cond
        ( ;; A dired buffer.
         (rassoc buf dired-buffers)
         (helm-buffer--show-details
          name name-prefix dir size mode dir
          'helm-buffer-directory 'helm-buffer-process nil details 'dired))
        ;; A buffer file modified somewhere outside of emacs.=>red
        ((and file-name
              (file-exists-p file-name)
              (not (verify-visited-file-modtime buf)))
         (helm-buffer--show-details
          name name-prefix file-name size mode dir
          'helm-buffer-saved-out 'helm-buffer-process nil details 'modout))
        ;; A new buffer file not already saved on disk (or a deleted file) .=>indianred2
        ((and file-name (not (file-exists-p file-name)))
         (helm-buffer--show-details
          name name-prefix file-name size mode dir
          'helm-buffer-not-saved 'helm-buffer-process nil details 'notsaved))
        ;; A buffer file modified and not saved on disk.=>orange
        ((and file-name (buffer-modified-p buf))
         (helm-buffer--show-details
          name name-prefix file-name size mode dir
          'helm-ff-symlink 'helm-buffer-process nil details 'mod))
        ;; A buffer file not modified and saved on disk.=>green
        (file-name
         (helm-buffer--show-details
          name name-prefix file-name size mode dir
          'helm-buffer-file 'helm-buffer-process nil details 'filebuf))
        ;; Any non--file buffer.=>grey italic
        (t
         (helm-buffer--show-details
          name (and proc name-prefix) dir size mode dir
          'italic 'helm-buffer-process proc details 'nofile))))))

(defun helm-highlight-buffers (buffers _source)
  "Transformer function to highlight BUFFERS list.
Should be called after others transformers i.e (boring buffers)."
  (cl-loop for i in buffers
        for (name size mode meta) = (if helm-buffer-details-flag
                                        (helm-buffer--details i 'details)
                                      (helm-buffer--details i))
        for truncbuf = (if (> (string-width name) helm-buffer-max-length)
                           (helm-substring-by-width
                            name helm-buffer-max-length)
                         (concat name (make-string
                                       (- (+ helm-buffer-max-length 3)
                                          (string-width name)) ? )))
        for len = (length mode)
        when (> len helm-buffer-max-len-mode)
        do (setq helm-buffer-max-len-mode len)
        for fmode = (concat (make-string
                             (- (max helm-buffer-max-len-mode len) len) ? )
                            mode)
        ;; The max length of a number should be 1023.9X where X is the
        ;; units, this is 7 characters.
        for formatted-size = (and size (format "%7s" size))
        collect (cons (if helm-buffer-details-flag
                          (concat truncbuf "\t" formatted-size
                                  "  " fmode "  " meta)
                        name)
                      (get-buffer i))))

(defun helm-buffer--get-preselection (buffer)
  (let ((bufname (buffer-name buffer)))
    (concat "^"
            (if (and (null helm-buffer-details-flag)
                     (numberp helm-buffer-max-length)
                     (> (string-width bufname)
                        helm-buffer-max-length))
                (regexp-quote
                 (helm-substring-by-width
                  bufname helm-buffer-max-length))
                (concat (regexp-quote bufname)
                        (if helm-buffer-details-flag
                            "$" "[[:blank:]]+"))))))

(defun helm-toggle-buffers-details ()
  (interactive)
  (let ((preselect (helm-buffer--get-preselection
                    (helm-get-selection))))
    (when helm-alive-p
      (setq helm-buffer-details-flag (not helm-buffer-details-flag))
      (helm-force-update preselect))))

(defun helm-buffers-sort-transformer (candidates _source)
  (if (string= helm-pattern "")
      candidates
    (sort candidates
          #'(lambda (s1 s2)
              (< (string-width s1) (string-width s2))))))

(defun helm-buffers-mark-similar-buffers-1 ()
  (with-helm-window
    (let ((type (get-text-property
                 0 'type (helm-get-selection nil 'withprop))))
      (save-excursion
        (goto-char (helm-get-previous-header-pos))
        (helm-next-line)
        (let* ((next-head (helm-get-next-header-pos))
               (end       (and next-head
                               (save-excursion
                                 (goto-char next-head)
                                 (forward-line -1)
                                 (point))))
               (maxpoint  (or end (point-max))))
          (while (< (point) maxpoint)
            (helm-mark-current-line)
            (let ((cand (helm-get-selection nil 'withprop)))
              (when (and (not (helm-this-visible-mark))
                         (eq (get-text-property 0 'type cand) type))
                (helm-make-visible-mark)))
            (forward-line 1) (end-of-line))))
      (helm-mark-current-line)
      (message "%s candidates marked" (length helm-marked-candidates)))))

(defun helm-buffers-mark-similar-buffers ()
    "Mark All buffers that have same property `type' than current.
i.e same color."
  (interactive)
  (let ((marked (helm-marked-candidates)))
    (if (and (>= (length marked) 1)
             (with-helm-window helm-visible-mark-overlays))
        (helm-unmark-all)
      (helm-buffers-mark-similar-buffers-1))))


;;; match functions
;;
(defun helm-buffer--match-mjm (pattern mjm)
  (when (string-match "\\`\\*" pattern)
    (cl-loop with patterns = (split-string (substring pattern 1) ",")
             for pat in patterns
             if (string-match "\\`!" pat)
             collect (string-match (substring pat 1) mjm) into neg
             else collect (string-match pat mjm) into pos
             finally return
             (let ((neg-test (cl-loop for i in neg thereis (numberp i)))
                   (pos-test (cl-loop for i in pos thereis (numberp i))))
               (or
                (and neg (not pos) (not neg-test))
                (and pos pos-test)
                (and neg neg-test (not neg-test)))))))

(defun helm-buffer--match-pattern (pattern candidate)
  (let ((fun (if (and helm-buffers-fuzzy-matching
                      (not (string-match "\\`\\^" pattern)))
                 #'helm--mapconcat-pattern
                 #'identity)))
    (if (string-match "\\`!" pattern)
        (not (string-match (funcall fun (substring pattern 1))
                           candidate))
        (string-match (funcall fun pattern) candidate))))

(defun helm-buffers--match-from-mjm (candidate)
  (let* ((cand (replace-regexp-in-string "^\\s-\\{1\\}" "" candidate))
         (buf  (get-buffer cand))
         (regexp (cl-loop with pattern = helm-pattern
                          for p in (split-string pattern)
                          when (string-match "\\`\\*" p)
                          return p)))
    (if regexp
        (when buf
          (with-current-buffer buf
            (let ((mjm (format-mode-line mode-name)))
              (helm-buffer--match-mjm regexp mjm))))
        t)))

(defun helm-buffers--match-from-pat (candidate)
  (let ((regexp-list (cl-loop with pattern = helm-pattern
                              for p in (split-string pattern)
                              unless (string-match
                                      "\\`\\(\\*\\)\\|\\(/\\)\\|\\(@\\)" p)
                              collect p)))
    (if regexp-list
        (cl-loop for re in regexp-list
                 always (helm-buffer--match-pattern re candidate))
        t)))

(defun helm-buffers--match-from-inside (candidate)
  (let* ((cand (replace-regexp-in-string "^\\s-\\{1\\}" "" candidate))
         (buf  (get-buffer cand))
         (regexp (cl-loop with pattern = helm-pattern
                          for p in (split-string pattern)
                          when (string-match "\\`@\\(.*\\)" p)
                          return (match-string 1 p))))
    (if regexp
        (with-current-buffer buf
          (save-excursion
            (goto-char (point-min))
            (re-search-forward regexp nil t)))
        t)))

(defun helm-buffers--match-from-directory (candidate)
  (let* ((cand (replace-regexp-in-string "^\\s-\\{1\\}" "" candidate))
         (buf  (get-buffer cand))
         (buf-fname (buffer-file-name buf))
         (regexps (cl-loop with pattern = helm-pattern
                          for p in (split-string pattern)
                          when (string-match "\\`/" p)
                          collect p)))
    (if regexps
        (cl-loop for re in regexps
                 thereis 
                 (and buf-fname
                      (string-match
                       (substring re 1) (helm-basedir buf-fname))))
        t)))

(defun helm-buffers-match-function (candidate)
  "Default function to match buffers."
  (and (helm-buffers--match-from-pat candidate)
       (helm-buffers--match-from-mjm candidate)
       (helm-buffers--match-from-inside candidate)
       (helm-buffers--match-from-directory candidate)))


(defun helm-buffer-query-replace-1 (&optional regexp-flag buffers)
  "Query replace in marked buffers.
If REGEXP-FLAG is given use `query-replace-regexp'."
  (let ((fn     (if regexp-flag 'query-replace-regexp 'query-replace))
        (prompt (if regexp-flag "Query replace regexp" "Query replace"))
        (bufs   (or buffers (helm-marked-candidates)))
        (helm--reading-passwd-or-string t))
    (cl-loop with replace = (query-replace-read-from prompt regexp-flag)
          with tostring = (unless (consp replace)
                            (query-replace-read-to
                             replace prompt regexp-flag))
          for buf in bufs
          do
          (save-window-excursion
            (switch-to-buffer buf)
            (save-excursion
              (let ((case-fold-search t))
                (goto-char (point-min))
                (if (consp replace)
                    (apply fn (list (car replace) (cdr replace)))
                  (apply fn (list replace tostring)))))))))

(defun helm-buffer-query-replace-regexp (_candidate)
  (helm-buffer-query-replace-1 'regexp))

(defun helm-buffer-query-replace (_candidate)
  (helm-buffer-query-replace-1))

(defun helm-buffer-toggle-diff (candidate)
  "Toggle diff buffer CANDIDATE with it's file."
  (let (helm-persistent-action-use-special-display)
    (helm-aif (get-buffer-window "*Diff*")
        (progn (kill-buffer "*Diff*")
               (set-window-buffer it helm-current-buffer))
      (diff-buffer-with-file (get-buffer candidate)))))

(defun helm-buffer-diff-persistent ()
  "Toggle diff buffer without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'diff-action 'helm-buffer-toggle-diff)
    (helm-execute-persistent-action 'diff-action)))

(defun helm-revert-buffer (candidate)
  (with-current-buffer candidate
    (helm-aif (buffer-file-name)
        (and (file-exists-p it) (revert-buffer t t)))))

(defun helm-revert-marked-buffers (_ignore)
  (mapc 'helm-revert-buffer (helm-marked-candidates)))

(defun helm-buffer-revert-and-update (_candidate)
  (let ((marked (helm-marked-candidates))
        (preselect (helm-buffers--quote-truncated-buffer
                    (helm-get-selection))))
    (cl-loop for buf in marked do (helm-revert-buffer buf))
    (when (> (length marked) 1) (helm-unmark-all))
    (helm-force-update preselect)))

(defun helm-buffer-revert-persistent ()
  "Revert buffer without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'revert-action '(helm-buffer-revert-and-update . never-split))
    (helm-execute-persistent-action 'revert-action)))

(defun helm-buffer-save-and-update (_candidate)
  (let ((marked (helm-marked-candidates))
        (preselect (helm-get-selection nil t))
        (enable-recursive-minibuffers t))
    (cl-loop for buf in marked do
          (with-current-buffer (get-buffer buf)
            (when (buffer-file-name) (save-buffer))))
    (when (> (length marked) 1) (helm-unmark-all))
    (helm-force-update (regexp-quote preselect))))

(defun helm-buffer-save-persistent ()
  "Save buffer without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'save-action '(helm-buffer-save-and-update . never-split))
    (helm-execute-persistent-action 'save-action)))

(defun helm-buffer-run-kill-persistent ()
  "Kill buffer without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'kill-action '(helm-buffers-persistent-kill . never-split))
    (helm-execute-persistent-action 'kill-action)))

(defun helm-kill-marked-buffers (_ignore)
  (mapc 'kill-buffer (helm-marked-candidates))
  (with-helm-buffer
    (setq helm-marked-candidates nil
          helm-visible-mark-overlays nil)))

(defun helm-buffer-run-kill-buffers ()
  "Run kill buffer action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-kill-marked-buffers)))

(defun helm-buffer-run-grep ()
  "Run Grep action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-grep-buffers)))

(defun helm-buffer-run-zgrep ()
  "Run Grep action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-zgrep-buffers)))

(defun helm-buffer-run-query-replace-regexp ()
  "Run Query replace regexp action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-buffer-query-replace-regexp)))

(defun helm-buffer-run-query-replace ()
  "Run Query replace action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-buffer-query-replace)))

(defun helm-buffer-switch-other-window ()
  "Run switch to other window action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-switch-to-buffers-other-window)))

(defun helm-buffer-switch-other-frame ()
  "Run switch to other frame action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'switch-to-buffer-other-frame)))

(defun helm-buffer-switch-to-elscreen ()
  "Run switch to elscreen  action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-buffer-on-elscreen)))

(defun helm-buffer-run-ediff ()
  "Run ediff action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ediff-marked-buffers)))

(defun helm-buffer-run-ediff-merge ()
  "Run ediff action from `helm-source-buffers-list'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ediff-marked-buffers-merge)))

(defun helm-buffers-persistent-kill-1 (buffer)
  "Persistent action to kill buffer."
  (if (eql (get-buffer buffer) (get-buffer helm-current-buffer))
      (progn
        (message "Can't kill `helm-current-buffer' without quitting session")
        (sit-for 1))
      (with-current-buffer (get-buffer buffer)
        (if (and (buffer-modified-p)
                 (buffer-file-name (current-buffer)))
            (progn
              (save-buffer)
              (kill-buffer buffer))
            (kill-buffer buffer)))
      (helm-delete-current-selection)
      (with-helm-temp-hook 'helm-after-persistent-action-hook
        (helm-force-update (regexp-quote (helm-get-selection nil t))))))

(defun helm-buffers--quote-truncated-buffer (buffer)
  (let ((bufname (and (bufferp buffer)
                      (buffer-name buffer))))
    (when bufname
      (regexp-quote
       (if helm-buffer-max-length
           (helm-substring-by-width
            bufname helm-buffer-max-length
            "")
           bufname)))))

(defun helm-buffers-persistent-kill (_buffer)
  (let ((marked (helm-marked-candidates)))
    (unwind-protect
         (cl-loop for b in marked
               do (progn (helm-preselect
                          (format "^%s"
                                  (helm-buffers--quote-truncated-buffer b)))
                         (when (y-or-n-p (format "kill buffer (%s)? " b))
                           (helm-buffers-persistent-kill-1 b))
                         (message nil)))
      (with-helm-buffer
        (setq helm-marked-candidates nil
              helm-visible-mark-overlays nil))
      (helm-force-update (helm-buffers--quote-truncated-buffer
                          (helm-get-selection))))))

(defun helm-buffers-list-persistent-action (candidate)
  (if current-prefix-arg
      (helm-buffers-persistent-kill candidate)
    (switch-to-buffer candidate)))

(defun helm-ediff-marked-buffers (_candidate &optional merge)
  "Ediff 2 marked buffers or CANDIDATE and `helm-current-buffer'.
With optional arg MERGE call `ediff-merge-buffers'."
  (let ((lg-lst (length (helm-marked-candidates)))
        buf1 buf2)
    (cl-case lg-lst
      (0
       (error "Error:You have to mark at least 1 buffer"))
      (1
       (setq buf1 helm-current-buffer
             buf2 (cl-first (helm-marked-candidates))))
      (2
       (setq buf1 (cl-first (helm-marked-candidates))
             buf2 (cl-second (helm-marked-candidates))))
      (t
       (error "Error:To much buffers marked!")))
    (if merge
        (ediff-merge-buffers buf1 buf2)
      (ediff-buffers buf1 buf2))))

(defun helm-ediff-marked-buffers-merge (candidate)
  "Ediff merge `helm-current-buffer' with CANDIDATE.
See `helm-ediff-marked-buffers'."
  (helm-ediff-marked-buffers candidate t))

(defun helm-multi-occur-as-action (_candidate)
  "Multi occur action for `helm-source-buffers-list'.
Can be used by any source that list buffers."
  (let ((helm-moccur-always-search-in-current
         (if helm-current-prefix-arg
             (not helm-moccur-always-search-in-current)
           helm-moccur-always-search-in-current))
        (buffers (helm-marked-candidates))
        (input (cl-loop for i in (split-string helm-pattern " " t)
                     thereis (and (string-match "\\`@\\(.*\\)" i)
                                  (match-string 1 i)))))
    (helm-multi-occur-1 buffers input)))

(defun helm-buffers-run-multi-occur ()
  "Run `helm-multi-occur-as-action' by key."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-multi-occur-as-action)))

(defun helm-buffers-toggle-show-hidden-buffers ()
  (interactive)
  (with-helm-alive-p
    (let ((filter-attrs (helm-attr 'filtered-candidate-transformer
                                   helm-source-buffers-list)))
      (if (memq 'helm-shadow-boring-buffers filter-attrs)
          (helm-attrset 'filtered-candidate-transformer
                        (cons 'helm-skip-boring-buffers
                              (remove 'helm-shadow-boring-buffers
                                      filter-attrs))
                        helm-source-buffers-list t)
        (helm-attrset 'filtered-candidate-transformer
                      (cons 'helm-shadow-boring-buffers
                            (remove 'helm-skip-boring-buffers
                                    filter-attrs))
                      helm-source-buffers-list t))
      (helm-force-update))))


;;; Candidate Transformers
;;
;;
(defun helm-skip-boring-buffers (buffers _source)
  (helm-skip-entries buffers helm-boring-buffer-regexp-list))

(defun helm-shadow-boring-buffers (buffers _source)
  "Buffers matching `helm-boring-buffer-regexp' will be
displayed with the `file-name-shadow' face if available."
  (helm-shadow-entries buffers helm-boring-buffer-regexp-list))


(define-helm-type-attribute 'buffer
  `((action
     . ,(helm-make-actions
         "Switch to buffer" 'switch-to-buffer
         (lambda () (and (locate-library "popwin") "Switch to buffer in popup window"))
         'popwin:popup-buffer
         "Switch to buffer other window `C-c o'" 'switch-to-buffer-other-window
         "Switch to buffer other frame `C-c C-o'" 'switch-to-buffer-other-frame
         (lambda () (and (locate-library "elscreen") "Display buffer in Elscreen"))
         'helm-find-buffer-on-elscreen
         "Query replace regexp `C-M-%'" 'helm-buffer-query-replace-regexp
         "Query replace `M-%'" 'helm-buffer-query-replace
         "View buffer" 'view-buffer
         "Display buffer" 'display-buffer
         "Grep buffers `M-g s' (C-u grep all buffers)" 'helm-zgrep-buffers
         "Multi occur buffer(s) `C-s'" 'helm-multi-occur-as-action
         "Revert buffer(s) `M-U'" 'helm-revert-marked-buffers
         "Insert buffer" 'insert-buffer
         "Kill buffer(s) `M-D'" 'helm-kill-marked-buffers
         "Diff with file" 'diff-buffer-with-file
         "Ediff Marked buffers `C-c ='" 'helm-ediff-marked-buffers
         "Ediff Merge marked buffers `M-='" (lambda (candidate)
                                              (helm-ediff-marked-buffers candidate t))))
    (persistent-help . "Show this buffer")
    (filtered-candidate-transformer helm-skip-boring-buffers
                                    helm-buffers-sort-transformer
                                    helm-highlight-buffers))
  "Buffer or buffer name.")

;;;###autoload
(defun helm-buffers-list ()
  "Preconfigured `helm' to list buffers."
  (interactive)
  (unless helm-source-buffers-list
    (setq helm-source-buffers-list
          (helm-make-source "Buffers" 'helm-source-buffers)))
  (helm :sources '(helm-source-buffers-list
                   helm-source-ido-virtual-buffers
                   helm-source-buffer-not-found)
        :buffer "*helm buffers*"
        :keymap helm-buffer-map
        :truncate-lines helm-buffers-truncate-lines))

;;;###autoload
(defun helm-mini ()
  "Preconfigured `helm' lightweight version \(buffer -> recentf\)."
  (interactive)
  (require 'helm-files)
  (unless helm-source-buffers-list
    (setq helm-source-buffers-list
          (helm-make-source "Buffers" 'helm-source-buffers)))
  (helm :sources helm-mini-default-sources
        :buffer "*helm mini*"
        :ff-transformer-show-only-basename nil
        :truncate-lines helm-buffers-truncate-lines))

(provide 'helm-buffers)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-buffers.el ends here
