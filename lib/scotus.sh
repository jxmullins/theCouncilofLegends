#!/usr/bin/env bash
#
# The Council of Legends - SCOTUS Mode
# Judicial-style debate with majority/concurrence/dissent opinions
#

# Source SCOTUS-specific prompt builders
source "${COUNCIL_ROOT}/lib/scotus_prompts.sh"

#=============================================================================
# Resolution Derivation (Arbiter converts open topic to yes/no resolution)
#=============================================================================

derive_resolution() {
    local topic="$1"
    local output_file="$2"

    log_info "Deriving formal resolution from topic..."

    local system_prompt="You are the Arbiter for The Council of Legends SCOTUS mode. Your task is to convert open-ended topics into formal, debatable resolutions.

A good resolution:
1. Is a clear yes/no proposition that takes a definitive stance
2. Is specific enough to argue meaningfully
3. Allows reasonable arguments on both sides
4. Frames the topic as an affirmative statement to be affirmed or opposed

Output ONLY valid JSON. No markdown, no explanatory text."

    local user_prompt="Convert this open topic into a formal SCOTUS-style resolution:

TOPIC: $topic

Generate a JSON object with:
- original_topic: The original topic as given
- resolution: A clear, debatable yes/no proposition (affirmative statement)
- key_dimensions: 3-5 key aspects that should be considered in debate

Example output format:
{
  \"original_topic\": \"Rust vs Go\",
  \"resolution\": \"Rust is the superior choice for systems programming over Go\",
  \"key_dimensions\": [\"performance\", \"safety\", \"developer productivity\", \"ecosystem maturity\"]
}"

    local temp_response="${output_file}.raw"
    if invoke_groq "$user_prompt" "$temp_response" "$system_prompt"; then
        # Extract and clean JSON from response
        local json_response
        json_response=$(extract_json_from_response "$temp_response")

        if [[ -z "$json_response" ]]; then
            log_error "Resolution derivation returned invalid JSON"
            cat "$temp_response" > "${output_file}.invalid"
            rm -f "$temp_response"
            return 1
        fi

        echo "$json_response" > "$output_file"
        rm -f "$temp_response"

        local resolution
        resolution=$(jq -r '.resolution // empty' "$output_file" 2>/dev/null)
        if [[ -n "$resolution" ]]; then
            log_success "Resolution derived: $resolution"
            return 0
        fi
    fi

    log_error "Failed to derive resolution"
    return 1
}

#=============================================================================
# SCOTUS Opening Round (with resolution context)
#=============================================================================

run_scotus_opening_round() {
    local debate_dir="$1"
    local topic="$2"
    local resolution="$3"
    local key_dimensions="$4"

    log_info "Round 1: Opening Arguments"
    header "Round 1: Opening Arguments on the Resolution"

    for ai in claude codex gemini; do
        local system_prompt
        system_prompt=$(load_persona "$ai")

        ai_header "$ai" "Opening Argument"

        local prompt
        prompt=$(build_scotus_opening_prompt "$topic" "$resolution" "$key_dimensions")

        local output_file="$debate_dir/responses/round_1_${ai}.md"

        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$ai" "$output_file"
        else
            handle_ai_failure "$ai" "opening" "$output_file"
        fi
    done
}

#=============================================================================
# CJ Moderation Round (CJ asks follow-up questions)
#=============================================================================

run_cj_moderation() {
    local debate_dir="$1"
    local topic="$2"
    local resolution="$3"
    local round="$4"
    local cj="$CHIEF_JUSTICE"

    log_info "Chief Justice $cj providing moderation..."
    ai_header "$cj" "Chief Justice Moderation"

    local system_prompt="You are the Chief Justice moderating this SCOTUS-style debate. Your role is to:
1. Identify areas that need clarification or deeper exploration
2. Probe weaknesses in arguments presented
3. Ensure all sides have opportunity to address key points
4. Synthesize points of agreement and disagreement

Be fair, balanced, and focused on improving the quality of the debate."

    local prompt
    prompt=$(build_cj_moderation_prompt "$topic" "$resolution" "$round" "$debate_dir")

    local output_file="$debate_dir/responses/cj_moderation_round_${round}.md"

    if invoke_ai "$cj" "$prompt" "$output_file" "$system_prompt"; then
        display_response "$cj" "$output_file"
        return 0
    else
        log_warn "CJ moderation failed, continuing without"
        return 1
    fi
}

