#!/usr/bin/env bash
#
# The Council of Legends - Team Collaboration Mode
# Multi-AI team collaboration for task completion
#
# Usage:
#   ./team.sh "Your task description here"
#   ./team.sh "Build a REST API" --pm codex --mode divide_conquer
#
# Options:
#   --pm AI          Force a specific Project Manager (claude, codex, gemini)
#   --mode MODE      Work mode: pair_programming, consultation, round_robin,
#                    divide_conquer, free_form (default: PM decides)
#   --with-arbiter   Include arbiter as 4th team member
#   --no-arbiter     Exclude arbiter from team
#   --checkpoints    Checkpoint level: all (default), major, none
#   --show-costs     Display estimated token costs during execution
#   --verbose        Enable verbose logging
#   --help           Show this help message
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COUNCIL_ROOT="$SCRIPT_DIR"

#=============================================================================
# Source Libraries
#=============================================================================

source "$COUNCIL_ROOT/lib/utils.sh"
source "$COUNCIL_ROOT/lib/config.sh"
source "$COUNCIL_ROOT/lib/context.sh"
source "$COUNCIL_ROOT/lib/adapters/claude_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/codex_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/gemini_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/groq_adapter.sh"
source "$COUNCIL_ROOT/lib/assessment.sh"
source "$COUNCIL_ROOT/lib/debate.sh"  # Provides invoke_ai function
source "$COUNCIL_ROOT/lib/team.sh"
source "$COUNCIL_ROOT/lib/pm.sh"
source "$COUNCIL_ROOT/lib/work_modes.sh"

#=============================================================================
# Help
#=============================================================================

show_help() {
    printf '%b' "
${PURPLE}╔════════════════════════════════════════════════════╗
║         THE COUNCIL OF LEGENDS                     ║
║     Team Collaboration Mode                        ║
╚════════════════════════════════════════════════════╝${NC}

${BOLD}USAGE${NC}
    ./team.sh \"Your task description\" [OPTIONS]

${BOLD}EXAMPLES${NC}
    ./team.sh \"Build a REST API for user authentication\"
    ./team.sh \"Design a database schema\" --pm codex
    ./team.sh \"Review this PR for security\" --mode consultation
    ./team.sh \"Quick code review\" --with-arbiter
    ./team.sh \"Complex architecture\" --checkpoints major

${BOLD}OPTIONS${NC}
    --pm AI          Force a specific Project Manager
                     Options: claude, codex, gemini
                     Default: Selected based on task analysis

    --mode MODE      Override PM's work mode selection
                     - pair_programming: Two AIs collaborate on same artifact
                     - consultation: Lead asks others for specific input
                     - round_robin: Sequential contributions
                     - divide_conquer: Split task, parallel work, merge
                     - free_form: Open collaboration, PM moderates

    --with-arbiter   Include arbiter (Groq/Llama) as 4th team member
                     Requires GROQ_API_KEY and arbiter questionnaire

    --no-arbiter     Explicitly exclude arbiter from team

    --checkpoints LEVEL
                     Control user approval checkpoints
                     - all: Every PM-defined milestone (default)
                     - major: Plan approval + final delivery only
                     - none: Trust PM fully (no checkpoints)

    --show-costs     Display estimated token costs during execution

    --output-dir DIR Create standalone project in specified directory
                     Example: --output-dir ~/devFiles/my-project
                     If not specified, prompts interactively after plan approval

    --add-dir DIR    Grant AI team access to external directories
                     Example: --add-dir ~/devFiles/other-project
                     Can be specified multiple times for multiple directories

    --verbose        Enable verbose/debug logging

    --help           Show this help message

${BOLD}TEAM MEMBERS${NC}
    ${CYAN}Claude${NC}  - Anthropic's Claude (reasoning, safety, ethics)
    ${GREEN}Codex${NC}   - OpenAI's model (code generation, technical)
    ${BLUE}Gemini${NC}  - Google's Gemini (multimodal, research)
    ${YELLOW}Arbiter${NC} - Groq/Llama (optional 4th member, fast reviews)

${BOLD}WORKFLOW${NC}
    1. Task intake: Parse description and options
    2. PM selection: Based on task type + questionnaire baselines
    3. Planning: PM creates execution plan with milestones
    4. User approval: Review and approve plan
    5. Execution: PM orchestrates team through work mode
    6. Checkpoints: User input at milestones (if enabled)
    7. Delivery: Final synthesis and artifacts

${BOLD}REQUIREMENTS${NC}
    - Claude CLI, Codex CLI, and Gemini CLI installed
    - Questionnaires completed (run ./assess.sh first)
    - GROQ_API_KEY for arbiter features

"
}

