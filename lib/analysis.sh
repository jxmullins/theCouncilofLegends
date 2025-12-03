#!/usr/bin/env bash
#
# The Council of Legends - Trend Analysis
# Compare baselines over time, visualize model capability evolution,
# and generate reports on CJ selection patterns
#

COUNCIL_ROOT="${COUNCIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$COUNCIL_ROOT/lib/utils.sh"

#=============================================================================
# Baseline Storage
#=============================================================================

BASELINES_DIR="${COUNCIL_ROOT}/config/baselines"
CJ_HISTORY_FILE="${COUNCIL_ROOT}/config/chief_justice_history.toon"

# Ensure baselines directory exists
ensure_baselines_dir() {
    ensure_dir "$BASELINES_DIR"
}

# Store a baseline with timestamp and model versions
# Args: $1 = baseline_json (from arbiter analysis)
store_baseline() {
    local baseline_json="$1"
    ensure_baselines_dir

    local timestamp
    timestamp=$(date -u +"%Y%m%d_%H%M%S")
    local baseline_file="$BASELINES_DIR/baseline_${timestamp}.toon"

    # Convert JSON baseline to TOON format
    local analyst_id analyst_model analyzed_at methodology
    analyst_id=$(echo "$baseline_json" | jq -r '.analyst.id // "groq"')
    analyst_model=$(echo "$baseline_json" | jq -r '.analyst.model_name // "unknown"')
    analyzed_at=$(echo "$baseline_json" | jq -r '.analyzed_at // ""')
    methodology=$(echo "$baseline_json" | jq -r '.methodology // ""')

    cat > "$baseline_file" <<EOF
; Baseline Assessment - ${analyzed_at}
; Stored: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

timestamp: "${timestamp}"
analyzed_at: "${analyzed_at}"

analyst:
  id: ${analyst_id}
  model: "${analyst_model}"

methodology: '''
${methodology}
'''

; Model versions at time of assessment
model_versions:
  claude: "${CLAUDE_MODEL:-unknown}"
  codex: "${CODEX_MODEL:-unknown}"
  gemini: "${GEMINI_MODEL:-unknown}"

; Rankings data (preserved as JSON for compatibility)
rankings_json: '''
$(echo "$baseline_json" | jq -c '.baseline_rankings')
'''

; Individual AI scores
EOF

    # Add individual AI scores
    echo "$baseline_json" | jq -r '.baseline_rankings[] | "scores[\(.model_id)]:\n  overall: \(.overall_score)\n  cj_suitability: \(.baseline_chief_justice_score)"' >> "$baseline_file"

    log_info "Baseline stored: $baseline_file"
    echo "$baseline_file"
}

#=============================================================================
# Chief Justice History
#=============================================================================

# Record a CJ selection to history
# Args: $1 = debate_id, $2 = topic, $3 = selected_cj, $4 = scores_json
record_cj_selection() {
    local debate_id="$1"
    local topic="$2"
    local selected_cj="$3"
    local scores_json="$4"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Append to history file
    cat >> "$CJ_HISTORY_FILE" <<EOF

; Selection ${timestamp}
selection[${debate_id}]:
  timestamp: "${timestamp}"
  topic: "${topic}"
  selected_cj: ${selected_cj}
  scores_json: '${scores_json}'

EOF

    log_debug "CJ selection recorded: $selected_cj for debate $debate_id"
}

#=============================================================================
# Trend Analysis
#=============================================================================

