#!/usr/bin/env bash
#
# The Council of Legends - Configuration Management
# Loads and manages configuration settings
#

# Get the script directory
COUNCIL_ROOT="${COUNCIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

#=============================================================================
# Default Values (fallbacks if config not loaded)
#=============================================================================

DEFAULT_ROUNDS="${DEFAULT_ROUNDS:-3}"
TURN_TIMEOUT="${TURN_TIMEOUT:-120}"
MAX_RESPONSE_WORDS="${MAX_RESPONSE_WORDS:-400}"
SUMMARIZE_AFTER_ROUND="${SUMMARIZE_AFTER_ROUND:-false}"
CLAUDE_MODEL="${CLAUDE_MODEL:-sonnet}"
CODEX_MODEL="${CODEX_MODEL:-o3}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
PARALLEL_OPENING="${PARALLEL_OPENING:-false}"
RETRY_ON_FAILURE="${RETRY_ON_FAILURE:-true}"
MAX_RETRIES="${MAX_RETRIES:-2}"
RETRY_DELAY="${RETRY_DELAY:-5}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-markdown}"
SAVE_DEBATES="${SAVE_DEBATES:-true}"
DEBATES_DIR="${DEBATES_DIR:-./debates}"
USE_COLORS="${USE_COLORS:-true}"
VERBOSE="${VERBOSE:-false}"
MAX_CONTEXT_CHARS="${MAX_CONTEXT_CHARS:-8000}"
INCLUDE_FULL_HISTORY="${INCLUDE_FULL_HISTORY:-false}"

#=============================================================================
# Configuration Loading
#=============================================================================

load_config() {
    local config_file="${1:-$COUNCIL_ROOT/config/council.conf}"

    if [[ -f "$config_file" ]]; then
        log_debug "Loading configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_warn "Configuration file not found: $config_file (using defaults)"
    fi

    # Ensure debates directory exists
    ensure_dir "$DEBATES_DIR"
}

#=============================================================================
# Persona Loading
#=============================================================================

load_persona() {
    local ai="$1"
    local persona_file="$COUNCIL_ROOT/config/personas/${ai}.persona"

    if [[ -f "$persona_file" ]]; then
        # Source the persona file to get SYSTEM_PROMPT
        # shellcheck source=/dev/null
        source "$persona_file"
        echo "$SYSTEM_PROMPT"
    else
        # Return default persona
        case "$ai" in
            claude)
                echo "You are Claude, an AI assistant by Anthropic, participating in a collaborative debate."
                ;;
            codex)
                echo "You are Codex, an AI assistant by OpenAI, participating in a collaborative debate."
                ;;
            gemini)
                echo "You are Gemini, an AI assistant by Google, participating in a collaborative debate."
                ;;
            *)
                echo "You are an AI assistant participating in a collaborative debate."
                ;;
        esac
    fi
}

get_ai_color() {
    local ai="$1"
    case "$ai" in
        claude) echo "$CLAUDE_COLOR" ;;
        codex)  echo "$CODEX_COLOR" ;;
        gemini) echo "$GEMINI_COLOR" ;;
        *)      echo "$WHITE" ;;
    esac
}

get_ai_name() {
    local ai="$1"
    case "$ai" in
        claude) echo "Claude" ;;
        codex)  echo "Codex" ;;
        gemini) echo "Gemini" ;;
        *)      echo "$ai" ;;
    esac
}

#=============================================================================
# Debate Directory Management
#=============================================================================

create_debate_directory() {
    local topic="$1"
    local timestamp
    timestamp=$(timestamp)
    local slug
    slug=$(slugify "$topic")
    local debate_dir="$DEBATES_DIR/${timestamp}_${slug}"

    mkdir -p "$debate_dir"/{responses,context}
    echo "$debate_dir"
}

save_metadata() {
    local debate_dir="$1"
    local topic="$2"
    local mode="$3"
    local rounds="$4"

    cat > "$debate_dir/metadata.json" <<EOF
{
    "topic": $(printf '%s' "$topic" | jq -Rs .),
    "mode": "$mode",
    "rounds": $rounds,
    "started_at": "$(human_date)",
    "config": {
        "claude_model": "$CLAUDE_MODEL",
        "codex_model": "$CODEX_MODEL",
        "gemini_model": "$GEMINI_MODEL",
        "turn_timeout": $TURN_TIMEOUT
    }
}
EOF
}
