# Toggling `lsp-ltex-plus-mode` On and Off

Status: **not yet implemented** — this document captures the goal, constraints,
and lessons learned so far.

## Goal

The user should be able to:

1. Start Emacs with `lsp-ltex-plus-check-programming-languages` set to `nil`
   (the default).
2. Open a Python file — basedpyright starts normally, ltex-ls-plus does **not**
   start.
3. Run `M-x lsp-ltex-plus-mode` to enable grammar checking on demand.
   Diagnostics from ltex-ls-plus appear alongside basedpyright diagnostics.
4. Run `M-x lsp-ltex-plus-mode` again to disable it.  ltex-ls-plus diagnostics
   (squiggly overlays) disappear; basedpyright continues undisturbed.
5. Repeat steps 3–4 any number of times in the same buffer.

The same toggle must also work for markup buffers (Markdown, LaTeX, Org) where
ltex-ls-plus may be the **sole** LSP client, and for buffers where it runs as
an add-on alongside another server (e.g., texlab + ltex in LaTeX).

## Constraints

### Hook ordering is unpredictable

When a Python buffer opens, both `basedpyright` and `lsp-ltex-plus-mode` are
attached via `python-mode-hook`.  The order in which hooks fire is not
guaranteed.  If pyright's `(lsp)` runs first, it calls `lsp--filter-clients` →
`:activation-fn` for every registered client.  If `:activation-fn` reads
`lsp-ltex-plus-mode` and the mode hook hasn't fired yet, the variable is `nil`
and ltex is filtered out.

**Lesson:** `:activation-fn` must not depend on `lsp-ltex-plus-mode`.  The
original `:activation-fn` (pre-ea8bf24) used only the major-mode list and
the programming flag — this worked correctly with the add-on pattern.

### `(lsp)` re-opens ALL matching workspaces

Calling `(lsp)` when `lsp-mode` is already active sends `textDocument/didOpen`
to **every** matching workspace, including ones that are already connected.
This produces a "Received redundant open text document" warning from servers
like basedpyright.

**Lesson:** On reactivation (ltex was previously connected then disconnected),
we cannot call `(lsp)`.  We need a surgical path that opens the document only
in the ltex workspace.

### Sole client vs. multi-client deactivation

When ltex-ls-plus is the **only** LSP client in a buffer and we disconnect it,
`lsp-mode` must also be disabled — otherwise it complains about having no
active clients.  When other clients remain (e.g., basedpyright), only the ltex
workspace should be removed.

- **Sole client:** `lsp-disconnect` handles this (disables `lsp-managed-mode`,
  `lsp-mode`, clears `lsp--buffer-workspaces`).
- **Multi-client:** Send `textDocument/didClose` scoped to the ltex workspace
  only (via `with-lsp-workspace`), remove the buffer from the workspace's
  buffer list, remove the workspace from `lsp--buffer-workspaces`.

### Diagnostics must be cleared on deactivation

`lsp-diagnostics--workspace-cleanup` clears the diagnostics data in the
workspace hash but does not remove the flycheck/flymake overlays from the
buffer.  After cleanup, the diagnostic UI must be told to refresh:

```elisp
(lsp-diagnostics--workspace-cleanup ltex-ws)
(run-hooks 'lsp-diagnostics-updated-hook)
(when (bound-and-true-p flycheck-mode)
  (flycheck-buffer))
(when (bound-and-true-p flymake-mode)
  (flymake-start))
```

`flycheck-buffer` and `flymake-start` are optional — guard with
`bound-and-true-p` and use `declare-function` with `"ext:flycheck"` /
`"flymake"` to silence the native-compiler.

### `lsp-disabled-clients` is too broad

The original deactivation added `ltex-ls-plus` to `lsp-disabled-clients`.
This is a global variable (even with `setq-local` it creates a buffer-local
binding that may interfere with other logic).  It is better to use a
purpose-built buffer-local flag.

### Preventing auto-restart after deactivation

After the user toggles the mode off, lsp-mode must not restart ltex-ls-plus
(e.g., on the next save or buffer change).  A buffer-local
`lsp-ltex-plus--suppressed` flag checked in `:activation-fn` achieves this
without touching `lsp-disabled-clients`.  The flag is set on deactivation and
cleared on activation.

## Approach considered (partially implemented, then reverted)

