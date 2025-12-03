#!/usr/bin/env bash
#
# The Council of Legends - Utility Functions
# Common utilities for logging, colors, and helper functions
#

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color
export BOLD='\033[1m'

# AI-specific colors
export CLAUDE_COLOR='\033[0;35m'   # Purple
export CODEX_COLOR='\033[0;32m'    # Green
export GEMINI_COLOR='\033[0;34m'   # Blue
export GROQ_COLOR='\033[0;33m'     # Orange/Yellow (4th AI Arbiter)

#=============================================================================
# Logging Functions
#=============================================================================

# Log file configuration
COUNCIL_LOG_DIR="${COUNCIL_LOG_DIR:-${COUNCIL_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/logs}"
COUNCIL_LOG_FILE="${COUNCIL_LOG_FILE:-}"
COUNCIL_LOG_LEVEL="${COUNCIL_LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

# Initialize logging - call this to enable file logging
init_logging() {
    local session_id="${1:-$(date +%Y%m%d_%H%M%S)}"

    mkdir -p "$COUNCIL_LOG_DIR"
    COUNCIL_LOG_FILE="$COUNCIL_LOG_DIR/council_${session_id}.log"

    # Create/clear log file with header
    {
        echo "=============================================="
        echo "Council of Legends - Session Log"
        echo "Started: $(date -Iseconds)"
        echo "Session: $session_id"
        echo "=============================================="
        echo ""
    } > "$COUNCIL_LOG_FILE"

    # Create symlink to latest log
    ln -sf "$(basename "$COUNCIL_LOG_FILE")" "$COUNCIL_LOG_DIR/latest.log"

    _log_to_file "INFO" "Logging initialized"
}

# Internal function to write to log file
_log_to_file() {
    local level="$1"
    local message="$2"

    if [[ -n "${COUNCIL_LOG_FILE:-}" ]] && [[ -w "${COUNCIL_LOG_FILE}" || -w "$(dirname "${COUNCIL_LOG_FILE}")" ]]; then
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] [$level] $message" >> "$COUNCIL_LOG_FILE"
    fi
}

# Check if we should log at this level
_should_log() {
    local level="$1"
    local levels=("DEBUG" "INFO" "WARN" "ERROR")
    local current_idx=0
    local level_idx=0

    for i in "${!levels[@]}"; do
        [[ "${levels[$i]}" == "$COUNCIL_LOG_LEVEL" ]] && current_idx=$i
        [[ "${levels[$i]}" == "$level" ]] && level_idx=$i
    done

    [[ $level_idx -ge $current_idx ]]
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    _log_to_file "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    _log_to_file "INFO" "[SUCCESS] $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
    _log_to_file "ERROR" "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    _log_to_file "WARN" "$1"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]] || _should_log "DEBUG"; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
    # Always log debug to file if logging is enabled
    _log_to_file "DEBUG" "$1"
}

# Log a structured event (JSON format for telemetry)
log_event() {
    local event_type="$1"
    local event_data="${2:-{}}"

    if [[ -n "${COUNCIL_LOG_FILE:-}" ]]; then
        local timestamp
        timestamp=$(date -Iseconds)
        local json_line
        json_line=$(jq -c --arg ts "$timestamp" --arg type "$event_type" \
            '. + {timestamp: $ts, event: $type}' <<< "$event_data" 2>/dev/null || echo "{\"timestamp\":\"$timestamp\",\"event\":\"$event_type\",\"data\":\"$event_data\"}")
        echo "$json_line" >> "${COUNCIL_LOG_FILE%.log}.events.jsonl"
    fi
}

#=============================================================================
# Display Functions
#=============================================================================

separator() {
    local char="${1:-━}"
    local width="${2:-50}"
    printf "${PURPLE}"
    printf '%*s' "$width" '' | tr ' ' "$char"
    printf "${NC}\n"
}

header() {
    local title="$1"
    echo ""
    separator "═" 52
    printf "${PURPLE}║${NC} ${BOLD}%-48s${NC} ${PURPLE}║${NC}\n" "$title"
    separator "═" 52
    echo ""
}

ai_header() {
    local ai="$1"
    local phase="$2"
    local color
    local name

    case "$ai" in
        claude)
            color="$CLAUDE_COLOR"
            name="Claude"
            ;;
        codex)
            color="$CODEX_COLOR"
            name="Codex"
            ;;
        gemini)
            color="$GEMINI_COLOR"
            name="Gemini"
            ;;
        groq)
            color="$GROQ_COLOR"
            name="Arbiter"
            ;;
        council)
            color="$PURPLE"
            name="The Council"
            ;;
        *)
            color="$WHITE"
            name="$ai"
            ;;
    esac

    echo ""
    echo -e "${color}━━━ ${name}: ${phase} ━━━${NC}"
}

