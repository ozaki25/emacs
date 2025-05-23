;;; helm-files.el --- helm file browser and related. -*- lexical-binding: t -*-

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
(require 'helm-external)
(require 'helm-grep)
(require 'helm-match-plugin)
(require 'helm-help)
(require 'helm-locate)
(require 'helm-bookmark)
(require 'helm-tags)
(require 'helm-buffers)
(require 'thingatpt)
(require 'ffap)
(require 'dired-aux)
(require 'dired-x)
(require 'tramp)
(require 'image-dired)

(declare-function find-library-name "find-func.el" (library))
(declare-function w32-shell-execute "ext:w32fns.c" (operation document &optional parameters show-flag))
(declare-function gnus-dired-attach "ext:gnus-dired.el" (files-to-attach))
(declare-function image-dired-display-image "image-dired.el" (file &optional original-size))
(declare-function image-dired-update-property "image-dired.el" (prop value))
(declare-function eshell-read-aliases-list "em-alias")
(declare-function eshell-send-input "esh-mode" (&optional use-region queue-p no-newline))
(declare-function eshell-kill-input "esh-mode")
(declare-function eshell-bol "esh-mode")
(declare-function eshell-quote-argument "esh-arg.el")
(declare-function helm-ls-git-ls "ext:helm-ls-git")
(declare-function helm-hg-find-files-in-project "ext:helm-ls-hg")
(declare-function helm-gid "helm-id-utils.el")
(declare-function helm-ls-svn-ls "ext:helm-ls-svn")

(defvar recentf-list)


;;; Type attributes
;;
;;
(define-helm-type-attribute 'file
    (helm-build-type-file)
  "File name.")



(defgroup helm-files nil
  "Files applications and libraries for Helm."
  :group 'helm)

(defcustom helm-boring-file-regexp-list
  (mapcar (lambda (f)
            (concat
             (rx-to-string
              (replace-regexp-in-string
               "/$" "" f) t) "$"))
          completion-ignored-extensions)
  "The regexp list matching boring files."
  :group 'helm-files
  :type  '(repeat (choice regexp)))

(defcustom helm-for-files-preferred-list
  '(helm-source-buffers-list
    helm-source-recentf
    helm-source-bookmarks
    helm-source-file-cache
    helm-source-files-in-current-dir
    helm-source-locate)
  "Your preferred sources to find files."
  :type '(repeat (choice symbol))
  :group 'helm-files)

(defcustom helm-tramp-verbose 0
  "Just like `tramp-verbose' but specific to helm.
When set to 0 don't show tramp messages in helm.
If you want to have the default tramp messages set it to 3."
  :type 'integer
  :group 'helm-files)

(defcustom helm-ff-auto-update-initial-value nil
  "Auto update when only one candidate directory is matched.
Default value when starting `helm-find-files' is nil because
it prevent using <backspace> to delete char backward and by the way
confuse beginners.
For a better experience with `helm-find-files' set this to non--nil
and use C-<backspace> to toggle it."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-lynx-style-map t
  "Use arrow keys to navigate with `helm-find-files'.
You will have to restart Emacs or reeval `helm-find-files-map'
and `helm-read-file-map' for this take effect."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-history-max-length 100
  "Number of elements shown in `helm-find-files' history."
  :group 'helm-files
  :type 'integer)

(defcustom helm-ff-smart-completion t
  "Try to complete filenames smarter when non--nil.
See `helm-ff--transform-pattern-for-completion' for more info."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-tramp-not-fancy t
  "No colors when listing remote files when set to non--nil.
This make listing much faster, specially on slow machines."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-exif-data-program "exiftran"
  "Program used to extract exif data of an image file."
  :group 'helm-files
  :type 'string)

(defcustom helm-ff-exif-data-program-args "-d"
  "Arguments used for `helm-ff-exif-data-program'."
  :group 'helm-files
  :type 'string)

(defcustom helm-ff-newfile-prompt-p t
  "Whether Prompt or not when creating new file.
This set `ffap-newfile-prompt'."
  :type  'boolean
  :group 'helm-files)

(defcustom helm-ff-avfs-directory "~/.avfs"
  "The default avfs directory, usually '~/.avfs'.
When this is set you will be able to expand archive filenames with `C-j'
inside an avfs directory mounted with mountavfs.
See <http://sourceforge.net/projects/avf/>."
  :type  'string
  :group 'helm-files)

(defcustom helm-ff-file-compressed-list '("gz" "bz2" "zip" "7z")
  "Minimal list of compressed files extension."
  :type  '(repeat (choice string))
  :group 'helm-files)

(defcustom helm-ff-printer-list nil
  "A list of available printers on your system.
When non--nil let you choose a printer to print file.
Otherwise when nil the variable `printer-name' will be used.
On Unix based systems (lpstat command needed) you don't need to set this,
`helm-ff-find-printers' will find a list of available printers for you."
  :type '(repeat (choice string))
  :group 'helm-files)

(defcustom helm-ff-transformer-show-only-basename t
  "Show only basename of candidates in `helm-find-files'.
This can be toggled at anytime from `helm-find-files' with \
\\<helm-find-files-map>\\[helm-ff-run-toggle-basename]."
  :type 'boolean
  :group 'helm-files)

(defcustom helm-ff-signal-error-on-dot-files t
  "Signal error when file is `.' or `..' on file deletion when non--nil.
Default is non--nil.
WARNING: Setting this to nil is unsafe and can cause deletion of a whole tree."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-ff-search-library-in-sexp nil
  "Search for library in `require' and `declare-function' sexp."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-tooltip-hide-delay 25
  "Hide tooltips automatically after this many seconds."
  :group 'helm-files
  :type 'integer)

(defcustom helm-ff-file-name-history-use-recentf nil
  "Use `recentf-list' instead of `file-name-history' in `helm-find-files'."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-ff-skip-boring-files nil
  "Non--nil to skip files matching regexps in `helm-boring-file-regexp-list'.
This take effect in `helm-find-files' and file completion used by `helm-mode'
i.e `helm-read-file-name'."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-findutils-skip-boring-files t
  "Ignore files matching regexps in `completion-ignored-extensions'."
  :group 'helm-files
  :type  'boolean)

(defcustom helm-findutils-search-full-path nil
  "Search in full path with shell command find when non--nil.
I.e use the -path/ipath arguments of find instead of -name/iname."
  :group 'helm-files
  :type 'boolean)

(defcustom helm-files-save-history-extra-sources
  '("Find" "Locate" "Recentf"
    "Files from Current Directory" "File Cache")
  "Extras source that save candidate to `file-name-history'."
  :group 'helm-files
  :type '(repeat (choice string)))

(defcustom helm-find-files-before-init-hook nil
  "Hook that run before initialization of `helm-find-files'."
  :group 'helm-files
  :type 'hook)

(defcustom helm-find-files-after-init-hook nil
  "Hook that run after initialization of `helm-find-files'."
  :group 'helm-files
  :type 'hook)

(defcustom helm-multi-files-toggle-locate-binding "C-c p"
  "Default binding to switch back and forth locate in `helm-multi-files'."
  :group 'helm-files
  :type 'string)

(defcustom helm-find-files-bookmark-prefix "Helm-find-files: "
  "bookmark name prefix of `helm-find-files' sessions."
  :group 'helm-files
  :type 'string)

;;; Faces
;;
;;
(defgroup helm-files-faces nil
  "Customize the appearance of helm-files."
  :prefix "helm-"
  :group 'helm-files
  :group 'helm-faces)

(defface helm-ff-prefix
    '((t (:background "yellow" :foreground "black")))
  "Face used to prefix new file or url paths in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-executable
    '((t (:foreground "green")))
  "Face used for executable files in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-directory
    '((t (:foreground "DarkRed" :background "LightGray")))
  "Face used for directories in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-dotted-directory
    '((t (:foreground "black" :background "DimGray")))
  "Face used for dotted directories in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-symlink
    '((t (:foreground "DarkOrange")))
  "Face used for symlinks in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-invalid-symlink
    '((t (:foreground "black" :background "red")))
  "Face used for invalid symlinks in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-ff-file
    '((t (:inherit font-lock-builtin-face)))
  "Face used for file names in `helm-find-files'."
  :group 'helm-files-faces)

(defface helm-history-deleted
    '((t (:inherit helm-ff-invalid-symlink)))
  "Face used for deleted files in `file-name-history'."
  :group 'helm-files-faces)

(defface helm-history-remote
    '((t (:foreground "Indianred1")))
  "Face used for remote files in `file-name-history'."
  :group 'helm-files-faces)


;;; Helm-find-files - The helm file browser.
;;
;; Keymaps
(defvar helm-find-files-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-]")           'helm-ff-run-toggle-basename)
    (define-key map (kbd "C-x C-f")       'helm-ff-run-locate)
    (define-key map (kbd "C-x C-d")       'helm-ff-run-browse-project)
    (define-key map (kbd "C-x r m")       'helm-ff-bookmark-set)
    (define-key map (kbd "C-x r b")       'helm-find-files-toggle-to-bookmark)
    (define-key map (kbd "C-s")           'helm-ff-run-grep)
    (define-key map (kbd "M-g s")         'helm-ff-run-grep)
    (define-key map (kbd "M-g p")         'helm-ff-run-pdfgrep)
    (define-key map (kbd "M-g z")         'helm-ff-run-zgrep)
    (define-key map (kbd "C-c g")         'helm-ff-run-gid)
    (define-key map (kbd "M-.")           'helm-ff-run-etags)
    (define-key map (kbd "M-R")           'helm-ff-run-rename-file)
    (define-key map (kbd "M-C")           'helm-ff-run-copy-file)
    (define-key map (kbd "M-B")           'helm-ff-run-byte-compile-file)
    (define-key map (kbd "M-L")           'helm-ff-run-load-file)
    (define-key map (kbd "M-S")           'helm-ff-run-symlink-file)
    (define-key map (kbd "M-H")           'helm-ff-run-hardlink-file)
    (define-key map (kbd "M-D")           'helm-ff-run-delete-file)
    (define-key map (kbd "M-K")           'helm-ff-run-kill-buffer-persistent)
    (define-key map (kbd "C-c d")         'helm-ff-persistent-delete)
    (define-key map (kbd "M-e")           'helm-ff-run-switch-to-eshell)
    (define-key map (kbd "C-c i")         'helm-ff-run-complete-fn-at-point)
    (define-key map (kbd "C-c o")         'helm-ff-run-switch-other-window)
    (define-key map (kbd "C-c C-o")       'helm-ff-run-switch-other-frame)
    (define-key map (kbd "C-c C-x")       'helm-ff-run-open-file-externally)
    (define-key map (kbd "C-c X")         'helm-ff-run-open-file-with-default-tool)
    (define-key map (kbd "M-!")           'helm-ff-run-eshell-command-on-file)
    (define-key map (kbd "M-%")           'helm-ff-run-query-replace-on-marked)
    (define-key map (kbd "C-c =")         'helm-ff-run-ediff-file)
    (define-key map (kbd "M-=")           'helm-ff-run-ediff-merge-file)
    (define-key map (kbd "M-p")           'helm-ff-run-switch-to-history)
    (define-key map (kbd "C-c h")         'helm-ff-file-name-history)
    (define-key map (kbd "M-i")           'helm-ff-properties-persistent)
    (define-key map (kbd "C-c ?")         'helm-ff-help)
    (define-key map (kbd "C-}")           'helm-narrow-window)
    (define-key map (kbd "C-{")           'helm-enlarge-window)
    (define-key map (kbd "C-<backspace>") 'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c <DEL>")     'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c C-a")       'helm-ff-run-gnus-attach-files)
    (define-key map (kbd "C-c p")         'helm-ff-run-print-file)
    (define-key map (kbd "C-c /")         'helm-ff-run-find-sh-command)
    ;; Next 2 have no effect if candidate is not an image file.
    (define-key map (kbd "M-l")           'helm-ff-rotate-left-persistent)
    (define-key map (kbd "M-r")           'helm-ff-rotate-right-persistent)
    (define-key map (kbd "C-l")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-r")           'helm-find-files-down-last-level)
    (define-key map (kbd "C-c r")         'helm-ff-run-find-file-as-root)
    (define-key map (kbd "C-c @")         'helm-ff-run-insert-org-link)
    (helm-define-key-with-subkeys map (kbd "DEL") ?\d 'helm-ff-delete-char-backward
                                  nil nil 'helm-ff-delete-char-backward--exit-fn)
    (when helm-ff-lynx-style-map
      (define-key map (kbd "<left>")      'helm-find-files-up-one-level)
      (define-key map (kbd "<right>")     'helm-execute-persistent-action))
    (delq nil map))
  "Keymap for `helm-find-files'.")

(defvar helm-read-file-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "<C-return>")    'helm-cr-empty-string)
    (define-key map (kbd "<M-RET>")       'helm-cr-empty-string)
    (define-key map (kbd "C-]")           'helm-ff-run-toggle-basename)
    (define-key map (kbd "C-.")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-l")           'helm-find-files-up-one-level)
    (define-key map (kbd "C-r")           'helm-find-files-down-last-level)
    (define-key map (kbd "C-c h")         'helm-ff-file-name-history)
    (define-key map (kbd "C-<backspace>") 'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c <DEL>")     'helm-ff-run-toggle-auto-update)
    (define-key map (kbd "C-c ?")         'helm-read-file-name-help)
    (helm-define-key-with-subkeys map (kbd "DEL") ?\d 'helm-ff-delete-char-backward
                                  nil nil 'helm-ff-delete-char-backward--exit-fn)
    (when helm-ff-lynx-style-map
      (define-key map (kbd "<left>")      'helm-find-files-up-one-level)
      (define-key map (kbd "<right>")     'helm-execute-persistent-action)
      (define-key map (kbd "<M-left>")    'helm-previous-source)
      (define-key map (kbd "<M-right>")   'helm-next-source))
    (delq nil map))
  "Keymap for `helm-read-file-name'.")

(defvar helm-esh-on-file-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c ?")    'helm-esh-help)
    map)
  "Keymap for `helm-find-files-eshell-command-on-file'.")


;; Internal.
(defvar helm-find-files-doc-header " (`C-l': Go up one level)"
  "*The doc that is inserted in the Name header of a find-files or dired source.")
(defvar helm-ff-auto-update-flag nil
  "Internal, flag to turn on/off auto-update in `helm-find-files'.
Don't set it directly, use instead `helm-ff-auto-update-initial-value'.")
(defvar helm-ff-last-expanded nil
  "Store last expanded directory or file.")
(defvar helm-ff-default-directory nil)
(defvar helm-ff-history nil)
(defvar helm-ff-cand-to-mark nil)
(defvar helm-ff-url-regexp
  "\\`\\(news\\(post\\)?:\\|nntp:\\|mailto:\\|file:\\|\\(ftp\\|https?\\|telnet\\|gopher\\|www\\|wais\\):/?/?\\).*"
  "Same as `ffap-url-regexp' but match earlier possible url.")
(defvar helm-tramp-file-name-regexp "\\`/\\([^[/:]+\\|[^/]+]\\):")
(defvar helm-marked-buffer-name "*helm marked*")
(defvar helm-ff--auto-update-state nil)
(defvar helm-ff--deleting-char-backward nil)
(defvar helm-multi-files--toggle-locate nil)
(defvar helm-ff--move-to-first-real-candidate t)
(defvar helm-find-files--toggle-bookmark nil)


;;; Helm-find-files
;;
;;
(defcustom helm-find-files-actions
  (helm-make-actions
   "Find File" 'helm-find-file-or-marked
   "Find file in Dired" 'helm-point-file-in-dired
   (lambda () (and (locate-library "elscreen") "Find file in Elscreen"))
   'helm-elscreen-find-file
   "View file" 'view-file
   "Checksum File" 'helm-ff-checksum
   "Query replace fnames on marked" 'helm-ff-query-replace-on-marked
   "Query replace contents on marked" 'helm-ff-query-replace
   "Query replace regexp contents on marked" 'helm-ff-query-replace-regexp
   "Serial rename files" 'helm-ff-serial-rename
   "Serial rename by symlinking files" 'helm-ff-serial-rename-by-symlink
   "Serial rename by copying files" 'helm-ff-serial-rename-by-copying
   "Open file with default tool" 'helm-open-file-with-default-tool
   "Find file in hex dump" 'hexl-find-file
   "Browse project" 'helm-ff-browse-project
   "Complete at point `C-c i'" 'helm-insert-file-name-completion-at-point
   "Insert as org link `C-c @'" 'helm-files-insert-as-org-link
   "Find shell command `C-c /'" 'helm-ff-find-sh-command
   "Add marked files to file-cache" 'helm-ff-cache-add-file
   "Open file externally `C-c C-x, C-u to choose'" 'helm-open-file-externally
   "Grep File(s) `C-s, C-u Recurse'" 'helm-find-files-grep
   "Zgrep File(s) `M-g z, C-u Recurse'" 'helm-ff-zgrep
   "Gid" 'helm-ff-gid
   "Switch to Eshell `M-e'" 'helm-ff-switch-to-eshell
   "Etags `M-., C-u reload tag file'" 'helm-ff-etags-select
   "Eshell command on file(s) `M-!, C-u take all marked as arguments.'"
   'helm-find-files-eshell-command-on-file
   "Find file as root `C-c r'" 'helm-find-file-as-root
   "Ediff File `C-='" 'helm-find-files-ediff-files
   "Ediff Merge File `C-c ='" 'helm-find-files-ediff-merge-files
   "Delete File(s) `M-D'" 'helm-delete-marked-files
   "Copy file(s) `M-C, C-u to follow'" 'helm-find-files-copy
   "Rename file(s) `M-R, C-u to follow'" 'helm-find-files-rename
   "Symlink files(s) `M-S, C-u to follow'" 'helm-find-files-symlink
   "Relsymlink file(s) `C-u to follow'" 'helm-find-files-relsymlink
   "Hardlink file(s) `M-H, C-u to follow'" 'helm-find-files-hardlink
   "Find file other window `C-c o'" 'find-file-other-window
   "Switch to history `M-p'" 'helm-find-files-switch-to-hist
   "Find file other frame `C-c C-o'" 'find-file-other-frame
   "Print File `C-c p, C-u to refresh'" 'helm-ff-print
   "Locate `C-x C-f, C-u to specify locate db'" 'helm-ff-locate)
  "Actions for `helm-find-files'."
  :group 'helm-files
  :type '(alist :key-type string :value-type function))

(defvar helm-source-find-files nil
  "The main source to browse files.
Should not be used among other sources.")

(defclass helm-source-ffiles (helm-source-sync)
  ((header-name
    :initform (lambda (name)
                (concat name helm-find-files-doc-header)))
   (init
    :initform (lambda ()
                (setq helm-ff-auto-update-flag
                      helm-ff-auto-update-initial-value)
                (setq helm-ff--auto-update-state
                      helm-ff-auto-update-flag)
                (helm-set-local-variable 'bookmark-make-record-function
                                         #'helm-ff-make-bookmark-record)))
   (candidates :initform 'helm-find-files-get-candidates)
   (filtered-candidate-transformer :initform 'helm-ff-sort-candidates)
   (filter-one-by-one :initform 'helm-ff-filter-candidate-one-by-one)
   (persistent-action :initform 'helm-find-files-persistent-action)
   (persistent-help :initform "Hit1 Expand Candidate, Hit2 or (C-u) Find file")
   (help-message :initform 'helm-ff-help-message)
   (volatile :initform t)
   (nohighlight :initform t)
   (keymap :initform helm-find-files-map)
   (candidate-number-limit
    :initform 9999)
   (action-transformer
    :initform 'helm-find-files-action-transformer)
   (action :initform 'helm-find-files-actions)
   (before-init-hook :initform 'helm-find-files-before-init-hook)
   (after-init-hook :initform 'helm-find-files-after-init-hook)))

;; Bookmark handlers.
;;
(defun helm-ff-make-bookmark-record ()
  "The `bookmark-make-record-function' for `helm-find-files'."
  (with-helm-buffer
    `((filename . ,helm-ff-default-directory)
      (presel . ,(helm-get-selection))
      (handler . helm-ff-bookmark-jump))))

(defun helm-ff-bookmark-jump (bookmark)
  "bookmark handler for `helm-find-files'."
  (let ((fname (bookmark-prop-get bookmark 'filename))
        (presel (bookmark-prop-get bookmark 'presel)))
    (helm-find-files-1 fname (if helm-ff-transformer-show-only-basename
                                 (helm-basename presel)
                                 presel))))

(defun helm-ff-bookmark-set ()
  "Record `helm-find-files' session in bookmarks."
  (interactive)
  (with-helm-buffer
    (bookmark-set
     (concat helm-find-files-bookmark-prefix
             (abbreviate-file-name helm-ff-default-directory))))
  (message "Helm find files session bookmarked! "))

(defun helm-dwim-target-directory ()
  "Return value of `default-directory' of buffer in other window.
If there is only one window return the value ot `default-directory'
for current buffer."
  (with-helm-current-buffer
    (let ((num-windows (length (remove (get-buffer-window helm-marked-buffer-name)
                                       (window-list)))))
      (expand-file-name
       (if (> num-windows 1)
           (save-selected-window
             (other-window 1)
             default-directory)
           ;; Using the car of *ff-history allow
           ;; allow staying in the directory visited instead of current.
           (or (car-safe helm-ff-history) default-directory))))))

(defun helm-find-files-do-action (action)
  "Generic function for creating actions from `helm-source-find-files'.
ACTION must be an action supported by `helm-dired-action'."
  (let* ((ifiles (mapcar 'expand-file-name ; Allow modify '/foo/.' -> '/foo'
                         (helm-marked-candidates :with-wildcard t)))
         (cand   (helm-get-selection)) ; Target
         (prompt (format "%s %s file(s) to: "
                         (capitalize (symbol-name action))
                         (length ifiles)))
         helm-ff--move-to-first-real-candidate
         (helm-always-two-windows t)
         (helm-reuse-last-window-split-state t)
         (helm-split-window-default-side
          (eq helm-split-window-default-side 'same))
         helm-split-window-in-side-p
         (parg   helm-current-prefix-arg)
         helm-display-source-at-screen-top ; prevent setting window-start.
         helm-ff-auto-update-initial-value
         (dest   (with-helm-display-marked-candidates
                   helm-marked-buffer-name
                   (mapcar #'(lambda (f)
                               (if (file-directory-p f)
                                   (concat (helm-basename f) "/")
                                 (helm-basename f)))
                           ifiles)
                   (with-helm-current-buffer
                     (helm-read-file-name
                      prompt
                      :preselect (unless (cdr ifiles)
                                   (if helm-ff-transformer-show-only-basename
                                       (helm-basename cand) cand))
                      :initial-input (helm-dwim-target-directory)
                      :history (helm-find-files-history :comp-read nil))))))
    (helm-dired-action
     dest :files ifiles :action action :follow parg)))

(defun helm-find-files-copy (_candidate)
  "Copy files from `helm-find-files'."
  (helm-find-files-do-action 'copy))

(defun helm-find-files-rename (_candidate)
  "Rename files from `helm-find-files'."
  (helm-find-files-do-action 'rename))

(defun helm-find-files-symlink (_candidate)
  "Symlink files from `helm-find-files'."
  (helm-find-files-do-action 'symlink))

(defun helm-find-files-relsymlink (_candidate)
  "Relsymlink files from `helm-find-files'."
  (helm-find-files-do-action 'relsymlink))

(defun helm-find-files-hardlink (_candidate)
  "Hardlink files from `helm-find-files'."
  (helm-find-files-do-action 'hardlink))

(defun helm-find-files-byte-compile (_candidate)
  "Byte compile elisp files from `helm-find-files'."
  (let ((files    (helm-marked-candidates :with-wildcard t))
        (parg     helm-current-prefix-arg))
    (cl-loop for fname in files
          do (byte-compile-file fname parg))))

(defun helm-find-files-load-files (_candidate)
  "Load elisp files from `helm-find-files'."
  (let ((files    (helm-marked-candidates :with-wildcard t)))
    (cl-loop for fname in files
          do (load fname))))

(defun helm-find-files-ediff-files-1 (candidate &optional merge)
  "Generic function to ediff/merge files in `helm-find-files'."
  (let* ((bname  (helm-basename candidate))
         (marked (helm-marked-candidates :with-wildcard t))
         (prompt (if merge "Ediff Merge `%s' With File: "
                   "Ediff `%s' With File: "))
         (fun    (if merge 'ediff-merge-files 'ediff-files))
         (input  (helm-dwim-target-directory))
         (presel (if helm-ff-transformer-show-only-basename
                     (helm-basename candidate)
                   (expand-file-name
                    (helm-basename candidate)
                    input))))
    (if (= (length marked) 2)
        (funcall fun (car marked) (cadr marked))
      (funcall fun candidate (helm-read-file-name
                              (format prompt bname)
                              :initial-input input
                              :preselect presel)))))

(defun helm-find-files-ediff-files (candidate)
  (helm-find-files-ediff-files-1 candidate))

(defun helm-find-files-ediff-merge-files (candidate)
  (helm-find-files-ediff-files-1 candidate 'merge))

(defun helm-find-files-grep (_candidate)
  "Default action to grep files from `helm-find-files'."
  (apply 'run-with-timer 0.01 nil
         #'helm-do-grep-1
         (helm-marked-candidates :with-wildcard t)
         helm-current-prefix-arg))

(defun helm-ff-zgrep (_candidate)
  "Default action to zgrep files from `helm-find-files'."
  (helm-ff-zgrep-1 (helm-marked-candidates :with-wildcard t) helm-current-prefix-arg))

(defun helm-ff-pdfgrep (_candidate)
  "Default action to pdfgrep files from `helm-find-files'."
  (let ((cands (cl-loop for file in (helm-marked-candidates :with-wildcard t)
                     if (or (string= (file-name-extension file) "pdf")
                            (string= (file-name-extension file) "PDF"))
                     collect file))
        (helm-pdfgrep-default-function 'helm-pdfgrep-init))
    (when cands
      (helm-do-pdfgrep-1 cands))))

(defun helm-ff-etags-select (candidate)
  "Default action to jump to etags from `helm-find-files'."
  (when (get-buffer helm-action-buffer)
    (kill-buffer helm-action-buffer))
  (let* ((source-name (assoc-default 'name (helm-get-current-source)))
         (default-directory (if (string= source-name "Find Files")
                                helm-ff-default-directory
                              (file-name-directory candidate))))
    (helm-etags-select helm-current-prefix-arg)))

(defun helm-find-files-switch-to-hist (_candidate)
  "Switch to helm-find-files history."
  (helm-find-files t))

(defvar eshell-command-aliases-list nil)
(defvar helm-eshell-command-on-file-input-history nil)
(defun helm-find-files-eshell-command-on-file-1 (&optional map)
  "Run `eshell-command' on CANDIDATE or marked candidates.
This is done possibly with an eshell alias, if no alias found, you can type in
an eshell command.

Basename of CANDIDATE can be a wild-card.
e.g you can do \"eshell-command command *.el\"
Where \"*.el\" is the CANDIDATE.

It is possible to do eshell-command command <CANDIDATE> <some more args>
like this: \"command %s some more args\".

If MAP is given run `eshell-command' on all marked files at once,
Otherwise, run `eshell-command' on each marked files.
In other terms, with a prefix arg do on the three marked files
\"foo\" \"bar\" \"baz\":

\"eshell-command command foo bar baz\"

otherwise do

\"eshell-command command foo\"
\"eshell-command command bar\"
\"eshell-command command baz\"

Note:
If `eshell' or `eshell-command' have not been run once,
or if you have no eshell aliases `eshell-command-aliases-list'
will not be loaded first time you use this."
  (when (or eshell-command-aliases-list
            (y-or-n-p "Eshell is not loaded, run eshell-command without alias anyway? "))
    (and eshell-command-aliases-list (eshell-read-aliases-list))
    (let* ((cand-list (helm-marked-candidates))
           (default-directory (or helm-ff-default-directory
                                  ;; If candidate is an url *-ff-default-directory is nil
                                  ;; so keep value of default-directory.
                                  default-directory))
           (command (helm-comp-read
                     "Command: "
                     (cl-loop for (a . c) in eshell-command-aliases-list
                              when (string-match "\\(\\$1\\|\\$\\*\\)$" (car c))
                              collect (propertize a 'help-echo (car c)) into ls
                              finally return (sort ls 'string<))
                     :buffer "*helm eshell on file*"
                     :name "Eshell command"
                     :keymap helm-esh-on-file-map
                     :mode-line
                     '("Eshell alias"
                       "C-h m: Help, \\[universal-argument]: Insert output at point")
                     :help-message 'helm-esh-help-message
                     :input-history
                     'helm-eshell-command-on-file-input-history))
           (alias-value (car (assoc-default command eshell-command-aliases-list)))
           cmd-line)
      (if (or (equal helm-current-prefix-arg '(16))
              (equal map '(16)))
          ;; Two time C-u from `helm-comp-read' mean print to current-buffer.
          ;; i.e `eshell-command' will use this value.
          (setq current-prefix-arg '(16))
          ;; Else reset the value of `current-prefix-arg'
          ;; to avoid printing in current-buffer.
          (setq current-prefix-arg nil))
      (if (and (or
                ;; One prefix-arg have been passed before `helm-comp-read'.
                ;; If map have been set with C-u C-u (value == '(16))
                ;; ignore it.
                (and map (equal map '(4)))
                ;; One C-u from `helm-comp-read'.
                (equal helm-current-prefix-arg '(4))
                ;; An alias that finish with $*
                (and alias-value
                     ;; If command is an alias be sure it accept
                     ;; more than one arg i.e $*.
                     (string-match "\\$\\*$" alias-value)))
               (cdr cand-list))

          ;; Run eshell-command with ALL marked files as arguments.
          ;; This wont work on remote files, because tramp handlers depends
          ;; on `default-directory' (limitation).
          (let ((mapfiles (mapconcat 'eshell-quote-argument cand-list " ")))
            (if (string-match "'%s'\\|\"%s\"\\|%s" command)
                (setq cmd-line (format command mapfiles)) ; See [1]
                (setq cmd-line (format "%s %s" command mapfiles)))
            (helm-log "%S" cmd-line)
            (eshell-command cmd-line))

          ;; Run eshell-command on EACH marked files.
          ;; To work with tramp handler we have to call
          ;; COMMAND on basename of each file, using
          ;; its basedir as `default-directory'.
          (cl-loop for f in cand-list
                   for dir = (and (not (string-match ffap-url-regexp f))
                                  (helm-basedir f))
                   for file = (eshell-quote-argument
                               (format "%s" (if (and dir (file-remote-p dir))
                                                (helm-basename f) f)))
                   for com = (if (string-match "'%s'\\|\"%s\"\\|%s" command)
                                 ;; [1] This allow to enter other args AFTER filename
                                 ;; i.e <command %s some_more_args>
                                 (format command file)
                                 (format "%s %s" command file))
                   do (let ((default-directory (or dir default-directory)))
                        (eshell-command com)))))))

(defun helm-find-files-eshell-command-on-file (_candidate)
  "Run `eshell-command' on CANDIDATE or marked candidates.
See `helm-find-files-eshell-command-on-file-1' for more info."
  (helm-find-files-eshell-command-on-file-1 helm-current-prefix-arg))

(defun helm-ff-switch-to-eshell (_candidate)
  "Switch to eshell and cd to `helm-ff-default-directory'."
  (let ((cd-eshell #'(lambda ()
                       (eshell-kill-input)
                       (goto-char (point-max))
                       (insert
                        (format "cd '%s'" helm-ff-default-directory))
                       (eshell-send-input))))
    (if (get-buffer "*eshell*")
        (switch-to-buffer "*eshell*")
      (call-interactively 'eshell))
    (unless (get-buffer-process (current-buffer))
      (funcall cd-eshell))))

(defun helm-ff-serial-rename-action (method)
  "Rename all marked files in `helm-ff-default-directory' with METHOD.
See `helm-ff-serial-rename-1'."
  (let* ((helm--reading-passwd-or-string t)
         (cands     (helm-marked-candidates :with-wildcard t))
         (def-name  (car cands))
         (name      (helm-read-string "NewName: "
                                      (replace-regexp-in-string
                                       "[0-9]+$" ""
                                       (helm-basename
                                        def-name
                                        (file-name-extension def-name)))))
         (start     (read-number "StartAtNumber: "))
         (extension (helm-read-string "Extension: "
                                      (file-name-extension (car cands))))
         (dir       (expand-file-name
                     (helm-read-file-name
                      "Serial Rename to directory: "
                      :initial-input
                      (expand-file-name helm-ff-default-directory)
                      :test 'file-directory-p
                      :must-match t)))
         done)
    (with-helm-display-marked-candidates
      helm-marked-buffer-name (mapcar 'helm-basename cands)
      (if (y-or-n-p
           (format "Rename %s file(s) to <%s> like this ?\n%s "
                   (length cands) dir (format "%s <-> %s%s.%s"
                                              (helm-basename (car cands))
                                              name start extension)))
          (progn
            (helm-ff-serial-rename-1
             dir cands name start extension :method method)
            (setq done t)
            (message nil))))
    (if done
        (with-helm-current-buffer (helm-find-files-1 dir))
      (message "Operation aborted"))))

(defun helm-ff-member-directory-p (file directory)
  (let ((dir-file (expand-file-name
                   (file-name-as-directory (file-name-directory file))))
        (cur-dir  (expand-file-name (file-name-as-directory directory))))
    (string= dir-file cur-dir)))

(cl-defun helm-ff-serial-rename-1
    (directory collection new-name start-at-num extension &key (method 'rename))
  "rename files in COLLECTION to DIRECTORY with the prefix name NEW-NAME.
Rename start at number START-AT-NUM - ex: prefixname-01.jpg.
EXTENSION is the file extension to use, in empty prompt,
reuse the original extension of file.
METHOD can be one of rename, copy or symlink.
Files will be renamed if they are files of current directory, otherwise they
will be treated with METHOD.
Default METHOD is rename."
  ;; Maybe remove directories selected by error in collection.
  (setq collection (cl-remove-if 'file-directory-p collection))
  (let* ((tmp-dir  (file-name-as-directory
                    (concat (file-name-as-directory directory)
                            (symbol-name (cl-gensym "tmp")))))
         (fn       (cl-case method
                     (copy    'copy-file)
                     (symlink 'make-symbolic-link)
                     (rename  'rename-file)
                     (t (error "Error: Unknown method %s" method)))))
    (make-directory tmp-dir)
    (unwind-protect
         (progn
           ;; Rename all files to tmp-dir with new-name.
           ;; If files are not from start directory, use method
           ;; to move files to tmp-dir.
           (cl-loop for i in collection
                 for count from start-at-num
                 for fnum = (if (< count 10) "0%s" "%s")
                 for nname = (concat tmp-dir new-name (format fnum count)
                                     (if (not (string= extension ""))
                                         (format ".%s" (replace-regexp-in-string
                                                        "[.]" "" extension))
                                       (file-name-extension i 'dot)))
                 do (if (helm-ff-member-directory-p i directory)
                        (rename-file i nname)
                      (funcall fn i nname)))
           ;; Now move all from tmp-dir to destination.
           (cl-loop with dirlist = (directory-files
                                    tmp-dir t directory-files-no-dot-files-regexp)
                 for f in dirlist do
                 (if (file-symlink-p f)
                     (make-symbolic-link (file-truename f)
                                         (concat (file-name-as-directory directory)
                                                 (helm-basename f)))
                   (rename-file f directory))))
      (delete-directory tmp-dir t))))

(defun helm-ff-serial-rename (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and symlink files coming from
other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'rename))

(defun helm-ff-serial-rename-by-symlink (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and symlink files coming from
other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'symlink))

(defun helm-ff-serial-rename-by-copying (_candidate)
  "Serial rename all marked files to `helm-ff-default-directory'.
Rename only file of current directory, and copy files coming from
other directories.
See `helm-ff-serial-rename-1'."
  (helm-ff-serial-rename-action 'copy))

(defun helm-ff-query-replace-on-marked-1 (candidates)
  (with-helm-display-marked-candidates
    helm-marked-buffer-name
    (mapcar 'helm-basename candidates)
    (let* ((regexp (read-string "Replace regexp on filename(s): "))
           (str    (read-string (format "Replace regexp `%s' with: " regexp))))
      (cl-loop with query = "y"
               with count = 0
               for old in candidates
               for new = (concat (helm-basedir old)
                                 (replace-regexp-in-string
                                  regexp str
                                  (helm-basename old)))
               ;; If `regexp' is not matched in `old'
               ;; `replace-regexp-in-string' will
               ;; return `old' unmodified.
               unless (string= old new)
               do (progn
                    (unless (string= query "!")
                      (while (not (member
                                   (setq query
                                         (string
                                          (read-key
                                           (propertize
                                            (format
                                             "Replace `%s' by `%s' [!,y,n,q]"
                                             old new)
                                            'face 'minibuffer-prompt))))
                                   '("y" "!" "n" "q")))
                        (message "Please answer by y,n,! or q") (sit-for 1)))
                    (when (string= query "q")
                      (cl-return (message "Operation aborted")))
                    (unless (string= query "n")
                      (rename-file old new)
                      (cl-incf count)))
               finally (message "%d Files renamed" count))))
  ;; This fix the emacs bug where "Emacs-Lisp:" is sent
  ;; in minibuffer (not the echo area).
  (sit-for 0.1)
  (with-current-buffer (window-buffer (minibuffer-window))
    (delete-minibuffer-contents)))

;; The action.
(defun helm-ff-query-replace-on-marked (_candidate)
  (let ((marked (helm-marked-candidates)))
    (helm-run-after-quit #'helm-ff-query-replace-on-marked-1 marked)))

;; The command for `helm-find-files-map'.
(defun helm-ff-run-query-replace-on-marked ()
  (interactive)
  (helm-ff-query-replace-on-marked nil))

(defun helm-ff-query-replace (_candidate)
  (let ((bufs (cl-loop for f in (helm-marked-candidates)
                       collect (buffer-name (find-file-noselect f)))))
    (helm-run-after-quit #'helm-buffer-query-replace-1 nil bufs)))

(defun helm-ff-query-replace-regexp (_candidate)
  (let ((bufs (cl-loop for f in (helm-marked-candidates)
                       collect (buffer-name (find-file-noselect f)))))
    (helm-run-after-quit #'helm-buffer-query-replace-1 'regexp bufs)))

(defun helm-ff-run-query-replace ()
  (interactive)
  (helm-ff-query-replace nil))

(defun helm-ff-run-query-replace-regexp ()
  (interactive)
  (helm-ff-query-replace-regexp nil))

(defun helm-ff-toggle-auto-update (_candidate)
  (setq helm-ff-auto-update-flag (not helm-ff-auto-update-flag))
  (setq helm-ff--auto-update-state helm-ff-auto-update-flag)
  (message "[Auto expansion %s]"
           (if helm-ff-auto-update-flag "enabled" "disabled")))

(defun helm-ff-run-toggle-auto-update ()
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'toggle-auto-update '(helm-ff-toggle-auto-update . never-split))
    (helm-execute-persistent-action 'toggle-auto-update)))

(defun helm-ff-delete-char-backward ()
  "Disable helm find files auto update and delete char backward."
  (interactive)
  (setq helm-ff-auto-update-flag nil)
  (setq helm-ff--deleting-char-backward t)
  (call-interactively
   (lookup-key (current-global-map)
               (read-kbd-macro "DEL"))))

(defun helm-ff-delete-char-backward--exit-fn ()
  (setq helm-ff-auto-update-flag helm-ff--auto-update-state)
  (setq helm-ff--deleting-char-backward nil))

(defun helm-ff-run-switch-to-history ()
  "Run Switch to history action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (when (helm-file-completion-source-p)
      (helm-quit-and-execute-action 'helm-find-files-switch-to-hist))))

(defun helm-ff-run-grep ()
  "Run Grep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-grep)))

(defun helm-ff-run-pdfgrep ()
  "Run Pdfgrep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-pdfgrep)))

(defun helm-ff-run-zgrep ()
  "Run Grep action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-zgrep)))

(defun helm-ff-run-copy-file ()
  "Run Copy file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-copy)))

(defun helm-ff-run-rename-file ()
  "Run Rename file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-rename)))

(defun helm-ff-run-byte-compile-file ()
  "Run Byte compile file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-byte-compile)))

(defun helm-ff-run-load-file ()
  "Run Load file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-load-files)))

(defun helm-ff-run-eshell-command-on-file ()
  "Run eshell command on file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action
     'helm-find-files-eshell-command-on-file)))

(defun helm-ff-run-ediff-file ()
  "Run Ediff file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-ediff-files)))

(defun helm-ff-run-ediff-merge-file ()
  "Run Ediff merge file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action
     'helm-find-files-ediff-merge-files)))

(defun helm-ff-run-symlink-file ()
  "Run Symlink file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-symlink)))

(defun helm-ff-run-hardlink-file ()
  "Run Hardlink file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-files-hardlink)))

(defun helm-ff-run-delete-file ()
  "Run Delete file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-delete-marked-files)))

(defun helm-ff-run-complete-fn-at-point ()
  "Run complete file name action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action
     'helm-insert-file-name-completion-at-point)))

(defun helm-ff-run-switch-to-eshell ()
  "Run switch to eshell action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-switch-to-eshell)))

(defun helm-ff-run-switch-other-window ()
  "Run switch to other window action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'find-file-other-window)))

(defun helm-ff-run-switch-other-frame ()
  "Run switch to other frame action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'find-file-other-frame)))

(defun helm-ff-run-open-file-externally ()
  "Run open file externally command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-open-file-externally)))

(defun helm-ff-run-open-file-with-default-tool ()
  "Run open file externally command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-open-file-with-default-tool)))

(defun helm-ff-locate (candidate)
  "Locate action function for `helm-find-files'."
  (helm-locate-set-command)
  (let ((input (concat (helm-basename
                        (expand-file-name
                         candidate
                         helm-ff-default-directory))
                       ;; The locate '-b' option doesn't exists
                       ;; in everything (es).
                       (unless (and (eq system-type 'windows-nt)
                                    (string-match "^es" helm-locate-command))
                         " -b"))))
    (helm-locate-1 helm-current-prefix-arg nil 'from-ff input)))

(defun helm-ff-run-locate ()
  "Run locate action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-locate)))

(defun helm-files-insert-as-org-link (candidate)
  (insert (format "[[%s][]]" candidate))
  (goto-char (- (point) 2)))

(defun helm-ff-run-insert-org-link ()
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-files-insert-as-org-link)))

(defun helm-ff-run-find-file-as-root ()
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-find-file-as-root)))

(defun helm-ff-run-gnus-attach-files ()
  "Run gnus attach files command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-gnus-attach-files)))

(defun helm-ff-run-etags ()
  "Run Etags command action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-etags-select)))

(defvar lpr-printer-switch)
(defun helm-ff-print (_candidate)
  "Print marked files.

You may to set in order
variables `lpr-command',`lpr-switches' and/or `printer-name',
but with no settings helm should detect your printer(s) and
print with the default `lpr' settings.

NOTE: DO NOT set the \"-P\" flag in `lpr-switches', if you really
have to modify this, do it in `lpr-printer-switch'.
  
Same as `dired-do-print' but for helm."
  (require 'lpr)
  (when (or helm-current-prefix-arg
            (not helm-ff-printer-list))
    (setq helm-ff-printer-list
          (helm-ff-find-printers)))
  (let* ((file-list (helm-marked-candidates :with-wildcard t))
         (len (length file-list))
         (printer-name (if helm-ff-printer-list
                           (helm-comp-read
                            "Printer: " helm-ff-printer-list)
                         printer-name))
         (lpr-switches
	  (if (and (stringp printer-name)
		   (string< "" printer-name))
	      (cons (concat lpr-printer-switch printer-name)
		    lpr-switches)
              lpr-switches))
         (command (helm-read-string
                   (format "Print *%s File(s):\n%s with: "
                           len
                           (mapconcat
                            (lambda (f) (format "- %s\n" f))
                            file-list ""))
                   (when (and lpr-command lpr-switches)
                     (mapconcat 'identity
                                (cons lpr-command
                                      (if (stringp lpr-switches)
                                          (list lpr-switches)
                                          lpr-switches))
                                " "))))
         (file-args (mapconcat #'(lambda (x)
                                   (format "'%s'" x))
                               file-list " "))
         (cmd-line (concat command " " file-args)))
    (if command
        (start-process-shell-command "helm-print" nil cmd-line)
      (error "Error: Please verify your printer settings in Emacs."))))

(defun helm-ff-run-print-file ()
  "Run Print file action from `helm-source-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-print)))

(defun helm-ff-checksum (file)
  "Calculate the checksum of FILE.
The checksum is copied to kill-ring."
  (let ((algo (intern (helm-comp-read
                       "Algorithm: "
                       '(md5 sha1 sha224 sha256 sha384 sha512)))))
    (kill-new (with-temp-buffer
                (insert-file-contents-literally file)
                (secure-hash algo (current-buffer))))
    (message "Checksum copied to kill-ring.")))

(defun helm-ff-toggle-basename (_candidate)
  (with-helm-buffer
    (setq helm-ff-transformer-show-only-basename
          (not helm-ff-transformer-show-only-basename))
    (let* ((cand   (helm-get-selection nil t))
           (target (if helm-ff-transformer-show-only-basename
                       (helm-basename cand) cand)))
      (helm-force-update (regexp-quote target)))))

(defun helm-ff-run-toggle-basename ()
  (interactive)
  (with-helm-alive-p
    (unless (helm-empty-source-p)
      (helm-ff-toggle-basename nil))))

(cl-defun helm-reduce-file-name (fname level &key unix-close expand)
  "Reduce FNAME by LEVEL from end or beginning depending LEVEL value.
If LEVEL is positive reduce from end else from beginning.
If UNIX-CLOSE is non--nil close filename with /.
If EXPAND is non--nil expand-file-name."
  (let* ((exp-fname  (expand-file-name fname))
         (fname-list (split-string (if (or (string= fname "~/") expand)
                                       exp-fname fname) "/" t))
         (len        (length fname-list))
         (pop-list   (if (< level 0)
                         (cl-subseq fname-list (* level -1))
                       (cl-subseq fname-list 0 (- len level))))
         (result     (mapconcat 'identity pop-list "/"))
         (empty      (string= result "")))
    (when unix-close (setq result (concat result "/")))
    (if (string-match "^~" result)
        (if (string= result "~/") "~/" result)
      (if (< level 0)
          (if empty "../" (concat "../" result))
        (cond ((eq system-type 'windows-nt)
               (if empty (expand-file-name "/") ; Expand to "/" or "c:/".
                 result))
              (empty "/")
              (t
               (concat "/" result)))))))

(defvar helm-find-files--level-tree nil)
(defvar helm-find-files--level-tree-iterator nil)
(defun helm-find-files-up-one-level (arg)
  "Go up one level like unix command `cd ..'.
If prefix numeric arg is given go ARG level up."
  (interactive "p")
  (with-helm-alive-p
    (when (and (helm-file-completion-source-p)
               (not (helm-ff-invalid-tramp-name-p)))
      (with-helm-window
        (when helm-follow-mode
          (helm-follow-mode -1) (message nil)))
      ;; When going up one level we want to be at the line
      ;; corresponding to actual directory, so store this info
      ;; in `helm-ff-last-expanded'.
      (let ((cur-cand (helm-get-selection))
            (new-pattern (helm-reduce-file-name
                          helm-pattern arg :unix-close t :expand t)))
        (cond ((file-directory-p helm-pattern)
               (setq helm-ff-last-expanded helm-ff-default-directory))
              ((file-exists-p helm-pattern)
               (setq helm-ff-last-expanded helm-pattern))
              ((and cur-cand (file-exists-p cur-cand))
               (setq helm-ff-last-expanded cur-cand)))
        (unless helm-find-files--level-tree
          (setq helm-find-files--level-tree
                (cons helm-ff-default-directory
                      helm-find-files--level-tree)))
        (setq helm-find-files--level-tree-iterator nil)
        (push new-pattern helm-find-files--level-tree)
        (helm-set-pattern new-pattern helm-suspend-update-flag)
        (with-helm-after-update-hook (helm-ff-retrieve-last-expanded))))))

(defun helm-find-files-down-last-level ()
  "Retrieve previous paths reached by `C-l' in helm-find-files."
  (interactive)
  (with-helm-alive-p
    (when (and (helm-file-completion-source-p)
               (not (helm-ff-invalid-tramp-name-p)))
      (unless helm-find-files--level-tree-iterator 
        (setq helm-find-files--level-tree-iterator
              (helm-iter-list (cdr helm-find-files--level-tree))))
      (setq helm-find-files--level-tree nil)
      (helm-aif (helm-iter-next helm-find-files--level-tree-iterator)
          (helm-set-pattern it)
        (ignore)
        (setq helm-find-files--level-tree-iterator nil)))))

(defun helm-find-files--reset-level-tree ()
  (setq helm-find-files--level-tree-iterator nil
        helm-find-files--level-tree nil))

(add-hook 'helm-cleanup-hook 'helm-find-files--reset-level-tree)
(add-hook 'post-self-insert-hook 'helm-find-files--reset-level-tree)
(add-hook 'helm-after-persistent-action-hook 'helm-find-files--reset-level-tree)

(defun helm-ff-retrieve-last-expanded ()
  "Move overlay to last visited directory `helm-ff-last-expanded'.
This happen after using `helm-find-files-up-one-level',
or hitting C-j on \"..\"."
  (when helm-ff-last-expanded
    (let ((presel (if helm-ff-transformer-show-only-basename
                      (helm-basename
                       (directory-file-name helm-ff-last-expanded))
                    (directory-file-name helm-ff-last-expanded))))
      (with-helm-window
        (when (re-search-forward (concat "^" (regexp-quote presel) "$") nil t)
          (forward-line 0)
          (helm-mark-current-line)))
      (setq helm-ff-last-expanded nil))))

(defun helm-ff-move-to-first-real-candidate ()
  "When candidate is an incomplete file name move to first real candidate."
  (helm-aif (and (helm-file-completion-source-p)
                 (not (helm-empty-source-p))
                 (not (string-match
                       "\\`[Dd]ired"
                       (assoc-default 'name (helm-get-current-source))))
                 helm-ff--move-to-first-real-candidate
                 (helm-get-selection))
      (unless (or (not (stringp it))
                  (and (string-match helm-tramp-file-name-regexp it)
                       (not (file-remote-p it nil t)))
                  (file-exists-p it))
        (helm-next-line))))
(add-hook 'helm-after-update-hook 'helm-ff-move-to-first-real-candidate)

;;; Auto-update - helm-find-files auto expansion of directories.
;;
;;
(defun helm-ff-update-when-only-one-matched ()
  "Expand to directory when sole completion.
When only one candidate is remaining and it is a directory,
expand to this directory.
This happen only when `helm-ff-auto-update-flag' is non--nil
or when `helm-pattern' is equal to \"~/\"."
  (when (or (and helm-ff-auto-update-flag
                 (null helm-ff--deleting-char-backward)
                 (helm-file-completion-source-p)
                 (not (get-buffer-window helm-action-buffer 'visible))
                 ;; Issue #295
                 ;; File predicates are returning t
                 ;; with paths like //home/foo.
                 ;; So check it is not the case by regexp
                 ;; to allow user to do C-a / to start e.g
                 ;; entering a tramp method e.g /sudo::.
                 (not (string-match "\\`//" helm-pattern))
                 (not (helm-ff-invalid-tramp-name-p))
                 (not (eq last-command 'helm-yank-text-at-point)))
            ;; Fix issue #542.
            (string= helm-pattern "~/"))
    (let* ((history-p   (string= (assoc-default
                                  'name (helm-get-current-source))
                                 "Read File Name History"))
           (pat         (if (string-match helm-tramp-file-name-regexp
                                          helm-pattern)
                            (helm-create-tramp-name helm-pattern)
                          helm-pattern))
           (completed-p (string= (file-name-as-directory
                                  (expand-file-name
                                   (substitute-in-file-name pat)))
                                 helm-ff-default-directory))
           (candnum (helm-get-candidate-number)))
      (when (and (or
                  ;; Only one candidate remaining
                  ;; and at least 2 char in basename.
                  (and (<= candnum 2)
                       (>= (string-width (helm-basename helm-pattern)) 2))
                  ;; Already completed.
                  completed-p)
                 (not history-p)) ; Don't try to auto complete in history.
        (with-helm-window
          (let ((cur-cand (prog2
                              (unless (or completed-p (file-exists-p pat))
                                ;; Only one non--existing candidate
                                ;; and one directory candidate, move to it.
                                (helm-next-line))
                              (helm-get-selection))))
            (when (and (stringp cur-cand)
                       (file-accessible-directory-p cur-cand))
              (if (and (not (helm-dir-is-dot cur-cand))         ; [1]
                       ;; Maybe we are here because completed-p is true
                       ;; but check this again to be sure. (Windows fix)
                       (<= candnum 2)) ; [2]
                  ;; If after going to next line the candidate
                  ;; is not one of "." or ".." [1]
                  ;; and only one candidate is remaining [2],
                  ;; assume candidate is a new directory to expand, and do it.
                  (helm-set-pattern (file-name-as-directory cur-cand))
                ;; The candidate is one of "." or ".."
                ;; that mean we have entered the last letter of the directory name
                ;; in prompt, so expansion is already done, just add the "/" at end
                ;; of name unless helm-pattern ends with "."
                ;; (i.e we are writing something starting with ".")
                (unless (string-match "\\`.*[.]\\{1\\}\\'" helm-pattern)
                  (helm-set-pattern
                   ;; Need to expand-file-name to avoid e.g /ssh:host:./ in prompt.
                   (expand-file-name (file-name-as-directory helm-pattern)))))
              (helm-check-minibuffer-input))))))))

(defun helm-ff-auto-expand-to-home-or-root ()
  "Allow expanding to home/user directory or root or text yanked after pattern."
  (when (and (helm-file-completion-source-p)
             (string-match
              "/?\\$.*/\\|/\\./\\|/\\.\\./\\|/~.*/\\|//\\|\\(/[[:alpha:]]:/\\|\\s\\+\\)"
              helm-pattern)
             (with-current-buffer (window-buffer (minibuffer-window)) (eolp))
             (not (string-match helm-ff-url-regexp helm-pattern)))
    (let* ((match (match-string 0 helm-pattern))
           (input (cond ((string= match "/./")
                         (expand-file-name default-directory))
                        ((string= helm-pattern "/../") "/")
                        ((string-match-p "\\`/\\$" match)
                         (let ((sub (substitute-in-file-name match)))
                           (if (file-directory-p sub)
                               sub (replace-regexp-in-string "/\\'" "" sub))))
                        (t (expand-file-name
                            (helm-substitute-in-filename helm-pattern)
                            ;; [Windows] On UNC paths "/" expand to current machine,
                            ;; so use the root of current Drive. (i.e "C:/")
                            (and (memq system-type '(windows-nt ms-dos))
                                 (getenv "SystemDrive")) ; nil on Unix.
                            )))))
      (if (file-directory-p input)
          (setq helm-ff-default-directory
                (setq input (file-name-as-directory input)))
        (setq helm-ff-default-directory (file-name-as-directory
                                         (file-name-directory input))))
      (with-helm-window
        (helm-set-pattern input)
        (helm-check-minibuffer-input)))))

(defun helm-substitute-in-filename (fname)
  "Substitute all parts of FNAME from start up to \"~/\" or \"/\".
On windows system substitute from start up to \"/[[:lower:]]:/\".
This function is needed for `helm-ff-auto-expand-to-home-or-root'
and should be used carefully elsewhere, or not at all, using
`substitute-in-file-name' instead."
  (if (and ffap-url-regexp
           (string-match-p ffap-url-regexp fname))
      fname
      (with-temp-buffer
        (insert fname)
        (goto-char (point-min))
        (skip-chars-forward "/") ;; Avoid infloop in UNC paths Issue #424
        (if (re-search-forward "~.*/?\\|//\\|/[[:alpha:]]:/" nil t)
            (let ((match (match-string 0)))
              (goto-char (if (or (string= match "//")
                                 (string-match-p "/[[:alpha:]]:/" match))
                             (1+ (match-beginning 0))
                             (match-beginning 0)))
              (buffer-substring-no-properties (point) (point-at-eol)))
            fname))))

(add-hook 'helm-after-update-hook 'helm-ff-update-when-only-one-matched)
(add-hook 'helm-after-update-hook 'helm-ff-auto-expand-to-home-or-root)

(defun helm-point-file-in-dired (file)
  "Put point on filename FILE in dired buffer."
  (unless (and ffap-url-regexp
               (string-match-p ffap-url-regexp file))
    (let ((target (expand-file-name (helm-substitute-in-filename file))))
      (dired (file-name-directory target))
      (dired-goto-file target))))

(defun helm-create-tramp-name (fname)
  "Build filename for `helm-pattern' like /su:: or /sudo::."
  (apply #'tramp-make-tramp-file-name
         (cl-loop with v = (tramp-dissect-file-name fname)
               for i across v collect i)))

(cl-defun helm-ff-tramp-hostnames (&optional (pattern helm-pattern))
  "Get a list of hosts for tramp method found in `helm-pattern'.
Argument PATTERN default to `helm-pattern', it is here only for debugging
purpose."
  (when (string-match helm-tramp-file-name-regexp pattern)
    (let ((method      (match-string 1 pattern))
          (tn          (match-string 0 pattern))
          (all-methods (mapcar 'car tramp-methods)))
      (helm-fast-remove-dups
       (cl-loop for (f . h) in (tramp-get-completion-function method)
             append (cl-loop for e in (funcall f (car h))
                          for host = (and (consp e) (cadr e))
                          when (and host (not (member host all-methods)))
                          collect (concat tn host)))
       :test 'equal))))

(defun helm-ff-before-action-hook-fn ()
  "Exit helm when user try to execute action on an invalid tramp fname."
  (let ((cand (helm-get-selection)))
    (when (and (helm-file-completion-source-p)
               (stringp cand)
               (helm-ff-invalid-tramp-name-p cand) ; Check candidate.
               (helm-ff-invalid-tramp-name-p)) ; check helm-pattern.
      (error "Error: Unknown file or directory `%s'" cand))))
(add-hook 'helm-before-action-hook 'helm-ff-before-action-hook-fn)

(cl-defun helm-ff-invalid-tramp-name-p (&optional (pattern helm-pattern))
  "Return non--nil when PATTERN is an invalid tramp filename."
  (string= (helm-ff-set-pattern pattern)
           "Invalid tramp file name"))

(defun helm-ff-set-pattern (pattern)
  "Handle tramp filenames in `helm-pattern'."
  (let ((methods (mapcar 'car tramp-methods))
        (reg "\\`/\\([^[/:]+\\|[^/]+]\\):.*:")
        cur-method tramp-name)
    ;; In some rare cases tramp can return a nil input,
    ;; so be sure pattern is a string for safety (Issue #476).
    (unless pattern (setq pattern ""))
    (cond ((string-match helm-ff-url-regexp pattern) pattern)
          ((string-match "\\`\\$" pattern)
           (substitute-in-file-name pattern))
          ((string= pattern "") "")
          ((string-match "\\`[.]\\{1,2\\}/\\'" pattern)
           (expand-file-name pattern))
          ((string-match ".*\\(~?/?[.]\\{1\\}/\\)\\'" pattern)
           (expand-file-name default-directory))
          ((string-match ".*\\(~//\\|//\\)\\'" pattern)
           (expand-file-name "/")) ; Expand to "/" or "c:/"
          ((string-match "\\`\\(~/\\|.*/~/\\)\\'" pattern)
           (expand-file-name "~/"))
          ;; Match "/method:maybe_hostname:~"
          ((and (string-match (concat reg "~") pattern)
                (setq cur-method (match-string 1 pattern))
                (member cur-method methods))
           (setq tramp-name (expand-file-name
                             (helm-create-tramp-name
                              (match-string 0 pattern))))
           (replace-match tramp-name nil t pattern))
          ;; Match "/method:maybe_hostname:"
          ((and (string-match reg pattern)
                (setq cur-method (match-string 1 pattern))
                (member cur-method methods))
           (setq tramp-name (helm-create-tramp-name
                             (match-string 0 pattern)))
           (replace-match tramp-name nil t pattern))
          ;; Match "/hostname:"
          ((and (string-match  helm-tramp-file-name-regexp pattern)
                (setq cur-method (match-string 1 pattern))
                (and cur-method (not (member cur-method methods))))
           (setq tramp-name (helm-create-tramp-name
                             (match-string 0 pattern)))
           (replace-match tramp-name nil t pattern))
          ;; Match "/method:" in this case don't try to connect.
          ((and (not (string-match reg pattern))
                (string-match helm-tramp-file-name-regexp pattern)
                (member (match-string 1 pattern) methods))
           "Invalid tramp file name")   ; Write in helm-buffer.
          ;; PATTERN is a directory, end it with "/".
          ;; This will make PATTERN not ending yet with "/"
          ;; candidate for `helm-ff-default-directory',
          ;; allowing `helm-ff-retrieve-last-expanded' to retrieve it
          ;; when descending level.
          ;; However, we don't add automatically the "/" when
          ;; `helm-ff-auto-update-flag' is enabled to avoid quick expansion.
          ((and (file-accessible-directory-p pattern)
                helm-ff-auto-update-flag)
           (file-name-as-directory (expand-file-name pattern)))
          ;; Return PATTERN unchanged.
          (t pattern))))

(defun helm-find-files-get-candidates (&optional require-match)
  "Create candidate list for `helm-source-find-files'."
  (let* ((path          (helm-ff-set-pattern helm-pattern))
         (dir-p         (file-accessible-directory-p path))
         basedir
         invalid-basedir
         non-essential
         (tramp-verbose helm-tramp-verbose)) ; No tramp message when 0.
    (set-text-properties 0 (length path) nil path)
    ;; Issue #118 allow creation of newdir+newfile.
    (unless (or
             ;; A tramp file name not completed.
             (string= path "Invalid tramp file name")
             ;; An empty pattern
             (string= path "")
             ;; Check if base directory of PATH is valid.
             (helm-aif (file-name-directory path)
                 ;; If PATH is a valid directory IT=PATH,
                 ;; else IT=basedir of PATH.
                 (file-directory-p it)))
      ;; BASEDIR is invalid, that's mean user is starting
      ;; to write a non--existing path in minibuffer
      ;; probably to create a 'new_dir' or a 'new_dir+new_file'.
      (setq invalid-basedir t))
    ;; Don't set now `helm-pattern' if `path' == "Invalid tramp file name"
    ;; like that the actual value (e.g /ssh:) is passed to
    ;; `helm-ff-tramp-hostnames'.
    (unless (or (string= path "Invalid tramp file name")
                invalid-basedir)      ; Leave  helm-pattern unchanged.
      (setq helm-ff-auto-update-flag  ; [1]
            ;; Unless auto update is disabled at startup or
            ;; interactively, start auto updating only at third char.
            (unless (or (null helm-ff-auto-update-initial-value)
                        (null helm-ff--auto-update-state)
                        ;; But don't enable auto update when
                        ;; deleting backward.
                        helm-ff--deleting-char-backward)
              (or (>= (length (helm-basename path)) 3) dir-p)))
      (setq helm-pattern (helm-ff--transform-pattern-for-completion path))
      ;; This have to be set after [1] to allow deleting char backward.
      (setq basedir (expand-file-name
                     (if (and dir-p helm-ff-auto-update-flag)
                         ;; Add the final "/" to path
                         ;; when `helm-ff-auto-update-flag' is enabled.
                         (file-name-as-directory path)
                         (if (string= path "") "/"
                             (file-name-directory path)))))
      (setq helm-ff-default-directory
            (if (string= helm-pattern "")
                (expand-file-name "/")  ; Expand to "/" or "c:/"
                ;; If path is an url *default-directory have to be nil.
                (unless (or (string-match helm-ff-url-regexp path)
                            (and ffap-url-regexp
                                 (string-match ffap-url-regexp path)))
                  basedir))))
    (cond ((string= path "Invalid tramp file name")
           (or (helm-ff-tramp-hostnames) ; Hostnames completion.
               (prog2
                   ;; `helm-pattern' have not been modified yet.
                   ;; Set it here to the value of `path' that should be now
                   ;; "Invalid tramp file name" and set the candidates list
                   ;; to ("Invalid tramp file name") to make `helm-pattern'
                   ;; match single candidate "Invalid tramp file name".
                   (setq helm-pattern path)
                   ;; "Invalid tramp file name" is now printed
                   ;; in `helm-buffer'.
                   (list path))))
          ((or (and (file-regular-p path)
                    (eq last-repeatable-command 'helm-execute-persistent-action))
               ;; `ffap-url-regexp' don't match until url is complete.
               (string-match helm-ff-url-regexp path)
               invalid-basedir
               (and (not (file-exists-p path)) (string-match "/$" path))
               (and ffap-url-regexp (string-match ffap-url-regexp path)))
           (list path))
          ((string= path "") (helm-ff-directory-files "/" t))
          ;; Check here if directory is accessible (not working on Windows).
          ((and (file-directory-p path) (not (file-readable-p path)))
           (list (format "file-error: Opening directory permission denied `%s'" path)))
          ;; A fast expansion of PATH is made only if `helm-ff-auto-update-flag'
          ;; is enabled.
          ((and dir-p helm-ff-auto-update-flag)
           (helm-ff-directory-files path t))
          (t (append (unless (or require-match
                                 ;; When `helm-ff-auto-update-flag' has been
                                 ;; disabled, whe don't want PATH to be added on top
                                 ;; if it is a directory.
                                 dir-p)
                       (list path))
                     (helm-ff-directory-files basedir t))))))

(defun helm-ff-directory-files (directory &optional full)
  "List contents of DIRECTORY.
Argument FULL mean absolute path.
It is same as `directory-files' but always returns the
dotted filename '.' and '..' even on root directories in Windows
systems."
  (setq directory (file-name-as-directory
                   (expand-file-name directory)))
  (let* (file-error
         (ls   (condition-case err
                   (directory-files
                    directory full directory-files-no-dot-files-regexp)
                 ;; Handle file-error from here for Windows
                 ;; because predicates like `file-readable-p' and friends
                 ;; seem broken on emacs for Windows systems (always returns t).
                 ;; This should never be called on GNU/Linux/Unix
                 ;; as the error is properly intercepted in
                 ;; `helm-find-files-get-candidates' by `file-readable-p'.
                 (file-error
                  (prog1
                      (list (format "%s:%s"
                                    (car err)
                                    (mapconcat 'identity (cdr err) " ")))
                    (setq file-error t)))))
        (dot  (concat directory "."))
        (dot2 (concat directory "..")))
    (append (and (not file-error) (list dot dot2)) ls)))

(defun helm-ff-handle-backslash (fname)
  ;; Allow creation of filenames containing a backslash.
  (cl-loop with bad = '((92 . ""))
        for i across fname
        for isbad = (assq i bad)
        if isbad concat (cdr isbad)
        else concat (string i)))

(defun helm-ff-smart-completion-p ()
  (and helm-ff-smart-completion
       (not (memq helm-mp-matching-method '(multi1 multi3p)))))

(defun helm-ff--transform-pattern-for-completion (pattern)
  "Maybe return PATTERN with it's basename modified as a regexp.
This happen only when `helm-ff-smart-completion' is enabled.
This provide a similar behavior as `ido-enable-flex-matching'.
See also `helm--mapconcat-pattern'.
If PATTERN is an url returns it unmodified.
When PATTERN contain a space fallback to match-plugin.
If basename contain one or more space fallback to match-plugin.
If PATTERN is a valid directory name,return PATTERN unchanged."
  ;; handle bad filenames containing a backslash.
  (setq pattern (helm-ff-handle-backslash pattern))
  (let ((bn      (helm-basename pattern))
        (bd      (or (helm-basedir pattern) ""))
        (dir-p   (file-directory-p pattern))
        (tramp-p (cl-loop for (m . f) in tramp-methods
                       thereis (string-match m pattern))))
    ;; Always regexp-quote base directory name to handle
    ;; crap dirnames such e.g bookmark+
    (cond
      ((or (and dir-p tramp-p (string-match ":\\'" pattern))
           (string= pattern "")
           (and dir-p (<= (length bn) 2))
           ;; Fix Issue #541 when BD have a subdir similar
           ;; to BN, don't switch to match plugin
           ;; which will match both.
           (and dir-p (string-match (regexp-quote bn) bd)))
       ;; Use full PATTERN on e.g "/ssh:host:".
       (regexp-quote pattern))
      ;; Prefixing BN with a space call match-plugin completion.
      ;; This allow showing all files/dirs matching BN (Issue #518).
      ;; FIXME: some match-plugin methods may not work here.
      (dir-p (concat (regexp-quote bd) " " (regexp-quote bn)))
      ((or (not (helm-ff-smart-completion-p))
           (string-match "\\s-" bn))    ; Fall back to match-plugin.
       (concat (regexp-quote bd) bn))
      ((or (string-match "[*][.]?.*" bn) ; Allow entering wilcard.
           (string-match "/$" pattern)     ; Allow mkdir.
           (string-match helm-ff-url-regexp pattern)
           (and (string= helm-ff-default-directory "/") tramp-p))
       ;; Don't treat wildcards ("*") as regexp char.
       ;; (e.g ./foo/*.el => ./foo/[*].el)
       (concat (regexp-quote bd)
               (replace-regexp-in-string "[*]" "[*]" bn)))
      (t
       (setq bn (if (>= (length bn) 2) ; wait 2nd char before concating.
                    (helm--mapconcat-pattern bn)
                  (concat ".*" (regexp-quote bn))))
       (concat (regexp-quote bd) bn)))))

(defun helm-dir-is-dot (dir)
  (string-match "\\(?:/\\|\\`\\)\\.\\{1,2\\}\\'" dir))

(defun helm-ff-save-history ()
  "Store the last value of `helm-ff-default-directory' in `helm-ff-history'.
Note that only existing directories are saved here."
  (when (and helm-ff-default-directory
             (helm-file-completion-source-p)
             (file-directory-p helm-ff-default-directory))
    (set-text-properties 0 (length helm-ff-default-directory)
                         nil helm-ff-default-directory)
    (push helm-ff-default-directory helm-ff-history)))
(add-hook 'helm-cleanup-hook 'helm-ff-save-history)

(defun helm-files-save-file-name-history (&optional force)
  "Save selected file to `file-name-history'."
  (let ((src-name (assoc-default 'name (helm-get-current-source))))
    (when (or force (helm-file-completion-source-p)
              (member src-name helm-files-save-history-extra-sources))
      (let ((mkd (helm-marked-candidates))
            (history-delete-duplicates t))
        (cl-loop for sel in mkd
              when (and sel
                        (stringp sel)
                        (file-exists-p sel)
                        (not (file-directory-p sel)))
              do
              ;; we use `abbreviate-file-name' here because
              ;; other parts of Emacs seems to,
              ;; and we don't want to introduce duplicates.
              (add-to-history 'file-name-history
                              (abbreviate-file-name sel)))))))
(add-hook 'helm-exit-minibuffer-hook 'helm-files-save-file-name-history)

(defun helm-ff-valid-symlink-p (file)
  (helm-aif (condition-case-unless-debug nil
                ;; `file-truename' send error
                ;; on cyclic symlinks (Issue #692).
                (file-truename file)
              (error nil))
      (file-exists-p it)))

(defun helm-get-default-mode-for-file (filename)
  "Return the default mode to open FILENAME."
  (let ((mode (cl-loop for (r . m) in auto-mode-alist
                    thereis (and (string-match r filename) m))))
    (or (and (symbolp mode) mode) "Fundamental")))

(defun helm-ff-properties (candidate)
  "Show file properties of CANDIDATE in a tooltip or message."
  (let* ((all                (helm-file-attributes candidate))
         (dired-line         (helm-file-attributes
                              candidate :dired t :human-size t))
         (type               (cl-getf all :type))
         (mode-type          (cl-getf all :mode-type))
         (owner              (cl-getf all :uid))
         (owner-right        (cl-getf all :user t))
         (group              (cl-getf all :gid))
         (group-right        (cl-getf all :group))
         (other-right        (cl-getf all :other))
         (size               (helm-file-human-size (cl-getf all :size)))
         (modif              (cl-getf all :modif-time))
         (access             (cl-getf all :access-time))
         (ext                (helm-get-default-program-for-file candidate))
         (tooltip-hide-delay (or helm-tooltip-hide-delay tooltip-hide-delay)))
    (if (and (window-system) tooltip-mode)
        (tooltip-show
         (concat
          (helm-basename candidate) "\n"
          dired-line "\n"
          (format "Mode: %s\n" (helm-get-default-mode-for-file candidate))
          (format "Ext prog: %s\n" (or (and ext (replace-regexp-in-string
                                                 " %s" "" ext))
                                       "Not defined"))
          (format "Type: %s: %s\n" type mode-type)
          (when (string= type "symlink")
            (format "True name: '%s'\n"
                    (cond ((string-match "^\.#" (helm-basename candidate))
                           "Autosave symlink")
                          ((helm-ff-valid-symlink-p candidate)
                           (file-truename candidate))
                          (t "Invalid Symlink"))))
          (format "Owner: %s: %s\n" owner owner-right)
          (format "Group: %s: %s\n" group group-right)
          (format "Others: %s\n" other-right)
          (format "Size: %s\n" size)
          (format "Modified: %s\n" modif)
          (format "Accessed: %s\n" access)))
      (message dired-line) (sit-for 5))))

(defun helm-ff-properties-persistent ()
  "Show properties without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'properties-action '(helm-ff-properties . never-split))
    (helm-execute-persistent-action 'properties-action)))

(defun helm-ff-persistent-delete ()
  "Delete current candidate without quitting."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'quick-delete '(helm-ff-quick-delete . never-split))
    (helm-execute-persistent-action 'quick-delete)))

(defun helm-ff-dot-file-p (file)
  "Check if FILE is `.' or `..'."
  (member (helm-basename file) '("." "..")))

(defun helm-ff-quick-delete (_candidate)
  "Delete file CANDIDATE without quitting."
  (let ((marked (helm-marked-candidates)))
    (unwind-protect
         (save-selected-window
           (cl-loop for c in marked do
                    (progn (helm-preselect (if (and helm-ff-transformer-show-only-basename
                                                    (not (helm-ff-dot-file-p c)))
                                               (helm-basename c) c))
                           (when (y-or-n-p (format "Really Delete file `%s'? " c))
                             (helm-delete-file c helm-ff-signal-error-on-dot-files
                                               'synchro)
                             (helm-delete-current-selection)
                             (message nil)))))
      (with-helm-buffer
        (setq helm-marked-candidates nil
              helm-visible-mark-overlays nil))
      (helm-force-update
       (let ((presel (helm-get-selection)))
         (regexp-quote (if (and helm-ff-transformer-show-only-basename
                                (not (helm-ff-dot-file-p presel)))
                           (helm-basename presel) presel)))))))

(defun helm-ff-kill-buffer-fname (candidate)
  (let ((buf (get-file-buffer candidate)))
    (if buf
        (progn
          (kill-buffer buf) (message "Buffer `%s' killed" buf))
      (message "No buffer to kill"))))

(defun helm-ff-kill-or-find-buffer-fname (candidate)
  "Find file CANDIDATE or kill it's buffer if it is visible.
Never kill `helm-current-buffer'.
Never kill buffer modified.
This is called normally on third hit of \
\\<helm-map>\\[helm-execute-persistent-action]
in `helm-find-files-persistent-action'."
  (let* ((buf      (get-file-buffer candidate))
         (buf-name (buffer-name buf))
         (win (get-buffer-window buf))
         (helm--reading-passwd-or-string t))
    (if (and buf win
             (not (eq buf (get-buffer helm-current-buffer)))
             (not (buffer-modified-p buf)))
        (progn
          (kill-buffer buf)
          (set-window-buffer win helm-current-buffer)
          (message "Buffer `%s' killed" buf-name))
      (find-file candidate))))

(defun helm-ff-run-kill-buffer-persistent ()
  "Execute `helm-ff-kill-buffer-fname' whitout quitting."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'kill-buffer-fname 'helm-ff-kill-buffer-fname)
    (helm-execute-persistent-action 'kill-buffer-fname)))

(defun helm-ff-prefix-filename (fname &optional file-or-symlinkp new-file)
  "Return filename FNAME maybe prefixed with [?] or [@].
If FILE-OR-SYMLINKP is non--nil this mean we assume FNAME is an
existing filename or valid symlink and there is no need to test it.
NEW-FILE when non--nil mean FNAME is a non existing file and
return FNAME prefixed with [?]."
  (let* ((prefix-new (propertize
                      " " 'display
                      (propertize "[?]" 'face 'helm-ff-prefix)))
         (prefix-url (propertize
                      " " 'display
                      (propertize "[@]" 'face 'helm-ff-prefix))))
    (cond ((or file-or-symlinkp (file-exists-p fname)) fname)
          ((or (string-match helm-ff-url-regexp fname)
               (and ffap-url-regexp (string-match ffap-url-regexp fname)))
           (concat prefix-url " " fname))
          ((or new-file (not (file-exists-p fname)))
           (concat prefix-new " " fname)))))

(defun helm-ff-score-candidate-for-pattern (str pattern)
  (if (member str '("." ".."))
      200
      (helm-score-candidate-for-pattern str pattern)))

(defun helm-ff-sort-candidates (candidates _source)
  "Sort function for `helm-source-find-files'.
Return candidates prefixed with basename of `helm-input' first."
  (if (or (and (file-directory-p helm-input)
               (string-match "/\\'" helm-input))
          (string-match "\\`\\$" helm-input)
          (null candidates))
      candidates
      (let* ((c1        (car candidates))
             (cand1real (if (consp c1) (cdr c1) c1))
             (cand1     (unless (file-exists-p cand1real) c1))
             (rest-cand (if cand1 (cdr candidates) candidates))
             (memo-src  (make-hash-table :test 'equal))
             (all (sort rest-cand
                        #'(lambda (s1 s2)
                            (let* ((score (lambda (str)
                                            (helm-ff-score-candidate-for-pattern
                                             str (helm-basename helm-input))))
                                   (bn1 (helm-basename (if (consp s1) (cdr s1) s1)))
                                   (bn2 (helm-basename (if (consp s2) (cdr s2) s2)))
                                   (sc1 (or (gethash bn1 memo-src)
                                            (puthash bn1 (funcall score bn1) memo-src)))
                                   (sc2 (or (gethash bn2 memo-src)
                                            (puthash bn2 (funcall score bn2) memo-src))))
                              (cond ((= sc1 sc2)
                                     (< (string-width bn1)
                                        (string-width bn2)))
                                    ((> sc1 sc2))))))))
        (if cand1 (cons cand1 all) all))))

(defun helm-ff-filter-candidate-one-by-one (file)
  "`filter-one-by-one' Transformer function for `helm-source-find-files'."
  ;; Handle boring files
  (unless (and helm-ff-skip-boring-files
               (cl-loop for r in helm-boring-file-regexp-list
                        ;; Prevent user doing silly thing like
                        ;; adding the dotted files to boring regexps (#924).
                        thereis (and (not (string-match "\\.$" file))
                                     (string-match r file))))
    ;; Handle tramp files.
    (if (and (string-match helm-tramp-file-name-regexp helm-pattern)
             helm-ff-tramp-not-fancy)
        (if helm-ff-transformer-show-only-basename
            (if (helm-dir-is-dot file)
                file
              (cons (or (helm-ff-get-host-from-tramp-invalid-fname file)
                        (helm-basename file))
                    file))
          file)
      ;; Now highlight.
      (let* ((disp (if (and helm-ff-transformer-show-only-basename
                            (not (helm-dir-is-dot file))
                            (not (and ffap-url-regexp
                                      (string-match ffap-url-regexp file)))
                            (not (string-match helm-ff-url-regexp file)))
                       (or (helm-ff-get-host-from-tramp-invalid-fname file)
                           (helm-basename file)) file))
             (attr (file-attributes file))
             (type (car attr)))

        (cond ((string-match "file-error" file) file)
              ( ;; A not already saved file.
               (and (stringp type)
                    (not (helm-ff-valid-symlink-p file))
                    (not (string-match "^\.#" (helm-basename file))))
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-invalid-symlink) t)
                     file))
              ;; A symlink.
              ((stringp type)
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-symlink) t)
                     file))
              ;; A dotted directory.
              ((and (eq t type) (helm-ff-dot-file-p file))
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-dotted-directory) t)
                     file))
              ;; A directory.
              ((eq t type)
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-directory) t)
                     file))
              ;; An executable file.
              ((and attr (string-match "x" (nth 8 attr)))
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-executable) t)
                     file))
              ;; A file.
              ((and attr (null type))
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-file) t)
                     file))
              ;; A non--existing file.
              (t
               (cons (helm-ff-prefix-filename
                      (propertize disp 'face 'helm-ff-file) nil 'new-file)
                     file)))))))

(defun helm-find-files-action-transformer (actions candidate)
  "Action transformer for `helm-source-find-files'."
  (let ((str-at-point (with-helm-current-buffer
                        (buffer-substring-no-properties
                         (point-at-bol) (point-at-eol))))
        (fname-at-point (with-helm-current-buffer (ffap-guesser))))
    (cond ((with-helm-current-buffer
             (eq major-mode 'message-mode))
           (append actions
                   '(("Gnus attach file(s)" . helm-ff-gnus-attach-files))))
          ((save-match-data
             (and (not (string-match-p ffap-url-regexp str-at-point))
                  (string-match (concat "\\(" fname-at-point "\\):\\([0-9]+:?\\)")
                                str-at-point)
                  (file-equal-p (match-string 1 str-at-point) candidate)))
           (append '(("Find file to line number" . helm-ff-goto-linum))
                   actions))
          ((string-match (image-file-name-regexp) candidate)
           (append actions
                   '(("Rotate image right `M-r'" . helm-ff-rotate-image-right)
                     ("Rotate image left `M-l'" . helm-ff-rotate-image-left))))
          ((string-match "\.el$" (helm-aif (helm-marked-candidates)
                                     (car it) candidate))
           (append actions
                   '(("Byte compile lisp file(s) `M-B, C-u to load'"
                      . helm-find-files-byte-compile)
                     ("Load File(s) `M-L'" . helm-find-files-load-files))))
          ((and (string-match "\.html?$" candidate)
                (file-exists-p candidate))
           (append actions
                   '(("Browse url file" . browse-url-of-file))))
          ((or (string= (file-name-extension candidate) "pdf")
               (string= (file-name-extension candidate) "PDF"))
           (append actions
                   '(("Pdfgrep File(s)" . helm-ff-pdfgrep))))
          (t actions))))

(defun helm-ff-goto-linum (candidate)
  "Find file CANDIDATE and maybe jump to line number found in fname at point.
line number should be added at end of fname preceded with \":\".
e.g \"foo:12\"."
  (let ((linum (let ((str (with-helm-current-buffer
                            (buffer-substring-no-properties
                             (point-at-bol) (point-at-eol))))
                     (fname (with-helm-current-buffer (ffap-guesser))))
                 (when (string-match
                        (concat "\\(" fname "\\):\\([0-9]+:?\\)") str)
                   (match-string 2 str)))))
    (find-file candidate)
    (and linum (not (string= linum ""))
         (helm-goto-line (string-to-number linum) t))))

(defun helm-ff-gnus-attach-files (_candidate)
  "Run `gnus-dired-attach' on `helm-marked-candidates' or CANDIDATE."
  (require 'gnus-dired)
  (let ((flist (helm-marked-candidates :with-wildcard t)))
    (gnus-dired-attach flist)))

(defvar image-dired-display-image-buffer)
(defun helm-ff-rotate-current-image-1 (file &optional num-arg)
  "Rotate current image at NUM-ARG degrees.
This is a destructive operation on FILE made by external tool mogrify."
  (setq file (file-truename file)) ; For symlinked images.
  ;; When FILE is not an image-file, do nothing.
  (when (string-match (image-file-name-regexp) file)
    (if (executable-find "mogrify")
        (progn
          (shell-command (format "mogrify -rotate %s %s"
                                 (or num-arg 90)
                                 (shell-quote-argument file)))
          (when (buffer-live-p image-dired-display-image-buffer)
            (kill-buffer image-dired-display-image-buffer))
          (image-dired-display-image file)
          (message nil)
          (display-buffer (get-buffer image-dired-display-image-buffer)))
      (error "mogrify not found"))))

(defun helm-ff-rotate-image-left (candidate)
  "Rotate image file CANDIDATE left.
This affect directly file CANDIDATE."
  (helm-ff-rotate-current-image-1 candidate -90))

(defun helm-ff-rotate-image-right (candidate)
  "Rotate image file CANDIDATE right.
This affect directly file CANDIDATE."
  (helm-ff-rotate-current-image-1 candidate))

(defun helm-ff-rotate-left-persistent ()
  "Rotate image left without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'image-action1 'helm-ff-rotate-image-left)
    (helm-execute-persistent-action 'image-action1)))

(defun helm-ff-rotate-right-persistent ()
  "Rotate image right without quitting helm."
  (interactive)
  (with-helm-alive-p
    (helm-attrset 'image-action2 'helm-ff-rotate-image-right)
    (helm-execute-persistent-action 'image-action2)))

(defun helm-ff-exif-data (candidate)
  "Extract exif data from file CANDIDATE using `helm-ff-exif-data-program'."
  (if (and helm-ff-exif-data-program
           (executable-find helm-ff-exif-data-program))
      (shell-command-to-string (format "%s %s %s"
                                       helm-ff-exif-data-program
                                       helm-ff-exif-data-program-args
                                       candidate))
    (format "No program %s found to extract exif"
            helm-ff-exif-data-program)))

(defun helm-find-files-persistent-action (candidate)
  "Open subtree CANDIDATE without quitting helm.
If CANDIDATE is not a directory expand CANDIDATE filename.
If CANDIDATE is alone, open file CANDIDATE filename.
That's mean:
First hit on C-j expand CANDIDATE second hit open file.
If a prefix arg is given or `helm-follow-mode' is on open file."
  (let* ((follow        (or (buffer-local-value
                             'helm-follow-mode
                             (get-buffer-create helm-buffer))
                            helm--temp-follow-flag))
         (new-pattern   (helm-get-selection))
         (num-lines-buf (with-current-buffer helm-buffer
                          (count-lines (point-min) (point-max))))
         (insert-in-minibuffer #'(lambda (fname)
                                   (with-selected-window (minibuffer-window)
                                     (unless follow
                                       (delete-minibuffer-contents)
                                       (set-text-properties 0 (length fname)
                                                            nil fname)
                                       (insert fname))))))
    (cond ((and (helm-ff-invalid-tramp-name-p)
                (string-match helm-tramp-file-name-regexp candidate))
           ;; First hit insert hostname and
           ;; second hit insert ":" and expand.
           (if (string= candidate helm-pattern)
               (funcall insert-in-minibuffer (concat candidate ":"))
             (funcall insert-in-minibuffer candidate)))
          ( ;; A symlink directory, expand it's truename.
           (and (file-directory-p candidate) (file-symlink-p candidate))
           (funcall insert-in-minibuffer (file-name-as-directory
                                          (file-truename
                                           (expand-file-name candidate)))))
          ;; A directory, open it.
          ((file-directory-p candidate)
           (when (string= (helm-basename candidate) "..")
             (setq helm-ff-last-expanded helm-ff-default-directory))
           (funcall insert-in-minibuffer (file-name-as-directory
                                          (expand-file-name candidate))))
          ;; A symlink file, expand to it's true name. (first hit)
          ((and (file-symlink-p candidate) (not current-prefix-arg) (not follow))
           (funcall insert-in-minibuffer (file-truename candidate)))
          ;; A regular file, expand it, (first hit)
          ((and (>= num-lines-buf 3) (not current-prefix-arg) (not follow))
           (setq helm-pattern "") ; Force update.
           (funcall insert-in-minibuffer new-pattern))
          ;; An image file and it is the second hit on C-j,
          ;; show the file in `image-dired'.
          ((string-match (image-file-name-regexp) candidate)
           (when (buffer-live-p (get-buffer image-dired-display-image-buffer))
             (kill-buffer image-dired-display-image-buffer))
           ;; Fix emacs bug never fixed upstream.
           (unless (file-directory-p image-dired-dir)
             (make-directory image-dired-dir))
           (image-dired-display-image candidate)
           (message nil)
           (switch-to-buffer image-dired-display-image-buffer)
           (with-current-buffer image-dired-display-image-buffer
             (let ((exif-data (helm-ff-exif-data candidate)))
               (setq default-directory helm-ff-default-directory)
               (image-dired-update-property 'help-echo exif-data))))
          ;; Allow browsing archive on avfs fs.
          ;; Assume volume is already mounted with mountavfs.
          ((and helm-ff-avfs-directory
                (string-match
                 (regexp-quote (expand-file-name helm-ff-avfs-directory))
                 (file-name-directory candidate))
                (helm-ff-file-compressed-p candidate))
           (funcall insert-in-minibuffer (concat candidate "#")))
          ;; On second hit we open file.
          ;; On Third hit we kill it's buffer maybe.
          (t
           (helm-ff-kill-or-find-buffer-fname candidate)))))

(defun helm-ff-file-compressed-p (candidate)
  "Whether CANDIDATE is a compressed file or not."
  (member (file-name-extension candidate)
          helm-ff-file-compressed-list))

(defun helm-insert-file-name-completion-at-point (candidate)
  "Insert file name completion at point."
  (with-helm-current-buffer
    (if buffer-read-only
        (error "Error: Buffer `%s' is read-only" (buffer-name))
      (let* ((end         (point))
             (tap         (thing-at-point 'filename))
             (guess       (and (stringp tap) (substring-no-properties tap)))
             (beg         (- (point) (length guess)))
             (full-path-p (and (stringp guess)
                               (or (string-match-p
                                    (concat "^" (getenv "HOME"))
                                    guess)
                                   (string-match-p
                                    "\\`\\(/\\|[[:lower:][:upper:]]:/\\)"
                                    guess)))))
        (set-text-properties 0 (length candidate) nil candidate)
        (if (and guess (not (string= guess ""))
                 (or (string-match "^\\(~/\\|/\\|[[:lower:][:upper:]]:/\\)"
                                   guess)
                     (file-exists-p candidate)))
            (progn
              (delete-region beg end)
              (insert (cond (full-path-p
                             (expand-file-name candidate))
                            ((string= (match-string 1 guess) "~/")
                              (abbreviate-file-name candidate))
                            (t (file-relative-name candidate)))))
            (insert (cond ((equal helm-current-prefix-arg '(4))
                           (abbreviate-file-name candidate))
                          ((equal helm-current-prefix-arg '(16))
                           (file-relative-name candidate))
                          (t candidate))))))))

(cl-defun helm-find-files-history (&key (comp-read t))
  "The `helm-find-files' history.
Show the first `helm-ff-history-max-length' elements of
`helm-ff-history' in an `helm-comp-read'."
  (let ((history (when helm-ff-history
                   (helm-fast-remove-dups helm-ff-history
                                          :test 'equal))))
    (when history
      (setq helm-ff-history
            (if (>= (length history) helm-ff-history-max-length)
                (cl-subseq history 0 helm-ff-history-max-length)
              history))
      (if comp-read
          (helm-comp-read
           "Switch to Directory: "
           helm-ff-history
           :name "Helm Find Files History"
           :must-match t)
        helm-ff-history))))

(defun helm-find-files-1 (fname &optional preselect)
  "Find FNAME with `helm' completion.
Like `find-file' but with `helm' support.
Use it for non--interactive calls of `helm-find-files'."
  (when (get-buffer helm-action-buffer)
    (kill-buffer helm-action-buffer))
  (setq helm-find-files--toggle-bookmark nil)
  (let* ( ;; Be sure we don't erase the precedent minibuffer if some.
         (helm-ff-auto-update-initial-value
          (and helm-ff-auto-update-initial-value
               (not (minibuffer-window-active-p (minibuffer-window)))))
         (tap (thing-at-point 'filename))
         (def (and tap (or (file-remote-p tap)
                           (expand-file-name tap)))))
    (unless helm-source-find-files
      (setq helm-source-find-files (helm-make-source
                                    "Find Files" 'helm-source-ffiles)))
    (helm :sources 'helm-source-find-files
          :input fname
          :case-fold-search helm-file-name-case-fold-search
          :preselect preselect
          :ff-transformer-show-only-basename
          helm-ff-transformer-show-only-basename
          :default def
          :prompt "Find Files or Url: "
          :buffer "*Helm Find Files*")))

(defun helm-find-files-toggle-to-bookmark ()
  "Toggle helm-bookmark for `helm-find-files' and `helm-find-files.'"
  (interactive)
  (with-helm-buffer
    (if (setq helm-find-files--toggle-bookmark
              (not helm-find-files--toggle-bookmark))
        (progn
          (helm-set-pattern "" t)
          (helm-set-sources '(helm-source-bookmark-helm-find-files)))
        ;; Switch back to helm-find-files.
        (helm-set-pattern "./" t) ; Back to initial directory of hff session.
        (helm-set-sources '(helm-source-find-files))
        (helm--maybe-update-keymap)))) 

(defun helm-find-files-initial-input (&optional input)
  "Return INPUT if present, otherwise try to guess it."
  (let ((ffap-machine-p-known 'reject))
    (unless (eq major-mode 'image-mode)
      (or (and input (or (and (file-remote-p input) input)
                         (expand-file-name input)))
          (helm-find-files-input
           (ffap-guesser)
           (thing-at-point 'filename))))))

(defun helm-find-files-input (file-at-pt thing-at-pt)
  "Try to guess a default input for `helm-find-files'."
  (let* ((non-essential t)
         (remp (or (and file-at-pt (file-remote-p file-at-pt))
                   (and thing-at-pt (file-remote-p thing-at-pt))))
         (def-dir (helm-current-directory))
         (urlp (and file-at-pt ffap-url-regexp
                    (string-match ffap-url-regexp file-at-pt)))
         (lib     (when helm-ff-search-library-in-sexp
                    (helm-find-library-at-point)))
         (hlink   (helm-ff-find-url-at-point))
         (file-p  (and file-at-pt
                       (not (string= file-at-pt ""))
                       (not remp)
                       (file-exists-p file-at-pt)
                       thing-at-pt
                       (not (string= thing-at-pt ""))
                       (file-exists-p
                        (file-name-directory
                         (expand-file-name thing-at-pt def-dir))))))
    (cond (lib)      ; e.g we are inside a require sexp.
          (hlink)    ; String at point is an hyperlink.
          (file-p    ; a regular file
           (helm-aif (ffap-file-at-point) (expand-file-name it)))
          (urlp file-at-pt) ; possibly an url or email.
          ((and file-at-pt
                (not remp)
                (file-exists-p file-at-pt))
           file-at-pt))))

(defun helm-ff-find-url-at-point ()
  "Try to find link to an url in text-property at point."
  (let* ((he      (get-text-property (point) 'help-echo))
         (ov      (overlays-at (point)))
         (ov-he   (and ov (overlay-get
                           (car (overlays-at (point))) 'help-echo)))
         (w3m-l   (get-text-property (point) 'w3m-href-anchor))
         (nt-prop (get-text-property (point) 'nt-link)))
    ;; Org link.
    (when (and (stringp he) (string-match "^LINK: " he))
      (setq he (replace-match "" t t he)))
    (cl-loop for i in (list he ov-he w3m-l nt-prop)
          thereis (and (stringp i) ffap-url-regexp (string-match ffap-url-regexp i) i))))

(defun helm-find-library-at-point ()
  "Try to find library path at point.
Find inside `require' and `declare-function' sexp."
  (require 'find-func)
  (let* ((beg-sexp (save-excursion (search-backward "(" (point-at-bol) t)))
         (end-sexp (save-excursion (search-forward ")" (point-at-eol) t)))
         (sexp     (and beg-sexp end-sexp
                        (buffer-substring-no-properties
                         (1+ beg-sexp) (1- end-sexp)))))
    (ignore-errors
      (cond ((and sexp (string-match "require \'.+[^)]" sexp))
             (find-library-name
              (replace-regexp-in-string
               "'\\|\)\\|\(" ""
               ;; If require use third arg, ignore it,
               ;; always use library path found in `load-path'.
               (cl-second (split-string (match-string 0 sexp))))))
            ((and sexp (string-match-p "^declare-function" sexp))
             (find-library-name
              (replace-regexp-in-string
               "\"\\|ext:" ""
               (cl-third (split-string sexp)))))
            (t nil)))))


;;; Handle copy, rename, symlink, relsymlink and hardlink from helm.
;;
;;
(defvar dired-async-mode)
(cl-defun helm-dired-action (candidate
                             &key action follow (files (dired-get-marked-files)))
  "Execute ACTION on FILES to CANDIDATE.
Where ACTION is a symbol that can be one of:
'copy, 'rename, 'symlink,'relsymlink, 'hardlink.
Argument FOLLOW when non--nil specify to follow FILES to destination for the actions
copy and rename."
  (when (get-buffer dired-log-buffer) (kill-buffer dired-log-buffer))
  (let ((fn     (cl-case action
                  (copy       'dired-copy-file)
                  (rename     'dired-rename-file)
                  (symlink    'make-symbolic-link)
                  (relsymlink 'dired-make-relative-symlink)
                  (hardlink   'dired-hardlink)))
        (marker (cl-case action
                  ((copy rename)   dired-keep-marker-copy)
                  (symlink        dired-keep-marker-symlink)
                  (relsymlink     dired-keep-marker-relsymlink)
                  (hardlink       dired-keep-marker-hardlink)))
        (dirflag (and (= (length files) 1)
                      (file-directory-p (car files))
                      (not (file-directory-p candidate))))
        (dired-async-state (if (and (boundp 'dired-async-mode)
                                    dired-async-mode)
                               1 -1)))
    (and follow (fboundp 'dired-async-mode) (dired-async-mode -1))
    (unwind-protect
         (dired-create-files
          fn (symbol-name action) files
          ;; CANDIDATE is the destination.
          (if (file-directory-p candidate)
              ;; When CANDIDATE is a directory, build file-name in this directory.
              ;; Else we use CANDIDATE.
              #'(lambda (from)
                  (expand-file-name (file-name-nondirectory from) candidate))
              #'(lambda (_from) candidate))
          marker)
      (and (fboundp 'dired-async-mode)
           (dired-async-mode dired-async-state)))
    (push (file-name-as-directory
           (if (file-directory-p candidate)
               (expand-file-name candidate)
             (file-name-directory candidate)))
          helm-ff-history)
    ;; If follow is non--nil we should not be in async mode.
    (when (and follow
               (not (memq action '(symlink relsymlink hardlink)))
               (not (get-buffer dired-log-buffer)))
      (let ((target (directory-file-name candidate)))
        (unwind-protect
             (progn
               (setq helm-ff-cand-to-mark
                     (helm-get-dest-fnames-from-list files candidate dirflag))
               (with-helm-after-update-hook (helm-ff-maybe-mark-candidates))
               (if (and dirflag (eq action 'rename))
                   (helm-find-files-1 (file-name-directory target)
                                      (if helm-ff-transformer-show-only-basename
                                          (helm-basename target) target))
                 (helm-find-files-1 (file-name-as-directory
                                     (expand-file-name candidate)))))
          (setq helm-ff-cand-to-mark nil))))))

(defun helm-get-dest-fnames-from-list (flist dest-cand rename-dir-flag)
  "Transform filenames of FLIST to abs of DEST-CAND.
If RENAME-DIR-FLAG is non--nil collect the `directory-file-name' of transformed
members of FLIST."
  ;; At this point files have been renamed/copied at destination.
  ;; That's mean DEST-CAND exists.
  (cl-loop
        with dest = (expand-file-name dest-cand)
        for src in flist
        for basename-src = (helm-basename src)
        for fname = (cond (rename-dir-flag (directory-file-name dest))
                          ((file-directory-p dest)
                           (concat (file-name-as-directory dest) basename-src))
                          (t dest))
        when (file-exists-p fname)
        collect fname into tmp-list
        finally return (sort tmp-list 'string<)))

(defun helm-ff-maybe-mark-candidates ()
  "Mark all candidates of list `helm-ff-cand-to-mark'.
This is used when copying/renaming/symlinking etc... and
following files to destination."
  (when (and (string= (assoc-default 'name (helm-get-current-source))
                      (assoc-default 'name helm-source-find-files))
             helm-ff-cand-to-mark)
    (with-helm-window
      (while helm-ff-cand-to-mark
        (if (string= (car helm-ff-cand-to-mark) (helm-get-selection))
            (progn
              (helm-make-visible-mark)
              (helm-next-line)
              (setq helm-ff-cand-to-mark (cdr helm-ff-cand-to-mark)))
          (helm-next-line)))
      (unless (helm-this-visible-mark)
        (helm-prev-visible-mark)))))


;;; Routines for files
;;
;;
(defun helm-file-buffers (filename)
  "Returns a list of buffer names corresponding to FILENAME."
  (cl-loop with name = (expand-file-name filename)
        for buf in (buffer-list)
        for bfn = (buffer-file-name buf)
        when (and bfn (string= name bfn))
        collect (buffer-name buf)))

(defun helm-delete-file (file &optional error-if-dot-file-p synchro)
  "Delete the given file after querying the user.
Ask to kill buffers associated with that file, too."
  (when (and error-if-dot-file-p
             (helm-ff-dot-file-p file))
    (error "Error: Cannot operate on `.' or `..'"))
  (let ((buffers (helm-file-buffers file))
        (helm--reading-passwd-or-string t))
    (if (or (< emacs-major-version 24) synchro)
        ;; `dired-delete-file' in Emacs versions < 24
        ;; doesn't support delete-by-moving-to-trash
        ;; so use `delete-directory' and `delete-file'
        ;; that handle it.
        (cond ((and (not (file-symlink-p file))
                    (file-directory-p file)
                    (directory-files file t dired-re-no-dot))
               (when (y-or-n-p (format "Recursive delete of `%s'? " file))
                 (delete-directory file 'recursive)))
              ((and (not (file-symlink-p file))
                    (file-directory-p file))
               (delete-directory file))
              (t (delete-file file)))
      (dired-delete-file
       file dired-recursive-deletes delete-by-moving-to-trash))
    (when buffers
      (cl-dolist (buf buffers)
        (when (y-or-n-p (format "Kill buffer %s, too? " buf))
          (kill-buffer buf))))))

(defun helm-delete-marked-files (_ignore)
  (let* ((files (helm-marked-candidates :with-wildcard t))
         (len (length files)))
    (with-helm-display-marked-candidates
      helm-marked-buffer-name
      (mapcar #'(lambda (f)
                  (if (file-directory-p f)
                      (concat (helm-basename f) "/")
                    (helm-basename f)))
              files)
      (if (not (y-or-n-p (format "Delete *%s File(s)" len)))
          (message "(No deletions performed)")
        (cl-dolist (i files)
          (set-text-properties 0 (length i) nil i)
          (helm-delete-file i helm-ff-signal-error-on-dot-files))
        (message "%s File(s) deleted" len)))))

(defun helm-find-file-or-marked (candidate)
  "Open file CANDIDATE or open helm marked files in separate windows.
Called with a prefix arg open files in background without selecting them."
  (let ((marked (helm-marked-candidates :with-wildcard t))
        (url-p (and ffap-url-regexp ; we should have only one candidate.
                    (string-match ffap-url-regexp candidate)))
        (ffap-newfile-prompt helm-ff-newfile-prompt-p)
        (find-file-wildcards nil)
        (make-dir-fn
         #'(lambda (dir &optional helm-ff)
             (when (y-or-n-p (format "Create directory `%s'? " dir))
               (let ((dirfname (directory-file-name dir)))
                 (if (file-exists-p dirfname)
                     (error
                      "Mkdir: Unable to create directory `%s': file exists."
                      (helm-basename dirfname))
                   (make-directory dir 'parent)))
               (when helm-ff
                 ;; Allow having this new dir in history
                 ;; to be able to retrieve it immediately
                 ;; if we want to e.g copy a file from somewhere in it.
                 (setq helm-ff-default-directory
                       (file-name-as-directory dir))
                 (push helm-ff-default-directory helm-ff-history))
               (or (and helm-ff (helm-find-files-1 dir)) t))))
        (helm--reading-passwd-or-string t))
    (if (cdr marked)
        (if helm-current-prefix-arg
            (dired-simultaneous-find-file marked nil)
            (mapc 'find-file-noselect (cdr marked))
            (find-file (car marked)))
      (if (and (not (file-exists-p candidate))
               (not url-p)
               (string-match "/$" candidate))
          ;; A a non--existing filename ending with /
          ;; Create a directory and jump to it.
          (funcall make-dir-fn candidate 'helm-ff)
        ;; A non--existing filename NOT ending with / or
        ;; an existing filename, create or jump to it.
        ;; If the basedir of candidate doesn't exists,
        ;; ask for creating it.
        (let ((dir (file-name-directory candidate)))
          (find-file-at-point
           (cond ((and dir (file-directory-p dir))
                  (substitute-in-file-name (car marked)))
                 ;; FIXME Why do we use this on urls ?
                 (url-p (helm-substitute-in-filename (car marked)))
                 ((funcall make-dir-fn dir) candidate))))))))

(defun helm-shadow-boring-files (files)
  "Files matching `helm-boring-file-regexp' will be
displayed with the `file-name-shadow' face if available."
  (helm-shadow-entries files helm-boring-file-regexp-list))

(defun helm-skip-boring-files (files)
  "Files matching `helm-boring-file-regexp' will be skipped."
  (helm-skip-entries files helm-boring-file-regexp-list))

(defun helm-skip-current-file (files)
  "Current file will be skipped."
  (remove (buffer-file-name helm-current-buffer) files))

(defun helm-w32-pathname-transformer (args)
  "Change undesirable features of windows pathnames to ones more acceptable to
other candidate transformers."
  (if (eq system-type 'windows-nt)
      (helm-transform-mapcar
       (lambda (x)
         (replace-regexp-in-string
          "/cygdrive/\\(.\\)" "\\1:"
          (replace-regexp-in-string "\\\\" "/" x)))
       args)
    args))

(defun helm-transform-file-load-el (actions candidate)
  "Add action to load the file CANDIDATE if it is an emacs lisp
file.  Else return ACTIONS unmodified."
  (if (member (file-name-extension candidate) '("el" "elc"))
      (append actions '(("Load Emacs Lisp File" . load-file)))
    actions))

(defun helm-transform-file-browse-url (actions candidate)
  "Add an action to browse the file CANDIDATE if it is a html file or URL.
Else return ACTIONS unmodified."
  (let ((browse-action '("Browse with Browser" . browse-url)))
    (cond ((string-match "^http\\|^ftp" candidate)
           (cons browse-action actions))
          ((string-match "\\.html?$" candidate)
           (append actions (list browse-action)))
          (t actions))))

(defun helm-multi-files-toggle-to-locate ()
  (interactive)
  (with-helm-buffer
  (if (setq helm-multi-files--toggle-locate
            (not helm-multi-files--toggle-locate))
      (progn
        (helm-set-sources (unless (memq 'helm-source-locate
                                        helm-sources)
                            (cons 'helm-source-locate helm-sources)))
        (helm-set-source-filter '(helm-source-locate)))
      (helm-kill-async-processes)
      (helm-set-sources (remove 'helm-source-locate
                                helm-for-files-preferred-list))
      (helm-set-source-filter nil))))


;;; List of files gleaned from every dired buffer
;;
;;
(defun helm-files-in-all-dired-candidates ()
  (save-excursion
    (cl-loop for (f . b) in dired-buffers
          when (buffer-live-p b)
          append (let ((dir (with-current-buffer b dired-directory)))
                   (if (listp dir) (cdr dir)
                     (directory-files f t dired-re-no-dot))))))

;; (dired '("~/" "~/.emacs.d/.emacs-custom.el" "~/.emacs.d/.emacs.bmk"))

(defclass helm-files-dired-source (helm-source-sync helm-type-file)
  ((candidates :initform #'helm-files-in-all-dired-candidates)))

(defvar helm-source-files-in-all-dired
  (helm-make-source "Files in all dired buffer." 'helm-files-dired-source))


;;; File Cache
;;
;;
(defvar file-cache-alist)

(defclass helm-file-cache (helm-source-in-buffer helm-type-file)
  ((init :initform (lambda () (require 'filecache)))
   (keymap :initform helm-generic-files-map)
   (help-message :initform helm-generic-file-help-message)))

(defun helm-file-cache-get-candidates ()
  (cl-loop for item in file-cache-alist append
           (cl-destructuring-bind (base &rest dirs) item
             (cl-loop for dir in dirs collect
                      (concat dir base)))))

(defvar helm-source-file-cache nil)

(defcustom helm-file-cache-fuzzy-match nil
  "Enable fuzzy matching in `helm-source-file-cache' when non--nil."
  :group 'helm-files
  :type 'boolean
  :set (lambda (var val)
         (set var val)
         (setq helm-source-file-cache
               (helm-make-source "File Cache" 'helm-file-cache
                 :fuzzy-match helm-file-cache-fuzzy-match
                 :data 'helm-file-cache-get-candidates))))

(cl-defun helm-file-cache-add-directory-recursively
    (dir &optional match (ignore-dirs t))
  (require 'filecache)
  (cl-loop for f in (helm-walk-directory
                     dir
                     :path 'full
                     :directories nil
                     :match match
                     :skip-subdirs ignore-dirs) 
           do (file-cache-add-file f)))

(defun helm-ff-cache-add-file (_candidate)
  (require 'filecache)
  (let ((mkd (helm-marked-candidates :with-wildcard t)))
    (mapc 'file-cache-add-file mkd)))

(defun helm-ff-file-cache-remove-file-1 (file)
  "Remove FILE from `file-cache-alist'."
  (let ((entry (assoc (helm-basename file) file-cache-alist))
        (dir   (helm-basedir file))
        new-entry)
    (setq new-entry (remove dir entry))
    (when (= (length entry) 1)
      (setq new-entry nil))
    (setq file-cache-alist
          (cons new-entry (remove entry file-cache-alist)))))

(defun helm-ff-file-cache-remove-file (_file)
  "Remove marked files from `file-cache-alist.'"
  (let ((mkd (helm-marked-candidates)))
    (mapc 'helm-ff-file-cache-remove-file-1 mkd)))

(defun helm-transform-file-cache (actions _candidate)
  (let ((source (helm-get-current-source)))
    (if (string= (assoc-default 'name source) "File Cache")
        (append actions
                '(("Remove marked files from file-cache"
                   . helm-ff-file-cache-remove-file)))
        actions)))


;;; File name history
;;
;;
(defvar helm-source-file-name-history
  (helm-build-sync-source "File Name History"
    :candidates 'file-name-history
    :persistent-action #'ignore
    :filtered-candidate-transformer #'helm-file-name-history-transformer
    :action 'helm-type-file-actions))

(defvar helm-source--ff-file-name-history nil
  "[Internal] This source is build to be used with `helm-find-files'.
Don't use it in your own code unless you know what you are doing.")

(defun helm-file-name-history-transformer (candidates _source)
  (cl-loop for c in candidates collect
        (cond ((file-remote-p c)
               (cons (propertize c 'face 'helm-history-remote) c))
              ((file-exists-p c)
               (cons (propertize c 'face 'helm-ff-file) c))
              (t (cons (propertize c 'face 'helm-history-deleted) c)))))

(defun helm-ff-file-name-history ()
  "Switch to `file-name-history' without quitting `helm-find-files'."
  (interactive)
  (unless helm-source--ff-file-name-history
    (setq helm-source--ff-file-name-history
          (helm-build-sync-source "File name history"
            :init (lambda ()
                    (with-helm-alive-p
                      (when helm-ff-file-name-history-use-recentf
                        (require 'recentf)
                        (or recentf-mode (recentf-mode 1)))))
            :candidates (lambda ()
                          (if helm-ff-file-name-history-use-recentf
                              recentf-list
                              file-name-history))
            :fuzzy-match t
            :persistent-action 'ignore
            :filtered-candidate-transformer 'helm-file-name-history-transformer
            :action (helm-make-actions
                     "Find file" (lambda (candidate)
                                   (helm-set-pattern
                                    (expand-file-name candidate))
                                   (with-helm-after-update-hook (helm-exit-minibuffer)))
                     "Find file in helm" (lambda (candidate)
                                           (helm-set-pattern
                                            (expand-file-name candidate)))))))
  (with-helm-alive-p
    (helm :sources 'helm-source--ff-file-name-history
          :buffer "*helm-file-name-history*"
          :allow-nest t
          :resume 'noresume)))

;;; Recentf files
;;
;;
(defvar helm-recentf--basename-flag nil)

(defun helm-recentf-pattern-transformer (pattern)
  (let ((pattern-no-flag (replace-regexp-in-string " -b" "" pattern)))
    (cond ((and (string-match " " pattern-no-flag)
                (string-match " -b\\'" pattern))
           (setq helm-recentf--basename-flag t)
           pattern-no-flag)
        ((string-match "\\([^ ]*\\) -b\\'" pattern)
         (prog1 (match-string 1 pattern)
           (setq helm-recentf--basename-flag t)))
        (t (setq helm-recentf--basename-flag nil)
           pattern))))

(defclass helm-recentf-source (helm-source-sync)
  ((init :initform (lambda ()
                     (require 'recentf)
                     (recentf-mode 1)))
   (candidates :initform (lambda () recentf-list))
   (pattern-transformer :initform 'helm-recentf-pattern-transformer)
   (match-part :initform (lambda (candidate)
                           (if (or helm-ff-transformer-show-only-basename
                                   helm-recentf--basename-flag)
                               (helm-basename candidate) candidate)))
   (filter-one-by-one :initform (lambda (c)
                                  (if (and helm-ff-transformer-show-only-basename
                                           (not (consp c)))
                                      (cons (helm-basename c) c)
                                      c)))
   (keymap :initform helm-generic-files-map)
   (help-message :initform helm-generic-file-help-message)
   (action :initform 'helm-type-file-actions)))

(defvar helm-source-recentf nil 
  "See (info \"(emacs)File Conveniences\").
Set `recentf-max-saved-items' to a bigger value if default is too small.")

(defcustom helm-recentf-fuzzy-match nil
  "Enable fuzzy matching in `helm-source-recentf' when non--nil."
  :group 'helm-files
  :type 'boolean
  :set (lambda (var val)
         (set var val)
         (setq helm-source-recentf
               (helm-make-source "Recentf" 'helm-recentf-source
                 :fuzzy-match helm-recentf-fuzzy-match))))

;;; Browse project
;; Need dependencies:
;; <https://github.com/emacs-helm/helm-ls-git>
;; <https://github.com/emacs-helm/helm-ls-hg>
;; Only hg and git are supported for now.
(defvar helm--browse-project-cache (make-hash-table :test 'equal))

(defun helm-browse-project-get-buffers (root-directory)
  (cl-loop for b in (helm-buffer-list)
           for bf = (buffer-file-name (get-buffer b)) 
           when (and bf (file-in-directory-p bf root-directory))
           collect b))

(defun helm-browse-project-build-buffers-source (directory)
  (helm-make-source "Buffers in project" 'helm-source-buffers
    :header-name (lambda (name)
                   (format
                    "%s (%s)"
                    name (abbreviate-file-name directory)))
    :buffer-list (lambda () (helm-browse-project-get-buffers directory))))

(defun helm-browse-project-find-files (directory &optional refresh)
  (when refresh (remhash directory helm--browse-project-cache))
  (unless (gethash directory helm--browse-project-cache)
    (puthash directory (helm-walk-directory
                        directory
                        :directories nil :path 'full :skip-subdirs t)
             helm--browse-project-cache))
  (helm :sources `(,(helm-browse-project-build-buffers-source directory)
                   ,(helm-build-in-buffer-source "Browse project"
                     :data (gethash directory helm--browse-project-cache)
                     :header-name (lambda (name)
                                    (format
                                     "%s (%s)"
                                     name (abbreviate-file-name directory)))
                     :match-part (lambda (c)
                                   (if helm-ff-transformer-show-only-basename
                                       (helm-basename c) c))
                     :filter-one-by-one
                     (lambda (c)
                       (if helm-ff-transformer-show-only-basename
                           (cons (propertize (helm-basename c)
                                             'face 'helm-ff-file)
                                 c)
                           (propertize c 'face 'helm-ff-file)))
                     :keymap helm-generic-files-map
                     :action 'helm-type-file-actions)) 
        :buffer "*helm browse project*"))

;;;###autoload
(defun helm-browse-project (arg)
  "Preconfigured helm to browse projects.
Browse files and see status of project with its vcs.
Only HG and GIT are supported for now.
Fall back to `helm-browse-project-find-files'
if current directory is not under control of one of those vcs.
With a prefix ARG browse files recursively, with two prefix ARG
rebuild the cache.
If the current directory is found in the cache, start
`helm-browse-project-find-files' even with no prefix ARG.
NOTE: The prefix ARG have no effect on the VCS controlled directories.

Needed dependencies for VCS:
<https://github.com/emacs-helm/helm-ls-git>
and
<https://github.com/emacs-helm/helm-ls-hg>
and
<http://melpa.org/#/helm-ls-svn>."
  (interactive "P")
  (cond ((and (require 'helm-ls-git nil t)
              (fboundp 'helm-ls-git-root-dir)
              (helm-ls-git-root-dir))
         (helm-ls-git-ls))
        ((and (require 'helm-ls-hg nil t)
              (fboundp 'helm-hg-root)
              (helm-hg-root))
         (helm-hg-find-files-in-project))
        ((and (require 'helm-ls-svn nil t)
              (fboundp 'helm-ls-svn-root-dir)
              (helm-ls-svn-root-dir))
         (helm-ls-svn-ls))
        (t (let ((cur-dir (helm-browse-project-get--root-dir
                           (helm-current-directory))))
             (if (or arg (gethash cur-dir helm--browse-project-cache))
                 (helm-browse-project-find-files cur-dir (equal arg '(16)))
                 (helm :sources (helm-browse-project-build-buffers-source cur-dir)
                       :buffer "*helm browse project*"))))))

(defun helm-browse-project-get--root-dir (directory)
  (cl-loop with dname = (file-name-as-directory directory)
           while (and dname (not (gethash dname helm--browse-project-cache)))
           if (file-remote-p dname)
           do (setq dname nil) else
           do (setq dname (helm-basedir (substring dname 0 (1- (length dname)))))
           finally return (or dname (file-name-as-directory directory))))

(defun helm-ff-browse-project (_candidate)
  "Browse project in current directory.
See `helm-browse-project'."
  (with-helm-default-directory helm-ff-default-directory
      (helm-browse-project helm-current-prefix-arg)))

(defun helm-ff-run-browse-project ()
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-browse-project)))

(defun helm-ff-gid (_candidate)
  (with-helm-default-directory helm-ff-default-directory
      (helm-gid)))

(defun helm-ff-run-gid ()
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-gid)))

;;; session.el files
;;
;;  session (http://emacs-session.sourceforge.net/) is an alternative to
;;  recentf that saves recent file history and much more.
(defvar session-file-alist)
(defvar helm-source-session
  (helm-build-sync-source "Session"
    :candidates (lambda ()
                  (cl-delete-if-not #'(lambda (f)
                                        (or (string-match helm-tramp-file-name-regexp f)
                                            (file-exists-p f)))
                                    (mapcar 'car session-file-alist)))
    :keymap helm-generic-files-map
    :help-message helm-generic-file-help-message
    :action 'helm-type-file-actions)
  "File list from emacs-session.")


;;; Files in current dir
;;
;;
(defun helm-highlight-files (files)
  "A basic transformer for helm files sources.
Colorize only symlinks, directories and files."
  (cl-loop for i in files
        for disp = (if (and helm-ff-transformer-show-only-basename
                            (not (helm-dir-is-dot i))
                            (not (and ffap-url-regexp
                                      (string-match ffap-url-regexp i)))
                            (not (string-match helm-ff-url-regexp i)))
                       (helm-basename i) i)
        for type = (and (null helm-ff-tramp-not-fancy)
                        (car (file-attributes i)))
        collect
        (cond ((and helm-ff-tramp-not-fancy
                    (string-match helm-tramp-file-name-regexp i))
               (cons disp i))
              ((stringp type)
               (cons (propertize disp
                                 'face 'helm-ff-symlink
                                 'help-echo (expand-file-name i))
                     i))
              ((eq type t)
               (cons (propertize disp
                                 'face 'helm-ff-directory
                                 'help-echo (expand-file-name i))
                     i))
              (t (cons (propertize disp
                                   'face 'helm-ff-file
                                   'help-echo (expand-file-name i))
                       i)))))

(defclass helm-files-in-current-dir-source (helm-source-sync helm-type-file)
  ((candidates :initform (lambda ()
                           (with-helm-current-buffer
                             (let ((dir (helm-current-directory)))
                               (when (file-accessible-directory-p dir)
                                 (directory-files dir t))))))
   (pattern-transformer :initform 'helm-recentf-pattern-transformer)
   (match-part :initform (lambda (candidate)
                           (if (or helm-ff-transformer-show-only-basename
                                   helm-recentf--basename-flag)
                               (helm-basename candidate) candidate)))
   (fuzzy-match :initform t)
   (keymap :initform helm-generic-files-map)
   (help-message :initform helm-generic-file-help-message)))

(defvar helm-source-files-in-current-dir
  (helm-make-source "Files from Current Directory"
      helm-files-in-current-dir-source))


;;; External searching file tools.
;;
;; Tracker desktop search
(defvar helm-source-tracker-cand-incomplete nil "Contains incomplete candidate")
(defun helm-source-tracker-transformer (candidates _source)
  (helm-log "received: %S" candidates)
  (cl-loop for cand in candidates
           for path = (when (stringp helm-source-tracker-cand-incomplete)
                        (caar (helm-highlight-files
                               (list helm-source-tracker-cand-incomplete))))
           for built = (if (not (stringp cand)) cand
                         (let ((snippet cand))
                           (unless (or (null path)
                                      (string= "" path)
                                      (not (string-match-p
                                          "\\`[[:space:]]*\\.\\.\\."
                                          snippet)))
                             (let ((complete-candidate
                                    (cons (concat path "\n" snippet) path)))
                               (setq helm-source-tracker-cand-incomplete nil)
                               (helm-log "built: %S" complete-candidate)
                               complete-candidate))))
           when (and (stringp cand)
                   (string-match "\\`[[:space:]]*file://" cand))
           do (setq helm-source-tracker-cand-incomplete ; save path
                    (replace-match "" t t cand)) end
           collect built))

(defvar helm-source-tracker-search
  (helm-build-async-source "Tracker Search"
    :candidates-process
     (lambda ()
       (start-process "tracker-search-process" nil
                      "tracker-search"
                      "--disable-color"
                      "--limit=512"
                      helm-pattern))
    :filtered-candidate-transformer #'helm-source-tracker-transformer
    ;;(multiline) ; https://github.com/emacs-helm/helm/issues/529
    :keymap helm-generic-files-map
    :action 'helm-type-file-actions
    :action-transformer '(helm-transform-file-load-el
                          helm-transform-file-browse-url)
    :requires-pattern 3)
  "Source for retrieving files matching the current input pattern
with the tracker desktop search.")

;; Spotlight (MacOS X desktop search)
(defclass helm-mac-spotlight-source (helm-source-async helm-type-file)
  ((candidates-process :initform
                       (lambda ()
                         (start-process
                          "mdfind-process" nil "mdfind" helm-pattern)))
   (requires-pattern :init-form 3)))

(defvar helm-source-mac-spotlight
  (helm-make-source "mdfind" helm-mac-spotlight-source)
  "Source for retrieving files via Spotlight's command line
utility mdfind.")


;;; Findutils
;;
;;
(defvar helm-source-findutils
  (helm-build-async-source "Find"
    :header-name (lambda (name)
                   (concat name " in [" (helm-default-directory) "]"))
    :candidates-process 'helm-find-shell-command-fn
    :filtered-candidate-transformer 'helm-findutils-transformer
    :action-transformer 'helm-transform-file-load-el
    :action 'helm-type-file-actions
    :keymap helm-generic-files-map
    :candidate-number-limit 9999
    :requires-pattern 3))

(defun helm-findutils-transformer (candidates _source)
  (let (non-essential
        (default-directory (helm-default-directory)))
    (cl-loop for i in candidates
             for abs = (expand-file-name
                        (helm-aif (file-remote-p default-directory)
                            (concat it i) i))
             for type = (car (file-attributes abs))
             for disp = (if (and helm-ff-transformer-show-only-basename
                                 (not (string-match "[.]\\{1,2\\}$" i)))
                            (helm-basename abs) abs)
             collect (cond ((eq t type)
                            (cons (propertize disp 'face 'helm-ff-directory)
                                  abs))
                           ((stringp type)
                            (cons (propertize disp 'face 'helm-ff-symlink)
                                  abs))
                           (t (cons (propertize disp 'face 'helm-ff-file)
                                    abs))))))

(defun helm-find--build-cmd-line ()
  (require 'find-cmd)
  (let* ((default-directory (or (file-remote-p default-directory 'localname)
                                default-directory))
         (patterns+options (split-string helm-pattern "\\(\\`\\| +\\)\\* +"))
         (fold-case (helm-set-case-fold-search (car patterns+options)))
         (patterns (split-string (car patterns+options)))
         (additional-options (and (cdr patterns+options)
                                  (list (concat (cadr patterns+options) " "))))
         (ignored-dirs ())
         (ignored-files (when helm-findutils-skip-boring-files
                          (cl-loop for f in completion-ignored-extensions
                                   if (string-match "/$" f)
                                   do (push (replace-match "" nil t f)
                                            ignored-dirs)
                                   else collect (concat "*" f))))
         (path-or-name (if helm-findutils-search-full-path
                           '(ipath path) '(iname name)))
         (name-or-iname (if fold-case
                            (car path-or-name) (cadr path-or-name))))
    (find-cmd (and ignored-dirs
                   `(prune (name ,@ignored-dirs)))
              (and ignored-files
                   `(not (name ,@ignored-files)))
              `(and ,@(mapcar
                       (lambda (pattern)
                         `(,name-or-iname ,(concat "*" pattern "*")))
                       patterns)
                    ,@additional-options))))

(defun helm-find-shell-command-fn ()
  "Asynchronously fetch candidates for `helm-find'.
Additional find options can be specified after a \"*\"
separator."
  (let* (process-connection-type
         non-essential
         (cmd (helm-find--build-cmd-line))
         (proc (start-file-process-shell-command "hfind" helm-buffer cmd)))
    (helm-log "Find command:\n%s" cmd)
    (prog1 proc
      (set-process-sentinel
       proc
       #'(lambda (process event)
           (helm-process-deferred-sentinel-hook
            process event (helm-default-directory))
           (if (string= event "finished\n")
               (with-helm-window
                 (setq mode-line-format
                       '(" " mode-line-buffer-identification " "
                         (:eval (format "L%s" (helm-candidate-number-at-point))) " "
                         (:eval (propertize
                                 (format "[Find process finished - (%s results)]" 
                                         (max (1- (count-lines
                                                   (point-min) (point-max)))
                                              0))
                                 'face 'helm-locate-finish))))
                 (force-mode-line-update))
               (helm-log "Error: Find %s"
                         (replace-regexp-in-string "\n" "" event))))))))

(defun helm-find-1 (dir)
  (let ((default-directory (file-name-as-directory dir)))
    (helm :sources 'helm-source-findutils
          :buffer "*helm find*"
          :ff-transformer-show-only-basename nil
          :case-fold-search helm-file-name-case-fold-search)))

;; helm-find-files integration.
(defun helm-ff-find-sh-command (_candidate)
  "Run `helm-find' from `helm-find-files'."
  (helm-find-1 helm-ff-default-directory))

(defun helm-ff-run-find-sh-command ()
  "Run find shell command action with key from `helm-find-files'."
  (interactive)
  (with-helm-alive-p
    (helm-quit-and-execute-action 'helm-ff-find-sh-command)))


;;; Preconfigured commands
;;
;;
;;;###autoload
(defun helm-find (arg)
  "Preconfigured `helm' for the find shell command."
  (interactive "P")
  (let ((directory
         (if arg
             (file-name-as-directory
              (read-directory-name "DefaultDirectory: "))
           default-directory)))
    (helm-find-1 directory)))

(defvar org-directory)
;;;###autoload
(defun helm-find-files (arg)
  "Preconfigured `helm' for helm implementation of `find-file'.
Called with a prefix arg show history if some.
Don't call it from programs, use `helm-find-files-1' instead.
This is the starting point for nearly all actions you can do on files."
  (interactive "P")
  (let* ((hist          (and arg helm-ff-history (helm-find-files-history)))
         (default-input (or hist (helm-find-files-initial-input)))
         (input         (cond ((and (eq major-mode 'org-agenda-mode)
                                    org-directory
                                    (not default-input))
                               (expand-file-name org-directory))
                              ((and (eq major-mode 'dired-mode) default-input)
                               (file-name-directory default-input))
                              ((and (not (string= default-input ""))
                                    default-input))
                              (t (expand-file-name (helm-current-directory)))))
         (presel        (helm-aif (or hist
                                      (buffer-file-name (current-buffer))
                                      (and (eq major-mode 'dired-mode)
                                           default-input))
                            (if helm-ff-transformer-show-only-basename
                                (helm-basename it) it))))
    (set-text-properties 0 (length input) nil input)
    (helm-find-files-1 input (and presel (concat "^" (regexp-quote presel))))))

;;;###autoload
(defun helm-for-files ()
  "Preconfigured `helm' for opening files.
Run all sources defined in `helm-for-files-preferred-list'."
  (interactive)
  (unless helm-source-buffers-list
    (setq helm-source-buffers-list
          (helm-make-source "Buffers" 'helm-source-buffers)))
  (helm :sources helm-for-files-preferred-list
        :ff-transformer-show-only-basename nil
        :buffer "*helm for files*"))

;;;###autoload
(defun helm-multi-files ()
  "Preconfigured helm similar to `helm-for-files' but that don't run locate.
Allow toggling from locate to others sources.
This allow seeing first if what you search is in other sources before launching
locate."
  (interactive)
  (unless helm-source-buffers-list
    (setq helm-source-buffers-list
          (helm-make-source "Buffers" 'helm-source-buffers)))
  (setq helm-multi-files--toggle-locate nil)
  (let ((sources (remove 'helm-source-locate helm-for-files-preferred-list))
        (old-key (lookup-key
                  helm-map
                  (read-kbd-macro helm-multi-files-toggle-locate-binding))))
    (with-helm-temp-hook 'helm-after-initialize-hook
      (define-key helm-map (kbd helm-multi-files-toggle-locate-binding)
        'helm-multi-files-toggle-to-locate))
    (unwind-protect
         (helm :sources sources
               :ff-transformer-show-only-basename nil
               :buffer "*helm multi files*")
      (define-key helm-map (kbd helm-multi-files-toggle-locate-binding)
        old-key))))

;;;###autoload
(defun helm-recentf ()
  "Preconfigured `helm' for `recentf'."
  (interactive)
  (helm :sources 'helm-source-recentf
        :ff-transformer-show-only-basename nil
        :buffer "*helm recentf*"))

(provide 'helm-files)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-files.el ends here
