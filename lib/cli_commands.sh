#!/usr/bin/env bash
#
# The Council of Legends - CLI Commands
# User-facing commands for model management and configuration
#

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/llm_manager.sh"

#=============================================================================
# Models Subcommand Handler
#=============================================================================

handle_models_command() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        list|ls)
            cmd_models_list "$@"
            ;;
        add)
            cmd_models_add "$@"
            ;;
        remove|rm)
            cmd_models_remove "$@"
            ;;
        enable)
            cmd_models_enable "$@"
            ;;
        disable)
            cmd_models_disable "$@"
            ;;
        test)
            cmd_models_test "$@"
            ;;
        info)
            cmd_models_info "$@"
            ;;
        update|set)
            cmd_models_update "$@"
            ;;
        help|--help|-h|*)
            show_models_help
            ;;
    esac
}

#=============================================================================
# Model Commands
#=============================================================================

cmd_models_list() {
    echo ""
    echo -e "${BOLD}${PURPLE}The Council of Many - Model Registry${NC}"
    echo ""

    list_llms

    echo ""
    echo -e "${DIM}Council members participate in debates. Use 'models enable/disable' to change.${NC}"
    echo ""
}

cmd_models_add() {
    if [[ $# -eq 0 ]]; then
        # Interactive mode
        cmd_models_add_interactive
        return
    fi

    # Direct mode: id provider model [options]
    local id="$1"
    local provider="$2"
    local model="$3"
    shift 3 || {
        log_error "Usage: models add <id> <provider> <model> [--name NAME] [--endpoint URL] [--auth-env VAR] [--council]"
        return 1
    }

    # Parse optional arguments
    local name="$id"
    local auth_type="none"
    local auth_env_var=""
    local endpoint=""
    local council_member="false"
    local context_window="4096"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --endpoint)
                endpoint="$2"
                shift 2
                ;;
            --auth-env)
                auth_env_var="$2"
                auth_type="api_key"
                shift 2
                ;;
            --council)
                council_member="true"
                shift
                ;;
            --context)
                context_window="$2"
                shift 2
                ;;
            *)
                log_warn "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Validate provider
    case "$provider" in
        anthropic|openai|google|groq|ollama|lmstudio|openai-compatible)
            ;;
        *)
            log_error "Unknown provider: $provider"
            echo "Valid providers: anthropic, openai, google, groq, ollama, lmstudio, openai-compatible"
            return 1
            ;;
    esac

    # Add to registry
    add_llm "$id" "$name" "$provider" "$model" "$auth_type" "$auth_env_var" "$council_member"

    # Add endpoint if specified
    if [[ -n "$endpoint" ]]; then
        update_llm_field "$id" "endpoint" "$endpoint"
    fi

    # Add context window
    update_llm_field "$id" "context_window" "$context_window"

    echo ""
    echo -e "${GREEN}Model added successfully!${NC}"
    echo ""
    echo "To enable as council member: ./council.sh models enable $id"
    echo "To test the model: ./council.sh models test $id"
}

