#!/usr/bin/env bash
#
# The Council of Legends - Assessment & Anonymization Module
# Handles self-assessment, blind peer review, and Chief Justice selection
#

# Source utils if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${UTILS_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/utils.sh"
    export UTILS_LOADED=true
fi

#=============================================================================
# Constants
#=============================================================================

# Anonymous IDs for blind peer review
declare -a ANON_IDS=("AI-A" "AI-B" "AI-C")

# Council member IDs (core debate participants)
declare -a COUNCIL_MEMBERS=("claude" "codex" "gemini")

# Team member IDs (includes optional arbiter for team mode)
declare -a TEAM_MEMBERS=("claude" "codex" "gemini")
declare -a TEAM_MEMBERS_WITH_ARBITER=("claude" "codex" "gemini" "arbiter")

#=============================================================================
# Anonymization Functions
#=============================================================================

# Generate a random anonymization mapping
# Shuffles council members and assigns to AI-A, AI-B, AI-C
# Returns: JSON object with mappings
generate_anonymization_map() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create a shuffled copy of council members
    local shuffled=()
    local members=("${COUNCIL_MEMBERS[@]}")

    while [[ ${#members[@]} -gt 0 ]]; do
        # Get random index
        local rand_idx=$((RANDOM % ${#members[@]}))
        shuffled+=("${members[$rand_idx]}")
        # Remove selected element
        members=("${members[@]:0:$rand_idx}" "${members[@]:$((rand_idx + 1))}")
    done

    # Build JSON mapping
    cat <<EOF
{
  "generated_at": "$timestamp",
  "mappings": {
    "${shuffled[0]}": "AI-A",
    "${shuffled[1]}": "AI-B",
    "${shuffled[2]}": "AI-C"
  }
}
EOF
}

# Get anonymous ID for a council member
# Args: $1 = council member id (claude, codex, gemini)
#       $2 = mapping JSON file path
# Returns: Anonymous ID (AI-A, AI-B, or AI-C)
get_anonymous_id() {
    local member_id="$1"
    local mapping_file="$2"

    if [[ ! -f "$mapping_file" ]]; then
        log_error "Mapping file not found: $mapping_file"
        return 1
    fi

    # Extract the anonymous ID for this member
    local anon_id
    anon_id=$(jq -r ".mappings[\"$member_id\"]" "$mapping_file")

    if [[ "$anon_id" == "null" ]] || [[ -z "$anon_id" ]]; then
        log_error "No mapping found for member: $member_id"
        return 1
    fi

    echo "$anon_id"
}

# Get real council member ID from anonymous ID
# Args: $1 = anonymous id (AI-A, AI-B, AI-C)
#       $2 = mapping JSON file path
# Returns: Real member ID (claude, codex, gemini)
get_real_id() {
    local anon_id="$1"
    local mapping_file="$2"

    if [[ ! -f "$mapping_file" ]]; then
        log_error "Mapping file not found: $mapping_file"
        return 1
    fi

    # Reverse lookup - find the key with this value
    local real_id
    real_id=$(jq -r ".mappings | to_entries[] | select(.value == \"$anon_id\") | .key" "$mapping_file")

    if [[ -z "$real_id" ]]; then
        log_error "No member found for anonymous ID: $anon_id"
        return 1
    fi

    echo "$real_id"
}

# Get list of anonymous IDs for OTHER council members (for peer review)
# Args: $1 = council member id (the reviewer)
#       $2 = mapping JSON file path
# Returns: Space-separated list of anonymous IDs to review
get_peer_anonymous_ids() {
    local reviewer_id="$1"
    local mapping_file="$2"

    if [[ ! -f "$mapping_file" ]]; then
        log_error "Mapping file not found: $mapping_file"
        return 1
    fi

    # Get all anonymous IDs except the reviewer's own
    local reviewer_anon_id
    reviewer_anon_id=$(get_anonymous_id "$reviewer_id" "$mapping_file")

    local peer_ids=()
    for anon_id in "${ANON_IDS[@]}"; do
        if [[ "$anon_id" != "$reviewer_anon_id" ]]; then
            peer_ids+=("$anon_id")
        fi
    done

    echo "${peer_ids[*]}"
}

#=============================================================================
# Self-Assessment Anonymization
#=============================================================================

# Anonymize a self-assessment for peer review
# Strips identifying information and replaces with anonymous ID
# Args: $1 = path to self-assessment JSON
#       $2 = mapping JSON file path
#       $3 = output path for anonymized version
anonymize_self_assessment() {
    local assessment_file="$1"
    local mapping_file="$2"
    local output_file="$3"

    if [[ ! -f "$assessment_file" ]]; then
        log_error "Assessment file not found: $assessment_file"
        return 1
    fi

    # Get the member ID from the assessment
    local member_id
    member_id=$(jq -r '.model.id' "$assessment_file")

    # Get their anonymous ID
    local anon_id
    anon_id=$(get_anonymous_id "$member_id" "$mapping_file")

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Create anonymized version - remove identifying info, add anonymous ID
    jq --arg anon_id "$anon_id" '{
        anonymous_id: $anon_id,
        submitted_at: .submitted_at,
        categories: .categories,
        overall_self_rating: .overall_self_rating,
        strengths_summary: .strengths_summary,
        weaknesses_summary: .weaknesses_summary
    }' "$assessment_file" > "$output_file"

    log_debug "Anonymized assessment for $member_id -> $anon_id"
}

# Anonymize all self-assessments in a directory
# Args: $1 = assessment directory (containing self_assessment_*.json files)
#       $2 = mapping JSON file path
#       $3 = output directory for anonymized versions
anonymize_all_assessments() {
    local assessment_dir="$1"
    local mapping_file="$2"
    local output_dir="$3"

    ensure_dir "$output_dir"

    local count=0
    for member in "${COUNCIL_MEMBERS[@]}"; do
        local assessment_file="$assessment_dir/self_assessment_${member}.json"
        if [[ -f "$assessment_file" ]]; then
            local anon_id
            anon_id=$(get_anonymous_id "$member" "$mapping_file")
            local output_file="$output_dir/anonymous_${anon_id}.json"

            anonymize_self_assessment "$assessment_file" "$mapping_file" "$output_file"
            count=$((count + 1))
        fi
    done

    log_info "Anonymized $count self-assessments"
}

#=============================================================================
# Peer Review Preparation
#=============================================================================

# Prepare peer review package for a specific reviewer
# Contains anonymized assessments of OTHER council members only
# Args: $1 = reviewer member id (claude, codex, gemini)
#       $2 = anonymized assessments directory
#       $3 = mapping JSON file path
#       $4 = output file for the review package
prepare_peer_review_package() {
    local reviewer_id="$1"
    local anon_dir="$2"
    local mapping_file="$3"
    local output_file="$4"

    # Get the reviewer's own anonymous ID (to exclude from package)
    local reviewer_anon_id
    reviewer_anon_id=$(get_anonymous_id "$reviewer_id" "$mapping_file")

    # Build array of peer assessments
    local peer_assessments="[]"

    for anon_id in "${ANON_IDS[@]}"; do
        if [[ "$anon_id" != "$reviewer_anon_id" ]]; then
            local anon_file="$anon_dir/anonymous_${anon_id}.json"
            if [[ -f "$anon_file" ]]; then
                # Add this assessment to the array
                peer_assessments=$(echo "$peer_assessments" | jq --slurpfile assessment "$anon_file" '. + $assessment')
            fi
        fi
    done

    # Create the review package
    cat > "$output_file" <<EOF
{
  "reviewer_instructions": "Review each anonymous council member's self-assessment. Rate them on overall capability and suitability for Chief Justice. You are reviewing members: $(get_peer_anonymous_ids "$reviewer_id" "$mapping_file")",
  "peer_assessments": $peer_assessments
}
EOF

    log_debug "Prepared peer review package for $reviewer_id (excluding $reviewer_anon_id)"
}

#=============================================================================
# De-anonymization (Post Review)
#=============================================================================

# De-anonymize peer review results
# Converts anonymous IDs back to real member IDs for final analysis
# Args: $1 = peer review results JSON file
#       $2 = mapping JSON file path
#       $3 = output file for de-anonymized version
deanonymize_peer_review() {
    local review_file="$1"
    local mapping_file="$2"
    local output_file="$3"

    if [[ ! -f "$review_file" ]]; then
        log_error "Review file not found: $review_file"
        return 1
    fi

    # Read the mapping
    local mapping
    mapping=$(cat "$mapping_file")

    # Process each review and replace anonymous IDs with real IDs
    jq --argjson mapping "$mapping" '
        # Create reverse mapping (AI-A -> claude, etc.)
        ($mapping.mappings | to_entries | map({(.value): .key}) | add) as $reverse |

        # Replace anonymous_id in each review
        .reviews |= map(
            .anonymous_id as $anon |
            . + { "real_id": $reverse[$anon] }
        )
    ' "$review_file" > "$output_file"

    log_debug "De-anonymized peer review results"
}

# De-anonymize all peer reviews and merge into final analysis
# Args: $1 = peer reviews directory
#       $2 = mapping JSON file path
#       $3 = output directory
deanonymize_all_reviews() {
    local reviews_dir="$1"
    local mapping_file="$2"
    local output_dir="$3"

    ensure_dir "$output_dir"

    for member in "${COUNCIL_MEMBERS[@]}"; do
        local review_file="$reviews_dir/peer_review_${member}.json"
        if [[ -f "$review_file" ]]; then
            local output_file="$output_dir/peer_review_${member}_revealed.json"
            deanonymize_peer_review "$review_file" "$mapping_file" "$output_file"
        fi
    done

    log_info "De-anonymized all peer reviews"
}

#=============================================================================
# Validation Functions
#=============================================================================

# Validate that anonymization mapping is complete
# Args: $1 = mapping JSON file path
validate_mapping() {
    local mapping_file="$1"

    if [[ ! -f "$mapping_file" ]]; then
        log_error "Mapping file not found: $mapping_file"
        return 1
    fi

    # Check all council members are mapped
    for member in "${COUNCIL_MEMBERS[@]}"; do
        local anon_id
        anon_id=$(jq -r ".mappings[\"$member\"]" "$mapping_file")
        if [[ "$anon_id" == "null" ]] || [[ -z "$anon_id" ]]; then
            log_error "Missing mapping for: $member"
            return 1
        fi
    done

    # Check all anonymous IDs are used
    for anon_id in "${ANON_IDS[@]}"; do
        local found
        found=$(jq -r ".mappings | to_entries[] | select(.value == \"$anon_id\") | .key" "$mapping_file")
        if [[ -z "$found" ]]; then
            log_error "Anonymous ID not assigned: $anon_id"
            return 1
        fi
    done

    log_debug "Mapping validation passed"
    return 0
}

# Ensure reviewer cannot see their own assessment
# Args: $1 = reviewer member id
#       $2 = review package file
#       $3 = mapping JSON file path
validate_no_self_review() {
    local reviewer_id="$1"
    local package_file="$2"
    local mapping_file="$3"

    # Get reviewer's anonymous ID
    local reviewer_anon_id
    reviewer_anon_id=$(get_anonymous_id "$reviewer_id" "$mapping_file")

    # Check if package contains reviewer's own assessment
    local contains_self
    contains_self=$(jq --arg anon "$reviewer_anon_id" '.peer_assessments[] | select(.anonymous_id == $anon)' "$package_file")

    if [[ -n "$contains_self" ]]; then
        log_error "SECURITY: Review package for $reviewer_id contains their own assessment!"
        return 1
    fi

    log_debug "Self-review validation passed for $reviewer_id"
    return 0
}

#=============================================================================
# Assessment Workflow Helpers
#=============================================================================

# Initialize a new assessment cycle
# Args: $1 = base directory for this assessment
#       $2 = trigger type (model_change, user_initiated, etc.)
#       $3 = trigger details (optional)
init_assessment_cycle() {
    local base_dir="$1"
    local trigger="$2"
    local trigger_details="${3:-}"

    local assessment_id
    assessment_id=$(timestamp)

    local assessment_dir="$base_dir/assessments/$assessment_id"
    ensure_dir "$assessment_dir"
    ensure_dir "$assessment_dir/self_assessments"
    ensure_dir "$assessment_dir/anonymized"
    ensure_dir "$assessment_dir/peer_reviews"
    ensure_dir "$assessment_dir/revealed"

    # Generate and save anonymization mapping
    local mapping_file="$assessment_dir/anonymization_map.json"
    generate_anonymization_map > "$mapping_file"

    # Validate the mapping
    validate_mapping "$mapping_file" || return 1

    # Create assessment metadata
    cat > "$assessment_dir/metadata.json" <<EOF
{
  "assessment_id": "$assessment_id",
  "questionnaire_version": "1.1",
  "trigger": "$trigger",
  "trigger_details": "$trigger_details",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "in_progress"
}
EOF

    log_info "Initialized assessment cycle: $assessment_id" >&2
    echo "$assessment_dir"
}

# Get the status of an assessment cycle
# Args: $1 = assessment directory
get_assessment_status() {
    local assessment_dir="$1"

    if [[ ! -f "$assessment_dir/metadata.json" ]]; then
        echo "not_found"
        return
    fi

    jq -r '.status' "$assessment_dir/metadata.json"
}

# Update assessment status
# Args: $1 = assessment directory
#       $2 = new status
update_assessment_status() {
    local assessment_dir="$1"
    local new_status="$2"

    local metadata_file="$assessment_dir/metadata.json"

    jq --arg status "$new_status" '.status = $status' "$metadata_file" > "${metadata_file}.tmp"
    mv "${metadata_file}.tmp" "$metadata_file"

    log_debug "Updated assessment status to: $new_status"
}

#=============================================================================
# Display Functions
#=============================================================================

# Display anonymization mapping (for debugging/admin only)
display_mapping() {
    local mapping_file="$1"

    echo ""
    echo -e "${YELLOW}Anonymization Mapping (CONFIDENTIAL)${NC}"
    separator "-" 40

    for member in "${COUNCIL_MEMBERS[@]}"; do
        local anon_id
        anon_id=$(get_anonymous_id "$member" "$mapping_file")
        local member_name
        member_name=$(get_ai_name "$member")
        printf "  %-10s -> %s\n" "$member_name" "$anon_id"
    done

    separator "-" 40
    echo ""
}

# Get AI display name (if not defined in utils.sh)
if ! declare -f get_ai_name > /dev/null; then
    get_ai_name() {
        local ai="$1"
        case "$ai" in
            claude) echo "Claude" ;;
            codex)  echo "Codex" ;;
            gemini) echo "Gemini" ;;
            *)      echo "$ai" ;;
        esac
    }
