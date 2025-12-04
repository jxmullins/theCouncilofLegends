#!/usr/bin/env bash
#
# The Council of Legends - Generic OpenAI-Compatible Adapter
# Handles invocation of any API that follows the OpenAI chat completions format
# Works with: vLLM, Text Generation Inference, LocalAI, Anyscale, Together AI, etc.
#

# Default settings (can be overridden per-model in registry)
OPENAI_COMPATIBLE_MAX_TOKENS="${OPENAI_COMPATIBLE_MAX_TOKENS:-4096}"
OPENAI_COMPATIBLE_TEMPERATURE="${OPENAI_COMPATIBLE_TEMPERATURE:-0.7}"

# Source LLM manager for registry lookups
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/../llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

# Check for jq dependency (required for JSON parsing)
if ! command -v jq &>/dev/null; then
    log_error "jq is required for OpenAI-compatible adapter but is not installed"
    log_info "Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)"
fi

invoke_openai_compatible() {
    local ai_id="$1"
    local prompt="$2"
    local output_file="$3"
    local system_prompt="${4:-You are a helpful AI assistant participating in a multi-AI council debate.}"

    local error_file="${output_file}.err"

    # Get configuration from registry
    local model endpoint auth_type auth_env_var api_key
    model=$(get_llm_field "$ai_id" "model" 2>/dev/null)
    endpoint=$(get_llm_field "$ai_id" "endpoint" 2>/dev/null)
    auth_type=$(get_llm_field "$ai_id" "auth_type" 2>/dev/null)
    auth_env_var=$(get_llm_field "$ai_id" "auth_env_var" 2>/dev/null)

    # Validate required fields
    if [[ -z "$endpoint" ]]; then
        log_error "No endpoint configured for '$ai_id' in registry"
        echo "[No endpoint configured for $ai_id]" > "$output_file"
        return 1
    fi

    if [[ -z "$model" ]]; then
        log_error "No model configured for '$ai_id' in registry"
        echo "[No model configured for $ai_id]" > "$output_file"
        return 1
    fi

    # Strip any trailing slashes from endpoint
    endpoint="${endpoint%/}"

    # Handle authentication
    local auth_header=""
    if [[ "$auth_type" == "api_key" || "$auth_type" == "token" ]]; then
        if [[ -n "$auth_env_var" ]]; then
            api_key="${!auth_env_var:-}"
            if [[ -z "$api_key" ]]; then
                log_error "API key not set: $auth_env_var environment variable is empty"
                echo "[API key not configured: set $auth_env_var]" > "$output_file"
                return 1
            fi
            auth_header="-H \"Authorization: Bearer $api_key\""
        fi
    fi

    log_debug "OpenAI-compatible invocation: ai=$ai_id model=$model endpoint=$endpoint"

    # Build the JSON payload
    local payload
    payload=$(jq -n \
        --arg model "$model" \
        --arg system "$system_prompt" \
        --arg user "$prompt" \
        --argjson max_tokens "$OPENAI_COMPATIBLE_MAX_TOKENS" \
        --argjson temperature "$OPENAI_COMPATIBLE_TEMPERATURE" \
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

    # Build curl command (handle auth header separately to avoid quoting issues)
    if [[ -n "$api_key" ]]; then
        run_with_timeout "${TURN_TIMEOUT:-180}" curl -s -X POST "$endpoint/v1/chat/completions" \
            -H "Authorization: Bearer $api_key" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            > "$response_file" 2>"$error_file" || exit_code=$?
    else
        run_with_timeout "${TURN_TIMEOUT:-180}" curl -s -X POST "$endpoint/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            > "$response_file" 2>"$error_file" || exit_code=$?
    fi

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log_error "OpenAI-compatible API timed out after ${TURN_TIMEOUT}s"
        echo "[API timed out]" > "$output_file"
        rm -f "$response_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "OpenAI-compatible API curl failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        echo "[API request failed]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Check for API errors in response
    local api_error
    api_error=$(jq -r '.error.message // .error // empty' "$response_file" 2>/dev/null)
    if [[ -n "$api_error" ]]; then
        log_error "API error: $api_error"
        echo "[API error: $api_error]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Extract the response content
    local content
    content=$(jq -r '.choices[0].message.content // empty' "$response_file" 2>/dev/null)

    if [[ -z "$content" ]]; then
        log_error "API returned empty or invalid response"
        log_debug "Raw response: $(cat "$response_file")"
        echo "[API returned invalid response]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Write the extracted content to output file
    echo "$content" > "$output_file"

    # Normalize output for consistency
    normalize_output_file "$output_file"

    # Clean up temp files on success
    rm -f "$response_file" "$error_file"

    log_debug "OpenAI-compatible response received (${#content} chars)"
    return 0
}

# Test connectivity to an OpenAI-compatible endpoint
test_openai_compatible_endpoint() {
    local endpoint="$1"
    local api_key="${2:-}"

    # Strip trailing slash
    endpoint="${endpoint%/}"

    log_info "Testing endpoint: $endpoint"

    local curl_args=(-s --connect-timeout 10 "$endpoint/v1/models")
    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi

    if curl "${curl_args[@]}" 2>/dev/null | jq -e '.data' >/dev/null 2>&1; then
        log_success "Endpoint is reachable and responding"
        return 0
    else
        log_error "Could not connect to endpoint or received invalid response"
        return 1
    fi
}

log_debug "OpenAI-compatible adapter loaded"
