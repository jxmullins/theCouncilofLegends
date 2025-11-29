#!/usr/bin/env bash
#
# The Council of Legends - Main Entry Point
# A multi-AI debate system featuring Claude, Codex, and Gemini
#
# Usage:
#   ./council.sh "Your topic or question here"
#   ./council.sh "Topic" --mode adversarial --rounds 4
#
# Options:
#   --mode       Debate mode: collaborative (default), adversarial, exploratory
#   --rounds     Number of rounds (default: 3)
#   --verbose    Enable verbose logging
#   --help       Show this help message
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COUNCIL_ROOT="$SCRIPT_DIR"

#=============================================================================
# Source Libraries
#=============================================================================

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/context.sh"
source "$SCRIPT_DIR/lib/adapters/claude_adapter.sh"
source "$SCRIPT_DIR/lib/adapters/codex_adapter.sh"
source "$SCRIPT_DIR/lib/adapters/gemini_adapter.sh"
source "$SCRIPT_DIR/lib/debate.sh"

#=============================================================================
# Help
#=============================================================================

show_help() {
    cat <<EOF
${PURPLE}╔════════════════════════════════════════════════════╗
║         THE COUNCIL OF LEGENDS                     ║
║     Multi-AI Debate System                         ║
╚════════════════════════════════════════════════════╝${NC}

${BOLD}USAGE${NC}
    ./council.sh "Your topic or question" [OPTIONS]

${BOLD}EXAMPLES${NC}
    ./council.sh "What is the best programming language for beginners?"
    ./council.sh "Should we use microservices or monolith?" --mode adversarial
    ./council.sh "How to improve code quality?" --rounds 4 --verbose

${BOLD}OPTIONS${NC}
    --mode MODE      Debate mode (default: collaborative)
                     - collaborative: AIs work together to find consensus
                     - adversarial: AIs argue different positions
                     - exploratory: AIs explore all angles without judgment

    --rounds N       Number of debate rounds (default: 3)
                     Minimum: 2, Maximum: 10

    --verbose        Enable verbose/debug logging

    --config FILE    Use custom configuration file

    --help           Show this help message

${BOLD}REQUIREMENTS${NC}
    The following CLI tools must be installed and authenticated:
    - claude  (Claude Code CLI from Anthropic)
    - codex   (Codex CLI from OpenAI)
    - gemini  (Gemini CLI from Google)

    Run ./test_adapters.sh to verify your setup.

${BOLD}OUTPUT${NC}
    Debates are saved to ./debates/ with:
    - transcript.md     Full debate transcript
    - final_synthesis.md Combined conclusions
    - metadata.json     Debate metadata

EOF
}

#=============================================================================
# Argument Parsing
#=============================================================================

parse_args() {
    TOPIC=""
    MODE="collaborative"
    ROUNDS="$DEFAULT_ROUNDS"
    CONFIG_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --rounds)
                ROUNDS="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$TOPIC" ]]; then
                    TOPIC="$1"
                else
                    log_error "Multiple topics provided. Please quote your topic."
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate topic
    if [[ -z "$TOPIC" ]]; then
        log_error "No topic provided"
        echo ""
        echo "Usage: ./council.sh \"Your topic or question\""
        echo "Use --help for more options"
        exit 1
    fi

    # Validate mode
    case "$MODE" in
        collaborative|adversarial|exploratory)
            ;;
        *)
            log_error "Invalid mode: $MODE"
            echo "Valid modes: collaborative, adversarial, exploratory"
            exit 1
            ;;
    esac

    # Validate rounds
    if ! [[ "$ROUNDS" =~ ^[0-9]+$ ]] || [[ "$ROUNDS" -lt 2 ]] || [[ "$ROUNDS" -gt 10 ]]; then
        log_error "Invalid rounds: $ROUNDS (must be 2-10)"
        exit 1
    fi
}

#=============================================================================
# Main
#=============================================================================

main() {
    # Parse arguments
    parse_args "$@"

    # Load configuration
    if [[ -n "$CONFIG_FILE" ]]; then
        load_config "$CONFIG_FILE"
    else
        load_config
    fi

    # Display banner
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}THE COUNCIL OF LEGENDS${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${CYAN}Claude${NC} ${WHITE}•${NC} ${GREEN}Codex${NC} ${WHITE}•${NC} ${BLUE}Gemini${NC}                       ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run the debate
    run_debate "$TOPIC" "$MODE" "$ROUNDS"
}

main "$@"
