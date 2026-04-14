# Emacs LTeX+

`lsp-ltex-plus` is a lightweight [lsp-mode](https://github.com/emacs-lsp/lsp-mode) client for **LTeX+**, a powerful grammar and spell checker powered by [LanguageTool](https://languagetool.org/).

This package allows you to have professional-grade grammar checking in Emacs while you write Markdown, LaTeX, Org-mode, and more. It is designed to be an "add-on" server, meaning it runs quietly in the background alongside your existing programming language servers.

## New to Emacs or LSP?

If you use Emacs for writing—perhaps in the humanities, social sciences, or law—rather than for programming, the term "LSP" might be new to you. Here is a simple way to understand how this works:

*   **The LSP Server (LTeX+):** This is a separate program that runs in the background on your computer. It "reads" your document as you type and identifies errors, much like the grammar checkers in Microsoft Word or Google Docs.
*   **The Bridge (lsp-mode):** This is a popular Emacs package that manages the connection between Emacs and these background programs.
*   **The Client (lsp-ltex-plus):** This is the package you are looking at right now. It acts as the specific "translator" that tells Emacs exactly how to interact with the LTeX+ grammar server.

While this technology was originally built for programmers to find "bugs" in their code, we use it here to provide a powerful, professional-grade assistant for your writing.

## Offline Privacy vs. Online Power

LTeX+ can operate in two distinct ways, depending on your needs:

1.  **Fully Offline (Default):** By default (or by setting `lsp-ltex-plus-lt-server-uri` to `nil`), the grammar checker runs entirely on your local machine. No text ever leaves your computer, making it ideal for sensitive work or when you don't have internet access.
2.  **Remote API:** You can connect to a remote LanguageTool server (like `https://api.languagetoolplus.com`) by setting the `lsp-ltex-plus-lt-server-uri` variable. This can offload the processing from your computer.

**Note on Premium Subscriptions:** If you have a paid LanguageTool Premium account, you can provide your credentials via `lsp-ltex-plus-lt-username` and `lsp-ltex-plus-lt-api-key`. While this provides access to some additional rules, many users find that the local/standard experience is already excellent and hard to distinguish from the premium service.

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

### Ready-to-go Configuration Example

For a more robust setup using `use-package` and `straight.el`, you can use the following pattern. This example shows how to automatically pull credentials from your system environment variables if you choose to use an online service:

```elisp
(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "username/emacs-ltex-plus")

  :custom
  ;; To use the online service, set the URI. 
  ;; If you prefer the local-only server, you can omit this (it defaults to nil).
  (lsp-ltex-plus-lt-server-uri "https://api.languagetoolplus.com")

  ;; Severity can be "warning", "error", "information", or "hint"
  (lsp-ltex-plus-diagnostic-severity "warning")

  :init
  ;; Activate the global mode to automatically hook into all supported files.
  (global-lsp-ltex-plus-mode 1)

  :config
  ;; Optional: Automatically use credentials from environment variables.
  ;; This is safer than hardcoding your API key in your configuration.
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (or (null lsp-ltex-plus-lt-username) (string-empty-p lsp-ltex-plus-lt-username)))
      (setq lsp-ltex-plus-lt-username user))
    (when (and key (or (null lsp-ltex-plus-lt-api-key) (string-empty-p lsp-ltex-plus-lt-api-key)))
      (setq lsp-ltex-plus-lt-api-key key))))
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