#=============================================================================
# Argument Parsing
#=============================================================================

parse_args() {
    TASK=""
    FORCE_PM=""
    WORK_MODE=""
    INCLUDE_ARBITER=""  # Empty means PM decides
    CHECKPOINT_LEVEL="all"
    SHOW_COSTS=false
    OUTPUT_DIR=""  # External project directory
    ADD_DIRS=""    # Additional directories for AI access

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --pm)
                FORCE_PM="$2"
                shift 2
                ;;
            --mode)
                WORK_MODE="$2"
                shift 2
                ;;
            --with-arbiter)
                INCLUDE_ARBITER="true"
                shift
                ;;
            --no-arbiter)
                INCLUDE_ARBITER="false"
                shift
                ;;
            --checkpoints)
                CHECKPOINT_LEVEL="$2"
                shift 2
                ;;
            --show-costs)
                SHOW_COSTS=true
                shift
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --add-dir)
                # Accumulate multiple directories (space-separated)
                if [[ -n "$ADD_DIRS" ]]; then
                    ADD_DIRS="$ADD_DIRS $2"
                else
                    ADD_DIRS="$2"
                fi
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$TASK" ]]; then
                    TASK="$1"
                else
                    log_error "Multiple tasks provided. Please quote your task description."
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate task
    if [[ -z "$TASK" ]]; then
        log_error "No task provided"
        echo ""
        echo "Usage: ./team.sh \"Your task description\""
        echo "Use --help for more options"
        exit 1
    fi

    # Validate PM if specified
    if [[ -n "$FORCE_PM" ]]; then
        case "$FORCE_PM" in
            claude|codex|gemini)
                ;;
            *)
                log_error "Invalid PM: $FORCE_PM"
                echo "Valid options: claude, codex, gemini"
                exit 1
                ;;
        esac
    fi

    # Validate work mode if specified
    if [[ -n "$WORK_MODE" ]]; then
        case "$WORK_MODE" in
            pair_programming|consultation|round_robin|divide_conquer|free_form)
                ;;
            *)
                log_error "Invalid work mode: $WORK_MODE"
                echo "Valid modes: pair_programming, consultation, round_robin, divide_conquer, free_form"
                exit 1
                ;;
        esac
    fi

    # Validate checkpoint level
    case "$CHECKPOINT_LEVEL" in
        all|major|none)
            ;;
        *)
            log_error "Invalid checkpoint level: $CHECKPOINT_LEVEL"
            echo "Valid levels: all, major, none"
            exit 1
            ;;
    esac
}

#=============================================================================
# Main
#=============================================================================

main() {
    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Display banner
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}THE COUNCIL OF LEGENDS${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${WHITE}Team Collaboration Mode${NC}                       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${CYAN}Claude${NC} ${WHITE}•${NC} ${GREEN}Codex${NC} ${WHITE}•${NC} ${BLUE}Gemini${NC}                       ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Export globals for team module
    export TEAM_TASK="$TASK"
    export TEAM_FORCE_PM="$FORCE_PM"
    export TEAM_WORK_MODE="$WORK_MODE"
    export TEAM_INCLUDE_ARBITER="$INCLUDE_ARBITER"
    export TEAM_CHECKPOINT_LEVEL="$CHECKPOINT_LEVEL"
    export TEAM_SHOW_COSTS="$SHOW_COSTS"
    export TEAM_OUTPUT_DIR="$OUTPUT_DIR"
    export TEAM_ADD_DIRS="$ADD_DIRS"

    # Run the team workflow
    run_team_workflow "$TASK"
}

main "$@"