fi

# Get AI color (if not defined in utils.sh)
if ! declare -f get_ai_color > /dev/null; then
    get_ai_color() {
        local ai="$1"
        case "$ai" in
            claude) echo "$CLAUDE_COLOR" ;;
            codex)  echo "$CODEX_COLOR" ;;
            gemini) echo "$GEMINI_COLOR" ;;
            *)      echo "$WHITE" ;;
        esac
    }
fi

#=============================================================================
# JSON Extraction Helper
#=============================================================================

# Extract JSON from AI response (handles markdown code blocks)
# Args: $1 = file containing raw response
# Returns: Clean JSON on stdout, empty string if invalid
extract_json_from_response() {
    local response_file="$1"

    if [[ ! -f "$response_file" ]]; then
        return 1
    fi

    local raw_response
    raw_response=$(cat "$response_file")

    local json_response=""
    local first_line
    first_line=$(echo "$raw_response" | head -1)

    # Try to extract JSON from markdown code blocks
    if [[ "$first_line" == '```json' ]] || [[ "$first_line" == '```' ]]; then
        # Skip first line, remove last line if it's closing backticks
        local total_lines
        total_lines=$(echo "$raw_response" | wc -l | tr -d ' ')
        local last_line
        last_line=$(echo "$raw_response" | tail -1)

        if [[ "$last_line" == '```' ]]; then
            # Skip first and last line
            json_response=$(echo "$raw_response" | tail -n +2 | sed '$d')
        else
            # Just skip first line
            json_response=$(echo "$raw_response" | tail -n +2)
        fi
    elif [[ "$first_line" == '{'* ]]; then
        # Response starts with JSON object
        json_response="$raw_response"
    elif [[ "$first_line" == '['* ]]; then
        # Response starts with JSON array
        json_response="$raw_response"
    else
        # Try to find JSON object embedded in response
        json_response=$(echo "$raw_response" | sed -n '/^{/,/^}/p')
    fi

    # Validate it's valid JSON
    if [[ -n "$json_response" ]] && echo "$json_response" | jq . >/dev/null 2>&1; then
        echo "$json_response"
    else
        # Try to fix common JSON issues from LLM output
        local fixed_response="$json_response"

        # Fix 1: Extra quotes at end of strings (e.g., .""" -> .")
        fixed_response=$(echo "$fixed_response" | sed 's/"""/"/g')

        # Fix 2: Missing } before ] at end of array items (e.g., ."] -> ."}])
        # Must apply to ALL lines, not just the last
        fixed_response=$(echo "$fixed_response" | sed 's/"\]$/"}]/g')

        # Fix 2b: After adding the }], there may be duplicate ] on next line
        # Pattern: "}]\n  ]," -> "}]\n  ,"  (remove duplicate ])
        fixed_response=$(echo "$fixed_response" | sed -e ':a' -e 'N' -e '$!ba' -e 's/}\]\n *\],/}],\n/g')

        # Fix 2c: Also handle case where next line is "}," (stray })
        # Pattern: "}]\n  }," -> "}]\n  ,"
        fixed_response=$(echo "$fixed_response" | sed -e ':a' -e 'N' -e '$!ba' -e 's/}\]\n *},/}],\n/g')

        # Fix 3: Missing closing braces/brackets - try to add them
        local open_braces close_braces open_brackets close_brackets
        open_braces=$(echo "$fixed_response" | grep -o '{' | wc -l | tr -d ' ')
        close_braces=$(echo "$fixed_response" | grep -o '}' | wc -l | tr -d ' ')
        open_brackets=$(echo "$fixed_response" | grep -o '\[' | wc -l | tr -d ' ')
        close_brackets=$(echo "$fixed_response" | grep -o '\]' | wc -l | tr -d ' ')

        # Add missing closing braces
        while [[ $close_braces -lt $open_braces ]]; do
            fixed_response="${fixed_response}}"
            close_braces=$((close_braces + 1))
        done

        # Add missing closing brackets
        while [[ $close_brackets -lt $open_brackets ]]; do
            fixed_response="${fixed_response}]"
            close_brackets=$((close_brackets + 1))
        done

        if echo "$fixed_response" | jq . >/dev/null 2>&1; then
            log_debug "Fixed JSON syntax issues"
            echo "$fixed_response"
        else
            # Return empty to indicate failure
            echo ""
        fi
    fi
}

