#!/usr/bin/env bash
#
# The Council of Legends - LM Studio Adapter
# Handles invocation of local LLMs via LM Studio's OpenAI-compatible API
# LM Studio provides a GUI for running local models with an API server
#

# Default LM Studio settings
LMSTUDIO_BASE_URL="${LMSTUDIO_BASE_URL:-http://localhost:1234}"
LMSTUDIO_MODEL="${LMSTUDIO_MODEL:-local-model}"
LMSTUDIO_MAX_TOKENS="${LMSTUDIO_MAX_TOKENS:-4096}"
LMSTUDIO_TEMPERATURE="${LMSTUDIO_TEMPERATURE:-0.7}"

# Source LLM manager for registry lookups
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/../llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

# Check for jq dependency (required for JSON parsing)
if ! command -v jq &>/dev/null; then
    log_error "jq is required for LM Studio adapter but is not installed"
    log_info "Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)"
fi

invoke_lmstudio() {
    local ai_id="$1"
    local prompt="$2"
    local output_file="$3"
    local system_prompt="${4:-You are a helpful AI assistant participating in a multi-AI council debate.}"

    local error_file="${output_file}.err"

    # Get model and endpoint from registry, with fallbacks to env vars
    local model endpoint
    model=$(get_llm_field "$ai_id" "model" 2>/dev/null) || model="$LMSTUDIO_MODEL"
    endpoint=$(get_llm_field "$ai_id" "endpoint" 2>/dev/null) || endpoint="$LMSTUDIO_BASE_URL"

    # Strip any trailing slashes from endpoint
    endpoint="${endpoint%/}"

    log_debug "LM Studio invocation: ai=$ai_id model=$model endpoint=$endpoint"

    # Check if LM Studio server is running
    if ! curl -s --connect-timeout 5 "$endpoint/v1/models" >/dev/null 2>&1; then
        log_error "LM Studio server is not running at $endpoint"
        log_info "Start LM Studio and enable the local server in settings"
        echo "[LM Studio not available at $endpoint]" > "$output_file"
        return 1
    fi

    # Build the JSON payload (OpenAI-compatible format)
    local payload
    payload=$(jq -n \
        --arg model "$model" \
        --arg system "$system_prompt" \
        --arg user "$prompt" \
        --argjson max_tokens "$LMSTUDIO_MAX_TOKENS" \
        --argjson temperature "$LMSTUDIO_TEMPERATURE" \
        '{
            model: $model,
            messages: [
                { role: "system", content: $system },
                { role: "user", content: $user }
            ],
            max_tokens: $max_tokens,
            temperature: $temperature,
            stream: false
        }')

    # Execute API call with timeout
    local exit_code=0
    local response_file="${output_file}.response"

    run_with_timeout "${TURN_TIMEOUT:-180}" curl -s -X POST "$endpoint/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > "$response_file" 2>"$error_file" || exit_code=$?

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log_error "LM Studio timed out after ${TURN_TIMEOUT}s"
        echo "[LM Studio timed out - model may still be loading]" > "$output_file"
        rm -f "$response_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "LM Studio curl failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        echo "[LM Studio request failed]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Check for API errors in response
    local api_error
    api_error=$(jq -r '.error.message // empty' "$response_file" 2>/dev/null)
    if [[ -n "$api_error" ]]; then
        log_error "LM Studio API error: $api_error"
        echo "[LM Studio error: $api_error]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Extract the response content
    local content
    content=$(jq -r '.choices[0].message.content // empty' "$response_file" 2>/dev/null)

    if [[ -z "$content" ]]; then
        log_error "LM Studio returned empty or invalid response"
        log_debug "Raw response: $(cat "$response_file")"
        echo "[LM Studio returned invalid response]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Write the extracted content to output file
    echo "$content" > "$output_file"

    # Normalize output for consistency
    normalize_output_file "$output_file"

    # Clean up temp files on success
    rm -f "$response_file" "$error_file"

    log_debug "LM Studio response received (${#content} chars)"
    return 0
}

# List available models from LM Studio
lmstudio_list_models() {
    local endpoint="${LMSTUDIO_BASE_URL:-http://localhost:1234}"

    if ! curl -s --connect-timeout 5 "$endpoint/v1/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null; then
        log_error "Could not list LM Studio models - is the server running?"
        return 1
    fi
}

# Check if LM Studio server is available
lmstudio_check_server() {
    local endpoint="${LMSTUDIO_BASE_URL:-http://localhost:1234}"

    if curl -s --connect-timeout 5 "$endpoint/v1/models" >/dev/null 2>&1; then
        log_success "LM Studio server is running at $endpoint"
        return 0
    else
        log_error "LM Studio server not available at $endpoint"
        return 1
    fi
}

log_debug "LM Studio adapter loaded (default model: $LMSTUDIO_MODEL, endpoint: $LMSTUDIO_BASE_URL)"