#=============================================================================
# Portable Timeout Function
#=============================================================================

run_with_timeout() {
    local timeout_seconds="$1"
    shift

    # Check if gtimeout (from coreutils) or timeout exists
    if command -v gtimeout &>/dev/null; then
        gtimeout "$timeout_seconds" "$@"
    elif command -v timeout &>/dev/null; then
        timeout "$timeout_seconds" "$@"
    else
        # Fallback: run without timeout on macOS
        "$@" &
        local pid=$!
        local count=0
        while kill -0 $pid 2>/dev/null; do
            sleep 1
            ((count++))
            if [[ $count -ge $timeout_seconds ]]; then
                kill -9 $pid 2>/dev/null
                return 124  # timeout exit code
            fi
        done
        wait $pid
        return $?
    fi
}

#=============================================================================
# Output Normalization
#=============================================================================

# Normalize LLM output for consistency across adapters
# - Removes trailing whitespace from each line
# - Normalizes line endings to Unix (\n)
# - Ensures exactly one trailing newline
# - Removes any BOM characters
normalize_output_file() {
    local file="$1"

    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 0
    fi

    local temp_file="${file}.norm"

    # Remove BOM, normalize line endings, trim trailing whitespace per line,
    # then ensure single trailing newline
    sed 's/\xEF\xBB\xBF//g' "$file" | \
        tr -d '\r' | \
        sed 's/[[:space:]]*$//' | \
        sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' > "$temp_file"

    # Ensure single trailing newline
    echo "" >> "$temp_file"

    mv "$temp_file" "$file"
}

#=============================================================================
# String Helpers
#=============================================================================

slugify() {
    local input="$1"
    echo "$input" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/_/g' | \
        sed 's/__*/_/g' | \
        sed 's/^_//;s/_$//' | \
        cut -c1-50
}

