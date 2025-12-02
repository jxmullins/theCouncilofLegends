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
# 4th AI Arbiter (Groq/Llama) - used for baseline analysis and Chief Justice selection
GROQ_MODEL="${GROQ_MODEL:-llama-3.3-70b-versatile}"
GROQ_MAX_TOKENS="${GROQ_MAX_TOKENS:-4096}"
GROQ_TEMPERATURE="${GROQ_TEMPERATURE:-0.7}"
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

    # Refresh persona selections from config (they may have been set in council.conf)
    refresh_persona_selections
}

# Refresh persona selections from environment/config variables
# Called after config is loaded to pick up CLAUDE_PERSONA, etc.
refresh_persona_selections() {
    if [[ -n "${CLAUDE_PERSONA:-}" ]]; then
        PERSONA_SELECTIONS[claude]="$CLAUDE_PERSONA"
    fi
    if [[ -n "${CODEX_PERSONA:-}" ]]; then
        PERSONA_SELECTIONS[codex]="$CODEX_PERSONA"
    fi
    if [[ -n "${GEMINI_PERSONA:-}" ]]; then
        PERSONA_SELECTIONS[gemini]="$GEMINI_PERSONA"
    fi
}

#=============================================================================
# Persona Loading (Universal TOON Catalog)
#=============================================================================

# TOON utility path
TOON_UTIL="$COUNCIL_ROOT/lib/toon_util.py"

# Global persona selections (can be set via CLI or config)
declare -A PERSONA_SELECTIONS
PERSONA_SELECTIONS[claude]="${CLAUDE_PERSONA:-default}"
PERSONA_SELECTIONS[codex]="${CODEX_PERSONA:-default}"
PERSONA_SELECTIONS[gemini]="${GEMINI_PERSONA:-default}"

# AI provider mapping
get_ai_provider() {
    local ai="$1"
    case "$ai" in
        claude) echo "Anthropic" ;;
        codex)  echo "OpenAI" ;;
        gemini) echo "Google" ;;
        *)      echo "Unknown" ;;
    esac
}

# Set persona for a specific AI
set_persona() {
    local ai="$1"
    local persona="$2"
    PERSONA_SELECTIONS[$ai]="$persona"
}

# Get current persona for an AI
get_persona() {
    local ai="$1"
    echo "${PERSONA_SELECTIONS[$ai]:-default}"
}

# Get persona file path (TOON format, with JSON fallback)
get_persona_file() {
    local persona="$1"
    local toon_file="$COUNCIL_ROOT/config/personas/${persona}.toon"
    local json_file="$COUNCIL_ROOT/config/personas/${persona}.json"

    # Prefer TOON, fall back to JSON
    if [[ -f "$toon_file" ]]; then
        echo "$toon_file"
    else
        echo "$json_file"
    fi
}

# Read field from persona file (TOON or JSON)
read_persona_field() {
    local persona_file="$1"
    local field="$2"

    if [[ "$persona_file" == *.toon ]]; then
        "$TOON_UTIL" get "$persona_file" "$field"
    else
        jq -r ".$field // empty" "$persona_file"
    fi
}

# Load persona system prompt (TOON catalog with template substitution)
load_persona() {
    local ai="$1"
    local persona="${2:-${PERSONA_SELECTIONS[$ai]:-default}}"

    # Get AI name and provider for template substitution
    local ai_name provider
    ai_name=$(get_ai_name "$ai")
    provider=$(get_ai_provider "$ai")

    # Universal persona file (config/personas/{persona}.toon or .json)
    local persona_file
    persona_file=$(get_persona_file "$persona")

    if [[ -f "$persona_file" ]]; then
        # Extract prompt_template and substitute placeholders
        local prompt
        prompt=$(read_persona_field "$persona_file" "prompt_template")

        # Substitute placeholders in template
        prompt="${prompt//\{\{AI_NAME\}\}/$ai_name}"
        prompt="${prompt//\{\{PROVIDER\}\}/$provider}"
        echo "$prompt"
    else
        # Return default persona
        echo "You are $ai_name (powered by $provider), participating in The Council of Legends - a collaborative debate between AI assistants."
    fi
}

