#!/usr/bin/env bash
#
# The Council of Legends - LLM Management
# Add, remove, and configure LLM configurations
# Supports both API-key and local/token-based authentication
#

COUNCIL_ROOT="${COUNCIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$COUNCIL_ROOT/lib/utils.sh"

#=============================================================================
# LLM Registry
#=============================================================================

LLM_REGISTRY_FILE="${COUNCIL_ROOT}/config/llms.toon"

# Initialize LLM registry if it doesn't exist
init_llm_registry() {
    if [[ ! -f "$LLM_REGISTRY_FILE" ]]; then
        cat > "$LLM_REGISTRY_FILE" <<'EOF'
; The Council of Legends - LLM Registry
; Configure available language models and their settings
;
; Each LLM entry defines:
;   - id: Unique identifier (used in code)
;   - name: Display name
;   - provider: API provider (anthropic, openai, google, groq, local)
;   - model: Model identifier
;   - auth_type: api_key | token | none (for local models)
;   - endpoint: API endpoint (optional, for custom endpoints)
;   - rate_limit: Max requests per minute (optional)
;   - context_window: Max context tokens (optional)

; Default Council Members
llm[claude]:
  name: "Claude"
  provider: anthropic
  model: "${CLAUDE_MODEL:-sonnet}"
  auth_type: api_key
  auth_env_var: ANTHROPIC_API_KEY
  context_window: 200000
  council_member: true

llm[codex]:
  name: "Codex"
  provider: openai
  model: "${CODEX_MODEL:-o3}"
  auth_type: api_key
  auth_env_var: OPENAI_API_KEY
  context_window: 128000
  council_member: true

llm[gemini]:
  name: "Gemini"
  provider: google
  model: "${GEMINI_MODEL:-gemini-2.5-flash}"
  auth_type: api_key
  auth_env_var: GOOGLE_API_KEY
  context_window: 1000000
  council_member: true

; 4th AI Arbiter
llm[groq]:
  name: "Arbiter"
  provider: groq
  model: "${GROQ_MODEL:-llama-3.3-70b-versatile}"
  auth_type: api_key
  auth_env_var: GROQ_API_KEY
  context_window: 131072
  council_member: false
  role: arbiter
EOF
        log_info "Created LLM registry: $LLM_REGISTRY_FILE"
    fi
}

#=============================================================================
# Registry Operations
#=============================================================================

# List all registered LLMs
list_llms() {
    init_llm_registry

    echo ""
    echo -e "${BOLD}Registered LLMs:${NC}"
    echo ""

    # Parse TOON file for LLM entries
    local in_llm=false
    local current_id=""
    local current_name=""
    local current_provider=""
    local current_model=""
    local current_council=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Match llm[id]: pattern
        if [[ "$line" =~ ^llm\[([^\]]+)\]: ]]; then
            # Print previous entry if exists
            if [[ -n "$current_id" ]]; then
                local status="[available]"
                if [[ "$current_council" == "true" ]]; then
                    status="${GREEN}[council]${NC}"
                fi
                printf "  %-12s %-15s %-10s %-25s %s\n" "$current_id" "$current_name" "$current_provider" "$current_model" "$status"
            fi

            current_id="${BASH_REMATCH[1]}"
            current_name=""
            current_provider=""
            current_model=""
            current_council=""
            in_llm=true
        elif [[ "$in_llm" == "true" ]]; then
            # Parse nested fields
            if [[ "$line" =~ ^[[:space:]]+name:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+provider:[[:space:]]*(.+) ]]; then
                current_provider="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+model:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_model="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+council_member:[[:space:]]*(true|false) ]]; then
                current_council="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*\; ]]; then
                in_llm=false
            fi
        fi
    done < "$LLM_REGISTRY_FILE"

    # Print last entry
    if [[ -n "$current_id" ]]; then
        local status="[available]"
        if [[ "$current_council" == "true" ]]; then
            status="${GREEN}[council]${NC}"
        fi
        printf "  %-12s %-15s %-10s %-25s %s\n" "$current_id" "$current_name" "$current_provider" "$current_model" "$status"
    fi

    echo ""
}

# Check if an LLM is configured and available
check_llm_availability() {
    local llm_id="$1"
    init_llm_registry

    # Check if LLM exists in registry
    if ! grep -q "llm\[$llm_id\]:" "$LLM_REGISTRY_FILE"; then
        log_error "LLM '$llm_id' not found in registry"
        return 1
    fi

    # Extract auth_env_var for this LLM
    local auth_var=""
    local in_block=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^llm\[$llm_id\]: ]]; then
            in_block=true
        elif [[ "$in_block" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]+auth_env_var:[[:space:]]*(.+) ]]; then
                auth_var="${BASH_REMATCH[1]}"
                break
            elif [[ "$line" =~ ^[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*\; ]]; then
                break
            fi
        fi
    done < "$LLM_REGISTRY_FILE"

    # Check if auth env var is set
    if [[ -n "$auth_var" ]]; then
        if [[ -z "${!auth_var:-}" ]]; then
            log_warn "LLM '$llm_id' requires $auth_var to be set"
            return 1
        fi
    fi

    # Check if CLI tool exists
    if command -v "$llm_id" &>/dev/null; then
        log_success "LLM '$llm_id' is available"
        return 0
    else
        log_warn "LLM '$llm_id' CLI tool not found"
        return 1
    fi
}