#=============================================================================
# Questionnaire Runner
#=============================================================================

# Build the prompt for an AI to complete the self-assessment questionnaire
# Args: $1 = path to questionnaire (TOON or JSON)
# Returns: Prompt text for the AI
build_questionnaire_prompt() {
    local questionnaire_file="$1"

    if [[ ! -f "$questionnaire_file" ]]; then
        log_error "Questionnaire file not found: $questionnaire_file"
        return 1
    fi

    # Read questionnaire (convert TOON to JSON if needed)
    local questionnaire
    if [[ "$questionnaire_file" == *.toon ]]; then
        # Use TOON util to decode to JSON
        local toon_util="${COUNCIL_ROOT:-$SCRIPT_DIR/..}/lib/toon_util.py"
        questionnaire=$("$toon_util" decode "$questionnaire_file" 2>/dev/null)
    else
        questionnaire=$(cat "$questionnaire_file")
    fi

    # Build the prompt
    cat <<'PROMPT_START'
You are completing a self-assessment questionnaire. Be honest and accurate - these ratings will be peer-reviewed by other AI systems.

IMPORTANT: You must respond with ONLY valid JSON. No markdown, no explanations, no code blocks - just the raw JSON object.

Rate yourself 1-10 on each capability:
- 1 = No capability
- 3 = Basic awareness
- 5 = Competent
- 7 = Proficient
- 10 = Expert

Here is the questionnaire structure:
PROMPT_START

    echo "$questionnaire" | jq -c '.'

    cat <<'PROMPT_END'

Respond with a JSON object in this exact format:
{
  "categories": [
    {
      "category_id": "reasoning_logic",
      "items": [
        { "item_id": "formal_deduction", "rating": 8, "notes": "optional brief note" }
      ]
    },
    {
      "category_id": "programming_languages",
      "subcategories": [
        {
          "subcategory_id": "legacy_classic",
          "items": [
            { "item_id": "c", "rating": 7 }
          ]
        }
      ]
    }
  ],
  "overall_self_rating": 7,
  "strengths_summary": "Brief summary of top 3-5 strengths",
  "weaknesses_summary": "Brief summary of 2-3 areas for improvement"
}

Complete the assessment for ALL categories and ALL items. Output ONLY the JSON, no other text.
PROMPT_END
}

