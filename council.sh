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
#   --personas   Set personas (format: claude:philosopher,codex:hacker,gemini:scientist)
#   --verbose    Enable verbose logging
#   --list-personas  Show available personas
#   --help       Show this help message
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
source "$COUNCIL_ROOT/lib/llm_manager.sh"  # Dynamic model registry (must be before adapters)
source "$COUNCIL_ROOT/lib/context.sh"

# Source adapters (core providers)
source "$COUNCIL_ROOT/lib/adapters/claude_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/codex_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/gemini_adapter.sh"
source "$COUNCIL_ROOT/lib/adapters/groq_adapter.sh"

# Source optional adapters if they exist (local LLMs, custom endpoints)
[[ -f "$COUNCIL_ROOT/lib/adapters/ollama_adapter.sh" ]] && \
    source "$COUNCIL_ROOT/lib/adapters/ollama_adapter.sh"
[[ -f "$COUNCIL_ROOT/lib/adapters/lmstudio_adapter.sh" ]] && \
    source "$COUNCIL_ROOT/lib/adapters/lmstudio_adapter.sh"
[[ -f "$COUNCIL_ROOT/lib/adapters/openai_compatible_adapter.sh" ]] && \
    source "$COUNCIL_ROOT/lib/adapters/openai_compatible_adapter.sh"

# Source dispatcher (routes invoke_ai to correct adapter)
source "$COUNCIL_ROOT/lib/dispatcher.sh"

source "$COUNCIL_ROOT/lib/debate.sh"
source "$COUNCIL_ROOT/lib/assessment.sh"
source "$COUNCIL_ROOT/lib/scotus.sh"
source "$COUNCIL_ROOT/lib/budget.sh"

# Initialize LLM registry (creates config/llms.toon if missing)
init_llm_registry

#=============================================================================
# Help
#=============================================================================

show_help() {
    printf '%b' "
${PURPLE}╔════════════════════════════════════════════════════╗
║         THE COUNCIL OF LEGENDS                     ║
║     Multi-AI Debate System                         ║
╚════════════════════════════════════════════════════╝${NC}

${BOLD}USAGE${NC}
    ./council.sh \"Your topic or question\" [OPTIONS]
    ./council.sh models <command>           # Manage AI models

${BOLD}SUBCOMMANDS${NC}
    models list          List all registered AI models
    models add           Add a new model (interactive or direct)
    models remove <id>   Remove a model from registry
    models enable <id>   Enable model as council member
    models disable <id>  Disable model as council member
    models test [id]     Test model availability
    models info <id>     Show model details

${BOLD}EXAMPLES${NC}
    ./council.sh \"What is the best programming language for beginners?\"
    ./council.sh \"Should we use microservices or monolith?\" --mode adversarial
    ./council.sh \"How to improve code quality?\" --rounds 4 --verbose
    ./council.sh \"AI ethics\" --personas claude:philosopher,gemini:futurist

${BOLD}OPTIONS${NC}
    --mode MODE      Debate mode (default: collaborative)
                     - collaborative: AIs work together to find consensus
                     - adversarial: AIs argue different positions
                     - exploratory: AIs explore all angles without judgment
                     - scotus: Judicial mode with formal opinions (majority/concurrence/dissent)

    --rounds N       Number of debate rounds (default: 3)
                     Minimum: 2, Maximum: 10

    --verbose        Enable verbose/debug logging

    --config FILE    Use custom configuration file

    --chief-justice AI   Force a specific Chief Justice (claude, codex, gemini)
                         If not specified:
                         - Uses arbiter selection if GROQ_API_KEY is set
                         - Falls back to first council member otherwise

    --no-cj          Skip Chief Justice selection (no moderator)

    --personas SPEC  Set personas for council members
                     Format: ai:persona,ai:persona,...
                     Example: --personas claude:philosopher,codex:hacker
                     Only specified AIs are changed; others use default

    --dynamic-personas  Enable dynamic persona switching between rounds
                        Arbiter suggests persona changes based on debate needs
                        Requires GROQ_API_KEY for arbiter

    --list-personas  Show all available personas and exit

    --max-cost N     Maximum budget in dollars (e.g., --max-cost 0.50)
                     Debate stops if budget exceeded

    --profile PROF   Budget profile: frugal, balanced (default), premium
                     Controls which model variants are used

    --show-costs     Display cost summary at end of debate

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

"
}

#=============================================================================
# Show Available Personas
#=============================================================================

