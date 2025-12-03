#!/usr/bin/env bash
#
# The Council of Legends - Interactive Persona Creator
# A wizard for creating custom personas
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COUNCIL_ROOT="$SCRIPT_DIR"

# Source libraries
source "$COUNCIL_ROOT/lib/utils.sh" 2>/dev/null || {
    # Minimal color fallbacks if utils.sh not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    NC='\033[0m'
}
source "$COUNCIL_ROOT/lib/persona_validator.sh" 2>/dev/null || true

# Directories
PERSONAS_DIR="$COUNCIL_ROOT/config/personas"
TOON_UTIL="$COUNCIL_ROOT/lib/toon_util.py"

#=============================================================================
# UI Helpers
#=============================================================================

clear_screen() {
    printf '\033[2J\033[H'
}

print_banner() {
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}PERSONA CREATOR WIZARD${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${CYAN}The Council of Legends${NC}                         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local total="$2"
    local title="$3"
    echo ""
    echo -e "${BOLD}Step $step/$total: $title${NC}"
    echo -e "${WHITE}────────────────────────────────────────────${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC}  $1"
}

# Read input with default value
read_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -rp "$prompt: " result
        echo "$result"
    fi
}

# Read multiline input
read_multiline() {
    local prompt="$1"
    echo "$prompt"
    echo -e "${WHITE}(Enter your text. Type 'END' on a new line when done)${NC}"
    echo ""

    local content=""
    local line
    while IFS= read -r line; do
        if [[ "$line" == "END" ]]; then
            break
        fi
        content+="$line"$'\n'
    done

    # Remove trailing newline
    echo "${content%$'\n'}"
}

# Select from options
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo "$prompt"
    echo ""
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done
    echo ""

    local choice
    while true; do
        read -rp "Select [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        print_error "Invalid choice. Please enter a number between 1 and ${#options[@]}"
    done
}

#=============================================================================
# Data Collection
#=============================================================================

# Get existing tags for suggestions
get_existing_tags() {
    local all_tags=()

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ -f "$file" ]]; then
            local tags
            if [[ "$file" == *.toon ]]; then
                tags=$(python3 "$TOON_UTIL" parse "$file" 2>/dev/null | jq -r '.tags[]?' 2>/dev/null) || continue
            else
                tags=$(jq -r '.tags[]?' "$file" 2>/dev/null) || continue
            fi
            while IFS= read -r tag; do
                [[ -n "$tag" ]] && all_tags+=("$tag")
            done <<< "$tags"
        fi
    done

    # Unique and sort
    printf '%s\n' "${all_tags[@]}" | sort -u
}

