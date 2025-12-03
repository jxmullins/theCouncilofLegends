# Improvement Plan

## Completed

- [x] **Fix Error Handling in `council.sh`**
    - Removed `2>/dev/null` from `select_chief_justice` call.
    - Errors now propagate properly for debugging.

- [x] **Robust Argument Parsing**
    - Rewrote `parse_args` in `council.sh` to safely handle missing values for flags.
    - Added validation checks: "Option --X requires a value" messages.

- [x] **Dependency Validation**
    - Created `validate_system_dependencies()` function in `lib/utils.sh`.
    - Verifies existence of `jq`, `python3`, `curl` on startup.
    - Fails gracefully with installation instructions if missing.

- [x] **Safe Configuration**
    - Replaced `source "$config_file"` with `_safe_load_config()` line-by-line parser.
    - Allows only `VARIABLE="value"` or `VARIABLE=value` syntax.
    - Logs warnings for ignored lines with shell metacharacters.

- [x] **Config Load Order Fix**
    - Config now loads BEFORE parsing arguments.
    - CLI flags properly override config file values.

- [x] **Context/Synthesis Limits**
    - `build_synthesis_prompt` now respects `MAX_CONTEXT_CHARS`.
    - Round files sorted numerically (round_1 before round_10).
    - Uses summaries for older rounds when context limit approached.

- [x] **Wire Up Dead Config Knobs**
    - `MAX_RESPONSE_WORDS` now used in prompt guidelines.
    - `INCLUDE_FULL_HISTORY` controls full vs smart context in rebuttals.

- [x] **Arbiter Prompts to TOON**
    - Converted `arbiter_baseline.json`, `arbiter_topic.json`, `arbiter_recommendation.json` to TOON format.

- [x] **Trend Analysis System**
    - Created `lib/analysis.sh` with baseline storage, comparison, and trend reports.
    - Detects model version changes since last baseline.
    - Tracks CJ selection history.

- [x] **LLM Management System**
    - Created `lib/llm_manager.sh` for managing language model configurations.
    - Supports adding/removing LLMs, checking availability, registry management.
    - Uses TOON format for LLM registry.

## Architectural Improvements (Remaining)

- [ ] **Externalize Prompt Templates**
    - Create directory `templates/prompts/core/`.
    - Move prompts from `lib/assessment.sh` (Assessment, Peer Review, Baseline) to separate text files.
    - Move prompts from `lib/scotus.sh` to separate files.
    - Implement `load_template()` in `lib/utils.sh` to read these files.

- [ ] **Dynamic Model Registry Integration**
    - Refactor `COUNCIL_MEMBERS` to use `lib/llm_manager.sh` registry.
    - Update `lib/assessment.sh` and `council.sh` to iterate over dynamic list.
    - Update `lib/adapters/` to support plugin-like architecture.

## Future Features

- [ ] **Interactive "First Run" Setup**
    - A `./setup.sh` script that:
        - Checks dependencies.
        - Asks for API keys (saving them to a `.env` file, not `config.sh`).
        - Runs `test_adapters.sh`.

- [ ] **Unified Logging**
    - Create a structured log file (e.g., `logs/latest.log`) in addition to console output.
    - Include timestamps and log levels for easier debugging.

- [ ] **Budget-Aware Debates**
    - `--max-cost` and `--profile frugal|balanced|premium` flags.
    - Track token usage per AI.
    - Use cheaper models for exploration, expensive for synthesis.

- [ ] **Structured Telemetry & Replay Log**
    - JSON event log: timings, prompt hashes, retries, personas.
    - Lightweight local replay viewer.
