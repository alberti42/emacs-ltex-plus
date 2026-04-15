# Comparative Analysis: `lsp-ltex-plus` vs. `lsp-ltex`

This document compares `lsp-ltex-plus` (this package) with the original [`lsp-ltex`](https://github.com/emacs-languagetool/lsp-ltex) package. While both act as LSP clients for LTeX, `lsp-ltex-plus` is a modernized, protocol-corrected implementation.

---

## 1. Core Stability: The LSP-Protocol Patch
The most significant technical difference is the inclusion of the **Kind-First** routing patch in `lsp-ltex-plus`. 

*   **The Problem:** The LTeX server frequently initiates its own requests (like `workspace/configuration`) to fetch your settings. Standard `lsp-mode` can misidentify these as responses to previous client requests if IDs collide (common with remote servers or high-latency environments). This leads to a permanent protocol deadlock where both Emacs and the server wait for each other indefinitely.
*   **`lsp-ltex-plus` Solution:**
    ```elisp
    ;; Kind-First routing: if a method exists, it's a server-initiated
    ;; message (request/notification) regardless of ID collisions.
    (message-type (cond
                   (has-method (if has-id 'request 'notification))
                   (has-id (if has-error 'response-error 'response))
                   (t 'notification)))
    ```
    *Source: `lsp-ltex-plus.el`, [lines 491-496](https://github.com/alberti42/emacs-ltex-plus/blob/db37bf3af620fbd21377999b22ad426fe7db2293/lsp-ltex-plus.el#L491-L496)
*   **`lsp-ltex` Status:** Relies on default `lsp-mode` behavior, making it vulnerable to these specific protocol deadlocks.

---

## 2. Modern Major Mode Support
`lsp-ltex-plus` includes built-in support for contemporary formats that the original package lacks or requires manual configuration for.

*   **`lsp-ltex-plus` Unique Support:** `typst-mode`, `quarto-mode`, `norg-mode` (Neorg), and `asciidoc-mode`.
*   **Target:** Specifically tuned for `ltex-ls-plus`, whereas `lsp-ltex` is hardcoded for the older, unmaintained `ltex-ls`.

---

## 2. Configuration Sync Strategy
`lsp-ltex-plus` ensures the server is always in sync with your Emacs settings by proactively pushing updates.

*   **`lsp-ltex-plus` (Proactive Push):** After every code action (like adding a word to the dictionary), it explicitly notifies the server to re-fetch settings.
    ```elisp
    (defun lsp-ltex-plus--action-add-to-dictionary (action)
      ...
      (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))
    ```
    *Source: `lsp-ltex-plus.el`, lines [394-408](https://github.com/alberti42/emacs-ltex-plus/blob/db37bf3af620fbd21377999b22ad426fe7db2293/lsp-ltex-plus.el#L394-L408)*
*   **`lsp-ltex` (Passive):** The original client updates local variables but does not send the `didChangeConfiguration` notification, relying instead on the server's next polling interval or a manual restart.
    ```elisp
    (lsp-defun lsp-ltex--code-action-add-to-dictionary ((&Command :arguments?))
      ...
      (setq lsp-ltex--combined-dictionary
            (lsp-ltex-combine-plists lsp-ltex-dictionary lsp-ltex--stored-dictionary))
      (lsp-message "[INFO] Word added to dictionary."))
    ```
    *Source: `lsp-ltex.el`, [lines 557-568](https://github.com/emacs-languagetool/lsp-ltex/blob/6adc2b4d32a907943a6ce06e2267090241e7af6a/lsp-ltex.el#L557-L568)*

---

## 3. Server Management vs. Core Bridge
The two projects have diverging philosophies regarding server binaries.

*   **`lsp-ltex` (Heavyweight):** Devotes roughly 100 lines of code to downloading, unzipping, and upgrading the `ltex-ls` binary from GitHub. This adds complexity and potential failure points during installation.
*   **`lsp-ltex-plus` (Lightweight/Surgical):** Focuses entirely on the LSP communication bridge. It expects the `ltex-ls-plus` binary to be managed by the system or the user (e.g., via `PATH`), resulting in a more predictable and self-contained package.

---

## 4. Debugging Infrastructure
`lsp-ltex-plus` provides superior visibility into the LSP "wire" protocol.

*   **`lsp-ltex-plus`:** Uses a `tee`-based pipeline to log raw JSON-RPC traffic to `/tmp/ltex-server-input.log` and `/tmp/ltex-server-output.log` when debugging is enabled.
*   **`lsp-ltex`:** Relies solely on `lsp-mode`'s standard logging, which may not capture raw timing or corruption issues at the process level.
