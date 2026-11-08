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

(defcustom mathjax-preview-overlay-color "#f3eaf4"
  "Color for math block (including inline) overlay color."
  :type 'string
  :group 'mathjax-preview)

(defcustom mathjax-preview-overlay-duration 3
  "Duration for showing overlay over math block in second."
  :type 'integer
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
       ;; 1. Check $ ... $ inline block (Parity-based matching with explicit start/end)
       ((save-excursion
          (let ((para-start (save-excursion (backward-paragraph) (point)))
                (para-end   (save-excursion (forward-paragraph) (point)))
                (dollars '())
                (matched nil))
            ;; Collect all valid unescaped single $ positions within the paragraph
            (save-excursion
              (goto-char para-start)
              (while (re-search-forward (rx (optional (not (any "\\"))) (group "$")) para-end t)
                (let ((pos (match-beginning 1)))
                  ;; Ensure it's a single $ and not escaped by a backslash
                  (unless (and (> pos para-start)
                               (= (char-before pos) ?\\)
                               (not (and (> pos (1+ para-start)) (= (char-before (1- pos)) ?\\))))
                    (push pos dollars)))))

            (setq dollars (nreverse dollars))

            ;; Find the pair enclosing the cursor p
            (let ((i 0))
              (while (and (< (1+ i) (length dollars)) (not matched))
                (let ((s (nth i dollars))
                      (e (nth (+ i 1) dollars)))
                  ;; Cursor must be strictly inside the dollar signs: s < p < e
                  (when (and (< s p) (< p e))
                    (setq start (1+ s)
                          end e
                          matched t)))
                (setq i (+ i 2))))
            matched))
        ;; start and end are now properly bound for the common substring extraction below)
        (setq latex (buffer-substring-no-properties start end)))

       ;; 2. check \( ... \) inline block
       ((save-excursion
          (when (re-search-backward (rx "\\(") nil t)
            (let ((s (match-end 0)))
              (goto-char s)
              (when (re-search-forward (rx "\\)") nil t)
                (let ((e (match-beginning 0)))
                  (when (and (<= s p) (<= p e))
                    (setq start s end e)))))))
        (setq latex (buffer-substring-no-properties start end)))

       ;; 3. check \[ ... \] block
       ((save-excursion
          (when (re-search-backward (rx "\\[\n") nil t)
            (let ((s (match-end 0)))
              (goto-char s)
              (when (re-search-forward (rx "\\]\n") nil t)
                (let ((e (match-beginning 0)))
                  (when (and (<= s p) (<= p e))
                    (setq start s end e)))))))
        (setq latex (buffer-substring-no-properties start end)))

       ;; 4. check $$ ... $$ block
       ((save-excursion
          (let ((markers '())
                (matched nil))
            ;; Collect all $$ markers across the ENTIRE document
            (save-excursion
              (goto-char (point-min))
              (let ((i 0))
                (while (re-search-forward (rx "$$" (optional "%math") "\n") nil t)
                  (if (= (% i 2) 0)
                      (push (match-end 0) markers)
                    (push (match-beginning 0) markers))
                  (setq i (1+ i)))))

            (setq markers (nreverse markers))

            ;; Pair up consecutive $$ markers globally: odd index = start, even index = end
            (let ((i 0))
              (while (and (< (1+ i) (length markers)) (not matched))
                (let ((s (nth i markers))
                      (e (nth (+ i 1) markers)))
                  ;; Determine actual content start
                  ;; Ensure cursor p is strictly inside the global block content
                  (when (and (<= s p) (<= p e))
                    (setq start s
                          end e
                          matched t)))
                (setq i (+ i 2))))
            matched))
        (setq latex (buffer-substring-no-properties start end))))

      (when (and start end latex)
        (mathjax-preview--highlight-math-expr start end))

      latex)))

(defun mathjax-preview--highlight-math-expr (start end)
  "Highlight captured math expression between START and END for three second."
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'face `(:background ,mathjax-preview-overlay-color :extend t))
    (run-with-timer mathjax-preview-overlay-duration nil #'delete-overlay ov)))

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
      (setq window (display-buffer-in-side-window preview-buf '((side . bottom)
                                                                (inhibit-select-window . t)))))
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
      (let ((svg (create-image output-string 'svg t :scale 1.2)))
        (mathjax-preview--update-buffer svg)
        (mathjax-preview--show-window svg))))))

(provide 'mathjax-preview)

;;; mathjax-preview.el ends here