# Run the questionnaire for a single AI
# Args: $1 = AI id (claude, codex, gemini)
#       $2 = questionnaire file path
#       $3 = output file path
run_questionnaire_for_ai() {
    local ai_id="$1"
    local questionnaire_file="$2"
    local output_file="$3"

    local ai_name
    ai_name=$(get_ai_name "$ai_id")

    log_info "Running questionnaire for $ai_name..."

    # Build the prompt
    local prompt
    prompt=$(build_questionnaire_prompt "$questionnaire_file")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to build questionnaire prompt"
        return 1
    fi

    # Create temp file for raw response
    local temp_response="${output_file}.raw"

    # Source the appropriate adapter
    local adapter_file="$SCRIPT_DIR/adapters/${ai_id}_adapter.sh"
    if [[ ! -f "$adapter_file" ]]; then
        log_error "Adapter not found: $adapter_file"
        return 1
    fi
    source "$adapter_file"

    # Invoke the AI
    local invoke_func="invoke_${ai_id}"
    if ! $invoke_func "$prompt" "$temp_response"; then
        log_error "$ai_name failed to complete questionnaire"
        return 1
    fi

    # Extract JSON from response (handle markdown code blocks if present)
    local raw_response
    raw_response=$(cat "$temp_response")

    # Try to extract JSON from markdown code blocks if present
    local json_response
    if echo "$raw_response" | grep -q '```json' 2>/dev/null; then
        json_response=$(echo "$raw_response" | sed -n '/```json/,/```/p' | sed '1d;$d')
    elif echo "$raw_response" | grep -q '```' 2>/dev/null; then
        json_response=$(echo "$raw_response" | sed -n '/```/,/```/p' | sed '1d;$d')
    else
        json_response="$raw_response"
    fi

    # Validate it's valid JSON
    if ! echo "$json_response" | jq . >/dev/null 2>&1; then
        log_error "$ai_name returned invalid JSON"
        log_debug "Raw response: $raw_response"
        # Save the raw response for debugging
        echo "$raw_response" > "${output_file}.invalid"
        return 1
    fi

    # Get model info based on AI
    local model_name
    case "$ai_id" in
        claude) model_name="${CLAUDE_MODEL:-claude-sonnet-4-20250514}" ;;
        codex)  model_name="${CODEX_MODEL:-codex-default}" ;;
        gemini) model_name="${GEMINI_MODEL:-gemini-2.0-flash}" ;;
        *)      model_name="unknown" ;;
    esac

    # Wrap with metadata
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg model_id "$ai_id" \
        --arg model_name "$model_name" \
        --arg submitted_at "$timestamp" \
        --argjson assessment "$json_response" \
        '{
            model: {
                id: $model_id,
                model_name: $model_name
            },
            submitted_at: $submitted_at,
            categories: $assessment.categories,
            overall_self_rating: $assessment.overall_self_rating,
            strengths_summary: $assessment.strengths_summary,
            weaknesses_summary: $assessment.weaknesses_summary
        }' > "$output_file"

    # Cleanup temp file
    rm -f "$temp_response"

    log_success "$ai_name completed questionnaire"
    return 0
}

