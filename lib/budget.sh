#!/usr/bin/env bash
#
# The Council of Legends - Budget Tracking System
# Token usage estimation and cost tracking
#

#=============================================================================
# Cost Configuration (per 1M tokens, as of Dec 2024)
#=============================================================================

# Claude pricing (Anthropic) - per 1M tokens
declare -A CLAUDE_COSTS=(
    ["sonnet_input"]="3.00"
    ["sonnet_output"]="15.00"
    ["opus_input"]="15.00"
    ["opus_output"]="75.00"
    ["haiku_input"]="0.25"
    ["haiku_output"]="1.25"
)

# OpenAI/Codex pricing - per 1M tokens
declare -A CODEX_COSTS=(
    ["gpt-4o_input"]="2.50"
    ["gpt-4o_output"]="10.00"
    ["gpt-4o-mini_input"]="0.15"
    ["gpt-4o-mini_output"]="0.60"
    ["gpt-4-turbo_input"]="10.00"
    ["gpt-4-turbo_output"]="30.00"
)

# Google Gemini pricing - per 1M tokens
declare -A GEMINI_COSTS=(
    ["gemini-2.5-flash_input"]="0.075"
    ["gemini-2.5-flash_output"]="0.30"
    ["gemini-2.5-pro_input"]="1.25"
    ["gemini-2.5-pro_output"]="5.00"
)

# Groq pricing (very low) - per 1M tokens
declare -A GROQ_COSTS=(
    ["llama-3.3-70b_input"]="0.59"
    ["llama-3.3-70b_output"]="0.79"
)

#=============================================================================
# Budget Profiles
#=============================================================================

# Profile definitions: model selections optimized for cost
declare -A BUDGET_PROFILES=(
    ["frugal"]="claude:haiku,codex:gpt-4o-mini,gemini:gemini-2.5-flash"
    ["balanced"]="claude:sonnet,codex:gpt-4o,gemini:gemini-2.5-flash"
    ["premium"]="claude:opus,codex:gpt-4-turbo,gemini:gemini-2.5-pro"
)

#=============================================================================
# Token Estimation
#=============================================================================

# Rough token estimation (avg ~4 chars per token for English)
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    echo $(( (char_count + 3) / 4 ))  # Round up
}

# Estimate tokens from a file
estimate_file_tokens() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local char_count
        char_count=$(wc -c < "$file" | tr -d ' ')
        echo $(( (char_count + 3) / 4 ))
    else
        echo 0
    fi
}

#=============================================================================
# Cost Calculation
#=============================================================================

# Calculate cost for a single API call
# Args: $1 = AI (claude/codex/gemini/groq)
#       $2 = model variant
#       $3 = input tokens
#       $4 = output tokens
calculate_call_cost() {
    local ai="$1"
    local model="$2"
    local input_tokens="$3"
    local output_tokens="$4"

    local input_cost=0
    local output_cost=0

    case "$ai" in
        claude)
            input_cost="${CLAUDE_COSTS[${model}_input]:-3.00}"
            output_cost="${CLAUDE_COSTS[${model}_output]:-15.00}"
            ;;
        codex)
            input_cost="${CODEX_COSTS[${model}_input]:-2.50}"
            output_cost="${CODEX_COSTS[${model}_output]:-10.00}"
            ;;
        gemini)
            input_cost="${GEMINI_COSTS[${model}_input]:-0.075}"
            output_cost="${GEMINI_COSTS[${model}_output]:-0.30}"
            ;;
        groq)
            input_cost="${GROQ_COSTS[${model}_input]:-0.59}"
            output_cost="${GROQ_COSTS[${model}_output]:-0.79}"
            ;;
    esac

    # Calculate cost (costs are per 1M tokens)
    local total_cost
    total_cost=$(echo "scale=6; ($input_tokens * $input_cost / 1000000) + ($output_tokens * $output_cost / 1000000)" | bc)
    echo "$total_cost"
}

#=============================================================================
# Session Budget Tracking
#=============================================================================

# Budget tracking state
BUDGET_SESSION_COST=0
BUDGET_MAX_COST="${BUDGET_MAX_COST:-0}"  # 0 = unlimited
BUDGET_PROFILE="${BUDGET_PROFILE:-balanced}"

# Token counters per AI
declare -A BUDGET_INPUT_TOKENS
declare -A BUDGET_OUTPUT_TOKENS
declare -A BUDGET_COSTS_BY_AI

# Initialize budget tracking for a session
init_budget() {
    local max_cost="${1:-0}"
    local profile="${2:-balanced}"

    BUDGET_MAX_COST="$max_cost"
    BUDGET_PROFILE="$profile"
    BUDGET_SESSION_COST=0

    for ai in claude codex gemini groq; do
        BUDGET_INPUT_TOKENS[$ai]=0
        BUDGET_OUTPUT_TOKENS[$ai]=0
        BUDGET_COSTS_BY_AI[$ai]=0
    done

    log_debug "Budget initialized: max=\$$max_cost, profile=$profile"
}

