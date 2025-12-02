# The Council of Legends - Todo List

## Next Up
<!-- Priority tasks for next session -->
1. Add historical tracking of CJ selections per debate
2. Test edge cases: unanimous (3-0), three-way split
3. Store persistent baseline for topic weighting

## Features
<!-- New functionality to add -->

### Debate Modes
- [x] Judicial mode - majority opinions, concurrences, dissents (`--mode scotus`)
  - [x] Resolution derivation (arbiter converts topic to yes/no proposition)
  - [x] CJ-moderated debate rounds (CJ asks follow-up questions)
  - [x] Position analysis (arbiter infers votes from argumentation)
  - [x] Opinion assignment (CJ assigns authors based on position)
  - [x] Opinion types: majority, concurrence, dissent
  - [x] Vote tallying (2-1 majority implemented, 3-0 unanimous supported)
  - [ ] Edge case: three-way split (plurality opinion)

### Chief Justice Selection System
Chief Justice is selected **per-debate** based on topic relevance to each AI's strengths.

#### Baseline Assessment (on model change or user re-eval)
- [x] **Self-Assessment Questionnaire** (`config/questionnaire_v1.json`)
  - [x] Design main questionnaire (9 categories, 70+ items)
  - [x] Implement questionnaire runner for each AI (`assess.sh --questionnaire`)
  - [ ] Trigger on model/version change or user-initiated re-eval
  - [ ] Mini-questionnaires for new topics not covered by main questionnaire
  - [ ] Auto-merge mini-questionnaire topics into main questionnaire for next re-eval
