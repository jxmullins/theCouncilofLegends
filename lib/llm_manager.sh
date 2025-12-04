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
# Input Validation & Security
#=============================================================================

# Valid characters for LLM IDs (alphanumeric, dash, underscore)
readonly LLM_ID_PATTERN='^[a-zA-Z][a-zA-Z0-9_-]*$'

# Valid providers
readonly VALID_PROVIDERS="anthropic openai google groq ollama lmstudio openai-compatible local"

# Validate LLM ID format (prevent injection attacks)
validate_llm_id() {
    local id="$1"
    if [[ -z "$id" ]]; then
        log_error "LLM ID cannot be empty"
        return 1
    fi
    if [[ ${#id} -gt 64 ]]; then
        log_error "LLM ID too long (max 64 characters)"
        return 1
    fi
    if [[ ! "$id" =~ $LLM_ID_PATTERN ]]; then
        log_error "Invalid LLM ID '$id'. Use only letters, numbers, dashes, underscores. Must start with a letter."
        return 1
    fi
    return 0
}

# Validate provider
validate_provider() {
    local provider="$1"
    if [[ -z "$provider" ]]; then
        log_error "Provider cannot be empty"
        return 1
    fi
    if [[ ! " $VALID_PROVIDERS " =~ " $provider " ]]; then
        log_error "Invalid provider '$provider'. Valid: $VALID_PROVIDERS"
        return 1
    fi
    return 0
}

# Sanitize value for registry (escape/reject dangerous characters)
sanitize_registry_value() {
    local value="$1"
    # Reject values with newlines (could inject new fields)
    if [[ "$value" == *$'\n'* ]] || [[ "$value" == *$'\r'* ]]; then
        log_error "Value cannot contain newlines"
        return 1
    fi
    # Reject values starting with special TOON characters
    if [[ "$value" =~ ^[[:space:]] ]]; then
        log_error "Value cannot start with whitespace"
        return 1
    fi
    echo "$value"
    return 0
}

# Validate endpoint URL (SSRF protection)
validate_endpoint() {
    local endpoint="$1"
    local allow_remote="${2:-false}"

    if [[ -z "$endpoint" ]]; then
        return 0  # Empty is OK (will use defaults)
    fi

    # Extract host from URL
    local host
    host=$(echo "$endpoint" | sed -E 's|^https?://([^/:]+).*|\1|')

    # Check if localhost or local network
    case "$host" in
        localhost|127.0.0.1|0.0.0.0|::1)
            return 0
            ;;
        192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
            # Local network - warn but allow
            log_warn "Endpoint uses local network address: $host"
            return 0
            ;;
        *)
            if [[ "$allow_remote" != "true" ]]; then
                log_warn "Remote endpoint detected: $host"
                log_info "Use --allow-remote to permit external endpoints"
                # Allow but warn - user can decide
            fi
            return 0
            ;;
    esac
}

# Check if LLM exists in registry (using fixed string matching)
llm_exists() {
    local id="$1"
    init_llm_registry
    # Use grep -F for fixed string matching (no regex interpretation)
    grep -qF "llm[$id]:" "$LLM_REGISTRY_FILE" 2>/dev/null
}

# Lock file for registry operations
REGISTRY_LOCK_FILE="${COUNCIL_ROOT}/config/.llms.lock"

# Execute a function with file locking
with_registry_lock() {
    local cmd="$1"
    shift

    # Ensure lock directory exists
    mkdir -p "$(dirname "$REGISTRY_LOCK_FILE")"

    # Use flock for exclusive access
    (
        flock -x 200 || {
            log_error "Could not acquire registry lock"
            return 1
        }
        "$cmd" "$@"
    ) 200>"$REGISTRY_LOCK_FILE"
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

    # Validate ID format first
    if ! validate_llm_id "$llm_id"; then
        return 1
    fi

    # Check if LLM exists in registry (using fixed string matching)
    if ! llm_exists "$llm_id"; then
        log_error "LLM '$llm_id' not found in registry"
        return 1
    fi

    # Extract auth_env_var for this LLM using get_llm_field (safe, uses fixed string matching)
    local auth_var
    auth_var=$(get_llm_field "$llm_id" "auth_env_var" 2>/dev/null) || auth_var=""

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

# Add a new LLM to the registry (internal implementation)
# Args: id, name, provider, model, auth_type, auth_env_var, council_member, endpoint, context_window
_add_llm_impl() {
    local id="$1"
    local name="$2"
    local provider="$3"
    local model="$4"
    local auth_type="${5:-api_key}"
    local auth_env_var="${6:-}"
    local council_member="${7:-false}"
    local endpoint="${8:-}"
    local context_window="${9:-}"

    init_llm_registry

    # Check if LLM already exists (using fixed string matching)
    if llm_exists "$id"; then
        log_error "LLM '$id' already exists. Use 'models update' or update_llm_field to modify."
        return 1
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$LLM_REGISTRY_FILE")"

    # Append new LLM entry
    {
        echo ""
        echo "; Added $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "llm[$id]:"
        echo "  name: \"$name\""
        echo "  provider: $provider"
        echo "  model: \"$model\""
        echo "  auth_type: $auth_type"
        if [[ -n "$auth_env_var" ]]; then
            echo "  auth_env_var: $auth_env_var"
        fi
        if [[ -n "$endpoint" ]]; then
            echo "  endpoint: \"$endpoint\""
        fi
        if [[ -n "$context_window" ]]; then
            echo "  context_window: $context_window"
        fi
        echo "  council_member: $council_member"
    } >> "$LLM_REGISTRY_FILE"

    log_success "Added LLM: $id ($name)"
}

# Add a new LLM to the registry (with validation and locking)
# Args: id, name, provider, model, auth_type, auth_env_var, council_member, endpoint, context_window
add_llm() {
    local id="$1"
    local name="$2"
    local provider="$3"
    local model="$4"
    local auth_type="${5:-api_key}"
    local auth_env_var="${6:-}"
    local council_member="${7:-false}"
    local endpoint="${8:-}"
    local context_window="${9:-}"

    # Validate required parameters
    if [[ -z "$id" ]] || [[ -z "$name" ]] || [[ -z "$provider" ]] || [[ -z "$model" ]]; then
        log_error "Missing required parameters: id, name, provider, model"
        return 1
    fi

    # Validate ID format (prevents injection)
    if ! validate_llm_id "$id"; then
        return 1
    fi

    # Validate provider
    if ! validate_provider "$provider"; then
        return 1
    fi

    # Sanitize user-provided values
    if ! name=$(sanitize_registry_value "$name"); then
        return 1
    fi
    if ! model=$(sanitize_registry_value "$model"); then
        return 1
    fi

    # Validate auth_type
    if [[ "$auth_type" != "api_key" && "$auth_type" != "token" && "$auth_type" != "none" ]]; then
        log_error "Invalid auth_type '$auth_type'. Use: api_key, token, or none"
        return 1
    fi

    # Validate council_member
    if [[ "$council_member" != "true" && "$council_member" != "false" ]]; then
        log_error "Invalid council_member '$council_member'. Use: true or false"
        return 1
    fi

    # Validate endpoint if provided
    if [[ -n "$endpoint" ]]; then
        if ! validate_endpoint "$endpoint"; then
            return 1
        fi
    fi

    # Validate context_window if provided (must be positive integer)
    if [[ -n "$context_window" ]]; then
        if ! [[ "$context_window" =~ ^[0-9]+$ ]] || [[ "$context_window" -le 0 ]]; then
            log_error "Invalid context_window '$context_window'. Must be a positive integer."
            return 1
        fi
    fi

    # Execute with file locking
    with_registry_lock _add_llm_impl "$id" "$name" "$provider" "$model" "$auth_type" "$auth_env_var" "$council_member" "$endpoint" "$context_window"
}

# Remove an LLM from the registry (internal implementation)
_remove_llm_impl() {
    local id="$1"
    init_llm_registry

    # Use fixed string matching for existence check
    if ! llm_exists "$id"; then
        log_error "LLM '$id' not found in registry"
        return 1
    fi

    # Create temp file without this LLM entry
    local temp_file="${LLM_REGISTRY_FILE}.tmp"
    local skip_until_next=false
    local target_header="llm[$id]:"

    # Clean up any existing temp file
    rm -f "$temp_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Use exact string comparison instead of regex
        if [[ "$line" == "$target_header" ]]; then
            skip_until_next=true
            continue
        fi

        if [[ "$skip_until_next" == "true" ]]; then
            # Check if we hit a new section (non-indented, non-comment, non-empty line)
            if [[ -n "$line" ]] && [[ "${line:0:1}" != " " ]] && [[ "${line:0:1}" != $'\t' ]] && [[ "${line:0:1}" != ";" ]]; then
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

# Remove an LLM from the registry (with validation and locking)
remove_llm() {
    local id="$1"

    # Validate ID
    if [[ -z "$id" ]]; then
        log_error "LLM ID required"
        return 1
    fi

    # Validate ID format (prevents injection)
    if ! validate_llm_id "$id"; then
        return 1
    fi

    # Execute with file locking
    with_registry_lock _remove_llm_impl "$id"
}

# Get LLM field value
get_llm_field() {
    local id="$1"
    local field="$2"
    init_llm_registry

    local in_block=false
    local target_header="llm[$id]:"

    while IFS= read -r line; do
        # Use exact string comparison instead of regex
        if [[ "$line" == "$target_header" ]]; then
            in_block=true
        elif [[ "$in_block" == "true" ]]; then
            # Check if line starts with the field (using string prefix match)
            local trimmed="${line#"${line%%[![:space:]]*}"}"  # Trim leading whitespace
            if [[ "$trimmed" == "${field}:"* ]]; then
                # Extract value after "field: "
                local value="${trimmed#"${field}:"}"
                value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
                # Remove surrounding quotes if present
                value="${value#\"}"
                value="${value%\"}"
                echo "$value"
                return 0
            elif [[ -n "$line" ]] && [[ "${line:0:1}" != " " ]] && [[ "${line:0:1}" != $'\t' ]] && [[ "${line:0:1}" != ";" ]]; then
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

# Get all LLM IDs (including non-council members)
get_all_llm_ids() {
    init_llm_registry

    # Use grep -o with basic regex (more portable than -P)
    # Match lines starting with "llm[" and extract the ID
    grep '^llm\[' "$LLM_REGISTRY_FILE" 2>/dev/null | sed 's/^llm\[\([^]]*\)\]:$/\1/' || true
}

# Get council members as bash array (for use with mapfile)
# Usage: mapfile -t members < <(get_council_members)
# This function is an alias for get_council_members for clarity
get_council_members_array() {
    get_council_members
}

# Enable or disable council membership for an LLM
# Args: id, enabled (true/false)
# Note: This is now a thin wrapper around update_llm_field for backwards compatibility
set_council_member() {
    local id="$1"
    local enabled="$2"

    # Validate enabled value
    if [[ "$enabled" != "true" && "$enabled" != "false" ]]; then
        log_error "Invalid value '$enabled'. Use 'true' or 'false'"
        return 1
    fi

    # Check if LLM exists first (for better error message)
    if ! llm_exists "$id"; then
        log_error "LLM '$id' not found in registry"
        return 1
    fi

    # Use update_llm_field (which handles validation and locking)
    # Suppress its success message and provide our own
    if _update_llm_field_impl "$id" "council_member" "$enabled" 2>/dev/null; then
        if [[ "$enabled" == "true" ]]; then
            log_success "Enabled council membership for: $id"
        else
            log_success "Disabled council membership for: $id"
        fi
        return 0
    else
        log_error "Failed to update council membership for: $id"
        return 1
    fi
}

# Update a field for an existing LLM (internal implementation)
# Args: id, field, value
_update_llm_field_impl() {
    local id="$1"
    local field="$2"
    local value="$3"

    init_llm_registry

    # Use fixed string matching to check existence
    if ! grep -qF "llm[$id]:" "$LLM_REGISTRY_FILE"; then
        log_error "LLM '$id' not found in registry"
        return 1
    fi

    local temp_file="${LLM_REGISTRY_FILE}.tmp"
    local in_block=false
    local found_field=false
    local target_header="llm[$id]:"

    # Clean up any existing temp file
    rm -f "$temp_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Use exact string comparison instead of regex
        if [[ "$line" == "$target_header" ]]; then
            in_block=true
            echo "$line" >> "$temp_file"
        elif [[ "$in_block" == "true" ]]; then
            # Check if line starts with the field (using string prefix match)
            local trimmed="${line#"${line%%[![:space:]]*}"}"  # Trim leading whitespace
            if [[ "$trimmed" == "${field}:"* ]]; then
                # Write the new value, properly escaped
                if [[ "$value" =~ [[:space:]] ]] || [[ "$value" == *\"* ]] || [[ "$value" == *\'* ]]; then
                    # Escape any existing quotes in value
                    local escaped_value="${value//\"/\\\"}"
                    echo "  ${field}: \"$escaped_value\"" >> "$temp_file"
                else
                    echo "  ${field}: $value" >> "$temp_file"
                fi
                found_field=true
            elif [[ -n "$line" ]] && [[ "${line:0:1}" != " " ]] && [[ "${line:0:1}" != $'\t' ]] && [[ "${line:0:1}" != ";" ]]; then
                # End of block (new section starts) - add field if not found
                if [[ "$found_field" == "false" ]]; then
                    if [[ "$value" =~ [[:space:]] ]] || [[ "$value" == *\"* ]] || [[ "$value" == *\'* ]]; then
                        local escaped_value="${value//\"/\\\"}"
                        echo "  ${field}: \"$escaped_value\"" >> "$temp_file"
                    else
                        echo "  ${field}: $value" >> "$temp_file"
                    fi
                fi
                in_block=false
                found_field=false
                echo "$line" >> "$temp_file"
            else
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$LLM_REGISTRY_FILE"

    # Handle last entry case
    if [[ "$in_block" == "true" && "$found_field" == "false" ]]; then
        if [[ "$value" =~ [[:space:]] ]] || [[ "$value" == *\"* ]] || [[ "$value" == *\'* ]]; then
            local escaped_value="${value//\"/\\\"}"
            echo "  ${field}: \"$escaped_value\"" >> "$temp_file"
        else
            echo "  ${field}: $value" >> "$temp_file"
        fi
    fi

    mv "$temp_file" "$LLM_REGISTRY_FILE"
    log_success "Updated $field for $id"
}

# Update a field for an existing LLM (with validation and locking)
# Args: id, field, value
update_llm_field() {
    local id="$1"
    local field="$2"
    local value="$3"

    # Validate ID format
    if ! validate_llm_id "$id"; then
        return 1
    fi

    # Validate field name (alphanumeric and underscore only)
    if [[ ! "$field" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_error "Invalid field name '$field'"
        return 1
    fi

    # Sanitize value
    if ! sanitize_registry_value "$value" >/dev/null; then
        return 1
    fi

    # Execute with file locking
    with_registry_lock _update_llm_field_impl "$id" "$field" "$value"
}

# Get count of council members
get_council_member_count() {
    get_council_members | wc -l | tr -d ' '
}

# Validate minimum council size
validate_council_size() {
    local min_size="${1:-2}"
    local count
    count=$(get_council_member_count)

    if [[ "$count" -lt "$min_size" ]]; then
        log_error "Council requires at least $min_size members (found: $count)"
        log_info "Use './council.sh models enable <id>' to add members"
        return 1
    fi
    return 0
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
        set)
            if [[ $# -lt 3 ]]; then
                log_error "Usage: llm_manager set <llm_id> <field> <value>"
                return 1
            fi
            update_llm_field "$1" "$2" "$3"
            ;;
        enable)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: llm_manager enable <llm_id>"
                return 1
            fi
            set_council_member "$1" "true"
            ;;
        disable)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: llm_manager disable <llm_id>"
                return 1
            fi
            set_council_member "$1" "false"
            ;;
        members)
            echo "Council Members:"
            get_council_members
            ;;
        count)
            echo "Council member count: $(get_council_member_count)"
            ;;
        validate)
            local min="${1:-2}"
            if validate_council_size "$min"; then
                echo "Council size is valid (minimum: $min)"
            fi
            ;;
        help|*)
            echo "LLM Manager - Manage language model configurations"
            echo ""
            echo "Usage: source lib/llm_manager.sh && llm_manager_cli <command>"
            echo ""
            echo "Commands:"
            echo "  init             Initialize LLM registry"
            echo "  list             List all registered LLMs"
            echo "  check <id>       Check if LLM is available"
            echo "  add <...>        Add new LLM to registry"
            echo "  remove <id>      Remove LLM from registry"
            echo "  get <id> <f>     Get field value for LLM"
            echo "  set <id> <f> <v> Update field value for LLM"
            echo "  enable <id>      Enable council membership"
            echo "  disable <id>     Disable council membership"
            echo "  members          List council member LLMs"
            echo "  count            Count council members"
            echo "  validate [min]   Validate minimum council size"
            ;;
    esac
}
