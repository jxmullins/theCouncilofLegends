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

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
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
