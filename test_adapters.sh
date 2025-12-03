#!/usr/bin/env bash
#
# The Council of Legends - CLI Adapter Test Script
# Tests that Claude, Codex, and Gemini CLIs are working correctly
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test prompt
TEST_PROMPT="In exactly one sentence, what is 2 + 2?"

# Portable timeout function (works on macOS without coreutils)
run_with_timeout() {
    local timeout_seconds="$1"
    shift

    # Check if gtimeout (from coreutils) or timeout exists
    if command -v gtimeout &>/dev/null; then
        gtimeout "$timeout_seconds" "$@"
    elif command -v timeout &>/dev/null; then
        timeout "$timeout_seconds" "$@"
    else
        # Fallback: run without timeout on macOS
        # Use background process with manual timeout
        "$@" &
        local pid=$!
        local count=0
        while kill -0 $pid 2>/dev/null; do
            sleep 1
            ((count++))
            if [[ $count -ge $timeout_seconds ]]; then
                kill -9 $pid 2>/dev/null
                return 124  # timeout exit code
            fi
        done
        wait $pid
        return $?
    fi
}

# Results tracking
CLAUDE_OK=false
CODEX_OK=false
GEMINI_OK=false

#=============================================================================
# Utility Functions
#=============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

separator() {
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#=============================================================================
# CLI Availability Check
#=============================================================================

check_cli_installed() {
    local cli_name="$1"
    if command -v "$cli_name" &>/dev/null; then
        log_success "$cli_name CLI is installed: $(command -v "$cli_name")"
        return 0
    else
        log_error "$cli_name CLI is NOT installed"
        return 1
    fi
}

#=============================================================================
# Test Functions
#=============================================================================

test_claude() {
    separator
    echo -e "${PURPLE}Testing Claude CLI${NC}"
    separator

    if ! check_cli_installed "claude"; then
        return 1
    fi

    log_info "Sending test prompt to Claude..."
    log_info "Prompt: \"$TEST_PROMPT\""

    local output_file error_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/council_test_claude.XXXXXX")
    error_file=$(mktemp "${TMPDIR:-/tmp}/council_test_claude_err.XXXXXX")
    trap "rm -f '$output_file' '$error_file'" RETURN

    # Claude CLI invocation with -p for non-interactive
    # Note: Unset ANTHROPIC_API_KEY if it contains placeholder value to use built-in auth
    local env_prefix=""
    if [[ "${ANTHROPIC_API_KEY:-}" == *"your-"* ]] || [[ "${ANTHROPIC_API_KEY:-}" == *"placeholder"* ]]; then
        log_warn "Detected placeholder ANTHROPIC_API_KEY, unsetting for Claude CLI"
        env_prefix="env -u ANTHROPIC_API_KEY"
    fi

    if run_with_timeout 60 $env_prefix claude -p "$TEST_PROMPT" > "$output_file" 2>"$error_file"; then
        if [[ -s "$output_file" ]]; then
            echo ""
            echo -e "${GREEN}Response from Claude:${NC}"
            cat "$output_file"
            echo ""
            log_success "Claude CLI is working correctly"
            CLAUDE_OK=true
            return 0
        else
            log_error "Claude returned empty response"
            return 1
        fi
    else
        log_error "Claude CLI failed"
        if [[ -s "$error_file" ]]; then
            echo "Error output:"
            cat "$error_file"
        fi
        return 1
    fi
}

test_codex() {
    separator
    echo -e "${GREEN}Testing Codex CLI${NC}"
    separator

    if ! check_cli_installed "codex"; then
        return 1
    fi

    log_info "Sending test prompt to Codex..."
    log_info "Prompt: \"$TEST_PROMPT\""

    local output_file error_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/council_test_codex.XXXXXX")
    error_file=$(mktemp "${TMPDIR:-/tmp}/council_test_codex_err.XXXXXX")
    trap "rm -f '$output_file' '$error_file'" RETURN

    # Codex CLI uses 'exec' subcommand for non-interactive mode
    # --skip-git-repo-check allows running in non-trusted directories
    log_info "Using: codex exec --skip-git-repo-check \"$TEST_PROMPT\""

    if run_with_timeout 60 codex exec --skip-git-repo-check "$TEST_PROMPT" > "$output_file" 2>"$error_file"; then
        if [[ -s "$output_file" ]]; then
            echo ""
            echo -e "${GREEN}Response from Codex:${NC}"
            cat "$output_file"
            echo ""
            log_success "Codex CLI is working correctly"
            CODEX_OK=true
            return 0
        else
            log_error "Codex returned empty response"
        fi
    fi

    log_error "Codex CLI failed to produce output"
    if [[ -s "$error_file" ]]; then
        echo "Error output:"
        cat "$error_file"
    fi
    return 1
}

test_gemini() {
    separator
    echo -e "${BLUE}Testing Gemini CLI${NC}"
    separator

    if ! check_cli_installed "gemini"; then
        return 1
    fi

    log_info "Sending test prompt to Gemini..."
    log_info "Prompt: \"$TEST_PROMPT\""

    local output_file error_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/council_test_gemini.XXXXXX")
    error_file=$(mktemp "${TMPDIR:-/tmp}/council_test_gemini_err.XXXXXX")
    trap "rm -f '$output_file' '$error_file'" RETURN

    # Gemini CLI invocation (positional query = one-shot mode)
    # Use --output-format text for clean text output
    log_info "Using: gemini \"$TEST_PROMPT\" --output-format text"

    if run_with_timeout 60 gemini "$TEST_PROMPT" --output-format text > "$output_file" 2>"$error_file"; then
        if [[ -s "$output_file" ]]; then
            echo ""
            echo -e "${BLUE}Response from Gemini:${NC}"
            cat "$output_file"
            echo ""
            log_success "Gemini CLI is working correctly"
            GEMINI_OK=true
            return 0
        else
            log_error "Gemini returned empty response"
            return 1
        fi
    else
        log_error "Gemini CLI failed"
        if [[ -s "$error_file" ]]; then
            echo "Error output:"
            cat "$error_file"
        fi
        return 1
    fi
}

#=============================================================================
# Summary
#=============================================================================

print_summary() {
    separator
    echo -e "${PURPLE}TEST SUMMARY${NC}"
    separator

    local passed=0
    local failed=0

    if [[ "$CLAUDE_OK" == "true" ]]; then
        echo -e "  Claude: ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Claude: ${RED}FAIL${NC}"
        ((failed++))
    fi

    if [[ "$CODEX_OK" == "true" ]]; then
        echo -e "  Codex:  ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Codex:  ${RED}FAIL${NC}"
        ((failed++))
    fi

    if [[ "$GEMINI_OK" == "true" ]]; then
        echo -e "  Gemini: ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Gemini: ${RED}FAIL${NC}"
        ((failed++))
    fi

    separator
    echo -e "  Total: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}"
    separator

    if [[ $passed -eq 3 ]]; then
        echo ""
        log_success "All CLI adapters are working! Ready to build The Council of Legends."
        return 0
    elif [[ $passed -ge 2 ]]; then
        echo ""
        log_warn "Some CLIs are working. You can proceed with reduced functionality."
        return 0
    else
        echo ""
        log_error "Multiple CLIs are not working. Please check your installations."
        return 1
    fi
}

#=============================================================================
# Main
#=============================================================================

main() {
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     THE COUNCIL OF LEGENDS - CLI ADAPTER TEST      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Testing CLI adapters for Claude, Codex, and Gemini..."
    log_info "Test prompt: \"$TEST_PROMPT\""
    echo ""

    # Run tests (continue even if some fail)
    test_claude || true
    echo ""
    test_codex || true
    echo ""
    test_gemini || true
    echo ""

    print_summary
}

main "$@"
