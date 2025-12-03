#!/usr/bin/env bash
#
# The Council of Legends - Groq Adapter
# Handles invocation of Groq API for the 4th AI arbiter
# Used for baseline analysis and Chief Justice selection
#

# Default Groq settings
GROQ_MODEL="${GROQ_MODEL:-llama-3.3-70b-versatile}"
GROQ_API_URL="${GROQ_API_URL:-https://api.groq.com/openai/v1/chat/completions}"
GROQ_MAX_TOKENS="${GROQ_MAX_TOKENS:-4096}"
GROQ_TEMPERATURE="${GROQ_TEMPERATURE:-0.7}"

invoke_groq() {
    local prompt="$1"
    local output_file="$2"
    local system_prompt="${3:-You are an impartial AI arbiter analyzing capabilities and making recommendations.}"

    local error_file="${output_file}.err"

    # Check for API key
    if [[ -z "${GROQ_API_KEY:-}" ]]; then
        log_error "GROQ_API_KEY environment variable not set"
        echo "[Groq API key not configured]" > "$output_file"
        return 1
    fi

    # Build the JSON payload
    local payload
    payload=$(jq -n \
        --arg model "$GROQ_MODEL" \
        --arg system "$system_prompt" \
        --arg user "$prompt" \
        --argjson max_tokens "$GROQ_MAX_TOKENS" \
        --argjson temperature "$GROQ_TEMPERATURE" \
        '{
            model: $model,
            messages: [
                { role: "system", content: $system },
                { role: "user", content: $user }
            ],
            max_tokens: $max_tokens,
            temperature: $temperature
        }')

    # Execute API call with timeout
    local exit_code=0
    local response_file="${output_file}.response"

    run_with_timeout "${TURN_TIMEOUT:-120}" curl -s -X POST "$GROQ_API_URL" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > "$response_file" 2>"$error_file" || exit_code=$?

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log_error "Groq timed out after ${TURN_TIMEOUT}s"
        echo "[Groq timed out]" > "$output_file"
        rm -f "$response_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Groq curl failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        rm -f "$response_file"
        return 1
    fi

    # Check for API errors in response
    local api_error
    api_error=$(jq -r '.error.message // empty' "$response_file" 2>/dev/null)
    if [[ -n "$api_error" ]]; then
        log_error "Groq API error: $api_error"
        echo "[Groq API error: $api_error]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Extract the response content
    local content
    content=$(jq -r '.choices[0].message.content // empty' "$response_file" 2>/dev/null)

    if [[ -z "$content" ]]; then
        log_error "Groq returned empty or invalid response"
        log_debug "Raw response: $(cat "$response_file")"
        echo "[Groq returned invalid response]" > "$output_file"
        rm -f "$response_file"
        return 1
    fi

    # Write the extracted content to output file
    echo "$content" > "$output_file"

    # Normalize output for consistency
    normalize_output_file "$output_file"

    # Clean up temp files on success
    rm -f "$response_file" "$error_file"

    log_debug "Groq response received (${#content} chars)"
    return 0
}

# Convenience function for arbiter tasks
invoke_arbiter() {
    local prompt="$1"
    local output_file="$2"
    local task_type="${3:-analysis}"

    local system_prompt
    case "$task_type" in
        baseline)
            system_prompt="You are an impartial AI arbiter for The Council of Legends. Your role is to analyze self-assessment data from council members and generate objective baseline capability scores. Be fair, thorough, and base your analysis solely on the evidence provided. Output structured JSON when requested."
            ;;
        topic)
            system_prompt="You are an impartial AI arbiter for The Council of Legends. Your role is to analyze debate topics and determine which capability categories are most relevant. Assign relevance weights (0.0-1.0) based on how important each skill area is for the given topic. Output structured JSON when requested."
            ;;
        recommendation)
            system_prompt="You are an impartial AI arbiter for The Council of Legends. Your role is to recommend which council member should serve as Chief Justice for a specific debate, based on their capabilities weighted by topic relevance. Provide clear reasoning for your recommendation. Output structured JSON when requested."
            ;;
        *)
            system_prompt="You are an impartial AI arbiter for The Council of Legends. Analyze the provided information objectively and provide structured output."
            ;;
    esac

    invoke_groq "$prompt" "$output_file" "$system_prompt"
}

log_debug "Groq adapter loaded (model: $GROQ_MODEL)"
