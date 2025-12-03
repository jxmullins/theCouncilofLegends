#!/usr/bin/env bash
#
# The Council of Legends - Persona Validator
# Validates persona files against the schema
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNCIL_ROOT="${COUNCIL_ROOT:-$SCRIPT_DIR/..}"

# Source utilities
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true

# Schema and persona locations
PERSONA_SCHEMA="$COUNCIL_ROOT/config/schemas/persona_schema.json"
PERSONAS_DIR="$COUNCIL_ROOT/config/personas"
TOON_UTIL="$COUNCIL_ROOT/lib/toon_util.py"

#=============================================================================
# Validation Functions
#=============================================================================

# Check if a persona ID already exists
# Args: $1 = persona ID to check
# Returns: 0 if exists, 1 if not
persona_id_exists() {
    local id="$1"
    local toon_file="$PERSONAS_DIR/${id}.toon"
    local json_file="$PERSONAS_DIR/${id}.json"

    [[ -f "$toon_file" ]] || [[ -f "$json_file" ]]
}

# Get list of existing persona IDs
list_existing_persona_ids() {
    local ids=()

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ -f "$file" ]]; then
            local basename
            basename=$(basename "$file")
            basename="${basename%.toon}"
            basename="${basename%.json}"
            ids+=("$basename")
        fi
    done

    # Remove duplicates and print
    printf '%s\n' "${ids[@]}" | sort -u
}

# Validate persona ID format
# Args: $1 = persona ID
# Returns: 0 if valid, 1 if invalid
validate_persona_id() {
    local id="$1"

    if [[ -z "$id" ]]; then
        echo "Error: Persona ID is required"
        return 1
    fi

    # Must start with lowercase letter, contain only lowercase letters, numbers, underscores
    if ! [[ "$id" =~ ^[a-z][a-z0-9_]*$ ]]; then
        echo "Error: Invalid ID format. Must start with lowercase letter, contain only lowercase letters, numbers, underscores."
        return 1
    fi

    return 0
}

# Validate version format (semver)
# Args: $1 = version string
validate_version() {
    local version="$1"

    if [[ -z "$version" ]]; then
        echo "Error: Version is required"
        return 1
    fi

    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid version format. Must be semver (e.g., 1.0.0)"
        return 1
    fi

    return 0
}

