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

(require 'cl-lib)

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
;; who want a narrower set can pass `:restrict-to' or `:exclude' to
;; `lsp-ltex-plus-install-hooks' without touching this variable at all.
(defvar lsp-ltex-plus-major-modes
  ;; Each entry is (MAJOR-MODE LANGUAGE-ID PROGRAMMING-P).
  ;; PROGRAMMING-P is nil for markup/writing languages (checked by default)
  ;; and t for programming languages (opt-in via
  ;; `lsp-ltex-plus-check-programming-languages').
  ;;
  ;; Markup languages (PROGRAMMING-P = nil)
  '((asciidoc-mode          "asciidoc"         nil)
    (bibtex-mode            "bibtex"           nil)
    (context-mode           "context"          nil)
    (gfm-mode               "markdown"         nil)
    (git-commit-mode        "plaintext"        nil)
    (html-mode              "html"             nil)
    (latex-mode             "latex"            nil)
    (LaTeX-mode             "latex"            nil)
    (markdown-mode          "markdown"         nil)
    (mdx-mode               "mdx"              nil)
    (norg-mode              "neorg"            nil)
    (org-mode               "org"              nil)
    (plain-tex-mode         "latex"            nil)
    (poly-noweb+r-mode      "rsweave"          nil)
    (quarto-mode            "quarto"           nil)
    (Rnw-mode               "rsweave"          nil)
    (rst-mode               "restructuredtext" nil)
    (tex-mode               "latex"            nil)
    (text-mode              "plaintext"        nil)
    (typst-mode             "typ"              nil)
    (typst-ts-mode          "typ"              nil)
    ;; Programming languages (PROGRAMMING-P = t)
    (bash-ts-mode           "shellscript"      t)
    (c-mode                 "c"                t)
    (c-ts-mode              "c"                t)
    (c++-mode               "cpp"              t)
    (c++-ts-mode            "cpp"              t)
    (clojure-mode           "clojure"          t)
    (coffee-mode            "coffeescript"     t)
    (common-lisp-mode       "lisp"             t)
    (cperl-mode             "perl"             t)
    (csharp-mode            "csharp"           t)
    (csharp-ts-mode         "csharp"           t)
    (dart-mode              "dart"             t)
    (elixir-mode            "elixier"          t)
    (elixir-ts-mode         "elixier"          t)
    (elm-mode               "elm"              t)
    (erlang-mode            "erlang"           t)
    (ess-r-mode             "r"                t)
    (f90-mode               "fortran-modern"   t)
    (fortran-mode           "fortran-modern"   t)
    (fsharp-mode            "fsharp"           t)
    (go-mode                "go"               t)
    (go-ts-mode             "go"               t)
    (groovy-mode            "groovy"           t)
    (haskell-mode           "haskell"          t)
    (java-mode              "java"             t)
    (java-ts-mode           "java"             t)
    (javascript-mode        "javascript"       t)
    (js-mode                "javascript"       t)
    (js-jsx-mode            "javascriptreact"  t)
    (js-ts-mode             "javascript"       t)
    (js2-mode               "javascript"       t)
    (julia-mode             "julia"            t)
    (kotlin-mode            "kotlin"           t)
    (lisp-mode              "lisp"             t)
    (lua-mode               "lua"              t)
    (lua-ts-mode            "lua"              t)
    (matlab-mode            "matlab"           t)
    (perl-mode              "perl"             t)
    (perl6-mode             "perl6"            t)
    (php-mode               "php"              t)
    (powershell-mode        "powershell"       t)
    (puppet-mode            "puppet"           t)
    (python-mode            "python"           t)
    (python-ts-mode         "python"           t)
    (raku-mode              "perl6"            t)
    (rjsx-mode              "javascriptreact"  t)
    (ruby-mode              "ruby"             t)
    (ruby-ts-mode           "ruby"             t)
    (rust-mode              "rust"             t)
    (rust-ts-mode           "rust"             t)
    (rustic-mode            "rust"             t)
    (scala-mode             "scala"            t)
    (sh-mode                "shellscript"      t)
    (sql-mode               "sql"              t)
    (swift-mode             "swift"            t)
    (tsx-ts-mode            "typescriptreact"  t)
    (typescript-mode        "typescript"       t)
    (typescript-ts-mode     "typescript"       t)
    (typescript-tsx-mode    "typescriptreact"  t)
    (verilog-mode           "verilog"          t)
    (visual-basic-mode      "vb"               t))
  "List of (MAJOR-MODE LANGUAGE-ID PROGRAMMING-P) entries for lsp-ltex-plus.

