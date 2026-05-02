;;; lsp-ltex-plus.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

;; Author: Andrea Alberti <a.alberti82@gmail.com>
;; Maintainer: Andrea Alberti <a.alberti82@gmail.com>
;; Version: 0.3.1
;; Package-Requires: ((emacs "27.1") (lsp-mode "6.0"))
;; Keywords: lsp, grammar, spelling, convenience
;; URL: https://github.com/alberti42/emacs-ltex-plus

;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at http://mozilla.org/MPL/2.0/.

;;; Commentary:
;;
;; This module provides a self-contained lsp-mode client for ltex-ls-plus,
;; a LanguageTool-based grammar and spell checker.
;;
;; DESIGN PRINCIPLES
;;
;; 1. Add-on Integration: Registered with :add-on? t and :priority -1,
;;    allowing it to run concurrently with primary language servers (e.g.,
;;    texlab or basedpyright) without interference.
;;
;; 2. Transparent Settings: Settings are registered via lsp-register-custom-settings.
;;    The server fetches these via workspace/configuration.  Updating the Lisp
;;    variables (like the dictionary) results in immediate server updates on
;;    the next check.
;;
;; EXTERNAL DEPENDENCIES
;;
;; - ltex-ls-plus binary on PATH
;; - Java runtime (Platform-specific ltex-ls-plus releases include a bundled
;;   Java runtime; otherwise, Java 21+ is required on your system).
;; - Optional: LanguageTool.org account (for premium features)

;;; Code:

