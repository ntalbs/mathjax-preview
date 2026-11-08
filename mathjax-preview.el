;; -*- lexical-binding: t; -*-

(require 'rx)
(require 'subr-x)

(defgroup mathjax-preview nil
  "MathJax Preview settings."
  :group 'applications)

(defcustom mathjax-preview-script-path "~/workspace/rendermj/src/index.js"
  "Path to the MathJax Node.js CLI script."
  :type 'file
  :group 'mathjax-preview)

(defcustom mathjax-preview-margin-left 10
  "Left margin for rendered math in pixels."
  :type 'integer
  :group 'mathjax-preview)

(defcustom mathjax-preview-margin-top 5
  "Top margin for rendered math in pixels."
  :type 'integer
  :group 'mathjax-preview)

(defvar mathjax-preview-buffer-name "*MathJax Preview*"
  "Name of the buffer displaying the math SVG preview.")

(defun mathjax-preview--get-math-at-point ()
  "Extract math expression at point"
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

      (mathjax-preview--highlight-math-expr start end)

      (when (and start end latex)
        (list :latex latex)))))

(defun mathjax-preview--highlight-math-expr (start end)
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'face '((t :background "light salmon" :extend t)))
    (run-with-timer 1.0 nil #'delete-overlay ov)))

(defun mathjax-preview--render-to-svg (latex-str)
  "Render the MathJax expression to SVG and return it as a string."
  (let ((output-buf (generate-new-buffer " *mathjax-temp-output*")))
    (unwind-protect
        (let ((exit-code (call-process "node" nil output-buf nil
                                       (expand-file-name mathjax-preview-script-path)
                                       latex-str)))
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

(defun mathjax-preview--update-buffer (img)
  "Open the preview buffer and insert the rendered image."
  (with-current-buffer (get-buffer-create mathjax-preview-buffer-name)
    (let* ((inhibit-read-only t)
           (char-height (max 1 (frame-char-height))))
      (erase-buffer)
      (insert (propertize " " 'display `(space :width 0 :height ,mathjax-preview-margin-top)))
      (insert (propertize " " 'display `(space :width ,mathjax-preview-margin-left)))
      (insert-image img)
      (goto-char (point-min))
      (setq-local cursor-type nil)
      (local-set-key (kbd "q") #'quit-window)
      (setq buffer-read-only t))))

(defun mathjax-preview--show-window (img)
  "Show preview window with proper size."
  (let* ((preview-buf (get-buffer mathjax-preview-buffer-name))
         (window (get-buffer-window preview-buf))
         (img-height-px (cdr (image-size img t)))
         (char-height (max 1 (frame-char-height)))
         (required-lines (+ (ceiling (/ (float img-height-px) char-height)) 4)))
    (unless window
      (setq window (display-buffer-in-side-window preview-buf '((side . bottom)))))
    (window-resize window (- required-lines (window-total-height window)) nil t)))

;;;###autoload
(defun mathjax-preview-at-point ()
  "Render the MathJax math expression at the current cursor position and display it in a bottom window."
  (interactive)
  (let* ((info (mathjax-preview--get-math-at-point))
         (latex (and info (plist-get info :latex)))
         (output-string (and latex (mathjax-preview--render-to-svg latex))))
    (cond
     ((not info)
      (message "No valid MathJax expression found at point."))
     ((not (and output-string (> (length output-string) 0)))
      (message "MathJax rendering failed or produced empty output."))
     (t
      (let ((img (create-image output-string 'svg t :scale 1.1)))
        (mathjax-preview--update-buffer img)
        (mathjax-preview--show-window img))))))

(provide 'mathjax-preview)