# Validate prompt template has required placeholders
# Args: $1 = prompt template
validate_prompt_template() {
    local template="$1"

    if [[ -z "$template" ]]; then
        echo "Error: Prompt template is required"
        return 1
    fi

    if [[ ${#template} -lt 100 ]]; then
        echo "Error: Prompt template too short (minimum 100 characters)"
        return 1
    fi

    # Check for required placeholders
    local warnings=()
    if ! echo "$template" | grep -q '{{AI_NAME}}'; then
        warnings+=("Warning: Template missing {{AI_NAME}} placeholder")
    fi
    if ! echo "$template" | grep -q '{{PROVIDER}}'; then
        warnings+=("Warning: Template missing {{PROVIDER}} placeholder")
    fi

    for warn in "${warnings[@]}"; do
        echo "$warn"
    done

    return 0
}

# Validate tags format
# Args: $1 = comma-separated tags or JSON array
validate_tags() {
    local tags="$1"

    if [[ -z "$tags" ]]; then
        return 0  # Tags are optional
    fi

    # If it's a JSON array, validate each element
    if [[ "$tags" =~ ^\[.*\]$ ]]; then
        local invalid_tags
        invalid_tags=$(echo "$tags" | jq -r '.[]' 2>/dev/null | grep -v '^[a-z][a-z0-9-]*$')
        if [[ -n "$invalid_tags" ]]; then
            echo "Error: Invalid tag format. Tags must be lowercase with hyphens only."
            echo "Invalid tags: $invalid_tags"
            return 1
        fi
    else
        # Comma-separated list
        IFS=',' read -ra tag_array <<< "$tags"
        for tag in "${tag_array[@]}"; do
            tag=$(echo "$tag" | xargs)  # Trim whitespace
            if ! [[ "$tag" =~ ^[a-z][a-z0-9-]*$ ]]; then
                echo "Error: Invalid tag '$tag'. Tags must be lowercase with hyphens only."
                return 1
            fi
        done
    fi

    return 0
}

# Validate tone enum
# Args: $1 = tone value
validate_tone() {
    local tone="$1"
    local valid_tones=("formal" "casual" "academic" "provocative" "contemplative" "pragmatic" "enthusiastic" "analytical" "encouraging" "cautious" "principled")

    if [[ -z "$tone" ]]; then
        return 0  # Tone is optional
    fi

    for valid in "${valid_tones[@]}"; do
        if [[ "$tone" == "$valid" ]]; then
            return 0
        fi
    done

    echo "Error: Invalid tone '$tone'"
    echo "Valid tones: ${valid_tones[*]}"
    return 1
}

# Validate a TOON persona file
# Args: $1 = path to TOON file
# Returns: 0 if valid, 1 if invalid
validate_toon_persona() {
    local file="$1"
    local errors=()
    local warnings=()

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        return 1
    fi

    # Check if toon_util.py exists
    if [[ ! -f "$TOON_UTIL" ]]; then
        echo "Error: TOON utility not found: $TOON_UTIL"
        return 1
    fi

    # Parse TOON to JSON for validation
    local json
    json=$(python3 "$TOON_UTIL" parse "$file" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to parse TOON file"
        echo "$json"
        return 1
    fi

    # Extract and validate fields
    local id name version description prompt_template
    id=$(echo "$json" | jq -r '.id // empty')
    name=$(echo "$json" | jq -r '.name // empty')
    version=$(echo "$json" | jq -r '.version // empty')
    description=$(echo "$json" | jq -r '.description // empty')
    prompt_template=$(echo "$json" | jq -r '.prompt_template // empty')

    # Required field validations
    if ! validate_persona_id "$id"; then
        errors+=("Invalid or missing ID")
    fi

    if [[ -z "$name" ]]; then
        errors+=("Missing required field: name")
    elif [[ ${#name} -gt 50 ]]; then
        errors+=("Name too long (max 50 characters)")
    fi

    if ! validate_version "$version"; then
        errors+=("Invalid or missing version")
    fi

    if [[ -z "$description" ]]; then
        errors+=("Missing required field: description")
    elif [[ ${#description} -lt 10 ]]; then
        errors+=("Description too short (min 10 characters)")
    elif [[ ${#description} -gt 200 ]]; then
        errors+=("Description too long (max 200 characters)")
    fi

    if ! validate_prompt_template "$prompt_template" 2>&1 | grep -q "^Error"; then
        : # Valid
    else
        errors+=("$(validate_prompt_template "$prompt_template" 2>&1 | head -1)")
    fi

    # Optional field validations
    local tags tone
    tags=$(echo "$json" | jq -c '.tags // empty')
    if [[ -n "$tags" ]] && [[ "$tags" != "null" ]]; then
        local tag_result
        tag_result=$(validate_tags "$tags" 2>&1)
        if [[ $? -ne 0 ]]; then
            errors+=("$tag_result")
        fi
    fi

    tone=$(echo "$json" | jq -r '.style.tone // empty')
    if [[ -n "$tone" ]]; then
        local tone_result
        tone_result=$(validate_tone "$tone" 2>&1)
        if [[ $? -ne 0 ]]; then
            errors+=("$tone_result")
        fi
    fi

    # Check for template placeholders (warnings only)
    if ! echo "$prompt_template" | grep -q '{{AI_NAME}}'; then
        warnings+=("Missing {{AI_NAME}} placeholder in prompt template")
    fi
    if ! echo "$prompt_template" | grep -q '{{PROVIDER}}'; then
        warnings+=("Missing {{PROVIDER}} placeholder in prompt template")
    fi

    # Report results
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "Warnings:"
        for warn in "${warnings[@]}"; do
            echo "  - $warn"
        done
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Errors:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi

    echo "Validation passed: $file"
    return 0
}

# Validate a JSON persona file
# Args: $1 = path to JSON file
validate_json_persona() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        return 1
    fi

    # Check if valid JSON
    if ! jq . "$file" >/dev/null 2>&1; then
        echo "Error: Invalid JSON syntax in $file"
        return 1
    fi

    # Use same validation as TOON (reuse the parsed JSON)
    local json
    json=$(cat "$file")

    # Create temp TOON-like structure for validation
    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/persona_validate.XXXXXX.json")
    echo "$json" > "$temp_file"

    # Extract and validate (same as TOON validation)
    local id name version description prompt_template
    id=$(echo "$json" | jq -r '.id // empty')
    name=$(echo "$json" | jq -r '.name // empty')
    version=$(echo "$json" | jq -r '.version // empty')
    description=$(echo "$json" | jq -r '.description // empty')
    prompt_template=$(echo "$json" | jq -r '.prompt_template // empty')

    local errors=()

    if ! validate_persona_id "$id" 2>/dev/null; then
        errors+=("Invalid or missing ID")
    fi

    if [[ -z "$name" ]]; then
        errors+=("Missing required field: name")
    fi

    if ! validate_version "$version" 2>/dev/null; then
        errors+=("Invalid or missing version")
    fi

    if [[ -z "$description" ]]; then
        errors+=("Missing required field: description")
    fi

    if [[ -z "$prompt_template" ]] || [[ ${#prompt_template} -lt 100 ]]; then
        errors+=("Invalid or missing prompt_template (min 100 chars)")
    fi

    rm -f "$temp_file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Errors in $file:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi

    echo "Validation passed: $file"
    return 0
}

# Validate any persona file (auto-detect format)
# Args: $1 = path to persona file
validate_persona_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        return 1
    fi

    local ext="${file##*.}"

    case "$ext" in
        toon)
            validate_toon_persona "$file"
            ;;
        json)
            validate_json_persona "$file"
            ;;
        *)
            echo "Error: Unknown file type: $ext (expected .toon or .json)"
            return 1
            ;;
    esac
}

# Test template substitution
# Args: $1 = prompt template, $2 = AI name, $3 = provider
test_template_substitution() {
    local template="$1"
    local ai_name="${2:-Claude}"
    local provider="${3:-Anthropic}"

    local result="$template"
    result="${result//\{\{AI_NAME\}\}/$ai_name}"
    result="${result//\{\{PROVIDER\}\}/$provider}"

    echo "$result"
}

# Preview a persona with sample substitutions
# Args: $1 = persona file
preview_persona() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        return 1
    fi

    local json
    if [[ "$file" == *.toon ]]; then
        json=$(python3 "$TOON_UTIL" parse "$file" 2>/dev/null)
    else
        json=$(cat "$file")
    fi

    local id name version description prompt_template
    id=$(echo "$json" | jq -r '.id')
    name=$(echo "$json" | jq -r '.name')
    version=$(echo "$json" | jq -r '.version')
    description=$(echo "$json" | jq -r '.description')
    prompt_template=$(echo "$json" | jq -r '.prompt_template')

    echo "=== Persona Preview ==="
    echo "ID:          $id"
    echo "Name:        $name"
    echo "Version:     $version"
    echo "Description: $description"
    echo ""
    echo "=== Sample Prompt (as Claude) ==="
    test_template_substitution "$prompt_template" "Claude" "Anthropic" | head -20
    echo "..."
    echo ""
    echo "=== Sample Prompt (as Codex) ==="
    test_template_substitution "$prompt_template" "Codex" "OpenAI" | head -20
    echo "..."
}

# Validate all personas in the personas directory
validate_all_personas() {
    local pass=0
    local fail=0

    echo "Validating all personas in $PERSONAS_DIR..."
    echo ""

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ -f "$file" ]]; then
            if validate_persona_file "$file"; then
                ((pass++))
            else
                ((fail++))
            fi
            echo ""
        fi
    done

    echo "=== Summary ==="
    echo "Passed: $pass"
    echo "Failed: $fail"

    [[ $fail -eq 0 ]]
}

#=============================================================================
# CLI Interface
#=============================================================================

show_help() {
    cat <<EOF
Usage: persona_validator.sh [command] [options]

Commands:
    validate <file>     Validate a single persona file
    validate-all        Validate all personas in config/personas/
    preview <file>      Preview a persona with sample substitutions
    list                List all existing persona IDs
    check-id <id>       Check if a persona ID already exists
    help                Show this help message

Examples:
    ./lib/persona_validator.sh validate config/personas/philosopher.toon
    ./lib/persona_validator.sh validate-all
    ./lib/persona_validator.sh preview config/personas/educator.toon
    ./lib/persona_validator.sh check-id my_new_persona
EOF
}

# Main entry point
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        validate)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a file to validate"
                exit 1
            fi
            validate_persona_file "$1"
            ;;
        validate-all)
            validate_all_personas
            ;;
        preview)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a file to preview"
                exit 1
            fi
            preview_persona "$1"
            ;;
        list)
            list_existing_persona_ids
            ;;
        check-id)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify an ID to check"
                exit 1
            fi
            if persona_id_exists "$1"; then
                echo "ID '$1' already exists"
                exit 1
            else
                echo "ID '$1' is available"
                exit 0
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
