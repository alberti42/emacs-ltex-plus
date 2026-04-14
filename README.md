# Emacs LTeX+

`lsp-ltex-plus` is a lightweight [lsp-mode](https://github.com/emacs-lsp/lsp-mode) client for **LTeX+**, a powerful grammar and spell checker powered by [LanguageTool](https://languagetool.org/).

This package allows you to have professional-grade grammar checking in Emacs while you write Markdown, LaTeX, Org-mode, and more. It is designed to be an "add-on" server, meaning it runs quietly in the background alongside your existing programming language servers.

![LTeX+ in action](screenshot.jpg)
*LTeX+ in action: `C-c l a a` activates the LSP actions, allowing you to choose the suitable correction (e.g., fixing "your" to "you're" in the example above). The key binding can be customized by configuring the `lsp-mode` package.*

For detailed information about the underlying LTeX+ server and its capabilities, please refer to the [official LTeX+ documentation](https://ltex-plus.github.io/ltex-plus/index.html).

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

### Lsp-mode Protocol Patch

LTeX+ frequently initiates its own requests to Emacs (e.g., to fetch your configuration). In high-latency environments—such as when using a **remote server**—these server requests often overlap with Emacs's own requests to the server (like checking a document). 

Because a remote document check can take several hundred milliseconds to complete, there is a very high probability that the server will send a request while Emacs is still waiting for a response. In this scenario, a JSON-RPC "id collision" occurs: `lsp-mode`'s default parser misinterprets the server's new request as a response to its own pending check, causing both sides to hang indefinitely.

This package includes a protocol-level patch that ensures Emacs doesn't just trust request ID numbers (which can collide). Instead, it analyzes the message format to distinguish with certainty whether a message is a new request from the server or a response to a previous client request.

*   **When to use:** **Required** if you use a **remote/online server**. Without this patch, the connection **will** deadlock as soon as a server request overlaps with a pending document check.
*   **When to skip:** Usually not needed if you use the **local server**, as the near-instantaneous response time makes such overlaps extremely unlikely.
*   **Upstream Note:** I plan to submit this fix to `lsp-mode` so it can eventually be integrated into the core package. Because this is a protocol-level improvement, enabling it will generally improve the stability and reliability of **all** your other LSP clients as well.

To enable the patch, add this to your `:custom` block:

```elisp
(use-package lsp-ltex-plus
  :custom
  (lsp-ltex-plus-apply-kind-first-patch t))
```

  ### Key Settings
- `lsp-ltex-plus-language`: The language variant to check (e.g., `"en-US"`, `"de-DE"`).
- `lsp-ltex-plus-diagnostic-severity`: Set to `"warning"`, `"error"`, `"information"`, or `"hint"`.
- `lsp-ltex-plus-additional-rules-enable-picky-rules`: Set to `t` if you want stricter grammar checks (e.g., passive voice detection).

## Customization

`lsp-ltex-plus` supports the full range of customizable parameters provided by the LTeX+ server, alongside unique settings specific to this Emacs client (such as debugging tools). For detailed documentation on the official LTeX+ server settings, visit the [official settings page](https://ltex-plus.github.io/ltex-plus/settings.html).

You can configure these using `:custom` in `use-package`:

```elisp
(use-package lsp-ltex-plus
  :custom
  ;; Client-specific: Enable detailed logging for troubleshooting
  (lsp-ltex-plus-debug t)
  ;; Server-specific: Provide a custom path to the LTeX+ root directory
  (lsp-ltex-plus-ltex-ls-path "~/path/to/ltex-ls-plus-18.6.1")
  ;; Server-specific: Set the language
  (lsp-ltex-plus-language "en-GB"))
```

<details>
<summary><b>Click to see the full list of supported parameters</b></summary>

| Parameter | Description | Official LTeX+ Setting |
| :--- | :--- | :---: |
| `lsp-ltex-plus-ls-plus-executable` | The name or path of the ltex-ls-plus executable. | |
| `lsp-ltex-plus-debug` | When non-nil, enable verbose logging and JSON-RPC tracing. | |
| `lsp-ltex-plus-major-modes` | Alist of (major-mode . language-id) pairs for lsp-ltex-plus activation. | |
| `lsp-ltex-plus-language` | The language (e.g., "en-US") LanguageTool should check against. | X |
| `lsp-ltex-plus-enabled-rules` | Lists of rules that should be enabled (language-specific). | X |
| `lsp-ltex-plus-disabled-rules` | Lists of rules that should be disabled (language-specific). | X |
| `lsp-ltex-plus-bibtex-fields` | List of BibTeX fields whose values are to be checked. | X |
| `lsp-ltex-plus-latex-commands` | List of LaTeX commands to be handled by the LaTeX parser. | X |
| `lsp-ltex-plus-latex-environments` | List of LaTeX environments to be handled by the LaTeX parser. | X |
| `lsp-ltex-plus-markdown-nodes` | List of Markdown node types to be handled by the Markdown parser. | X |
| `lsp-ltex-plus-additional-rules-enable-picky-rules` | Enable LanguageTool rules that are marked as picky. | X |
| `lsp-ltex-plus-additional-rules-mother-tongue` | Optional mother tongue of the user (e.g., "de-DE"). | X |
| `lsp-ltex-plus-additional-rules-language-model` | Optional path to a directory with n-gram language models. | X |
| `lsp-ltex-plus-lt-server-uri` | Base URI for the LanguageTool HTTP server (set to nil for local-only). | X |
| `lsp-ltex-plus-lt-username` | Username for LanguageTool Premium API access. | X |
| `lsp-ltex-plus-lt-api-key` | API key for LanguageTool Premium API access. | X |
| `lsp-ltex-plus-ltex-ls-path` | Path to the root directory of ltex-ls-plus. | X |
| `lsp-ltex-plus-ltex-ls-log-level` | Logging level of the ltex-ls-plus server log. | X |
| `lsp-ltex-plus-java-path` | Path to an existing Java installation (JAVA_HOME). | X |
| `lsp-ltex-plus-java-initial-heap` | Initial size of the Java heap memory (MB). | X |
| `lsp-ltex-plus-java-max-heap` | Maximum size of the Java heap memory (MB). | X |
| `lsp-ltex-plus-sentence-cache-size` | Size of the LanguageTool ResultCache in sentences. | X |
| `lsp-ltex-plus-completion-enabled` | Controls whether completion is enabled (IntelliSense). | X |
| `lsp-ltex-plus-diagnostic-severity` | Severity of the diagnostics (error, warning, information, hint). | X |
| `lsp-ltex-plus-check-frequency` | Controls when documents should be checked (edit, save, manual). | X |
| `lsp-ltex-plus-clear-diagnostics-when-closing-file` | Whether to clear diagnostics when a file is closed. | X |
| `lsp-ltex-plus-apply-kind-first-patch` | Whether to apply the 'Kind-First' routing patch to lsp-mode. | |

</details>

## Usage

Once active, LTeX+ works just like any other LSP server:

- **Diagnostics:** Errors and warnings will be highlighted in your buffer.
- **Code Actions:** Use your standard `lsp-execute-code-action` (usually `s-l a` or `C-c l a`) to:
    - Add a word to your personal dictionary.
    - Disable a specific rule you don't like.
    - Ignore a false positive.

## Why this package?

Previously, the only available option was [lsp-ltex](https://github.com/emacs-languagetool/lsp-ltex). However, that package had not been updated to support the newer **plus** version of the server (`ltex-ls-plus`), and it suffered from persistent instability—at least on my setup using Emacs 31.0.50.

More importantly, I simply could not get the original package to run reliably; in fact, it rarely managed more than a few corrections before the communication with the server crashed. I spent numerous hours trying to diagnose the issue, but I couldn't find a fix. While it might work fine for others on different versions of Emacs, I found it impossible to maintain a stable workflow where the spell checker could survive more than a few edits.

To solve this, I decided to rewrite the client from scratch, specifically modernized for LTeX+. By rebuilding the entire communication chain—starting with direct command-line interrogation of the server—I was able to understand exactly how the server and client interact. This deep dive allowed me to identify and fix the underlying protocol issues described in the [Lsp-mode Protocol Patch](#lsp-mode-protocol-patch) section above. The result is a lightweight, reliable client that handles the full JSON-RPC communication without the deadlocks or crashes I encountered before.

## License

This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)**. See the `LICENSE` file for details.