- [x] **Blind Peer Review** (`lib/assessment.sh`)
  - [x] Anonymize self-assessment results (AI-A, AI-B, AI-C)
  - [x] Generate random mapping each cycle
  - [x] Prepare peer review packages (excludes reviewer's own assessment)
  - [x] Security validation (no self-review possible)
  - [x] De-anonymize after review complete
  - [x] Each council member ranks the other two based on blind results (`assess.sh --peer-review`)
- [x] **Baseline Analysis (4th AI)** (`config/assessment_results_schema.json`)
  - [x] Fixed model to start (Groq/Llama) - `lib/adapters/groq_adapter.sh`
  - [x] Design 4th AI prompt templates (`config/prompts/`)
    - [x] `arbiter_baseline.json` - Analyze assessments, generate baseline scores
    - [x] `arbiter_topic.json` - Analyze topic, assign category relevance weights
    - [x] `arbiter_recommendation.json` - Combine baseline + topic → recommend CJ
  - [x] Generate baseline scores per category for each AI (`assess.sh --analyze`)
  - [ ] Store as persistent baseline for topic weighting

#### Per-Debate Context Analysis (`config/debate_context_schema.json`)
- [x] **Topic Analysis** (`assess.sh --select-cj`)
  - [x] 4th AI analyzes debate topic
  - [x] Assigns relevance weights (0.0-1.0) to each questionnaire category
  - [ ] Can weight down to specific items (e.g., "python" vs all programming)
- [x] **Context-Weighted Scoring**
  - [x] Recalculate each AI's score using only relevant categories
  - [x] AI strong in relevant areas rises; irrelevant strengths don't help
  - [x] Example: Technical debate → Codex leads; Ethics debate → Claude leads
- [x] **Recommendation & User Decision**
  - [x] Present context-weighted rankings table
  - [x] Show score delta from baseline (who benefits from this topic)
  - [x] User accepts recommendation or manually overrides (`--chief-justice AI`)

#### Historical Tracking
- [ ] Store all baseline assessments with timestamps
- [ ] Track Chief Justice per debate (`chief_justice_history`)
- [ ] Trend analysis as models evolve

### User Interfaces
- [ ] Web UI
- [ ] macOS UI

### LLM Management
- [ ] Add ability to add additional LLMs
- [ ] Select token-based (local) vs API auth per LLM

### Persona System
- [x] Universal JSON persona catalog (`config/personas/*.json`)
  - [x] JSON schema for validation (`config/schemas/persona_schema.json`)
  - [x] Any persona can be assigned to any AI
  - [x] Template system with `{{AI_NAME}}` and `{{PROVIDER}}` placeholders
  - [x] Marketplace-ready format: id, name, version, author, description, tags, style
  - [x] 10 personas: default, philosopher, devils_advocate, historian, architect, hacker, security_expert, scientist, futurist, pragmatist
- [x] Select personas via CLI (`--personas claude:philosopher,codex:hacker`)
- [x] List available personas with metadata (`--list-personas`)
- [x] Persona info in metadata.json and transcripts
- [ ] Change personas per round (or let LLM decide when to switch)
- [ ] Create additional themed personas (e.g., educator, optimist, pessimist)
- [ ] Persona marketplace: import/export, validation, versioning

## Improvements
<!-- Enhancements to existing functionality -->

- [ ] Normalize output formatting across all LLMs for consistency

## Bug Fixes
<!-- Issues that need fixing -->

### From Codex Code Review (Dec 2024)
*Note: Most Codex bug reports were false positives - code already handles these cases*
- [x] **Retry path missing system_prompt** - Already fixed: `handle_ai_failure` accepts and passes prompt/system_prompt correctly
- [x] **Personas ignored after config load** - Already fixed: `load_config()` calls `refresh_persona_selections()`
- [x] **SCOTUS mode allows --no-cj** - Already fixed: Guard at `council.sh:394-401` enforces CJ for SCOTUS
- [x] **Context controls unused** - Already implemented: `SUMMARIZE_AFTER_ROUND` checked at `context.sh:70`, `MAX_CONTEXT_CHARS` used at `context.sh:93,140,168`
- [x] **Token bloat risk** - Mitigated: `get_previous_context()` uses summaries when context exceeds threshold

### From Gemini Code Review (Dec 2024)
- [ ] **Hardcoded temp files** (`test_adapters.sh:66,111,147`) - Use `mktemp` instead of `/tmp/council_test_*.txt` to avoid conflicts (low priority - test files only)
- [x] **Error files not cleaned up** - Fixed: All adapters now cleanup `.err` files on success
- [x] **`run_with_timeout` not centralized** - Already in `lib/utils.sh:112-137` (Gemini's report was inaccurate)

## Documentation
<!-- Docs, README, examples -->

## Ideas
<!-- Raw thoughts to classify later -->

### Codex Suggestions (Dec 2024)
Features leveraging the multi-AI architecture:

- [ ] **Round Referee & Scoreboard** - Arbiter grades each AI after rounds on clarity, evidence, responsiveness; shows running scoreboard plus "next-round nudge" notes. Keeps debates sharp.
- [ ] **Cross-Examination Microturns** - Each AI asks a targeted question to another participant; CJ assigns pairings to avoid dogpiles. Forces direct engagement with weak points.
- [ ] **Coverage Tracker** - Maintain checklist of `key_dimensions` after resolution derivation; flag unaddressed dimensions each round in prompts. Ensures complete outputs.
- [ ] **Fact-Checking & Citation Agent** - Optional agent that verifies claims against configured sources, adds citations/uncertainty tags. (High complexity)
- [ ] **Confidence & Calibration Mode** - AIs attach confidence bands to claims; arbiter reconciles into consensus probability in final verdict.
- [ ] **Debate Resume & Branching** - Persist structured state to resume crashed runs or branch from any round for "what-if" scenarios.
- [ ] **Structured Telemetry & Replay Log** - JSON event log with timings, prompt hashes, CLI versions, retries, persona selections. Plus lightweight local replay viewer.
- [ ] **Synthetic Regression Harness** - Stub adapters with canned responses and golden transcripts for CI testing without live LLMs.
- [ ] **Automatic Persona Matcher** - Auto-pick personas based on topic analysis for coverage diversity (e.g., ethicist + engineer + historian).
- [ ] **Collaboration Exports (Slack/Notion/PR)** - Push final verdict, opinions, key disagreements to Slack/Notion/PR comments with tl;dr and action items.

### Gemini Suggestions (Dec 2024)
Creative features leveraging multi-AI dynamics:

- [ ] **Argument Graph Visualization** - Auto-generate directed graph showing argument flow (claims as nodes, support/refutation as edges). Produces visual "debate map" for post-analysis.
- [ ] **Dynamic Debate Difficulty** - Monitor for groupthink/stagnation; inject controversial premises or assign devil's advocate persona mid-debate. (High complexity)
- [ ] **Budget-Aware Debates** - Specify `--max-cost` or `--profile frugal`; use cheaper models for exploration rounds, expensive models for synthesis.
- [ ] **"Silent Observer" Meta-Analysis** - Non-participating AI reports on conversation health: speaking time balance, logical fallacies, persona adherence.
- [ ] **Git-Inspired Debate Forking & Merging** - Fork from specific rounds (`--fork <id> --from-round 2`), change variables, arbiter merges divergent conclusions. (High complexity)
- [ ] **On-Demand Evidence Locker** - AIs request evidence via structured calls; system fetches from search/vector DB and injects into context. (High complexity)

### Claude's Favorites (Cross-AI Analysis)
Top picks combining Codex + Gemini suggestions:

- [ ] **Budget-Aware Debates** (Gemini) - Practical cost control, essential for scaling
- [ ] **Structured Telemetry & Replay Log** (Codex) - Essential for debugging and observability
- [ ] **"Silent Observer" Meta-Analysis** (Gemini) - Unique meta-perspective on debate quality
- [ ] **Synthetic Regression Harness** (Codex) - Enables CI testing without live LLMs

---

## Inbox
<!-- Drop any thought here - Claude will classify it -->

