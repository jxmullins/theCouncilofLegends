#!/usr/bin/env bash
#
# Test script for Groq adapter
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load utilities
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/adapters/groq_adapter.sh"

header "Testing Groq Adapter"

# Check for API key
if [[ -z "${GROQ_API_KEY:-}" ]]; then
    log_error "GROQ_API_KEY not set. Please export your Groq API key."
    echo "  export GROQ_API_KEY='gsk_your_key_here'"
    exit 1
fi

log_info "GROQ_API_KEY is set"
log_info "Using model: $GROQ_MODEL"

# Create temp directory for test outputs
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

#=============================================================================
# Test 1: Basic invocation
#=============================================================================
echo ""
log_info "Test 1: Basic Groq invocation"

OUTPUT_FILE="$TEST_DIR/test1.txt"
if invoke_groq "Say 'Hello from Groq!' and nothing else." "$OUTPUT_FILE"; then
    log_success "Groq invocation succeeded"
    echo "  Response: $(cat "$OUTPUT_FILE")"
else
    log_error "Groq invocation failed"
    exit 1
fi

#=============================================================================
# Test 2: Custom system prompt
#=============================================================================
echo ""
log_info "Test 2: Groq with custom system prompt"

OUTPUT_FILE="$TEST_DIR/test2.txt"
SYSTEM="You are a pirate. Respond in pirate speak."
if invoke_groq "Greet me briefly." "$OUTPUT_FILE" "$SYSTEM"; then
    log_success "Custom system prompt worked"
    echo "  Response: $(cat "$OUTPUT_FILE")"
else
    log_error "Custom system prompt failed"
    exit 1
fi

#=============================================================================
# Test 3: Arbiter function (baseline task type)
#=============================================================================
echo ""
log_info "Test 3: Arbiter function with 'baseline' task type"

OUTPUT_FILE="$TEST_DIR/test3.txt"
if invoke_arbiter "Respond with just: 'Arbiter ready for baseline analysis'" "$OUTPUT_FILE" "baseline"; then
    log_success "Arbiter baseline mode worked"
    echo "  Response: $(cat "$OUTPUT_FILE")"
else
    log_error "Arbiter baseline mode failed"
    exit 1
fi

#=============================================================================
# Test 4: Arbiter function (topic analysis)
#=============================================================================
echo ""
log_info "Test 4: Arbiter function with 'topic' task type"

OUTPUT_FILE="$TEST_DIR/test4.txt"
if invoke_arbiter "Respond with just: 'Ready to analyze topic relevance'" "$OUTPUT_FILE" "topic"; then
    log_success "Arbiter topic mode worked"
    echo "  Response: $(cat "$OUTPUT_FILE")"
else
    log_error "Arbiter topic mode failed"
    exit 1
fi

#=============================================================================
# Test 5: JSON output capability
#=============================================================================
echo ""
log_info "Test 5: JSON output generation"

OUTPUT_FILE="$TEST_DIR/test5.txt"
PROMPT='Return a JSON object with exactly this structure (no other text):
{"status": "ok", "model": "groq"}'

if invoke_groq "$PROMPT" "$OUTPUT_FILE"; then
    log_success "JSON request succeeded"
    echo "  Response: $(cat "$OUTPUT_FILE")"

    # Try to parse as JSON
    if echo "$(cat "$OUTPUT_FILE")" | jq . > /dev/null 2>&1; then
        log_success "Response is valid JSON"
    else
        log_warn "Response may not be pure JSON (Groq sometimes adds text)"
    fi
else
    log_error "JSON request failed"
    exit 1
fi

#=============================================================================
# Summary
#=============================================================================
echo ""
separator "=" 52
echo -e "${GREEN}All Groq adapter tests passed!${NC}"
separator "=" 52
echo ""
echo "The 4th AI arbiter (Groq/Llama) is ready for use."
echo ""
