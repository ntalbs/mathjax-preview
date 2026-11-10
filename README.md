# mathjax-preview

MathJax-Preview lets you quickly and easily render and preview MathJax
expressions in a dedicated buffer. It is handy if you want to check
how your math formula is rendered.

## Installation

1. Install `rendermj`
`mathjax-preview` internally uses
[rendermj](https://www.npmjs.com/package/rendermj) command, you need
to install `rendermj` first.
```console
npm install rendermj -g
```
2. Copy `mathjax-preview.el` into `~/.emacs.d/lisp`.
3. Then add the following to `init.el`.
```elisp
(use-package mathjax-preview
  :bind (("C-c j p" . mathjax-preview)))
```

## Usage

This package provides an interactive functions, `mathjax-preview`,
which finds and renders the MathJax expression at point, and display
the result in a preview window. You can also interactively select and
preview specific math expressions.

![](images/mathjax-preview.png)

## Math Syntax Support

`mathjax-preview` supports standard LaTeX math syntax:

* **Block Math**: Wrapped with `$$\n ... $$` or `\[\n ... \]`
* **Inline Math**: Wrapped with `$ ... $` or `\( ... \)`