# Run questionnaire for all council members
# Args: $1 = assessment directory (from init_assessment_cycle)
#       $2 = questionnaire file path
run_all_questionnaires() {
    local assessment_dir="$1"
    local questionnaire_file="$2"

    local self_assessments_dir="$assessment_dir/self_assessments"
    ensure_dir "$self_assessments_dir"

    local success_count=0
    local fail_count=0

    for member in "${COUNCIL_MEMBERS[@]}"; do
        local output_file="$self_assessments_dir/self_assessment_${member}.json"

        if run_questionnaire_for_ai "$member" "$questionnaire_file" "$output_file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    log_info "Questionnaire results: $success_count succeeded, $fail_count failed"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi

    # Update assessment status
    update_assessment_status "$assessment_dir" "self_assessment_complete"

    return 0
}

#=============================================================================
# Peer Review Runner
#=============================================================================

# Build prompt for peer review
# Args: $1 = review package file (contains anonymized assessments to review)
build_peer_review_prompt() {
    local package_file="$1"

    if [[ ! -f "$package_file" ]]; then
        log_error "Review package not found: $package_file"
        return 1
    fi

    local package
    package=$(cat "$package_file")

    cat <<'PROMPT_START'
You are reviewing anonymized self-assessments from other AI council members.

IMPORTANT: You must respond with ONLY valid JSON. No markdown, no explanations, no code blocks.

Review each assessment and provide your evaluation. Be fair but critical - look for:
- Overclaiming (ratings that seem too high)
- Underclaiming (false modesty)
- Inconsistencies between ratings and stated strengths/weaknesses
- Areas where you think their assessment is accurate

Here are the assessments to review:
PROMPT_START

    echo "$package" | jq -c '.'

    cat <<'PROMPT_END'

For each anonymous AI (AI-A, AI-B, or AI-C in the package), provide:
{
  "reviews": [
    {
      "anonymous_id": "AI-A",
      "overall_ranking": 7,
      "category_rankings": [
        { "category_id": "reasoning_logic", "ranking": 8, "reasoning": "Ratings seem accurate" },
        { "category_id": "programming_languages", "ranking": 6, "reasoning": "May be overclaiming on some languages" }
      ],
      "strengths_observed": "Strong logical reasoning, honest about limitations",
      "weaknesses_observed": "Some overclaiming in domain knowledge",
      "chief_justice_suitability": {
        "rating": 7,
        "reasoning": "Good balance of skills, shows objectivity"
      }
    }
  ]
}

Review ALL assessments in the package. Output ONLY the JSON.
PROMPT_END
}

# Run peer review for a single AI
# Args: $1 = reviewer AI id
#       $2 = review package file
#       $3 = output file
run_peer_review_for_ai() {
    local reviewer_id="$1"
    local package_file="$2"
    local output_file="$3"

    local reviewer_name
    reviewer_name=$(get_ai_name "$reviewer_id")

    log_info "$reviewer_name is reviewing peers..."

    # Build the prompt
    local prompt
    prompt=$(build_peer_review_prompt "$package_file")

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Create temp file for raw response
    local temp_response="${output_file}.raw"

    # Source the appropriate adapter
    local adapter_file="$SCRIPT_DIR/adapters/${reviewer_id}_adapter.sh"
    source "$adapter_file"

    # Invoke the AI
    local invoke_func="invoke_${reviewer_id}"
    if ! $invoke_func "$prompt" "$temp_response"; then
        log_error "$reviewer_name failed to complete peer review"
        return 1
    fi

    # Extract JSON from response
    local raw_response
    raw_response=$(cat "$temp_response")

    local json_response
    if echo "$raw_response" | grep -q '```json'; then
        json_response=$(echo "$raw_response" | sed -n '/```json/,/```/p' | sed '1d;$d')
    elif echo "$raw_response" | grep -q '```'; then
        json_response=$(echo "$raw_response" | sed -n '/```/,/```/p' | sed '1d;$d')
    else
        json_response="$raw_response"
    fi

    # Validate JSON
    if ! echo "$json_response" | jq . >/dev/null 2>&1; then
        log_error "$reviewer_name returned invalid JSON for peer review"
        echo "$raw_response" > "${output_file}.invalid"
        return 1
    fi

    # Get model info
    local model_name
    case "$reviewer_id" in
        claude) model_name="${CLAUDE_MODEL:-claude-sonnet-4-20250514}" ;;
        codex)  model_name="${CODEX_MODEL:-codex-default}" ;;
        gemini) model_name="${GEMINI_MODEL:-gemini-2.0-flash}" ;;
        *)      model_name="unknown" ;;
    esac

    # Wrap with metadata
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg reviewer_id "$reviewer_id" \
        --arg model_name "$model_name" \
        --arg submitted_at "$timestamp" \
        --argjson review "$json_response" \
        '{
            reviewer: {
                id: $reviewer_id,
                model_name: $model_name
            },
            submitted_at: $submitted_at,
            reviews: $review.reviews
        }' > "$output_file"

    rm -f "$temp_response"

    log_success "$reviewer_name completed peer review"
    return 0
}

