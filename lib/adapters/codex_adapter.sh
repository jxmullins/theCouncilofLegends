#!/usr/bin/env bash
#
# The Council of Legends - Codex CLI Adapter
# Handles invocation of OpenAI Codex CLI for non-interactive use
#

invoke_codex() {
    local prompt="$1"
    local output_file="$2"
    local system_prompt="${3:-}"

    local error_file="${output_file}.err"

    # Codex exec requires full prompt (no separate system prompt flag)
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
    # Note: Codex with ChatGPT accounts doesn't support custom model selection
    # It uses the default model assigned to the account
    local cmd_args=("exec" "--skip-git-repo-check" "$full_prompt")

    # Execute with timeout
    local exit_code=0
    run_with_timeout "${TURN_TIMEOUT:-120}" codex "${cmd_args[@]}" > "$output_file" 2>"$error_file" || exit_code=$?

    # Handle results
    if [[ $exit_code -eq 124 ]]; then
        log_error "Codex timed out after ${TURN_TIMEOUT}s"
        echo "[Codex timed out]" > "$output_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Codex failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        return 1
    fi

    # Verify output
    if [[ ! -s "$output_file" ]]; then
        log_error "Codex returned empty response"
        return 1
    fi

    # Normalize output for consistency
    normalize_output_file "$output_file"

    # Clean up error file on success
    rm -f "$error_file"

    return 0
}
