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

- [x] **Externalize Prompt Templates**
    - Created `templates/prompts/` directory with `assessment/`, `scotus/`, and `core/` subdirectories.
    - Moved prompts from `lib/assessment.sh` (self_assessment, peer_review) to template files.
    - Moved prompts from `lib/scotus.sh` (resolution_derivation, cj_moderation, position_analysis) to templates.
    - Implemented `load_template()` and `load_template_with_content()` in `lib/utils.sh`.

- [ ] **Dynamic Model Registry Integration**
    - Refactor `COUNCIL_MEMBERS` to use `lib/llm_manager.sh` registry.
    - Update `lib/assessment.sh` and `council.sh` to iterate over dynamic list.
    - Update `lib/adapters/` to support plugin-like architecture.

## Future Features

- [x] **Interactive "First Run" Setup**
    - Created `./setup.sh` interactive wizard that:
        - Checks system dependencies (jq, curl, python3).
        - Verifies AI CLI tools (claude, codex, gemini).
        - Configures API keys (saves to `.env` file).
        - Runs `test_adapters.sh` for verification.

- [x] **Unified Logging**
    - Added `init_logging()` function to create session log files in `logs/`.
    - All log functions now write to both console and log file with timestamps.
    - Log levels: DEBUG, INFO, WARN, ERROR (configurable via COUNCIL_LOG_LEVEL).
    - Added `log_event()` for structured JSON telemetry events.
    - Symlink `logs/latest.log` points to most recent session.

- [x] **Budget-Aware Debates**
    - Created `lib/budget.sh` with comprehensive cost tracking.
    - Added `--max-cost`, `--profile`, and `--show-costs` flags to council.sh.
    - Token estimation and cost calculation per AI/model.
    - Budget profiles: frugal (mini models), balanced (default), premium (flagship).
    - Session-level cost tracking with per-AI breakdown.
    - `print_budget_report()` for cost summaries.

- [x] **Structured Telemetry & Replay Log**
    - Created `lib/telemetry.sh` with comprehensive event system.
    - JSON event log (.jsonl format) with timestamps and sequence numbers.
    - Event types: session, debate, round, AI request/response/error/retry, CJ selection, persona changes.
    - `emit_*` convenience functions for all event types.
    - `replay_telemetry()` for human-readable replay of events.
    - `telemetry_stats()` for event statistics summary.
