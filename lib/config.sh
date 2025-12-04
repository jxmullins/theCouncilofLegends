#!/usr/bin/env bash
#
# The Council of Legends - Configuration Management
# Loads and manages configuration settings
#

# Get the script directory
COUNCIL_ROOT="${COUNCIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Source LLM manager for dynamic council membership
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

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
        # Safe config loading - only allow KEY=VALUE patterns
        _safe_load_config "$config_file"
    else
        log_warn "Configuration file not found: $config_file (using defaults)"
    fi

    # Ensure debates directory exists
    ensure_dir "$DEBATES_DIR"

    # Refresh persona selections from config (they may have been set in council.conf)
    refresh_persona_selections
}

# Safe configuration loader - only allows KEY=VALUE patterns
# Prevents arbitrary code execution from config files
_safe_load_config() {
    local config_file="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Match KEY=VALUE or KEY="VALUE" patterns only
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Reject values containing shell metacharacters that could be dangerous
            if [[ "$value" =~ [\$\`\(\)\;\&\|] ]]; then
                log_warn "Config line $line_num: Ignoring potentially unsafe value for $key"
                continue
            fi

            # Export the variable
            export "$key=$value"
            log_debug "Config: $key set"
        else
            # Line doesn't match safe pattern
            if [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
                log_debug "Config line $line_num: Ignoring non-standard line"
            fi
        fi
    done < "$config_file"
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

#=============================================================================
# Dynamic Persona Switching
#=============================================================================

# Dynamic persona mode flag
DYNAMIC_PERSONAS="${DYNAMIC_PERSONAS:-false}"

# History of persona switches during debate
declare -a PERSONA_HISTORY=()

# Enable dynamic persona switching
enable_dynamic_personas() {
    DYNAMIC_PERSONAS="true"
    log_info "Dynamic persona switching enabled"
}

# Disable dynamic persona switching
disable_dynamic_personas() {
    DYNAMIC_PERSONAS="false"
}

# Check if dynamic personas are enabled
is_dynamic_personas_enabled() {
    [[ "$DYNAMIC_PERSONAS" == "true" ]]
}

# Record a persona switch to history
record_persona_switch() {
    local round="$1"
    local ai="$2"
    local old_persona="$3"
    local new_persona="$4"
    local reason="${5:-}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local entry
    entry=$(jq -n \
        --arg round "$round" \
        --arg ai "$ai" \
        --arg from "$old_persona" \
        --arg to "$new_persona" \
        --arg reason "$reason" \
        --arg time "$timestamp" \
        '{round: ($round | tonumber), ai: $ai, from: $from, to: $to, reason: $reason, timestamp: $time}')

    PERSONA_HISTORY+=("$entry")
    log_info "Persona switch: $ai changed from $old_persona to $new_persona"
}

# Get persona history as JSON array
get_persona_history() {
    if [[ ${#PERSONA_HISTORY[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi

    printf '%s\n' "${PERSONA_HISTORY[@]}" | jq -s '.'
}

# Switch persona for an AI and record it
switch_persona() {
    local round="$1"
    local ai="$2"
    local new_persona="$3"
    local reason="${4:-manual switch}"

    local old_persona
    old_persona=$(get_persona "$ai")

    if [[ "$old_persona" == "$new_persona" ]]; then
        return 0  # No change needed
    fi

    # Validate new persona exists
    local persona_file
    persona_file=$(get_persona_file "$new_persona")
    if [[ ! -f "$persona_file" ]]; then
        log_warn "Persona '$new_persona' not found, keeping '$old_persona'"
        return 1
    fi

    set_persona "$ai" "$new_persona"
    record_persona_switch "$round" "$ai" "$old_persona" "$new_persona" "$reason"
    return 0
}

# Get all available persona IDs
list_available_persona_ids() {
    local toon_files=("$COUNCIL_ROOT"/config/personas/*.toon)
    local ids=()

    for file in "${toon_files[@]}"; do
        if [[ -f "$file" ]]; then
            local basename
            basename=$(basename "$file" .toon)
            ids+=("$basename")
        fi
    done

    printf '%s\n' "${ids[@]}"
}

# Suggest persona switches based on debate context (calls arbiter)
# Args: $1 = debate_dir, $2 = round number, $3 = topic
# Returns: JSON with suggested switches
suggest_persona_switches() {
    local debate_dir="$1"
    local round="$2"
    local topic="$3"

    if ! is_dynamic_personas_enabled; then
        echo '{"suggestions": []}'
        return 0
    fi

    # Get available personas
    local available_personas
    available_personas=$(list_available_persona_ids | jq -R -s 'split("\n") | map(select(length > 0))')

    # Get current personas
    local current_personas
    current_personas=$(jq -n \
        --arg claude "$(get_persona claude)" \
        --arg codex "$(get_persona codex)" \
        --arg gemini "$(get_persona gemini)" \
        '{claude: $claude, codex: $codex, gemini: $gemini}')

    # Get debate context from recent rounds
    local context=""
    local prev_round=$((round - 1))
    local members
    mapfile -t members < <(get_council_members)
    for ai in "${members[@]}"; do
        local prev_file="$debate_dir/responses/round_${prev_round}_${ai}.md"
        if [[ -f "$prev_file" ]]; then
            local snippet
            snippet=$(head -20 "$prev_file" | tr '\n' ' ' | cut -c1-200)
            context+="$ai (last round): $snippet... "
        fi
    done

    # Build prompt for arbiter
    local prompt
    prompt=$(cat <<EOF
Analyze the debate and suggest persona switches to improve coverage and diversity.

TOPIC: $topic
ROUND: $round

CURRENT PERSONAS:
$current_personas

AVAILABLE PERSONAS:
$available_personas

RECENT CONTEXT:
$context

Consider:
1. Are important perspectives missing? (e.g., no ethical focus when ethics are relevant)
2. Is there too much agreement? (might need a contrarian persona)
3. Has the debate stagnated? (might need fresh perspectives)
4. Are technical details missing? (might need specialist personas)

Output ONLY valid JSON:
{
  "suggestions": [
    {"ai": "claude|codex|gemini", "new_persona": "persona_id", "reason": "brief reason"}
  ],
  "reasoning": "overall analysis of persona balance"
}

If no changes needed, return {"suggestions": [], "reasoning": "current balance is good"}
EOF
)

    # Invoke arbiter for suggestions
    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/persona_suggest.XXXXXX")
    trap "rm -f '$temp_file'" RETURN

    # Source groq adapter if not already loaded
    local adapter_file="$COUNCIL_ROOT/lib/adapters/groq_adapter.sh"
    if [[ -f "$adapter_file" ]]; then
        source "$adapter_file"

        if invoke_groq "$prompt" "$temp_file"; then
            local response
            response=$(cat "$temp_file")
            # Try to extract JSON
            if echo "$response" | jq . >/dev/null 2>&1; then
                echo "$response"
                return 0
            fi
        fi
    fi

    # Fallback: no suggestions
    echo '{"suggestions": [], "reasoning": "arbiter unavailable"}'
}

# Apply suggested persona switches
# Args: $1 = suggestions JSON, $2 = round number
apply_persona_suggestions() {
    local suggestions_json="$1"
    local round="$2"

    local count
    count=$(echo "$suggestions_json" | jq '.suggestions | length')

    if [[ "$count" -eq 0 ]]; then
        log_debug "No persona switches suggested for round $round"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Dynamic Persona Suggestions for Round $round:${NC}"

    # Apply each suggestion
    echo "$suggestions_json" | jq -c '.suggestions[]' | while read -r suggestion; do
        local ai new_persona reason
        ai=$(echo "$suggestion" | jq -r '.ai')
        new_persona=$(echo "$suggestion" | jq -r '.new_persona')
        reason=$(echo "$suggestion" | jq -r '.reason')

        echo "  • $ai: switching to $new_persona ($reason)"
        switch_persona "$round" "$ai" "$new_persona" "$reason"
    done

    echo ""
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
        "initial": {
            "claude": "${PERSONA_SELECTIONS[claude]:-default}",
            "codex": "${PERSONA_SELECTIONS[codex]:-default}",
            "gemini": "${PERSONA_SELECTIONS[gemini]:-default}"
        },
        "dynamic_enabled": $DYNAMIC_PERSONAS
    }
}
EOF
}

# Update metadata with persona history at end of debate
update_metadata_with_persona_history() {
    local debate_dir="$1"
    local metadata_file="$debate_dir/metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        return 1
    fi

    local persona_history
    persona_history=$(get_persona_history)

    local final_personas
    final_personas=$(jq -n \
        --arg claude "$(get_persona claude)" \
        --arg codex "$(get_persona codex)" \
        --arg gemini "$(get_persona gemini)" \
        '{claude: $claude, codex: $codex, gemini: $gemini}')

    # Update the metadata file
    local temp_file="${metadata_file}.tmp"
    jq --argjson history "$persona_history" \
       --argjson final "$final_personas" \
       '.personas.final = $final | .personas.switches = $history' \
       "$metadata_file" > "$temp_file"
    mv "$temp_file" "$metadata_file"

    log_debug "Metadata updated with persona history (${#PERSONA_HISTORY[@]} switches)"
}
