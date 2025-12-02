#!/usr/bin/env bash
#
# The Council of Legends - SCOTUS Mode Prompt Builders
# Builds prompts for each phase of SCOTUS-style debate
#

#=============================================================================
# Opening Round Prompt (Resolution-aware)
#=============================================================================

build_scotus_opening_prompt() {
    local topic="$1"
    local resolution="$2"
    local key_dimensions="$3"

    cat <<EOF
# The Council of Legends - Judicial Mode: Opening Argument

## Topic
$topic

## Formal Resolution Before the Council
**"$resolution"**

You must take a position on this resolution: AFFIRM (support it) or OPPOSE (argue against it).

## Key Dimensions to Consider
$key_dimensions

## Your Task
Present your opening argument. Structure your response as follows:

1. **Your Position**: Clearly state whether you AFFIRM or OPPOSE the resolution
2. **Primary Argument**: Your strongest reasoning for this position
3. **Supporting Points**: 2-3 additional arguments supporting your position
4. **Anticipated Counterarguments**: Acknowledge the strongest opposing arguments and briefly address them

Guidelines:
- Take a clear position - do not hedge or remain neutral
- Support arguments with reasoning, examples, or evidence
- Be persuasive but fair
- Keep your response focused (400-500 words maximum)
- Remember: The Chief Justice will probe your arguments, and you may face rebuttals
EOF
}

#=============================================================================
# CJ Moderation Prompt
#=============================================================================

build_cj_moderation_prompt() {
    local topic="$1"
    local resolution="$2"
    local round="$3"
    local debate_dir="$4"

    cat <<EOF
# Chief Justice Moderation - After Round $round

## Resolution
"$resolution"

## Arguments Presented So Far
EOF

    # Include all responses from rounds up to current
    for r in $(seq 1 "$round"); do
        for ai in claude codex gemini; do
            local response_file="$debate_dir/responses/round_${r}_${ai}.md"
            if [[ -f "$response_file" ]]; then
                local ai_name
                ai_name=$(get_ai_name "$ai")
                cat <<EOF

### Round $r - ${ai_name}:
$(cat "$response_file")

EOF
            fi
        done
    done

    cat <<EOF

## Your Task as Chief Justice
As Chief Justice, guide the next round of debate by:

1. **Identify Unresolved Issues**: What key questions remain unanswered?
2. **Probe Weak Arguments**: Which arguments need more support or have logical gaps?
3. **Clarify Positions**: Are there ambiguities in any AI's position?
4. **Direct Questions**: Pose 2-3 specific questions for the council to address in the next round

Your moderation should:
- Be fair to all positions
- Focus on improving argument quality
- Not reveal your own opinion on the resolution
- Keep the debate focused on key dimensions

Format:
### Summary of Current State
[Brief overview of positions and key disagreements]

### Questions for the Council
1. [Specific question targeting a gap or weakness]
2. [Question to clarify or deepen a position]
3. [Question about an overlooked consideration]

Keep moderation concise (200-300 words).
EOF
}

#=============================================================================
# SCOTUS Rebuttal Prompt (includes CJ questions)
#=============================================================================

build_scotus_rebuttal_prompt() {
    local topic="$1"
    local resolution="$2"
    local round="$3"
    local current_ai="$4"
    local debate_dir="$5"

    local prev_round=$((round - 1))

    cat <<EOF
# The Council of Legends - Judicial Mode: Round $round Response

## Resolution
"$resolution"

## Previous Round Arguments
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

    # Include CJ moderation questions if available
    local cj_mod="$debate_dir/responses/cj_moderation_round_${prev_round}.md"
    if [[ -f "$cj_mod" ]]; then
        cat <<EOF

## Chief Justice's Questions
The Chief Justice has posed the following questions for this round:

$(cat "$cj_mod")

EOF
    fi

    cat <<EOF

## Your Task
Respond to both the Chief Justice's questions AND the other participants' arguments.

1. **Address CJ Questions**: Respond to any questions directed at your position
2. **Rebut Opposing Arguments**: Counter specific points made against your position
3. **Defend Your Position**: Strengthen your arguments in light of criticism
4. **Refine If Needed**: Adjust your position if you've been convinced by good arguments

Guidelines:
- Maintain your position (AFFIRM or OPPOSE) unless truly convinced otherwise
- Engage substantively with specific arguments
- Be respectful but vigorous in defense
- Acknowledge strong points even from opponents
- Keep response focused (400-500 words maximum)
EOF
}