# List all stored baselines
list_baselines() {
    ensure_baselines_dir

    local baselines=()
    for file in "$BASELINES_DIR"/baseline_*.toon; do
        if [[ -f "$file" ]]; then
            baselines+=("$file")
        fi
    done

    if [[ ${#baselines[@]} -eq 0 ]]; then
        log_warn "No baselines found in $BASELINES_DIR"
        echo "[]"
        return
    fi

    # Sort by timestamp (filename)
    printf '%s\n' "${baselines[@]}" | sort
}

# Get baseline count
get_baseline_count() {
    local count=0
    for file in "$BASELINES_DIR"/baseline_*.toon; do
        if [[ -f "$file" ]]; then
            ((count++))
        fi
    done
    echo "$count"
}

# Extract scores from a baseline file
# Args: $1 = baseline_file
extract_baseline_scores() {
    local baseline_file="$1"

    if [[ ! -f "$baseline_file" ]]; then
        echo "{}"
        return 1
    fi

    # Extract the rankings_json field and parse it
    local rankings_json
    rankings_json=$(grep -A1 "rankings_json:" "$baseline_file" | tail -1 | sed "s/'''//g" | tr -d '\n')

    if [[ -n "$rankings_json" ]]; then
        echo "$rankings_json"
    else
        echo "[]"
    fi
}

# Compare two baselines and show score deltas
# Args: $1 = old_baseline, $2 = new_baseline
compare_baselines() {
    local old_baseline="$1"
    local new_baseline="$2"

    local old_scores new_scores
    old_scores=$(extract_baseline_scores "$old_baseline")
    new_scores=$(extract_baseline_scores "$new_baseline")

    echo "# Baseline Comparison"
    echo ""
    echo "| AI | Old Score | New Score | Delta |"
    echo "|----|-----------|-----------|-------|"

    for ai in claude codex gemini; do
        local old_score new_score delta
        old_score=$(echo "$old_scores" | jq -r ".[] | select(.model_id == \"$ai\") | .overall_score // 0")
        new_score=$(echo "$new_scores" | jq -r ".[] | select(.model_id == \"$ai\") | .overall_score // 0")

        if [[ -n "$old_score" ]] && [[ -n "$new_score" ]]; then
            delta=$(echo "$new_score - $old_score" | bc 2>/dev/null || echo "N/A")
            local delta_str
            if [[ "$delta" != "N/A" ]]; then
                if (( $(echo "$delta > 0" | bc -l) )); then
                    delta_str="+${delta}"
                else
                    delta_str="${delta}"
                fi
            else
                delta_str="N/A"
            fi
            echo "| $(get_ai_name "$ai") | ${old_score:-N/A} | ${new_score:-N/A} | ${delta_str} |"
        fi
    done
}

# Generate trend report across all baselines
generate_trend_report() {
    local baselines
    mapfile -t baselines < <(list_baselines)

    if [[ ${#baselines[@]} -lt 2 ]]; then
        log_warn "Need at least 2 baselines for trend analysis"
        return 1
    fi

    local report_file="$COUNCIL_ROOT/reports/trend_$(date +%Y%m%d_%H%M%S).md"
    ensure_dir "$COUNCIL_ROOT/reports"

    cat > "$report_file" <<EOF
# Council of Legends - Trend Analysis Report

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Baselines Analyzed: ${#baselines[@]}

## Score Evolution Over Time

| Baseline | Date | Claude | Codex | Gemini |
|----------|------|--------|-------|--------|
EOF

    for baseline in "${baselines[@]}"; do
        local basename
        basename=$(basename "$baseline" .toon)
        local date_str="${basename#baseline_}"
        local scores
        scores=$(extract_baseline_scores "$baseline")

        local claude_score codex_score gemini_score
        claude_score=$(echo "$scores" | jq -r '.[] | select(.model_id == "claude") | .overall_score // "N/A"')
        codex_score=$(echo "$scores" | jq -r '.[] | select(.model_id == "codex") | .overall_score // "N/A"')
        gemini_score=$(echo "$scores" | jq -r '.[] | select(.model_id == "gemini") | .overall_score // "N/A"')

        echo "| $basename | $date_str | $claude_score | $codex_score | $gemini_score |" >> "$report_file"
    done

    # Add comparison between first and last baseline
    local first_baseline="${baselines[0]}"
    local last_baseline="${baselines[-1]}"

    cat >> "$report_file" <<EOF

## First vs Latest Comparison

EOF

    compare_baselines "$first_baseline" "$last_baseline" >> "$report_file"

    # Add CJ selection patterns if history exists
    if [[ -f "$CJ_HISTORY_FILE" ]]; then
        cat >> "$report_file" <<EOF

## Chief Justice Selection Patterns

EOF
        # Count CJ selections
        local claude_count codex_count gemini_count
        claude_count=$(grep -c "selected_cj: claude" "$CJ_HISTORY_FILE" 2>/dev/null || echo 0)
        codex_count=$(grep -c "selected_cj: codex" "$CJ_HISTORY_FILE" 2>/dev/null || echo 0)
        gemini_count=$(grep -c "selected_cj: gemini" "$CJ_HISTORY_FILE" 2>/dev/null || echo 0)

        cat >> "$report_file" <<EOF
| AI | Times Selected as CJ |
|----|---------------------|
| Claude | $claude_count |
| Codex | $codex_count |
| Gemini | $gemini_count |
EOF
    fi

    log_success "Trend report generated: $report_file"
    echo "$report_file"
}

# Detect if model versions have changed since last baseline
detect_model_changes() {
    local latest_baseline
    latest_baseline=$(list_baselines | tail -1)

    if [[ -z "$latest_baseline" ]] || [[ ! -f "$latest_baseline" ]]; then
        echo "no_baseline"
        return
    fi

    # Extract model versions from baseline
    local stored_claude stored_codex stored_gemini
    stored_claude=$(grep "claude:" "$latest_baseline" | head -1 | awk -F'"' '{print $2}')
    stored_codex=$(grep "codex:" "$latest_baseline" | head -1 | awk -F'"' '{print $2}')
    stored_gemini=$(grep "gemini:" "$latest_baseline" | head -1 | awk -F'"' '{print $2}')

    local changes=()

    if [[ "${CLAUDE_MODEL:-}" != "$stored_claude" ]] && [[ -n "$stored_claude" ]]; then
        changes+=("claude: $stored_claude -> ${CLAUDE_MODEL:-unknown}")
    fi
    if [[ "${CODEX_MODEL:-}" != "$stored_codex" ]] && [[ -n "$stored_codex" ]]; then
        changes+=("codex: $stored_codex -> ${CODEX_MODEL:-unknown}")
    fi
    if [[ "${GEMINI_MODEL:-}" != "$stored_gemini" ]] && [[ -n "$stored_gemini" ]]; then
        changes+=("gemini: $stored_gemini -> ${GEMINI_MODEL:-unknown}")
    fi

    if [[ ${#changes[@]} -gt 0 ]]; then
        echo "changed"
        for change in "${changes[@]}"; do
            echo "  - $change"
        done
    else
        echo "unchanged"
    fi
}

# Prompt user for re-evaluation if model changed
prompt_for_reevaluation() {
    local change_status
    change_status=$(detect_model_changes)

    if [[ "$change_status" == "changed" ]]; then
        echo ""
        log_warn "Model version changes detected since last baseline:"
        detect_model_changes | tail -n +2
        echo ""
        echo "Consider running './assess.sh --analyze' to update baseline scores."
        echo ""
        return 0
    elif [[ "$change_status" == "no_baseline" ]]; then
        log_info "No previous baseline found. Run './assess.sh --analyze' to create one."
        return 1
    fi

    return 0
}

#=============================================================================
# CLI Interface
#=============================================================================

analysis_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        list)
            echo "Stored Baselines:"
            list_baselines
            ;;
        count)
            echo "Baseline count: $(get_baseline_count)"
            ;;
        compare)
            if [[ $# -lt 2 ]]; then
                log_error "Usage: analysis compare <old_baseline> <new_baseline>"
                return 1
            fi
            compare_baselines "$1" "$2"
            ;;
        report)
            generate_trend_report
            ;;
        check-models)
            prompt_for_reevaluation
            ;;
        help|*)
            echo "Usage: source lib/analysis.sh && analysis_cli <command>"
            echo ""
            echo "Commands:"
            echo "  list          List all stored baselines"
            echo "  count         Show number of baselines"
            echo "  compare       Compare two baselines"
            echo "  report        Generate trend report"
            echo "  check-models  Check if model versions have changed"
            ;;
    esac
}
