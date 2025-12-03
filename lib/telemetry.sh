#!/usr/bin/env bash
#
# The Council of Legends - Telemetry & Replay System
# Structured event logging for debugging and analysis
#

#=============================================================================
# Telemetry Configuration
#=============================================================================

TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-true}"
TELEMETRY_FILE=""

#=============================================================================
# Event Types
#=============================================================================

# Event types for structured logging
declare -A EVENT_TYPES=(
    ["session_start"]="Session started"
    ["session_end"]="Session ended"
    ["debate_start"]="Debate started"
    ["debate_end"]="Debate ended"
    ["round_start"]="Round started"
    ["round_end"]="Round ended"
    ["ai_request"]="AI API request"
    ["ai_response"]="AI API response"
    ["ai_error"]="AI error occurred"
    ["ai_retry"]="AI retry attempted"
    ["cj_selected"]="Chief Justice selected"
    ["persona_set"]="Persona assigned"
    ["persona_changed"]="Persona changed mid-debate"
    ["token_usage"]="Token usage recorded"
    ["budget_warning"]="Budget threshold reached"
    ["budget_exceeded"]="Budget exceeded"
)

#=============================================================================
# Telemetry Initialization
#=============================================================================

# Initialize telemetry for a session
# Args: $1 = debate_dir (where to store telemetry file)
init_telemetry() {
    local debate_dir="${1:-$COUNCIL_ROOT}"

    if [[ "$TELEMETRY_ENABLED" != "true" ]]; then
        log_debug "Telemetry disabled"
        return 0
    fi

    TELEMETRY_FILE="$debate_dir/telemetry.jsonl"

    # Write session start event
    emit_event "session_start" "{
        \"council_version\": \"1.0.0\",
        \"working_dir\": \"$(pwd)\",
        \"user\": \"$(whoami)\",
        \"hostname\": \"$(hostname)\",
        \"shell\": \"$SHELL\"
    }"

    log_debug "Telemetry initialized: $TELEMETRY_FILE"
}

#=============================================================================
# Event Emission
#=============================================================================

# Emit a telemetry event
# Args: $1 = event_type, $2 = event_data (JSON object)
emit_event() {
    local event_type="$1"
    local event_data="${2:-{}}"

    if [[ "$TELEMETRY_ENABLED" != "true" ]] || [[ -z "$TELEMETRY_FILE" ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    local sequence
    sequence=$((${TELEMETRY_SEQUENCE:-0} + 1))
    TELEMETRY_SEQUENCE=$sequence

    # Build the event JSON
    local event_json
    event_json=$(jq -c \
        --arg ts "$timestamp" \
        --arg type "$event_type" \
        --argjson seq "$sequence" \
        '. + {
            timestamp: $ts,
            event: $type,
            sequence: $seq
        }' <<< "$event_data" 2>/dev/null)

    # Fallback if jq fails
    if [[ -z "$event_json" ]]; then
        event_json="{\"timestamp\":\"$timestamp\",\"event\":\"$event_type\",\"sequence\":$sequence,\"raw\":\"$event_data\"}"
    fi

    # Append to telemetry file
    echo "$event_json" >> "$TELEMETRY_FILE"
}

#=============================================================================
# Convenience Event Emitters
#=============================================================================

# Debate lifecycle events
emit_debate_start() {
    local topic="$1"
    local mode="$2"
    local rounds="$3"
    local cj="${4:-none}"

    emit_event "debate_start" "{
        \"topic\": $(jq -n --arg t "$topic" '$t'),
        \"mode\": \"$mode\",
        \"rounds\": $rounds,
        \"chief_justice\": \"$cj\"
    }"
}

emit_debate_end() {
    local debate_dir="$1"
    local duration_secs="${2:-0}"
    local status="${3:-completed}"

    emit_event "debate_end" "{
        \"debate_dir\": \"$debate_dir\",
        \"duration_seconds\": $duration_secs,
        \"status\": \"$status\"
    }"
}

emit_round_start() {
    local round="$1"
    local phase="$2"

    emit_event "round_start" "{
        \"round\": $round,
        \"phase\": \"$phase\"
    }"
}

emit_round_end() {
    local round="$1"
    local duration_secs="${2:-0}"

    emit_event "round_end" "{
        \"round\": $round,
        \"duration_seconds\": $duration_secs
    }"
}

# AI interaction events
emit_ai_request() {
    local ai="$1"
    local model="$2"
    local prompt_length="$3"
    local request_id="${4:-$(date +%s%N)}"

    emit_event "ai_request" "{
        \"ai\": \"$ai\",
        \"model\": \"$model\",
        \"prompt_chars\": $prompt_length,
        \"request_id\": \"$request_id\"
    }"

    echo "$request_id"
}

emit_ai_response() {
    local request_id="$1"
    local ai="$2"
    local response_length="$3"
    local duration_ms="$4"
    local input_tokens="${5:-0}"
    local output_tokens="${6:-0}"

    emit_event "ai_response" "{
        \"request_id\": \"$request_id\",
        \"ai\": \"$ai\",
        \"response_chars\": $response_length,
        \"duration_ms\": $duration_ms,
        \"input_tokens\": $input_tokens,
        \"output_tokens\": $output_tokens
    }"
}

emit_ai_error() {
    local ai="$1"
    local error_type="$2"
    local error_message="$3"
    local request_id="${4:-}"

    emit_event "ai_error" "{
        \"ai\": \"$ai\",
        \"error_type\": \"$error_type\",
        \"message\": $(jq -n --arg m "$error_message" '$m'),
        \"request_id\": \"$request_id\"
    }"
}