cmd_models_add_interactive() {
    echo ""
    echo -e "${BOLD}Add New Model - Interactive Setup${NC}"
    echo ""

    # Get ID
    read -rp "Model ID (lowercase, no spaces): " id
    if [[ -z "$id" ]]; then
        log_error "Model ID is required"
        return 1
    fi
    id=$(echo "$id" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    # Check if exists
    if get_llm_field "$id" "name" >/dev/null 2>&1; then
        log_error "Model '$id' already exists"
        return 1
    fi

    # Get display name
    read -rp "Display name [$id]: " name
    name="${name:-$id}"

    # Get provider
    echo ""
    echo "Available providers:"
    echo "  1. ollama          - Local Ollama installation"
    echo "  2. lmstudio        - LM Studio local server"
    echo "  3. openai-compatible - Any OpenAI-compatible API"
    echo "  4. anthropic       - Anthropic Claude API"
    echo "  5. openai          - OpenAI API"
    echo "  6. google          - Google Gemini API"
    echo "  7. groq            - Groq API"
    echo ""
    read -rp "Provider (1-7 or name): " provider_input

    local provider
    case "$provider_input" in
        1|ollama) provider="ollama" ;;
        2|lmstudio) provider="lmstudio" ;;
        3|openai-compatible) provider="openai-compatible" ;;
        4|anthropic) provider="anthropic" ;;
        5|openai) provider="openai" ;;
        6|google) provider="google" ;;
        7|groq) provider="groq" ;;
        *) provider="$provider_input" ;;
    esac

    # Get model name
    echo ""
    if [[ "$provider" == "ollama" ]]; then
        echo "Available Ollama models (if Ollama is running):"
        ollama_list_models 2>/dev/null | head -10 || echo "  (Could not list models)"
    fi
    read -rp "Model name/ID: " model

    # Get endpoint for local providers
    local endpoint=""
    case "$provider" in
        ollama)
            read -rp "Ollama endpoint [http://localhost:11434]: " endpoint
            endpoint="${endpoint:-http://localhost:11434}"
            ;;
        lmstudio)
            read -rp "LM Studio endpoint [http://localhost:1234]: " endpoint
            endpoint="${endpoint:-http://localhost:1234}"
            ;;
        openai-compatible)
            read -rp "API endpoint (required): " endpoint
            if [[ -z "$endpoint" ]]; then
                log_error "Endpoint is required for openai-compatible provider"
                return 1
            fi
            ;;
    esac

    # Get auth info
    local auth_type="none"
    local auth_env_var=""
    case "$provider" in
        anthropic|openai|google|groq|openai-compatible)
            echo ""
            read -rp "API key environment variable (or leave empty for none): " auth_env_var
            if [[ -n "$auth_env_var" ]]; then
                auth_type="api_key"
            fi
            ;;
    esac

    # Context window
    echo ""
    local context_window=""
    case "$provider" in
        ollama|lmstudio)
            read -rp "Context window size [8192]: " context_window
            context_window="${context_window:-8192}"
            ;;
        *)
            read -rp "Context window size [4096]: " context_window
            context_window="${context_window:-4096}"
            ;;
    esac

    # Council membership
    echo ""
    read -rp "Add as council member? (y/N): " council_input
    local council_member="false"
    if [[ "$council_input" =~ ^[Yy] ]]; then
        council_member="true"
    fi

    # Add the model
    echo ""
    add_llm "$id" "$name" "$provider" "$model" "$auth_type" "$auth_env_var" "$council_member" "$endpoint" "$context_window"

    echo ""
    echo -e "${GREEN}Model '$id' added successfully!${NC}"
}

cmd_models_remove() {
    local id="$1"

    if [[ -z "$id" ]]; then
        log_error "Usage: models remove <id>"
        return 1
    fi

    # Confirm removal
    echo ""
    read -rp "Remove model '$id'? This cannot be undone. (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Cancelled."
        return 0
    fi

    remove_llm "$id"
}

cmd_models_enable() {
    local id="$1"

    if [[ -z "$id" ]]; then
        log_error "Usage: models enable <id>"
        return 1
    fi

    set_council_member "$id" "true"

    echo ""
    echo "Council now has $(get_council_member_count) members:"
    get_council_members | while read -r member; do
        local name
        name=$(get_llm_field "$member" "name" 2>/dev/null) || name="$member"
        echo "  - $name ($member)"
    done
}

cmd_models_disable() {
    local id="$1"

    if [[ -z "$id" ]]; then
        log_error "Usage: models disable <id>"
        return 1
    fi

    # Check if this would leave too few members
    local current_count
    current_count=$(get_council_member_count)
    if [[ "$current_count" -le 2 ]]; then
        log_warn "Council requires at least 2 members"
        read -rp "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Cancelled."
            return 0
        fi
    fi

    set_council_member "$id" "false"

    echo ""
    echo "Council now has $(get_council_member_count) members"
}

cmd_models_test() {
    local id="$1"

    if [[ -z "$id" ]]; then
        # Test all models
        echo ""
        echo -e "${BOLD}Testing all registered models...${NC}"
        echo ""

        local all_ids
        mapfile -t all_ids < <(get_all_llm_ids)

        for model_id in "${all_ids[@]}"; do
            test_single_model "$model_id"
        done
    else
        test_single_model "$id"
    fi
}