truncate() {
    local text="$1"
    local max_len="${2:-100}"
    if [[ ${#text} -gt $max_len ]]; then
        echo "${text:0:$max_len}..."
    else
        echo "$text"
    fi
}

#=============================================================================
# File Helpers
#=============================================================================

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

safe_write() {
    local file="$1"
    local content="$2"
    ensure_dir "$(dirname "$file")"
    echo "$content" > "$file"
}

#=============================================================================
# Validation
#=============================================================================

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
    return 0
}

# Check system dependencies (jq, curl, python3)
# These are required by various parts of the codebase
validate_system_dependencies() {
    local missing=()
    local warnings=()

    # Required dependencies
    if ! command -v jq &>/dev/null; then
        missing+=("jq (JSON processing)")
    fi

    if ! command -v curl &>/dev/null; then
        missing+=("curl (API requests)")
    fi

    if ! command -v python3 &>/dev/null; then
        missing+=("python3 (TOON parser)")
    fi

    # Optional but recommended
    if ! command -v gtimeout &>/dev/null && ! command -v timeout &>/dev/null; then
        warnings+=("timeout/gtimeout (for request timeouts - install coreutils)")
    fi

    # Report warnings
    for warn in "${warnings[@]}"; do
        log_warn "Optional dependency missing: $warn"
    done

    # Report errors and fail if required deps missing
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required system dependencies:"
        for dep in "${missing[@]}"; do
            log_error "  - $dep"
        done
        echo ""
        echo "Install missing dependencies:"
        echo "  macOS:   brew install jq curl python3"
        echo "  Ubuntu:  sudo apt install jq curl python3"
        echo "  Fedora:  sudo dnf install jq curl python3"
        return 1
    fi

    return 0
}

validate_cli_availability() {
    local missing=()

    for cli in claude codex gemini; do
        if ! command -v "$cli" &>/dev/null; then
            missing+=("$cli")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing CLI tools: ${missing[*]}"
        log_error "Please install the missing tools before running the council."
        return 1
    fi

    return 0
}

# Full preflight check - run before debates/assessments
validate_all_dependencies() {
    log_debug "Running dependency preflight check..."

    # Check system dependencies first
    if ! validate_system_dependencies; then
        return 1
    fi

    # Then check AI CLIs
    if ! validate_cli_availability; then
        return 1
    fi

    log_debug "All dependencies validated"
    return 0
}

#=============================================================================
# Date/Time Helpers
#=============================================================================

timestamp() {
    date '+%Y%m%d_%H%M%S'
}

human_date() {
    date '+%Y-%m-%d %H:%M:%S'
}

#=============================================================================
# Response Display Functions
#=============================================================================

display_response() {
    local ai="$1"
    local response_file="$2"
    local color
    color=$(get_ai_color "$ai")

    if [[ -f "$response_file" ]] && [[ -s "$response_file" ]]; then
        echo ""
        echo -e "${color}"
        cat "$response_file"
        echo -e "${NC}"
        echo ""
    else
        log_warn "No response to display from $ai"
    fi
}

display_synthesis() {
    local synthesis_file="$1"

    if [[ -f "$synthesis_file" ]] && [[ -s "$synthesis_file" ]]; then
        echo ""
        echo -e "${BOLD}${WHITE}"
        cat "$synthesis_file"
        echo -e "${NC}"
        echo ""
    else
        log_warn "No synthesis to display"
    fi
}

#=============================================================================
# Transcript Generation
#=============================================================================

generate_transcript() {
    local debate_dir="$1"
    local topic="$2"
    local transcript_file="$debate_dir/transcript.md"

    log_debug "Generating transcript: $transcript_file"

    # Start transcript
    cat > "$transcript_file" <<EOF
# The Council of Legends - Debate Transcript

**Topic:** $topic
**Date:** $(human_date)

---

EOF

    # Add all rounds in order
    local round=1
    while true; do
        local found_round=false

        # Check if any responses exist for this round
        for ai in claude codex gemini; do
            local response_file="$debate_dir/responses/round_${round}_${ai}.md"
            if [[ -f "$response_file" ]]; then
                found_round=true
                break
            fi
        done

        if [[ "$found_round" == "false" ]]; then
            break
        fi

        # Add round header
        if [[ $round -eq 1 ]]; then
            echo "## Round $round: Opening Statements" >> "$transcript_file"
        else
            echo "## Round $round: Rebuttals" >> "$transcript_file"
        fi
        echo "" >> "$transcript_file"

        # Add each AI's response for this round
        for ai in claude codex gemini; do
            local response_file="$debate_dir/responses/round_${round}_${ai}.md"
            if [[ -f "$response_file" ]]; then
                local ai_name
                ai_name=$(get_ai_name "$ai")
                cat >> "$transcript_file" <<EOF
### $ai_name

$(cat "$response_file")

---

EOF
            fi
        done

        ((round++))
    done

    # Add individual syntheses
    echo "## Final Syntheses" >> "$transcript_file"
    echo "" >> "$transcript_file"

    for ai in claude codex gemini; do
        local synthesis_file="$debate_dir/responses/synthesis_${ai}.md"
        if [[ -f "$synthesis_file" ]]; then
            local ai_name
            ai_name=$(get_ai_name "$ai")
            cat >> "$transcript_file" <<EOF
### ${ai_name}'s Synthesis

$(cat "$synthesis_file")

---

EOF
        fi
    done

    # Add combined final synthesis
    local final_synthesis="$debate_dir/final_synthesis.md"
    if [[ -f "$final_synthesis" ]]; then
        cat >> "$transcript_file" <<EOF
## The Council's Final Verdict

$(cat "$final_synthesis")

---

*Generated by The Council of Legends*
EOF
    fi

    log_debug "Transcript generated successfully"
}

#=============================================================================
# Template Loading
#=============================================================================

# Load a prompt template from the templates directory
# Usage: load_template "category/template_name" [VAR1=value1] [VAR2=value2]
# Template variables use {{VAR_NAME}} syntax
# Returns: The template content with variables substituted
load_template() {
    local template_path="$1"
    shift

    # Find the script directory (works even when sourced)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local templates_dir="$script_dir/templates/prompts"

    # Support both with and without .txt extension
    local full_path="$templates_dir/$template_path"
    if [[ ! -f "$full_path" ]] && [[ ! -f "${full_path}.txt" ]]; then
        log_error "Template not found: $template_path"
        log_debug "Looked in: $templates_dir"
        return 1
    fi

    # Add .txt extension if needed
    if [[ ! -f "$full_path" ]]; then
        full_path="${full_path}.txt"
    fi

    # Read template content
    local content
    content=$(cat "$full_path")

    # Substitute variables passed as arguments (VAR=value format)
    for arg in "$@"; do
        if [[ "$arg" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            # Escape special characters in the replacement string
            var_value=$(printf '%s' "$var_value" | sed 's/[&/\]/\\&/g')
            content=$(echo "$content" | sed "s|{{${var_name}}}|${var_value}|g")
        fi
    done

    echo "$content"
}

# Load template and substitute a single large block (for multi-line content)
# Usage: load_template_with_content "category/template_name" "PLACEHOLDER" "$content"
load_template_with_content() {
    local template_path="$1"
    local placeholder="$2"
    local replacement="$3"

    local template
    template=$(load_template "$template_path") || return 1

    # For multi-line content, we use awk instead of sed
    echo "$template" | awk -v placeholder="{{${placeholder}}}" -v replacement="$replacement" '
    {
        idx = index($0, placeholder)
        if (idx > 0) {
            print substr($0, 1, idx-1) replacement substr($0, idx+length(placeholder))
        } else {
            print
        }
    }'
}

log_debug "Utils loaded (with template support)"
