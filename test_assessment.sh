#!/usr/bin/env bash
#
# Test script for the Assessment & Anonymization module
#

set -e

# Get the project root (where this script lives)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assessment.sh"

# Test directory - use project root, not lib directory
TEST_DIR="$PROJECT_ROOT/.test_assessment"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

header "Testing Assessment & Anonymization Module"

#=============================================================================
# Test 1: Generate Anonymization Map
#=============================================================================
echo -e "${CYAN}Test 1: Generate Anonymization Map${NC}"

mapping=$(generate_anonymization_map)
echo "$mapping" > "$TEST_DIR/mapping.json"

# Verify it's valid JSON
if jq -e . "$TEST_DIR/mapping.json" > /dev/null 2>&1; then
    log_success "Generated valid JSON mapping"
else
    log_error "Invalid JSON generated"
    exit 1
fi

# Verify all members are mapped
for member in claude codex gemini; do
    anon_id=$(jq -r ".mappings[\"$member\"]" "$TEST_DIR/mapping.json")
    if [[ "$anon_id" =~ ^AI-[A-C]$ ]]; then
        log_success "$member -> $anon_id"
    else
        log_error "$member not properly mapped"
        exit 1
    fi
done

#=============================================================================
# Test 2: Validate Mapping
#=============================================================================
echo ""
echo -e "${CYAN}Test 2: Validate Mapping${NC}"

if validate_mapping "$TEST_DIR/mapping.json"; then
    log_success "Mapping validation passed"
else
    log_error "Mapping validation failed"
    exit 1
fi

#=============================================================================
# Test 3: Get Anonymous ID
#=============================================================================
echo ""
echo -e "${CYAN}Test 3: Get Anonymous ID${NC}"

for member in claude codex gemini; do
    anon_id=$(get_anonymous_id "$member" "$TEST_DIR/mapping.json")
    log_success "get_anonymous_id($member) = $anon_id"
done

#=============================================================================
# Test 4: Reverse Lookup (Get Real ID)
#=============================================================================
echo ""
echo -e "${CYAN}Test 4: Reverse Lookup (Get Real ID)${NC}"

for anon_id in AI-A AI-B AI-C; do
    real_id=$(get_real_id "$anon_id" "$TEST_DIR/mapping.json")
    log_success "get_real_id($anon_id) = $real_id"
done

#=============================================================================
# Test 5: Get Peer Anonymous IDs
#=============================================================================
echo ""
echo -e "${CYAN}Test 5: Get Peer Anonymous IDs (for review)${NC}"

for member in claude codex gemini; do
    peer_ids=$(get_peer_anonymous_ids "$member" "$TEST_DIR/mapping.json")
    own_id=$(get_anonymous_id "$member" "$TEST_DIR/mapping.json")
    log_success "$member (is $own_id) reviews: $peer_ids"

    # Verify own ID is NOT in peer list
    if [[ "$peer_ids" == *"$own_id"* ]]; then
        log_error "SECURITY FAILURE: $member would review their own assessment!"
        exit 1
    fi
done

#=============================================================================
# Test 6: Create Sample Self-Assessments
#=============================================================================
echo ""
echo -e "${CYAN}Test 6: Create Sample Self-Assessments${NC}"

mkdir -p "$TEST_DIR/self_assessments"

# Claude's self-assessment
cat > "$TEST_DIR/self_assessments/self_assessment_claude.json" <<'EOF'
{
  "model": {
    "id": "claude",
    "model_name": "claude-opus-4-5-20251101"
  },
  "submitted_at": "2025-12-01T15:00:00Z",
  "categories": [
    {
      "category_id": "reasoning_logic",
      "items": [
        { "item_id": "formal_deduction", "rating": 9 },
        { "item_id": "fallacy_identification", "rating": 8 }
      ]
    }
  ],
  "overall_self_rating": 8,
  "strengths_summary": "Strong ethical reasoning",
  "weaknesses_summary": "Limited legacy language knowledge"
}
EOF

