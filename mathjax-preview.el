;;; mathjax-preview.el --- Render MathJax expressions to SVG -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ntalbs

;; Author: ntalbs <ntalbsen@gmail.com>
;; License: MIT
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.2"))
;; Keywords: convenience, wp
;; URL: https://github.com/ntalbs/mathjax-preview

;;; Commentary:
;; This package provides a quick and easy way to render and preview
;; MathJax expressions in a dedicated buffer.

;;; License:
;; MIT License

;; Copyright (c) 2026 ntalbs

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Code:

(require 'rx)

(defgroup mathjax-preview nil
  "MathJax Preview settings."
  :group 'applications)

(defcustom mathjax-preview-command "rendermj"
  "Command used to render MathJax expressions to SVG.
Can be an executable name available in PATH or an absolute path."
  :type 'string
  :group 'mathjax-preview)

(defcustom mathjax-preview-margin-left 10
  "Left margin for rendered math in pixels."
  :type 'integer
  :group 'mathjax-preview)

(defcustom mathjax-preview-margin-top 0
  "Top margin for rendered math in pixels."
  :type 'integer
  :group 'mathjax-preview)

(defconst mathjax-preview-buffer-name "*MathJax Preview*"
  "Name of the buffer displaying the math SVG preview.")

(defun mathjax-preview--get-math-at-point ()
  "Extract math expression at point."
  (save-excursion
    (let ((p (point))
          start end latex)
      (cond
       ;; 1. check \[ ... \] block
       ((save-excursion
          (when (re-search-backward (rx "\\" "[") nil t)
            (let ((s (match-beginning 0)))
              (goto-char (match-end 0))
              (when (re-search-forward (rx "\\" "]") nil t)
                (let ((e (match-end 0)))
                  (when (and (<= s p) (<= p e))
                    (setq start (+ s 2) end (- e 2))))))))
        (setq latex (buffer-substring-no-properties start end)))
       ;; 2. check \( ... \) inline block
       ((save-excursion
          (when (re-search-backward (rx "\\" "(") nil t)
            (let ((s (match-beginning 0)))
              (goto-char (match-end 0))
              (when (re-search-forward (rx "\\" ")") nil t)
                (let ((e (match-end 0)))
                  (when (and (<= s p) (<= p e))
                    (setq start (+ s 2) end (- e 2))))))))
        (setq latex (buffer-substring-no-properties start end)))
       ;; 3. check $$ ... $$ block
       ((save-excursion
          (when (re-search-backward (rx "$$") nil t)
            (let ((s (match-beginning 0)))
              (goto-char (match-end 0))
              (when (re-search-forward (rx "$$") nil t)
                (let ((e (match-end 0)))
                  (when (and (<= s p) (<= p e))
                    (setq start (+ s 2) end (- e 2))))))))
        (setq latex (buffer-substring-no-properties start end)))

       ;; 4. check $ ... $ inline block
       ((save-excursion
          (let ((found nil))
            (while (and (not found) (re-search-backward (rx "$") nil t))
              (let ((s (match-beginning 0)))
                (unless (or (and (> s (point-min)) (= (char-before s) ?$))
                            (and (< s (point-max)) (= (char-after (1+ s)) ?$)))
                  (setq found s))))
            (when found
              (let ((s found))
                (goto-char (1+ s))
                (when (re-search-forward (rx "$") nil t)
                  (let ((e (match-end 0)))
                    (unless (and (< e (point-max)) (= (char-after e) ?$))
                      (when (and (<= s p) (<= p e))
                        (setq start (+ s 1) end (- e 1))))))))))
        (setq latex (buffer-substring-no-properties start end))))

      (when (and start end latex)
        (mathjax-preview--highlight-math-expr start end))

      latex)))

(defun mathjax-preview--highlight-math-expr (start end)
  "Highlight captured math expression between START and END for a second."
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'face '((:background "light yellow" :extend t)))
    (run-with-timer 1.0 nil #'delete-overlay ov)))

(defun mathjax-preview--render-to-svg (input)
  "Render the MathJax expression INPUT string to SVG and return it as a string."
  (let ((output-buf (generate-new-buffer " *mathjax-temp-output*")))
    (unwind-protect
        (let ((exit-code (call-process mathjax-preview-command nil output-buf nil input)))
          (if (= exit-code 0)
              (with-current-buffer output-buf
                (let ((result (string-trim (buffer-string))))
                  (if (string-prefix-p "<svg" result)
                      result
                    (progn
                      (message "MathJax Output Error: %s" result)
                      nil))))
            (progn
              (message "MathJax process exited with code %d" exit-code)
              nil)))
      (when (get-buffer output-buf)
        (kill-buffer output-buf)))))

(defun mathjax-preview--update-buffer (svg)
  "Open the preview buffer and insert the rendered SVG."
  (with-current-buffer (get-buffer-create mathjax-preview-buffer-name)
    (let* ((inhibit-read-only t))
      (erase-buffer)
      (insert "\n")
      (insert (propertize " "
                          'display
                          `(space :width ,mathjax-preview-margin-left
                                  ;; :height ,mathjax-preview-margin-top
                                  )))
      (insert-image svg)
      (insert "\n")
      (goto-char (point-min))
      (setq-local cursor-type nil)
      (hl-line-mode -1)
      (local-set-key (kbd "q") #'quit-window)
      (setq buffer-read-only t))))

(defun mathjax-preview--show-window (svg)
  "Show SVG in preview window with proper size."
  (let* ((preview-buf (get-buffer mathjax-preview-buffer-name))
         (window (get-buffer-window preview-buf))
         (img-height-px (cdr (image-size svg t)))
         (char-height (max 1 (frame-char-height)))
         (required-lines (+ (ceiling (/ (float img-height-px) char-height)) 4)))
    (unless window
      (setq window (display-buffer-in-side-window preview-buf '((side . bottom)))))
    (window-resize window (- required-lines (window-total-height window)) nil t)))

(defun mathjax-preview--close-window ()
  "Close the mathjax-preview window if it is currently visible."
  (let ((window (get-buffer-window mathjax-preview-buffer-name)))
    (when window
      (delete-window window))))

;;;###autoload
(defun mathjax-preview-at-point ()
  "Render the MathJax math expression at the current cursor position and display it in a bottom window."
  (interactive)
  (let* ((latex (mathjax-preview--get-math-at-point))
         (output-string (and latex (mathjax-preview--render-to-svg latex))))
    (cond
     ((not latex)
      (mathjax-preview--close-window)
      (message "No valid MathJax expression found at point."))
     ((not (and output-string (> (length output-string) 0)))
      (mathjax-preview--close-window)
      (message "MathJax rendering failed or produced empty output."))
     (t
      (let ((svg (create-image output-string 'svg t :scale 1.1)))
        (mathjax-preview--update-buffer svg)
        (mathjax-preview--show-window svg))))))

(provide 'mathjax-preview)

;;; mathjax-preview.el ends here
