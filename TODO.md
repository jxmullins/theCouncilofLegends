# The Council of Legends - Todo List

## Next Up
<!-- Priority tasks for next session -->
1. Implement questionnaire runner for each AI (have each AI fill out `questionnaire_v1.json`)
2. Implement peer review ranking (each council member ranks the other two)
3. Wire up arbiter to generate baseline scores using the prompt templates

## Features
<!-- New functionality to add -->

### Debate Modes
- [ ] SCOTUS mode - majority opinions, concurrences, dissents
  - [ ] Chief Justice Selection System (see below)
  - [ ] Opinion types: majority, concurrence, dissent
  - [ ] Vote tallying (3-0 unanimous, 2-1 majority)

### Chief Justice Selection System
Chief Justice is selected **per-debate** based on topic relevance to each AI's strengths.

#### Baseline Assessment (on model change or user re-eval)
- [x] **Self-Assessment Questionnaire** (`config/questionnaire_v1.json`)
  - [x] Design main questionnaire (9 categories, 70+ items)
  - [ ] Implement questionnaire runner for each AI
  - [ ] Trigger on model/version change or user-initiated re-eval
  - [ ] Mini-questionnaires for new topics not covered by main questionnaire
  - [ ] Auto-merge mini-questionnaire topics into main questionnaire for next re-eval
- [x] **Blind Peer Review** (`lib/assessment.sh`)
  - [x] Anonymize self-assessment results (AI-A, AI-B, AI-C)
  - [x] Generate random mapping each cycle
  - [x] Prepare peer review packages (excludes reviewer's own assessment)
  - [x] Security validation (no self-review possible)
  - [x] De-anonymize after review complete
  - [ ] Each council member ranks the other two based on blind results
- [x] **Baseline Analysis (4th AI)** (`config/assessment_results_schema.json`)
  - [x] Fixed model to start (Groq/Llama) - `lib/adapters/groq_adapter.sh`
  - [x] Design 4th AI prompt templates (`config/prompts/`)
    - [x] `arbiter_baseline.json` - Analyze assessments, generate baseline scores
    - [x] `arbiter_topic.json` - Analyze topic, assign category relevance weights
    - [x] `arbiter_recommendation.json` - Combine baseline + topic → recommend CJ
  - [ ] Generate baseline scores per category for each AI
  - [ ] Store as persistent baseline for topic weighting

#### Per-Debate Context Analysis (`config/debate_context_schema.json`)
- [ ] **Topic Analysis**
  - [ ] 4th AI analyzes debate topic
  - [ ] Assigns relevance weights (0.0-1.0) to each questionnaire category
  - [ ] Can weight down to specific items (e.g., "python" vs all programming)
- [ ] **Context-Weighted Scoring**
  - [ ] Recalculate each AI's score using only relevant categories
  - [ ] AI strong in relevant areas rises; irrelevant strengths don't help
  - [ ] Example: Technical debate → Codex leads; Ethics debate → Claude leads
- [ ] **Recommendation & User Decision**
  - [ ] Present context-weighted rankings table
  - [ ] Show score delta from baseline (who benefits from this topic)
  - [ ] User accepts recommendation or manually overrides

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
- [ ] Update personas for each LLM or add new personas
- [ ] Select personas for each debate
- [ ] Change personas per round (or let LLM decide when to switch)

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

