;;; mathjax-preview.el --- Render MathJax expressions to SVG -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ntalbs

;; Author: ntalbs <ntalbsen@gmail.com>
;; Assisted-by: Gemini:3
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1"))
;; Keywords: tex, mathjax, latex, preview
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

(defcustom mathjax-preview-rendermj-exec-path "rendermj"
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
  :type 'number
  :group 'mathjax-preview)

(defcustom mathjax-preview-margin-left 10
  "Left margin for rendered math in pixels."
  :type 'integer
  :group 'mathjax-preview)

(defconst mathjax-preview-buffer-name "*MathJax Preview*"
  "Name of the buffer displaying the math SVG preview.")

(defun mathjax-preview--check-executable ()
  "Check if `rendermj` executable path is valid."
  (if (not (executable-find mathjax-preview-rendermj-exec-path))
      (let ((msg (format
                  "Could not find the 'rendermj' executable. Please check the path '%s' or install the CLI tool."
                  mathjax-preview-rendermj-exec-path)))
        (mathjax-preview--update-buffer msg)
        nil)
    t))

(defun mathjax-preview--get-inline-math-paren ()
  "Return inline math expression if point is enclosed in \\( ... \\)."
  (let ((p (point))
        start
        end
        matched)
    (save-excursion
      (when (re-search-backward (rx "\\(") nil t)
        (let ((s (match-end 0)))
          (goto-char s)
          (when (re-search-forward (rx "\\)") nil t)
            (let ((e (match-beginning 0)))
              (when (and (<= s p) (<= p e))
                (setq start s end e matched t))))))
      (if matched (buffer-substring-no-properties start end)))))

(defun mathjax-preview--get-block-math-bracket ()
  "Return block math expression if point is enclosed in \\[ ... \\]."
  (save-excursion
    (let ((p (point))
          start
          end
          matched)
      (when (re-search-backward (rx "\\[\n") nil t)
        (let ((s (match-end 0)))
          (goto-char s)
          (when (re-search-forward (rx "\\]\n") nil t)
            (let ((e (match-beginning 0)))
              (when (and (<= s p) (<= p e))
                (setq start s end e matched t))))))
      (if matched (buffer-substring-no-properties start end)))))

(defun mathjax-preview--escaped-p (pos)
  "Return non-nil if the char at POS is escaped."
  (let ((count 0)
        (p (1- pos)))
    (while (and (>= p (point-min))
                (= (char-after p) ?\\))
      (setq count (1+ count)
            p (1- p)))
    (= (% count 2) 1)))

(defun mathjax-preview--get-inline-math-dollar ()
  "Return inline math expression if point is enclosed in $ ... $."
  (let ((p (point))
        (para-start (save-excursion (backward-paragraph) (point)))
        (para-end   (save-excursion (forward-paragraph) (point)))
        (dollars '())
        matched
        start
        end)

    ;; Collect all unescaped single $ positions within the paragraph
    (save-excursion
      (goto-char para-start)
      (while (re-search-forward (rx "$") para-end t)
        (let ((pos (match-beginning 0)))
          (unless (mathjax-preview--escaped-p pos)
            (push pos dollars)))))

    (setq dollars (nreverse dollars))

    ;; Find the pair enclosing the cursor p
    (let ((i 0)
          (len (length dollars)))
      (while (and (< i (1- len)) (not matched))
        (let* ((s (nth i dollars))
               (e (nth (1+ i) dollars))
               (valid-opening-p
                (and (< (1+ s) para-end)
                     (not (memq (char-after (1+ s)) '(?\s ?\t ?\n)))))

               (valid-closing-p
                (and (> e para-start)
                     (not (memq (char-before e) '(?\s ?\t ?\n))))))

          (when (and valid-opening-p valid-closing-p (< s p e))
            (setq start (1+ s)
                  end e
                  matched t))
          (setq i (1+ i)))))

    (if matched
        (buffer-substring-no-properties start end))))

(defun mathjax-preview--get-block-math-dollar ()
  "Return block math expression if point is enclosed in $$ ... $$."
  (let ((p (point))
        (markers '()))
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
    (let ((i 0)
          start
          end
          matched)
      (while (and (< (1+ i) (length markers)) (not matched))
        (let ((s (nth i markers))
              (e (nth (+ i 1) markers)))
          ;; Determine actual content start
          ;; Ensure cursor p is strictly inside the global block content
          (when (and (<= s p) (<= p e))
            (setq start s
                  end e
                  matched t)))
        (setq i (+ i 2)))
      (if matched (buffer-substring-no-properties start end)))))

(defun mathjax-preview--get-math-at-point ()
  "Extract math expression at point."
  (or
   (mathjax-preview--get-inline-math-paren)
   (mathjax-preview--get-block-math-bracket)
   (mathjax-preview--get-inline-math-dollar)
   (mathjax-preview--get-block-math-dollar)))

(defun mathjax-preview--highlight-math-expr (start end)
  "Highlight captured math expression between START and END for three second."
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'face `(:background ,mathjax-preview-overlay-color :extend t))
    (run-with-timer mathjax-preview-overlay-duration nil #'delete-overlay ov)))

(defun mathjax-preview--render-to-svg (input)
  "Render the MathJax expression INPUT string to SVG and return it as a string."
  (let ((output-buf (generate-new-buffer " *mathjax-temp-output*")))
    (unwind-protect
        (let ((exit-code (call-process mathjax-preview-rendermj-exec-path nil output-buf nil input))
              (output (with-current-buffer output-buf (string-trim (buffer-string)))))
          (if (= exit-code 0)
              output
            (let ((err-msg output))
              (if (string-empty-p err-msg) "Unknown error" err-msg))))
      (when (get-buffer output-buf)
        (kill-buffer output-buf)))))

(defun mathjax-preview--render (input)
  "Render INPUT to SVG and display it in a bottom window."
  (when (mathjax-preview--check-executable)
    (let ((output (and input (mathjax-preview--render-to-svg input))))
      (cond
       ((not input)
        (let ((msg "No valid MathJax expression found at point."))
          (mathjax-preview--update-buffer msg)))
       ((not (string-prefix-p "<svg" output))
        (let ((msg (format "MathJax rendering failed: %s" output)))
          (mathjax-preview--update-buffer msg)))
       (t
        (let ((svg (create-image output 'svg t :scale 1.2)))
          (mathjax-preview--update-buffer svg)))))))

(defun mathjax-preview--update-buffer (content)
  "Display CONTENT (either svg or error message) in the preview buffer."
  (with-current-buffer (get-buffer-create mathjax-preview-buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (cond
       ((imagep content)
        (let ((svg content))
          (insert "\n")
          (insert (propertize " "
                              'display
                              `(space :width ,mathjax-preview-margin-left)))
          (insert-image svg)
          (insert "\n")))
       ((stringp content)
        (let ((err content))
          (insert "\n" err "\n"))))

      (goto-char (point-min))
      (setq-local cursor-type nil)
      (hl-line-mode -1)
      (local-set-key (kbd "q") #'quit-window)
      (setq buffer-read-only t)))
  (mathjax-preview--show-window content))

(defun mathjax-preview--compute-height (content)
  "Compute CONTENT height in number of lines."
  (cond
   ((imagep content)
    (let* ((img-height-px (cdr (image-size content t)))
          (line-height-px (max 1 (frame-char-height))))
      (ceiling (/ (float img-height-px) line-height-px))))
   ((stringp content)
    (length (split-string content "\n")))
   (t 1)))

(defun mathjax-preview--show-window (content)
  "Show the preview window displaying CONTENT (image or error text)."
  (let* ((buf (get-buffer mathjax-preview-buffer-name))
         (height-lines (mathjax-preview--compute-height content))
         (win (display-buffer-in-side-window
               buf
               `((side . bottom)
                 (window-height . ,(+ height-lines 3))))))
    (set-window-dedicated-p win t)))

(defun mathjax-preview--close-window ()
  "Close the mathjax-preview window if it is currently visible."
  (let ((window (get-buffer-window mathjax-preview-buffer-name)))
    (when window
      (delete-window window))))

;;;###autoload
(defun mathjax-preview-at-point ()
  "Render the MathJax expression at point.
Display the result in a bottom window."
  (interactive)
  (let ((input (mathjax-preview--get-math-at-point)))
    (mathjax-preview--render input)))

(defun mathjax-preview-region ()
  "Render the MathJax expression in region.
Display the result in a bottom window."
  (interactive)
  (if (use-region-p)
      (let* ((start (region-beginning))
             (end (region-end))
             (input (string-trim (buffer-substring-no-properties start end))))
        (mathjax-preview--render input))))

(provide 'mathjax-preview)

;;; mathjax-preview.el ends here
