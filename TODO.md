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
- [x] Universal persona catalog (`config/personas/*.persona`)
  - [x] Any persona can be assigned to any AI
  - [x] Template system with `{{AI_NAME}}` and `{{PROVIDER}}` placeholders
  - [x] 10 personas: default, philosopher, devils_advocate, historian, architect, hacker, security_expert, scientist, futurist, pragmatist
- [x] Select personas via CLI (`--personas claude:philosopher,codex:hacker`)
- [x] List available personas (`--list-personas`)
- [x] Persona info in metadata.json and transcripts
- [ ] Change personas per round (or let LLM decide when to switch)
- [ ] Create additional themed personas (e.g., educator, optimist, pessimist)

## Improvements
<!-- Enhancements to existing functionality -->

- [ ] Normalize output formatting across all LLMs for consistency

## Bug Fixes
<!-- Issues that need fixing -->

## Documentation
<!-- Docs, README, examples -->

## Ideas
<!-- Raw thoughts to classify later -->

---

## Inbox
<!-- Drop any thought here - Claude will classify it -->