# Collect persona information
collect_persona_info() {
    local -n info=$1

    clear_screen
    print_banner

    # Step 1: Basic Info
    print_step 1 7 "Basic Information"

    # ID
    while true; do
        info[id]=$(read_with_default "Persona ID (lowercase, underscores allowed)" "")
        if [[ -z "${info[id]}" ]]; then
            print_error "ID is required"
            continue
        fi
        if ! [[ "${info[id]}" =~ ^[a-z][a-z0-9_]*$ ]]; then
            print_error "ID must start with lowercase letter, contain only lowercase letters, numbers, underscores"
            continue
        fi
        if persona_id_exists "${info[id]}" 2>/dev/null; then
            print_warning "A persona with ID '${info[id]}' already exists"
            read -rp "Overwrite? [y/N]: " overwrite
            if [[ ! "$overwrite" =~ ^[Yy] ]]; then
                continue
            fi
        fi
        break
    done

    # Name
    while true; do
        info[name]=$(read_with_default "Display Name" "")
        if [[ -z "${info[name]}" ]]; then
            print_error "Name is required"
            continue
        fi
        if [[ ${#info[name]} -gt 50 ]]; then
            print_error "Name too long (max 50 characters)"
            continue
        fi
        break
    done

    # Version
    info[version]=$(read_with_default "Version" "1.0.0")
    if ! [[ "${info[version]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warning "Invalid version format, using 1.0.0"
        info[version]="1.0.0"
    fi

    # Author
    info[author]=$(read_with_default "Author" "$(whoami)")

    echo ""
    print_success "Basic info collected"

    # Step 2: Description
    print_step 2 7 "Description"
    print_info "A brief description of this persona's approach and personality (10-200 chars)"
    echo ""

    while true; do
        info[description]=$(read_with_default "Description" "")
        if [[ -z "${info[description]}" ]]; then
            print_error "Description is required"
            continue
        fi
        if [[ ${#info[description]} -lt 10 ]]; then
            print_error "Description too short (min 10 characters)"
            continue
        fi
        if [[ ${#info[description]} -gt 200 ]]; then
            print_error "Description too long (max 200 characters)"
            continue
        fi
        break
    done

    print_success "Description set"

    # Step 3: Tags
    print_step 3 7 "Tags"
    print_info "Tags help categorize and search for personas"
    echo ""

    echo "Existing tags in your collection:"
    local existing_tags
    existing_tags=$(get_existing_tags)
    if [[ -n "$existing_tags" ]]; then
        echo -e "${CYAN}$(echo "$existing_tags" | tr '\n' ', ' | sed 's/,$//')${NC}"
    else
        echo -e "${CYAN}(none yet)${NC}"
    fi
    echo ""

    print_info "Enter tags separated by commas (e.g., ethics,philosophy,careful)"
    info[tags]=$(read_with_default "Tags" "")

    print_success "Tags set"

    # Step 4: Style
    print_step 4 7 "Style Configuration"

    # Tone
    echo ""
    print_info "Select the persona's communication tone:"
    local tones=("formal" "casual" "academic" "provocative" "contemplative" "pragmatic" "enthusiastic" "analytical" "encouraging" "cautious" "principled")
    info[tone]=$(select_option "" "${tones[@]}")
    echo ""

    # Approach
    print_info "Describe the persona's approach/methodology:"
    print_info "Example: 'Socratic questioning', 'First-principles analysis', 'Evidence-based reasoning'"
    info[approach]=$(read_with_default "Approach" "")
    echo ""

    # Strengths
    print_info "List the persona's key strengths (comma-separated):"
    print_info "Example: clarity, depth, creativity, precision"
    info[strengths]=$(read_with_default "Strengths" "")

    print_success "Style configured"

    # Step 5: Compatibility (Optional)
    print_step 5 7 "Compatibility Settings (Optional)"

    echo ""
    read -rp "Configure compatibility settings? [y/N]: " configure_compat

    if [[ "$configure_compat" =~ ^[Yy] ]]; then
        print_info "Which debate modes work best with this persona?"
        print_info "Options: collaborative, adversarial, exploratory, scotus, all"
        info[debate_modes]=$(read_with_default "Debate modes" "all")

        print_info "Which other personas work well with this one?"
        print_info "Enter persona IDs separated by commas, or 'all'"
        info[works_well_with]=$(read_with_default "Works well with" "all")
    else
        info[debate_modes]="all"
        info[works_well_with]="all"
    fi

    print_success "Compatibility set"

    # Step 6: Prompt Template
    print_step 6 7 "Prompt Template"

    echo ""
    print_info "The prompt template defines how the AI will behave with this persona."
    print_info "Use these placeholders:"
    echo -e "  ${CYAN}{{AI_NAME}}${NC}   - Will be replaced with the AI's name (Claude, Codex, Gemini)"
    echo -e "  ${CYAN}{{PROVIDER}}${NC}  - Will be replaced with the provider (Anthropic, OpenAI, Google)"
    echo ""
    print_info "Minimum 100 characters. Be specific about the persona's approach."
    echo ""

    echo "Example structure:"
    echo -e "${WHITE}You are {{AI_NAME}} the [Role], powered by {{PROVIDER}}.${NC}"
    echo -e "${WHITE}Your approach: [describe methodology]${NC}"
    echo -e "${WHITE}Your personality: [describe traits]${NC}"
    echo -e "${WHITE}In debates, you: [describe behavior]${NC}"
    echo ""

    while true; do
        info[prompt_template]=$(read_multiline "Enter your prompt template:")

        if [[ ${#info[prompt_template]} -lt 100 ]]; then
            print_error "Prompt template too short (minimum 100 characters, you have ${#info[prompt_template]})"
            continue
        fi

        # Check for placeholders
        if ! echo "${info[prompt_template]}" | grep -q '{{AI_NAME}}'; then
            print_warning "Template missing {{AI_NAME}} placeholder (recommended)"
            read -rp "Continue anyway? [y/N]: " cont
            [[ ! "$cont" =~ ^[Yy] ]] && continue
        fi
        if ! echo "${info[prompt_template]}" | grep -q '{{PROVIDER}}'; then
            print_warning "Template missing {{PROVIDER}} placeholder (recommended)"
            read -rp "Continue anyway? [y/N]: " cont
            [[ ! "$cont" =~ ^[Yy] ]] && continue
        fi

        break
    done

    print_success "Prompt template set"
}

#=============================================================================
# Preview and Output
#=============================================================================

# Show preview of the persona
show_preview() {
    local -n info=$1

    print_step 7 7 "Preview"

    echo ""
    echo -e "${BOLD}=== Persona Summary ===${NC}"
    echo ""
    echo -e "ID:          ${CYAN}${info[id]}${NC}"
    echo -e "Name:        ${info[name]}"
    echo -e "Version:     ${info[version]}"
    echo -e "Author:      ${info[author]}"
    echo -e "Description: ${info[description]}"
    echo -e "Tags:        ${info[tags]}"
    echo ""
    echo -e "${BOLD}Style:${NC}"
    echo -e "  Tone:      ${info[tone]}"
    echo -e "  Approach:  ${info[approach]}"
    echo -e "  Strengths: ${info[strengths]}"
    echo ""

    echo -e "${BOLD}=== Sample Prompt (as Claude) ===${NC}"
    echo ""
    local sample="${info[prompt_template]}"
    sample="${sample//\{\{AI_NAME\}\}/Claude}"
    sample="${sample//\{\{PROVIDER\}\}/Anthropic}"
    echo "$sample" | head -10
    if [[ $(echo "${info[prompt_template]}" | wc -l) -gt 10 ]]; then
        echo "..."
    fi
    echo ""

    echo -e "${BOLD}=== Sample Prompt (as Codex) ===${NC}"
    echo ""
    sample="${info[prompt_template]}"
    sample="${sample//\{\{AI_NAME\}\}/Codex}"
    sample="${sample//\{\{PROVIDER\}\}/OpenAI}"
    echo "$sample" | head -10
    if [[ $(echo "${info[prompt_template]}" | wc -l) -gt 10 ]]; then
        echo "..."
    fi
    echo ""
}

# Generate TOON file content
generate_toon() {
    local -n info=$1

    local tags_array=""
    if [[ -n "${info[tags]}" ]]; then
        IFS=',' read -ra tag_arr <<< "${info[tags]}"
        tags_array="tags[${#tag_arr[@]}]: $(echo "${info[tags]}" | tr ',' ',')"
    fi

    local strengths_array=""
    if [[ -n "${info[strengths]}" ]]; then
        IFS=',' read -ra str_arr <<< "${info[strengths]}"
        strengths_array="  strengths[${#str_arr[@]}]: ${info[strengths]}"
    fi

    local debate_modes_val=""
    if [[ "${info[debate_modes]}" != "all" ]]; then
        IFS=',' read -ra dm_arr <<< "${info[debate_modes]}"
        debate_modes_val="    debate_modes[${#dm_arr[@]}]: ${info[debate_modes]}"
    else
        debate_modes_val="    debate_modes[4]: collaborative,adversarial,exploratory,scotus"
    fi

    local works_with_val=""
    if [[ "${info[works_well_with]}" != "all" ]]; then
        IFS=',' read -ra ww_arr <<< "${info[works_well_with]}"
        works_with_val="    works_well_with[${#ww_arr[@]}]: ${info[works_well_with]}"
    fi

    # Build the TOON content
    cat <<EOF
# ${info[name]} Persona
# Created: $(date +%Y-%m-%d)
# Author: ${info[author]}

id: ${info[id]}
name: ${info[name]}
version: ${info[version]}
author: ${info[author]}
description: "${info[description]}"
$tags_array

prompt_template: """
${info[prompt_template]}
"""

style:
  tone: ${info[tone]}
  approach: "${info[approach]}"
$strengths_array

compatibility:
$debate_modes_val
$works_with_val
EOF
}

# Save the persona
save_persona() {
    local -n info=$1
    local output_file="$PERSONAS_DIR/${info[id]}.toon"

    # Generate TOON content
    local content
    content=$(generate_toon info)

    # Write to file
    echo "$content" > "$output_file"

    # Validate
    if validate_persona_file "$output_file" >/dev/null 2>&1; then
        print_success "Persona saved and validated: $output_file"
        return 0
    else
        print_warning "Persona saved but validation had issues:"
        validate_persona_file "$output_file"
        return 1
    fi
}

#=============================================================================
# Main Wizard
#=============================================================================

run_wizard() {
    # Declare associative array for persona info
    declare -A persona_info

    # Collect all information
    collect_persona_info persona_info

    # Show preview
    clear_screen
    print_banner
    show_preview persona_info

    # Confirm save
    echo ""
    echo -e "${BOLD}Ready to save this persona?${NC}"
    echo ""
    echo "  1) Save and exit"
    echo "  2) Edit (start over)"
    echo "  3) Cancel"
    echo ""

    local choice
    read -rp "Choose [1-3]: " choice

    case "$choice" in
        1)
            save_persona persona_info
            echo ""
            echo -e "${BOLD}Usage:${NC}"
            echo "  ./council.sh \"topic\" --personas claude:${persona_info[id]}"
            echo "  ./council.sh \"topic\" --personas codex:${persona_info[id]},gemini:${persona_info[id]}"
            echo ""
            ;;
        2)
            run_wizard
            ;;
        3)
            echo "Cancelled."
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

#=============================================================================
# CLI Interface
#=============================================================================

show_help() {
    cat <<EOF
Usage: create_persona.sh [options]

Interactive wizard for creating custom personas for The Council of Legends.

Options:
    --help, -h     Show this help message
    --quick        Skip optional fields for faster creation

The wizard will guide you through:
  1. Basic Information (ID, name, version, author)
  2. Description
  3. Tags (with suggestions from existing personas)
  4. Style (tone, approach, strengths)
  5. Compatibility settings (optional)
  6. Prompt template (with placeholder guidance)
  7. Preview with live AI substitutions
  8. Validation and save

Examples:
    ./create_persona.sh              # Full wizard
    ./create_persona.sh --quick      # Skip optional fields

After creation, use your persona:
    ./council.sh "topic" --personas claude:your_persona_id
EOF
}

main() {
    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --quick)
            export QUICK_MODE=true
            ;;
    esac

    # Check dependencies
    if [[ ! -f "$TOON_UTIL" ]]; then
        print_error "TOON utility not found: $TOON_UTIL"
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        print_error "Python 3 is required"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        print_error "jq is required"
        exit 1
    fi

    # Ensure personas directory exists
    mkdir -p "$PERSONAS_DIR"

    # Run the wizard
    run_wizard
}

main "$@"