(require 'lsp-mode)
(require 'seq)
(require 'cl-lib)
(require 'lsp-ltex-plus-bootstrap)

;; Optional diagnostic front-ends; checked via `bound-and-true-p' at runtime.
(declare-function flycheck-buffer "ext:flycheck")
(declare-function flymake-start "flymake")

;;;; -- Customization ----------------------------------------------------------

(defgroup lsp-ltex-plus nil
  "Customization group for the LTEX+ grammar checker."
  :group 'lsp-mode
  :prefix "lsp-ltex-plus-")

(defcustom lsp-ltex-plus-ls-plus-executable "ltex-ls-plus"
  "The name or path of the ltex-ls-plus executable."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-debug nil
  "When non-nil, enable verbose logging and JSON-RPC tracing.
Enabling this automatically sets `lsp-log-io' to t and creates
detailed log files in /tmp."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-server-input-log "/tmp/ltex-server-input.log"
  "Log file for JSON-RPC input received by the server (from Emacs)."
  :type 'file
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-server-output-log "/tmp/ltex-server-output.log"
  "Log file for JSON-RPC output produced by the server (to Emacs)."
  :type 'file
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-check-programming-languages nil
  "When non-nil, enable grammar checking in programming language comments.

By default this is nil, matching LTeX+\\='s own default: only markup languages
\(LaTeX, Markdown, Org, …) are checked automatically.  Setting this to t lets
the dispatcher activate `lsp-ltex-plus-mode\\=' in buffers whose `major-mode\\='
is flagged as a programming language in `lsp-ltex-plus-major-modes\\=',
enabling comment checking in 30+ languages.

This flag only affects client-side activation.  The `ltex.enabled\\='
list sent to the server always contains every supported language ID from
`lsp-ltex-plus-major-modes\\='; the dispatcher is the authoritative
gate.  Explicit interactive calls (M-x `lsp-ltex-plus-mode\\=') always
proceed regardless of this flag, so on-demand grammar checks work in any
supported buffer without toggling this global setting.

Note: LTeX+ is selective about which comments it checks — the exact rule
is not documented and has to be read off the server source.  What is
verified empirically: standalone comment lines (the delimiter is the
first non-whitespace on the line) followed by a space before the text
are checked; trailing/inline comments after code on the same line are
*not*.  Other cases remain to be explored in the server's comment
regex tables.  The common effect is to minimise false positives from
commented-out code.  Python comments are parsed as reStructuredText;
all others are parsed as Markdown."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-show-progress t
  "When non-nil (default), show ltex-ls-plus progress in the mode line.

Progress updates from `ltex-ls-plus\\=' typically complete in ~100 ms,
so the `⌛\\=' prefix (plus optional spinner animation) can flicker
distractingly on every keystroke.  Users who find this bothersome
should set this variable to nil; progress is then silenced for
ltex-ls-plus only, while other LSP clients continue to render their
progress normally.

The default is t because the filtering mechanism is a narrow
`advice-add\\=' around `lsp-on-progress-modeline\\=' — the default
value of `lsp-progress-function\\=' in `lsp-mode\\='.  Advice on
third-party internals is fragile, so we ship in the pass-through
state by default and leave the opt-in to users who actually mind the
flicker.  Users who have replaced `lsp-progress-function\\=' with a
custom handler are not affected by the advice and should filter on
`lsp--workspace-server-id\\=' themselves."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-show-latency nil
  "When non-nil, echo the server round-trip time after every check.

Two distinct events are measured and reported with different wording
so the two regimes can be distinguished at a glance:

- `textDocument/didOpen\\='   → \"Completed initial spell check in N ms.\"
- `textDocument/didChange\\=' → \"Completed spell check in N ms.\"

The didOpen figure reflects a cold start: the server loads the
document for the first time and runs LanguageTool against the full
text.  The didChange figure reflects the warm path: incremental
re-checks triggered by edits, served from the sentence cache where
possible.  Reporting both makes it easy to quote numbers of the form
\"first open: X ms, incremental edit: Y ms\".

In both cases the timer runs from the moment the notification is
dispatched to ltex-ls-plus until the matching
`textDocument/publishDiagnostics\\=' arrives.

This reports server-side latency only.  It does *not* include the
subsequent `lsp-mode' / flycheck / flymake rendering step that draws
the squiggles on screen, which typically adds several hundred
milliseconds on top and dominates perceived responsiveness in Emacs.

Off by default: with a short debounce interval the didChange message
fires on essentially every keystroke and the constant echo-area
updates are distracting during normal editing.  Enable it when
investigating latency (e.g. comparing local vs. remote LanguageTool
backends) and disable it again afterwards."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-multi-root t
  "When non-nil, register the ltex-ls-plus client as multi-root.

This is the default and recommended setting.  With multi-root enabled,
a single `ltex-ls-plus\\=' JVM process handles all folders in the Emacs
session, avoiding the memory cost of one process per project root.

The feature works on any `ltex-ls-plus\\=' binary: multi-root is a
client-side decision about workspace reuse, and a `ltex-ls-plus\\='
server does not need to know about project roots to check documents
correctly.  When the server advertises `workspaceFolders\\=' support in
its `initialize\\=' response, the `workspaceFolders\\=' init param and
the `workspace/didChangeWorkspaceFolders\\=' notification are a proper
part of the handshake; when it does not, those messages are still sent
and silently ignored per the LSP spec (which `lsp4j'-based servers
honour).  Either way, a single JVM handles every folder.

Set this variable to nil only if you want to disable client-side
workspace reuse — for example, because you want per-project isolation
once the server gains per-project settings."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-language "en-US"
  "The language (e.g., \"en-US\") LanguageTool should check against.
If possible, use a specific variant like \"en-US\" or \"de-DE\" instead of the
generic language code like \"en\" or \"de\" to obtain spelling corrections (in
addition to grammar corrections).

When using the language code \"auto\", LTeX+ will try to detect the language of
the document.  This is not recommended, as only generic languages like \"en\" or
\"de\" will be detected and thus no spelling errors might be reported."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-dictionary nil
  "Additional words accepted as correctly spelled, per language.
This setting is language-specific, so use a plist of the form
\\='(:en-US [\"WORD1\" \"WORD2\"] :de-DE [\"WORD1\" ...]) where the key is
the language code and the value is a vector of words.

Provides the user-seeded counterpart to entries added at runtime via the
_ltex.addToDictionary code action; the two sources are kept separate
and merged on the fly for the server.  For large, hand-curated word
lists, prefer editing the on-disk file (see the External settings
section in the README) rather than stuffing everything into this
variable."
  :type 'plist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-enabled-rules nil
  "Lists of rules that should be enabled (if disabled by default).
This setting is language-specific, so use an object of the format
\\='(:en-US [\"RULE1\" \"RULE2\"] :de-DE [\"RULE1\" ...]) where the key is
the language code and the value is a vector of rule IDs."
  :type 'plist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-disabled-rules nil
  "Lists of rules that should be disabled (if enabled by default).
This setting is language-specific, so use an object of the format
\\='(:en-US [\"RULE1\" \"RULE2\"] :de-DE [\"RULE1\" ...]) where the key is
the language code and the value is a vector of rule IDs."
  :type 'plist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-hidden-false-positives nil
  "False-positive diagnostics that should be hidden from reports.
This setting is language-specific, so use a plist of the form
\\='(:en-US [\"<jsonObject1>\" ...] :de-DE [\"<jsonObject1>\" ...]) where
each string is a JSON object of the form
`{\"rule\":\"RULE_ID\",\"sentence\":\"REGEX\"}' that matches a diagnostic's
rule ID and surrounding sentence regex.

Provides the user-seeded counterpart to entries added at runtime via the
_ltex.hideFalsePositives code action; the two sources are kept
separate and merged on the fly for the server.  See the LTeX+
documentation for the feature:
https://ltex-plus.github.io/ltex-plus/advanced-usage.html#hiding-false-positives-with-regular-expressions"
  :type 'plist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-bibtex-fields nil
  "List of BibTeX fields whose values are to be checked in BibTeX files.
This setting is an object with the field names as keys and Booleans as values,
where true means that the field value should be checked and false means that
the field value should be ignored."
  :type 'alist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-latex-commands nil
  "List of LaTeX commands to be handled by the LaTeX parser.
Listed together with empty arguments (e.g., \"\\ref{}\", \"\\documentclass[]{}\").
This setting is an object with the commands as keys and corresponding actions
as values (\"default\", \"ignore\", \"dummy\", \"pluralDummy\", \"vowelDummy\")."
  :type 'alist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-latex-environments nil
  "List of names of LaTeX environments to be handled by the LaTeX parser.
This setting is an object with the environment names as keys and corresponding
actions as values (\"default\", \"ignore\")."
  :type 'alist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-markdown-nodes nil
  "List of Markdown node types to be handled by the Markdown parser.
This setting is an object with the node types as keys and corresponding actions
as values (\"default\", \"ignore\", \"dummy\", \"pluralDummy\", \"vowelDummy\")."
  :type 'alist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-additional-rules-enable-picky-rules nil
  "Enable LanguageTool rules that are marked as picky.
These are disabled by default, e.g., rules about passive voice, sentence length,
etc., at the cost of more false positives."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-additional-rules-mother-tongue ""
  "Optional mother tongue of the user (e.g., \"de-DE\").
If set, additional rules will be checked to detect false friends. Picky rules
may need to be enabled in order to see an effect."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-additional-rules-language-model ""
  "Optional path to a directory with rules of a language model with n-gram counts.
Set this to the parent directory that contains subdirectories for languages."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-lt-server-uri nil
  "Base URI for the LanguageTool HTTP server.
When nil (default), ltex-ls-plus uses its local, built-in LanguageTool.
To use an online service, set this to e.g., \"https://api.languagetoolplus.com\".
Note: ltex-ls-plus appends /v2/check to this, so omit the /v2 suffix here."
  :type '(choice (const :tag "Local (Built-in)" nil)
                 (string :tag "Remote URI"))
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-lt-username ""
  "Username/email as used to log in at languagetool.org for Premium API access.
Only relevant if `lsp-ltex-plus-lt-server-uri' is set."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-lt-api-key ""
  "API key for Premium API access.
Only relevant if `lsp-ltex-plus-lt-server-uri' is set."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-ltex-ls-path ""
  "Use the path to the root directory of ltex-ls-plus.
It contains bin and lib subdirectories.  If empty, the bundled version is used."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-ltex-ls-log-level "fine"
  "Logging level (verbosity) of the ltex-ls-plus server log.
The levels in descending order are \"severe\", \"warning\", \"info\", \"config\",
\"fine\", \"finer\", and \"finest\"."
  :type '(choice (const "severe") (const "warning") (const "info")
                 (const "config") (const "fine") (const "finer")
                 (const "finest"))
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-java-path ""
  "Path to an existing Java installation on your computer.
Use the same path as you would use for the JAVA_HOME environment variable."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-java-initial-heap 64
  "Initial size of the Java heap memory in megabytes (corresponds to -Xms)."
  :type 'integer
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-java-max-heap 512
  "Maximum size of the Java heap memory in megabytes (corresponds to -Xmx)."
  :type 'integer
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-sentence-cache-size 2000
  "Size of the LanguageTool ResultCache in sentences.
Decreasing this might decrease RAM usage.  If you set this too small, checking
time may increase significantly."
  :type 'integer
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-completion-enabled nil
  "Controls whether completion is enabled (IntelliSense)."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-diagnostic-severity "warning"
  "Severity of the diagnostics corresponding to the grammar and spelling errors.
Possible severities are \"error\", \"warning\", \"information\", and \"hint\"."
  :type '(choice (const "error") (const "warning") (const "information") (const "hint"))
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-check-frequency "edit"
  "Controls when documents should be checked.
- \"edit\": checked when opened or edited (on every keystroke).
- \"save\": checked when opened or saved.
- \"manual\": use commands to manually trigger checks."
  :type '(choice (const "edit") (const "save") (const "manual"))
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-clear-diagnostics-when-closing-file t
  "If set to true, diagnostics of a file are cleared when the file is closed."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-apply-kind-first-patch nil
  "Whether to apply the \\='Kind-First\\=' routing patch to `lsp-mode'.
This patch redefines `lsp--parser-on-message' to prioritize the
\\='method\\=' field, preventing deadlocks when server-initiated
requests (like workspace/configuration) collide with client
requests.

Note: This is a global surgical patch affecting all LSP servers."
  :type 'boolean
  :group 'lsp-ltex-plus)

(defvar lsp-ltex-plus-trace-server "off"
  "Debug setting to log the communication between language client and server.
- \"off\": Don't log any communication.
- \"messages\": Log the type of requests and responses.
- \"verbose\": Log the type and contents of requests and responses.")

;;;; -- Internal State & Logging -----------------------------------------------

(defvar lsp-ltex-plus--start-time nil
  "Timestamp of when `lsp-ltex-plus--setup' was executed.")

(defvar lsp-ltex-plus--dictionary-stored nil
  "Dictionary plist loaded from on-disk file.
File location: `lsp-ltex-plus-dictionary-file'.  Mutated by the
_ltex.addToDictionary code action and persisted back to the file.
Merged with the pristine defcustom `lsp-ltex-plus-dictionary' into
`lsp-ltex-plus--dictionary-merged' for the server.")

(defvar lsp-ltex-plus--enabled-rules-stored nil
  "Enabled-rules plist loaded from on-disk file.
File location: `lsp-ltex-plus-enabled-rules-file'.  Kept separate from
the user-facing defcustom `lsp-ltex-plus-enabled-rules' so `:custom'
values never get written to disk; the server sees the merge of the two
via `lsp-ltex-plus--enabled-rules-merged'.")

(defvar lsp-ltex-plus--disabled-rules-stored nil
  "Disabled-rules plist loaded from on-disk file.
File location: `lsp-ltex-plus-disabled-rules-file'.  Mutated by the
_ltex.disableRules code action and persisted back to the file.  Merged
with the pristine defcustom `lsp-ltex-plus-disabled-rules' into
`lsp-ltex-plus--disabled-rules-merged' for the server.")

(defvar lsp-ltex-plus--hidden-false-positives-stored nil
  "Hidden-false-positives plist loaded from on-disk file.
File location: `lsp-ltex-plus-hidden-false-positives-file'.  Mutated by
the _ltex.hideFalsePositives code action and persisted back.  Merged
with the pristine defcustom `lsp-ltex-plus-hidden-false-positives' into
`lsp-ltex-plus--hidden-false-positives-merged' for the server.")

(defvar lsp-ltex-plus--dictionary-merged nil
  "Merge of custom-defined words and on-disk-defined words.
Custom-defined words are stored in `lsp-ltex-plus-dictionary', while
on-disk-defined words are stored in `lsp-ltex-plus--dictionary-stored'.
Read by the server; recomputed whenever either source changes.")

(defvar lsp-ltex-plus--enabled-rules-merged nil
  "Merge of custom-defined rules and on-disk-defined rules.
Custom-defined rules are stored in `lsp-ltex-plus-enabled-rules', while
on-disk-defined rules are stored in
`lsp-ltex-plus--enabled-rules-stored'.  Read by the server; recomputed
whenever either source changes.")

(defvar lsp-ltex-plus--disabled-rules-merged nil
  "Merge of custom-defined rules and on-disk-defined rules.
Custom-defined rules are stored in `lsp-ltex-plus-disabled-rules', while
on-disk-defined rules are stored in
`lsp-ltex-plus--disabled-rules-stored'.  Read by the server; recomputed
whenever either source changes.")

(defvar lsp-ltex-plus--hidden-false-positives-merged nil
  "Merge of custom-defined false positives and on-disk-defined ones.
Custom-defined false positives are stored in
`lsp-ltex-plus-hidden-false-positives', while on-disk-defined ones are
stored in `lsp-ltex-plus--hidden-false-positives-stored'.  Read by the
server; recomputed whenever either source changes.")

(defun lsp-ltex-plus--elapsed ()
  "Return seconds (float) since `lsp-ltex-plus--start-time' or Emacs init."
  (float-time (time-subtract (current-time)
                             (or lsp-ltex-plus--start-time before-init-time))))

(defun lsp-ltex-plus--log-to-buffer (msg)
  "Write MSG with a timestamp to the *lsp-ltex-plus::client* buffer."
  (with-current-buffer (get-buffer-create "*lsp-ltex-plus::client*")
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "[%10.3f] %s\n" (lsp-ltex-plus--elapsed) msg))
      (setq buffer-read-only t))))

