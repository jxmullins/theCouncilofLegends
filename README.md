# The Council of Legends

**What happens when you put Claude, Codex, and Gemini in a room together?**

A multi-AI debate and collaboration system that orchestrates structured discussions between frontier AI models. Each AI presents arguments, responds to others, and synthesizes conclusions on any topic you choose.

[![Status: Work In Progress](https://img.shields.io/badge/Status-Work%20In%20Progress-yellow)](TODO.md)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Built%20with-Bash-blue)](https://www.gnu.org/software/bash/)

> **Note:** This project is under active development. Core functionality works, but some features are still being built. See the [Roadmap](#roadmap) for current status.

---

## The Idea

**Old way:** Ask one AI, get one perspective, wonder if you're missing something.

**Council way:** Three AIs debate the topic, challenge each other's reasoning, then synthesize their conclusions. You get a richer, more nuanced answer.

---

## Quick Demo

```bash
# Start a debate
./council.sh "Should we use microservices or monolith for our startup?"

# The Council deliberates...
# - Claude presents opening position
# - Codex responds with counterpoints
# - Gemini offers a third perspective
# - Multiple rounds of rebuttals
# - Final synthesis with consensus and disagreements
```

```bash
# Team mode: AIs collaborate on a task
./team.sh "Build a REST API authentication system"

# A Project Manager is selected
# Task is broken into subtasks
# AIs work together (pair programming, divide & conquer, etc.)
# Final deliverable is merged and presented
```

---

## Features

| Feature | Description |
|---------|-------------|
| **Three AI Participants** | Claude (Anthropic), Codex (OpenAI), Gemini (Google) |
| **Debate Modes** | Collaborative, Adversarial, Exploratory, SCOTUS (judicial) |
| **Team Collaboration** | AIs work together on tasks with a PM coordinating |
| **Persona System** | Assign personalities (philosopher, hacker, scientist, etc.) |
| **Chief Justice Selection** | Arbiter selects moderator based on topic expertise |
| **Context Management** | Smart summarization for long debates |
| **Full Transcripts** | Every debate saved as markdown |

---

## Prerequisites

### Required CLI Tools

Install and authenticate each AI's CLI:

```bash
# Claude CLI (Anthropic)
npm install -g @anthropic-ai/claude-code
claude auth login

# Codex CLI (OpenAI)
npm install -g @openai/codex
codex auth login

# Gemini CLI (Google)
npm install -g @anthropic/gemini-cli
gemini auth login
```

### Optional: Groq API Key

For Chief Justice selection and SCOTUS mode:

```bash
export GROQ_API_KEY="your-groq-api-key"
```

### Verify Setup

```bash
./test_adapters.sh
```

---

## Usage

### Debates

```bash
./council.sh "Your topic" [OPTIONS]

Options:
    --mode MODE        collaborative, adversarial, exploratory, scotus
    --rounds N         Number of rounds (2-10, default: 3)
    --personas SPEC    claude:philosopher,codex:hacker,gemini:scientist
    --chief-justice AI Force specific CJ (claude, codex, gemini)
    --no-cj            Skip Chief Justice selection
    --verbose          Enable debug logging
    --list-personas    Show available personas
```

### Team Collaboration

```bash
./team.sh "Your task" [OPTIONS]

Options:
    --pm AI            Force specific Project Manager
    --mode MODE        pair_programming, consultation, round_robin,
                       divide_conquer, free_form
    --checkpoints LVL  all, major, none
```

---

## Output

Debates are saved to `./debates/`:

```
debates/20241201_123456_your-topic/
  transcript.md       # Full debate transcript
  final_synthesis.md  # Combined conclusions
  metadata.json       # Debate metadata
  responses/          # Individual AI responses
```

Team projects are saved to `./projects/`:

```
projects/20241201_123456_build-api/
  final_delivery.md   # Final deliverable
  execution_plan.json # PM's plan
  artifacts/          # Generated code/docs
  checkpoints/        # Milestone snapshots
```

---

## Roadmap

### Core Features
- [x] Multi-AI debate orchestration
- [x] Multiple debate modes (collaborative, adversarial, exploratory)
- [x] SCOTUS judicial mode with majority/dissent opinions
- [x] Persona system with customizable personalities
- [x] Chief Justice selection via arbiter
- [x] Context summarization for long debates
- [x] Team collaboration mode with PM coordination
- [x] Work modes (pair programming, divide & conquer, etc.)
- [x] Role assignment system

### Recently Completed
- [x] Safe configuration loading (security fix)
- [x] Robust argument parsing
- [x] Dependency validation
- [x] Context limits enforcement
- [x] LLM registry management (`lib/llm_manager.sh`)
- [x] Trend analysis system (`lib/analysis.sh`)
- [x] Secrets scanning with gitleaks pre-commit hook

### In Progress
- [ ] Externalize prompt templates to `templates/prompts/`
- [ ] Dynamic model registry integration
- [ ] Interactive first-run setup wizard

### Planned
- [ ] Budget-aware debates (token tracking, cost limits)
- [ ] Structured telemetry and replay logs
- [ ] Mini-questionnaires for specialized topics
- [ ] Unified logging system

See [TODO.md](TODO.md) for the full improvement plan.

---

## Configuration

Edit `config/council.conf`:

```bash
# Debate Settings
DEFAULT_ROUNDS=3
TURN_TIMEOUT=120
MAX_RESPONSE_WORDS=400

# AI Models
CLAUDE_MODEL="sonnet"
CODEX_MODEL="gpt-4o"
GEMINI_MODEL="gemini-2.5-flash"

# Context Management
MAX_CONTEXT_CHARS=8000
INCLUDE_FULL_HISTORY=false
```

---

## Project Structure

```
theCouncilofLegends/
  council.sh          # Debate entry point
  team.sh             # Team collaboration entry point
  assess.sh           # Baseline assessment tool
  config/
    council.conf      # Configuration
    personas/         # Debate personas (TOON/JSON)
    roles/            # Team role definitions
  lib/
    adapters/         # AI CLI adapters
    llm_manager.sh    # LLM registry management
    analysis.sh       # Trend analysis
    debate.sh         # Debate orchestration
    team.sh           # Team orchestration
    scotus.sh         # SCOTUS judicial mode
  debates/            # Saved transcripts
  projects/           # Saved team projects
```

---

## Why I Built This

> I wanted to explore what happens when you stop treating AIs as isolated oracles and start treating them as participants in a conversation. Can they challenge each other? Find blind spots? Reach better conclusions together than alone? This project is my experiment to find out. It's also a playground for learning how different AI models reason differently about the same problems.

---

## Acknowledgments

Credit where it's due: [karpathy/llm-council](https://github.com/karpathy/llm-council) led the way on this concept. While I had started sketching out the idea for "The Council of Legends" before discovering their project, they were first out the gate with an impressive implementation. Check out their work—it's excellent and worth exploring alongside this project.

---

## Support

If this project is useful to you, consider buying me a coffee:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buy-me-a-coffee)](https://buymeacoffee.com/jxmullins)

## Contributing

This project is a work in progress! Ideas, bug reports, and contributions are welcome. Check [ISSUES.md](ISSUES.md) for known issues and [TODO.md](TODO.md) for planned features.

## License

Apache 2.0 — Free to use, but attribution required. See [LICENSE](LICENSE) for details.

---

*Built with Claude Code and a lot of curiosity.*
