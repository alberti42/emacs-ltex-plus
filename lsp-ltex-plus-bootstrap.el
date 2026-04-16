;;; lsp-ltex-plus-bootstrap.el --- Bootstrap for lsp-ltex-plus -*- lexical-binding: t; -*-

;; Author: Andrea Alberti <a.alberti82@gmail.com>
;; Maintainer: Andrea Alberti <a.alberti82@gmail.com>
;; Version: 0.1.1
;; Keywords: lsp, grammar, spelling, convenience
;; URL: https://github.com/alberti42/emacs-ltex-plus

;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at http://mozilla.org/MPL/2.0/.

;;; Commentary:
;;
;; Lightweight bootstrap for lsp-ltex-plus.  This file is the only part of
;; the package that needs to be loaded at Emacs startup.  It defines the
;; default major-mode → language-ID alist and two autoloaded entry points
;; that let the full lsp-ltex-plus package load lazily — only when the user
;; first opens a file whose major mode is in the list.
;;
;; Users normally do not load this file directly; it is pulled in
;; automatically when `lsp-ltex-plus-install-hooks' is called from the
;; `:init' block of `use-package'.

;;; Code:

;; lsp-ltex-plus-mode is defined in lsp-ltex-plus.el, which loads lazily.
;; This declaration silences the byte-compiler without creating a load-time dependency.
(declare-function lsp-ltex-plus-mode "lsp-ltex-plus")


;; This variable is defined here, in the bootstrap file, rather than in the main
;; `lsp-ltex-plus.el', so that it is available at Emacs startup without loading
;; the full package.  `lsp-ltex-plus-install-hooks' reads this list at `:init'
;; time to register per-mode hooks; those hooks are what trigger the lazy load
;; of `lsp-ltex-plus.el' — only when the user first opens a relevant file.
;; If the list lived in `lsp-ltex-plus.el', calling `lsp-ltex-plus-install-hooks'
;; would force the entire package to load immediately, defeating deferred loading.
;;
;; By design, the list ships pre-populated with 80+ entries.  Many similar
;; packages ask the user to opt in to each major mode individually, but that
;; would be an unreasonable burden for a grammar checker that is useful across
;; virtually every language.  The default covers all commonly used modes; users
;; who want a narrower set can trim the list before calling
;; `lsp-ltex-plus-install-hooks' — see `lsp-ltex-plus-ensure-major-modes'.
(defvar lsp-ltex-plus-major-modes
  '((asciidoc-mode          . "asciidoc")
    (bibtex-mode            . "bibtex")
    (c-mode                 . "c")
    (c-ts-mode              . "c")
    (c++-mode               . "cpp")
    (c++-ts-mode            . "cpp")
    (clojure-mode           . "clojure")
    (common-lisp-mode       . "lisp")
    (context-mode           . "context")
    (coffee-mode            . "coffeescript")
    (cperl-mode             . "perl")
    (csharp-mode            . "csharp")
    (csharp-ts-mode         . "csharp")
    (dart-mode              . "dart")
    (elixir-mode            . "elixier")
    (elixir-ts-mode         . "elixier")
    (elm-mode               . "elm")
    (erlang-mode            . "erlang")
    (ess-r-mode             . "r")
    (f90-mode               . "fortran-modern")
    (fortran-mode           . "fortran-modern")
    (fsharp-mode            . "fsharp")
    (gfm-mode               . "markdown")
    (git-commit-mode        . "plaintext")
    (go-mode                . "go")
    (go-ts-mode             . "go")
    (groovy-mode            . "groovy")
    (haskell-mode           . "haskell")
    (html-mode              . "html")
    (java-mode              . "java")
    (java-ts-mode           . "java")
    (javascript-mode        . "javascript")
    (js-mode                . "javascript")
    (js-jsx-mode            . "javascriptreact")
    (js-ts-mode             . "javascript")
    (js2-mode               . "javascript")
    (julia-mode             . "julia")
    (kotlin-mode            . "kotlin")
    (latex-mode             . "latex")
    (LaTeX-mode             . "latex")
    (lisp-mode              . "lisp")
    (lua-mode               . "lua")
    (lua-ts-mode            . "lua")
    (markdown-mode          . "markdown")
    (matlab-mode            . "matlab")
    (mdx-mode               . "mdx")
    (norg-mode              . "neorg")
    (org-mode               . "org")
    (perl-mode              . "perl")
    (perl6-mode             . "perl6")
    (php-mode               . "php")
    (plain-tex-mode         . "latex")
    (poly-noweb+r-mode      . "rsweave")
    (powershell-mode        . "powershell")
    (puppet-mode            . "puppet")
    (python-mode            . "python")
    (python-ts-mode         . "python")
    (quarto-mode            . "quarto")
    (raku-mode              . "perl6")
    (rjsx-mode              . "javascriptreact")
    (Rnw-mode               . "rsweave")
    (rst-mode               . "restructuredtext")
    (ruby-mode              . "ruby")
    (ruby-ts-mode           . "ruby")
    (rust-mode              . "rust")
    (rust-ts-mode           . "rust")
    (rustic-mode            . "rust")
    (scala-mode             . "scala")
    (sh-mode                . "shellscript")
    (bash-ts-mode           . "shellscript")
    (sql-mode               . "sql")
    (swift-mode             . "swift")
    (tex-mode               . "latex")
    (text-mode              . "plaintext")
    (tsx-ts-mode            . "typescriptreact")
    (typescript-mode        . "typescript")
    (typescript-ts-mode     . "typescript")
    (typescript-tsx-mode    . "typescriptreact")
    (typst-mode             . "typ")
    (typst-ts-mode          . "typ")
    (verilog-mode           . "verilog")
    (visual-basic-mode      . "vb"))
  "Alist of (major-mode . language-id) pairs for lsp-ltex-plus activation.