show_personas() {
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}AVAILABLE PERSONAS${NC}                            ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}Any persona can be assigned to any AI member.${NC}"
    echo ""

    # Use list_all_personas from config.sh (handles both TOON and JSON)
    while IFS='|' read -r persona_id name description; do
        if [[ -n "$persona_id" ]]; then
            local persona_file author version tags
            persona_file=$(get_persona_file "$persona_id")
            author=$(read_persona_field "$persona_file" "author")
            version=$(read_persona_field "$persona_file" "version")
            tags=$(get_persona_tags "$persona_id")

            printf "  ${BOLD}%-18s${NC} %s\n" "$persona_id" "$description"
            printf "    ${WHITE}v%s by %s${NC}" "$version" "${author:-Unknown}"
            if [[ -n "$tags" ]]; then
                printf " ${CYAN}[%s]${NC}" "$tags"
            fi
            echo ""
        fi
    done < <(list_all_personas)

    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  ./council.sh \"topic\" --personas claude:philosopher,codex:hacker"
    echo "  ./council.sh \"topic\" --personas claude:scientist,codex:scientist,gemini:scientist"
    echo ""
    echo -e "${WHITE}Format: ai:persona,ai:persona,...${NC}"
    echo -e "${WHITE}AIs: claude, codex, gemini${NC}"
    echo ""
}

#=============================================================================
# Parse Persona Specification
#=============================================================================

parse_personas() {
    local spec="$1"

    # Split by comma
    IFS=',' read -ra pairs <<< "$spec"
    for pair in "${pairs[@]}"; do
        # Split by colon
        local ai="${pair%%:*}"
        local persona="${pair##*:}"

        # Validate AI name
        case "$ai" in
            claude|codex|gemini)
                ;;
            *)
                log_error "Invalid AI in persona spec: $ai"
                echo "Valid AIs: claude, codex, gemini"
                exit 1
                ;;
        esac

        # Validate persona exists (universal catalog - persona only)
        if ! validate_persona "$persona"; then
            log_error "Unknown persona: $persona"
            echo "Run --list-personas to see available options"
            exit 1
        fi

        # Set the persona
        set_persona "$ai" "$persona"
        log_debug "Set $ai persona to: $persona"
    done
}

#=============================================================================
# Argument Parsing
#=============================================================================

parse_args() {
    TOPIC=""
    MODE="collaborative"
    ROUNDS="$DEFAULT_ROUNDS"
    CONFIG_FILE=""
    CHIEF_JUSTICE=""
    SKIP_CJ=false
    PERSONAS_SPEC=""
    BUDGET_MAX_COST="${BUDGET_MAX_COST:-0}"
    BUDGET_PROFILE="${BUDGET_PROFILE:-balanced}"
    SHOW_COSTS=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --list-personas)
                show_personas
                exit 0
                ;;
            --mode)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --mode requires a value"
                    exit 1
                fi
                MODE="$2"
                shift 2
                ;;
            --rounds)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --rounds requires a value"
                    exit 1
                fi
                ROUNDS="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --config)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --config requires a value"
                    exit 1
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            --chief-justice|--cj)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --chief-justice requires a value"
                    exit 1
                fi
                CHIEF_JUSTICE="$2"
                shift 2
                ;;
            --no-cj)
                SKIP_CJ=true
                shift
                ;;
            --personas)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --personas requires a value"
                    exit 1
                fi
                PERSONAS_SPEC="$2"
                shift 2
                ;;
            --dynamic-personas)
                enable_dynamic_personas
                shift
                ;;
            --max-cost)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --max-cost requires a value"
                    exit 1
                fi
                BUDGET_MAX_COST="$2"
                shift 2
                ;;
            --profile)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option --profile requires a value"
                    exit 1
                fi
                BUDGET_PROFILE="$2"
                shift 2
                ;;
            --show-costs)
                SHOW_COSTS=true
                shift
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
        collaborative|adversarial|exploratory|scotus)
            ;;
        *)
            log_error "Invalid mode: $MODE"
            echo "Valid modes: collaborative, adversarial, exploratory, scotus"
            exit 1
            ;;
    esac

    # Validate rounds
    if ! [[ "$ROUNDS" =~ ^[0-9]+$ ]] || [[ "$ROUNDS" -lt 2 ]] || [[ "$ROUNDS" -gt 10 ]]; then
        log_error "Invalid rounds: $ROUNDS (must be 2-10)"
        exit 1
    fi

    # Validate chief justice if specified
    if [[ -n "$CHIEF_JUSTICE" ]]; then
        case "$CHIEF_JUSTICE" in
            claude|codex|gemini)
                ;;
            *)
                log_error "Invalid chief justice: $CHIEF_JUSTICE"
                echo "Valid options: claude, codex, gemini"
                exit 1
                ;;
        esac
    fi
}

#=============================================================================
# Main
#=============================================================================

