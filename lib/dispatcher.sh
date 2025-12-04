#!/usr/bin/env bash
#
# The Council of Legends - Dynamic AI Dispatcher
# Routes AI invocations to appropriate adapters based on provider registry
#

# Source LLM manager if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

#=============================================================================
# Dynamic AI Invocation
#=============================================================================

# Invoke an AI by ID, routing to the appropriate adapter based on provider
# Args: $1 = AI ID, $2 = prompt, $3 = output file, $4 = system prompt (optional)
invoke_ai() {
    local ai="$1"
    local prompt="$2"
    local output_file="$3"
    local system_prompt="${4:-}"

    # Normalize AI name to lowercase
    ai=$(echo "$ai" | tr '[:upper:]' '[:lower:]')

    # Get provider from registry
    local provider
    provider=$(get_llm_field "$ai" "provider" 2>/dev/null)

    if [[ -z "$provider" ]]; then
        # Fallback: try direct adapter match for backward compatibility
        # This allows "claude", "codex", "gemini" to work without registry lookup
        case "$ai" in
            claude)  provider="anthropic" ;;
            codex)   provider="openai" ;;
            gemini)  provider="google" ;;
            groq|arbiter) provider="groq" ;;
            *)
                log_error "Unknown AI '$ai' - not in registry and no fallback"
                return 1
                ;;
        esac
        log_debug "Using fallback provider mapping: $ai -> $provider"
    fi

    log_debug "Dispatching $ai (provider: $provider)"

    # Check if adapter is available before invoking
    if ! check_adapter_available "$provider"; then
        log_error "Adapter not available for provider '$provider'. Ensure the adapter file is sourced."
        log_info "Available providers: $(get_available_providers | tr '\n' ', ' | sed 's/,$//')"
        return 1
    fi

    # Ensure output directory exists
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            log_error "Could not create output directory: $output_dir"
            return 1
        }
    fi

    # Route to appropriate adapter based on provider
    case "$provider" in
        anthropic)
            invoke_claude "$prompt" "$output_file" "$system_prompt"
            ;;
        openai)
            invoke_codex "$prompt" "$output_file" "$system_prompt"
            ;;
        google)
            invoke_gemini "$prompt" "$output_file" "$system_prompt"
            ;;
        groq)
            invoke_groq "$prompt" "$output_file" "$system_prompt"
            ;;
        ollama)
            # Ollama adapter takes AI ID to look up model from registry
            invoke_ollama "$ai" "$prompt" "$output_file" "$system_prompt"
            ;;
        lmstudio)
            # LM Studio adapter takes AI ID for model lookup
            invoke_lmstudio "$ai" "$prompt" "$output_file" "$system_prompt"
            ;;
        openai-compatible|openai_compatible)
            # Generic OpenAI-compatible adapter
            invoke_openai_compatible "$ai" "$prompt" "$output_file" "$system_prompt"
            ;;
        local)
            # Alias for ollama (common case)
            invoke_ollama "$ai" "$prompt" "$output_file" "$system_prompt"
            ;;
        *)
            log_error "Unknown provider '$provider' for AI '$ai'"
            return 1
            ;;
    esac
}

#=============================================================================
# Adapter Availability Checks
#=============================================================================

# Check if an adapter is available for a given provider
# Returns 0 if adapter function exists, 1 otherwise
check_adapter_available() {
    local provider="$1"

    case "$provider" in
        anthropic)
            type invoke_claude &>/dev/null
            ;;
        openai)
            type invoke_codex &>/dev/null
            ;;
        google)
            type invoke_gemini &>/dev/null
            ;;
        groq)
            type invoke_groq &>/dev/null
            ;;
        ollama|local)
            type invoke_ollama &>/dev/null
            ;;
        lmstudio)
            type invoke_lmstudio &>/dev/null
            ;;
        openai-compatible|openai_compatible)
            type invoke_openai_compatible &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Get list of available providers (those with loaded adapters)
get_available_providers() {
    local providers=()

    type invoke_claude &>/dev/null && providers+=("anthropic")
    type invoke_codex &>/dev/null && providers+=("openai")
    type invoke_gemini &>/dev/null && providers+=("google")
    type invoke_groq &>/dev/null && providers+=("groq")
    type invoke_ollama &>/dev/null && providers+=("ollama")
    type invoke_lmstudio &>/dev/null && providers+=("lmstudio")
    type invoke_openai_compatible &>/dev/null && providers+=("openai-compatible")

    printf '%s\n' "${providers[@]}"
}

#=============================================================================
# Batch Operations
#=============================================================================

# Invoke multiple AIs in sequence
# Args: $1 = output directory, $2 = prompt, $3 = system prompt (optional)
# Uses council members from registry
invoke_all_council_members() {
    local output_dir="$1"
    local prompt="$2"
    local system_prompt="${3:-}"

    local members
    mapfile -t members < <(get_council_members)

    local results=()
    for ai in "${members[@]}"; do
        local output_file="$output_dir/${ai}.md"
        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            results+=("$ai:success")
        else
            results+=("$ai:failed")
        fi
    done

    printf '%s\n' "${results[@]}"
}

log_debug "Dispatcher loaded with provider-based routing"