#=============================================================================
# Majority Opinion Prompt
#=============================================================================

build_majority_opinion_prompt() {
    local topic="$1"
    local resolution="$2"
    local majority_position="$3"
    local affirm_args="$4"
    local oppose_args="$5"
    local debate_dir="$6"

    local holding
    if [[ "$majority_position" == "affirm" ]]; then
        holding="The resolution is AFFIRMED."
    else
        holding="The resolution is NOT AFFIRMED (opposed)."
    fi

    cat <<EOF
# Writing the Majority Opinion for The Council of Legends

## Resolution
"$resolution"

## Holding
$holding

## Arguments FOR the Resolution (Affirm):
$(echo -e "$affirm_args")

## Arguments AGAINST the Resolution (Oppose):
$(echo -e "$oppose_args")

## Your Task
Write the MAJORITY OPINION for this deliberation. Your opinion must:

### I. Holding
State clearly that the resolution is ${majority_position}ed and summarize the decision.

### II. Reasoning
Explain the reasoning that supports this holding. Draw from the strongest arguments made during the debate.

### III. Response to Dissent
Directly address the key arguments made by those who oppose this holding. Explain why those arguments are insufficient to change the outcome.

### IV. Conclusion
Summarize the key points and restate the holding.

Guidelines:
- Write in formal opinion style
- Be authoritative and clear
- Address counterarguments fairly before dismissing them
- Focus on the strongest reasoning, not all arguments
- Length: 500-700 words
EOF
}

#=============================================================================
# Dissent Opinion Prompt
#=============================================================================

build_dissent_opinion_prompt() {
    local topic="$1"
    local resolution="$2"
    local majority_position="$3"
    local affirm_args="$4"
    local oppose_args="$5"
    local debate_dir="$6"

    local dissent_position
    if [[ "$majority_position" == "affirm" ]]; then
        dissent_position="oppose"
    else
        dissent_position="affirm"
    fi

    cat <<EOF
# Writing the Dissenting Opinion for The Council of Legends

## Resolution
"$resolution"

## Majority Holding
The majority has ${majority_position}ed the resolution. You DISSENT from this holding.

## Arguments FOR the Resolution:
$(echo -e "$affirm_args")

## Arguments AGAINST the Resolution:
$(echo -e "$oppose_args")

## Your Task
Write a DISSENTING OPINION explaining why the majority is wrong.

### I. Statement of Dissent
Clearly state that you dissent and briefly why.

### II. The Majority's Error
Explain the fundamental flaw in the majority's reasoning. What did they get wrong?

### III. The Correct View
Present your alternative analysis. Why should the resolution have been ${dissent_position}ed?

### IV. Consequences
What are the implications of the majority's flawed reasoning?

### V. Conclusion
Summarize your dissent and restate your position.

Guidelines:
- Write in formal dissent style
- Be respectful but pointed in your criticism
- Focus on the strongest grounds for disagreement
- Explain how you would have ruled differently
- Length: 400-600 words
EOF
}

#=============================================================================
# Concurrence Opinion Prompt
#=============================================================================

build_concurrence_opinion_prompt() {
    local topic="$1"
    local resolution="$2"
    local majority_position="$3"
    local majority_author="$4"
    local debate_dir="$5"

    cat <<EOF
# Writing a Concurring Opinion for The Council of Legends

## Resolution
"$resolution"

## Majority Holding
The majority, authored by $(get_ai_name "$majority_author"), has ${majority_position}ed the resolution.

You CONCUR with this holding (agree with the outcome).

## Your Task
Write a CONCURRING OPINION. You agree with the result but want to add your perspective.

### I. Concurrence Statement
State that you concur in the judgment.

### II. Points of Agreement
Briefly acknowledge where you agree with the majority's reasoning.

### III. Additional or Alternative Reasoning
Explain your own reasoning for reaching the same conclusion. This might include:
- Different emphasis on which arguments are strongest
- Additional considerations the majority didn't address
- Alternative logical path to the same conclusion
- Narrower or broader grounds for the holding

### IV. Conclusion
Summarize your concurrence.

Guidelines:
- Write in formal concurrence style
- Be collegial - you're agreeing with the outcome
- Add value by offering a distinct perspective
- Don't just repeat the majority's reasoning
- Length: 300-400 words
EOF
}
