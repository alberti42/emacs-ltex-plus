# Maintainer Scripts

This directory contains scripts used during development and maintenance of `lsp-ltex-plus`. They are **not** intended for end users; you do not need to run anything here to use the package.

## Scripts

- **`probe_rules.bash`** — interrogates a running `ltex-ls-plus` server to enumerate the rule IDs it currently advertises. Used to keep `is_proposed_unknown_word_rule` in `lsp-ltex-plus.el` aligned with upstream when ltex-ls-plus renames or adds rules.

- **`check_language_ids.py`** — cross-checks the language IDs declared in `lsp-ltex-plus-major-modes` (in `lsp-ltex-plus-bootstrap.el`) against those that the server source actually understands. Parses three canonical Kotlin files (`FileIo.kt`, `ProgramCommentRegexs.kt`, `CodeFragmentizer.kt`) from a local checkout of the `ltex-ls-plus` repo and reports IDs missing from our alist or present in our alist but unknown to the server. Run from the repo root: `python3 dev/check_language_ids.py /path/to/ltex-ls-plus`.
