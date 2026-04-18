# Emacs LTeX+

`lsp-ltex-plus` is a lightweight [lsp-mode](https://github.com/emacs-lsp/lsp-mode) client for **LTeX+**, a powerful grammar and spell checker powered by [LanguageTool](https://languagetool.org/).

*Developed and tested on Emacs 31.0.50. Expected to work on Emacs 29 and later.*

This package allows you to have professional-grade grammar checking in Emacs while you write Markdown, LaTeX, Org-mode, Magit-commit messages, and more — and also checks grammar and spelling inside comments and string literals of 30+ programming languages. It is designed to be an "add-on" server, meaning it runs quietly in the background alongside your existing language servers without interfering with them. With the local backend, checks typically complete fast enough to feel instant while you type — see [Performance](#performance) for measured numbers and a reproducible benchmark.

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
- **Programming Language Support:** Optionally checks grammar and spelling in comments of 30+ programming languages (Python, C, C++, Rust, Java, …), running transparently alongside the primary language server thanks to its add-on design. Disabled by default (matching LTeX+), opt-in via `lsp-ltex-plus-check-programming-languages`.
- **Lightweight & Lazy-loading:** Split into a tiny bootstrap file loaded at Emacs startup and a full client loaded on first use of a supported buffer, so startup time is essentially unaffected.
- **Intuitive API:** A deliberately small surface area — one entry point (`lsp-ltex-plus-enable-for-modes`) plus customisation variables under a consistent `lsp-ltex-plus-` prefix, so configuration is discoverable through `customize-group` or tab-completion.

## Performance

`lsp-ltex-plus` is fast. On an Apple M2, grammar checking a full-page Markdown or Org buffer completes in about **70 ms**, and a longer LaTeX document (around 15 KB) in about **150 ms** — both comfortably inside the threshold that feels instantaneous while typing. The package ships with a small built-in benchmark (`lsp-ltex-plus-show-latency`) that echoes the round-trip time to the minibuffer after every check, so you can reproduce these numbers on your own hardware; see [Measuring Server Latency](#measuring-server-latency) for how to enable it.

Two caveats worth stating honestly:

- **What you *see* on screen is slower than what the server reports.** The figures above measure the round-trip from `textDocument/didChange` to `textDocument/publishDiagnostics`. Between `publishDiagnostics` arriving and the squiggly underline appearing in the buffer, Emacs still has to pass the diagnostic through `lsp-mode`'s idle cadence (`lsp-idle-delay`, default 0.5 s), the full-sync debounce, and the Flycheck / Flymake overlay refresh. With stock settings the visible delay can add several hundred milliseconds on top of the server round-trip. The grammar checker is not the bottleneck in an Emacs session — the display pipeline typically is. Normal users, however, would likely find Emacs' default settings quite acceptable when typing or editing texts. 

  For a snappier response, consider lowering `lsp-idle-delay` (default 0.5 s), `flycheck-idle-change-delay` (default 0.5 s), and `lsp-debounce-full-sync-notifications-interval` (default 1.0 s). The last of these races against a secondary flush path in lsp-mode that fires whenever Emacs is about to send any outgoing LSP message — a completion request, a hover, a periodic `textDocument/documentHighlight` fired by `lsp-on-idle-hook` after `lsp-idle-delay` seconds of inactivity, or even traffic from a co-tenant server on the same buffer. Whichever of the two paths fires first drains the queue, so reducing the interval only starts to bite once it drops below typical inter-message times (~`lsp-idle-delay`). If you want the interval to be the sole flush trigger — useful mainly when benchmarking or reasoning about timing — additionally set `(setq lsp-flush-delayed-changes-before-next-message nil)` to temporarily disable the secondary flush path.
- **A remote LanguageTool server is noticeably slower.** If you point `lsp-ltex-plus-lt-server-uri` at the hosted service, the round-trip stretches to roughly **1–4 seconds** depending on network conditions and how busy the service is. That is the trade-off for Premium-only rules, but the local backend is likely what the majority of users may want for an interactive writing experience.

## Prerequisites

Before using this package, you need:

1.  **LTeX+ Language Server:** This is the core engine that performs the grammar checks. See [Server Installation](#server-installation) below.
2.  **Java:** LTeX+ requires **Java 21** or higher. Most platform-specific releases of LTeX+ include a bundled Java runtime, so you don't necessarily need to install it separately. See [Java Runtime Configuration](#3-java-runtime-configuration) for details.
3.  **Emacs lsp-mode:** This package is an extension for `lsp-mode` (version 6.0 or higher). Therefore, `lsp-mode` must be installed and available before `lsp-ltex-plus` can function.

## Server Installation

The LTeX+ language server is a standalone program. You can install it anywhere on your computer that suits your workflow.

### 1. Download the Server

Download the latest release for your architecture from the [official GitHub releases page](https://github.com/ltex-plus/ltex-ls-plus/releases/latest). 

Choose the file that matches your operating system and CPU architecture:

- **Linux:** `ltex-ls-plus-X.Y.Z-linux-x64.tar.gz` or `ltex-ls-plus-X.Y.Z-linux-aarch64.tar.gz`
- **macOS:** `ltex-ls-plus-X.Y.Z-mac-x64.tar.gz` or `ltex-ls-plus-X.Y.Z-mac-aarch64.tar.gz` (Apple Silicon)
- **Windows:** `ltex-ls-plus-X.Y.Z-windows-x64.zip` or `ltex-ls-plus-X.Y.Z-windows-aarch64.zip`

### 2. Choose an Installation Directory

A common, Emacs-idiomatic place to store such tools is within your `.emacs.d` directory (e.g., `~/.emacs.d/ltex-ls-plus/`). However, you can place it anywhere—for instance, in `/usr/local/bin/` or a dedicated software folder.

Once extracted, the package contains:
- `bin/ltex-ls-plus`: The main executable used by this package.
- `bin/ltex-cli-plus`: A command-line interface for LTeX+.
- `jdk-21.x.y/`: A bundled Java runtime.

### 3. Java Runtime Configuration

LTeX+ is a Java application. By default, the server uses the Java runtime bundled within its own directory. 

- **Recommendation:** Start with the bundled Java runtime. It is guaranteed to be compatible.
- **Using System Java:** If you already have Java 21+ installed and prefer to use it, you can delete the bundled `jdk-21.x.y/` folder. In this case, ensure your `JAVA_HOME` environment variable points to your system Java or explicitly set the path in Emacs:
  ```elisp
  (use-package lsp-ltex-plus
    :custom
    (lsp-ltex-plus-java-path "/path/to/your/java/home"))
  ```

### 4. Make it Discoverable

For `lsp-ltex-plus` to work, Emacs must be able to find the `ltex-ls-plus` binary. You have several options:

- **Symlink or Shim (Recommended):** To avoid cluttering your `PATH` with many individual directories, you can create a symlink or a small shim script in a directory that is already in your `PATH` (such as `~/.local/bin/` or `/usr/local/bin/`).
  
  Example (Linux/macOS symlink):
  ```bash
  ln -s /path/to/ltex-ls-plus/bin/ltex-ls-plus ~/.local/bin/ltex-ls-plus
  ```

  Example (Bash shim script):
  A shim is useful if you need to set environment variables like `JAVA_HOME` specifically for the server:
  ```bash
  #!/bin/bash
  # Save this as ~/.local/bin/ltex-ls-plus and make it executable
  export JAVA_HOME="/path/to/ltex-ls-plus/jdk-21.x.y"
  exec "/path/to/ltex-ls-plus/bin/ltex-ls-plus" "$@"
  ```

- **Direct Configuration:** If you prefer not to modify your system environment, you can point to the executable directly in your Emacs configuration:
  ```elisp
  (use-package lsp-ltex-plus
    :custom
    (lsp-ltex-plus-ls-plus-executable "/path/to/ltex-ls-plus/bin/ltex-ls-plus"))
  ```

- **Update PATH:** Alternatively, add the `bin/` directory of the extracted server to your system `PATH` (via your shell profile) or your Emacs `exec-path`.

## Installation (Emacs Package)

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

The most idiomatic way to use this package is to call `lsp-ltex-plus-enable-for-modes` in your `:init` block. It reads the default list of ~80 supported major modes, records them as the effective enabled set, and installs a single dispatcher on `after-change-major-mode-hook`. The dispatcher activates the client only when `major-mode` exactly matches an enabled mode — no parent-mode leakage. The full package is loaded lazily — only when you first open a file whose major mode is on the list.

```elisp
(use-package lsp-ltex-plus
  :defer t
  :init
  (lsp-ltex-plus-enable-for-modes))
```

### Customizing Supported Modes

`lsp-ltex-plus-major-modes` is the **client's registry of supported modes**. Each entry is a three-element list `(major-mode language-id programming-p)`:

- `major-mode` — the Emacs major mode symbol.
- `language-id` — a **VS Code language identifier**, the string LTeX+ uses to select the correct grammar rules and that the LSP protocol sends in `textDocument/didOpen`. The canonical list is at the [VS Code language identifiers page](https://code.visualstudio.com/docs/languages/identifiers).
- `programming-p` — `nil` for markup and writing modes (LaTeX, Markdown, Org, …), `t` for programming languages (Python, C, Rust, …). This flag controls whether the mode is checked by default or only when `lsp-ltex-plus-check-programming-languages` is enabled.

The registry serves two purposes: it tells the client which buffers to accept, and it provides the language ID to send over the wire. Both are looked up dynamically at activation time, so changes take effect immediately without restarting the server.

`lsp-ltex-plus-enable-for-modes` reads `lsp-ltex-plus-major-modes` to compute the effective set of modes the dispatcher activates on, but its keyword arguments (`:restrict-to`, `:exclude`, `:extend-to`) only control that set — they never modify `lsp-ltex-plus-major-modes` itself. The full registry always stays intact.

This matters in practice: even if you auto-start the server only in Markdown, you can still call `M-x lsp-ltex-plus-mode` in an Org or Python buffer and the client activates without any prompt — because those modes are already in the registry.

**Activate only a specific subset** with `:restrict-to` (whitelist):

```elisp
(use-package lsp-ltex-plus
  :defer t
  :init
  (lsp-ltex-plus-enable-for-modes
    :restrict-to '(org-mode markdown-mode latex-mode LaTeX-mode)))
```

**Drop a few unwanted modes** from the large default list with `:exclude` (blacklist):

```elisp
(use-package lsp-ltex-plus
  :defer t
  :init
  (lsp-ltex-plus-enable-for-modes
    :exclude '(python-mode c-mode c++-mode)))
```

**Add a mode that is not in the built-in list** with `:extend-to`:

```elisp
(use-package lsp-ltex-plus
  :defer t
  :init
  (lsp-ltex-plus-enable-for-modes
    :extend-to '((my-custom-mode "plaintext" nil))))
```

All three keywords can be combined. `:extend-to` entries are always added after `:restrict-to` and `:exclude` are applied, so they are never accidentally dropped:

```elisp
(lsp-ltex-plus-enable-for-modes
  :restrict-to '(org-mode markdown-mode)
  :exclude     '(markdown-mode)
  :extend-to   '((my-custom-mode "plaintext" nil)))
```

If none of the keyword arguments are sufficient and you need to replace the list entirely, set `lsp-ltex-plus-major-modes` directly **before** the `use-package` block (it is a plain `defvar`, not a `defcustom`):

```elisp
(setq lsp-ltex-plus-major-modes
      '((markdown-mode "markdown" nil)
        (org-mode      "org"      nil)
        (text-mode     "plaintext" nil)))

(use-package lsp-ltex-plus
  :defer t
  :init
  (lsp-ltex-plus-enable-for-modes))
```

### Ready-to-go Configuration Example

For a more robust setup using `use-package` and `straight.el`, you can use the following pattern. This example shows how to automatically pull credentials from your system environment variables if you choose to use an online service:

```elisp
(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "username/emacs-ltex-plus")

  :defer t

  :custom
  ;; Uncomment to use the online LanguageTool service.
  ;; If left commented, the local-only server is used (default).
  ;; (lsp-ltex-plus-lt-server-uri "https://api.languagetoolplus.com")

  ;; Opt in to grammar checking inside programming language comments.
  ;; By default only markup languages (LaTeX, Markdown, Org, …) are checked.
  ;; Set to t to also check comments in Python, C, Rust, and all other
  ;; programming languages in lsp-ltex-plus-major-modes.
  (lsp-ltex-plus-check-programming-languages t)

  ;; Apply the "Kind-First" protocol patch to lsp-mode. Strongly recommended
  ;; if you uncomment the remote server URI above — network latency makes
  ;; JSON-RPC ID collisions almost inevitable, which can stall the connection.
  ;; Safe to leave enabled for local use too; benefits every LSP client, not
  ;; only ltex-ls-plus.  See the "Lsp-mode Protocol Patch" section below for
  ;; details.
  (lsp-ltex-plus-apply-kind-first-patch t)

  :init
  ;; Enable lsp-ltex-plus for all supported major modes. The full package
  ;; loads lazily — only when you first open a relevant file.
  (lsp-ltex-plus-enable-for-modes)

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
- `lsp-ltex-plus-additional-rules-enable-picky-rules`: Set to `t` if you want stricter grammar checks (e.g., passive voice detection).
- `lsp-ltex-plus-apply-kind-first-patch`: Set to `t` to enable the protocol deadlock fix (defaults to `nil`). **Strongly recommended if you use a remote server** — see [Communication Stalls — No More Diagnostics](#communication-stalls--no-more-diagnostics) for details.

For the full list of available settings, see [Customization](#customization).

## Usage

Once active, LTeX+ works just like any other LSP server:

- **Diagnostics:** Errors and warnings will be highlighted in your buffer.
- **Code Actions:** Use your standard `lsp-execute-code-action` (usually `s-l a` or `C-c l a`) to:
    - Add a word to your personal dictionary.
    - Disable a specific rule you don't like.
    - Ignore a false positive.

### Toggling grammar checking in a buffer

`lsp-ltex-plus-mode` is a standard Emacs minor mode: `M-x lsp-ltex-plus-mode` toggles it on and off in the current buffer. In practice this means:

- **Disable** in a buffer where it auto-activated — for example, while you write a throwaway draft that you don't want flagged. Diagnostics disappear, the `LTeX+` mode-line lighter is removed, and running `M-x lsp-ltex-plus-mode` again re-enables it.
- **Enable** in a buffer where automatic activation did not fire — because the major mode was filtered out by `:restrict-to` / `:exclude`, or because it is a programming language and `lsp-ltex-plus-check-programming-languages` is nil. The client starts immediately; you do not need to flip any global variable first.

If the current major mode is not yet in `lsp-ltex-plus-major-modes`, you will be prompted for a [VS Code language identifier](https://code.visualstudio.com/docs/languages/identifiers) (press `RET` to accept the default `"plaintext"`). The mode is then registered and the grammar checker starts immediately. When called from a hook rather than interactively, `"plaintext"` is used silently without prompting.

Deactivation is properly scoped: when the mode is turned off in a buffer where other LSP servers are also active (e.g. `texlab` for LaTeX, `basedpyright` for Python), only the LTeX+ workspace is detached and its diagnostics are cleared; the co-tenant servers keep running untouched. The mode is also re-entrant — toggling it off and on repeatedly in the same buffer works cleanly.

> **Why two tables?**  lsp-mode uses `lsp-language-id-configuration` to decide the language ID string sent over the wire (in `textDocument/didOpen` and similar messages). Most common modes — Markdown, Org, LaTeX, plain text — already have entries there from lsp-mode's built-in defaults, so they work without any extra step. Modes outside that list (e.g. `fundamental-mode`) have no default entry, which is why `lsp-ltex-plus-mode` adds the mode to both `lsp-ltex-plus-major-modes` and `lsp-language-id-configuration` simultaneously.


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

### Full list of supported parameters

| Parameter | Description | Official LTeX+ Setting |
| :--- | :--- | :---: |
| `lsp-ltex-plus-ls-plus-executable` | The name or path of the ltex-ls-plus executable. | |
| `lsp-ltex-plus-debug` | When non-nil, enable verbose logging and JSON-RPC tracing. | |
| `lsp-ltex-plus-major-modes` | Alist of (major-mode . language-id) pairs for lsp-ltex-plus activation. | |
| `lsp-ltex-plus-check-programming-languages` | When non-nil, enable grammar checking in comments of programming languages (disabled by default, matching LTeX+). | |
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
| `lsp-ltex-plus-show-progress` | When non-nil (default), show `ltex-ls-plus` progress updates in the mode line (the `⌛` prefix and optional spinner). Set to nil to silence the flicker on every keystroke without affecting progress rendering for other LSP clients. **Read at startup only** — see the note below the table. | || `lsp-ltex-plus-apply-kind-first-patch` | Whether to apply the 'Kind-First' routing patch to lsp-mode. | |
| `lsp-ltex-plus-show-latency` | When non-nil, echo the server round-trip time after every check. Reports both the cold start (`"Completed initial spell check in N ms."` after `textDocument/didOpen`) and the warm path (`"Completed spell check in N ms."` after each `textDocument/didChange`). Off by default; see [Measuring Server Latency](#measuring-server-latency). **Read at startup only** — see the note below the table. | |
| `lsp-ltex-plus-multi-root` | When non-nil (default), register the client as multi-root so a single `ltex-ls-plus` JVM handles all folders in the session. Leave enabled unless you have a specific need to isolate projects — disabling it spawns one JVM per project root, which can balloon memory usage. | |

> **Note — startup-only settings.** `lsp-ltex-plus-show-progress` and `lsp-ltex-plus-show-latency` are read once when `lsp-ltex-plus` initialises (the first time a supported buffer is opened in the Emacs session). Each one controls an `advice-add` that is installed at that moment only if the flag has the appropriate value; changing the flag afterwards with `setq` or `customize-set-variable` does not install or remove the advice retroactively. To make a mid-session change take effect, restart Emacs or call `M-: (lsp-ltex-plus--setup)` to re-run the client setup.

</details>

## Troubleshooting

All variables mentioned below are standard Emacs customization options. If you use `use-package`, it is recommended to set them within the `:custom` block of your configuration.

### Server Not Found

If Emacs cannot find the `ltex-ls-plus` binary, ensure it is in your system `PATH`. You can verify this within Emacs by evaluating:

```elisp
(executable-find "ltex-ls-plus")
```

If it returns `nil`, you must either add the binary's directory to your `PATH` or provide the absolute path to the executable via `lsp-ltex-plus-ls-plus-executable`. See [Server Installation](#4-make-it-discoverable) for details.

### Communication Stalls — No More Diagnostics

**Symptom:** After a few edits, grammar diagnostics stop updating entirely. The `*lsp-log*` buffer shows no new activity, and the server appears alive but silent.

**Cause:** This is a JSON-RPC ID collision deadlock. LTeX+ sends its own requests to Emacs (e.g., to fetch your configuration) while Emacs is still waiting for a response from the server. When the IDs of these two concurrent messages happen to collide, `lsp-mode`'s default parser misroutes the server's request as a response to a pending client request — causing both sides to wait for each other indefinitely.

This is most likely with a **remote/online server**, where both network latency and the server's own processing time (it is a shared service handling many requests) mean that responses take long enough for message overlaps to become virtually inevitable. It can also occur, though rarely, with the local server.

**Fix:** Enable the Kind-First protocol patch:

```elisp
(use-package lsp-ltex-plus
  :custom
  (lsp-ltex-plus-apply-kind-first-patch t))
```

This makes `lsp-mode` classify messages by their content (presence of a `"method"` field) rather than by ID alone, which is the correct approach per the JSON-RPC specification. See [Lsp-mode Protocol Patch](#lsp-mode-protocol-patch) for the full technical explanation.

### Server Crashes or Memory Issues

The LTeX+ server runs on the Java Virtual Machine (JVM) and can be memory-intensive. If the server crashes unexpectedly or becomes unresponsive, you may need to adjust its memory allocation.

You can control the Java heap size using these variables (values are in megabytes):

- `lsp-ltex-plus-java-initial-heap` (default: `64`): Corresponds to the `-Xms` Java option.
- `lsp-ltex-plus-java-max-heap` (default: `512`): Corresponds to the `-Xmx` Java option.

If you encounter crashes, try increasing the maximum heap size:

```elisp
(use-package lsp-ltex-plus
  :custom
  (lsp-ltex-plus-java-max-heap 1024))
```

While you can experiment with lower values to save system resources, be aware that setting the memory too low may result in an unstable server and frequent crashes. See [Java Runtime Configuration](#3-java-runtime-configuration) for more context.

### Startup Delay After Closing Buffers

**Symptom:** Opening a supported buffer is noticeably slow — grammar checking only kicks in after several seconds, and this happens repeatedly, not just on the first buffer opened after starting Emacs.

**Possible explanation:** `ltex-ls-plus` runs on the JVM and reloads the LanguageTool model at startup, so a cold start takes non-trivial time. This happens when `lsp-keep-workspace-alive` is set to `nil`: `lsp-mode` will shut down the server process when the last buffer attached to it is killed; the next supported buffer you open will have to wait through another cold start.

**Fix:** Ensure `lsp-keep-workspace-alive` is left at its default value of `t`:

```elisp
(setq lsp-keep-workspace-alive t)
```

This keeps the workspace (and the server process) alive even when no buffers are currently attached, so later buffers reuse the warm server and diagnostics appear nearly instantaneously.

Note that this setting only matters when the **last** buffer using `ltex-ls-plus` is killed. As long as at least one supported buffer remains open, the server is still in active use and will not be shut down regardless of this setting.

### High Memory Use with Many Loose Files

**Symptom:** After opening several supported files from unrelated directories, you notice multiple `java` / `ltex-ls-plus` processes running, each claiming several hundred megabytes of RAM. Memory use scales roughly linearly with the number of distinct directories you have touched in the session. You can check from a terminal:

```bash
pgrep -afl 'ltex-ls-plus|ltex.ls.plus'
```

**Possible explanation:** `lsp-ltex-plus-multi-root` may have been set to `nil` somewhere in your configuration. When this variable is `nil`, each distinct project root (the git repo for files inside one, or the file's own directory for loose files) gets its own dedicated server process. With the default (`t`), a single server handles every supported buffer in the session regardless of where the files live.

**Fix:** confirm that `lsp-ltex-plus-multi-root` is at its default value of `t`:

```elisp
(setq lsp-ltex-plus-multi-root t)
```

Unless you have a specific need to isolate projects (e.g., you are experimenting with per-project dictionaries or rule sets and want to keep them from bleeding across projects), leave this enabled. With it set to `t`, a single `ltex-ls-plus` process handles every supported buffer in the session regardless of how many unrelated directories those buffers come from.

### No Grammar Checking in Scratch or Anonymous Buffers

**Symptom:** You write prose in `*scratch*` (or any buffer not visiting a file), enable `lsp-ltex-plus-mode` manually, and nothing happens — no lighter, no diagnostics.

**Explanation:** `lsp-mode` identifies every document by a `file://` URI derived from the buffer's file name. A buffer without a file name cannot form such a URI, so the `textDocument/didOpen` handshake that would carry the buffer contents to the server never happens. The grammar-check engine itself has no problem with orphan buffers — it operates purely on the text content passed over the wire — but the LSP plumbing around it does.

**Workaround:** save the buffer to a file first. Even a throwaway path under `/tmp` is enough to satisfy the URI requirement, after which `lsp-ltex-plus-mode` activates normally.

Supporting orphan buffers without requiring a save is tracked as a future enhancement (synthetic `untitled:` URIs or transparent temp-file mirroring).

## Under the Hood

This section is for users who want to understand how `lsp-ltex-plus` works internally — useful context if you hit an unexpected issue or simply want to know what is happening behind the scenes.

### Measuring Server Latency

If you want to evaluate how fast `ltex-ls-plus` responds on your machine — for example, to compare the local backend against a remote LanguageTool service — enable `lsp-ltex-plus-show-latency`:

```elisp
(use-package lsp-ltex-plus
  :custom
  (lsp-ltex-plus-show-latency t))
```

Two distinct events are reported with different wording so the two regimes can be distinguished at a glance:

| Event | Triggered by | Message |
| :--- | :--- | :--- |
| **Cold start** | `textDocument/didOpen` (first time the buffer is shown to the server) | `Completed initial spell check in N ms.` |
| **Warm path** | `textDocument/didChange` (every edit, debounced) | `Completed spell check in N ms.` |

The cold-start figure reflects a full first-pass check of the entire document. The warm-path figure reflects incremental re-checks served partly from the server's sentence cache. Reporting both lets you quote numbers such as *"first open: X ms, incremental edit: Y ms."*

On a modern laptop with the local backend, incremental edits typically land in around **~60 ms** for short Org / Markdown buffers and **~120 ms** for long LaTeX documents. The cold-start figure is always noticeably higher — the server has to parse the full document from scratch and prime its caches before the first diagnostics come back.

A remote LanguageTool server typically adds 100–300 ms on top of both numbers, depending on network latency and how busy the service is.

> **Important — what the numbers do _not_ include.** Each measurement stops the instant diagnostics *arrive*. It does **not** cover the subsequent rendering step inside Emacs: `lsp-mode`'s diagnostic dispatch, `flycheck` / `flymake` overlay refresh, and any `lsp-ui-sideline` redraw. On typical configurations that rendering path adds several hundred milliseconds on top and is the **dominant contributor to perceived responsiveness** — not the grammar checker itself.
>
> So if the experience feels laggy even though `ltex-ls-plus` reports a small number, the bottleneck is in the UI layer above LSP, not in the grammar checker below it. Tuning `lsp-idle-delay`, `flycheck-idle-change-delay`, and `lsp-ui-sideline-delay` usually helps more than replacing the checker with a faster one.

Because the warm-path message fires after every check (i.e. on essentially every keystroke when `lsp-ltex-plus-check-frequency` is `"edit"` and the debounce interval is small), it is intended for investigation only. Turn the flag off again when you are done measuring. For richer diagnostic output — including entries in the `*lsp-ltex-plus::client*` log buffer and raw JSON-RPC dumps under `/tmp` — see `lsp-ltex-plus-debug` instead; the two flags are independent and can be combined.

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

### How does `lsp-ltex-plus-mode` get set up and activated?

The package is split into two files with different load-time profiles:

- **`lsp-ltex-plus-bootstrap.el`** — tiny, no dependencies. Loaded at `:init` time. Defines the major-mode alist and exposes two autoloaded entry points.
- **`lsp-ltex-plus.el`** — the full client. Loaded lazily, only when a relevant buffer is first opened.

#### Setup: what happens at startup

When the package manager builds `lsp-ltex-plus`, it scans both files for `;;;###autoload` cookies and writes a single autoloads file. This registers lightweight stubs for two symbols — `lsp-ltex-plus-enable-for-modes` and `lsp-ltex-plus-mode` — very early at startup, before any `use-package` form is evaluated. Neither file is loaded yet.

When `use-package` evaluates the `:init` block and calls `(lsp-ltex-plus-enable-for-modes)`, it hits that stub, which loads `lsp-ltex-plus-bootstrap.el` (the tiny file only). The full package is **not** loaded. The function stores the effective set of enabled modes in `lsp-ltex-plus--enabled-modes` and adds a single dispatcher, `lsp-ltex-plus--maybe-activate`, to `after-change-major-mode-hook`.

#### Activation: user opens a file

```
User opens foo.md
  → markdown-mode activates → after-change-major-mode-hook fires
      → lsp-ltex-plus--maybe-activate runs
          → (memq 'markdown-mode lsp-ltex-plus--enabled-modes) → non-nil
          → lsp-ltex-plus-mode called ← hits its autoload stub
              → lsp-ltex-plus.el loads for the first time
                  → (require 'lsp-ltex-plus-bootstrap) → already loaded, no-op
                  → (with-eval-after-load 'lsp-mode ...) registered
              → lsp-ltex-plus-mode body runs → (lsp) called
                  → lsp-mode.el loads → (provide 'lsp-mode) fires
                      → lsp-ltex-plus--setup runs ← client registered
                  → lsp-mode finds ltex-ls-plus, activates it
```

The crucial detail is that `with-eval-after-load` fires **synchronously inside the `require` call**, at the exact moment `lsp-mode.el` evaluates `(provide 'lsp-mode)`. By the time `(lsp)` returns, the client is already registered. There is no race condition.

Thus, with `with-eval-after-load`, we ensure the correct load orders, while no special configuration is required from the user.

#### Why a single dispatcher?

An earlier design registered `lsp-ltex-plus-mode` on each selected mode's hook individually (`text-mode-hook`, `org-mode-hook`, `markdown-mode-hook`, …). It was abandoned for two reasons:

1. **Parent-mode leakage.** Emacs mode hooks inherit along the `define-derived-mode` chain. Opening an `org-mode` buffer also runs `text-mode-hook` (org derives from text via outline), so `:exclude '(org-mode)` could not actually keep the client out of org buffers as long as `text-mode` remained in the enabled set.
2. **Redundant firings.** Every parent hook in the chain ran for each buffer open, calling the minor mode multiple times per buffer — harmless but wasteful.

A grammar and spell checker is a cross-cutting tool expected to run across many writing and programming modes (the default registry ships with 80+), so the realistic baseline is a large enabled set. At that scale a single dispatcher on `after-change-major-mode-hook` that checks `(memq major-mode lsp-ltex-plus--enabled-modes)` is both the correct and the efficient choice — it fires once per mode change and matches by exact identity, so inheritance never leaks.

For users who go the other way and pick only a handful of modes with `:restrict-to`, per-mode hooks would have been roughly as efficient; the remaining advantage of the dispatcher there is purely about `:exclude` correctness when an excluded descendant mode shares a parent with an enabled one. The common situation takes precedence, hence the decision for a single dispatcher. The design stays simple: one hook, one list, exact match.

## Why this package?

Two Emacs LSP clients for LTeX already existed before this package:

- [`emacs-languagetool/lsp-ltex`](https://github.com/emacs-languagetool/lsp-ltex) — the original client, targeted at the older `ltex-ls` server.
- [`emacs-languagetool/lsp-ltex-plus`](https://github.com/emacs-languagetool/lsp-ltex-plus) — a more recent variant by the same author, with function and variable prefixes renamed and the client retargeted at `ltex-ls-plus`. From a reading of its source, the renaming is the only substantive change, so it shares the original's architecture. For that reason the [detailed comparison](docs/comparison-lsp-ltex.md) treats the two as one family and refers to them jointly as `lsp-ltex`.

> **Note on the name collision.** The overlap with `emacs-languagetool/lsp-ltex-plus` is unintentional — I was not aware of that project when I chose the name for this one. The two packages are independent; they simply converged on the same label.

The motivation for writing a new client was practical: on my setup the existing client reliably stalled after a handful of edits — the server stopped publishing diagnostics and a workspace restart was needed to recover. Tracing that symptom led to the JSON-RPC ID-collision issue documented in [Lsp-mode Protocol Patch](#lsp-mode-protocol-patch), and from there to a from-scratch implementation designed specifically for `ltex-ls-plus`. Rebuilding the communication chain — starting with direct command-line interrogation of the server — made it possible to understand exactly how the server and client interact. The result is a lightweight client built around `ltex-ls-plus`'s actual behaviour (bi-directional server-initiated requests, full document sync, server-pulled configuration) rather than inheriting a design tuned for the older `ltex-ls`.

If you want to dig deeper:

- [Detailed Technical Comparison between `lsp-ltex` and `lsp-ltex-plus`](docs/comparison-lsp-ltex.md)
- [What is New with LTeX+?](docs/what-is-new-with-ltex-plus.md)

## License

This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)**. See the `LICENSE` file for details.
