#!/usr/bin/env bash
#
# The Council of Legends - Team Orchestration Engine
# Core logic for team collaboration workflows
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

# Team members (core council + optional arbiter)
declare -a TEAM_MEMBERS=("claude" "codex" "gemini")
declare -a TEAM_MEMBERS_WITH_ARBITER=("claude" "codex" "gemini" "arbiter")

# Work modes
declare -a VALID_WORK_MODES=("pair_programming" "consultation" "round_robin" "divide_conquer" "free_form")

# Project directories
PROJECTS_DIR="${PROJECTS_DIR:-$COUNCIL_ROOT/projects}"

#=============================================================================
# Project Directory Management
#=============================================================================

# Create project directory for a team task
# Args: $1 = task description
# Returns: Path to project directory
create_project_directory() {
    local task="$1"
    local timestamp
    timestamp=$(timestamp)
    local slug
    slug=$(slugify "$task")
    local project_dir="$PROJECTS_DIR/${timestamp}_${slug}"

    mkdir -p "$project_dir"/{responses,artifacts,checkpoints}
    echo "$project_dir"
}

# Save project metadata
# Args: $1 = project dir, $2 = task, $3 = PM, $4 = work mode, $5 = team members (space-separated)
save_project_metadata() {
    local project_dir="$1"
    local task="$2"
    local pm="$3"
    local work_mode="$4"
    local team_members="$5"

    cat > "$project_dir/metadata.json" <<EOF
{
    "task": $(printf '%s' "$task" | jq -Rs .),
    "project_manager": "$pm",
    "work_mode": "$work_mode",
    "team_members": $(echo "$team_members" | jq -R 'split(" ")'),
    "checkpoint_level": "${TEAM_CHECKPOINT_LEVEL:-all}",
    "started_at": "$(human_date)",
    "status": "in_progress",
    "config": {
        "claude_model": "$CLAUDE_MODEL",
        "codex_model": "$CODEX_MODEL",
        "gemini_model": "$GEMINI_MODEL",
        "groq_model": "$GROQ_MODEL"
    }
}
EOF
}

# Update project status
# Args: $1 = project dir, $2 = new status
update_project_status() {
    local project_dir="$1"
    local new_status="$2"
    local metadata_file="$project_dir/metadata.json"

    jq --arg status "$new_status" '.status = $status' "$metadata_file" > "${metadata_file}.tmp"
    mv "${metadata_file}.tmp" "$metadata_file"
}

#=============================================================================
# Arbiter Availability Check
#=============================================================================

# Check if arbiter is available (GROQ_API_KEY + questionnaire)
# Returns: 0 if available, 1 if not
check_arbiter_availability() {
    # Check for API key
    if [[ -z "${GROQ_API_KEY:-}" ]]; then
        log_debug "Arbiter not available: GROQ_API_KEY not set"
        return 1
    fi

    # Check for arbiter questionnaire
    local arbiter_assessment=""
    local latest_dir
    latest_dir=$(ls -dt "$COUNCIL_ROOT/assessments/"*/ 2>/dev/null | head -1)

    if [[ -n "$latest_dir" ]] && [[ -f "$latest_dir/self_assessments/self_assessment_arbiter.json" ]]; then
        arbiter_assessment="$latest_dir/self_assessments/self_assessment_arbiter.json"
    fi

    if [[ -z "$arbiter_assessment" ]]; then
        log_debug "Arbiter not available: No questionnaire found"
        return 1
    fi

    log_debug "Arbiter available: $arbiter_assessment"
    return 0
}

# Auto-run arbiter assessment if missing
# Returns: 0 on success, 1 on failure
ensure_arbiter_assessed() {
    if check_arbiter_availability; then
        return 0
    fi

    # Check if we have API key but no questionnaire
    if [[ -n "${GROQ_API_KEY:-}" ]]; then
        log_info "Arbiter hasn't been assessed. Running questionnaire..."
        if run_arbiter_questionnaire; then
            log_success "Arbiter assessment complete"
            return 0
        else
            log_error "Failed to assess arbiter"
            return 1
        fi
    fi

    return 1
}

#=============================================================================
# Team Member Resolution
#=============================================================================

