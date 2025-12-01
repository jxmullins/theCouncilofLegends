#!/usr/bin/env bash
#
# The Council of Legends - Assessment & Anonymization Module
# Handles self-assessment, blind peer review, and Chief Justice selection
#

# Source utils if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$UTILS_LOADED" ]]; then
    source "$SCRIPT_DIR/utils.sh"
    export UTILS_LOADED=true
fi

#=============================================================================
# Constants
#=============================================================================

# Anonymous IDs for blind peer review
declare -a ANON_IDS=("AI-A" "AI-B" "AI-C")

# Council member IDs
declare -a COUNCIL_MEMBERS=("claude" "codex" "gemini")

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

log_debug "Assessment module loaded"
