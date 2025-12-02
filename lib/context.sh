#!/usr/bin/env bash
#
# The Council of Legends - Context Building
# Builds prompts and manages context for each debate phase
#

#=============================================================================
# Context Summarization (for token efficiency)
#=============================================================================

# Summarize a single round's responses to save context space
# Uses Groq arbiter for fast, cheap summarization
# Args: $1 = debate_dir, $2 = round number, $3 = output file
summarize_round() {
    local debate_dir="$1"
    local round="$2"
    local output_file="$3"

    log_debug "Summarizing round $round..."

    # Collect all responses from this round
    local round_content=""
    for ai in claude codex gemini; do
        local response_file="$debate_dir/responses/round_${round}_${ai}.md"
        if [[ -f "$response_file" ]]; then
            local ai_name
            ai_name=$(get_ai_name "$ai")
            round_content+="### ${ai_name}:
$(cat "$response_file")

"
        fi
    done

    if [[ -z "$round_content" ]]; then
        log_warn "No content to summarize for round $round"
        return 1
    fi

    # Build summarization prompt
    local prompt="Summarize the following debate round responses concisely. Preserve:
1. Each participant's main position
2. Key arguments made
3. Points of agreement/disagreement

Keep summary under 300 words total while retaining essential points.

---

$round_content"

    local system_prompt="You are a neutral summarizer. Create concise, accurate summaries that preserve key arguments."

    # Check if Groq is available, otherwise use Claude
    if [[ -n "${GROQ_API_KEY:-}" ]]; then
        source "${COUNCIL_ROOT}/lib/adapters/groq_adapter.sh"
        invoke_groq "$prompt" "$output_file" "$system_prompt"
    else
        # Fallback to Claude for summarization
        invoke_claude "$prompt" "$output_file" "$system_prompt"
    fi
}

# Summarize all rounds in a debate (called after each round if SUMMARIZE_AFTER_ROUND=true)
# Args: $1 = debate_dir
run_round_summarization() {
    local debate_dir="$1"
    local round="$2"

    if [[ "${SUMMARIZE_AFTER_ROUND:-false}" != "true" ]]; then
        return 0
    fi

    local summary_dir="$debate_dir/context"
    ensure_dir "$summary_dir"

    local summary_file="$summary_dir/round_${round}_summary.md"
    if summarize_round "$debate_dir" "$round" "$summary_file"; then
        log_debug "Round $round summary saved to: $summary_file"
    else
        log_warn "Failed to summarize round $round"
    fi
}

