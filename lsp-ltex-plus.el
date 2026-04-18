;;; lsp-ltex-plus.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

;; Author: Andrea Alberti <a.alberti82@gmail.com>
;; Maintainer: Andrea Alberti <a.alberti82@gmail.com>
;; Version: 0.1.1
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

(defcustom lsp-ltex-plus-buffer-setup-function #'lsp-ltex-plus-buffer-setup-default
  "Function used to configure buffer-local settings when the mode is enabled.
The default value `lsp-ltex-plus-buffer-setup-default' sets sane defaults for
a grammar checker (disabling watchers, auto-guessing roots, etc.)."
  :type 'function
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

(defvar lsp-ltex-plus--dictionary nil
  "In-memory plist of additional dictionary words.")

(defvar lsp-ltex-plus--hidden-false-positives nil
  "List of false-positive diagnostics to hide.")

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
  "Load and merge external settings from disk into current variables."
  (setq lsp-ltex-plus--dictionary
        (lsp-ltex-plus--merge-plists lsp-ltex-plus--dictionary
                                     (lsp-ltex-plus--load-plist lsp-ltex-plus-dictionary-file)))
  (setq lsp-ltex-plus-enabled-rules
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-enabled-rules
                                     (lsp-ltex-plus--load-plist lsp-ltex-plus-enabled-rules-file)))
  (setq lsp-ltex-plus-disabled-rules
        (lsp-ltex-plus--merge-plists lsp-ltex-plus-disabled-rules
                                     (lsp-ltex-plus--load-plist lsp-ltex-plus-disabled-rules-file)))
  (setq lsp-ltex-plus--hidden-false-positives
        (lsp-ltex-plus--merge-plists lsp-ltex-plus--hidden-false-positives
                                     (lsp-ltex-plus--load-plist lsp-ltex-plus-hidden-false-positives-file))))

(defun lsp-ltex-plus--add-to-plist (plist-sym file-path lang items)
  "Add ITEMS for LANG to the plist stored in PLIST-SYM and save to FILE-PATH."
  (lsp-ltex-plus--log "Adding items for %s to %s: %S" lang (symbol-name plist-sym) items)
  (let* ((key (intern (concat ":" lang)))
         (new-data (list key (vconcat items)))
         (merged (lsp-ltex-plus--merge-plists (symbol-value plist-sym) new-data)))
    (set plist-sym merged)
    (lsp-ltex-plus--save-plist merged file-path)))

(defun lsp-ltex-plus-list-dictionary ()
  "Print the current external dictionary content to the echo area."
  (interactive)
  (message "[lsp-ltex-plus] External Dictionary: %S" lsp-ltex-plus--dictionary))

;;;; -- Action Handlers --------------------------------------------------------

(defun lsp-ltex-plus--action-add-to-dictionary (action)
  "Process the _ltex.addToDictionary ACTION from the server."
  (lsp-ltex-plus--log "Action: addToDictionary")
  (let* ((args (gethash "arguments" action))
         (arg0 (and (vectorp args) (aref args 0)))
         (words-by-lang (and arg0 (gethash "words" arg0))))
    (if (null words-by-lang)
        (message "[lsp-ltex-plus] addToDictionary: Malformed arguments %S" args)
      (maphash (lambda (lang words-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus--dictionary
                                              lsp-ltex-plus-dictionary-file
                                              lang (append words-arr nil)))
               words-by-lang)))
  ;; Notify server of config change so it re-fetches settings.
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun lsp-ltex-plus--action-disable-rules (action)
  "Process the _ltex.disableRules ACTION."
  (lsp-ltex-plus--log "Action: disableRules")
  (let* ((args (gethash "arguments" action))
         (arg0 (and (vectorp args) (aref args 0)))
         (rules-by-lang (and arg0 (gethash "ruleIds" arg0))))
    (if (null rules-by-lang)
        (message "[lsp-ltex-plus] disableRules: Malformed arguments %S" args)
      (maphash (lambda (lang rules-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus-disabled-rules
                                              lsp-ltex-plus-disabled-rules-file
                                              lang (append rules-arr nil)))
               rules-by-lang)))
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun lsp-ltex-plus--action-hide-false-positives (action)
  "Process the _ltex.hideFalsePositives ACTION."
  (lsp-ltex-plus--log "Action: hideFalsePositives")
  (let* ((args (gethash "arguments" action))
         (arg0 (and (vectorp args) (aref args 0)))
         (fps-by-lang (and arg0 (gethash "falsePositives" arg0))))
    (if (null fps-by-lang)
        (message "[lsp-ltex-plus] hideFalsePositives: Malformed arguments %S" args)
      (maphash (lambda (lang fps-arr)
                 (lsp-ltex-plus--add-to-plist 'lsp-ltex-plus--hidden-false-positives
                                              lsp-ltex-plus-hidden-false-positives-file
                                              lang (append fps-arr nil)))
               fps-by-lang)))
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))


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

  (lsp-ltex-plus--load-external-settings)

  ;; Apply sticky debug defaults.
  (when lsp-ltex-plus-debug
    (setq lsp-log-io t)
    (when (string= lsp-ltex-plus-trace-server "off")
      (setq lsp-ltex-plus-trace-server "messages")))

  (lsp-ltex-plus--log "Registering settings and client...")
  (lsp-ltex-plus--log "Registering ltex-ls-plus client (priority: -1)...")
  (lsp-register-custom-settings
   `(("ltex.enabled"                             ,(lambda () (vconcat (lsp-ltex-plus--enabled-languages))))
     ("ltex.language"                            lsp-ltex-plus-language)
     ("ltex.dictionary"                          lsp-ltex-plus--dictionary)
     ("ltex.enabledRules"                        lsp-ltex-plus-enabled-rules)
     ("ltex.disabledRules"                       lsp-ltex-plus-disabled-rules)
     ("ltex.hiddenFalsePositives"                lsp-ltex-plus--hidden-false-positives)
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
    ;; `:multi-root' reads the defcustom at registration time.  The fallback
    ;; path inside `:initialized-fn' re-registers the client with the flag
    ;; cleared if the server does not advertise workspace folders support.
    :multi-root lsp-ltex-plus-multi-root
    :initialized-fn (lambda (workspace)
                      (lsp-ltex-plus--log "Server initialized; pushing configuration...")
                      (lsp-notify "workspace/didChangeConfiguration"
                                  `(:settings (:ltex (:enabled ,(vconcat (lsp-ltex-plus--enabled-languages))
                                                               :language ,lsp-ltex-plus-language
                                                               :enabledRules ,lsp-ltex-plus-enabled-rules
                                                               :disabledRules ,lsp-ltex-plus-disabled-rules
                                                               :hiddenFalsePositives ,lsp-ltex-plus--hidden-false-positives
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
            ("_ltex.disableRules"       #'lsp-ltex-plus--action-disable-rules)
            ("_ltex.hideFalsePositives" #'lsp-ltex-plus--action-hide-false-positives))))
  (lsp-ltex-plus--log "lsp-ltex-plus--setup completed."))

;;;; -- Activation -------------------------------------------------------------

(defun lsp-ltex-plus-buffer-setup-default ()
  "Apply sane default buffer-local settings for ltex-ls-plus."
  ;; ltex-ls-plus is not root-aware; auto-guessing avoids prompts for standalone files.
  (setq-local lsp-auto-guess-root t)
  ;; Watching is unnecessary and potentially expensive for this server.
  (setq-local lsp-enable-file-watchers nil)
  ;; UI and behavior tweaks for a grammar checker.
  (setq-local lsp-idle-delay 0.5)
  (setq-local lsp-completion-enable lsp-ltex-plus-completion-enabled)
  (if (featurep 'lsp-ui)
      (setq-local lsp-ui-sideline-enable t))
  (setq-local lsp-modeline-code-actions-enable t))

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

When enabled, this mode configures the buffer for ltex-ls-plus and starts
the server.  It uses `lsp-ltex-plus-buffer-setup-function' to apply
buffer-local settings.

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
            (funcall lsp-ltex-plus-buffer-setup-function)
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
