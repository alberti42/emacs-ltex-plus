;;; lsp-ltex-plus.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

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
;;    The server fetches these via workspace/configuration. Updating the Lisp
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

(defcustom lsp-ltex-plus-major-modes
  '((markdown-mode   . "markdown")
    (gfm-mode        . "markdown")
    (LaTeX-mode      . "latex")
    (latex-mode      . "latex")
    (tex-mode        . "latex")
    (plain-tex-mode  . "latex")
    (text-mode       . "plaintext")
    (org-mode        . "org")
    (rst-mode        . "restructuredtext")
    (git-commit-mode . "plaintext")
    (bibtex-mode     . "bibtex")
    (context-mode    . "context")
    (html-mode       . "html")
    (typst-mode      . "typst")
    (asciidoc-mode   . "asciidoc")
    (norg-mode       . "neorg")
    (quarto-mode     . "quarto"))
  "Alist of (major-mode . language-id) pairs for lsp-ltex-plus activation.
This decides where LTeX+ is active.  Each entry enables the minor mode
for that major mode and registers its language identifier with lsp-mode."
  :type '(alist :key-type symbol :value-type string)
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-language "en-US"
  "The language (e.g., \"en-US\") LanguageTool should check against.
If possible, use a specific variant like \"en-US\" or \"de-DE\" instead of the
generic language code like \"en\" or \"de\" to obtain spelling corrections (in
addition to grammar corrections).

When using the language code \"auto\", LTeX+ will try to detect the language of
the document. This is not recommended, as only generic languages like \"en\" or
\"de\" will be detected and thus no spelling errors might be reported."
  :type 'string
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-enabled-rules nil
  "Lists of rules that should be enabled (if disabled by default by LanguageTool).
This setting is language-specific, so use an object of the format
'(:en-US [\"RULE1\" \"RULE2\"] :de-DE [\"RULE1\" ...]) where the key is the
language code and the value is a vector of rule IDs."
  :type 'plist
  :group 'lsp-ltex-plus)