# Get context for previous rounds, using summaries if available and needed
# Args: $1 = debate_dir, $2 = current_round, $3 = current_ai
get_previous_context() {
    local debate_dir="$1"
    local current_round="$2"
    local current_ai="$3"
    local context=""
    local total_chars=0
    local max_chars="${MAX_CONTEXT_CHARS:-8000}"

    # For round 2, just use full round 1 content (it's the only previous round)
    if [[ "$current_round" -eq 2 ]]; then
        for ai in claude codex gemini; do
            if [[ "$ai" != "$current_ai" ]]; then
                local response_file="$debate_dir/responses/round_1_${ai}.md"
                if [[ -f "$response_file" ]]; then
                    local ai_name
                    ai_name=$(get_ai_name "$ai")
                    local response_content
                    response_content=$(cat "$response_file")
                    context+="### ${ai_name}'s Position (Round 1):
$response_content

"
                fi
            fi
        done
        echo "$context"
        return
    fi

    # For later rounds, check if we should use summaries
    local prev_round=$((current_round - 1))

    # Always include full previous round (most recent)
    for ai in claude codex gemini; do
        if [[ "$ai" != "$current_ai" ]]; then
            local response_file="$debate_dir/responses/round_${prev_round}_${ai}.md"
            if [[ -f "$response_file" ]]; then
                local ai_name
                ai_name=$(get_ai_name "$ai")
                local response_content
                response_content=$(cat "$response_file")
                context+="### ${ai_name}'s Position (Round $prev_round):
$response_content

"
                total_chars=$((total_chars + ${#response_content}))
            fi
        fi
    done

    # For older rounds, use summaries if available and context is getting large
    for ((r=1; r<prev_round; r++)); do
        local summary_file="$debate_dir/context/round_${r}_summary.md"
        if [[ -f "$summary_file" ]] && [[ $total_chars -gt $((max_chars / 2)) ]]; then
            # Use summary for older rounds when context is large
            context+="### Round $r Summary:
$(cat "$summary_file")

"
        else
            # Use full content if summary not available or context is small
            for ai in claude codex gemini; do
                if [[ "$ai" != "$current_ai" ]]; then
                    local response_file="$debate_dir/responses/round_${r}_${ai}.md"
                    if [[ -f "$response_file" ]]; then
                        local ai_name
                        ai_name=$(get_ai_name "$ai")
                        local response_content
                        response_content=$(cat "$response_file")
                        context+="### ${ai_name}'s Position (Round $r):
$response_content

"
                        total_chars=$((total_chars + ${#response_content}))
                    fi
                fi
            done
        fi
    done

    # Warn if context is very large
    if [[ $total_chars -gt $max_chars ]]; then
        log_warn "Context size ($total_chars chars) exceeds MAX_CONTEXT_CHARS ($max_chars)"
    fi

    echo "$context"
}

#=============================================================================
# Opening Round Prompt
#=============================================================================

build_opening_prompt() {
    local topic="$1"
    local mode="${2:-collaborative}"

    cat <<EOF
# The Council of Legends - Opening Statement

## Topic for Discussion
$topic

## Debate Format
This is a ${mode} debate between AI assistants from different providers (Claude, Codex, Gemini). Each participant will present their initial position, followed by rebuttal rounds, and finally a synthesis of perspectives.

## Your Task
Present your opening position on this topic. Structure your response as follows:

1. **Main Position**: State your primary thesis or recommendation
2. **Key Arguments**: Provide 2-3 supporting points with reasoning
3. **Considerations**: Note any important trade-offs, risks, or factors to consider

Guidelines:
- Be clear and direct in your position
- Support arguments with reasoning, not just assertions
- Keep your response focused (300-400 words maximum)
- Remember: other AIs will respond to your arguments
EOF
}

#=============================================================================
# Rebuttal Round Prompt
#=============================================================================

build_rebuttal_prompt() {
    local topic="$1"
    local mode="$2"
    local round="$3"
    local current_ai="$4"
    local debate_dir="$5"

    local prev_round=$((round - 1))

    cat <<EOF
# The Council of Legends - Round $round Rebuttal

## Topic
$topic

## Previous Debate Context
EOF

    # Use get_previous_context for smart context management
    local context
    context=$(get_previous_context "$debate_dir" "$round" "$current_ai")
    echo "$context"

    # Include own previous response
    local own_response="$debate_dir/responses/round_${prev_round}_${current_ai}.md"
    if [[ -f "$own_response" ]]; then
        cat <<EOF

### Your Previous Position:
$(cat "$own_response")

EOF
    fi

    cat <<EOF

## Your Task
Respond to the other participants' arguments. Structure your response as follows:

1. **Points of Agreement**: What do you agree with and why?
2. **Points of Disagreement**: What do you disagree with? Provide counterarguments.
3. **New Insights**: Any new perspectives or considerations to add?
4. **Refined Position**: How has your view evolved (if at all)?

Guidelines:
- Engage substantively with specific arguments made by others
- Be constructive, not dismissive
- Acknowledge strong points even when you disagree
- Keep your response focused (300-400 words maximum)
EOF
}

#=============================================================================
# Synthesis Round Prompt
#=============================================================================

build_synthesis_prompt() {
    local topic="$1"
    local mode="$2"
    local debate_dir="$3"
    local current_ai="$4"

    cat <<EOF
# The Council of Legends - Final Synthesis

## Topic
$topic

## Full Debate Summary
EOF

    # Include all responses from all rounds
    local found_responses=false
    for round_file in "$debate_dir"/responses/round_*.md; do
        if [[ -f "$round_file" ]]; then
            found_responses=true
            local basename
            basename=$(basename "$round_file" .md)
            local round ai
            round=$(echo "$basename" | sed 's/round_//' | cut -d'_' -f1)
            ai=$(echo "$basename" | sed 's/round_[0-9]*_//')
            local ai_name
            ai_name=$(get_ai_name "$ai")

            cat <<EOF

### Round $round - ${ai_name}:
$(cat "$round_file")

EOF
        fi
    done

    if [[ "$found_responses" == "false" ]]; then
        echo "No previous responses found."
    fi

    cat <<EOF

## Your Task
Provide your final synthesis of this debate. Structure your response as follows:

1. **Areas of Consensus**: What did all participants agree on?
2. **Key Disagreements**: What issues remained contested? Briefly summarize different positions.
3. **Your Conclusion**: Based on the debate, what is your final recommendation or conclusion?
4. **Key Insights**: What were the most valuable insights from this discussion?

Guidelines:
- Be balanced and fair to all perspectives
- Highlight what was learned through the debate
- Provide actionable conclusions where possible
- Keep your synthesis focused (400-500 words maximum)

This synthesis should be useful to someone who didn't witness the full debate.
EOF
}

#=============================================================================
# Combined Synthesis Prompt (for final merged synthesis)
#=============================================================================

build_combined_synthesis_prompt() {
    local topic="$1"
    local debate_dir="$2"

    cat <<EOF
# The Council of Legends - Combined Final Synthesis

## Topic
$topic

## Individual Syntheses from Each AI
EOF

    # Include each AI's synthesis
    for ai in claude codex gemini; do
        local synthesis_file="$debate_dir/responses/synthesis_${ai}.md"
        if [[ -f "$synthesis_file" ]]; then
            local ai_name
            ai_name=$(get_ai_name "$ai")
            cat <<EOF

### ${ai_name}'s Synthesis:
$(cat "$synthesis_file")

EOF
        fi
    done

    cat <<EOF

## Your Task
Create a unified final synthesis that combines all three perspectives. This should:

1. Identify the true consensus across all three AIs
2. Acknowledge remaining differences of opinion
3. Provide a balanced final recommendation
4. Highlight the most important takeaways

This is the final output that will be presented to the user.
EOF
}
