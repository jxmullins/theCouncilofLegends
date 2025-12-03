#!/usr/bin/env bash
#
# The Council of Legends - Interactive Setup Wizard
# First-run configuration for new users
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities for colors and logging
source "$SCRIPT_DIR/lib/utils.sh"

#=============================================================================
# Banner
#=============================================================================

show_banner() {
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                                                            ║${NC}"
    echo -e "${PURPLE}║     ${BOLD}THE COUNCIL OF LEGENDS${NC}${PURPLE}                               ║${NC}"
    echo -e "${PURPLE}║     ${CYAN}Interactive Setup Wizard${NC}${PURPLE}                             ║${NC}"
    echo -e "${PURPLE}║                                                            ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#=============================================================================
# Dependency Checks
#=============================================================================

check_system_dependencies() {
    header "Checking System Dependencies"

    local all_ok=true

    # Required system tools
    local required=("jq" "curl" "python3")
    for cmd in "${required[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_success "$cmd is installed"
        else
            log_error "$cmd is NOT installed"
            all_ok=false
        fi
    done

    # Optional but recommended
    if command -v gtimeout &>/dev/null || command -v timeout &>/dev/null; then
        log_success "timeout command available"
    else
        log_warn "timeout not available (install coreutils for better timeout handling)"
    fi

    if [[ "$all_ok" == "false" ]]; then
        echo ""
        echo "Please install missing dependencies:"
        echo "  macOS:   brew install jq curl python3"
        echo "  Ubuntu:  sudo apt install jq curl python3"
        echo "  Fedora:  sudo dnf install jq curl python3"
        return 1
    fi

    return 0
}

check_cli_tools() {
    header "Checking AI CLI Tools"

    local available=()
    local missing=()

    # Check each AI CLI
    if command -v claude &>/dev/null; then
        log_success "Claude CLI is installed"
        available+=("claude")
    else
        log_warn "Claude CLI is NOT installed"
        missing+=("claude")
    fi

    if command -v codex &>/dev/null; then
        log_success "Codex CLI is installed"
        available+=("codex")
    else
        log_warn "Codex CLI is NOT installed"
        missing+=("codex")
    fi

    if command -v gemini &>/dev/null; then
        log_success "Gemini CLI is installed"
        available+=("gemini")
    else
        log_warn "Gemini CLI is NOT installed"
        missing+=("gemini")
    fi

    echo ""

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing CLI tools can be installed with:"
        for cli in "${missing[@]}"; do
            case "$cli" in
                claude)
                    echo "  npm install -g @anthropic-ai/claude-code && claude auth login"
                    ;;
                codex)
                    echo "  npm install -g @openai/codex && codex auth login"
                    ;;
                gemini)
                    echo "  npm install -g @google/gemini-cli && gemini auth login"
                    ;;
            esac
        done
        echo ""
    fi

    if [[ ${#available[@]} -lt 2 ]]; then
        log_error "At least 2 AI CLIs are required for debates"
        return 1
    fi

    log_success "Found ${#available[@]} AI CLIs - sufficient for debates"
    return 0
}

#=============================================================================
# API Key Configuration
#=============================================================================

configure_api_keys() {
    header "API Key Configuration"

    local env_file="$SCRIPT_DIR/.env"

    echo "The Council uses environment variables for API keys."
    echo "We can save them to a .env file for convenience."
    echo ""

    # Check if .env already exists
    if [[ -f "$env_file" ]]; then
        echo -e "${YELLOW}Existing .env file found.${NC}"
        read -p "Overwrite existing configuration? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing .env configuration"
            return 0
        fi
    fi

    # Groq API key (optional, for arbiter)
    echo ""
    echo -e "${CYAN}Groq API Key (optional)${NC}"
    echo "Used for the 4th AI arbiter (Chief Justice selection, SCOTUS mode)"
    echo "Get one at: https://console.groq.com/keys"
    echo ""
    read -p "Enter Groq API key (or press Enter to skip): " groq_key

    # Create .env file
    {
        echo "# The Council of Legends - Environment Configuration"
        echo "# Generated by setup.sh on $(date)"
        echo ""
        if [[ -n "${groq_key:-}" ]]; then
            echo "GROQ_API_KEY=\"$groq_key\""
        else
            echo "# GROQ_API_KEY=\"your-groq-api-key\""
        fi
        echo ""
        echo "# Model preferences (optional)"
        echo "# CLAUDE_MODEL=\"sonnet\""
        echo "# CODEX_MODEL=\"gpt-4o\""
        echo "# GEMINI_MODEL=\"gemini-2.5-flash\""
    } > "$env_file"

    log_success "Configuration saved to .env"
    echo ""
    echo "To load these settings, add to your shell profile:"
    echo "  source $env_file"
    echo ""
    echo "Or run: export \$(cat $env_file | grep -v '^#' | xargs)"

    return 0
}

#=============================================================================
# Test Adapters
#=============================================================================

test_adapters() {
    header "Testing AI Adapters"

    echo "Running adapter tests to verify CLI authentication..."
    echo ""

    if [[ -x "$SCRIPT_DIR/test_adapters.sh" ]]; then
        "$SCRIPT_DIR/test_adapters.sh" || true
    else
        log_warn "test_adapters.sh not found or not executable"
    fi
}

#=============================================================================
# Summary
#=============================================================================

show_summary() {
    header "Setup Complete"

    echo -e "${GREEN}The Council of Legends is ready!${NC}"
    echo ""
    echo "Quick start commands:"
    echo ""
    echo "  ${CYAN}Start a debate:${NC}"
    echo "    ./council.sh \"Your topic here\""
    echo ""
    echo "  ${CYAN}Team collaboration:${NC}"
    echo "    ./team.sh \"Your task here\""
    echo ""
    echo "  ${CYAN}Run with SCOTUS mode:${NC}"
    echo "    ./council.sh \"Your topic\" --mode scotus"
    echo ""
    echo "  ${CYAN}See all options:${NC}"
    echo "    ./council.sh --help"
    echo ""

    if [[ -f "$SCRIPT_DIR/.env" ]] && grep -q "^GROQ_API_KEY=" "$SCRIPT_DIR/.env"; then
        echo -e "${GREEN}Arbiter enabled${NC} - Chief Justice selection available"
    else
        echo -e "${YELLOW}Arbiter not configured${NC} - Set GROQ_API_KEY for CJ selection"
    fi

    echo ""
    echo "Documentation: https://github.com/jxmullins/theCouncilofLegends"
    echo ""
}

#=============================================================================
# Main
#=============================================================================

main() {
    show_banner

    # Step 1: System dependencies
    if ! check_system_dependencies; then
        log_error "Please install missing system dependencies and run setup again"
        exit 1
    fi

    # Step 2: AI CLI tools
    if ! check_cli_tools; then
        log_error "Please install at least 2 AI CLI tools and run setup again"
        exit 1
    fi

    # Step 3: API key configuration
    echo ""
    read -p "Configure API keys now? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        configure_api_keys
    fi

    # Step 4: Test adapters
    echo ""
    read -p "Test AI adapters now? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        test_adapters
    fi

    # Final summary
    show_summary
}

main "$@"