# Get list of available team members for this task
# Args: $1 = include_arbiter preference ("true", "false", or empty for PM decision)
# Returns: Space-separated list of team members
get_available_team_members() {
    local include_arbiter="${1:-}"

    if [[ "$include_arbiter" == "true" ]]; then
        # User explicitly wants arbiter - ensure it's available
        if ensure_arbiter_assessed; then
            echo "${TEAM_MEMBERS_WITH_ARBITER[*]}"
        else
            log_warn "Arbiter requested but not available. Using core team."
            echo "${TEAM_MEMBERS[*]}"
        fi
    elif [[ "$include_arbiter" == "false" ]]; then
        # User explicitly doesn't want arbiter
        echo "${TEAM_MEMBERS[*]}"
    else
        # PM will decide - check if arbiter is available
        if check_arbiter_availability; then
            echo "${TEAM_MEMBERS_WITH_ARBITER[*]}"
        else
            echo "${TEAM_MEMBERS[*]}"
        fi
    fi
}

#=============================================================================
# User Checkpoints
#=============================================================================

# Prompt user for approval at a checkpoint
# Args: $1 = checkpoint type (plan, milestone, delivery)
#       $2 = description
#       $3 = file to display (optional)
# Returns: 0 for approved, 1 for rejected, 2 for adjust
prompt_checkpoint() {
    local checkpoint_type="$1"
    local description="$2"
    local display_file="${3:-}"

    # Check if checkpoints are enabled for this type
    case "${TEAM_CHECKPOINT_LEVEL:-all}" in
        none)
            return 0
            ;;
        major)
            if [[ "$checkpoint_type" != "plan" ]] && [[ "$checkpoint_type" != "delivery" ]]; then
                return 0
            fi
            ;;
        all)
            # All checkpoints enabled
            ;;
    esac

    separator "─" 52
    echo -e "${YELLOW}CHECKPOINT: ${NC}${BOLD}$description${NC}"
    separator "─" 52

    # Display file content if provided
    if [[ -n "$display_file" ]] && [[ -f "$display_file" ]]; then
        echo ""
        cat "$display_file"
        echo ""
    fi

    echo ""
    echo -e "${WHITE}Options:${NC}"
    echo "  [a] Approve and continue"
    echo "  [r] Reject and stop"
    echo "  [m] Modify/adjust (provide feedback)"
    echo ""

    while true; do
        read -r -p "Your choice [a/r/m]: " choice
        case "$choice" in
            a|A)
                log_success "Checkpoint approved"
                return 0
                ;;
            r|R)
                log_warn "Checkpoint rejected"
                return 1
                ;;
            m|M)
                read -r -p "Enter your feedback: " feedback
                export CHECKPOINT_FEEDBACK="$feedback"
                return 2
                ;;
            *)
                echo "Invalid choice. Please enter a, r, or m."
                ;;
        esac
    done
}

#=============================================================================
# Main Team Workflow
#=============================================================================

