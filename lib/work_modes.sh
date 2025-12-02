#!/usr/bin/env bash
#
# The Council of Legends - Work Mode Implementations
# Different collaboration patterns for team tasks
#

# Source utils if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${UTILS_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/utils.sh"
    export UTILS_LOADED=true
fi

# Source roles module for team role personas
if [[ -z "${ROLES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/roles.sh"
    export ROLES_LOADED=true
fi

#=============================================================================
# Work Mode Dispatcher
#=============================================================================

# Run the specified work mode
# Args: $1 = work mode
#       $2 = task
#       $3 = PM id
#       $4 = team members (space-separated)
#       $5 = plan file
#       $6 = project directory
run_work_mode() {
    local work_mode="$1"
    local task="$2"
    local pm="$3"
    local team_members="$4"
    local plan_file="$5"
    local project_dir="$6"

    case "$work_mode" in
        pair_programming)
            run_pair_programming "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
            ;;
        consultation)
            run_consultation "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
            ;;
        round_robin)
            run_round_robin "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
            ;;
        divide_conquer)
            run_divide_conquer "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
            ;;
        free_form)
            run_free_form "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
            ;;
        *)
            log_error "Unknown work mode: $work_mode"
            return 1
            ;;
    esac
}

#=============================================================================
# Pair Programming Mode
#=============================================================================

# Two AIs collaborate on the same artifact, passing it back and forth
run_pair_programming() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local plan_file="$4"
    local project_dir="$5"

    log_info "Starting pair programming mode..."

    # Get lead and partner from plan
    local lead partner
    lead=$(jq -r '.roles.lead // empty' "$plan_file")
    partner=$(jq -r '.roles.reviewer // .roles.partner // empty' "$plan_file")

    # Default to first two team members if not specified
    if [[ -z "$lead" ]]; then
        lead=$(echo "$team_members" | awk '{print $1}')
    fi
    if [[ -z "$partner" ]]; then
        partner=$(echo "$team_members" | awk '{print $2}')
    fi

    local estimated_rounds
    estimated_rounds=$(jq -r '.estimated_rounds // 3' "$plan_file")

    local artifact=""
    local round=1

    while [[ $round -le $estimated_rounds ]]; do
        # Lead writes/extends
        ai_header "$lead" "Round $round: Writing"

        local lead_prompt
        if [[ -z "$artifact" ]]; then
            lead_prompt="Start working on this task. Create the initial implementation.

TASK: $task

Provide your work as markdown. Be thorough but concise."
        else
            lead_prompt="Continue working on this task. Review and extend the previous work.

TASK: $task

CURRENT WORK:
$artifact

Extend and improve the work. Add your contributions."
        fi

        local lead_output="$project_dir/responses/round_${round}_${lead}.md"
        if invoke_ai "$lead" "$lead_prompt" "$lead_output"; then
            display_response "$lead" "$lead_output"
            artifact=$(cat "$lead_output")
        else
            handle_ai_failure "$lead" "pair programming round $round" "$lead_output" "$lead_prompt"
        fi

        # Partner reviews/extends
        ai_header "$partner" "Round $round: Reviewing"

        local partner_prompt="Review and improve this work. Add your perspective and enhancements.

TASK: $task

CURRENT WORK:
$artifact

Review the work, fix any issues, and add improvements."

        local partner_output="$project_dir/responses/round_${round}_${partner}.md"
        if invoke_ai "$partner" "$partner_prompt" "$partner_output"; then
            display_response "$partner" "$partner_output"
            artifact=$(cat "$partner_output")
        else
            handle_ai_failure "$partner" "pair programming round $round" "$partner_output" "$partner_prompt"
        fi

        # Checkpoint at milestones
        if should_checkpoint "$round" "$plan_file"; then
            if ! prompt_checkpoint "milestone" "Round $round Complete - Review Progress"; then
                return 1
            fi
        fi

        round=$((round + 1))
    done

    log_success "Pair programming complete"
    return 0
}

#=============================================================================
# Consultation Mode
#=============================================================================

# Lead works independently but can request input from specialists
run_consultation() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local plan_file="$4"
    local project_dir="$5"

    log_info "Starting consultation mode..."

    # Get lead and specialists
    local lead
    lead=$(jq -r '.roles.lead // empty' "$plan_file")
    if [[ -z "$lead" ]]; then
        lead=$(echo "$team_members" | awk '{print $1}')
    fi

    # Get specialists (everyone except lead)
    local specialists=""
    for member in $team_members; do
        if [[ "$member" != "$lead" ]]; then
            specialists+="$member "
        fi
    done
    specialists=$(echo "$specialists" | xargs)

    local estimated_rounds
    estimated_rounds=$(jq -r '.estimated_rounds // 3' "$plan_file")

    # Phase 1: Lead creates initial work
    ai_header "$lead" "Initial Implementation"

    local lead_prompt="You are the lead on this task. Create the initial implementation.