main() {
    # Handle subcommands before full initialization
    # This allows 'models' command to work without loading full debate stack
    case "${1:-}" in
        models|llm)
            shift
            source "$COUNCIL_ROOT/lib/cli_commands.sh"
            handle_models_command "$@"
            exit $?
            ;;
    esac

    # Pre-parse for --config flag (needs to happen before full parse)
    local config_file_arg=""
    for arg in "$@"; do
        if [[ "$arg" == "--config" ]]; then
            shift_next=true
            continue
        fi
        if [[ "${shift_next:-}" == "true" ]]; then
            config_file_arg="$arg"
            break
        fi
    done

    # Validate system dependencies before anything else
    if ! validate_system_dependencies; then
        exit 1
    fi

    # Load configuration FIRST (so CLI args can override)
    if [[ -n "$config_file_arg" ]]; then
        load_config "$config_file_arg"
    else
        load_config
    fi

    # Parse arguments (CLI args will override config values)
    parse_args "$@"

    # Parse persona specifications if provided
    if [[ -n "$PERSONAS_SPEC" ]]; then
        parse_personas "$PERSONAS_SPEC"
    fi

    # Validate council size (minimum 2 members required for debate)
    if ! validate_council_size 2; then
        echo ""
        echo -e "${YELLOW}Tip: Use './council.sh models list' to see available models${NC}"
        echo -e "${YELLOW}     Use './council.sh models enable <id>' to add council members${NC}"
        exit 1
    fi

    # Display banner
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     ${BOLD}THE COUNCIL OF LEGENDS${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ${CYAN}Claude${NC} ${WHITE}•${NC} ${GREEN}Codex${NC} ${WHITE}•${NC} ${BLUE}Gemini${NC}                       ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Display active personas if any non-default
    local has_custom_persona=false
    local members
    mapfile -t members < <(get_council_members)
    for ai in "${members[@]}"; do
        if [[ "$(get_persona "$ai")" != "default" ]]; then
            has_custom_persona=true
            break
        fi
    done

    if [[ "$has_custom_persona" == "true" ]]; then
        echo -e "${BOLD}Active Personas:${NC}"
        local members
        mapfile -t members < <(get_council_members)
        for ai in "${members[@]}"; do
            local persona
            persona=$(get_persona "$ai")
            local display_name
            display_name=$(get_persona_display_name "$ai" "$persona")
            local ai_color
            ai_color=$(get_ai_color "$ai")
            echo -e "  ${ai_color}${display_name}${NC}"
        done
        echo ""
    fi

    # Select Chief Justice
    local selected_cj=""

    if [[ "$SKIP_CJ" == "true" ]]; then
        log_info "Chief Justice selection skipped"
    elif [[ -n "$CHIEF_JUSTICE" ]]; then
        # Use manually specified CJ
        selected_cj="$CHIEF_JUSTICE"
        log_info "Chief Justice (manual): $(get_ai_name "$selected_cj")"
    elif [[ -n "${GROQ_API_KEY:-}" ]]; then
        # Try to use arbiter selection
        header "Chief Justice Selection"

        # Find most recent baseline
        local baseline_file=""
        local latest_dir
        latest_dir=$(ls -dt "$COUNCIL_ROOT/assessments/"*/ 2>/dev/null | head -1)
        if [[ -n "$latest_dir" ]] && [[ -f "$latest_dir/baseline_analysis.json" ]]; then
            baseline_file="$latest_dir/baseline_analysis.json"
        fi

        if [[ -f "$baseline_file" ]]; then
            log_info "Using baseline from: $latest_dir"
            local cj_output_dir="$COUNCIL_ROOT/cj_selections/$(date +%Y%m%d_%H%M%S)"

            # Run CJ selection (logs go to stderr, result to stdout)
            selected_cj=$(select_chief_justice "$TOPIC" "$baseline_file" "$cj_output_dir") || true

            if [[ -n "$selected_cj" ]]; then
                log_success "Chief Justice selected: $(get_ai_name "$selected_cj")"
            else
                log_warn "CJ selection failed, using default"
                selected_cj="${COUNCIL_MEMBERS[0]}"
            fi
        else
            log_warn "No baseline assessment found. Run './assess.sh' to enable smart CJ selection."
            log_info "Using default Chief Justice: $(get_ai_name "${COUNCIL_MEMBERS[0]}")"
            selected_cj="${COUNCIL_MEMBERS[0]}"
        fi
    else
        # No GROQ_API_KEY, use default
        selected_cj="${COUNCIL_MEMBERS[0]}"
        log_info "Chief Justice (default): $(get_ai_name "$selected_cj")"
    fi

    # Export CJ for debate module
    export CHIEF_JUSTICE="$selected_cj"

    # Run the debate (route to SCOTUS mode if selected)
    if [[ "$MODE" == "scotus" ]]; then
        # SCOTUS mode requires a Chief Justice - enforce it
        if [[ -z "$selected_cj" ]]; then
            log_warn "SCOTUS mode requires a Chief Justice. Using default."
            selected_cj="${COUNCIL_MEMBERS[0]}"
            export CHIEF_JUSTICE="$selected_cj"
            log_info "Chief Justice (default for SCOTUS): $(get_ai_name "$selected_cj")"
        fi
        run_scotus_debate "$TOPIC" "$ROUNDS"
    else
        run_debate "$TOPIC" "$MODE" "$ROUNDS"
    fi
}

main "$@"
