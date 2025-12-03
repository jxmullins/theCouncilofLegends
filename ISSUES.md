# Known Issues & Bugs

## Resolved Issues

### 1. Error Suppression in Chief Justice Selection - FIXED
- **Location:** `council.sh` (Line ~399)
- **Fix Applied:** Removed `2>/dev/null` from `select_chief_justice` call. Errors now propagate properly for debugging.

### 2. Security: Unsafe Configuration Loading - FIXED
- **Location:** `lib/config.sh` (Lines 59-102)
- **Fix Applied:** Implemented `_safe_load_config()` function that:
  - Only allows `KEY=VALUE` or `KEY="VALUE"` patterns
  - Rejects lines containing shell metacharacters (`$`, backticks, `()`, `;`, `&`, `|`)
  - Logs warnings for ignored lines

### 5. Fragile Argument Parsing - FIXED
- **Location:** `council.sh` (`parse_args` function)
- **Fix Applied:** Added validation checks for all flags that require values. Now properly errors with "Option --X requires a value" message.

### 6. Undocumented Dependencies - FIXED
- **Location:** `lib/utils.sh` (Lines 225-268)
- **Fix Applied:** Added `validate_system_dependencies()` function that checks for `jq`, `curl`, and `python3` with helpful installation instructions.

### 7. Config Load Order Overrides CLI Flags - FIXED
- **Location:** `council.sh` (Lines 326-353)
- **Fix Applied:** Restructured `main()` to load config BEFORE parsing arguments. CLI flags now always override config file values.

### 8. Synthesis Prompt Can Exceed Context Limits - FIXED
- **Location:** `lib/context.sh` (`build_synthesis_prompt` function)
- **Fix Applied:** Now respects `MAX_CONTEXT_CHARS`, uses summaries for older rounds when limit approached, and truncates with notification if needed.

### 9. Round Files Fed in Lexical Order, Not Numeric - FIXED
- **Location:** `lib/context.sh` (`build_synthesis_prompt` function)
- **Fix Applied:** Round files are now sorted numerically before processing (round_1 before round_2 before round_10).

### 10. Advertised Config Knobs Are Dead - FIXED
- **Location:** `lib/context.sh` (`build_opening_prompt`, `build_rebuttal_prompt`)
- **Fix Applied:** `MAX_RESPONSE_WORDS` now used in prompt guidelines. `INCLUDE_FULL_HISTORY` now controls whether full debate history or smart summaries are used.

### 11. Missing Dependency Preflight Beyond AI CLIs - FIXED
- **Location:** `lib/utils.sh` (Lines 289-305)
- **Fix Applied:** Added `validate_all_dependencies()` that combines system dependency check with AI CLI check. Called at startup.

---

## Open Issues (Architectural - Lower Priority)

### 3. Scalability: Hardcoded AI Models
- **Location:** Multiple files (`council.sh`, `lib/assessment.sh`, `lib/config.sh`, `lib/utils.sh`, `lib/context.sh`).
- **Description:** The list of council members (`claude`, `codex`, `gemini`) is hardcoded in arrays, `case` statements, and loops throughout the codebase.
- **Impact:** Adding a new AI model (e.g., "mistral") requires manual modification of at least 6 different files.
- **Recommended Fix:** Centralize the model list in `lib/config.sh` or a JSON registry. Use dynamic iteration instead of hardcoded strings.
- **Status:** Planned for future refactoring

### 4. Maintainability: Embedded Prompts
- **Location:** `lib/assessment.sh`, `lib/scotus.sh`, `lib/context.sh`.
- **Description:** Large, multi-line prompt templates (HEREDOCs) are embedded directly inside shell functions.
- **Impact:**
    - Reduces code readability.
    - Makes it difficult to edit or version prompts independently.
    - Prevents the use of specific file extensions (like `.md` or `.toon`) for syntax highlighting of prompts.
- **Recommended Fix:** Extract all prompts to `templates/prompts/` and load them using a helper function.
- **Status:** Planned for future refactoring