emit_ai_retry() {
    local ai="$1"
    local attempt="$2"
    local max_attempts="$3"
    local reason="$4"

    emit_event "ai_retry" "{
        \"ai\": \"$ai\",
        \"attempt\": $attempt,
        \"max_attempts\": $max_attempts,
        \"reason\": \"$reason\"
    }"
}

# Chief Justice events
emit_cj_selected() {
    local cj="$1"
    local method="$2"
    local confidence="${3:-1.0}"

    emit_event "cj_selected" "{
        \"chief_justice\": \"$cj\",
        \"selection_method\": \"$method\",
        \"confidence\": $confidence
    }"
}

# Persona events
emit_persona_set() {
    local ai="$1"
    local persona="$2"

    emit_event "persona_set" "{
        \"ai\": \"$ai\",
        \"persona\": \"$persona\"
    }"
}

emit_persona_changed() {
    local ai="$1"
    local old_persona="$2"
    local new_persona="$3"
    local reason="$4"

    emit_event "persona_changed" "{
        \"ai\": \"$ai\",
        \"old_persona\": \"$old_persona\",
        \"new_persona\": \"$new_persona\",
        \"reason\": \"$reason\"
    }"
}

#=============================================================================
# Session Summary
#=============================================================================

# Generate a summary of the telemetry session
finalize_telemetry() {
    if [[ -z "$TELEMETRY_FILE" ]] || [[ ! -f "$TELEMETRY_FILE" ]]; then
        return 0
    fi

    # Emit session end
    emit_event "session_end" "{
        \"total_events\": $TELEMETRY_SEQUENCE
    }"

    log_debug "Telemetry finalized: $TELEMETRY_SEQUENCE events recorded"
}

#=============================================================================
# Replay Utilities
#=============================================================================

# Print telemetry events in a human-readable format
replay_telemetry() {
    local telemetry_file="$1"

    if [[ ! -f "$telemetry_file" ]]; then
        log_error "Telemetry file not found: $telemetry_file"
        return 1
    fi

    echo ""
    echo -e "${BOLD}Telemetry Replay${NC}"
    separator "=" 70

    local line_num=0
    while IFS= read -r line; do
        ((line_num++))

        local event_type timestamp
        event_type=$(echo "$line" | jq -r '.event // "unknown"')
        timestamp=$(echo "$line" | jq -r '.timestamp // ""')

        # Format timestamp for display
        local ts_display=""
        if [[ -n "$timestamp" ]]; then
            ts_display=$(echo "$timestamp" | cut -d'T' -f2 | cut -d'+' -f1 | cut -d'-' -f1)
        fi

        # Color based on event type
        local color="$NC"
        case "$event_type" in
            *_start) color="$GREEN" ;;
            *_end) color="$BLUE" ;;
            *_error) color="$RED" ;;
            *_retry|*_warning) color="$YELLOW" ;;
            ai_*) color="$CYAN" ;;
        esac

        # Print formatted event
        printf "${WHITE}%3d${NC} ${PURPLE}%s${NC} ${color}%-20s${NC}" "$line_num" "$ts_display" "$event_type"

        # Print key details based on event type
        case "$event_type" in
            debate_start)
                echo " topic=$(echo "$line" | jq -r '.topic // ""' | cut -c1-40)..."
                ;;
            ai_request)
                echo " ai=$(echo "$line" | jq -r '.ai') chars=$(echo "$line" | jq -r '.prompt_chars')"
                ;;
            ai_response)
                echo " ai=$(echo "$line" | jq -r '.ai') chars=$(echo "$line" | jq -r '.response_chars') ms=$(echo "$line" | jq -r '.duration_ms')"
                ;;
            ai_error)
                echo " ai=$(echo "$line" | jq -r '.ai') type=$(echo "$line" | jq -r '.error_type')"
                ;;
            cj_selected)
                echo " cj=$(echo "$line" | jq -r '.chief_justice') method=$(echo "$line" | jq -r '.selection_method')"
                ;;
            round_start|round_end)
                echo " round=$(echo "$line" | jq -r '.round')"
                ;;
            *)
                echo ""
                ;;
        esac
    done < "$telemetry_file"

    separator "=" 70
    echo "Total events: $line_num"
    echo ""
}

# Get statistics from telemetry
telemetry_stats() {
    local telemetry_file="$1"

    if [[ ! -f "$telemetry_file" ]]; then
        return 1
    fi

    echo ""
    echo -e "${BOLD}Telemetry Statistics${NC}"
    separator "-" 40

    # Count events by type
    echo "Events by type:"
    jq -r '.event' "$telemetry_file" 2>/dev/null | sort | uniq -c | sort -rn | while read count event; do
        printf "  %-25s %d\n" "$event" "$count"
    done

    # AI request stats
    local total_requests ai_requests
    total_requests=$(grep -c '"event":"ai_request"' "$telemetry_file" 2>/dev/null || echo 0)
    if [[ $total_requests -gt 0 ]]; then
        echo ""
        echo "AI Requests:"
        for ai in claude codex gemini groq; do
            ai_requests=$(grep '"event":"ai_request"' "$telemetry_file" | grep "\"ai\":\"$ai\"" | wc -l | tr -d ' ')
            if [[ $ai_requests -gt 0 ]]; then
                printf "  %-10s %d requests\n" "$ai" "$ai_requests"
            fi
        done
    fi

    echo ""
}

log_debug "Telemetry module loaded"
