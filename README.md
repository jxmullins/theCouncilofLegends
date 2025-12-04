# The Council of Legends

**What happens when you put multiple AIs in a room together?**

A multi-AI debate and collaboration system that orchestrates structured discussions between AI models. Each AI presents arguments, responds to others, and synthesizes conclusions on any topic you choose.

**Now with The Council of Many:** Add your own AIs—local models via Ollama/LM Studio, or any OpenAI-compatible endpoint. Build a council of 2, 5, or 10 AIs. Mix cloud and local models. Your council, your rules.

[![Status: Work In Progress](https://img.shields.io/badge/Status-Work%20In%20Progress-yellow)](TODO.md)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet?logo=anthropic)](https://claude.com/claude-code)
[![Bash](https://img.shields.io/badge/Shell-Bash-blue?logo=gnu-bash)](https://www.gnu.org/software/bash/)

> **Note:** This project is under active development. Core functionality works, but some features are still being built. See the [Roadmap](#roadmap) for current status.

---

## The Idea

**Old way:** Ask one AI, get one perspective, wonder if you're missing something.

**Council way:** Multiple AIs debate the topic, challenge each other's reasoning, then synthesize their conclusions. You get a richer, more nuanced answer.

---

## The Council of Many

Build your own council with any combination of AI models:

```bash
# Add a local Ollama model
./council.sh models add llama3 ollama llama3:8b --council

# Add LM Studio model
./council.sh models add mistral lmstudio mistral-7b --endpoint http://localhost:1234 --council

# Add any OpenAI-compatible API
./council.sh models add deepseek openai-compatible deepseek-chat \
    --endpoint https://api.deepseek.com --auth-env DEEPSEEK_API_KEY --council

# See your council
./council.sh models list

# Mix and match - disable cloud, go full local
./council.sh models disable claude
./council.sh models enable llama3
```

| Provider | Examples | Auth |
|----------|----------|------|
| `ollama` | Llama 3, Mistral, Phi, Qwen | None (local) |
| `lmstudio` | Any GGUF model | None (local) |
| `openai-compatible` | vLLM, Together AI, Anyscale, LocalAI | API key |
| `anthropic` | Claude 3.5 Sonnet, Opus, Haiku | API key |
| `openai` | GPT-4o, o1, o3 | API key |
| `google` | Gemini 2.5 Flash/Pro | API key |
| `groq` | Llama 3.3 70B (fast inference) | API key |

---

## Two Modes: Council vs Team

| | **Council Mode** (`council.sh`) | **Team Mode** (`team.sh`) |
|---|---|---|
| **Purpose** | Debate and explore ideas | Build and deliver artifacts |
| **Structure** | Rounds of arguments and rebuttals | Task breakdown with milestones |
| **Output** | Synthesis of perspectives | Working code, docs, or designs |
| **Leadership** | Chief Justice moderates | Project Manager coordinates |
| **Best for** | "Should we...", "What's the best...", "Pros/cons of..." | "Build a...", "Create a...", "Implement..." |

**Use Council when** you want multiple perspectives on a decision, need to explore tradeoffs, or want to stress-test an idea.

**Use Team when** you want the AIs to collaborate on producing something tangible—code, documentation, architecture designs, etc.

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
| **Dynamic Council** | Add any number of AIs—2, 5, or 10. Mix cloud and local models. |
| **Local LLM Support** | Ollama, LM Studio, or any OpenAI-compatible endpoint |
| **Default Debaters** | Claude (Anthropic), Codex (OpenAI), Gemini (Google) |
| **4th AI Arbiter** | Groq/Llama serves as impartial judge for Chief Justice selection |
| **Model Management** | CLI to add, remove, enable, disable, update, and test models |
| **Debate Modes** | Collaborative, Adversarial, Exploratory, SCOTUS (judicial) |
| **Team Collaboration** | AIs work together on tasks with a PM coordinating |
| **Persona System** | Assign personalities (philosopher, hacker, scientist, etc.) |
| **Chief Justice Selection** | Arbiter analyzes topic and selects best-suited moderator |
| **Context Management** | Smart summarization for long debates |
| **Full Transcripts** | Every debate saved as markdown |

---

## Prerequisites

### Required: At Least 2 AIs

You need at least 2 AIs to run a debate. Choose from cloud APIs or local models:

**Option A: Cloud APIs (Default Setup)**

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

**Option B: Local Models (No API Keys Needed)**

```bash
# Install Ollama (https://ollama.ai)
brew install ollama   # macOS
ollama pull llama3    # Download a model

# Add to council
./council.sh models add llama3 ollama llama3 --council
./council.sh models add phi ollama phi3 --council

# Disable cloud models if desired
./council.sh models disable claude codex gemini
```

**Option C: Mix Both**

Use cloud APIs for some members, local models for others. The system handles routing automatically.

### Optional: 4th AI Arbiter (Groq)

The arbiter is an impartial 4th AI (Groq/Llama) that doesn't participate in debates but:
- Analyzes topics to select the best Chief Justice
- Provides baseline capability scoring
- Enables SCOTUS judicial mode

```bash
export GROQ_API_KEY="your-groq-api-key"
```

### Required: jq

JSON processing is required for API responses:

```bash
brew install jq      # macOS
apt install jq       # Debian/Ubuntu
```

### Verify Setup

```bash
./council.sh models test    # Test all registered models
./test_adapters.sh          # Legacy adapter test
```

---

## Usage

### Model Management

```bash
./council.sh models <command>

Commands:
    list              List all registered models
    add               Add a new model (interactive wizard)
    add <id> <provider> <model> [options]
                      Add a model directly
    update <id>       Update model configuration
    remove <id>       Remove a model from registry
    enable <id>       Add model to council
    disable <id>      Remove model from council
    test [id]         Test model connectivity
    info <id>         Show model details

Add Options:
    --name NAME       Display name
    --endpoint URL    API endpoint (required for openai-compatible)
    --auth-env VAR    Environment variable containing API key
    --context N       Context window size
    --council         Enable as council member immediately
```

### Debates

```bash
./council.sh "Your topic" [OPTIONS]

Options:
    --mode MODE        collaborative, adversarial, exploratory, scotus
    --rounds N         Number of rounds (2-10, default: 3)
    --personas SPEC    claude:philosopher,codex:hacker,gemini:scientist
    --chief-justice AI Force specific CJ (any council member ID)
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

### The Council of Many (v2.0)
- [x] Dynamic council membership (any number of AIs)
- [x] Local LLM support (Ollama, LM Studio)
- [x] Generic OpenAI-compatible endpoint support
- [x] CLI model management (add, remove, enable, disable, update, test)
- [x] Provider-based dispatcher routing
- [x] Security hardening (input validation, SSRF protection, file locking)
- [x] Backward compatibility with existing 3-AI setup

### Previously Completed
- [x] Safe configuration loading (security fix)
- [x] Robust argument parsing
- [x] Dependency validation
- [x] Context limits enforcement
- [x] LLM registry management (`lib/llm_manager.sh`)
- [x] Trend analysis system (`lib/analysis.sh`)
- [x] Secrets scanning with gitleaks pre-commit hook

### In Progress
- [ ] Externalize prompt templates to `templates/prompts/`
- [ ] Interactive first-run setup wizard

### Planned
- [ ] Budget-aware debates (token tracking, cost limits)
- [ ] Structured telemetry and replay logs
- [ ] Mini-questionnaires for specialized topics
- [ ] Unified logging system
- [ ] Parallel council invocation (performance)

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
  council.sh          # Main entry point (debates + model management)
  team.sh             # Team collaboration entry point
  assess.sh           # Baseline assessment tool
  config/
    council.conf      # Configuration
    llms.toon         # LLM registry (models, providers, endpoints)
    personas/         # Debate personas (TOON/JSON)
    roles/            # Team role definitions
  lib/
    adapters/         # AI provider adapters
      ollama_adapter.sh         # Ollama local LLMs
      lmstudio_adapter.sh       # LM Studio local LLMs
      openai_compatible_adapter.sh  # Generic OpenAI API
    cli_commands.sh   # Model management CLI
    dispatcher.sh     # Provider-based AI routing
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