# Codex's self-assessment
cat > "$TEST_DIR/self_assessments/self_assessment_codex.json" <<'EOF'
{
  "model": {
    "id": "codex",
    "model_name": "gpt-4-turbo"
  },
  "submitted_at": "2025-12-01T15:01:00Z",
  "categories": [
    {
      "category_id": "programming_languages",
      "items": [
        { "item_id": "python", "rating": 10 },
        { "item_id": "javascript", "rating": 9 }
      ]
    }
  ],
  "overall_self_rating": 8,
  "strengths_summary": "Exceptional programming",
  "weaknesses_summary": "Ethics less developed"
}
EOF

# Gemini's self-assessment
cat > "$TEST_DIR/self_assessments/self_assessment_gemini.json" <<'EOF'
{
  "model": {
    "id": "gemini",
    "model_name": "gemini-2.0-flash"
  },
  "submitted_at": "2025-12-01T15:02:00Z",
  "categories": [
    {
      "category_id": "domain_knowledge",
      "items": [
        { "item_id": "science_technology", "rating": 9 },
        { "item_id": "history", "rating": 8 }
      ]
    }
  ],
  "overall_self_rating": 8,
  "strengths_summary": "Strong scientific knowledge",
  "weaknesses_summary": "Less specialized"
}
EOF

log_success "Created 3 sample self-assessments"

#=============================================================================
# Test 7: Anonymize All Assessments
#=============================================================================
echo ""
echo -e "${CYAN}Test 7: Anonymize All Assessments${NC}"

mkdir -p "$TEST_DIR/anonymized"
anonymize_all_assessments "$TEST_DIR/self_assessments" "$TEST_DIR/mapping.json" "$TEST_DIR/anonymized"

# Verify anonymized files exist and don't contain real IDs
for anon_id in AI-A AI-B AI-C; do
    anon_file="$TEST_DIR/anonymized/anonymous_${anon_id}.json"
    if [[ -f "$anon_file" ]]; then
        # Check it has anonymous_id field
        file_anon_id=$(jq -r '.anonymous_id' "$anon_file")
        if [[ "$file_anon_id" == "$anon_id" ]]; then
            log_success "anonymous_${anon_id}.json has correct anonymous_id"
        else
            log_error "anonymous_${anon_id}.json has wrong anonymous_id: $file_anon_id"
            exit 1
        fi

        # Check it does NOT contain model.id (should be stripped)
        if jq -e '.model' "$anon_file" > /dev/null 2>&1; then
            log_error "SECURITY: anonymous_${anon_id}.json still contains model info!"
            exit 1
        else
            log_success "anonymous_${anon_id}.json properly stripped of model info"
        fi
    else
        log_error "Missing anonymized file: $anon_file"
        exit 1
    fi
done

#=============================================================================
# Test 8: Prepare Peer Review Packages
#=============================================================================
echo ""
echo -e "${CYAN}Test 8: Prepare Peer Review Packages${NC}"

mkdir -p "$TEST_DIR/review_packages"

for member in claude codex gemini; do
    prepare_peer_review_package "$member" "$TEST_DIR/anonymized" "$TEST_DIR/mapping.json" "$TEST_DIR/review_packages/package_${member}.json"

    # Validate no self-review
    if validate_no_self_review "$member" "$TEST_DIR/review_packages/package_${member}.json" "$TEST_DIR/mapping.json"; then
        log_success "Package for $member: no self-review (safe)"
    else
        log_error "SECURITY FAILURE in package for $member"
        exit 1
    fi

    # Check package contains exactly 2 assessments
    count=$(jq '.peer_assessments | length' "$TEST_DIR/review_packages/package_${member}.json")
    if [[ "$count" -eq 2 ]]; then
        log_success "Package for $member: contains 2 peer assessments"
    else
        log_error "Package for $member: expected 2 assessments, got $count"
        exit 1
    fi