(defcustom lsp-ltex-plus-disabled-rules nil
  "Lists of rules that should be disabled (if enabled by default by LanguageTool).
This setting is language-specific, so use an object of the format
'(:en-US [\"RULE1\" \"RULE2\"] :de-DE [\"RULE1\" ...]) where the key is the
language code and the value is a vector of rule IDs."
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
It contains bin and lib subdirectories. If empty, the bundled version is used."
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
Decreasing this might decrease RAM usage. If you set this too small, checking
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
  "Whether to apply the 'Kind-First' routing patch to `lsp-mode'.
This patch redefines `lsp--parser-on-message' to prioritize the 'method' field,
preventing deadlocks when server-initiated requests (like workspace/configuration)
collide with client requests.

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
  "Log a formatted message if `lsp-ltex-plus-debug' is enabled."
  `(when lsp-ltex-plus-debug
     (lsp-ltex-plus--log-to-buffer (format ,fmt ,@args))))

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
  "Load a plist from FILE-PATH. Return nil if it doesn't exist or fails."
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
  "Process the _ltex.addToDictionary action from the server."
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
  "Process the _ltex.disableRules action."
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
  "Process the _ltex.hideFalsePositives action."
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
;; Standard `lsp-mode` routes incoming JSON-RPC messages based on the 'id' field:
;; 1. If 'id' is present, it's treated as a RESPONSE to a client request.
;; 2. If 'method' is present (but no 'id'), it's a NOTIFICATION or REQUEST.
;;
;; LTeX+ frequently initiates its own requests (like `workspace/configuration`)
;; to fetch your dictionary and rules. If the server-initiated request uses an
;; ID that `lsp-mode` is already tracking for a client-side request, `lsp-mode`
;; will misroute the server's request as a response to its own request.
;; This results in a protocol deadlock where both sides are waiting for each
;; other indefinitely.
;;
;; SOLUTION: KIND-FIRST ROUTING
;;
;; The "Kind-First" patch below redefines `lsp--parser-on-message` to prioritize
;; the 'method' field over the 'id' field. If a 'method' is present, we know the
;; message is a Request or Notification from the server, regardless of whether
;; the ID happens to collide with an internal Emacs ID.

(defun lsp-ltex-plus--apply-lsp-mode-patch ()
  "Apply the 'Kind-First' patch to `lsp-mode'.
This redefines `lsp--parser-on-message' with the logic to prioritize
the 'method' field, preventing deadlocks when server-initiated
requests collide with client response IDs."
  ;; Silently catch and log any errors during message processing. This prevents
  ;; a single malformed message from crashing the entire LSP client.
  (with-demoted-errors "Error processing message %S."
    (with-lsp-workspace workspace
      (let* ((client (lsp--workspace-client workspace))
             (method (lsp-core--json-get json-data "method"))
             (raw-id (lsp-core--json-get json-data "id"))
             (has-method (not (null method)))
             (has-id (not (null raw-id)))
             (has-error (not (null (lsp-core--json-get json-data "error"))))
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
                       (result (lsp-core--json-get json-data "result")))
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
                       (err (lsp-core--json-get json-data "error")))
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
           (lsp--on-request workspace json-data)))))))

;;;; -- Lsp-mode Registration --------------------------------------------------

(defun lsp-ltex-plus--setup ()
  "Initialize and register the ltex-ls-plus client with lsp-mode."
  (setq lsp-ltex-plus--start-time (current-time))
  (lsp-ltex-plus--log "Initializing lsp-ltex-plus...")

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
   `(("ltex.enabled"                             t)
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
    :major-modes (mapcar #'car lsp-ltex-plus-major-modes)
    :server-id 'ltex-ls-plus
    ;; Priority -1 ensures LTeX+ acts as an auxiliary server.  It will not
    ;; "hijack" primary LSP features (like Go to Definition or Completion) if a
    ;; language-specific server (like texlab or pyright) is also active in the
    ;; buffer.
    :priority -1
    :initialized-fn (lambda (_workspace)
                      (lsp-ltex-plus--log "Server initialized; pushing configuration...")
                      (lsp-notify "workspace/didChangeConfiguration"
                                  `(:settings (:ltex (:enabled t
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

;;;###autoload
(define-minor-mode lsp-ltex-plus-mode
  "Minor mode for LTEX+ grammar checking via lsp-mode.

When enabled, this mode configures the buffer for ltex-ls-plus and
calls `lsp-deferred` to start the server.  It uses
`lsp-ltex-plus-buffer-setup-function' to apply buffer-local settings."
  :lighter " LTeX+"
  :group 'lsp-ltex-plus
  (if lsp-ltex-plus-mode
      (if (not (executable-find lsp-ltex-plus-ls-plus-executable))
          (progn
            (message "[lsp-ltex-plus] Aborting: %s not found on PATH." lsp-ltex-plus-ls-plus-executable)
            (setq lsp-ltex-plus-mode nil))
        (lsp-ltex-plus--log "Enabling LTEX+ in %s" (buffer-name))
        (funcall lsp-ltex-plus-buffer-setup-function)
        ;; If lsp-mode isn't already active, calling lsp-deferred won't do
        ;; anything unless another server triggers lsp-mode.  We call (lsp) to
        ;; ensure lsp-mode starts.
        (if (and (fboundp 'lsp) (not (bound-and-true-p lsp-mode)))
            (lsp)
          (lsp-deferred)))
    ;; When disabling, we add the server to disabled clients so it doesn't restart.
    (setq-local lsp-disabled-clients (add-to-list 'lsp-disabled-clients 'ltex-ls-plus))))

(defun lsp-ltex-plus--global-activate ()
  "Activate `lsp-ltex-plus-mode' if the major mode is in the allowed list."
  (when (assoc major-mode lsp-ltex-plus-major-modes)
    (lsp-ltex-plus-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-lsp-ltex-plus-mode lsp-ltex-plus-mode
  lsp-ltex-plus--global-activate
  :group 'lsp-ltex-plus)

;; Initialize on lsp-mode load.
(with-eval-after-load 'lsp-mode
  (dolist (pair lsp-ltex-plus-major-modes)
    (add-to-list 'lsp-language-id-configuration pair))
  (lsp-ltex-plus--setup))

(provide 'lsp-ltex-plus)
;;; lsp-ltex-plus.el ends here