# Add a new LLM to the registry
# Args: id, name, provider, model, auth_type, auth_env_var
add_llm() {
    local id="$1"
    local name="$2"
    local provider="$3"
    local model="$4"
    local auth_type="${5:-api_key}"
    local auth_env_var="${6:-}"
    local council_member="${7:-false}"

    init_llm_registry

    # Check if LLM already exists
    if grep -q "llm\[$id\]:" "$LLM_REGISTRY_FILE"; then
        log_error "LLM '$id' already exists. Use update_llm to modify."
        return 1
    fi

    # Append new LLM entry
    cat >> "$LLM_REGISTRY_FILE" <<EOF

; Added $(date -u +"%Y-%m-%dT%H:%M:%SZ")
llm[$id]:
  name: "$name"
  provider: $provider
  model: "$model"
  auth_type: $auth_type
  auth_env_var: $auth_env_var
  council_member: $council_member
EOF

    log_success "Added LLM: $id ($name)"
}

# Remove an LLM from the registry
remove_llm() {
    local id="$1"
    init_llm_registry

    if ! grep -q "llm\[$id\]:" "$LLM_REGISTRY_FILE"; then
        log_error "LLM '$id' not found in registry"
        return 1
    fi

    # Create temp file without this LLM entry
    local temp_file="${LLM_REGISTRY_FILE}.tmp"
    local skip_until_next=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^llm\[$id\]: ]]; then
            skip_until_next=true
            continue
        fi

        if [[ "$skip_until_next" == "true" ]]; then
            # Check if we hit a new entry or non-indented line
            if [[ "$line" =~ ^[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*\; ]] && [[ ! "$line" =~ ^$ ]]; then
                skip_until_next=false
            else
                continue
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$LLM_REGISTRY_FILE"

    mv "$temp_file" "$LLM_REGISTRY_FILE"
    log_success "Removed LLM: $id"
}

# Get LLM field value
get_llm_field() {
    local id="$1"
    local field="$2"
    init_llm_registry

    local in_block=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^llm\[$id\]: ]]; then
            in_block=true
        elif [[ "$in_block" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]+${field}:[[:space:]]*\"?([^\"]+)\"? ]]; then
                echo "${BASH_REMATCH[1]}"
                return 0
            elif [[ "$line" =~ ^[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*\; ]]; then
                break
            fi
        fi
    done < "$LLM_REGISTRY_FILE"

    return 1
}

# Get all council member IDs
get_council_members() {
    init_llm_registry

    local members=()
    local current_id=""
    local in_block=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^llm\[([^\]]+)\]: ]]; then
            current_id="${BASH_REMATCH[1]}"
            in_block=true
        elif [[ "$in_block" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]+council_member:[[:space:]]*true ]]; then
                members+=("$current_id")
            elif [[ "$line" =~ ^[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*\; ]]; then
                in_block=false
            fi
        fi
    done < "$LLM_REGISTRY_FILE"

    printf '%s\n' "${members[@]}"
}

#=============================================================================
# CLI Interface
#=============================================================================

llm_manager_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        init)
            init_llm_registry
            echo "LLM registry initialized"
            ;;
        list)
            list_llms
            ;;
        check)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: llm_manager check <llm_id>"
                return 1
            fi
            check_llm_availability "$1"
            ;;
        add)
            if [[ $# -lt 4 ]]; then
                log_error "Usage: llm_manager add <id> <name> <provider> <model> [auth_type] [auth_env_var] [council_member]"
                return 1
            fi
            add_llm "$@"
            ;;
        remove)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: llm_manager remove <llm_id>"
                return 1
            fi
            remove_llm "$1"
            ;;
        get)
            if [[ $# -lt 2 ]]; then
                log_error "Usage: llm_manager get <llm_id> <field>"
                return 1
            fi
            get_llm_field "$1" "$2"
            ;;
        members)
            echo "Council Members:"
            get_council_members
            ;;
        help|*)
            echo "LLM Manager - Manage language model configurations"
            echo ""
            echo "Usage: source lib/llm_manager.sh && llm_manager_cli <command>"
            echo ""
            echo "Commands:"
            echo "  init          Initialize LLM registry"
            echo "  list          List all registered LLMs"
            echo "  check <id>    Check if LLM is available"
            echo "  add <...>     Add new LLM to registry"
            echo "  remove <id>   Remove LLM from registry"
            echo "  get <id> <f>  Get field value for LLM"
            echo "  members       List council member LLMs"
            ;;
    esac
}