# Run peer reviews for all council members
# Args: $1 = assessment directory
run_all_peer_reviews() {
    local assessment_dir="$1"

    local anon_dir="$assessment_dir/anonymized"
    local peer_reviews_dir="$assessment_dir/peer_reviews"
    local mapping_file="$assessment_dir/anonymization_map.json"

    ensure_dir "$peer_reviews_dir"

    # First, anonymize all self-assessments
    log_info "Anonymizing self-assessments for peer review..."
    anonymize_all_assessments "$assessment_dir/self_assessments" "$mapping_file" "$anon_dir"

    local success_count=0
    local fail_count=0

    for reviewer in "${COUNCIL_MEMBERS[@]}"; do
        # Prepare review package (excludes reviewer's own assessment)
        local package_file="$peer_reviews_dir/package_${reviewer}.json"
        prepare_peer_review_package "$reviewer" "$anon_dir" "$mapping_file" "$package_file"

        # Validate no self-review
        if ! validate_no_self_review "$reviewer" "$package_file" "$mapping_file"; then
            log_error "Security validation failed for $reviewer"
            fail_count=$((fail_count + 1))
            continue
        fi

        # Run the review
        local output_file="$peer_reviews_dir/peer_review_${reviewer}.json"
        if run_peer_review_for_ai "$reviewer" "$package_file" "$output_file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    log_info "Peer review results: $success_count succeeded, $fail_count failed"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi

    # De-anonymize the results
    log_info "De-anonymizing peer review results..."
    deanonymize_all_reviews "$peer_reviews_dir" "$mapping_file" "$assessment_dir/revealed"

    # Update status
    update_assessment_status "$assessment_dir" "peer_review_complete"

    return 0
}

#=============================================================================
# Full Assessment Workflow
#=============================================================================

# Run complete assessment cycle
# Args: $1 = base directory
#       $2 = trigger type
#       $3 = trigger details (optional)
#       $4 = questionnaire file (optional, defaults to config/questionnaire_v1.toon or .json)
run_full_assessment() {
    local base_dir="$1"
    local trigger="$2"
    local trigger_details="${3:-}"
    # Prefer TOON, fall back to JSON
    local questionnaire_file="${4:-}"
    if [[ -z "$questionnaire_file" ]]; then
        if [[ -f "$base_dir/config/questionnaire_v1.toon" ]]; then
            questionnaire_file="$base_dir/config/questionnaire_v1.toon"
        else
            questionnaire_file="$base_dir/config/questionnaire_v1.json"
        fi
    fi

    header "Council Assessment Cycle"

    # Initialize the assessment
    local assessment_dir
    assessment_dir=$(init_assessment_cycle "$base_dir" "$trigger" "$trigger_details")

    if [[ $? -ne 0 ]] || [[ -z "$assessment_dir" ]]; then
        log_error "Failed to initialize assessment cycle"
        return 1
    fi

    log_info "Assessment directory: $assessment_dir"

    # Display the anonymization mapping (debug only)
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        display_mapping "$assessment_dir/anonymization_map.json"
    fi

    # Phase 1: Self-assessments
    ai_header "council" "Self-Assessment Phase"
    if ! run_all_questionnaires "$assessment_dir" "$questionnaire_file"; then
        log_error "Self-assessment phase failed"
        return 1
    fi

    # Phase 2: Peer reviews
    ai_header "council" "Peer Review Phase"
    if ! run_all_peer_reviews "$assessment_dir"; then
        log_error "Peer review phase failed"
        return 1
    fi

    # Phase 3: Baseline analysis (if GROQ_API_KEY is set)
    if [[ -n "${GROQ_API_KEY:-}" ]]; then
        ai_header "groq" "Baseline Analysis"
        if ! run_baseline_analysis "$assessment_dir"; then
            log_warn "Baseline analysis failed (non-fatal)"
            # Don't fail the whole assessment if arbiter is unavailable
        fi
    else
        log_warn "GROQ_API_KEY not set - skipping baseline analysis"
        log_info "Set GROQ_API_KEY to enable arbiter baseline scoring"
    fi

    log_success "Assessment cycle complete: $assessment_dir"
    echo "$assessment_dir"
}

#=============================================================================
# Arbiter Baseline Analysis
#=============================================================================

# Build the baseline analysis prompt (compact version for API limits)
# Args: $1 = assessment directory
build_baseline_analysis_prompt() {
    local assessment_dir="$1"

    # Prefer TOON, fall back to JSON
    local questionnaire_file
    if [[ -f "$COUNCIL_ROOT/config/questionnaire_v1.toon" ]]; then
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.toon"
    else
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.json"
    fi

    # Build questionnaire categories list (decode TOON if needed)
    local categories
    if [[ "$questionnaire_file" == *.toon ]]; then
        local toon_util="${COUNCIL_ROOT:-$SCRIPT_DIR/..}/lib/toon_util.py"
        categories=$("$toon_util" decode "$questionnaire_file" 2>/dev/null | jq -r '.categories[] | .id' | tr '\n' ', ')
    else
        categories=$(jq -r '.categories[] | .id' "$questionnaire_file" | tr '\n' ', ')
    fi

    # Get anonymization map
    local anon_map
    anon_map=$(cat "$assessment_dir/anonymization_map.json")

    # Build compact summaries of self-assessments
    local self_summaries=""
    for f in "$assessment_dir/anonymized/anonymous_AI-"*.json; do
        if [[ -f "$f" ]]; then
            local anon_id
            anon_id=$(jq -r '.anonymous_id' "$f")
            local overall
            overall=$(jq -r '.overall_self_rating // "N/A"' "$f")
            local strengths
            strengths=$(jq -r '.strengths_summary // "N/A"' "$f" | cut -c1-150)
            local weaknesses
            weaknesses=$(jq -r '.weaknesses_summary // "N/A"' "$f" | cut -c1-150)
            self_summaries+="$anon_id: overall=$overall, strengths=\"$strengths\", weaknesses=\"$weaknesses\"
"
        fi
    done

    # Build compact summaries of peer reviews
    local peer_summaries=""
    for f in "$assessment_dir/peer_reviews/peer_review_"*.json; do
        if [[ -f "$f" ]]; then
            local reviewer
            reviewer=$(jq -r '.reviewer.id' "$f")
            # Extract CJ ratings for each reviewed AI
            local reviews
            reviews=$(jq -r '.reviews[] | "\(.anonymous_id): overall=\(.overall_ranking), cj=\(.chief_justice_suitability.rating // "N/A")"' "$f" | tr '\n' '; ')
            peer_summaries+="$reviewer reviewed: $reviews
"
        fi
    done

    # Build compact prompt
    cat <<EOF
Analyze council member assessments and generate baseline scores.

ANONYMIZATION MAP:
$anon_map

CATEGORIES: $categories

SELF-ASSESSMENTS (summary):
$self_summaries

PEER REVIEWS (summary):
$peer_summaries

Generate JSON with baseline rankings. For each council member (use real IDs: claude, codex, gemini):
- overall_rank (1-3)
- overall_score (1.0-10.0)
- category_scores (object with category_id keys, numeric values)
- baseline_chief_justice_score (1.0-10.0)
- strengths (brief)
- weaknesses (brief)

Weight: 40% self-assessment, 60% peer review.
Include ranking_table_markdown and brief full_report.

Output ONLY valid JSON:
{
  "analyst": {"id": "groq", "model_name": "$GROQ_MODEL"},
  "analyzed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "methodology": "40% self / 60% peer weighted",
  "baseline_rankings": [...],
  "full_report": "...",
  "ranking_table_markdown": "| Rank | AI | Overall | CJ Score |..."
}
EOF
}

