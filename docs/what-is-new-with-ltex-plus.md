# What is New with LTeX+?

LTeX+ is the modernized successor to the original `ltex-ls` project. While the original project laid the groundwork for grammar checking in LaTeX and Markdown, LTeX+ has significantly expanded the scope, reliability, and technical foundation of the server.

## The Evolution of the "Plus" Fork

As of April 12, 2026, the original `valentjn/ltex-ls` repository has been officially **archived**. LTeX+ emerged as a fork specifically to address unmaintained issues and to integrate years of pending community improvements (Pull Requests) that were left dormant in the original project.

The "Plus" project officially took its own name with version **17.0.0** (August 2024) and has since undergone a rapid transformation.

---

## 1. Support for Modern Writing Formats

LTeX+ has transformed from a LaTeX-centric tool into a comprehensive engine for modern technical writing. Most of these were added during the **18.x** release cycle:

*   **Typst (v18.3.0):** Native support for the modern, fast LaTeX alternative.
*   **Quarto & MDX (v18.3.0):** Support for advanced Markdown variants used in data science and web development.
*   **Neorg & AsciiDoc (v18.5.0):** Integrated parsers for these powerful organization and documentation formats.
*   **(X)HTML (v18.2.0):** Added support for magic comments within HTML files.

## 2. Technical Modernization: The Java 21 Leap

The most significant architectural change occurred in **v18.0.0** (September 2024):

*   **Java 21 Required:** The server moved from Java 11 to Java 21. This allows LTeX+ to utilize modern JVM features and ensures compatibility with the latest **LanguageTool 6.7+** engines.
*   **Native ARM64/AArch64:** LTeX+ introduced dedicated Java runtimes for Apple Silicon (M1/M2/M3), Linux ARM (Raspberry Pi), and Windows on ARM, drastically improving performance on modern hardware.
*   **LanguageTool 6.7 Integration:** Regular updates to the underlying grammar engine ensure you have the most recent rules for grammar, style, and spell-checking.

## 3. Deep Integration of Community Improvements

LTeX+ isn't just a fork; it's a consolidation of the community's best work. Many features added in the **18.4.x** and **18.5.x** series were originally PRs to the old project that had been stuck in limbo:

*   **Expanded LaTeX Command Set:** Massive additions to supported commands, including `apacite`, `cleveref` variants, and modern LaTeX3-style primitives (`\NewDocumentCommand`, etc.).
*   **Robust HTTP Handling:** Fixed a long-standing "slash issue" and HTTP 413 (Payload Too Large) errors when communicating with remote LanguageTool servers.
*   **Format Corrections:** In v18.6.0, `ltex.hiddenFalsePositives` was corrected to use a structured JSON format instead of simple strings, preventing configuration corruption.

## 4. Advanced "Magic Comments"

LTeX+ introduces a much more sophisticated way to configure settings directly inside your documents:

*   **Comprehensive Magic Comments (v18.6.0):** You can now adjust almost any setting via comments, and LTeX+ now allows multiple settings to be defined in a single comment block.
*   **Multi-language Dummies:** Improved handling of multi-lingual documents (Dutch, Spanish, Swedish, Polish, etc.) to reduce false positives in polyglot environments.

---

## Timeline Summary

| Version | Milestone | Key Changes |
| :--- | :--- | :--- |
| **17.0.0** | **The Birth of Plus** | Rename to LTeX+ LS; fix long-standing Linux crashes. |
| **18.0.0** | **The Infrastructure** | **Java 21 mandatory**; Native ARM64 support. |
| **18.3.0** | **The Parsers** | Added **Typst** and **MDX** support. |
| **18.5.0** | **The Expansion** | Added **Neorg**, **AsciiDoc**, and massive LaTeX command updates. |
| **18.6.0** | **The Refinement** | Comprehensive Magic Comments; LanguageTool 6.7. |
| **Current** | **The Successor** | Original repo archived; LTeX+ is the current standard. |

