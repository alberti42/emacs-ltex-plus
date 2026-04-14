# Emacs LTeX+

`lsp-ltex-plus` is a lightweight [lsp-mode](https://github.com/emacs-lsp/lsp-mode) client for **LTeX+**, a powerful grammar and spell checker powered by [LanguageTool](https://languagetool.org/).

This package allows you to have professional-grade grammar checking in Emacs while you write Markdown, LaTeX, Org-mode, and more. It is designed to be an "add-on" server, meaning it runs quietly in the background alongside your existing programming language servers.

## Features

- **Concurrent Execution:** Works simultaneously with other LSP servers (like `texlab` for LaTeX or `pyright` for Python).
- **Smart Persistence:** Words you "add to dictionary" or rules you disable are automatically saved to your Emacs directory and remembered across sessions.
- **Bi-directional Support:** Handles advanced server requests (like dynamic configuration fetching) safely.
- **Highly Configurable:** Easily switch languages, enable "picky" grammar rules, or connect to a premium LanguageTool account.
- **Wide Language Support:** Pre-configured for Markdown, LaTeX, Org, RestructuredText, HTML, BibTeX, and many others.

## Prerequisites

Before using this package, you need:

1.  **LTeX+ Language Server:** Follow the installation instructions at [ltex-plus/ltex-ls-plus](https://github.com/ltex-plus/ltex-ls-plus). Ensure the `ltex-ls-plus` binary is discoverable by Emacs (e.g., by adding it to your system `PATH` or by setting `lsp-ltex-plus-ls-plus-executable` to the full path).
2.  **Java:** Platform-specific LTeX+ releases include a bundled Java runtime. Otherwise, a Java runtime (JRE/JDK) version 21 or higher is required on your system.
3.  **Emacs lsp-mode:** This package is an extension for `lsp-mode`.

## Installation

### Using straight.el

```elisp
(straight-use-package
 '(lsp-ltex-plus :type git :host github :repo "username/emacs-ltex-plus"))
```

### Manual Installation

Download `lsp-ltex-plus.el`, place it in your load path, and require it:

```elisp
(require 'lsp-ltex-plus)
```

## Basic Configuration

The most idiomatic way to use this package is to enable the **global minor mode**. It will automatically activate LTeX+ in any buffer that matches the languages in its supported list.

```elisp
(use-package lsp-ltex-plus
  :init
  (global-lsp-ltex-plus-mode 1))
```

### Customizing Supported Modes

If you want to add or remove support for specific file types, simply customize the `lsp-ltex-plus-major-modes` variable. The global mode will automatically respect your changes for all new buffers:

```elisp
(use-package lsp-ltex-plus
  :init
  (global-lsp-ltex-plus-mode 1)
  :custom
  (lsp-ltex-plus-major-modes '((markdown-mode . "markdown")
                               (org-mode      . "org")
                               (text-mode     . "plaintext"))))
```

### Key Settings

- `lsp-ltex-plus-language`: The language variant to check (e.g., `"en-US"`, `"de-DE"`).
- `lsp-ltex-plus-diagnostic-severity`: Set to `"warning"`, `"error"`, `"information"`, or `"hint"`.
- `lsp-ltex-plus-additional-rules-enable-picky-rules`: Set to `t` if you want stricter grammar checks (e.g., passive voice detection).

## Usage

Once active, LTeX+ works just like any other LSP server:

- **Diagnostics:** Errors and warnings will be highlighted in your buffer.
- **Code Actions:** Use your standard `lsp-execute-code-action` (usually `s-l a` or `C-c l a`) to:
    - Add a word to your personal dictionary.
    - Disable a specific rule you don't like.
    - Ignore a false positive.

## License

This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)**. See the `LICENSE` file for details.