TASK: $task

You can request specialist input in later rounds. For now, do your best work."

    local lead_output="$project_dir/responses/phase_1_${lead}.md"
    if ! invoke_ai "$lead" "$lead_prompt" "$lead_output"; then
        handle_ai_failure "$lead" "consultation initial" "$lead_output" "$lead_prompt"
    fi
    display_response "$lead" "$lead_output"
    local current_work
    current_work=$(cat "$lead_output")

    # Phase 2: Get specialist input
    for specialist in $specialists; do
        ai_header "$specialist" "Specialist Review"

        local specialist_prompt="Review this work from your specialist perspective.

TASK: $task

CURRENT WORK:
$current_work

Provide your expert feedback, suggestions, and any concerns."

        local specialist_output="$project_dir/responses/specialist_${specialist}.md"
        if invoke_ai "$specialist" "$specialist_prompt" "$specialist_output"; then
            display_response "$specialist" "$specialist_output"
        else
            handle_ai_failure "$specialist" "consultation specialist" "$specialist_output" "$specialist_prompt"
        fi
    done

    # Phase 3: Lead incorporates feedback
    ai_header "$lead" "Final Integration"

    # Gather all specialist feedback
    local all_feedback=""
    for specialist in $specialists; do
        local feedback_file="$project_dir/responses/specialist_${specialist}.md"
        if [[ -f "$feedback_file" ]]; then
            all_feedback+="### $(get_ai_name "$specialist")'s Feedback
$(cat "$feedback_file")

"
        fi
    done

    local final_prompt="Incorporate the specialist feedback into your final work.

TASK: $task

YOUR INITIAL WORK:
$current_work

SPECIALIST FEEDBACK:
$all_feedback

Create the final, integrated version incorporating the best suggestions."

    local final_output="$project_dir/responses/final_${lead}.md"
    if ! invoke_ai "$lead" "$final_prompt" "$final_output"; then
        handle_ai_failure "$lead" "consultation final" "$final_output" "$final_prompt"
    fi
    display_response "$lead" "$final_output"

    log_success "Consultation mode complete"
    return 0
}

#=============================================================================
# Round Robin Mode
#=============================================================================

# All team members contribute sequentially, each building on previous work
run_round_robin() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local plan_file="$4"
    local project_dir="$5"

    log_info "Starting round robin mode..."

    local members=($team_members)
    local num_members=${#members[@]}
    local current_work=""
    local round=1

    for member in "${members[@]}"; do
        ai_header "$member" "Round $round of $num_members"

        local prompt
        if [[ -z "$current_work" ]]; then
            prompt="Start working on this task. Provide the initial contribution.

TASK: $task

Be thorough but leave room for others to extend your work."
        else
            prompt="Continue this work. Build on what came before and add your contribution.

TASK: $task

PREVIOUS WORK:
$current_work

Add your unique perspective and extend the work."
        fi

        local output_file="$project_dir/responses/round_${round}_${member}.md"
        if invoke_ai "$member" "$prompt" "$output_file"; then
            display_response "$member" "$output_file"
            current_work=$(cat "$output_file")
        else
            handle_ai_failure "$member" "round robin round $round" "$output_file" "$prompt"
        fi

        # Checkpoint if configured
        if should_checkpoint "$round" "$plan_file"; then
            if ! prompt_checkpoint "milestone" "Round $round Complete"; then
                return 1
            fi
        fi

        round=$((round + 1))
    done

    # Final polish by PM if different from last contributor
    local last_member="${members[-1]}"
    if [[ "$pm" != "$last_member" ]]; then
        ai_header "$pm" "Final Polish"

        local polish_prompt="Review and polish the final work.

TASK: $task

CURRENT WORK:
$current_work

Make final refinements and ensure quality."

        local polish_output="$project_dir/responses/final_polish_${pm}.md"
        if invoke_ai "$pm" "$polish_prompt" "$polish_output"; then
            display_response "$pm" "$polish_output"
        fi
    fi

    log_success "Round robin mode complete"
    return 0
}

#=============================================================================
# Divide and Conquer Mode
#=============================================================================

