#!/usr/bin/env bash
#
# The Council of Legends - Claude CLI Adapter
# Handles invocation of Claude Code CLI for non-interactive use
#

invoke_claude() {
    local prompt="$1"
    local output_file="$2"
    local system_prompt="${3:-}"

    local error_file="${output_file}.err"

    # Build command arguments
    local cmd_args=("-p")

    # Add system prompt if provided
    if [[ -n "$system_prompt" ]]; then
        cmd_args+=("--system-prompt" "$system_prompt")
    fi

    # Add model if specified
    if [[ -n "${CLAUDE_MODEL:-}" ]]; then
        cmd_args+=("--model" "$CLAUDE_MODEL")
    fi

    # Add the prompt
    cmd_args+=("$prompt")

    # Handle placeholder ANTHROPIC_API_KEY
    local env_cmd=""
    if [[ "${ANTHROPIC_API_KEY:-}" == *"your-"* ]] || [[ "${ANTHROPIC_API_KEY:-}" == *"placeholder"* ]]; then
        log_debug "Unsetting placeholder ANTHROPIC_API_KEY for Claude CLI"
        env_cmd="env -u ANTHROPIC_API_KEY"
    fi

    # Execute with timeout
    local exit_code=0
    if [[ -n "$env_cmd" ]]; then
        run_with_timeout "${TURN_TIMEOUT:-120}" $env_cmd claude "${cmd_args[@]}" > "$output_file" 2>"$error_file" || exit_code=$?
    else
        run_with_timeout "${TURN_TIMEOUT:-120}" claude "${cmd_args[@]}" > "$output_file" 2>"$error_file" || exit_code=$?
    fi

    # Handle results
    if [[ $exit_code -eq 124 ]]; then
        log_error "Claude timed out after ${TURN_TIMEOUT}s"
        echo "[Claude timed out]" > "$output_file"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Claude failed with exit code $exit_code"
        if [[ -s "$error_file" ]]; then
            log_debug "Error output: $(cat "$error_file")"
        fi
        return 1
    fi

    # Verify output
    if [[ ! -s "$output_file" ]]; then
        log_error "Claude returned empty response"
        return 1
    fi

    # Clean up error file on success
    rm -f "$error_file"

    return 0
}