# Run baseline analysis with the arbiter (4th AI)
# Args: $1 = assessment directory
run_baseline_analysis() {
    local assessment_dir="$1"

    log_info "Running baseline analysis with Arbiter..."

    # Source the Groq adapter
    local adapter_file="$SCRIPT_DIR/adapters/groq_adapter.sh"
    if [[ ! -f "$adapter_file" ]]; then
        log_error "Groq adapter not found: $adapter_file"
        return 1
    fi
    source "$adapter_file"

    # Build the prompt
    local prompt
    prompt=$(build_baseline_analysis_prompt "$assessment_dir")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to build baseline analysis prompt"
        return 1
    fi

    # Create output file
    local output_file="$assessment_dir/baseline_analysis.json"
    local temp_response="${output_file}.raw"

    # Invoke arbiter
    if ! invoke_arbiter "$prompt" "$temp_response" "baseline"; then
        log_error "Arbiter failed to complete baseline analysis"
        return 1
    fi

    # Extract JSON using helper function
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Arbiter returned invalid JSON"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    # Save the analysis
    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    # Update status
    update_assessment_status "$assessment_dir" "analysis_complete"

    log_success "Baseline analysis complete"

    # Display ranking table if available
    local ranking_table
    ranking_table=$(jq -r '.ranking_table_markdown // empty' "$output_file")
    if [[ -n "$ranking_table" ]]; then
        echo ""
        echo -e "${YELLOW}Baseline Rankings:${NC}"
        echo "$ranking_table"
        echo ""
    fi

    return 0
}

#=============================================================================
# Topic Analysis for Per-Debate CJ Selection
#=============================================================================

# Build topic analysis prompt
# Args: $1 = debate topic
#       $2 = additional context (optional)
build_topic_analysis_prompt() {
    local topic="$1"
    local context="${2:-No additional context provided.}"

    # Prefer TOON, fall back to JSON
    local questionnaire_file
    if [[ -f "$COUNCIL_ROOT/config/questionnaire_v1.toon" ]]; then
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.toon"
    else
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.json"
    fi

    # Build compact category structure (decode TOON if needed)
    local categories
    if [[ "$questionnaire_file" == *.toon ]]; then
        local toon_util="${COUNCIL_ROOT:-$SCRIPT_DIR/..}/lib/toon_util.py"
        categories=$("$toon_util" decode "$questionnaire_file" 2>/dev/null | jq -r '.categories[] | "- \(.id): \(.name)"')
    else
        categories=$(jq -r '.categories[] | "- \(.id): \(.name)"' "$questionnaire_file")
    fi

    cat <<EOF
Analyze this debate topic and assign relevance weights (0.0-1.0) to each category.

TOPIC: $topic

CONTEXT: $context

CATEGORIES:
$categories

Relevance scale:
- 0.0: Irrelevant
- 0.4: Somewhat relevant
- 0.6: Moderately relevant
- 0.8: Highly relevant
- 1.0: Essential

Output ONLY valid JSON:
{
  "analyst": {"id": "groq", "model_name": "$GROQ_MODEL"},
  "analyzed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "topic_summary": "<1 sentence>",
  "topic_keywords": ["keyword1", "keyword2"],
  "category_relevance": [
    {"category_id": "reasoning_logic", "relevance": 0.8, "reasoning": "..."},
    {"category_id": "legal_ethical", "relevance": 0.6, "reasoning": "..."},
    {"category_id": "argumentation", "relevance": 0.7, "reasoning": "..."},
    {"category_id": "domain_knowledge", "relevance": 0.5, "reasoning": "..."},
    {"category_id": "programming_languages", "relevance": 0.3, "reasoning": "..."},
    {"category_id": "accessibility_inclusive_design", "relevance": 0.2, "reasoning": "..."},
    {"category_id": "communication", "relevance": 0.7, "reasoning": "..."},
    {"category_id": "meta_cognition", "relevance": 0.8, "reasoning": "..."},
    {"category_id": "collaboration", "relevance": 0.6, "reasoning": "..."}
  ],
  "analysis_notes": "..."
}
EOF
}