(defmacro lsp-ltex-plus--log (fmt &rest args)
  "Log a formatted message if `lsp-ltex-plus-debug' is enabled.
FMT is the format string, and ARGS are the arguments for it."
  `(when lsp-ltex-plus-debug
     (lsp-ltex-plus--log-to-buffer (format ,fmt ,@args))))

(defun lsp-ltex-plus--enabled-languages ()
  "Return the unique language IDs from `lsp-ltex-plus-major-modes'.
All supported IDs are always returned.  Filtering happens client-side,
via the dispatcher (`lsp-ltex-plus--maybe-activate') and the
`lsp-ltex-plus-mode' guard: the server only ever sees documents for
buffers in which the minor mode is active, so `ltex.enabled' can safely
cover every registered language without triggering unwanted checks.

This design differs from the VS Code LTeX+ extension, which (to the best
of our knowledge) registers a static document selector covering every
supported language and relies on `ltex.enabled' as a server-side runtime
filter: the client always fires `textDocument/didChange' and the server
drops notifications whose language ID is not enabled.  In the Emacs
client the filter lives in the dispatcher instead, so the server only
ever sees documents the user intended to check, and `ltex.enabled' is
effectively a no-op by construction."
  (seq-uniq (mapcar #'cadr lsp-ltex-plus-major-modes) #'string=))

;;;; -- Dictionary Management --------------------------------------------------

(defvar lsp-ltex-plus-dictionary-file
  (expand-file-name "lsp-ltex-plus/stored-dictionary" user-emacs-directory)
  "Path to the external dictionary file (plist format).")

(defvar lsp-ltex-plus-enabled-rules-file
  (expand-file-name "lsp-ltex-plus/enabled-rules" user-emacs-directory)
  "Path to the external enabled rules file (plist format).")

(defvar lsp-ltex-plus-disabled-rules-file
  (expand-file-name "lsp-ltex-plus/disabled-rules" user-emacs-directory)
  "Path to the external disabled rules file (plist format).")

(defvar lsp-ltex-plus-hidden-false-positives-file
  (expand-file-name "lsp-ltex-plus/hidden-false-positives" user-emacs-directory)
  "Path to the external hidden false positives file (plist format).")

(defun lsp-ltex-plus--load-plist (file-path)
  "Load a plist from FILE-PATH.  Return nil if it doesn't exist or fails."
  (lsp-ltex-plus--log "Loading plist from %s" file-path)
  (if (not (file-exists-p file-path))
      (progn (lsp-ltex-plus--log "File not found: %s" file-path) nil)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file-path)
          (read (current-buffer)))
      (error
       (message "[lsp-ltex-plus] Failed to read %s: %S" file-path err)
       nil))))

(defun lsp-ltex-plus--save-plist (plist file-path)
  "Save PLIST to FILE-PATH."
  (lsp-ltex-plus--log "Saving plist to %s" file-path)
  (make-directory (file-name-directory file-path) t)
  (with-temp-file file-path
    (let ((print-length nil)
          (print-level nil))
      (prin1 plist (current-buffer)))))

(defun lsp-ltex-plus--merge-plists (p1 p2)
  "Merge plist P2 into P1 and return the result.
Items in vectors are merged and deduplicated using `string=`."
  (let ((res (copy-sequence p1)))
    (cl-loop for (key val) on p2 by #'cddr do
             (let* ((v1 (plist-get res key))
                    (l1 (if (vectorp v1) (append v1 nil) nil))
                    (l2 (if (vectorp val) (append val nil) nil))
                    (merged (vconcat (seq-uniq (append l1 l2) #'string=))))
               (setq res (plist-put res key merged))))
    res))

(defun lsp-ltex-plus--load-external-settings ()
  "Load external settings from disk and recompute merged views.
Reads each of the four on-disk plist files into its `-stored'
variable, then rebuilds the `-merged' variables by combining the
stored values with the pristine defcustoms.  The defcustoms
themselves are never mutated."
  (setq lsp-ltex-plus--dictionary-stored
        (lsp-ltex-plus--load-plist lsp-ltex-plus-dictionary-file))
  (setq lsp-ltex-plus--enabled-rules-stored
        (lsp-ltex-plus--load-plist lsp-ltex-plus-enabled-rules-file))
  (setq lsp-ltex-plus--disabled-rules-stored
        (lsp-ltex-plus--load-plist lsp-ltex-plus-disabled-rules-file))
  (setq lsp-ltex-plus--hidden-false-positives-stored
        (lsp-ltex-plus--load-plist lsp-ltex-plus-hidden-false-positives-file))
  (lsp-ltex-plus--recompute-merged))

(defun lsp-ltex-plus--recompute-merged ()
  "Rebuild the four `-merged' plists from defcustoms + `-stored' values.
Called after any change to a `-stored' variable (e.g. a code-action
write) and at the end of `lsp-ltex-plus--load-external-settings'."
  (setq lsp-ltex-plus--dictionary-merged
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-dictionary
                                     lsp-ltex-plus--dictionary-stored))
  (setq lsp-ltex-plus--enabled-rules-merged
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-enabled-rules
                                     lsp-ltex-plus--enabled-rules-stored))
  (setq lsp-ltex-plus--disabled-rules-merged
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-disabled-rules
                                     lsp-ltex-plus--disabled-rules-stored))
  (setq lsp-ltex-plus--hidden-false-positives-merged
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-hidden-false-positives
                                     lsp-ltex-plus--hidden-false-positives-stored)))

(defun lsp-ltex-plus--add-to-plist (plist-sym file-path lang items)
  "Add ITEMS for LANG to the plist stored in PLIST-SYM and save to FILE-PATH."
  (lsp-ltex-plus--log "Adding items for %s to %s: %S" lang (symbol-name plist-sym) items)
  (let* ((key (intern (concat ":" lang)))
         (new-data (list key (vconcat items)))
         (merged (lsp-ltex-plus--merge-plists (symbol-value plist-sym) new-data)))
    (set plist-sym merged)
    (lsp-ltex-plus--save-plist merged file-path)))

(defun lsp-ltex-plus-list-dictionary ()
  "Print the merged dictionary currently in effect to the echo area.
The value shown is `lsp-ltex-plus--dictionary-merged' — the union of
the user-provided defcustom `lsp-ltex-plus-dictionary' and the
on-disk `lsp-ltex-plus-dictionary-file'."
  (interactive)
  (message "[lsp-ltex-plus] Dictionary: %S" lsp-ltex-plus--dictionary-merged))

(defun lsp-ltex-plus--notify-ltex-workspaces ()
  "Send `workspace/didChangeConfiguration' to every ltex-ls-plus workspace.
No-op if `lsp-mode' is not loaded or no ltex-ls-plus workspace is active."
  (when (fboundp 'lsp-session)
    (dolist (ws (lsp--session-workspaces (lsp-session)))
      (when (eq 'ltex-ls-plus (lsp--workspace-server-id ws))
        (with-lsp-workspace ws
          (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))))))

(defun lsp-ltex-plus-reload-and-notify-server ()
  "Reload settings from disk and push them to every ltex-ls-plus workspace.
Two steps run together:

  1. Re-read the four external plist files under
     `~/.emacs.d/lsp-ltex-plus/' and rebuild the merged views
     (each merged view combines a file's contents with its
     corresponding user defcustom).
  2. Send `workspace/didChangeConfiguration' to every running
     ltex-ls-plus workspace so the new state takes effect on the
     next check, with no server restart.

Use this whenever you change anything that the server reads —
either by editing one of the on-disk files by hand (bulk-adding
words, removing stale disabled rules) or by setting an
`lsp-ltex-plus-*' defcustom in an active session and wanting the
change applied without reloading."
  (interactive)
  (lsp-ltex-plus--load-external-settings)
  (lsp-ltex-plus--notify-ltex-workspaces)
  (message "[lsp-ltex-plus] Settings reloaded and pushed to server."))

;; Deprecated alias (introduced in v0.3.0, renamed in v0.3.1).
;; The previous name described only the disk-reload half; the function
;; also pushes to the server, which is what makes settings take effect.
(define-obsolete-function-alias 'lsp-ltex-plus-reload-external-settings
  #'lsp-ltex-plus-reload-and-notify-server
  "0.3.1"
  "Renamed to better describe what the function does (reload + push to server).")

;;;; -- Action Handlers --------------------------------------------------------

;; Use abstract `lsp-get' / `lsp-map' (from `lsp-protocol.el') rather low-level
;; than `gethash' / `maphash' directly: lsp-mode represents JSON objects as hash
;; tables by default but as plists when `lsp-use-plists' is set at byte-compile
;; time (the default in Doom Emacs).  The `lsp-get' / `lsp-map' helpers pick the
;; right accessor for the active representation and normalise the key to a
;; string.

