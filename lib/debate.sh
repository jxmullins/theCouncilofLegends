#!/usr/bin/env bash
#
# The Council of Legends - Debate Engine
# Core orchestration logic for running debates
#

#=============================================================================
# AI Invocation Dispatcher
#=============================================================================

invoke_ai() {
    local ai="$1"
    local prompt="$2"
    local output_file="$3"
    local system_prompt="${4:-}"

    case "$ai" in
        claude)
            invoke_claude "$prompt" "$output_file" "$system_prompt"
            ;;
        codex)
            invoke_codex "$prompt" "$output_file" "$system_prompt"
            ;;
        gemini)
            invoke_gemini "$prompt" "$output_file" "$system_prompt"
            ;;
        *)
            log_error "Unknown AI: $ai"
            return 1
            ;;
    esac
}

#=============================================================================
# Error Handling
#=============================================================================

handle_ai_failure() {
    local ai="$1"
    local phase="$2"
    local output_file="$3"

    log_error "$ai failed during $phase"

    if [[ "${RETRY_ON_FAILURE:-true}" == "true" ]]; then
        for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
            log_warn "Retry attempt $attempt/$MAX_RETRIES for $ai..."
            sleep "${RETRY_DELAY:-5}"

            if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
                log_success "$ai recovered on retry $attempt"
                return 0
            fi
        done
    fi

    # Graceful degradation
    log_warn "Continuing debate without $ai for this round"
    echo "[$(get_ai_name "$ai") was unable to respond in this round]" > "$output_file"
    return 1
}

#=============================================================================
# Opening Round
#=============================================================================

run_opening_round() {
    local debate_dir="$1"
    local topic="$2"
    local mode="$3"

    log_info "Round 1: Opening Statements"
    header "Round 1: Opening Statements"

    local prompt
    prompt=$(build_opening_prompt "$topic" "$mode")

    for ai in claude codex gemini; do
        local system_prompt
        system_prompt=$(load_persona "$ai")

        ai_header "$ai" "Opening Statement"

        local output_file="$debate_dir/responses/round_1_${ai}.md"

        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$ai" "$output_file"
        else
            handle_ai_failure "$ai" "opening" "$output_file"
        fi
    done
}

#=============================================================================
# Rebuttal Rounds
#=============================================================================

run_rebuttal_round() {
    local debate_dir="$1"
    local topic="$2"
    local mode="$3"
    local round="$4"

    log_info "Round $round: Rebuttals"
    header "Round $round: Rebuttals"

    for ai in claude codex gemini; do
        local system_prompt
        system_prompt=$(load_persona "$ai")

        ai_header "$ai" "Round $round Rebuttal"

        local prompt
        prompt=$(build_rebuttal_prompt "$topic" "$mode" "$round" "$ai" "$debate_dir")

        local output_file="$debate_dir/responses/round_${round}_${ai}.md"

        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$ai" "$output_file"
        else
            handle_ai_failure "$ai" "round $round" "$output_file"
        fi
    done
}

#=============================================================================
# Synthesis Round (Each AI provides their synthesis)
#=============================================================================

run_synthesis_round() {
    local debate_dir="$1"
    local topic="$2"
    local mode="$3"

    log_info "Final Round: Individual Syntheses"
    header "Final Round: Synthesis"

    for ai in claude codex gemini; do
        local system_prompt
        system_prompt=$(load_persona "$ai")

        ai_header "$ai" "Final Synthesis"

        local prompt
        prompt=$(build_synthesis_prompt "$topic" "$mode" "$debate_dir" "$ai")

        local output_file="$debate_dir/responses/synthesis_${ai}.md"

        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$ai" "$output_file"
        else
            handle_ai_failure "$ai" "synthesis" "$output_file"
        fi
    done
}

#=============================================================================
# Combined Final Synthesis
#=============================================================================

run_combined_synthesis() {
    local debate_dir="$1"
    local topic="$2"

    log_info "Generating Combined Final Synthesis"
    header "The Council's Final Verdict"

    local prompt
    prompt=$(build_combined_synthesis_prompt "$topic" "$debate_dir")

    # Use Claude for the final combined synthesis
    local system_prompt="You are synthesizing the final conclusions of The Council of Legends debate. Be balanced, fair, and actionable."

    local output_file="$debate_dir/final_synthesis.md"

    ai_header "council" "Final Verdict"

    if invoke_ai "claude" "$prompt" "$output_file" "$system_prompt"; then
        display_synthesis "$output_file"
    else
        log_error "Failed to generate combined synthesis"
        # Fallback: combine the individual syntheses
        cat > "$output_file" <<EOF
# Combined Synthesis

The individual AI syntheses are available in the debate transcript.
Please review each perspective:
- Claude's synthesis
- Codex's synthesis
- Gemini's synthesis
EOF
    fi
}

#=============================================================================
# Main Debate Runner
#=============================================================================

run_debate() {
    local topic="$1"
    local mode="${2:-collaborative}"
    local rounds="${3:-$DEFAULT_ROUNDS}"

    # Validate topic
    if [[ -z "$topic" ]]; then
        log_error "Topic is required"
        return 1
    fi

    # Validate CLIs
    if ! validate_cli_availability; then
        return 1
    fi

    # Setup
    local debate_dir
    debate_dir=$(create_debate_directory "$topic")
    save_metadata "$debate_dir" "$topic" "$mode" "$rounds"

    # Display intro
    header "THE COUNCIL OF LEGENDS"
    echo -e "${WHITE}Topic:${NC} $topic"
    echo -e "${WHITE}Mode:${NC} $mode"
    echo -e "${WHITE}Rounds:${NC} $rounds"
    echo ""

    # Round 1: Opening Statements
    run_opening_round "$debate_dir" "$topic" "$mode"

    # Rounds 2-N: Rebuttals
    for ((round=2; round<=rounds; round++)); do
        run_rebuttal_round "$debate_dir" "$topic" "$mode" "$round"
    done

    # Final: Individual Syntheses
    run_synthesis_round "$debate_dir" "$topic" "$mode"

    # Combined Final Synthesis
    run_combined_synthesis "$debate_dir" "$topic"

    # Generate transcript
    generate_transcript "$debate_dir" "$topic"

    # Final output
    separator "═" 52
    log_success "Debate completed!"
    echo ""
    echo -e "${WHITE}Transcript saved to:${NC} $debate_dir/transcript.md"
    echo -e "${WHITE}Final synthesis:${NC} $debate_dir/final_synthesis.md"
    separator "═" 52

    return 0
}