The approach used two buffer-local flags and a `lsp-ltex-plus--rejoin-workspace`
function:

### Buffer-local state

- `lsp-ltex-plus--suppressed` — set to `t` on deactivation, `nil` on
  activation.  Checked by `:activation-fn` to block auto-restart.
- `lsp-ltex-plus--was-connected` — set to `t` when ltex is disconnected from
  a buffer.  Used to distinguish reactivation from first activation.

### `:activation-fn`

```elisp
:activation-fn (lambda (_file-name mode)
                 (and (not lsp-ltex-plus--suppressed)
                      (let ((entry (assq mode lsp-ltex-plus-major-modes)))
                        (and entry
                             (or lsp-ltex-plus-check-programming-languages
                                 (not (nth 2 entry)))))))
```

This preserves the add-on pattern (no dependency on `lsp-ltex-plus-mode`) while
blocking restart after deactivation.

### Activation paths

```elisp
(cond
 ;; lsp-mode not yet loaded.
 ((not (fboundp 'lsp))
  (lsp-deferred))
 ;; Reactivation: ltex was previously connected.
 ((and (bound-and-true-p lsp-mode)
       lsp-ltex-plus--was-connected)
  (lsp-ltex-plus--rejoin-workspace))
 ;; First activation or lsp-mode not active.
 (t
  (lsp)))
```

### `lsp-ltex-plus--rejoin-workspace`

Finds the existing ltex workspace in the session (or starts a new connection)
and opens the document only in that workspace:

```elisp
(defun lsp-ltex-plus--rejoin-workspace ()
  (let* ((session (lsp-session))
         (client (gethash 'ltex-ls-plus lsp-clients))
         (project-root (-some-> session
                         (lsp--calculate-root (buffer-file-name))
                         (lsp-f-canonical)))
         (workspace (and client project-root
                         (->> (lsp-session-folder->servers session)
                              (gethash project-root)
                              (--first (eq 'ltex-ls-plus
                                           (lsp--workspace-server-id it)))))))
    (cond
     (workspace
      (lsp--open-in-workspace workspace)
      (cl-pushnew workspace lsp--buffer-workspaces))
     ((and client project-root)
      (let ((new-ws (lsp--start-connection session client project-root)))
        (when new-ws
          (cl-pushnew new-ws lsp--buffer-workspaces))))
     (t
      (lsp--warn "[lsp-ltex-plus] Could not rejoin workspace.")))))
```

### Programming guard change

The guard in the mode body was changed to skip for interactive calls so
`M-x lsp-ltex-plus-mode` works in Python without the programming flag:

```elisp
(if (and programming-p
         (not lsp-ltex-plus-check-programming-languages)
         (not (called-interactively-p 'any)))
    (setq lsp-ltex-plus-mode nil)
  ...)
```

### What went wrong

The individual pieces were tested incrementally but the full combination was
not validated end-to-end.  Activation in Python worked, but the
deactivation/reactivation cycle had remaining issues that were not fully
debugged before the changes were reverted.  The main uncertainty is whether
`lsp-ltex-plus--rejoin-workspace` correctly handles all edge cases (project
root calculation, workspace lookup when no prior workspace exists, interaction
with `lsp--open-in-workspace` and `lsp-managed-mode`).

## Recommended next steps

1. **Start from ea8bf24** (the deactivation commit) which is known to work for
   the basic deactivation case.
2. Apply changes **one at a time**, testing each in isolation:
   a. `declare-function` for flycheck/flymake (compile-time only, no behavior change).
   b. Diagnostic overlay cleanup on deactivation (flycheck/flymake refresh).
   c. Replace `lsp-ltex-plus-mode` in `:activation-fn` with `lsp-ltex-plus--suppressed`.
   d. Programming guard: skip for interactive calls.
   e. Reactivation path: `lsp-ltex-plus--rejoin-workspace`.
3. Test each step against all scenarios:
   - Markdown buffer (sole client): activate → deactivate → reactivate.
   - LaTeX buffer (texlab + ltex): activate → deactivate → reactivate.
   - Python buffer (pyright + ltex, programming flag on): open → verify both
     servers start → deactivate ltex → reactivate ltex.
   - Python buffer (programming flag off): open → verify ltex does not start →
     `M-x lsp-ltex-plus-mode` → verify ltex starts → deactivate → reactivate.
