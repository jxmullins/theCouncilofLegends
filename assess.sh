#!/usr/bin/env bash
#
# The Council of Legends - Assessment Runner
# Run self-assessments and peer reviews for Chief Justice selection
#
# Usage:
#   ./assess.sh                    Run full assessment cycle
#   ./assess.sh --questionnaire    Run only self-assessments
#   ./assess.sh --peer-review DIR  Run peer reviews on existing assessments
#   ./assess.sh --verbose          Enable debug output
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
source "$SCRIPT_DIR/lib/assessment.sh"

# Assessment prompts are larger, need longer timeout
TURN_TIMEOUT="${TURN_TIMEOUT:-300}"
export TURN_TIMEOUT

#=============================================================================
# Help
#=============================================================================

show_help() {
    cat <<EOF
${PURPLE}╔════════════════════════════════════════════════════╗
║     THE COUNCIL OF LEGENDS                         ║
║     Assessment & Chief Justice Selection           ║
╚════════════════════════════════════════════════════╝${NC}

${BOLD}USAGE${NC}
    ./assess.sh [OPTIONS]

${BOLD}EXAMPLES${NC}
    ./assess.sh                           # Full assessment cycle
    ./assess.sh --verbose                 # With debug output
    ./assess.sh --questionnaire           # Self-assessment only
    ./assess.sh --peer-review DIR         # Peer review existing assessments

${BOLD}OPTIONS${NC}
    --questionnaire      Run only self-assessment questionnaires
                         (skip peer reviews)

    --peer-review DIR    Run peer reviews on an existing assessment
                         DIR should be the assessment directory

    --analyze DIR        Run arbiter baseline analysis on existing assessment
                         Requires GROQ_API_KEY environment variable

    --select-cj TOPIC    Select Chief Justice for a debate topic
                         Uses the most recent baseline analysis
                         Requires GROQ_API_KEY environment variable

    --baseline DIR       Specify baseline analysis directory for --select-cj
                         (default: most recent in ./assessments/)

    --trigger TYPE       Assessment trigger type:
                         - user_initiated (default)
                         - model_change
                         - scheduled

    --verbose, -v        Enable verbose/debug logging

    --help, -h           Show this help message

${BOLD}ASSESSMENT CYCLE${NC}
    1. Self-Assessment: Each AI completes the capability questionnaire
    2. Anonymization: Responses are anonymized (AI-A, AI-B, AI-C)
    3. Peer Review: Each AI reviews the other two (blind)
    4. De-anonymization: Results are revealed for analysis
    5. Arbiter Analysis: 4th AI generates baseline scores (TODO)

${BOLD}OUTPUT${NC}
    Assessments are saved to ./assessments/<timestamp>/ with:
    - self_assessments/     Each AI's questionnaire responses
    - anonymized/           Anonymized versions for peer review
    - peer_reviews/         Each AI's review of peers
    - revealed/             De-anonymized final results
    - anonymization_map.json  Secret mapping (AI-A = claude, etc.)
    - metadata.json         Assessment metadata and status

EOF
}

#=============================================================================
# Argument Parsing
#=============================================================================

MODE="full"
TRIGGER="user_initiated"
ASSESSMENT_DIR=""
BASELINE_DIR=""
CJ_TOPIC=""
VERBOSE="${VERBOSE:-false}"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --questionnaire)
                MODE="questionnaire"
                shift
                ;;
            --peer-review)
                MODE="peer-review"
                ASSESSMENT_DIR="$2"
                shift 2
                ;;
            --analyze)
                MODE="analyze"
                ASSESSMENT_DIR="$2"
                shift 2
                ;;
            --select-cj)
                MODE="select-cj"
                CJ_TOPIC="$2"
                shift 2
                ;;
            --baseline)
                BASELINE_DIR="$2"
                shift 2
                ;;
            --trigger)
                TRIGGER="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                exit 1
                ;;
        esac
    done

    # Validate trigger
    case "$TRIGGER" in
        user_initiated|model_change|scheduled)
            ;;
        *)
            log_error "Invalid trigger: $TRIGGER"
            echo "Valid triggers: user_initiated, model_change, scheduled"
            exit 1
            ;;
    esac

    # Validate peer-review mode has directory
    if [[ "$MODE" == "peer-review" ]] && [[ -z "$ASSESSMENT_DIR" ]]; then
        log_error "Peer review mode requires an assessment directory"
        exit 1
    fi

    # Validate analyze mode has directory and API key
    if [[ "$MODE" == "analyze" ]]; then
        if [[ -z "$ASSESSMENT_DIR" ]]; then
            log_error "Analyze mode requires an assessment directory"
            exit 1
        fi
        if [[ -z "${GROQ_API_KEY:-}" ]]; then
            log_error "GROQ_API_KEY environment variable required for arbiter analysis"
            exit 1
        fi
    fi

    # Validate select-cj mode
    if [[ "$MODE" == "select-cj" ]]; then
        if [[ -z "$CJ_TOPIC" ]]; then
            log_error "Select CJ mode requires a topic"
            exit 1
        fi
        if [[ -z "${GROQ_API_KEY:-}" ]]; then
            log_error "GROQ_API_KEY environment variable required for CJ selection"
            exit 1
        fi
    fi
}