test_single_model() {
    local id="$1"
    local verbose="${2:-false}"
    local provider name auth_env_var auth_type endpoint

    provider=$(get_llm_field "$id" "provider" 2>/dev/null)
    name=$(get_llm_field "$id" "name" 2>/dev/null) || name="$id"
    auth_env_var=$(get_llm_field "$id" "auth_env_var" 2>/dev/null) || auth_env_var=""
    auth_type=$(get_llm_field "$id" "auth_type" 2>/dev/null) || auth_type="none"
    endpoint=$(get_llm_field "$id" "endpoint" 2>/dev/null) || endpoint=""

    echo -n "Testing $name ($id)... "

    if [[ -z "$provider" ]]; then
        echo -e "${RED}NOT FOUND${NC}"
        [[ "$verbose" == "true" ]] && echo "  └─ Model '$id' is not registered in the registry"
        return 1
    fi

    local errors=()

    # Check if adapter is available
    if ! check_adapter_available "$provider" 2>/dev/null; then
        errors+=("Adapter for provider '$provider' is not loaded")
    fi

    # Check auth if required
    if [[ "$auth_type" == "api_key" && -n "$auth_env_var" ]]; then
        if [[ -z "${!auth_env_var:-}" ]]; then
            errors+=("Missing API key: $auth_env_var is not set")
        fi
    fi

    # Check endpoint reachability for local providers
    case "$provider" in
        ollama)
            local ollama_endpoint="${endpoint:-http://localhost:11434}"
            if ! curl -s --connect-timeout 2 "$ollama_endpoint/api/version" >/dev/null 2>&1; then
                errors+=("Cannot reach Ollama at $ollama_endpoint")
            fi
            ;;
        lmstudio)
            local lm_endpoint="${endpoint:-http://localhost:1234}"
            if ! curl -s --connect-timeout 2 "$lm_endpoint/v1/models" >/dev/null 2>&1; then
                errors+=("Cannot reach LM Studio at $lm_endpoint")
            fi
            ;;
        openai-compatible|openai_compatible)
            if [[ -n "$endpoint" ]]; then
                if ! curl -s --connect-timeout 2 "$endpoint/v1/models" >/dev/null 2>&1; then
                    errors+=("Cannot reach endpoint at $endpoint")
                fi
            fi
            ;;
    esac

    # Report results
    if [[ ${#errors[@]} -eq 0 ]]; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        if [[ "$verbose" == "true" ]] || [[ ${#errors[@]} -gt 0 ]]; then
            for err in "${errors[@]}"; do
                echo -e "  └─ ${YELLOW}$err${NC}"
            done
        fi
        return 1
    fi
}

cmd_models_info() {
    local id="$1"

    if [[ -z "$id" ]]; then
        log_error "Usage: models info <id>"
        return 1
    fi

    local name provider model auth_type endpoint council_member context_window

    name=$(get_llm_field "$id" "name" 2>/dev/null) || name="Unknown"
    provider=$(get_llm_field "$id" "provider" 2>/dev/null) || provider="Unknown"
    model=$(get_llm_field "$id" "model" 2>/dev/null) || model="Unknown"
    auth_type=$(get_llm_field "$id" "auth_type" 2>/dev/null) || auth_type="none"
    endpoint=$(get_llm_field "$id" "endpoint" 2>/dev/null) || endpoint="(default)"
    council_member=$(get_llm_field "$id" "council_member" 2>/dev/null) || council_member="false"
    context_window=$(get_llm_field "$id" "context_window" 2>/dev/null) || context_window="Unknown"

    echo ""
    echo -e "${BOLD}Model: $name${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ID:             $id"
    echo "  Provider:       $provider"
    echo "  Model:          $model"
    echo "  Auth Type:      $auth_type"
    echo "  Endpoint:       $endpoint"
    echo "  Context Window: $context_window"
    echo "  Council Member: $council_member"
    echo ""
}

cmd_models_update() {
    local id="$1"
    shift || {
        log_error "Usage: models update <id> [--field value ...]"
        log_info "Fields: --name, --model, --endpoint, --auth-env, --context"
        return 1
    }

    # Check if model exists
    if ! llm_exists "$id"; then
        log_error "Model '$id' not found in registry"
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        # Interactive update mode
        cmd_models_update_interactive "$id"
        return
    fi

    # Parse field updates
    local updated=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                update_llm_field "$id" "name" "$2" && ((updated++))
                shift 2
                ;;
            --model)
                update_llm_field "$id" "model" "$2" && ((updated++))
                shift 2
                ;;
            --endpoint)
                update_llm_field "$id" "endpoint" "$2" && ((updated++))
                shift 2
                ;;
            --auth-env)
                update_llm_field "$id" "auth_env_var" "$2" && ((updated++))
                update_llm_field "$id" "auth_type" "api_key"
                shift 2
                ;;
            --context)
                update_llm_field "$id" "context_window" "$2" && ((updated++))
                shift 2
                ;;
            *)
                log_warn "Unknown option: $1"
                shift
                ;;
        esac
    done

    if [[ "$updated" -gt 0 ]]; then
        echo ""
        echo -e "${GREEN}Updated $updated field(s) for model '$id'${NC}"
    else
        log_warn "No fields were updated"
    fi
}