# Run the complete team workflow
# Args: $1 = task description
run_team_workflow() {
    local task="$1"

    log_info "Starting team workflow..."
    echo -e "${WHITE}Task:${NC} $task"
    echo ""

    # Phase 1: Task Intake
    header "Phase 1: Task Intake"

    # Determine available team members
    local team_members
    team_members=$(get_available_team_members "${TEAM_INCLUDE_ARBITER:-}")
    log_info "Available team: $team_members"

    # Create project directory
    local project_dir
    project_dir=$(create_project_directory "$task")
    log_info "Project directory: $project_dir"
    export TEAM_PROJECT_DIR="$project_dir"

    # Phase 2: PM Selection
    header "Phase 2: Project Manager Selection"

    local selected_pm
    if [[ -n "${TEAM_FORCE_PM:-}" ]]; then
        selected_pm="$TEAM_FORCE_PM"
        log_info "Using manually specified PM: $(get_ai_name "$selected_pm")"
    else
        # Use PM selection logic (reuses CJ selection)
        selected_pm=$(select_project_manager "$task" "$team_members" "$project_dir")
        if [[ -z "$selected_pm" ]]; then
            log_warn "PM selection failed, using default (Claude)"
            selected_pm="claude"
        fi
        log_success "Selected PM: $(get_ai_name "$selected_pm")"
    fi
    export TEAM_PM="$selected_pm"

    # Phase 3: PM Plans Approach
    header "Phase 3: Planning"
    ai_header "$selected_pm" "Creating execution plan..."

    local plan_file="$project_dir/execution_plan.json"
    if ! create_execution_plan "$task" "$selected_pm" "$team_members" "$plan_file"; then
        log_error "Failed to create execution plan"
        return 1
    fi

    # Display plan summary
    display_plan_summary "$plan_file"

    # User checkpoint: approve plan
    if ! prompt_checkpoint "plan" "Review Execution Plan" "$project_dir/plan_summary.md"; then
        log_error "Plan rejected by user"
        update_project_status "$project_dir" "rejected"
        return 1
    fi

    # Handle plan adjustments if user provided feedback
    if [[ -n "${CHECKPOINT_FEEDBACK:-}" ]]; then
        log_info "Adjusting plan based on feedback..."
        if ! adjust_execution_plan "$plan_file" "$CHECKPOINT_FEEDBACK"; then
            log_error "Failed to adjust plan"
            return 1
        fi
        unset CHECKPOINT_FEEDBACK
        display_plan_summary "$plan_file"
    fi

    # Extract plan details
    local work_mode
    work_mode=$(jq -r '.plan.work_mode' "$plan_file")
    local include_arbiter
    include_arbiter=$(jq -r '.plan.include_arbiter' "$plan_file")

    # Override work mode if user specified
    if [[ -n "${TEAM_WORK_MODE:-}" ]]; then
        work_mode="$TEAM_WORK_MODE"
        log_info "Using user-specified work mode: $work_mode"
    fi

    # Update team members based on arbiter decision
    if [[ "$include_arbiter" == "false" ]]; then
        team_members="${TEAM_MEMBERS[*]}"
    fi

    # Save final metadata
    save_project_metadata "$project_dir" "$task" "$selected_pm" "$work_mode" "$team_members"

    # Phase 4: Execution
    header "Phase 4: Execution ($work_mode)"

    if ! run_work_mode "$work_mode" "$task" "$selected_pm" "$team_members" "$plan_file" "$project_dir"; then
        log_error "Execution failed"
        update_project_status "$project_dir" "failed"
        return 1
    fi

    # Phase 5: Delivery
    header "Phase 5: Delivery"
    ai_header "$selected_pm" "Synthesizing final deliverable..."

    local delivery_file="$project_dir/final_delivery.md"
    if ! create_final_delivery "$task" "$selected_pm" "$project_dir" "$delivery_file"; then
        log_error "Failed to create final delivery"
        return 1
    fi

    # User checkpoint: accept delivery
    if ! prompt_checkpoint "delivery" "Review Final Delivery" "$delivery_file"; then
        log_error "Delivery rejected by user"
        update_project_status "$project_dir" "rejected"
        return 1
    fi

    # Complete!
    update_project_status "$project_dir" "completed"

    separator "═" 52
    log_success "Team task completed!"
    echo ""
    echo -e "${WHITE}Project saved to:${NC} $project_dir"
    echo -e "${WHITE}Final delivery:${NC} $delivery_file"
    separator "═" 52

    return 0
}

#=============================================================================
# Plan Display Helpers
#=============================================================================

# Display plan summary for user review
# Args: $1 = plan file
display_plan_summary() {
    local plan_file="$1"
    local project_dir
    project_dir=$(dirname "$plan_file")
    local summary_file="$project_dir/plan_summary.md"

    # Extract and format plan details
    local work_mode pm include_arbiter
    work_mode=$(jq -r '.plan.work_mode // "unknown"' "$plan_file")
    include_arbiter=$(jq -r '.plan.include_arbiter // false' "$plan_file")

    # Generate summary markdown
    cat > "$summary_file" <<EOF
# Execution Plan Summary

## Work Mode
**$work_mode**

$(case "$work_mode" in
    pair_programming) echo "Two AIs will collaborate on the same artifact, passing it back and forth." ;;
    consultation) echo "Lead works independently but can request input from specialists." ;;
    round_robin) echo "All team members contribute sequentially, each building on previous work." ;;
    divide_conquer) echo "Task is split into subtasks, parallel work, then merged by PM." ;;
    free_form) echo "Open collaboration with PM moderating discussion." ;;
esac)

## Team Composition
$(jq -r '.roles | to_entries | .[] | "- **\(.key)**: \(.value)"' "$plan_file" 2>/dev/null || echo "- Core team: Claude, Codex, Gemini")

## Include Arbiter
$(if [[ "$include_arbiter" == "true" ]]; then echo "Yes - Arbiter will participate"; else echo "No - Core team only"; fi)

## Milestones
$(jq -r '.milestones[]? | "1. \(.description)"' "$plan_file" 2>/dev/null || echo "1. Complete task\n2. Review and deliver")

## Arbiter Reasoning
$(jq -r '.plan.arbiter_reasoning // "N/A"' "$plan_file")

EOF

    # Display to user
    cat "$summary_file"
}

log_debug "Team orchestration module loaded"