# Record token usage for an API call
# Args: $1 = AI, $2 = model, $3 = input_tokens, $4 = output_tokens
record_usage() {
    local ai="$1"
    local model="$2"
    local input_tokens="$3"
    local output_tokens="$4"

    # Update counters
    BUDGET_INPUT_TOKENS[$ai]=$(( ${BUDGET_INPUT_TOKENS[$ai]:-0} + input_tokens ))
    BUDGET_OUTPUT_TOKENS[$ai]=$(( ${BUDGET_OUTPUT_TOKENS[$ai]:-0} + output_tokens ))

    # Calculate cost
    local call_cost
    call_cost=$(calculate_call_cost "$ai" "$model" "$input_tokens" "$output_tokens")

    BUDGET_COSTS_BY_AI[$ai]=$(echo "${BUDGET_COSTS_BY_AI[$ai]:-0} + $call_cost" | bc)
    BUDGET_SESSION_COST=$(echo "$BUDGET_SESSION_COST + $call_cost" | bc)

    log_debug "Usage: $ai +$input_tokens in / +$output_tokens out = \$$call_cost (session total: \$$BUDGET_SESSION_COST)"

    # Log event for telemetry
    log_event "token_usage" "{\"ai\":\"$ai\",\"model\":\"$model\",\"input\":$input_tokens,\"output\":$output_tokens,\"cost\":$call_cost}"
}

# Check if we're within budget
check_budget() {
    if [[ "$BUDGET_MAX_COST" == "0" ]]; then
        return 0  # No limit
    fi

    local over_budget
    over_budget=$(echo "$BUDGET_SESSION_COST > $BUDGET_MAX_COST" | bc)

    if [[ "$over_budget" == "1" ]]; then
        log_warn "Budget exceeded: \$$BUDGET_SESSION_COST > \$$BUDGET_MAX_COST"
        return 1
    fi

    return 0
}

# Get remaining budget
get_remaining_budget() {
    if [[ "$BUDGET_MAX_COST" == "0" ]]; then
        echo "unlimited"
    else
        echo "$(echo "$BUDGET_MAX_COST - $BUDGET_SESSION_COST" | bc)"
    fi
}

#=============================================================================
# Budget Report
#=============================================================================

# Print a summary of token usage and costs
print_budget_report() {
    echo ""
    echo -e "${BOLD}Budget Report${NC}"
    separator "-" 50

    printf "%-10s %12s %12s %10s\n" "AI" "Input Tok" "Output Tok" "Cost"
    separator "-" 50

    local total_input=0
    local total_output=0

    for ai in claude codex gemini groq; do
        local input="${BUDGET_INPUT_TOKENS[$ai]:-0}"
        local output="${BUDGET_OUTPUT_TOKENS[$ai]:-0}"
        local cost="${BUDGET_COSTS_BY_AI[$ai]:-0}"

        if [[ "$input" -gt 0 ]] || [[ "$output" -gt 0 ]]; then
            printf "%-10s %12d %12d %10s\n" "$ai" "$input" "$output" "\$$cost"
            total_input=$((total_input + input))
            total_output=$((total_output + output))
        fi
    done

    separator "-" 50
    printf "%-10s %12d %12d %10s\n" "TOTAL" "$total_input" "$total_output" "\$$BUDGET_SESSION_COST"

    if [[ "$BUDGET_MAX_COST" != "0" ]]; then
        echo ""
        local remaining
        remaining=$(get_remaining_budget)
        echo -e "Budget: \$$BUDGET_SESSION_COST / \$$BUDGET_MAX_COST (remaining: \$$remaining)"
    fi

    echo ""
}

# Save budget report to file
save_budget_report() {
    local output_file="$1"

    {
        echo "{"
        echo "  \"session_cost\": $BUDGET_SESSION_COST,"
        echo "  \"max_cost\": $BUDGET_MAX_COST,"
        echo "  \"profile\": \"$BUDGET_PROFILE\","
        echo "  \"usage_by_ai\": {"

        local first=true
        for ai in claude codex gemini groq; do
            local input="${BUDGET_INPUT_TOKENS[$ai]:-0}"
            local output="${BUDGET_OUTPUT_TOKENS[$ai]:-0}"
            local cost="${BUDGET_COSTS_BY_AI[$ai]:-0}"

            if [[ "$input" -gt 0 ]] || [[ "$output" -gt 0 ]]; then
                [[ "$first" == "true" ]] || echo ","
                first=false
                echo -n "    \"$ai\": {\"input_tokens\": $input, \"output_tokens\": $output, \"cost\": $cost}"
            fi
        done
        echo ""
        echo "  }"
        echo "}"
    } > "$output_file"
}

log_debug "Budget tracking module loaded"
