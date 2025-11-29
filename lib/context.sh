#!/usr/bin/env bash
#
# The Council of Legends - Context Building
# Builds prompts and manages context for each debate phase
#

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

## Previous Round Responses
EOF

    # Include other AIs' responses from previous round
    for ai in claude codex gemini; do
        if [[ "$ai" != "$current_ai" ]]; then
            local response_file="$debate_dir/responses/round_${prev_round}_${ai}.md"
            if [[ -f "$response_file" ]]; then
                local ai_name
                ai_name=$(get_ai_name "$ai")
                cat <<EOF

### ${ai_name}'s Position (Round $prev_round):
$(cat "$response_file")

EOF
            fi
        fi
    done

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