# Run topic analysis with arbiter
# Args: $1 = debate topic
#       $2 = output file
#       $3 = additional context (optional)
run_topic_analysis() {
    local topic="$1"
    local output_file="$2"
    local context="${3:-}"

    log_info "Analyzing topic relevance..."

    # Source the Groq adapter
    local adapter_file="$SCRIPT_DIR/adapters/groq_adapter.sh"
    if [[ ! -f "$adapter_file" ]]; then
        log_error "Groq adapter not found: $adapter_file"
        return 1
    fi
    source "$adapter_file"

    # Build the prompt
    local prompt
    prompt=$(build_topic_analysis_prompt "$topic" "$context")

    # Invoke arbiter
    local temp_response="${output_file}.raw"
    if ! invoke_arbiter "$prompt" "$temp_response" "topic"; then
        log_error "Topic analysis failed"
        return 1
    fi

    # Extract JSON using helper function
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Topic analysis returned invalid JSON"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    log_success "Topic analysis complete"
    return 0
}

#=============================================================================
# Chief Justice Recommendation
#=============================================================================

# Build CJ recommendation prompt
# Args: $1 = debate topic
#       $2 = topic relevance file (JSON)
#       $3 = baseline scores file (JSON)
#       $4 = debate_id
build_cj_recommendation_prompt() {
    local topic="$1"
    local topic_file="$2"
    local baseline_file="$3"
    local debate_id="$4"

    # Extract compact topic relevance
    local topic_relevance
    topic_relevance=$(jq -c '.category_relevance | map({(.category_id): .relevance}) | add' "$topic_file")

    # Extract compact baseline scores
    local baseline_scores
    baseline_scores=$(jq -c '[.baseline_rankings[] | {id: .id, overall: .overall_score, cj: .baseline_chief_justice_score, categories: .category_scores}]' "$baseline_file")

    cat <<EOF
Recommend Chief Justice for this debate based on topic relevance.

TOPIC: $topic
DEBATE_ID: $debate_id

TOPIC RELEVANCE (0.0-1.0 per category):
$topic_relevance

BASELINE SCORES:
$baseline_scores

Calculate context-weighted scores:
1. For each AI, multiply their category scores by relevance weights
2. CJ role weights meta_cognition, communication, collaboration 1.5x extra
3. Rank by context-weighted CJ suitability
4. Show delta from baseline (positive = topic favors this AI)

Output ONLY valid JSON:
{
  "debate_id": "$debate_id",
  "calculated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "methodology": "context-weighted with 1.5x CJ skill bonus",
  "rankings": [
    {
      "model_id": "claude",
      "context_rank": 1,
      "context_weighted_score": 8.5,
      "baseline_score": 8.4,
      "score_delta": 0.1,
      "chief_justice_suitability": 8.2
    }
  ],
  "recommended_chief_justice": "claude",
  "recommendation_reasoning": "Brief explanation...",
  "ranking_table_markdown": "| Rank | AI | Context | Baseline | Delta | CJ Suit. |\\n|---|---|---|---|---|---|\\n| 1 | ... |",
  "alternative_considerations": "Notes if scores are close..."
}
EOF
}

# Run CJ recommendation
# Args: $1 = debate topic
#       $2 = topic analysis file
#       $3 = baseline analysis file
#       $4 = output file
#       $5 = debate_id (optional, generated if not provided)
run_cj_recommendation() {
    local topic="$1"
    local topic_file="$2"
    local baseline_file="$3"
    local output_file="$4"
    local debate_id="${5:-$(date +%Y%m%d_%H%M%S)_$(echo "$topic" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | cut -c1-30)}"

    log_info "Generating Chief Justice recommendation..."

    # Validate inputs exist
    if [[ ! -f "$topic_file" ]]; then
        log_error "Topic analysis file not found: $topic_file"
        return 1
    fi
    if [[ ! -f "$baseline_file" ]]; then
        log_error "Baseline analysis file not found: $baseline_file"
        return 1
    fi

    # Source the Groq adapter
    local adapter_file="$SCRIPT_DIR/adapters/groq_adapter.sh"
    source "$adapter_file"

    # Build the prompt
    local prompt
    prompt=$(build_cj_recommendation_prompt "$topic" "$topic_file" "$baseline_file" "$debate_id")

    # Invoke arbiter
    local temp_response="${output_file}.raw"
    if ! invoke_arbiter "$prompt" "$temp_response" "recommendation"; then
        log_error "CJ recommendation failed"
        return 1
    fi

    # Extract JSON using helper function
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "CJ recommendation returned invalid JSON"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    # Display recommendation
    local recommended
    recommended=$(jq -r '.recommended_chief_justice' "$output_file")
    local reasoning
    reasoning=$(jq -r '.recommendation_reasoning' "$output_file")
    local ranking_table
    ranking_table=$(jq -r '.ranking_table_markdown' "$output_file")

    echo ""
    echo -e "${YELLOW}Chief Justice Recommendation:${NC} ${BOLD}$(get_ai_name "$recommended")${NC}"
    echo ""
    echo "$reasoning"
    echo ""
    echo -e "${CYAN}Context-Weighted Rankings:${NC}"
    echo "$ranking_table"
    echo ""

    log_success "CJ recommendation complete"
    return 0
}

# Full CJ selection workflow for a debate topic
# Args: $1 = debate topic
#       $2 = baseline file (from prior assessment)
#       $3 = output directory
#       $4 = additional context (optional)
# Returns: Recommended CJ model id
select_chief_justice() {
    local topic="$1"
    local baseline_file="$2"
    local output_dir="$3"
    local context="${4:-}"

    ensure_dir "$output_dir"

    local topic_file="$output_dir/topic_analysis.json"
    local recommendation_file="$output_dir/cj_recommendation.json"

    # Step 1: Analyze topic (redirect stdout to stderr so only final result goes to stdout)
    if ! run_topic_analysis "$topic" "$topic_file" "$context" >&2; then
        log_error "Failed to analyze topic"
        return 1
    fi

    # Step 2: Generate recommendation (redirect stdout to stderr)
    if ! run_cj_recommendation "$topic" "$topic_file" "$baseline_file" "$recommendation_file" >&2; then
        log_error "Failed to generate CJ recommendation"
        return 1
    fi

    # Return the recommended CJ (this is the ONLY thing that goes to stdout)
    jq -r '.recommended_chief_justice' "$recommendation_file"
}

log_debug "Assessment module loaded"