done

#=============================================================================
# Test 9: Simulate Peer Reviews
#=============================================================================
echo ""
echo -e "${CYAN}Test 9: Simulate Peer Reviews${NC}"

mkdir -p "$TEST_DIR/peer_reviews"

# Claude reviews AI-A and AI-B (whoever they are)
claude_peers=$(get_peer_anonymous_ids "claude" "$TEST_DIR/mapping.json")
read -ra CLAUDE_PEERS <<< "$claude_peers"

cat > "$TEST_DIR/peer_reviews/peer_review_claude.json" <<EOF
{
  "reviewer": { "id": "claude", "model_name": "claude-opus-4-5" },
  "submitted_at": "2025-12-01T16:00:00Z",
  "reviews": [
    {
      "anonymous_id": "${CLAUDE_PEERS[0]}",
      "overall_ranking": 7,
      "chief_justice_suitability": { "rating": 7 }
    },
    {
      "anonymous_id": "${CLAUDE_PEERS[1]}",
      "overall_ranking": 8,
      "chief_justice_suitability": { "rating": 6 }
    }
  ]
}
EOF

log_success "Created sample peer review from Claude"

#=============================================================================
# Test 10: De-anonymize Peer Review
#=============================================================================
echo ""
echo -e "${CYAN}Test 10: De-anonymize Peer Review${NC}"

mkdir -p "$TEST_DIR/revealed"
deanonymize_peer_review "$TEST_DIR/peer_reviews/peer_review_claude.json" "$TEST_DIR/mapping.json" "$TEST_DIR/revealed/peer_review_claude_revealed.json"

# Check that real_id was added to each review
for i in 0 1; do
    real_id=$(jq -r ".reviews[$i].real_id" "$TEST_DIR/revealed/peer_review_claude_revealed.json")
    anon_id=$(jq -r ".reviews[$i].anonymous_id" "$TEST_DIR/revealed/peer_review_claude_revealed.json")

    if [[ "$real_id" != "null" ]] && [[ -n "$real_id" ]]; then
        log_success "Revealed: $anon_id -> $real_id"
    else
        log_error "Failed to de-anonymize $anon_id"
        exit 1
    fi
done

#=============================================================================
# Test 11: Init Assessment Cycle
#=============================================================================
echo ""
echo -e "${CYAN}Test 11: Init Assessment Cycle${NC}"

assessment_dir=$(init_assessment_cycle "$TEST_DIR" "user_initiated" "Test run")

if [[ -d "$assessment_dir" ]]; then
    log_success "Created assessment directory: $assessment_dir"
else
    log_error "Failed to create assessment directory"
    exit 1
fi

# Check subdirectories exist
for subdir in self_assessments anonymized peer_reviews revealed; do
    if [[ -d "$assessment_dir/$subdir" ]]; then
        log_success "  Subdir exists: $subdir"
    else
        log_error "  Missing subdir: $subdir"
        exit 1
    fi
done

# Check files exist
for file in metadata.json anonymization_map.json; do
    if [[ -f "$assessment_dir/$file" ]]; then
        log_success "  File exists: $file"
    else
        log_error "  Missing file: $file"
        exit 1
    fi
done

#=============================================================================
# Test 12: Display Mapping (Visual Check)
#=============================================================================
echo ""
echo -e "${CYAN}Test 12: Display Mapping (Visual)${NC}"
display_mapping "$TEST_DIR/mapping.json"

#=============================================================================
# Summary
#=============================================================================
echo ""
separator "═" 52
echo -e "${GREEN}${BOLD}All tests passed!${NC}"
separator "═" 52

# Cleanup option
echo ""
read -p "Clean up test files? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$TEST_DIR"
    log_info "Test files cleaned up"
else
    log_info "Test files preserved at: $TEST_DIR"
fi
