#!/usr/bin/env bash
#
# The Council of Legends - Team Role Management
# Task-oriented role personas for Team Collaboration mode
#

# Get the script directory
COUNCIL_ROOT="${COUNCIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Source LLM manager for dynamic council membership
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LLM_MANAGER_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/llm_manager.sh"
    export LLM_MANAGER_LOADED=true
fi

# TOON utility path
TOON_UTIL="${TOON_UTIL:-$COUNCIL_ROOT/lib/toon_util.py}"

#=============================================================================
# Role Assignments (tracks current role for each AI during team work)
#=============================================================================

declare -A ROLE_ASSIGNMENTS
ROLE_ASSIGNMENTS[claude]=""
ROLE_ASSIGNMENTS[codex]=""
ROLE_ASSIGNMENTS[gemini]=""
ROLE_ASSIGNMENTS[arbiter]=""

#=============================================================================
# Role File Management
#=============================================================================

# Get role file path (TOON format, with JSON fallback)
# Args: $1 = role id
get_role_file() {
    local role="$1"
    local toon_file="$COUNCIL_ROOT/config/roles/${role}.toon"
    local json_file="$COUNCIL_ROOT/config/roles/${role}.json"

    # Prefer TOON, fall back to JSON
    if [[ -f "$toon_file" ]]; then
        echo "$toon_file"
    elif [[ -f "$json_file" ]]; then
        echo "$json_file"
    else
        echo ""
    fi
}

# Read field from role file (TOON or JSON)
# Args: $1 = role file, $2 = field name
read_role_field() {
    local role_file="$1"
    local field="$2"

    if [[ "$role_file" == *.toon ]]; then
        "$TOON_UTIL" get "$role_file" "$field"
    else
        jq -r ".$field // empty" "$role_file"
    fi
}

# Check if role exists
# Args: $1 = role id
role_exists() {
    local role="$1"
    local role_file
    role_file=$(get_role_file "$role")
    [[ -n "$role_file" ]] && [[ -f "$role_file" ]]
}

#=============================================================================
# Role Assignment
#=============================================================================

# Set role for a specific AI
# Args: $1 = AI id, $2 = role id
set_role() {
    local ai="$1"
    local role="$2"

    if [[ -n "$role" ]] && ! role_exists "$role"; then
        log_warn "Role not found: $role (using no role)"
        ROLE_ASSIGNMENTS[$ai]=""
        return 1
    fi

    ROLE_ASSIGNMENTS[$ai]="$role"
    log_debug "Assigned role '$role' to $ai"
}

# Get current role for an AI
# Args: $1 = AI id
get_role() {
    local ai="$1"
    echo "${ROLE_ASSIGNMENTS[$ai]:-}"
}

# Clear role for an AI
# Args: $1 = AI id
clear_role() {
    local ai="$1"
    ROLE_ASSIGNMENTS[$ai]=""
}

# Clear all role assignments
clear_all_roles() {
    ROLE_ASSIGNMENTS[claude]=""
    ROLE_ASSIGNMENTS[codex]=""
    ROLE_ASSIGNMENTS[gemini]=""
    ROLE_ASSIGNMENTS[arbiter]=""
}

#=============================================================================
# Role Prompt Loading
#=============================================================================

# Load role prompt template
# Args: $1 = role id
# Returns: The role's prompt_template content
load_role_prompt() {
    local role="$1"

    if [[ -z "$role" ]]; then
        echo ""
        return
    fi

    local role_file
    role_file=$(get_role_file "$role")

    if [[ -n "$role_file" ]] && [[ -f "$role_file" ]]; then
        read_role_field "$role_file" "prompt_template"
    else
        echo ""
    fi
}

# Build stacked system prompt: AI identity + role
# Args: $1 = AI id
#       $2 = role id (optional, uses assigned role if not provided)
# Returns: Complete system prompt with role stacked on identity
build_role_system_prompt() {
    local ai="$1"
    local role="${2:-${ROLE_ASSIGNMENTS[$ai]:-}}"

    # Get AI identity from config.sh
    local ai_name provider
    ai_name=$(get_ai_name "$ai")
    provider=$(get_ai_provider "$ai")

    # Base identity prompt for team mode
    local identity_prompt="You are $ai_name (powered by $provider), participating in The Council of Legends team collaboration."

    # If no role assigned, return just identity
    if [[ -z "$role" ]]; then
        echo "$identity_prompt"
        return
    fi

    # Load role prompt
    local role_prompt
    role_prompt=$(load_role_prompt "$role")

    if [[ -n "$role_prompt" ]]; then
        # Stack role on top of identity
        cat <<EOF
$identity_prompt

--- CURRENT ROLE ---
$role_prompt
--- END ROLE ---
EOF
    else
        echo "$identity_prompt"
    fi
}

