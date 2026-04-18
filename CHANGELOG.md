# Change Log

## [0.2.0] - 2026-04-18

### Added
- `lsp-ltex-plus-show-latency` — echo-area benchmark of server round-trip latency (cold-start `didOpen` and warm-path `didChange` reported separately). Debug mode implicitly enables it via sticky defaults. Documented in the new `Performance` and `Measuring Server Latency` README sections.
- `lsp-ltex-plus-show-progress` — toggle to silence ltex-ls-plus progress updates in the mode line without affecting other LSP clients.
- `lsp-ltex-plus-multi-root` — on by default; a single JVM handles every folder in the session. Can be disabled for per-project isolation.
- `lsp-ltex-plus-check-programming-languages` — opt-in to grammar/spell checking in comments of 30+ programming languages (Python, C, Rust, …). Matches LTeX+'s own default (off).
- `lsp-ltex-plus-enable-for-modes` keyword arguments `:restrict-to`, `:exclude`, and `:extend-to` for filtering or extending the default mode set without mutating `lsp-ltex-plus-major-modes`.
- Add-on registration (`:add-on? t`, `:priority -1`) so the client runs concurrently with primary language servers (`texlab`, `basedpyright`, …) instead of competing for priority.
- Helpful message when the `ltex-ls-plus` binary is not on `PATH`, pointing to installation instructions.

### Changed
- Activation uses a single dispatcher on `after-change-major-mode-hook` (exact-match against the enabled-modes set) instead of per-mode hooks, eliminating parent-mode hook leakage (e.g. `text-mode` → `org-mode`).
- `lsp-ltex-plus-major-modes` entries are now 3-tuples `(major-mode language-id programming-p)`.
- Activation paths handle lsp-mode being already active for a co-tenant server (new `lsp-ltex-plus--rejoin-workspace`), piggybacking on an already-scheduled `lsp-deferred`, and the sole-client case.
- Deactivation is re-entrant and correctly scopes `textDocument/didClose`, diagnostic cleanup, and flycheck/flymake refresh to the ltex-ls-plus workspace when co-tenants are present.
- Benchmark and progress advices are installed at setup time only when their corresponding flags are on, so the package leaves no advice on `lsp-mode` internals during normal use.

### Fixed
- Explicit interactive `M-x lsp-ltex-plus-mode` calls now always proceed, regardless of `lsp-ltex-plus-check-programming-languages`, so on-demand checks work in any supported buffer.
- Dispatcher skips buffers without a file name (scratch, temporary buffers) instead of erroring.
- Removed the capability check on `workspace/didChangeWorkspaceFolders` that was forcing single-root fallback on older server builds.

### Documentation
- New README sections: `Performance` (with measured numbers and a reproducible benchmark), `Under the Hood`, and several `Troubleshooting` entries (communication stalls, cold-start delay, high memory, orphan buffers).
- Added `docs/comparison-lsp-ltex.md` (technical side-by-side) and `docs/what-is-new-with-ltex-plus.md` (upstream feature notes).
- Acknowledged the naming collision with `emacs-languagetool/lsp-ltex-plus` (independent projects that converged on the same label; the renamed variant shares `lsp-ltex`'s architecture).

## [0.1.1] - 2026-04-14

### Added
- Implemented protocol-level deadlock fix of `lsp-mode` using `advice-add` with `:override`.
- Added `lsp-core--json-get` helper to ensure the package is standalone and functional.

### Fixed
- Fixed unescaped single quotes in docstrings to resolve byte-compiler warnings.
- Fixed typos in variable names (`lsp-ltex-plus-enabledRules` -> `lsp-ltex-plus-enabled-rules`).
- Resolved "free variable" warnings in `lsp-ltex-plus--setup`.

## [0.1.0] - 2026-04-14

This is the first release of `lsp-ltex-plus` for Emacs!

### Why this package exists

Previously, the only available option was [lsp-ltex](https://github.com/emacs-languagetool/lsp-ltex). However, that package had not been updated to support the newer **plus** version of the server (`ltex-ls-plus`), and it suffered from persistent instability—at least on my setup using Emacs 31.0.50.

More importantly, I simply could not get the original package to run reliably; in fact, it rarely managed more than a few corrections before the communication with the server crashed. I spent numerous hours trying to diagnose the issue, but I couldn't find a fix. While it might work fine for others on different versions of Emacs, I found it impossible to maintain a stable workflow where the spell checker could survive more than a few edits.

To solve this, I decided to rewrite the client from scratch, specifically modernized for LTeX+. By rebuilding the entire communication chain—starting with direct command-line interrogation of the server—I was able to understand exactly how the server and client interact. This deep dive allowed me to identify and fix the underlying protocol issues described in the README. The result is a lightweight, reliable client that handles the full JSON-RPC communication without the deadlocks or crashes I encountered before.