# Get persona display name (combines AI name with persona name)
get_persona_display_name() {
    local ai="$1"
    local persona="${2:-${PERSONA_SELECTIONS[$ai]:-default}}"
    local persona_file
    persona_file=$(get_persona_file "$persona")

    local ai_name
    ai_name=$(get_ai_name "$ai")

    if [[ -f "$persona_file" ]]; then
        local persona_name
        persona_name=$(read_persona_field "$persona_file" "name")
        if [[ "$persona" == "default" ]]; then
            echo "$ai_name"
        else
            echo "$ai_name (${persona_name})"
        fi
    else
        echo "$ai_name"
    fi
}

# Get persona metadata field
get_persona_field() {
    local persona="$1"
    local field="$2"
    local persona_file
    persona_file=$(get_persona_file "$persona")

    if [[ -f "$persona_file" ]]; then
        read_persona_field "$persona_file" "$field"
    fi
}

# List all available personas (TOON catalog with JSON fallback)
list_all_personas() {
    local personas_dir="$COUNCIL_ROOT/config/personas"

    # Get unique persona IDs (prefer .toon over .json)
    local -A seen_personas=()
    for persona_file in "$personas_dir"/*.toon "$personas_dir"/*.json; do
        if [[ -f "$persona_file" ]]; then
            local persona_id filename
            filename=$(basename "$persona_file")
            # Strip extension using bash parameter expansion
            persona_id="${filename%.toon}"
            persona_id="${persona_id%.json}"

            # Skip if we've already processed this persona (TOON takes priority)
            if [[ -v "seen_personas[$persona_id]" ]]; then
                continue
            fi
            seen_personas[$persona_id]=1

            local name description
            name=$(read_persona_field "$persona_file" "name")
            description=$(read_persona_field "$persona_file" "description")
            echo "${persona_id}|${name:-$persona_id}|${description:-No description}"
        fi
    done
}

# Validate persona exists (TOON or JSON)
validate_persona() {
    local persona="$1"
    local toon_file="$COUNCIL_ROOT/config/personas/${persona}.toon"
    local json_file="$COUNCIL_ROOT/config/personas/${persona}.json"
    [[ -f "$toon_file" ]] || [[ -f "$json_file" ]]
}

# Get persona tags (for marketplace/filtering)
get_persona_tags() {
    local persona="$1"
    local persona_file
    persona_file=$(get_persona_file "$persona")

    if [[ -f "$persona_file" ]]; then
        if [[ "$persona_file" == *.toon ]]; then
            # TOON util returns JSON array, convert to comma-separated
            "$TOON_UTIL" get "$persona_file" "tags" | jq -r 'join(", ")'
        else
            jq -r '.tags // [] | join(", ")' "$persona_file"
        fi
    fi
}

# Get persona info (formatted for display)
get_persona_info() {
    local persona="$1"
    local persona_file
    persona_file=$(get_persona_file "$persona")

    if [[ -f "$persona_file" ]]; then
        local name version author description tags
        name=$(read_persona_field "$persona_file" "name")
        version=$(read_persona_field "$persona_file" "version")
        author=$(read_persona_field "$persona_file" "author")
        description=$(read_persona_field "$persona_file" "description")
        tags=$(get_persona_tags "$persona")

        echo "Name: $name"
        echo "Version: $version"
        echo "Author: ${author:-Unknown}"
        echo "Description: $description"
        echo "Tags: $tags"
    fi
}

get_ai_color() {
    local ai="$1"
    case "$ai" in
        claude) echo "$CLAUDE_COLOR" ;;
        codex)  echo "$CODEX_COLOR" ;;
        gemini) echo "$GEMINI_COLOR" ;;
        groq)   echo "$GROQ_COLOR" ;;
        *)      echo "$WHITE" ;;
    esac
}

get_ai_name() {
    local ai="$1"
    case "$ai" in
        claude) echo "Claude" ;;
        codex)  echo "Codex" ;;
        gemini) echo "Gemini" ;;
        groq)   echo "Arbiter" ;;
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
    },
    "personas": {
        "claude": "${PERSONA_SELECTIONS[claude]:-default}",
        "codex": "${PERSONA_SELECTIONS[codex]:-default}",
        "gemini": "${PERSONA_SELECTIONS[gemini]:-default}"
    }
}
EOF
}