Each entry registers a major mode with its VS Code language identifier and
category:

  MAJOR-MODE    — Emacs major mode symbol.
  LANGUAGE-ID   — VS Code language identifier string, used in the LSP wire
                  protocol and by LTeX+ to select grammar rules.  The
                  canonical list is at URL
                  `https://code.visualstudio.com/docs/languages/identifiers'.
  PROGRAMMING-P — nil for markup/writing languages (LaTeX, Markdown, Org, …),
                  which LTeX+ checks by default.  t for programming languages
                  (Python, C, Rust, …), which LTeX+ checks only in comments
                  and only when `lsp-ltex-plus-check-programming-languages'
                  is non-nil.

This variable is intentionally not autoloaded; it is defined here so that
`lsp-ltex-plus-install-hooks' can read it at startup without loading the full
`lsp-ltex-plus' package.")

;;;###autoload
(cl-defun lsp-ltex-plus-install-hooks (&key restrict-to exclude extend-to)
  "Install major-mode hooks for deferred lsp-ltex-plus activation.

With no arguments, hooks are installed for every major mode listed in
`lsp-ltex-plus-major-modes\\='.

The effective set of modes is built in three steps:

1. RESTRICT-TO — whitelist.  If non-nil, must be a list of major-mode symbols.
   Only modes present in both RESTRICT-TO and `lsp-ltex-plus-major-modes\\='
   are considered; any symbol not found in the alist is silently skipped.
   Omit this keyword to start from the full default list.

   (lsp-ltex-plus-install-hooks
     :restrict-to \\='(org-mode markdown-mode latex-mode LaTeX-mode))

2. EXCLUDE — blacklist.  If non-nil, must be a list of major-mode symbols.
   Those modes are removed from the list produced by step 1.  Use this to
   drop a few unwanted modes from the large default list without having to
   enumerate all the ones you do want:

   (lsp-ltex-plus-install-hooks
     :exclude \\='(python-mode c-mode c++-mode))

3. EXTEND-TO — additions.  If non-nil, must be a list of
   (MAJOR-MODE LANGUAGE-ID PROGRAMMING-P) entries following the same format
   as `lsp-ltex-plus-major-modes\\='.  These entries are appended after steps
   1 and 2, so they are never excluded.  Use this to hook modes that are
   absent from the built-in list:

   (lsp-ltex-plus-install-hooks
     :extend-to \\='((my-custom-mode \"plaintext\" nil)))

All three keywords may be combined:

  (lsp-ltex-plus-install-hooks
    :restrict-to \\='(org-mode markdown-mode)
    :exclude     \\='(markdown-mode)       ; hypothetical, for illustration
    :extend-to   \\='((my-custom-mode . \"plaintext\")))

The full lsp-ltex-plus package is loaded lazily — only when one of the hooked
major modes is first activated.

Because `lsp-ltex-plus-major-modes\\=' is read at call time, any customization
of that variable must happen BEFORE this function is called.  With
`use-package\\=', place such customization in `:custom\\=' (which runs before
`:init\\='):

  (use-package lsp-ltex-plus
    :defer t
    :custom
    (lsp-ltex-plus-major-modes \\='((markdown-mode \"markdown\" nil)
                                   (org-mode      \"org\"      nil)))
    :init
    (lsp-ltex-plus-install-hooks))"
  (let ((pairs (if restrict-to
                   (delq nil (mapcar (lambda (m) (assq m lsp-ltex-plus-major-modes))
                                     restrict-to))
                 (copy-sequence lsp-ltex-plus-major-modes))))
    (when exclude
      (setq pairs (cl-remove-if (lambda (pair) (memq (car pair) exclude)) pairs)))
    (when extend-to
      (setq pairs (append pairs extend-to)))
    (dolist (pair pairs)
      (add-hook (intern (concat (symbol-name (car pair)) "-hook"))
                #'lsp-ltex-plus-mode))))


(provide 'lsp-ltex-plus-bootstrap)
;;; lsp-ltex-plus-bootstrap.el ends here
