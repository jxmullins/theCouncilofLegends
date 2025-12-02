# The Council of Legends

A multi-AI debate system that orchestrates structured discussions between Claude, Codex, and Gemini. Each AI presents arguments, responds to others, and synthesizes conclusions on any topic you choose.

## Features

- **Three AI Participants**: Claude (Anthropic), Codex (OpenAI), Gemini (Google)
- **Multiple Debate Modes**:
  - `collaborative` - AIs work together toward consensus
  - `adversarial` - AIs argue opposing positions
  - `exploratory` - AIs explore all angles without judgment
  - `scotus` - Judicial mode with formal majority/dissent opinions
- **Persona System**: Assign different personas (philosopher, hacker, scientist, etc.) to each AI
- **Chief Justice Selection**: Optional arbiter (Groq/Llama) selects a moderator based on topic
- **Context Summarization**: Automatic round summaries for long debates
- **Full Transcripts**: Markdown transcripts saved for every debate

## Prerequisites

### Required CLI Tools

Install and authenticate each AI's CLI tool:

1. **Claude CLI** (Anthropic)
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude auth login
   ```

2. **Codex CLI** (OpenAI)
   ```bash
   npm install -g @openai/codex
   codex auth login
   ```

3. **Gemini CLI** (Google)
   ```bash
   npm install -g @anthropic/gemini-cli
   gemini auth login
   ```

### Optional: Groq API Key

For Chief Justice selection and SCOTUS mode, set your Groq API key:

```bash
export GROQ_API_KEY="your-groq-api-key"
```

### Verify Setup

Run the adapter test to verify all CLIs are working:

```bash
./test_adapters.sh
```

## Quick Start

```bash
# Basic collaborative debate
./council.sh "What is the best programming language for beginners?"

# Adversarial debate with 4 rounds
./council.sh "Should we use microservices or monolith?" --mode adversarial --rounds 4

# SCOTUS judicial mode
./council.sh "AI should be regulated by government" --mode scotus

# With personas
./council.sh "Future of work" --personas claude:philosopher,codex:hacker,gemini:scientist
```

## Usage

```
./council.sh "Your topic or question" [OPTIONS]

OPTIONS:
    --mode MODE        Debate mode: collaborative, adversarial, exploratory, scotus
    --rounds N         Number of rounds (2-10, default: 3)
    --verbose          Enable debug logging
    --config FILE      Use custom configuration file
    --chief-justice AI Force a specific Chief Justice (claude, codex, gemini)
    --no-cj            Skip Chief Justice selection
    --personas SPEC    Set personas (format: claude:persona,codex:persona,gemini:persona)
    --list-personas    Show available personas
    --help             Show help message
```

## Configuration

Edit `config/council.conf` to customize defaults:

```bash
# Debate Settings
DEFAULT_ROUNDS=3
TURN_TIMEOUT=120
MAX_RESPONSE_WORDS=400
SUMMARIZE_AFTER_ROUND=false

# AI Models
CLAUDE_MODEL="sonnet"
CODEX_MODEL="gpt-4o"
GEMINI_MODEL="gemini-2.5-flash"

# Context Management
MAX_CONTEXT_CHARS=8000
INCLUDE_FULL_HISTORY=false

# Retry Settings
RETRY_ON_FAILURE=true
MAX_RETRIES=2
RETRY_DELAY=5
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GROQ_API_KEY` | Groq API key for arbiter functions | (none) |
| `CLAUDE_MODEL` | Claude model selection | `sonnet` |
| `CODEX_MODEL` | Codex model selection | `gpt-4o` |
| `GEMINI_MODEL` | Gemini model selection | `gemini-2.5-flash` |
| `VERBOSE` | Enable debug logging | `false` |

## Output

Debates are saved to `./debates/` with:

```
debates/
  20241201_123456_your-topic/
    transcript.md       # Full debate transcript
    final_synthesis.md  # Combined conclusions
    metadata.json       # Debate metadata
    responses/          # Individual AI responses
    context/            # Round summaries (if enabled)
```

## Personas

View available personas:

```bash
./council.sh --list-personas
```

Personas are defined in `config/personas/` as TOON or JSON files. Each persona provides a custom system prompt that shapes how the AI approaches the debate.

Example personas:
- `philosopher` - Deep analytical thinking
- `hacker` - Pragmatic, systems-oriented
- `scientist` - Evidence-based reasoning
- `futurist` - Forward-looking perspective

## Baseline Assessment

Run baseline assessment to evaluate each AI's capabilities:

```bash
./assess.sh
```

This generates analysis in `assessments/` used for smart Chief Justice selection.

## Project Structure

```
theCouncilofLegends/
  council.sh          # Main entry point
  assess.sh           # Baseline assessment tool
  config/
    council.conf      # Configuration file
    personas/         # Persona definitions (TOON/JSON)
  lib/
    adapters/         # AI CLI adapters (claude, codex, gemini, groq)
    config.sh         # Configuration management
    context.sh        # Context building and summarization
    debate.sh         # Debate orchestration
    scotus.sh         # SCOTUS judicial mode
    utils.sh          # Utility functions
    assessment.sh     # Assessment logic
  debates/            # Saved debate transcripts
  assessments/        # Baseline assessment results
```

## Testing

```bash
# Test all AI adapters
./test_adapters.sh

# Test assessment module
./test_assessment.sh

# Test Groq arbiter
./test_groq.sh
```

## License

MIT