#=============================================================================
# SCOTUS Rebuttal Round (responds to CJ questions + other AIs)
#=============================================================================

run_scotus_rebuttal_round() {
    local debate_dir="$1"
    local topic="$2"
    local resolution="$3"
    local round="$4"

    log_info "Round $round: Rebuttals"
    header "Round $round: Rebuttals"

    for ai in claude codex gemini; do
        local system_prompt
        system_prompt=$(load_persona "$ai")

        ai_header "$ai" "Round $round Response"

        local prompt
        prompt=$(build_scotus_rebuttal_prompt "$topic" "$resolution" "$round" "$ai" "$debate_dir")

        local output_file="$debate_dir/responses/round_${round}_${ai}.md"

        if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$ai" "$output_file"
        else
            handle_ai_failure "$ai" "round $round" "$output_file"
        fi
    done
}

#=============================================================================
# Position Analysis (Arbiter infers positions from debate)
#=============================================================================

analyze_positions() {
    local debate_dir="$1"
    local resolution="$2"
    local output_file="$3"

    log_info "Analyzing positions from debate transcript..."

    # Build transcript of all debate rounds
    local transcript=""
    for round_file in "$debate_dir"/responses/round_*.md; do
        if [[ -f "$round_file" ]]; then
            local basename
            basename=$(basename "$round_file" .md)
            local round ai
            round=$(echo "$basename" | sed 's/round_//' | cut -d'_' -f1)
            ai=$(echo "$basename" | sed 's/round_[0-9]*_//')
            local ai_name
            ai_name=$(get_ai_name "$ai")

            transcript+="
### Round $round - ${ai_name}:
$(cat "$round_file")
"
        fi
    done

    local system_prompt="You are analyzing a completed debate transcript to determine the positions each AI took on the resolution. Your task is to:

1. Infer each AI's position on the resolution (affirm/oppose/nuanced)
2. NOT rely on explicit voting - infer from argumentation patterns
3. Identify the strongest advocate for each position
4. Determine majority/minority positions

Be objective. Positions must be inferred from the substance of arguments, not stated preferences.

Output ONLY valid JSON. No markdown, no explanatory text."

    local user_prompt="Analyze this debate and infer positions.

RESOLUTION: $resolution

DEBATE TRANSCRIPT:
$transcript

For each AI (claude, codex, gemini), determine:
- Their position: \"affirm\" (supports resolution), \"oppose\" (against resolution), or \"nuanced\" (mixed/unclear)
- Confidence in that inference (0.0-1.0)
- Their key contribution to that position

Then determine:
- Vote tally (how many affirm vs oppose vs nuanced)
- Majority position (affirm or oppose, whichever has more)
- Best advocate for majority position
- Best advocate for minority position (if any)

Output JSON:
{
  \"resolution\": \"...\",
  \"vote_tally\": { \"affirm\": N, \"oppose\": N, \"nuanced\": N },
  \"majority_position\": \"affirm|oppose\",
  \"position_by_ai\": {
    \"claude\": { \"position\": \"...\", \"confidence\": 0.X, \"key_contribution\": \"...\" },
    \"codex\": { \"position\": \"...\", \"confidence\": 0.X, \"key_contribution\": \"...\" },
    \"gemini\": { \"position\": \"...\", \"confidence\": 0.X, \"key_contribution\": \"...\" }
  },
  \"best_advocate\": { \"majority\": \"...\", \"minority\": \"...\" },
  \"analysis_notes\": \"...\"
}"

    local temp_response="${output_file}.raw"
    if invoke_groq "$user_prompt" "$temp_response" "$system_prompt"; then
        # Extract and clean JSON from response
        local json_response
        json_response=$(extract_json_from_response "$temp_response")

        if [[ -z "$json_response" ]]; then
            log_error "Position analysis returned invalid JSON"
            cat "$temp_response" > "${output_file}.invalid"
            rm -f "$temp_response"
            return 1
        fi

        echo "$json_response" > "$output_file"
        rm -f "$temp_response"

        local majority
        majority=$(jq -r '.majority_position // empty' "$output_file" 2>/dev/null)
        if [[ -n "$majority" ]]; then
            log_success "Position analysis complete"

            # Display results
            echo ""
            echo -e "${BOLD}Position Analysis Results:${NC}"
            local vote_affirm vote_oppose
            vote_affirm=$(jq -r '.vote_tally.affirm // 0' "$output_file")
            vote_oppose=$(jq -r '.vote_tally.oppose // 0' "$output_file")
            echo -e "  Vote: ${GREEN}$vote_affirm affirm${NC} - ${RED}$vote_oppose oppose${NC}"
            echo -e "  Majority position: ${CYAN}$majority${NC}"

            for ai in claude codex gemini; do
                local pos conf
                pos=$(jq -r ".position_by_ai.$ai.position // \"unknown\"" "$output_file")
                conf=$(jq -r ".position_by_ai.$ai.confidence // 0" "$output_file")
                local ai_name
                ai_name=$(get_ai_name "$ai")
                echo -e "  $ai_name: $pos (confidence: $conf)"
            done
            echo ""

            return 0
        fi
    fi

    log_error "Failed to analyze positions"
    return 1
}