cmd_models_update_interactive() {
    local id="$1"

    echo ""
    echo -e "${BOLD}Update Model: $id${NC}"
    echo "(Press Enter to keep current value)"
    echo ""

    # Get current values
    local current_name current_model current_endpoint current_context
    current_name=$(get_llm_field "$id" "name" 2>/dev/null) || current_name="$id"
    current_model=$(get_llm_field "$id" "model" 2>/dev/null) || current_model=""
    current_endpoint=$(get_llm_field "$id" "endpoint" 2>/dev/null) || current_endpoint=""
    current_context=$(get_llm_field "$id" "context_window" 2>/dev/null) || current_context=""

    # Prompt for updates
    read -rp "Display name [$current_name]: " new_name
    read -rp "Model [$current_model]: " new_model
    read -rp "Endpoint [$current_endpoint]: " new_endpoint
    read -rp "Context window [$current_context]: " new_context

    # Apply updates
    local updated=0
    if [[ -n "$new_name" && "$new_name" != "$current_name" ]]; then
        update_llm_field "$id" "name" "$new_name" && ((updated++))
    fi
    if [[ -n "$new_model" && "$new_model" != "$current_model" ]]; then
        update_llm_field "$id" "model" "$new_model" && ((updated++))
    fi
    if [[ -n "$new_endpoint" && "$new_endpoint" != "$current_endpoint" ]]; then
        update_llm_field "$id" "endpoint" "$new_endpoint" && ((updated++))
    fi
    if [[ -n "$new_context" && "$new_context" != "$current_context" ]]; then
        update_llm_field "$id" "context_window" "$new_context" && ((updated++))
    fi

    echo ""
    if [[ "$updated" -gt 0 ]]; then
        echo -e "${GREEN}Updated $updated field(s)${NC}"
    else
        echo "No changes made"
    fi
}

show_models_help() {
    echo ""
    echo -e "${BOLD}${PURPLE}The Council of Many - Model Management${NC}"
    echo ""
    echo -e "${BOLD}USAGE${NC}"
    echo "    ./council.sh models <command> [options]"
    echo ""
    echo -e "${BOLD}COMMANDS${NC}"
    echo "    list              List all registered models"
    echo "    add               Add a new model (interactive)"
    echo "    add <id> <provider> <model> [options]"
    echo "                      Add a new model directly"
    echo "    update <id>       Update model configuration (interactive)"
    echo "    update <id> [--field value ...]"
    echo "                      Update specific model fields"
    echo "    remove <id>       Remove a model from registry"
    echo "    enable <id>       Enable model as council member"
    echo "    disable <id>      Disable model as council member"
    echo "    test [id]         Test model availability"
    echo "    info <id>         Show model details"
    echo ""
    echo -e "${BOLD}PROVIDERS${NC}"
    echo "    ollama            Local Ollama installation"
    echo "    lmstudio          LM Studio local server"
    echo "    openai-compatible Any OpenAI-compatible API"
    echo "    anthropic         Anthropic Claude API"
    echo "    openai            OpenAI API"
    echo "    google            Google Gemini API"
    echo "    groq              Groq API"
    echo ""
    echo -e "${BOLD}EXAMPLES${NC}"
    echo "    # Add Ollama model"
    echo "    ./council.sh models add llama3 ollama llama3 --council"
    echo ""
    echo "    # Add OpenAI-compatible endpoint"
    echo "    ./council.sh models add vllm openai-compatible mistral-7b \\"
    echo "        --endpoint http://localhost:8000 --council"
    echo ""
    echo "    # Enable existing model as council member"
    echo "    ./council.sh models enable groq"
    echo ""
}

log_debug "CLI commands module loaded"
