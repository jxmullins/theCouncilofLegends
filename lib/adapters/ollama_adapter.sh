#!/usr/bin/env bash
#
# The Council of Legends - Ollama Adapter
# Handles invocation of local LLMs via Ollama
# Supports any model available in your local Ollama installation
#

# Default Ollama settings
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"
OLLAMA_TEMPERATURE="${OLLAMA_TEMPERATURE:-0.7}"

# Source LLM manager for registry lookups
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/../llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

# Check for jq dependency (required for JSON parsing)
if ! command -v jq &>/dev/null; then
    log_error "jq is required for Ollama adapter but is not installed"
    log_info "Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)"
    # Don't exit, just warn - function will fail gracefully if called
fi

invoke_ollama() {
    local ai_id="$1"
    local prompt="$2"
    local output_file="$3"
    local system_prompt="${4:-You are a helpful AI assistant participating in a multi-AI council debate.}"

    local error_file="${output_file}.err"

    # Get model and endpoint from registry, with fallbacks to env vars
    local model endpoint
    model=$(get_llm_field "$ai_id" "model" 2>/dev/null) || model="$OLLAMA_MODEL"
    endpoint=$(get_llm_field "$ai_id" "endpoint" 2>/dev/null) || endpoint="$OLLAMA_BASE_URL"

    # Strip any trailing slashes from endpoint
    endpoint="${endpoint%/}"

    log_debug "Ollama invocation: ai=$ai_id model=$model endpoint=$endpoint"

    # Check if Ollama is running
    if ! curl -s --connect-timeout 5 "$endpoint/api/tags" >/dev/null 2>&1; then
        log_error "Ollama is not running at $endpoint"
        echo "[Ollama not available at $endpoint]" > "$output_file"
        return 1
    fi

    # Build the JSON payload for Ollama chat API
    local payload
    payload=$(jq -n \
        --arg model "$model" \
        --arg system "$system_prompt" \
        --arg user "$prompt" \
        --argjson temperature "$OLLAMA_TEMPERATURE" \
        '{
            model: $model,
            messages: [
                { role: "system", content: $system },
                { role: "user", content: $user }
            ],
            stream: false,
            options: {
                temperature: $temperature
            }
        }')

    # Execute API call with timeout
    local exit_code=0
    local response_file="${output_file}.response"

    run_with_timeout "${TURN_TIMEOUT:-180}" curl -s -X POST "$endpoint/api/chat" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > "$response_file" 2>"$error_file" || exit_code=$?

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log_error "Ollama timed out after ${TURN_TIMEOUT}s"
        echo "[Ollama timed out - local model may be loading or slow]" > "$output_file"
        rm -f "$response_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Ollama curl failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        echo "[Ollama request failed]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Check for errors in response
    local api_error
    api_error=$(jq -r '.error // empty' "$response_file" 2>/dev/null)
    if [[ -n "$api_error" ]]; then
        log_error "Ollama error: $api_error"
        echo "[Ollama error: $api_error]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Extract the response content
    local content
    content=$(jq -r '.message.content // empty' "$response_file" 2>/dev/null)

    if [[ -z "$content" ]]; then
        log_error "Ollama returned empty or invalid response"
        log_debug "Raw response: $(cat "$response_file")"
        echo "[Ollama returned invalid response]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Write the extracted content to output file
    echo "$content" > "$output_file"

    # Normalize output for consistency
    normalize_output_file "$output_file"

    # Clean up temp files on success
    rm -f "$response_file" "$error_file"

    log_debug "Ollama response received (${#content} chars)"
    return 0
}

# List available models from Ollama
ollama_list_models() {
    local endpoint="${OLLAMA_BASE_URL:-http://localhost:11434}"

    if ! curl -s --connect-timeout 5 "$endpoint/api/tags" 2>/dev/null | jq -r '.models[].name' 2>/dev/null; then
        log_error "Could not list Ollama models - is Ollama running?"
        return 1
    fi
}

# Check if a specific model is available
ollama_check_model() {
    local model="$1"
    local endpoint="${OLLAMA_BASE_URL:-http://localhost:11434}"

    if curl -s --connect-timeout 5 "$endpoint/api/tags" 2>/dev/null | jq -e ".models[] | select(.name == \"$model\")" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

log_debug "Ollama adapter loaded (default model: $OLLAMA_MODEL, endpoint: $OLLAMA_BASE_URL)"