#=============================================================================
# Opinion Assignment (CJ assigns who writes what)
#=============================================================================

assign_opinions() {
    local debate_dir="$1"
    local position_analysis_file="$2"
    local output_file="$3"
    local cj="$CHIEF_JUSTICE"

    log_info "Chief Justice $cj assigning opinion authors..."

    # Read position analysis
    local majority_position best_majority best_minority
    majority_position=$(jq -r '.majority_position' "$position_analysis_file")
    best_majority=$(jq -r '.best_advocate.majority' "$position_analysis_file")
    best_minority=$(jq -r '.best_advocate.minority // empty' "$position_analysis_file")

    local vote_affirm vote_oppose
    vote_affirm=$(jq -r '.vote_tally.affirm // 0' "$position_analysis_file")
    vote_oppose=$(jq -r '.vote_tally.oppose // 0' "$position_analysis_file")

    # Build assignments based on analysis
    local assignments
    assignments=$(cat <<EOF
{
  "chief_justice": "$cj",
  "majority_position": "$majority_position",
  "vote_summary": "$vote_affirm-$vote_oppose",
  "assignments": {
    "majority": {
      "author": "$best_majority",
      "reason": "Strongest advocate for $majority_position position"
    }
  }
}
EOF
)

    # Determine minority/concurrence assignments
    local minority_position
    if [[ "$majority_position" == "affirm" ]]; then
        minority_position="oppose"
    else
        minority_position="affirm"
    fi

    # Find who is in minority and who might concur
    local majority_ais=()
    local minority_ais=()

    for ai in claude codex gemini; do
        local pos
        pos=$(jq -r ".position_by_ai.$ai.position" "$position_analysis_file")
        if [[ "$pos" == "$majority_position" ]]; then
            majority_ais+=("$ai")
        elif [[ "$pos" == "$minority_position" ]]; then
            minority_ais+=("$ai")
        fi
    done

    # Update assignments with dissent/concurrence
    if [[ ${#minority_ais[@]} -gt 0 ]]; then
        local dissent_author="${minority_ais[0]}"
        assignments=$(echo "$assignments" | jq --arg author "$dissent_author" \
            '.assignments.dissent = { "author": $author, "reason": "Primary advocate for minority position" }')
    fi

    # Third AI in majority can concur if they're not the majority author
    for ai in "${majority_ais[@]}"; do
        if [[ "$ai" != "$best_majority" ]]; then
            assignments=$(echo "$assignments" | jq --arg author "$ai" \
                '.assignments.concurrence = { "author": $author, "reason": "Joined majority with potentially different reasoning" }')
            break
        fi
    done

    echo "$assignments" > "$output_file"

    # Display assignments
    echo ""
    echo -e "${BOLD}Opinion Assignments (by CJ $cj):${NC}"
    local maj_author
    maj_author=$(jq -r '.assignments.majority.author' "$output_file")
    echo -e "  ${GREEN}Majority Opinion:${NC} $(get_ai_name "$maj_author")"

    local conc_author
    conc_author=$(jq -r '.assignments.concurrence.author // empty' "$output_file")
    if [[ -n "$conc_author" ]]; then
        echo -e "  ${CYAN}Concurrence:${NC} $(get_ai_name "$conc_author")"
    fi

    local diss_author
    diss_author=$(jq -r '.assignments.dissent.author // empty' "$output_file")
    if [[ -n "$diss_author" ]]; then
        echo -e "  ${RED}Dissent:${NC} $(get_ai_name "$diss_author")"
    fi
    echo ""

    log_success "Opinion assignments complete"
    return 0
}

#=============================================================================
# Opinion Writing Phase
#=============================================================================

run_opinion_phase() {
    local debate_dir="$1"
    local topic="$2"
    local resolution="$3"
    local position_analysis_file="$4"
    local assignments_file="$5"

    header "Opinion Writing Phase"

    local majority_position
    majority_position=$(jq -r '.majority_position' "$position_analysis_file")

    # Get all positions and arguments for context
    local affirm_args oppose_args
    affirm_args=""
    oppose_args=""

    for ai in claude codex gemini; do
        local pos key_contrib
        pos=$(jq -r ".position_by_ai.$ai.position" "$position_analysis_file")
        key_contrib=$(jq -r ".position_by_ai.$ai.key_contribution" "$position_analysis_file")
        if [[ "$pos" == "affirm" ]]; then
            affirm_args+="- $(get_ai_name "$ai"): $key_contrib\n"
        elif [[ "$pos" == "oppose" ]]; then
            oppose_args+="- $(get_ai_name "$ai"): $key_contrib\n"
        fi
    done

    # Write Majority Opinion
    local maj_author
    maj_author=$(jq -r '.assignments.majority.author' "$assignments_file")
    log_info "Writing Majority Opinion ($(get_ai_name "$maj_author"))..."
    ai_header "$maj_author" "Majority Opinion"

    local maj_prompt
    maj_prompt=$(build_majority_opinion_prompt "$topic" "$resolution" "$majority_position" "$affirm_args" "$oppose_args" "$debate_dir")

    local maj_system="You are writing the MAJORITY OPINION for The Council of Legends. Write a formal opinion that:
1. States the holding clearly
2. Provides reasoning for the decision
3. Directly addresses and rebuts the dissent's key arguments
Be authoritative but fair. Structure as a formal judicial-style opinion."

    local maj_output="$debate_dir/opinions/majority_${maj_author}.md"
    mkdir -p "$debate_dir/opinions"

    if invoke_ai "$maj_author" "$maj_prompt" "$maj_output" "$maj_system"; then
        display_response "$maj_author" "$maj_output"
    else
        handle_ai_failure "$maj_author" "majority opinion" "$maj_output"
    fi

    # Write Dissent (if any)
    local diss_author
    diss_author=$(jq -r '.assignments.dissent.author // empty' "$assignments_file")
    if [[ -n "$diss_author" ]]; then
        log_info "Writing Dissent ($(get_ai_name "$diss_author"))..."
        ai_header "$diss_author" "Dissenting Opinion"

        local diss_prompt
        diss_prompt=$(build_dissent_opinion_prompt "$topic" "$resolution" "$majority_position" "$affirm_args" "$oppose_args" "$debate_dir")

        local diss_system="You are writing the DISSENTING OPINION for The Council of Legends. Write a formal dissent that:
1. Explains why you disagree with the majority's holding
2. Points out flaws in the majority's reasoning
3. Presents your alternative view
Be respectful but pointed in your disagreement. Structure as a formal judicial-style dissent."

        local diss_output="$debate_dir/opinions/dissent_${diss_author}.md"

        if invoke_ai "$diss_author" "$diss_prompt" "$diss_output" "$diss_system"; then
            display_response "$diss_author" "$diss_output"
        else
            handle_ai_failure "$diss_author" "dissent" "$diss_output"
        fi
    fi

    # Write Concurrence (if any)
    local conc_author
    conc_author=$(jq -r '.assignments.concurrence.author // empty' "$assignments_file")
    if [[ -n "$conc_author" ]]; then
        log_info "Writing Concurrence ($(get_ai_name "$conc_author"))..."
        ai_header "$conc_author" "Concurring Opinion"

        local conc_prompt
        conc_prompt=$(build_concurrence_opinion_prompt "$topic" "$resolution" "$majority_position" "$maj_author" "$debate_dir")

        local conc_system="You are writing a CONCURRING OPINION for The Council of Legends. You agree with the majority's outcome but want to add your own perspective. Write a formal concurrence that:
1. States you agree with the judgment
2. Explains any different or additional reasoning
3. Adds insights the majority may have missed
Be collegial but distinct. Structure as a formal judicial-style concurrence."

        local conc_output="$debate_dir/opinions/concurrence_${conc_author}.md"

        if invoke_ai "$conc_author" "$conc_prompt" "$conc_output" "$conc_system"; then
            display_response "$conc_author" "$conc_output"
        else
            handle_ai_failure "$conc_author" "concurrence" "$conc_output"
        fi
    fi
}

#=============================================================================
# SCOTUS Transcript Generation
#=============================================================================

generate_scotus_transcript() {
    local debate_dir="$1"
    local topic="$2"
    local resolution="$3"
    local assignments_file="$4"

    local transcript_file="$debate_dir/transcript.md"

    local vote_summary
    vote_summary=$(jq -r '.vote_summary' "$assignments_file")
    local cj
    cj=$(jq -r '.chief_justice' "$assignments_file")
    local majority_position
    majority_position=$(jq -r '.majority_position' "$assignments_file")

    cat > "$transcript_file" <<EOF
# The Council of Legends - Judicial Mode

## Deliberation Summary
- **Topic:** $topic
- **Resolution:** $resolution
- **Chief Justice:** $(get_ai_name "$cj")
- **Vote:** $vote_summary
- **Decision:** Resolution ${majority_position}ed

---

## Debate Rounds

EOF

    # Include debate rounds
    for round_file in "$debate_dir"/responses/round_*.md; do
        if [[ -f "$round_file" ]]; then
            local basename
            basename=$(basename "$round_file" .md)
            local round ai
            round=$(echo "$basename" | sed 's/round_//' | cut -d'_' -f1)
            ai=$(echo "$basename" | sed 's/round_[0-9]*_//')
            local ai_name
            ai_name=$(get_ai_name "$ai")

            cat >> "$transcript_file" <<EOF
### Round $round - ${ai_name}
$(cat "$round_file")

EOF
        fi
    done

    # Include CJ moderation
    for mod_file in "$debate_dir"/responses/cj_moderation_*.md; do
        if [[ -f "$mod_file" ]]; then
            local basename
            basename=$(basename "$mod_file" .md)
            local round
            round=$(echo "$basename" | sed 's/cj_moderation_round_//')

            cat >> "$transcript_file" <<EOF
### Chief Justice Moderation (after Round $round)
$(cat "$mod_file")

EOF
        fi
    done

    cat >> "$transcript_file" <<EOF

---

## Opinions of the Council

EOF

    # Majority Opinion
    local maj_author
    maj_author=$(jq -r '.assignments.majority.author' "$assignments_file")
    local maj_file="$debate_dir/opinions/majority_${maj_author}.md"
    if [[ -f "$maj_file" ]]; then
        cat >> "$transcript_file" <<EOF
### Majority Opinion
**$(get_ai_name "$maj_author")**, delivering the opinion of the Council.

$(cat "$maj_file")

EOF
    fi

    # Concurrence
    local conc_author
    conc_author=$(jq -r '.assignments.concurrence.author // empty' "$assignments_file")
    if [[ -n "$conc_author" ]]; then
        local conc_file="$debate_dir/opinions/concurrence_${conc_author}.md"
        if [[ -f "$conc_file" ]]; then
            cat >> "$transcript_file" <<EOF
### Concurring Opinion
**$(get_ai_name "$conc_author")**, concurring.

$(cat "$conc_file")

EOF
        fi
    fi

    # Dissent
    local diss_author
    diss_author=$(jq -r '.assignments.dissent.author // empty' "$assignments_file")
    if [[ -n "$diss_author" ]]; then
        local diss_file="$debate_dir/opinions/dissent_${diss_author}.md"
        if [[ -f "$diss_file" ]]; then
            cat >> "$transcript_file" <<EOF
### Dissenting Opinion
**$(get_ai_name "$diss_author")**, dissenting.

$(cat "$diss_file")

EOF
        fi
    fi

    cat >> "$transcript_file" <<EOF

---

*Generated by The Council of Legends - Judicial Mode*
*$(date)*
EOF

    log_success "Transcript saved to: $transcript_file"
}

#=============================================================================
# Main SCOTUS Debate Runner
#=============================================================================

run_scotus_debate() {
    local topic="$1"
    local rounds="${2:-3}"

    # Validate
    if [[ -z "$topic" ]]; then
        log_error "Topic is required"
        return 1
    fi

    if ! validate_cli_availability; then
        return 1
    fi

    # Check for arbiter (required for SCOTUS mode)
    if [[ -z "${GROQ_API_KEY:-}" ]]; then
        log_error "SCOTUS mode requires GROQ_API_KEY for arbiter functions"
        echo "Please set GROQ_API_KEY environment variable"
        return 1
    fi

    # Setup
    local debate_dir
    debate_dir=$(create_debate_directory "$topic")
    save_metadata "$debate_dir" "$topic" "scotus" "$rounds"

    # Display intro
    header "JUDICIAL MODE"
    echo -e "${WHITE}Topic:${NC} $topic"
    echo -e "${WHITE}Chief Justice:${NC} $(get_ai_name "$CHIEF_JUSTICE")"
    echo -e "${WHITE}Rounds:${NC} $rounds"
    echo ""

    #=========================================================================
    # Phase 1: Resolution Derivation
    #=========================================================================
    header "Phase 1: Resolution Derivation"

    local resolution_file="$debate_dir/resolution.json"
    if ! derive_resolution "$topic" "$resolution_file"; then
        log_error "Failed to derive resolution. Cannot proceed with SCOTUS mode."
        return 1
    fi

    local resolution key_dimensions
    resolution=$(jq -r '.resolution' "$resolution_file")
    key_dimensions=$(jq -r '.key_dimensions | join(", ")' "$resolution_file")

    echo ""
    echo -e "${BOLD}Formal Resolution:${NC}"
    echo -e "  ${CYAN}\"$resolution\"${NC}"
    echo -e "${WHITE}Key Dimensions:${NC} $key_dimensions"
    echo ""

    #=========================================================================
    # Phase 2: Debate Rounds (CJ-moderated)
    #=========================================================================
    header "Phase 2: Oral Arguments"

    # Round 1: Opening Arguments
    run_scotus_opening_round "$debate_dir" "$topic" "$resolution" "$key_dimensions"

    # Rounds 2-N: CJ Moderation + Rebuttals
    for ((round=2; round<=rounds; round++)); do
        # CJ provides moderation/questions
        run_cj_moderation "$debate_dir" "$topic" "$resolution" "$((round-1))"

        # AIs respond
        run_scotus_rebuttal_round "$debate_dir" "$topic" "$resolution" "$round"
    done

    #=========================================================================
    # Phase 3: Position Analysis
    #=========================================================================
    header "Phase 3: Position Analysis"

    local position_file="$debate_dir/position_analysis.json"
    if ! analyze_positions "$debate_dir" "$resolution" "$position_file"; then
        log_error "Failed to analyze positions"
        return 1
    fi

    #=========================================================================
    # Phase 4: Opinion Assignment
    #=========================================================================
    header "Phase 4: Opinion Assignment"

    local assignments_file="$debate_dir/opinion_assignments.json"
    assign_opinions "$debate_dir" "$position_file" "$assignments_file"

    #=========================================================================
    # Phase 5: Opinion Writing
    #=========================================================================
    run_opinion_phase "$debate_dir" "$topic" "$resolution" "$position_file" "$assignments_file"

    #=========================================================================
    # Phase 6: Generate Transcript
    #=========================================================================
    generate_scotus_transcript "$debate_dir" "$topic" "$resolution" "$assignments_file"

    # Final output
    separator "=" 52
    log_success "Judicial debate completed!"
    echo ""
    local vote_summary
    vote_summary=$(jq -r '.vote_summary' "$assignments_file")
    local majority_position
    majority_position=$(jq -r '.majority_position' "$assignments_file")
    echo -e "${BOLD}Decision:${NC} Resolution ${majority_position}ed ($vote_summary)"
    echo -e "${WHITE}Transcript:${NC} $debate_dir/transcript.md"
    separator "=" 52

    return 0
}
