#!/usr/bin/env bash
#
# The Council of Legends - Gemini CLI Adapter
# Handles invocation of Google Gemini CLI for non-interactive use
#

invoke_gemini() {
    local prompt="$1"
    local output_file="$2"
    local system_prompt="${3:-}"

    local error_file="${output_file}.err"

    # Gemini uses positional query (no separate system prompt flag)
    # Prepend system prompt to the main prompt
    local full_prompt=""
    if [[ -n "$system_prompt" ]]; then
        full_prompt="${system_prompt}

---

${prompt}"
    else
        full_prompt="$prompt"
    fi

    # Build command arguments
    local cmd_args=("$full_prompt" "--output-format" "text")

    # Add model if specified
    if [[ -n "${GEMINI_MODEL:-}" ]]; then
        cmd_args+=("-m" "$GEMINI_MODEL")
    fi

    # Execute with timeout
    local exit_code=0
    run_with_timeout "${TURN_TIMEOUT:-120}" gemini "${cmd_args[@]}" > "$output_file" 2>"$error_file" || exit_code=$?

    # Handle results
    if [[ $exit_code -eq 124 ]]; then
        log_error "Gemini timed out after ${TURN_TIMEOUT}s"
        echo "[Gemini timed out]" > "$output_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Gemini failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        return 1
    fi

    # Verify output
    if [[ ! -s "$output_file" ]]; then
        log_error "Gemini returned empty response"
        return 1
    fi

    # Clean up error file on success
    rm -f "$error_file"

    return 0
}