# PM splits task into subtasks, assigns to team members, merges results
run_divide_conquer() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local plan_file="$4"
    local project_dir="$5"

    log_info "Starting divide and conquer mode..."

    # Get subtasks from plan
    local subtasks
    subtasks=$(jq -c '.subtasks[]?' "$plan_file")

    if [[ -z "$subtasks" ]]; then
        log_warn "No subtasks defined in plan. Using round robin instead."
        run_round_robin "$task" "$pm" "$team_members" "$plan_file" "$project_dir"
        return $?
    fi

    # Execute each subtask
    local subtask_results=""
    local subtask_num=1

    while IFS= read -r subtask; do
        local assignee
        assignee=$(echo "$subtask" | jq -r '.assignee')
        local description
        description=$(echo "$subtask" | jq -r '.description')
        local subtask_id
        subtask_id=$(echo "$subtask" | jq -r '.id')
        local role
        role=$(echo "$subtask" | jq -r '.role // empty')

        # Set role for this AI if specified
        if [[ -n "$role" ]]; then
            set_role "$assignee" "$role"
            local role_name
            role_name=$(get_role_name "$role")
            ai_header "$assignee" "Subtask: $subtask_id (as $role_name)"
        else
            clear_role "$assignee"
            ai_header "$assignee" "Subtask: $subtask_id"
        fi

        # Build system prompt with role stacked on identity
        local system_prompt
        system_prompt=$(build_role_system_prompt "$assignee")

        local prompt="Complete this subtask as part of a larger team effort.

MAIN TASK: $task

YOUR SUBTASK: $description

Complete your subtask thoroughly. It will be merged with other team members' work."

        local output_file="$project_dir/responses/subtask_${subtask_id}_${assignee}.md"
        if invoke_ai "$assignee" "$prompt" "$output_file" "$system_prompt"; then
            display_response "$assignee" "$output_file"
            subtask_results+="### Subtask: $subtask_id ($(get_ai_name "$assignee"))
$(cat "$output_file")

"
        else
            handle_ai_failure "$assignee" "subtask $subtask_id" "$output_file" "$prompt" "$system_prompt"
        fi

        # Check for milestone role reassignments after this subtask
        check_and_apply_milestone_roles "$plan_file" "$subtask_id"

        subtask_num=$((subtask_num + 1))
    done <<< "$subtasks"

    # PM merges results
    ai_header "$pm" "Merging Results"

    local merge_prompt="Merge the subtask results into a cohesive final deliverable.

MAIN TASK: $task

SUBTASK RESULTS:
$subtask_results

Combine all contributions into a unified, coherent result."

    local merge_output="$project_dir/responses/merged_${pm}.md"
    if ! invoke_ai "$pm" "$merge_prompt" "$merge_output"; then
        handle_ai_failure "$pm" "merge" "$merge_output" "$merge_prompt"
    fi
    display_response "$pm" "$merge_output"

    log_success "Divide and conquer mode complete"
    return 0
}

#=============================================================================
# Free Form Mode
#=============================================================================

# Open collaboration with PM moderating discussion
run_free_form() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local plan_file="$4"
    local project_dir="$5"

    log_info "Starting free form collaboration..."

    local members=($team_members)
    local estimated_rounds
    estimated_rounds=$(jq -r '.estimated_rounds // 3' "$plan_file")

    local discussion=""
    local round=1

    while [[ $round -le $estimated_rounds ]]; do
        header "Discussion Round $round"

        # PM poses question or direction
        ai_header "$pm" "Moderating"

        local pm_prompt
        if [[ $round -eq 1 ]]; then
            pm_prompt="Start a team discussion on this task.

TASK: $task

Pose the initial question or direction for the team. What should we explore first?"
        else
            pm_prompt="Continue moderating the discussion.

TASK: $task

DISCUSSION SO FAR:
$discussion

Synthesize progress and pose the next question or direction."
        fi

        local pm_output="$project_dir/responses/round_${round}_${pm}_moderate.md"
        if invoke_ai "$pm" "$pm_prompt" "$pm_output"; then
            display_response "$pm" "$pm_output"
            discussion+="### $(get_ai_name "$pm") (Moderator)
$(cat "$pm_output")

"
        fi

        # All team members contribute
        for member in "${members[@]}"; do
            if [[ "$member" == "$pm" ]]; then
                continue
            fi

            ai_header "$member" "Contributing"

            local member_prompt="Contribute to this team discussion.

TASK: $task

DISCUSSION SO FAR:
$discussion

Add your perspective, ideas, or solutions."

            local member_output="$project_dir/responses/round_${round}_${member}.md"
            if invoke_ai "$member" "$member_prompt" "$member_output"; then
                display_response "$member" "$member_output"
                discussion+="### $(get_ai_name "$member")
$(cat "$member_output")

"
            else
                handle_ai_failure "$member" "free form round $round" "$member_output" "$member_prompt"
            fi
        done

        # Checkpoint
        if should_checkpoint "$round" "$plan_file"; then
            if ! prompt_checkpoint "milestone" "Discussion Round $round Complete"; then
                return 1
            fi
        fi

        round=$((round + 1))
    done

    # PM synthesizes final conclusion
    ai_header "$pm" "Final Synthesis"

    local synthesis_prompt="Synthesize the discussion into a final conclusion.