(defun lsp-ltex-plus--action-add-to-dictionary (action)
  "Process the _ltex.addToDictionary ACTION from the server."
  (lsp-ltex-plus--log "Action: addToDictionary")
  (let* ((args (lsp-get action :arguments))
         (arg0 (and (vectorp args) (aref args 0)))
         (words-by-lang (and arg0 (lsp-get arg0 :words))))
    (if (null words-by-lang)
        (message "[lsp-ltex-plus] addToDictionary: Malformed arguments %S" args)
      (lsp-map (lambda (lang words-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus--dictionary-stored
                                              lsp-ltex-plus-dictionary-file
                                              lang (append words-arr nil)))
               words-by-lang)
      (lsp-ltex-plus--recompute-merged)))
  ;; Notify server of config change so it re-fetches settings.
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun lsp-ltex-plus--action-disable-rules (action)
  "Process the _ltex.disableRules ACTION."
  (lsp-ltex-plus--log "Action: disableRules")
  (let* ((args (lsp-get action :arguments))
         (arg0 (and (vectorp args) (aref args 0)))
         (rules-by-lang (and arg0 (lsp-get arg0 :ruleIds))))
    (if (null rules-by-lang)
        (message "[lsp-ltex-plus] disableRules: Malformed arguments %S" args)
      (lsp-map (lambda (lang rules-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus--disabled-rules-stored
                                              lsp-ltex-plus-disabled-rules-file
                                              lang (append rules-arr nil)))
               rules-by-lang)
      (lsp-ltex-plus--recompute-merged)))
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun lsp-ltex-plus--action-hide-false-positives (action)
  "Process the _ltex.hideFalsePositives ACTION."
  (lsp-ltex-plus--log "Action: hideFalsePositives")
  (let* ((args (lsp-get action :arguments))
         (arg0 (and (vectorp args) (aref args 0)))
         (fps-by-lang (and arg0 (lsp-get arg0 :falsePositives))))
    (if (null fps-by-lang)
        (message "[lsp-ltex-plus] hideFalsePositives: Malformed arguments %S" args)
      (lsp-map (lambda (lang fps-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus--hidden-false-positives-stored
                                              lsp-ltex-plus-hidden-false-positives-file
                                              lang (append fps-arr nil)))
               fps-by-lang)
      (lsp-ltex-plus--recompute-merged)))
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

;;;; -- Custom Request Handlers ------------------------------------------------

(defun lsp-ltex-plus--request-workspace-specific-configuration (_workspace params)
  "Handle the custom `ltex/workspaceSpecificConfiguration' request.

PARAMS carries `items', a vector of `(scopeUri URI, section SECTION)'.
For each requested item we return the same merged language-keyed maps
(`dictionary', `disabledRules', `enabledRules', `hiddenFalsePositives'),
mirroring VS Code's `WorkspaceConfigurationRequestHandler'.

Per-scope differentiation is intentionally not implemented: every URI
receives the same global merged values.  See the \"Hierarchical scope
support\" item in CLAUDE.md for what would be needed to honour scopeUri.

PARAMS may arrive as either a plist (when `lsp-use-plists' is non-nil)
or a hash-table (the default).  We read it via `lsp-get', the
representation-agnostic accessor exported by lsp-mode, and count the
items defensively for both vector and list shapes.

The result is a vector — one entry per requested item — to match the
shape `vscode-languageclient' returns to the server.  Each entry is a
plist with keyword keys; `json-serialize' converts those to JSON object
keys regardless of `lsp-use-plists', so no hash-table conversion on the
outgoing side is needed (except for the empty-map case handled in the
`let*' below)."
  (lsp-ltex-plus--log "ltex/workspaceSpecificConfiguration request: %S" params)
  (let* ((items (lsp-get params :items))
         (count (cond ((vectorp items) (length items))
                      ((listp items) (length items))
                      (t 0)))
         ;; Bridge an Elisp/JSON ambiguity for the four fields below.
         ;;
         ;; Protocol contract (VS Code's TS type `LanguageSpecificSettingValue')
         ;; says each field is a JSON object — never nullable.  An empty value
         ;; must serialize as `{}', not `null'.
         ;;
         ;; In Elisp, `nil' simultaneously means false, the empty list, the
         ;; empty plist, and the empty alist — one value plays many roles.
         ;; JSON has no such conflation: `null' and `{}' are distinct.  When
         ;; `json-serialize' (Emacs's libjansson wrapper) sees `nil', it has
         ;; to pick one, and it picks `null'.  The Elisp -> JSON mapping is:
         ;;
         ;;   nil                          -> null
         ;;   (:k v ...)   (keyword plist) -> {"k": v, ...}
         ;;   hash-table                   -> {} (or populated object)
         ;;   [a b]        (vector)        -> [a, b]
         ;;   '()          (= nil)         -> null   (NOT [])
         ;;
         ;; The merged vars below are plists keyed by language code (e.g.
         ;; `(:en-US ["foo"])').  When non-empty they serialize correctly as
         ;; JSON objects.  When empty they are `nil', which would emit `null'
         ;; and violate the protocol contract.  Substitute an empty hash-table
         ;; for the `nil' case: a hash-table is unambiguously a JSON object,
         ;; so `json-serialize' emits `{}' regardless of content.  One shared
         ;; empty hash-table is fine — the structure is read-only past this
         ;; point (only `json-serialize' touches it).
         (empty (make-hash-table :test 'equal))
         (entry (list :dictionary           (or lsp-ltex-plus--dictionary-merged           empty)
                      :disabledRules        (or lsp-ltex-plus--disabled-rules-merged        empty)
                      :enabledRules         (or lsp-ltex-plus--enabled-rules-merged         empty)
                      :hiddenFalsePositives (or lsp-ltex-plus--hidden-false-positives-merged empty)))
         (result (make-vector count nil)))
    (dotimes (i count)
      (aset result i (copy-sequence entry)))
    result))


;;;; -- Lsp-mode Patch ---------------------------------------------------------

;; This section contains a protocol-level deadlock fix for `lsp-mode`.
;;
;; PROBLEM: ID COLLISIONS
;;
;; Standard `lsp-mode` routes incoming JSON-RPC messages based on the \\='id\\=' field:
;; 1. If \\='id\\=' is present, it\\='s treated as a RESPONSE to a client request.
;; 2. If \\='method\\=' is present (but no \\='id\\='), it\\='s a NOTIFICATION or REQUEST.
;;
;; LTeX+ frequently initiates its own requests (like `workspace/configuration`)
;; to fetch your dictionary and rules. If the server-initiated request uses an
;; ID that `lsp-mode` is already tracking for a client-side request, `lsp-mode`
;; will misroute the server\\='s request as a response to its own request.
;; This results in a protocol deadlock where both sides are waiting for each
;; other indefinitely.
;;
;; SOLUTION: KIND-FIRST ROUTING
;;
;; The "Kind-First" patch below provides `lsp-core--parser-on-message-patch'
;; which prioritizes the \\='method\\=' field over the \\='id\\=' field.
;; If a \\='method\\=' is present, we know the message is a Request or
;; Notification from the server, regardless of whether the ID happens to
;; collide with an internal Emacs ID.

(defun lsp-core--parser-on-message-patch (json-data workspace)
  "Patched `lsp--parser-on-message' to prioritize \\='method\\=' (Kind-First routing).

JSON-DATA is the parsed JSON message; WORKSPACE is the active lsp workspace.

This patch prevents server-initiated requests from being misrouted as responses
to client requests when IDs collide."
  ;; Define a local helper for JSON parsing. This is an auxiliary function
  ;; used exclusively by the patch to ensure the package remains standalone.
  (cl-labels ((json-get (obj key)
                (cond
                 ((hash-table-p obj)
                  (gethash key obj))
                 ((listp obj)
                  (or (plist-get obj (intern (concat ":" key)))
                      (plist-get obj (intern key))))
                 (t nil))))
    ;; Silently catch and log any errors during message processing. This prevents
    ;; a single malformed message from crashing the entire LSP client.
    (with-demoted-errors "Error processing message %S."
      (with-lsp-workspace workspace
        (let* ((client (lsp--workspace-client workspace))
               (method (json-get json-data "method"))
               (raw-id (json-get json-data "id"))
               (has-method (not (null method)))
               (has-id (not (null raw-id)))
               (has-error (not (null (json-get json-data "error"))))
               ;; Kind-First routing: if a method exists, it's a server-initiated
               ;; message (request/notification) regardless of ID collisions.
               (message-type (cond
                              (has-method (if has-id 'request 'notification))
                              (has-id (if has-error 'response-error 'response))
                              (t 'notification)))
               ;; Normalize response IDs only (client-generated ids are numeric).
               (id (and (memq message-type '(response response-error))
                        raw-id
                        (if (stringp raw-id) (string-to-number raw-id) raw-id))))
          (pcase message-type
            ('response
             (when id
               (let ((handler (gethash id (lsp--client-response-handlers client))))
                 (when handler
                   (let ((callback (nth 0 handler))
                         (cb-method (nth 2 handler))
                         (before-send (nth 4 handler))
                         (result (json-get json-data "result")))
                     (when (lsp--log-io-p cb-method)
                       (lsp--log-entry-new
                        (lsp--make-log-entry cb-method id result 'incoming-resp
                                             (lsp--ms-since before-send))
                        workspace))
                     (when callback
                       (remhash id (lsp--client-response-handlers client))
                       (funcall callback result)))))))
            ('response-error
             (when id
               (let ((handler (gethash id (lsp--client-response-handlers client))))
                 (when handler
                   (let ((err-callback (nth 1 handler))
                         (cb-method (nth 2 handler))
                         (before-send (nth 4 handler))
                         (err (json-get json-data "error")))
                     (when (lsp--log-io-p cb-method)
                       (lsp--log-entry-new
                        (lsp--make-log-entry cb-method id err 'incoming-resp
                                             (lsp--ms-since before-send))
                        workspace))
                     (when err-callback
                       (remhash id (lsp--client-response-handlers client))
                       (funcall err-callback err)))))))
            ('notification
             (lsp--on-notification workspace json-data))
            ('request
             (lsp--on-request workspace json-data))))))))

(defun lsp-ltex-plus--apply-lsp-mode-patch ()
  "Apply the protocol patch to `lsp-mode'.
This patches `lsp--parser-on-message' using :override advice to
prioritize the \\='method\\=' field over \\='id\\=', preventing
deadlocks when server-initiated requests collide with client
response IDs."
  (advice-add 'lsp--parser-on-message :override #'lsp-core--parser-on-message-patch))

(defun lsp-ltex-plus--suppress-progress (orig-fn workspace params)
  "Swallow ltex-ls-plus progress notifications.
Notifications are silenced when `lsp-ltex-plus-show-progress' is nil.
Around-advice for `lsp-on-progress-modeline'; passes PARAMS through to
ORIG-FN for every other WORKSPACE."
  (if (and (not lsp-ltex-plus-show-progress)
           (eq 'ltex-ls-plus (lsp--workspace-server-id workspace)))
      nil
    (funcall orig-fn workspace params)))

;;;; -- Latency Benchmarking ---------------------------------------------------

;; Measure the round-trip between trigger notifications sent to ltex-ls-plus
;; (`textDocument/didOpen', `textDocument/didChange') and the matching
;; `textDocument/publishDiagnostics' that the server returns.  Two independent
;; reporters consume the measurement:
;;
;; - `lsp-ltex-plus-debug'         → timestamped entry in the
;;                                   `*lsp-ltex-plus::client*' log buffer.
;; - `lsp-ltex-plus-show-latency'  → one-line echo-area message; phrased
;;                                   differently for the cold-start (didOpen)
;;                                   and warm-path (didChange) cases so the
;;                                   two numbers can be read off at a glance.
;;
;; The benchmark only reflects server-side latency; the subsequent
;; flycheck/flymake rendering step is not included (see the
;; `lsp-ltex-plus-show-latency' docstring).
;;
;; When lsp-mode flushes a debounced didChange, we time from that flush — not
;; from the user's keystroke — so the number reflects "server became aware of
;; the new state → diagnostics returned", which is what we want to report.
;;
;; The two advices are installed at setup time only when
;; `lsp-ltex-plus-show-latency' is non-nil.  `lsp-ltex-plus-debug' does not gate
;; installation directly; instead, when debug mode is on, the sticky-defaults
;; block inside `lsp-ltex-plus--setup' turns `lsp-ltex-plus-show-latency' on
;; implicitly, so the debug user gets the benchmark "for free".
;;
;; Flipping `lsp-ltex-plus-show-latency' later in the session does not install
;; the advice retroactively: `lsp-ltex-plus--setup' fires once, via
;; `with-eval-after-load', when `lsp-mode' is first loaded, and is not
;; re-entered by `lsp-restart-workspace' (that only restarts the server
;; process).  To start measuring mid-session, either re-evaluate the two
;; `advice-add' forms below or call `lsp-ltex-plus--setup' again (it is
;; idempotent).  This prevent the benchmark — a basic, investigative tool that
;; is off in everyday use — from installing leaving advice on
;; `lsp--on-diagnostics', which is a private `lsp-mode' function whose signature
;; may change between versions.
;;
;; CURRENT LIMITATIONS OF BENCHMARKS
;;
;; A `publishDiagnostics' notification does not carry a reference to the
;; trigger it answers: no JSON-RPC `id' (it is a notification, not a
;; response), and `ltex-ls-plus' does not echo `textDocument.version' in its
;; params (verified in the wire log).  We therefore cannot match a response
;; to its originating request.
;;
;; Practical solution: we keep a *single* pending-measurement slot per
;; workspace.  Every outgoing trigger overwrites it; the first
;; publishDiagnostics that arrives claims whatever is in the slot.  This is the
;; simplest workable scheme with no correlation ID available, and it is correct
;; in the common case (one trigger → one response, with nothing else in flight).
;;
;; CAVEAT: OPTIMISTIC TIMING IN PATHOLOGICAL SITUATIONS
;;
;;  When more than one trigger fires before the first response returns, we
;;  measure from the *most recent* trigger, even though the server may still be
;;  answering an earlier, now-overwritten one.  The reported elapsed is
;;  therefore always ≤ true latency: we can underestimate but never
;;  overestimate.  Example timeline:
;;
;;        t=0    didChange v2 sent     (slot := T0, label incremental)
;;        t=50   didChange v3 sent     (slot := T1, overwrite)
;;        t=100  didChange v4 sent     (slot := T2, overwrite)
;;        t=180  publishDiagnostics    (elapsed reported: 180-100 = 80 ms)
;;
;;    If that diagnostic was really the server's answer to v2 (true latency
;;    180 ms), the bias is 100 ms downward.  If it was the answer to v4, the
;;    report is exact.
;;
;; In practice, this situation is rare.  `lsp-mode' coalesces rapid edits into
;; one didChange because of `lsp-debounce-full-sync-notifications-interval'
;; before flushing, and `ltex-ls-plus' publishes diagnostics for the latest
;; processed version rather than every intermediate one, so the "most recent
;; trigger" slot usually is the one the server is actually answering.  In
;; conclusion: a bias rarely occurs and, when present, is silent and always
;; optimistic.

(defvar lsp-ltex-plus--pending-measurements (make-hash-table :test 'eq)
  "Per-workspace map of pending latency measurements.
Each value is a list (TIMESTAMP BUFFER LABEL) where LABEL is one of
\"initial\" (didOpen) or \"incremental\" (didChange).  Consumed when the
matching `textDocument/publishDiagnostics' arrives.")

(defconst lsp-ltex-plus--benchmark-method-labels
  '(("textDocument/didOpen"   . "initial")
    ("textDocument/didChange" . "incremental"))
  "Mapping of outgoing LSP method names to benchmark labels.")

(defun lsp-ltex-plus--benchmark-outgoing (orig-fn method params)
  "Record the dispatch time of trigger notifications sent to ltex-ls-plus.
Around-advice for `lsp-notify'.  METHOD is matched against
`lsp-ltex-plus--benchmark-method-labels'; unrelated methods are ignored.
ORIG-FN and PARAMS are forwarded unchanged; the advice only observes the
call.

Gated on `lsp-ltex-plus-show-latency' so toggling the flag off mid-session
silences reporting immediately, even though the advice itself remains
installed until Emacs is restarted (it is only installed at startup when
the flag is on in the first place)."
  (when-let* ((lsp-ltex-plus-show-latency)
              ((bound-and-true-p lsp--cur-workspace))
              ((eq 'ltex-ls-plus
                   (lsp--workspace-server-id lsp--cur-workspace)))
              (label (cdr (assoc method
                                 lsp-ltex-plus--benchmark-method-labels))))
    (puthash lsp--cur-workspace
             (list (current-time) (current-buffer) label)
             lsp-ltex-plus--pending-measurements))
  (funcall orig-fn method params))

(defun lsp-ltex-plus--benchmark-diagnostics (workspace &rest _args)
  "Report server latency for ltex-ls-plus after diagnostics arrive.
After-advice for `lsp--on-diagnostics'; WORKSPACE is the workspace that
just published diagnostics.  The echo-area message is emitted
unconditionally (reaching this advice implies
`lsp-ltex-plus-show-latency' was non-nil at setup time); the log-buffer
entry is additionally emitted when `lsp-ltex-plus-debug' is non-nil.

The echo-area wording differs for cold-start (didOpen → \"initial
spell check\") and warm-path (didChange → \"spell check\")
measurements."
  (when (and lsp-ltex-plus-show-latency
             (eq 'ltex-ls-plus (lsp--workspace-server-id workspace)))
    (when-let* ((entry   (gethash workspace lsp-ltex-plus--pending-measurements))
                (ts      (nth 0 entry))
                (buf     (nth 1 entry))
                (label   (nth 2 entry))
                (elapsed (lsp--ms-since ts))
                (phrase  (pcase label
                           ("initial"     "initial spell check")
                           ("incremental" "spell check")
                           (_             "spell check"))))
      (when lsp-ltex-plus-debug
        (lsp-ltex-plus--log "%s → publishDiagnostics: %d ms (buffer: %s)"
                            (if (equal label "initial")
                                "didOpen"
                              "didChange")
                            elapsed (buffer-name buf)))
      (let ((message-log-max nil))
        (message "Completed %s in %d ms." phrase elapsed))
      (remhash workspace lsp-ltex-plus--pending-measurements))))

;;;; -- Lsp-mode Registration --------------------------------------------------

(defun lsp-ltex-plus--setup ()
  "Initialize and register the ltex-ls-plus client with `lsp-mode'."
  (setq lsp-ltex-plus--start-time (current-time))
  (lsp-ltex-plus--log "Initializing lsp-ltex-plus...")

  ;; Register all our modes into lsp-mode's global language-ID table so that
  ;; `lsp-buffer-language' returns a value for them and no "Unable to
  ;; calculate the languageId" warning is emitted.  We only add entries that
  ;; are not already present; lsp-mode's built-in defaults take precedence.
  (dolist (entry lsp-ltex-plus-major-modes)
    (let ((mode    (car entry))
          (lang-id (cadr entry)))
      (unless (assq mode lsp-language-id-configuration)
        (push (cons mode lang-id) lsp-language-id-configuration))))

  (when lsp-ltex-plus-apply-kind-first-patch
    (lsp-ltex-plus--apply-lsp-mode-patch))

  ;; Progress-silencing advice — only installed when the user has opted
  ;; in to hiding ltex-ls-plus progress updates by setting
  ;; `lsp-ltex-plus-show-progress' to nil.  Flipping the flag mid-session
  ;; does not install or remove the advice retroactively; re-evaluate the
  ;; form below (or call `lsp-ltex-plus--setup' again) to change state.
  ;; The advice body additionally re-checks the flag, so a mid-session
  ;; toggle back to t already-installed-advice correctly falls through to
  ;; the original modeline handler.
  (unless lsp-ltex-plus-show-progress
    (advice-add 'lsp-on-progress-modeline :around
                #'lsp-ltex-plus--suppress-progress))

  ;; Apply sticky debug defaults.  Must run before the benchmark advice install
  ;; below, because enabling debug mode here implicitly turns on
  ;; `lsp-ltex-plus-show-latency' — the sole gate for the benchmark advice
  ;; install — so a debug-only user still gets latency readings.
  (when lsp-ltex-plus-debug
    (setq lsp-log-io t)
    (setq lsp-ltex-plus-show-latency t)
    (when (string= lsp-ltex-plus-trace-server "off")
      ;; We already record the raw JSON-RPC exchange to
      ;; /tmp/ltex-server-input.log and /tmp/ltex-server-output.log, therefore
      ;; setting "verbose" here would be too noisy for essentially no gain.  We
      ;; choose messages for pretty-print, which is especially useful for large
      ;; payloads.
      (setq lsp-ltex-plus-trace-server "messages")))

  ;; Latency benchmark advice — only installed if the user asked for it at
  ;; startup (directly via `lsp-ltex-plus-show-latency', or indirectly by
  ;; enabling `lsp-ltex-plus-debug' above).  Flipping the flag mid-session does
  ;; not install the advice retroactively; see the Latency Benchmarking section
  ;; comment for why we prefer not to keep this advice around when nobody is
  ;; measuring.
  (when lsp-ltex-plus-show-latency
    (advice-add 'lsp-notify :around
                #'lsp-ltex-plus--benchmark-outgoing)
    (advice-add 'lsp--on-diagnostics :after
                #'lsp-ltex-plus--benchmark-diagnostics))

  (lsp-ltex-plus--load-external-settings)

  (lsp-ltex-plus--log "Registering settings and client...")
  (lsp-ltex-plus--log "Registering ltex-ls-plus client (priority: -1)...")
  (lsp-register-custom-settings
   `(("ltex.enabled"                             ,(lambda () (vconcat (lsp-ltex-plus--enabled-languages))))
     ("ltex.language"                            lsp-ltex-plus-language)
     ("ltex.dictionary"                          lsp-ltex-plus--dictionary-merged)
     ("ltex.enabledRules"                        lsp-ltex-plus--enabled-rules-merged)
     ("ltex.disabledRules"                       lsp-ltex-plus--disabled-rules-merged)
     ("ltex.hiddenFalsePositives"                lsp-ltex-plus--hidden-false-positives-merged)
     ("ltex.bibtex.fields"                       lsp-ltex-plus-bibtex-fields)
     ("ltex.latex.commands"                      lsp-ltex-plus-latex-commands)
     ("ltex.latex.environments"                  lsp-ltex-plus-latex-environments)
     ("ltex.markdown.nodes"                      lsp-ltex-plus-markdown-nodes)
     ("ltex.additionalRules.enablePickyRules"    lsp-ltex-plus-additional-rules-enable-picky-rules)
     ("ltex.additionalRules.motherTongue"        lsp-ltex-plus-additional-rules-mother-tongue)
     ("ltex.additionalRules.languageModel"       lsp-ltex-plus-additional-rules-language-model)
     ("ltex.languageToolHttpServerUri"           ,(lambda () (or lsp-ltex-plus-lt-server-uri "")))
     ("ltex.languageToolOrg.username"            lsp-ltex-plus-lt-username)
     ("ltex.ltex-ls.languageToolOrgApiKey"       lsp-ltex-plus-lt-api-key)
     ("ltex.ltex-ls.path"                        lsp-ltex-plus-ltex-ls-path)
     ("ltex.ltex-ls.logLevel"                    lsp-ltex-plus-ltex-ls-log-level)
     ("ltex.java.path"                           lsp-ltex-plus-java-path)
     ("ltex.java.initialHeapSize"                lsp-ltex-plus-java-initial-heap)
     ("ltex.java.maximumHeapSize"                lsp-ltex-plus-java-max-heap)
     ("ltex.sentenceCacheSize"                   lsp-ltex-plus-sentence-cache-size)
     ("ltex.completionEnabled"                   lsp-ltex-plus-completion-enabled)
     ("ltex.diagnosticSeverity"                  lsp-ltex-plus-diagnostic-severity)
     ("ltex.checkFrequency"                      lsp-ltex-plus-check-frequency)
     ("ltex.clearDiagnosticsWhenClosingFile"     lsp-ltex-plus-clear-diagnostics-when-closing-file)
     ("ltex.trace.server"                        lsp-ltex-plus-trace-server)))

  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (if (and lsp-ltex-plus-debug (executable-find "tee"))
                           (list "sh" "-c"
                                 (format "tee %s | %s | tee %s"
                                         (shell-quote-argument lsp-ltex-plus-server-input-log)
                                         (shell-quote-argument lsp-ltex-plus-ls-plus-executable)
                                         (shell-quote-argument lsp-ltex-plus-server-output-log)))
                         (list lsp-ltex-plus-ls-plus-executable))))
    ;; `lsp-ltex-plus-mode' is the sole gate: if the minor mode is on,
    ;; the user (or a permitted hook) has decided this buffer should be
    ;; checked.  The programming-language guard lives in the mode body,
    ;; not here, so that explicit interactive calls always succeed.
    :activation-fn (lambda (_file-name _mode)
                     lsp-ltex-plus-mode)
    :language-id (lambda (buf)
                   (cadr (assq (buffer-local-value 'major-mode buf)
                               lsp-ltex-plus-major-modes)))
    :server-id 'ltex-ls-plus
    ;; :add-on? t tells lsp-mode to start this client alongside any already-
    ;; selected primary server (e.g. pyright, texlab) rather than competing
    ;; with it by priority.  Without this flag, lsp-mode would pick only the
    ;; highest-priority client and never start ltex-ls-plus when another server
    ;; is present.  :priority -1 is kept as a safeguard so that if, for some
    ;; reason, ltex-ls-plus ends up in a priority contest, it will never
    ;; "hijack" primary LSP features (Go to Definition, Completion, etc.).
    :add-on? t
    :priority -1
    ;; `:multi-root' is latched at registration time (when this
    ;; `lsp-register-client' call fires).  Changing `lsp-ltex-plus-multi-root'
    ;; after that has no effect until Emacs restarts.
    :multi-root lsp-ltex-plus-multi-root
    :initialized-fn (lambda (_workspace)
                      (lsp-ltex-plus--log "Server initialized; pushing configuration...")
                      (lsp-notify "workspace/didChangeConfiguration"
                                  `(:settings (:ltex (:enabled ,(vconcat (lsp-ltex-plus--enabled-languages))
                                                               :language ,lsp-ltex-plus-language
                                                               :dictionary ,lsp-ltex-plus--dictionary-merged
                                                               :enabledRules ,lsp-ltex-plus--enabled-rules-merged
                                                               :disabledRules ,lsp-ltex-plus--disabled-rules-merged
                                                               :hiddenFalsePositives ,lsp-ltex-plus--hidden-false-positives-merged
                                                               :bibtex (:fields ,lsp-ltex-plus-bibtex-fields)
                                                               :latex (:commands ,lsp-ltex-plus-latex-commands
                                                                                 :environments ,lsp-ltex-plus-latex-environments)
                                                               :markdown (:nodes ,lsp-ltex-plus-markdown-nodes)
                                                               :additionalRules (:enablePickyRules ,lsp-ltex-plus-additional-rules-enable-picky-rules
                                                                                                   :motherTongue ,lsp-ltex-plus-additional-rules-mother-tongue
                                                                                                   :languageModel ,lsp-ltex-plus-additional-rules-language-model)
                                                               :languageToolHttpServerUri ,(or lsp-ltex-plus-lt-server-uri "")
                                                               :languageToolOrg (:username ,lsp-ltex-plus-lt-username)
                                                               :ltex-ls (:languageToolOrgApiKey ,lsp-ltex-plus-lt-api-key
                                                                                                :path ,lsp-ltex-plus-ltex-ls-path
                                                                                                :logLevel ,lsp-ltex-plus-ltex-ls-log-level)
                                                               :java (:path ,lsp-ltex-plus-java-path
                                                                            :initialHeapSize ,lsp-ltex-plus-java-initial-heap
                                                                            :maximumHeapSize ,lsp-ltex-plus-java-max-heap)
                                                               :sentenceCacheSize ,lsp-ltex-plus-sentence-cache-size
                                                               :completionEnabled ,lsp-ltex-plus-completion-enabled
                                                               :diagnosticSeverity ,lsp-ltex-plus-diagnostic-severity
                                                               :checkFrequency ,lsp-ltex-plus-check-frequency
                                                               :clearDiagnosticsWhenClosingFile ,lsp-ltex-plus-clear-diagnostics-when-closing-file
                                                               :trace (:server ,lsp-ltex-plus-trace-server))))))
    :action-handlers
    (lsp-ht ("_ltex.addToDictionary"     #'lsp-ltex-plus--action-add-to-dictionary)
            ("_ltex.disableRules"        #'lsp-ltex-plus--action-disable-rules)
            ("_ltex.hideFalsePositives"  #'lsp-ltex-plus--action-hide-false-positives))
    ;; PoC: advertise the custom capability so ltex-ls-plus issues
    ;; `ltex/workspaceSpecificConfiguration' on every check.  Mirrors
    ;; VS Code's extension.ts initializationOptions.
    :initialization-options
    (lambda ()
      '(:customCapabilities (:workspaceSpecificConfiguration t)))
    :request-handlers
    (lsp-ht ("ltex/workspaceSpecificConfiguration"
             #'lsp-ltex-plus--request-workspace-specific-configuration))))
  (lsp-ltex-plus--log "lsp-ltex-plus--setup completed."))

;;;; -- Activation -------------------------------------------------------------

(defun lsp-ltex-plus--rejoin-workspace ()
  "Attach the current buffer to the ltex-ls-plus workspace only.
Used when `lsp-ltex-plus-mode' activates in a buffer where `lsp-mode'
is already running for another client (e.g. pyright, texlab).  A plain
`(lsp)' would re-send `textDocument/didOpen' to every matching client,
producing a \"redundant open text document\" warning from co-tenants.

If an ltex-ls-plus workspace already exists for the current project,
the buffer is opened in it.  Otherwise, a new ltex-ls-plus connection
is started for the project."
  (let* ((session (lsp-session))
         (client (gethash 'ltex-ls-plus lsp-clients))
         (project-root (when-let* ((buf-file (buffer-file-name))
                                   (root (lsp--calculate-root session buf-file)))
                         (lsp-f-canonical root)))
         (workspace (and client project-root
                         (seq-find
                          (lambda (ws)
                            (eq 'ltex-ls-plus (lsp--workspace-server-id ws)))
                          (gethash project-root
                                   (lsp-session-folder->servers session))))))
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

;;;###autoload
(define-minor-mode lsp-ltex-plus-mode
  "Minor mode for LTEX+ grammar checking via `lsp-mode'.

When enabled, this mode starts the ltex-ls-plus server for the current
buffer.  Run `lsp-ltex-plus-mode-hook' to apply any per-buffer tweaks.

If the current major mode is not in `lsp-ltex-plus-major-modes', it is
registered automatically before the server starts.  When called
interactively the language identifier is requested from the user (default:
\"plaintext\"); when called from a hook or from Lisp, \"plaintext\" is used
silently."
  :lighter " LTeX+"
  :group 'lsp-ltex-plus
  (if lsp-ltex-plus-mode
      (let* ((entry (assq major-mode lsp-ltex-plus-major-modes))
             (programming-p (and entry (nth 2 entry))))
        (if (and programming-p
                 (not lsp-ltex-plus-check-programming-languages)
                 (not (called-interactively-p 'any)))
            ;; Hook-driven activation for a programming-language mode with
            ;; checking disabled: silently bail out.  Explicit interactive
            ;; calls always proceed so the user can run an on-demand check.
            (setq lsp-ltex-plus-mode nil)
          ;; Register the current major mode if it is not yet known to the client.
          ;; Two tables must be updated:
          ;;   1. `lsp-ltex-plus-major-modes' — our own registry, read by the
          ;;      :activation-fn and :language-id lambda in lsp-register-client.
          ;;      This controls which buffers the client accepts and what language
          ;;      ID is sent in textDocument/didOpen.
          ;;   2. `lsp-language-id-configuration' — lsp-mode's own lookup table,
          ;;      used solely by `lsp-buffer-language' for bookkeeping and to
          ;;      suppress an "Unable to calculate the languageId" warning.  It
          ;;      does NOT affect the language ID sent over the wire (our
          ;;      :language-id lambda handles that).  Modes already in lsp-mode's
          ;;      built-in defaults (markdown, org, latex, …) need no entry here;
          ;;      any mode absent from those defaults must be added to silence the
          ;;      warning.
          (unless entry
            (let ((lang-id (if (called-interactively-p 'any)
                               (read-string
                                (format "Language ID for %s (RET for \"plaintext\"): "
                                        major-mode)
                                nil nil "plaintext")
                             "plaintext")))
              ;; New entries added interactively are treated as markup (nil),
              ;; since unknown modes are typically plain-text writing contexts.
              (push (list major-mode lang-id nil) lsp-ltex-plus-major-modes)
              ;; lsp-language-id-configuration uses plain cons pairs.
              (push (cons major-mode lang-id) lsp-language-id-configuration)))
          (if (not (executable-find lsp-ltex-plus-ls-plus-executable))
              (progn
                (message
                 (concat "[lsp-ltex-plus] Aborting: %s not found on PATH.  "
                         "See installation instructions at "
                         "https://github.com/alberti42/emacs-ltex-plus/#server-installation "
                         "or set `lsp-ltex-plus-ls-plus-executable' to the absolute path of the binary.")
                 lsp-ltex-plus-ls-plus-executable)
                (setq lsp-ltex-plus-mode nil))
            (lsp-ltex-plus--log "Enabling LTEX+ in %s" (buffer-name))
            (cond
             ;; lsp-mode not yet loaded — defensive, deferred startup.
             ((not (fboundp 'lsp))
              (lsp-ltex-plus--log "Activation path: lsp-deferred (lsp-mode not loaded)")
              (lsp-deferred))
             ;; lsp-mode already active in this buffer (another client,
             ;; e.g. pyright or texlab).  Attach only the ltex-ls-plus
             ;; workspace to avoid a redundant didOpen to the co-tenants.
             ((bound-and-true-p lsp-mode)
              (lsp-ltex-plus--log "Activation path: rejoin-workspace (lsp-mode already active)")
              (lsp-ltex-plus--rejoin-workspace))
             ;; Another caller (e.g., a `python-mode-hook' that calls
             ;; `lsp-deferred') already scheduled `(lsp)' to run when the
             ;; buffer becomes visible.  Skip our own call — piggyback on
             ;; theirs to avoid a second didOpen to the primary server.
             ;; `ltex-ls-plus' is a registered client with `:add-on? t',
             ;; so their `(lsp)' will pick it up automatically.
             ((bound-and-true-p lsp--buffer-deferred)
              (lsp-ltex-plus--log "Activation path: piggyback (lsp-deferred already scheduled)"))
             ;; lsp-mode loaded but not yet active in this buffer —
             ;; full startup.
             (t
              (lsp-ltex-plus--log "Activation path: (lsp) (first startup)")
              (lsp))))))
    ;; Deactivation.  Two paths depending on co-tenant state:
    ;;   • Sole client — `lsp-disconnect' cleanly tears down lsp-managed-mode,
    ;;     clears diagnostics, and stops the server.
    ;;   • Co-tenants (e.g., basedpyright, texlab) — `lsp-disconnect' would
    ;;     tear them down too, so we surgically remove only the ltex workspace:
    ;;     detach this buffer from it, send `textDocument/didClose' scoped to
    ;;     the ltex workspace, drop the workspace from `lsp--buffer-workspaces',
    ;;     and clean up diagnostics it published.
    (when (bound-and-true-p lsp--buffer-workspaces)
      (let ((ltex-ws (seq-find
                      (lambda (ws)
                        (eq 'ltex-ls-plus (lsp--workspace-server-id ws)))
                      lsp--buffer-workspaces)))
        (when ltex-ws
          (lsp-ltex-plus--log "Disabling LTEX+ in %s" (buffer-name))
          (if (= 1 (length lsp--buffer-workspaces))
              ;; Sole client.
              (lsp-disconnect)
            ;; Co-tenants remain — selective tear-down.
            (with-lsp-workspace ltex-ws
              (cl-callf2 delq (lsp-current-buffer)
                         (lsp--workspace-buffers ltex-ws))
              (with-demoted-errors
                  "[lsp-ltex-plus] Error in didClose: %S"
                (lsp-notify "textDocument/didClose"
                            `(:textDocument ,(lsp--text-document-identifier)))))
            (setq lsp--buffer-workspaces
                  (delete ltex-ws lsp--buffer-workspaces))
            ;; Clear diagnostics in lsp-mode's model, then force the UI to
            ;; refresh — flycheck/flymake cache overlays independently and
            ;; won't drop ltex squiggles until asked to re-check.
            (lsp-diagnostics--workspace-cleanup ltex-ws)
            (run-hooks 'lsp-diagnostics-updated-hook)
            (when (bound-and-true-p flycheck-mode)
              (flycheck-buffer))
            (when (bound-and-true-p flymake-mode)
              (flymake-start))))))))


;; Initialize on lsp-mode load.
(with-eval-after-load 'lsp-mode
  (lsp-ltex-plus--setup))

(provide 'lsp-ltex-plus)
;;; lsp-ltex-plus.el ends here