#=============================================================================
# Main
#=============================================================================

main() {
    parse_args "$@"

    # Load configuration
    load_config

    # Display banner
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}THE COUNCIL OF LEGENDS${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${YELLOW}Assessment & Chief Justice Selection${NC}         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Prefer TOON, fall back to JSON
    local questionnaire_file
    if [[ -f "$COUNCIL_ROOT/config/questionnaire_v1.toon" ]]; then
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.toon"
    else
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.json"
    fi

    case "$MODE" in
        full)
            # Run complete assessment cycle
            run_full_assessment "$COUNCIL_ROOT" "$TRIGGER" "" "$questionnaire_file"
            ;;
        questionnaire)
            # Run only self-assessments
            header "Self-Assessment Phase"
            local assessment_dir
            assessment_dir=$(init_assessment_cycle "$COUNCIL_ROOT" "$TRIGGER" "questionnaire-only")
            run_all_questionnaires "$assessment_dir" "$questionnaire_file"
            log_success "Self-assessments complete: $assessment_dir"
            ;;
        peer-review)
            # Run peer reviews on existing assessment
            if [[ ! -d "$ASSESSMENT_DIR" ]]; then
                log_error "Assessment directory not found: $ASSESSMENT_DIR"
                exit 1
            fi
            header "Peer Review Phase"
            run_all_peer_reviews "$ASSESSMENT_DIR"
            log_success "Peer reviews complete"
            ;;
        analyze)
            # Run arbiter baseline analysis on existing assessment
            if [[ ! -d "$ASSESSMENT_DIR" ]]; then
                log_error "Assessment directory not found: $ASSESSMENT_DIR"
                exit 1
            fi
            header "Arbiter Baseline Analysis"
            run_baseline_analysis "$ASSESSMENT_DIR"
            ;;
        select-cj)
            # Select Chief Justice for a debate topic
            header "Chief Justice Selection"

            # Find baseline file
            local baseline_file=""
            if [[ -n "$BASELINE_DIR" ]]; then
                baseline_file="$BASELINE_DIR/baseline_analysis.json"
            else
                # Find most recent assessment with baseline
                local latest_dir
                latest_dir=$(ls -dt "$COUNCIL_ROOT/assessments/"*/ 2>/dev/null | head -1)
                if [[ -n "$latest_dir" ]] && [[ -f "$latest_dir/baseline_analysis.json" ]]; then
                    baseline_file="$latest_dir/baseline_analysis.json"
                    log_info "Using baseline from: $latest_dir"
                fi
            fi

            if [[ ! -f "$baseline_file" ]]; then
                log_error "No baseline analysis found. Run './assess.sh' first to generate baseline scores."
                exit 1
            fi

            # Create output directory for this selection
            local cj_output_dir="$COUNCIL_ROOT/cj_selections/$(date +%Y%m%d_%H%M%S)"

            # Run selection
            local recommended_cj
            recommended_cj=$(select_chief_justice "$CJ_TOPIC" "$baseline_file" "$cj_output_dir")

            if [[ -n "$recommended_cj" ]]; then
                echo ""
                log_success "Recommended Chief Justice: $(get_ai_name "$recommended_cj")"
                echo "Selection details saved to: $cj_output_dir"
            fi
            ;;
    esac

    echo ""
    log_info "Assessment cycle finished"
}

main "$@"