#=============================================================================
# Role Metadata
#=============================================================================

# Get role display name
# Args: $1 = role id
get_role_name() {
    local role="$1"
    local role_file
    role_file=$(get_role_file "$role")

    if [[ -n "$role_file" ]] && [[ -f "$role_file" ]]; then
        read_role_field "$role_file" "name"
    else
        echo "$role"
    fi
}

# Get role category
# Args: $1 = role id
get_role_category() {
    local role="$1"
    local role_file
    role_file=$(get_role_file "$role")

    if [[ -n "$role_file" ]] && [[ -f "$role_file" ]]; then
        read_role_field "$role_file" "category"
    fi
}

# Get role description
# Args: $1 = role id
get_role_description() {
    local role="$1"
    local role_file
    role_file=$(get_role_file "$role")

    if [[ -n "$role_file" ]] && [[ -f "$role_file" ]]; then
        read_role_field "$role_file" "description"
    fi
}

#=============================================================================
# Role Listing
#=============================================================================

# List all available roles
list_roles() {
    local roles_dir="$COUNCIL_ROOT/config/roles"

    if [[ ! -d "$roles_dir" ]]; then
        return
    fi

    # Find all .toon and .json role files
    local role_files
    role_files=$(find "$roles_dir" -maxdepth 1 \( -name "*.toon" -o -name "*.json" \) -type f 2>/dev/null | sort)

    for role_file in $role_files; do
        local role_id
        role_id=$(basename "$role_file" | sed 's/\.\(toon\|json\)$//')
        echo "$role_id"
    done
}

# List roles by category
# Args: $1 = category
list_roles_by_category() {
    local category="$1"
    local all_roles
    all_roles=$(list_roles)

    for role in $all_roles; do
        local role_category
        role_category=$(get_role_category "$role")
        if [[ "$role_category" == "$category" ]]; then
            echo "$role"
        fi
    done
}

# Display role summary (for user display)
display_role_summary() {
    local role="$1"
    local name description category

    name=$(get_role_name "$role")
    description=$(get_role_description "$role")
    category=$(get_role_category "$role")

    echo "$name [$category]: $description"
}

#=============================================================================
# Role Assignment Utilities for PM
#=============================================================================

# Apply role assignments from plan JSON
# Args: $1 = plan file or JSON content
apply_role_assignments_from_plan() {
    local plan="$1"

    # If it's a file, read it
    if [[ -f "$plan" ]]; then
        plan=$(cat "$plan")
    fi

    # Extract role assignments (supports both subtask roles and milestone role_assignments)
    # Check for subtask roles first
    local subtasks
    subtasks=$(echo "$plan" | jq -r '.subtasks[]? | "\(.assignee):\(.role // empty)"' 2>/dev/null)

    for assignment in $subtasks; do
        if [[ "$assignment" == *":"* ]] && [[ "$assignment" != *":\"\"" ]] && [[ "$assignment" != *":" ]]; then
            local ai="${assignment%%:*}"
            local role="${assignment##*:}"
            if [[ -n "$role" ]] && [[ "$role" != "null" ]]; then
                set_role "$ai" "$role"
            fi
        fi
    done

    # Check for milestone role_assignments
    local milestone_roles
    milestone_roles=$(echo "$plan" | jq -r '.milestone?.role_assignments? // .role_assignments? // {} | to_entries[] | "\(.key):\(.value)"' 2>/dev/null)

    for assignment in $milestone_roles; do
        if [[ "$assignment" == *":"* ]]; then
            local ai="${assignment%%:*}"
            local role="${assignment##*:}"
            if [[ -n "$role" ]] && [[ "$role" != "null" ]]; then
                set_role "$ai" "$role"
            fi
        fi
    done
}

# Get display string showing all current role assignments
get_role_assignments_display() {
    local display=""

    local all_llms
    mapfile -t all_llms < <(get_all_llm_ids)
    for ai in "${all_llms[@]}"; do
        local role="${ROLE_ASSIGNMENTS[$ai]:-}"
        if [[ -n "$role" ]]; then
            local ai_name role_name
            ai_name=$(get_ai_name "$ai")
            role_name=$(get_role_name "$role")
            if [[ -n "$display" ]]; then
                display+=", "
            fi
            display+="$ai_name → $role_name"
        fi
    done

    if [[ -z "$display" ]]; then
        echo "(no roles assigned)"
    else
        echo "$display"
    fi
}

log_debug "Roles module loaded"