This decides where LTeX+ is active.  Each entry enables the minor mode
for that major mode and registers its language identifier with `lsp-mode'.

The language-id strings are VS Code language identifiers, which are also
the identifiers used by the LSP specification.  The canonical list is at
URL `https://code.visualstudio.com/docs/languages/identifiers'.
Extensions can define additional identifiers beyond that list.

This variable is intentionally not autoloaded.  To read or modify it
before hooks are installed, call `lsp-ltex-plus-ensure-major-modes'
first — that function loads this file as a side effect.")

;;;###autoload
(defun lsp-ltex-plus-ensure-major-modes ()
  "Make `lsp-ltex-plus-major-modes' available for customization.

Calling this function loads the lsp-ltex-plus bootstrap, which defines
`lsp-ltex-plus-major-modes' with its default list of ~80 major-mode →
language-ID pairs.  The function body is intentionally empty: the sole
purpose is to trigger that load via the autoload mechanism.

Call this before your `use-package\\=' block whenever you want to read or
modify `lsp-ltex-plus-major-modes\\=' — for example, to remove a mode:

  (lsp-ltex-plus-ensure-major-modes)
  (setq lsp-ltex-plus-major-modes
        (assoc-delete-all \\='python-mode lsp-ltex-plus-major-modes))

  (use-package lsp-ltex-plus
    :defer t
    :init (lsp-ltex-plus-install-hooks))

Users who are satisfied with the default list do not need to call this
function at all; `lsp-ltex-plus-install-hooks\\=' loads the bootstrap as a
side effect.")

;;;###autoload
(defun lsp-ltex-plus-install-hooks ()
  "Install major-mode hooks for deferred lsp-ltex-plus activation.

Reads `lsp-ltex-plus-major-modes\\=' at call time and adds
`lsp-ltex-plus-mode\\=' to each corresponding major-mode hook.  The full
lsp-ltex-plus package is loaded lazily — only when one of those hooks
fires for the first time.

Because the alist is read once, at call time, any customization of
`lsp-ltex-plus-major-modes\\=' must happen BEFORE this function is called.
With `use-package\\=', place the customization in `:custom\\=' (which runs
before `:init\\='):

  (use-package lsp-ltex-plus
    :defer t
    :custom
    (lsp-ltex-plus-major-modes \\='((markdown-mode . \"markdown\")
                                   (org-mode      . \"org\")))
    :init
    (lsp-ltex-plus-install-hooks))

To modify the default list rather than replace it entirely, call
`lsp-ltex-plus-ensure-major-modes\\=' first — see its docstring."
  (dolist (pair lsp-ltex-plus-major-modes)
    (add-hook (intern (concat (symbol-name (car pair)) "-hook"))
              #'lsp-ltex-plus-mode)))

(provide 'lsp-ltex-plus-bootstrap)
;;; lsp-ltex-plus-bootstrap.el ends here