TASK: $task

FULL DISCUSSION:
$discussion

Create a comprehensive summary and conclusion based on all contributions."

    local synthesis_output="$project_dir/responses/synthesis_${pm}.md"
    if ! invoke_ai "$pm" "$synthesis_prompt" "$synthesis_output"; then
        handle_ai_failure "$pm" "free form synthesis" "$synthesis_output" "$synthesis_prompt"
    fi
    display_response "$pm" "$synthesis_output"

    log_success "Free form collaboration complete"
    return 0
}

#=============================================================================
# Role Reassignment at Milestones
#=============================================================================

# Apply role reassignments from a milestone
# Args: $1 = plan file, $2 = milestone id or "after" value
apply_milestone_roles() {
    local plan_file="$1"
    local milestone_id="$2"

    # Find milestone and extract role_assignments
    local role_assignments
    role_assignments=$(jq -r --arg id "$milestone_id" \
        '.milestones[]? | select(.id == $id or .after == $id) | .role_assignments // {}' \
        "$plan_file" 2>/dev/null)

    if [[ -z "$role_assignments" ]] || [[ "$role_assignments" == "{}" ]]; then
        return 0  # No role reassignments for this milestone
    fi

    log_info "Applying role reassignments for milestone: $milestone_id"

    # Parse and apply each role assignment
    local assignments
    assignments=$(echo "$role_assignments" | jq -r 'to_entries[] | "\(.key):\(.value)"')

    for assignment in $assignments; do
        if [[ "$assignment" == *":"* ]]; then
            local ai="${assignment%%:*}"
            local role="${assignment##*:}"
            if [[ -n "$role" ]] && [[ "$role" != "null" ]]; then
                set_role "$ai" "$role"
                local role_name
                role_name=$(get_role_name "$role")
                log_debug "  $ai → $role_name"
            fi
        fi
    done

    # Display current role assignments
    echo -e "${YELLOW}Role Assignments:${NC} $(get_role_assignments_display)"
}

# Check for milestone role reassignments after a subtask or round
# Args: $1 = plan file, $2 = subtask id or round number
check_and_apply_milestone_roles() {
    local plan_file="$1"
    local after_id="$2"

    # Find milestones that trigger after this id
    local matching_milestones
    matching_milestones=$(jq -r --arg after "$after_id" \
        '.milestones[]? | select(.after == $after) | .id // .after' \
        "$plan_file" 2>/dev/null)

    for milestone in $matching_milestones; do
        apply_milestone_roles "$plan_file" "$milestone"
    done
}

#=============================================================================
# Helper Functions
#=============================================================================

# Check if we should checkpoint at this round
# Args: $1 = current round
#       $2 = plan file
should_checkpoint() {
    local round="$1"
    local plan_file="$2"

    # Check checkpoint level
    case "${TEAM_CHECKPOINT_LEVEL:-all}" in
        none)
            return 1
            ;;
        major)
            # Only checkpoint at milestones defined in plan
            local milestone_rounds
            milestone_rounds=$(jq -r '.milestones[]? | select(.after | test("round_?'$round'$")) | .after' "$plan_file" 2>/dev/null)
            [[ -n "$milestone_rounds" ]]
            ;;
        all)
            # Checkpoint every round
            return 0
            ;;
    esac
}

# Display response from AI
# Args: $1 = AI id
#       $2 = response file
display_response() {
    local ai="$1"
    local response_file="$2"

    if [[ -f "$response_file" ]]; then
        local ai_color
        ai_color=$(get_ai_color "$ai")
        echo ""
        echo -e "${ai_color}$(cat "$response_file")${NC}"
        echo ""
    fi
}

# Handle AI failure with retry
# Args: $1 = AI id
#       $2 = phase
#       $3 = output file
#       $4 = prompt
#       $5 = system prompt (optional)
handle_ai_failure() {
    local ai="$1"
    local phase="$2"
    local output_file="$3"
    local prompt="$4"
    local system_prompt="${5:-}"

    log_error "$ai failed during $phase"

    if [[ "${RETRY_ON_FAILURE:-true}" == "true" ]]; then
        for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
            log_warn "Retry attempt $attempt/$MAX_RETRIES for $ai..."
            sleep "${RETRY_DELAY:-5}"

            if invoke_ai "$ai" "$prompt" "$output_file" "$system_prompt"; then
                log_success "$ai recovered on retry $attempt"
                return 0
            fi
        done
    fi

    # Graceful degradation
    log_warn "Continuing without $ai for this phase"
    echo "[$(get_ai_name "$ai") was unable to respond in this phase]" > "$output_file"
    return 1
}

log_debug "Work modes module loaded"
