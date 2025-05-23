;;; helm-bookmark.el --- Helm for Emacs regular Bookmarks. -*- lexical-binding: t -*-

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
(require 'bookmark)
(require 'helm)
(require 'helm-types)
(require 'helm-utils)
(require 'helm-info)
(require 'helm-adaptive)
(require 'helm-net)

(declare-function addressbook-bookmark-edit "ext:addressbook-bookmark.el" (bookmark))
(declare-function message-buffers "message.el")
(declare-function addressbook-set-mail-buffer-1 "ext:addressbook-bookmark.el"
                  (&optional bookmark-name append cc))


(defgroup helm-bookmark nil
  "Predefined configurations for `helm.el'."
  :group 'helm)

(defcustom helm-bookmark-show-location nil
  "Show location of bookmark on display."
  :group 'helm-bookmark
  :type 'boolean)

(defcustom helm-bookmark-default-filtered-sources
  (append '(helm-source-bookmark-files&dirs
            helm-source-bookmark-helm-find-files
            helm-source-bookmark-info
            helm-source-bookmark-gnus
            helm-source-bookmark-man
            helm-source-bookmark-images
            helm-source-bookmark-w3m)
          (and (locate-library "addressbook-bookmark")
               (list 'helm-source-bookmark-addressbook))
          (list 'helm-source-bookmark-uncategorized
                'helm-source-bookmark-set))
  "List of sources to use in `helm-filtered-bookmarks'."
  :group 'helm-bookmark
  :type '(repeat (choice symbol)))

(defcustom helm-bookmark-addressbook-actions
  '(("Show Contact(s)"
     . (lambda (candidate)
         (let* ((contacts (helm-marked-candidates))
                (current-prefix-arg helm-current-prefix-arg))
           (bookmark-jump
            (helm-bookmark-get-bookmark-from-name (car contacts)))
           (helm-aif (cdr contacts)
               (let ((current-prefix-arg '(4)))
                 (cl-loop for bmk in it do
                          (bookmark-jump
                           (helm-bookmark-get-bookmark-from-name bmk))))))))
    ("Mail To" . helm-bookmark-addressbook-send-mail-1)
    ("Mail Cc" . (lambda (_candidate)
                   (helm-bookmark-addressbook-send-mail-1 nil 'cc)))
    ("Mail Bcc" . (lambda (_candidate)
                    (helm-bookmark-addressbook-send-mail-1 nil 'bcc)))
    ("Edit Bookmark"
     . (lambda (candidate)
         (let ((bmk (helm-bookmark-get-bookmark-from-name
                     candidate)))
           (addressbook-bookmark-edit
            (assoc bmk bookmark-alist)))))
    ("Delete bookmark(s)" . helm-delete-marked-bookmarks)
    ("Insert Email at point"
     . (lambda (candidate)
         (let* ((bmk   (helm-bookmark-get-bookmark-from-name
                        candidate))
                (mlist (split-string
                        (assoc-default
                         'email (assoc bmk bookmark-alist))
                        ", ")))
           (insert
            (if (> (length mlist) 1)
                (helm-comp-read
                 "Insert Mail Address: " mlist :must-match t)
                (car mlist))))))
    ("Show annotation"
     . (lambda (candidate)
         (let ((bmk (helm-bookmark-get-bookmark-from-name
                     candidate)))
           (bookmark-show-annotation bmk))))
    ("Edit annotation"
     . (lambda (candidate)
         (let ((bmk (helm-bookmark-get-bookmark-from-name
                     candidate)))
           (bookmark-edit-annotation bmk))))
    ("Show Google map"
     . (lambda (candidate)
         (let* ((bmk (helm-bookmark-get-bookmark-from-name
                      candidate))
                (full-bmk (assoc bmk bookmark-alist)))
           (addressbook-google-map full-bmk)))))
  "Actions for addressbook bookmarks."
  :group 'helm-bookmark
  :type '(alist :key-type string :value-type function))


(defface helm-bookmark-info
    '((t (:foreground "green")))
  "Face used for W3m Emacs bookmarks (not w3m bookmarks)."
  :group 'helm-bookmark)

(defface helm-bookmark-w3m
    '((t (:foreground "yellow")))
  "Face used for W3m Emacs bookmarks (not w3m bookmarks)."
  :group 'helm-bookmark)

(defface helm-bookmark-gnus
    '((t (:foreground "magenta")))
  "Face used for Gnus bookmarks."
  :group 'helm-bookmark)

(defface helm-bookmark-man
    '((t (:foreground "Orange4")))
  "Face used for Woman/man bookmarks."
  :group 'helm-bookmark)

(defface helm-bookmark-file
    '((t (:foreground "Deepskyblue2")))
  "Face used for file bookmarks."
  :group 'helm-bookmark)

(defface helm-bookmark-directory
    '((t (:inherit helm-ff-directory)))
  "Face used for file bookmarks."
  :group 'helm-bookmark)

(defface helm-bookmark-addressbook
    '((t (:foreground "tomato")))
  "Face used for addressbook bookmarks."
  :group 'helm-bookmark)


(defvar helm-bookmark-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c o") 'helm-bookmark-run-jump-other-window)
    (define-key map (kbd "C-d")   'helm-bookmark-run-delete)
    (define-key map (kbd "C-]")   'helm-bookmark-toggle-filename)
    (define-key map (kbd "M-e")   'helm-bookmark-run-edit)
    (define-key map (kbd "C-c ?") 'helm-bookmark-help)
    map)
  "Generic Keymap for emacs bookmark sources.")

(defclass helm-source-basic-bookmarks (helm-source-in-buffer helm-type-bookmark)
   ((init :initform (lambda ()
                      (bookmark-maybe-load-default-file)
                      (helm-init-candidates-in-buffer
                          'global
                        (bookmark-all-names))))
    (filtered-candidate-transformer :initform 'helm-bookmark-transformer)
    (search :initform 'helm-bookmark-search-fn)))

(defvar helm-source-bookmarks
  (helm-make-source "Bookmarks" 'helm-source-basic-bookmarks)
  "See (info \"(emacs)Bookmarks\").")

(defun helm-bookmark-transformer (candidates _source)
  (cl-loop for i in candidates
        for loc = (bookmark-location i)
        for len =  (string-width i)
        for trunc = (if (> len bookmark-bmenu-file-column)
                        (helm-substring i bookmark-bmenu-file-column)
                      i)
        for sep = (make-string (- (+ bookmark-bmenu-file-column 2)
                                  (length trunc))
                               ? )
        if helm-bookmark-show-location
        collect (cons (concat trunc sep (if (listp loc) (car loc) loc)) i)
        else collect i))

(defun helm-bookmark-toggle-filename-1 (_candidate)
  (let* ((real (helm-get-selection helm-buffer))
         (trunc (if (> (string-width real) bookmark-bmenu-file-column)
                    (helm-substring real bookmark-bmenu-file-column)
                    real))
         (loc (bookmark-location real)))
    (setq helm-bookmark-show-location (not helm-bookmark-show-location))
    (helm-force-update (if helm-bookmark-show-location
                           (concat (regexp-quote trunc)
                                   " +"
                                   (regexp-quote
                                    (if (listp loc) (car loc) loc)))
                           real))))

(defun helm-bookmark-toggle-filename ()
  "Toggle bookmark location visibility."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'toggle-filename
                  '(helm-bookmark-toggle-filename-1 . never-split))
    (helm-execute-persistent-action 'toggle-filename)))

(defun helm-bookmark-jump (candidate)
  "Jump to bookmark from keyboard."
  (let ((current-prefix-arg helm-current-prefix-arg)
        non-essential)
    (bookmark-jump candidate)))

(defun helm-bookmark-jump-other-window (candidate)
  (let (non-essential)
    (bookmark-jump-other-window candidate)))


;;; bookmark-set
;;
(defvar helm-source-bookmark-set
  (helm-build-dummy-source "Set Bookmark" :action 'bookmark-set)
  "See (info \"(emacs)Bookmarks\").")


;;; Search and match-part fns.
;;
(defun helm-bookmark-search-fn (pattern)
    "Search function for bookmark sources using `helm-source-in-buffer'."
  (if helm-bookmark-show-location
      (helm-aif (next-single-property-change (point) 'location)
          (goto-char it))
    (re-search-forward pattern nil t)))

(defun helm-bookmark-match-part-fn (candidate)
  "Match part function for bookmark sources using `helm-source-in-buffer'."
  (helm-aif (and helm-bookmark-show-location
                 (bookmark-location candidate))
      ;; Match against bookmark-name and location.
      (concat candidate " " it)
    ;; Match against bookmark-name.
    candidate))


;;; Predicates
;;
(defconst helm-bookmark--non-file-filename "   - no file -"
  "Name to use for `filename' entry, for non-file bookmarks.")

(defun helm-bookmark-gnus-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is a Gnus bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (or (eq (bookmark-get-handler bookmark) 'bmkext-jump-gnus)
      (eq (bookmark-get-handler bookmark) 'gnus-summary-bookmark-jump)
      (eq (bookmark-get-handler bookmark) 'bookmarkp-jump-gnus)))

(defun helm-bookmark-w3m-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is a W3m bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (or (eq (bookmark-get-handler bookmark) 'bmkext-jump-w3m)
      (eq (bookmark-get-handler bookmark) 'bookmark-w3m-bookmark-jump)
      (eq (bookmark-get-handler bookmark) 'bookmarkp-jump-w3m)))

(defun helm-bookmark-woman-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is a Woman bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (or (eq (bookmark-get-handler bookmark) 'bmkext-jump-woman)
      (eq (bookmark-get-handler bookmark) 'woman-bookmark-jump)
      (eq (bookmark-get-handler bookmark) 'bookmarkp-jump-woman)))

(defun helm-bookmark-man-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is a Man bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (or (eq (bookmark-get-handler bookmark) 'bmkext-jump-man)
      (eq (bookmark-get-handler bookmark) 'Man-bookmark-jump)
      (eq (bookmark-get-handler bookmark) 'bookmarkp-jump-man)))

(defun helm-bookmark-woman-man-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is a Man or Woman bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (or (helm-bookmark-man-bookmark-p bookmark)
      (helm-bookmark-woman-bookmark-p bookmark)))

(defun helm-bookmark-info-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK is an Info bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (eq (bookmark-get-handler bookmark) 'Info-bookmark-jump))

(defun helm-bookmark-image-bookmark-p (bookmark)
  "Return non-nil if BOOKMARK bookmarks an image file."
  (if (stringp bookmark)
      (assoc 'image-type (assoc bookmark bookmark-alist))
    (assoc 'image-type bookmark)))

(defun helm-bookmark-file-p (bookmark)
  "Return non-nil if BOOKMARK bookmarks a file or directory.
BOOKMARK is a bookmark name or a bookmark record.
This excludes bookmarks of a more specific kind (Info, Gnus, and W3m)."
  (let* ((filename   (bookmark-get-filename bookmark))
         (isnonfile  (equal filename helm-bookmark--non-file-filename))) 
    (and filename (not isnonfile) (not (bookmark-get-handler bookmark)))))

(defun helm-bookmark-helm-find-files-p (bookmark)
  "Return non-nil if BOOKMARK bookmarks a `helm-find-files' session.
BOOKMARK is a bookmark name or a bookmark record."
  (eq (bookmark-get-handler bookmark) 'helm-ff-bookmark-jump))

(defun helm-bookmark-addressbook-p (bookmark)
  "Return non--nil if BOOKMARK is a contact recorded with addressbook-bookmark.
BOOKMARK is a bookmark name or a bookmark record."
  (if (listp bookmark)
      (string= (assoc-default 'type bookmark) "addressbook")
    (string= (assoc-default
              'type (assoc bookmark bookmark-alist)) "addressbook")))

(defun helm-bookmark-uncategorized-bookmark-p (bookmark)
  "Return non--nil if BOOKMARK match no known category."
  (cl-loop for pred in '(helm-bookmark-addressbook-p
                         helm-bookmark-gnus-bookmark-p
                         helm-bookmark-w3m-bookmark-p
                         helm-bookmark-woman-man-bookmark-p
                         helm-bookmark-info-bookmark-p
                         helm-bookmark-image-bookmark-p
                         helm-bookmark-file-p
                         helm-bookmark-helm-find-files-p
                         helm-bookmark-addressbook-p)
           never (funcall pred bookmark)))

(defun helm-bookmark-filter-setup-alist (fn)
  "Return a filtered `bookmark-alist' sorted alphabetically."
  (cl-loop with alist = (cl-loop for b in bookmark-alist
                              when (funcall fn b) collect b)
        for bmk in alist
        for name = (car bmk)
        collect (propertize name 'location (bookmark-location name))))


;;; Bookmark handlers
;;
(defvar w3m-async-exec)
(defun helm-bookmark-jump-w3m (bookmark)
  "Jump to W3m bookmark BOOKMARK, setting a new tab.
If `browse-url-browser-function' is set to something else
than `w3m-browse-url' use it."
  (require 'helm-net)
  (let ((file  (or (bookmark-prop-get bookmark 'filename)
                   (bookmark-prop-get bookmark 'url)))
        (buf   (generate-new-buffer-name "*w3m*"))
        (w3m-async-exec nil)
        (really-use-w3m (equal browse-url-browser-function 'w3m-browse-url)))
    (helm-browse-url file really-use-w3m)
    (when really-use-w3m
      (bookmark-default-handler
       `("" (buffer . ,buf) . ,(bookmark-get-bookmark-record bookmark))))))

;; All bookmarks recorded with the handler provided with w3m
;; (`bookmark-w3m-bookmark-jump') will use our handler which open
;; the bookmark in a new tab or in an external browser depending
;; on `browse-url-browser-function'.
(defalias 'bookmark-w3m-bookmark-jump 'helm-bookmark-jump-w3m)

;; Provide compatibility with old handlers provided in external
;; packages bookmark-extensions.el and bookmark+.
(defalias 'bmkext-jump-woman 'woman-bookmark-jump)
(defalias 'bmkext-jump-man 'Man-bookmark-jump)
(defalias 'bmkext-jump-w3m 'helm-bookmark-jump-w3m)
(defalias 'bmkext-jump-gnus 'gnus-summary-bookmark-jump)
(defalias 'bookmarkp-jump-gnus 'gnus-summary-bookmark-jump)
(defalias 'bookmarkp-jump-w3m 'helm-bookmark-jump-w3m)
(defalias 'bookmarkp-jump-woman 'woman-bookmark-jump)
(defalias 'bookmarkp-jump-man 'Man-bookmark-jump)


;;;; Filtered bookmark sources
;;
;;
(defclass helm-source-filtered-bookmarks (helm-source-in-buffer helm-type-bookmark)
  ((search :initform #'helm-bookmark-search-fn)
   (match-part :initform #'helm-bookmark-match-part-fn)
   (filtered-candidate-transformer
    :initform '(helm-adaptive-sort
                helm-highlight-bookmark))))

;;; W3m bookmarks.
;;
(defun helm-bookmark-w3m-setup-alist ()
  "Specialized filter function for bookmarks w3m."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-w3m-bookmark-p))

(defvar helm-source-bookmark-w3m
  (helm-make-source "Bookmark W3m" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-w3m-setup-alist)))))

;;; Images
;;
(defun helm-bookmark-images-setup-alist ()
  "Specialized filter function for images bookmarks."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-image-bookmark-p))

(defvar helm-source-bookmark-images
  (helm-make-source "Bookmark Images" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-images-setup-alist)))))

;;; Woman Man
;;
(defun helm-bookmark-man-setup-alist ()
  "Specialized filter function for bookmarks w3m."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-woman-man-bookmark-p))

(defvar helm-source-bookmark-man
  (helm-make-source "Bookmark Woman&Man" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-man-setup-alist)))))

;;; Gnus
;;
(defun helm-bookmark-gnus-setup-alist ()
  "Specialized filter function for bookmarks gnus."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-gnus-bookmark-p))

(defvar helm-source-bookmark-gnus
  (helm-make-source "Bookmark Gnus" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-gnus-setup-alist)))))

;;; Info
;;
(defun helm-bookmark-info-setup-alist ()
  "Specialized filter function for bookmarks info."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-info-bookmark-p))

(defvar helm-source-bookmark-info
  (helm-make-source "Bookmark Info" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-info-setup-alist)))))

;;; Files and directories
;;
(defun helm-bookmark-local-files-setup-alist ()
  "Specialized filter function for bookmarks locals files."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-file-p))

(defvar helm-source-bookmark-files&dirs
  (helm-make-source "Bookmark Files&Directories" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-local-files-setup-alist)))))

;;; Helm find files sessions.
;;
(defun helm-bookmark-helm-find-files-setup-alist ()
  "Specialized filter function for `helm-find-files' bookmarks."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-helm-find-files-p))

(defvar helm-source-bookmark-helm-find-files
  (helm-make-source "Bookmark helm-find-files sessions" 'helm-source-filtered-bookmarks
      :init (lambda ()
              (bookmark-maybe-load-default-file)
              (helm-init-candidates-in-buffer
                  'global (helm-bookmark-helm-find-files-setup-alist)))))

;;; Uncategorized bookmarks
;;
(defun helm-bookmark-uncategorized-setup-alist ()
  "Specialized filter function for uncategorized bookmarks."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-uncategorized-bookmark-p))

(defvar helm-source-bookmark-uncategorized
  (helm-make-source "Bookmark uncategorized" 'helm-source-filtered-bookmarks
    :init (lambda ()
            (bookmark-maybe-load-default-file)
            (helm-init-candidates-in-buffer
                'global (helm-bookmark-uncategorized-setup-alist)))))

;;; Addressbook.
;;
;;
(defclass helm-bookmark-addressbook-class (helm-source-in-buffer)
  ((init :initform (lambda ()
                     (require 'addressbook-bookmark nil t)
                     (bookmark-maybe-load-default-file)
                     (helm-init-candidates-in-buffer
                         'global
                       (helm-bookmark-addressbook-setup-alist))))
   (search :initform #'helm-bookmark-search-fn)
   (match-part :initform #'helm-bookmark-match-part-fn)
   (persistent-action :initform
                      (lambda (candidate)
                        (let ((bmk (helm-bookmark-get-bookmark-from-name
                                    candidate)))
                          (bookmark--jump-via bmk 'switch-to-buffer))))
   (persistent-help :initform "Show contact - Prefix with C-u to append")
   (filtered-candidate-transformer :initform
                                   '(helm-adaptive-sort
                                     helm-highlight-bookmark))
   (action :initform 'helm-bookmark-addressbook-actions)))

(defun helm-bookmark-addressbook-send-mail-1 (_candidate &optional cc)
  (let* ((contacts (helm-marked-candidates))
         (bookmark      (helm-bookmark-get-bookmark-from-name
                         (car contacts)))
         (append   (message-buffers)))
    (addressbook-set-mail-buffer-1 bookmark append)
    (helm-aif (cdr contacts)
        (progn
          (when cc (addressbook-set-mail-buffer-1 (car it) nil cc))
          (cl-loop for bmk in (cdr it) do
                   (addressbook-set-mail-buffer-1
                    (helm-bookmark-get-bookmark-from-name bmk) 'append cc))))))

(defun helm-bookmark-addressbook-setup-alist ()
  "Specialized filter function for addressbook bookmarks."
  (helm-bookmark-filter-setup-alist 'helm-bookmark-addressbook-p))

(defvar helm-source-bookmark-addressbook
  (helm-make-source "Bookmark Addressbook" 'helm-bookmark-addressbook-class))

;;; Transformer
;;

(defun helm-highlight-bookmark (bookmarks _source)
  "Used as `filtered-candidate-transformer' to colorize bookmarks.
Work both with standard Emacs bookmarks and bookmark-extensions.el."
  (let ((non-essential t))
    (cl-loop for i in bookmarks
          for isfile        = (bookmark-get-filename i)
          for hff           = (helm-bookmark-helm-find-files-p i)
          for handlerp      = (and (fboundp 'bookmark-get-handler)
                                   (bookmark-get-handler i))
          for isw3m         = (and (fboundp 'helm-bookmark-w3m-bookmark-p)
                                   (helm-bookmark-w3m-bookmark-p i))
          for isgnus        = (and (fboundp 'helm-bookmark-gnus-bookmark-p)
                                   (helm-bookmark-gnus-bookmark-p i))
          for isman         = (and (fboundp 'helm-bookmark-man-bookmark-p) ; Man
                                   (helm-bookmark-man-bookmark-p i))
          for iswoman       = (and (fboundp 'helm-bookmark-woman-bookmark-p) ; Woman
                                   (helm-bookmark-woman-bookmark-p i))
          for isannotation  = (bookmark-get-annotation i)
          for isabook       = (string= (bookmark-prop-get i 'type)
                                       "addressbook")
          for isinfo        = (eq handlerp 'Info-bookmark-jump)
          for loc = (bookmark-location i)
          for len =  (string-width i)
          for trunc = (if (and helm-bookmark-show-location
                               (> len bookmark-bmenu-file-column))
                          (helm-substring
                           i bookmark-bmenu-file-column)
                        i)
          ;; Add a * if bookmark have annotation
          if (and isannotation (not (string-equal isannotation "")))
          do (setq trunc (concat "*" (if helm-bookmark-show-location trunc i)))
          for sep = (and helm-bookmark-show-location
                         (make-string (- (+ bookmark-bmenu-file-column 2)
                                         (string-width trunc))
                                      ? ))
          for bmk = (cond ( ;; info buffers
                           isinfo
                           (propertize trunc 'face 'helm-bookmark-info
                                       'help-echo isfile))
                          ( ;; w3m buffers
                           isw3m
                           (propertize trunc 'face 'helm-bookmark-w3m
                                       'help-echo isfile))
                          ( ;; gnus buffers
                           isgnus
                           (propertize trunc 'face 'helm-bookmark-gnus
                                       'help-echo isfile))
                          ( ;; Man Woman
                           (or iswoman isman)
                           (propertize trunc 'face 'helm-bookmark-man
                                       'help-echo isfile))
                          ( ;; Addressbook
                           isabook
                           (propertize trunc 'face 'helm-bookmark-addressbook))
                          ( ;; directories
                           (and isfile
                                (or hff
                                    ;; This is needed because `non-essential'
                                    ;; is not working on Emacs-24.2 and the behavior
                                    ;; of tramp seems to have changed since previous
                                    ;; versions (Need to reenter password even if a
                                    ;; first connection have been established,
                                    ;; probably when host is named differently
                                    ;; i.e machine/localhost)
                                    (and (not (file-remote-p isfile))
                                         (file-directory-p isfile))))
                           (propertize trunc 'face 'helm-bookmark-directory
                                       'help-echo isfile))
                          ( ;; regular files
                           t
                           (propertize trunc 'face 'helm-bookmark-file
                                       'help-echo isfile)))
          collect (if helm-bookmark-show-location
                      (cons (concat bmk sep (if (listp loc) (car loc) loc))
                            i)
                    (cons bmk i)))))


;;; Edit/rename/save bookmarks.
;;
;;
(defun helm-bookmark-edit-bookmark (bookmark-name)
  "Edit bookmark's name and file name, and maybe save them.
BOOKMARK-NAME is the current (old) name of the bookmark to be renamed."
  (let ((bmk (helm-bookmark-get-bookmark-from-name bookmark-name))
        (handler (bookmark-prop-get bookmark-name 'handler)))
    (if (eq handler 'addressbook-bookmark-jump)
        (addressbook-bookmark-edit
         (assoc bmk bookmark-alist))
      (helm-bookmark-edit-bookmark-1 bookmark-name handler))))

(defun helm-bookmark-edit-bookmark-1 (bookmark-name handler)
  (let* ((helm--reading-passwd-or-string t)
         (bookmark-fname (bookmark-get-filename bookmark-name))
         (bookmark-loc   (bookmark-prop-get bookmark-name 'location))
         (new-name       (read-from-minibuffer "Name: " bookmark-name))
         (new-loc        (read-from-minibuffer "FileName or Location: "
                                               (or bookmark-fname
                                                   (if (consp bookmark-loc)
                                                       (car bookmark-loc)
                                                     bookmark-loc))))
         (docid           (and (eq handler 'mu4e-bookmark-jump)
                               (read-number "Docid: " (cdr bookmark-loc)))))
    (when docid
      (setq new-loc (cons new-loc docid)))
    (when (and (not (equal new-name "")) (not (equal new-loc ""))
               (y-or-n-p "Save changes? "))
      (if bookmark-fname
          (progn
            (helm-bookmark-rename bookmark-name new-name 'batch)
            (bookmark-set-filename new-name new-loc))
        (bookmark-prop-set
         (bookmark-get-bookmark bookmark-name) 'location new-loc)
        (helm-bookmark-rename bookmark-name new-name 'batch))
      (helm-bookmark-maybe-save-bookmark)
      (list new-name new-loc))))

(defun helm-bookmark-maybe-save-bookmark ()
  "Increment save counter and maybe save `bookmark-alist'."
  (setq bookmark-alist-modification-count (1+ bookmark-alist-modification-count))
  (when (bookmark-time-to-save-p) (bookmark-save)))

(defun helm-bookmark-rename (old &optional new batch)
  "Change bookmark's name from OLD to NEW.
Interactively:
 If called from the keyboard, then prompt for OLD.
 If called from the menubar, select OLD from a menu.
If NEW is nil, then prompt for its string value.

If BATCH is non-nil, then do not rebuild the menu list.

While the user enters the new name, repeated `C-w' inserts consecutive
words from the buffer into the new bookmark name."
  (interactive (list (bookmark-completing-read "Old bookmark name")))
  (bookmark-maybe-historicize-string old)
  (bookmark-maybe-load-default-file)
  (save-excursion (skip-chars-forward " ") (setq bookmark-yank-point (point)))
  (setq bookmark-current-buffer (current-buffer))
  (let ((newname  (or new  (read-from-minibuffer
                            "New name: " nil
                            (let ((now-map  (copy-keymap minibuffer-local-map)))
                              (define-key now-map  "\C-w" 'bookmark-yank-word)
                              now-map)
                            nil 'bookmark-history))))
    (bookmark-set-name old newname)
    (setq bookmark-current-bookmark  newname)
    (unless batch (bookmark-bmenu-surreptitiously-rebuild-list))
    (helm-bookmark-maybe-save-bookmark) newname))

(defun helm-bookmark-run-edit ()
  "Run `helm-bookmark-edit-bookmark' from keyboard."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-bookmark-edit-bookmark)))


;;; Bookmarks attributes
;;
(define-helm-type-attribute 'bookmark
    `((coerce . helm-bookmark-get-bookmark-from-name)
      (action . ,(helm-make-actions
                  "Jump to bookmark" 'helm-bookmark-jump
                  "Jump to BM other window" 'helm-bookmark-jump-other-window
                  "Bookmark edit annotation" 'bookmark-edit-annotation
                  "Bookmark show annotation" 'bookmark-show-annotation
                  "Delete bookmark(s)" 'helm-delete-marked-bookmarks
                  "Edit Bookmark" 'helm-bookmark-edit-bookmark
                  "Rename bookmark" 'helm-bookmark-rename
                  "Relocate bookmark" 'bookmark-relocate))
      (keymap . ,helm-bookmark-map))
  "Bookmark name.")


(defun helm-bookmark-run-jump-other-window ()
  "Jump to bookmark from keyboard."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'bookmark-jump-other-window)))

(defun helm-bookmark-run-delete ()
  "Delete bookmark from keyboard."
  (interactive)
  (with-helm-alive-p
    (when (y-or-n-p "Delete bookmark(s)?")
      (helm-quit-and-execute-action 'helm-delete-marked-bookmarks))))

(defun helm-bookmark-get-bookmark-from-name (bmk)
  "Return bookmark name even if it is a bookmark with annotation.
e.g prepended with *."
  (let ((bookmark (replace-regexp-in-string "\\`\\*" "" bmk)))
    (if (assoc bookmark bookmark-alist) bookmark bmk)))

(defun helm-delete-marked-bookmarks (_ignore)
  "Delete this bookmark or all marked bookmarks."
  (cl-dolist (i (helm-marked-candidates))
    (bookmark-delete (helm-bookmark-get-bookmark-from-name i)
                     'batch)))


;;;###autoload
(defun helm-bookmarks ()
  "Preconfigured `helm' for bookmarks."
  (interactive)
  (helm :sources '(helm-source-bookmarks
                   helm-source-bookmark-set)
        :buffer "*helm bookmarks*"
        :default (buffer-name helm-current-buffer)))

;;;###autoload
(defun helm-filtered-bookmarks ()
  "Preconfigured helm for bookmarks (filtered by category).
Optional source `helm-source-bookmark-addressbook' is loaded
only if external library addressbook-bookmark.el is available."
  (interactive)
  (helm :sources helm-bookmark-default-filtered-sources
        :prompt "Search Bookmark: "
        :buffer "*helm filtered bookmarks*"
        :default (list (thing-at-point 'symbol)
                       (buffer-name helm-current-buffer))))

(provide 'helm-bookmark)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-bookmark.el ends here
