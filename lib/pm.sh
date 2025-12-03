#!/usr/bin/env bash
#
# The Council of Legends - Project Manager Module
# PM selection, planning, and direction logic
#

# Source utils if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${UTILS_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/utils.sh"
    export UTILS_LOADED=true
fi

#=============================================================================
# PM Selection (Reuses CJ Selection Logic)
#=============================================================================

# Select project manager based on task analysis
# Args: $1 = task description
#       $2 = available team members (space-separated)
#       $3 = output directory
# Returns: Selected PM model id
select_project_manager() {
    local task="$1"
    local team_members="$2"
    local output_dir="$3"

    # Check for baseline assessment
    local baseline_file=""
    local latest_dir
    latest_dir=$(ls -dt "$COUNCIL_ROOT/assessments/"*/ 2>/dev/null | head -1)
    if [[ -n "$latest_dir" ]] && [[ -f "$latest_dir/baseline_analysis.json" ]]; then
        baseline_file="$latest_dir/baseline_analysis.json"
    fi

    if [[ -z "$baseline_file" ]] || [[ ! -f "$baseline_file" ]]; then
        log_warn "No baseline assessment found. Using default PM selection."
        # Default: Claude for general tasks, Codex for technical tasks
        if echo "$task" | grep -qiE 'code|implement|build|program|api|database|deploy'; then
            echo "codex"
        else
            echo "claude"
        fi
        return 0
    fi

    # Use arbiter to analyze task and select PM (reuse CJ selection)
    if [[ -z "${GROQ_API_KEY:-}" ]]; then
        log_warn "GROQ_API_KEY not set. Using heuristic PM selection."
        if echo "$task" | grep -qiE 'code|implement|build|program|api|database|deploy'; then
            echo "codex"
        else
            echo "claude"
        fi
        return 0
    fi

    # Full PM selection with task analysis
    local pm_selection_dir="$output_dir/pm_selection"
    ensure_dir "$pm_selection_dir"

    # Run task analysis
    local task_analysis_file="$pm_selection_dir/task_analysis.json"
    if ! run_task_analysis_for_pm "$task" "$task_analysis_file"; then
        log_warn "Task analysis failed. Using default PM."
        echo "claude"
        return 0
    fi

    # Generate PM recommendation
    local recommendation_file="$pm_selection_dir/pm_recommendation.json"
    if ! run_pm_recommendation "$task" "$task_analysis_file" "$baseline_file" "$recommendation_file"; then
        log_warn "PM recommendation failed. Using default PM."
        echo "claude"
        return 0
    fi

    # Extract recommended PM
    local recommended_pm
    recommended_pm=$(jq -r '.recommended_pm' "$recommendation_file")

    # Validate it's a valid team member
    if ! echo "$team_members" | grep -qw "$recommended_pm"; then
        log_warn "Recommended PM '$recommended_pm' not in team. Using Claude."
        echo "claude"
        return 0
    fi

    echo "$recommended_pm"
}

#=============================================================================
# Task Analysis for PM Selection
#=============================================================================

# Analyze task for PM selection
# Args: $1 = task description
#       $2 = output file
run_task_analysis_for_pm() {
    local task="$1"
    local output_file="$2"

    log_debug "Analyzing task for PM selection..."

    # Prefer TOON, fall back to JSON
    local questionnaire_file
    if [[ -f "$COUNCIL_ROOT/config/questionnaire_v1.toon" ]]; then
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.toon"
    else
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.json"
    fi

    # Build category list (decode TOON if needed)
    local categories
    if [[ "$questionnaire_file" == *.toon ]]; then
        local toon_util="${COUNCIL_ROOT:-$SCRIPT_DIR/..}/lib/toon_util.py"
        categories=$("$toon_util" decode "$questionnaire_file" 2>/dev/null | jq -r '.categories[] | "- \(.id): \(.name)"')
    else
        categories=$(jq -r '.categories[] | "- \(.id): \(.name)"' "$questionnaire_file")
    fi

    local prompt
    prompt=$(cat <<EOF
Analyze this task and determine category relevance for PM selection.

TASK: $task

CATEGORIES:
$categories

Analyze the task and output ONLY valid JSON:
{
  "task_summary": "<1-2 sentence summary>",
  "task_type": "<implementation|design|review|research|debugging|other>",
  "complexity": "<low|medium|high>",
  "estimated_rounds": <1-5>,
  "category_weights": {
    "reasoning_logic": 0.0-1.0,
    "legal_ethical": 0.0-1.0,
    "argumentation": 0.0-1.0,
    "domain_knowledge": 0.0-1.0,
    "programming_languages": 0.0-1.0,
    "accessibility_inclusive_design": 0.0-1.0,
    "communication": 0.0-1.0,
    "meta_cognition": 0.0-1.0,
    "collaboration": 0.0-1.0
  },
  "key_skills_needed": ["skill1", "skill2"]
}
EOF
)

    # Source the Groq adapter
    local adapter_file="$SCRIPT_DIR/adapters/groq_adapter.sh"
    source "$adapter_file"

    local temp_response="${output_file}.raw"
    if ! invoke_arbiter "$prompt" "$temp_response" "task_analysis"; then
        log_error "Task analysis failed"
        return 1
    fi

    # Extract JSON
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Invalid JSON from task analysis"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    log_debug "Task analysis complete"
    return 0
}

# Generate PM recommendation based on task analysis and baselines
# Args: $1 = task
#       $2 = task analysis file
#       $3 = baseline file
#       $4 = output file
run_pm_recommendation() {
    local task="$1"
    local task_file="$2"
    local baseline_file="$3"
    local output_file="$4"

    log_debug "Generating PM recommendation..."

    # Extract task weights
    local task_weights
    task_weights=$(jq -c '.category_weights' "$task_file")

    # Extract baseline scores
    local baseline_scores
    baseline_scores=$(jq -c '[.baseline_rankings[] | {id: .id, overall: .overall_score, categories: .category_scores}]' "$baseline_file")

    local prompt
    prompt=$(cat <<EOF
Recommend the best Project Manager for this team task.

TASK: $task

TASK CATEGORY WEIGHTS (0.0-1.0):
$task_weights

BASELINE SCORES:
$baseline_scores

PM SKILLS BONUS: Weight these 1.5x extra for PM role:
- meta_cognition (self-awareness, planning)
- communication (clarity, coordination)
- collaboration (teamwork, delegation)

Calculate context-weighted scores and recommend the best PM.

Output ONLY valid JSON:
{
  "analyzed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "rankings": [
    {"id": "claude", "pm_score": 8.5, "reasoning": "..."},
    {"id": "codex", "pm_score": 7.2, "reasoning": "..."},
    {"id": "gemini", "pm_score": 7.8, "reasoning": "..."}
  ],
  "recommended_pm": "claude",
  "recommendation_reasoning": "Brief explanation..."
}
EOF
)

    # Source the Groq adapter
    local adapter_file="$SCRIPT_DIR/adapters/groq_adapter.sh"
    source "$adapter_file"

    local temp_response="${output_file}.raw"
    if ! invoke_arbiter "$prompt" "$temp_response" "pm_recommendation"; then
        log_error "PM recommendation failed"
        return 1
    fi

    # Extract JSON
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Invalid JSON from PM recommendation"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    # Display recommendation
    local recommended
    recommended=$(jq -r '.recommended_pm' "$output_file")
    local reasoning
    reasoning=$(jq -r '.recommendation_reasoning' "$output_file")

    echo -e "${YELLOW}PM Recommendation:${NC} ${BOLD}$(get_ai_name "$recommended")${NC}"
    echo "$reasoning"
    echo ""

    log_debug "PM recommendation complete"
    return 0
}

#=============================================================================
# Execution Plan Creation
#=============================================================================

# Create execution plan with PM
# Args: $1 = task
#       $2 = PM id
#       $3 = team members (space-separated)
#       $4 = output file
create_execution_plan() {
    local task="$1"
    local pm="$2"
    local team_members="$3"
    local output_file="$4"

    log_debug "Creating execution plan with $(get_ai_name "$pm")..."

    # Check if arbiter is in team
    local arbiter_available="false"
    if echo "$team_members" | grep -qw "arbiter"; then
        arbiter_available="true"
    fi

    local prompt
    prompt=$(cat <<EOF
You are the Project Manager for this team task. Create an execution plan.

TASK: $task

AVAILABLE TEAM:
$(for m in $team_members; do
    echo "- $(get_ai_name "$m")"
done)

WORK MODES:
1. pair_programming - Two AIs collaborate on same artifact, passing back and forth
2. consultation - Lead works independently, requests input from specialists
3. round_robin - All members contribute sequentially, each builds on previous
4. divide_conquer - Split task into subtasks, parallel work, merge results
5. free_form - Open collaboration, PM moderates discussion

ARBITER AVAILABLE: $arbiter_available
Consider: Include arbiter if fast reviews, tie-breaking, or extra perspective adds value.

Create a plan in JSON format:
{
  "plan": {
    "work_mode": "divide_conquer",
    "include_arbiter": false,
    "arbiter_reasoning": "Why include/exclude arbiter"
  },
  "roles": {
    "lead": "codex",
    "reviewer": "claude",
    "specialist": "gemini"
  },
  "subtasks": [
    {"id": "subtask_1", "assignee": "codex", "description": "..."},
    {"id": "subtask_2", "assignee": "claude", "description": "..."}
  ],
  "milestones": [
    {"after": "subtask_1", "description": "Review initial implementation"},
    {"after": "all_subtasks", "description": "Final integration review"}
  ],
  "estimated_rounds": 3
}

Consider the task type and complexity when choosing work mode.

CRITICAL: Your response must be ONLY valid JSON. No explanations, no questions, no markdown formatting.
Do NOT ask clarifying questions. Make reasonable assumptions based on the task description.
Start your response with { and end with }. Nothing else.
EOF
)

    # Use PM to create plan
    local system_prompt
    system_prompt="You are a Project Manager bot that outputs ONLY JSON. Never include explanations, questions, or prose. Your entire response must be valid JSON that can be parsed directly. If you need to make assumptions, make them silently and proceed with the plan."

    local temp_response="${output_file}.raw"

    # Invoke PM
    if ! invoke_ai "$pm" "$prompt" "$temp_response" "$system_prompt"; then
        log_error "$(get_ai_name "$pm") failed to create execution plan"
        return 1
    fi

    # Extract JSON
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Invalid JSON from execution plan"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    echo "$json_response" > "$output_file"
    rm -f "$temp_response"

    log_success "Execution plan created"
    return 0
}

# Adjust execution plan based on user feedback
# Args: $1 = plan file
#       $2 = user feedback
adjust_execution_plan() {
    local plan_file="$1"
    local feedback="$2"

    log_debug "Adjusting plan based on feedback..."

    local current_plan
    current_plan=$(cat "$plan_file")

    local pm="${TEAM_PM:-claude}"

    local prompt
    prompt=$(cat <<EOF
Adjust this execution plan based on user feedback.

CURRENT PLAN:
$current_plan

USER FEEDBACK:
$feedback

Update the plan to address the feedback while maintaining the JSON structure.
Output ONLY the updated JSON plan.
EOF
)

    local system_prompt
    system_prompt="You are the Project Manager adjusting the execution plan based on user feedback."

    local temp_response="${plan_file}.adjusted.raw"

    if ! invoke_ai "$pm" "$prompt" "$temp_response" "$system_prompt"; then
        log_error "Failed to adjust plan"
        return 1
    fi

    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Invalid JSON from plan adjustment"
        return 1
    fi

    echo "$json_response" > "$plan_file"
    rm -f "$temp_response"

    log_success "Plan adjusted"
    return 0
}

#=============================================================================
# Final Delivery Creation
#=============================================================================

# Create final delivery document
# Args: $1 = task
#       $2 = PM id
#       $3 = project directory
#       $4 = output file
create_final_delivery() {
    local task="$1"
    local pm="$2"
    local project_dir="$3"
    local output_file="$4"

    log_debug "Creating final delivery with $(get_ai_name "$pm")..."

    # Gather all responses from execution
    local all_responses=""
    for response_file in "$project_dir/responses/"*.md; do
        if [[ -f "$response_file" ]]; then
            all_responses+="### $(basename "$response_file" .md)
$(cat "$response_file")

"
        fi
    done

    local prompt
    prompt=$(cat <<EOF
Synthesize the final deliverable for this team task.

ORIGINAL TASK:
$task

TEAM CONTRIBUTIONS:
$all_responses

Create a comprehensive final delivery that:
1. Summarizes what was accomplished
2. Presents the main deliverable/solution
3. Notes any important considerations or caveats
4. Lists any follow-up items or future work

Format as a clear markdown document.
EOF
)

    local system_prompt
    system_prompt="You are the Project Manager synthesizing the team's work into a final deliverable."

    if ! invoke_ai "$pm" "$prompt" "$output_file" "$system_prompt"; then
        log_error "Failed to create final delivery"
        return 1
    fi

    log_success "Final delivery created"
    return 0
}

#=============================================================================
# Arbiter Questionnaire Runner
#=============================================================================

# Run questionnaire for arbiter (Groq/Llama)
# Returns: 0 on success, 1 on failure
run_arbiter_questionnaire() {
    log_info "Running questionnaire for Arbiter..."

    # Find or create assessment directory
    local latest_dir
    latest_dir=$(ls -dt "$COUNCIL_ROOT/assessments/"*/ 2>/dev/null | head -1)

    if [[ -z "$latest_dir" ]]; then
        log_warn "No assessment directory found. Running full assessment first."
        return 1
    fi

    local self_assessments_dir="$latest_dir/self_assessments"
    ensure_dir "$self_assessments_dir"

    # Prefer TOON, fall back to JSON
    local questionnaire_file
    if [[ -f "$COUNCIL_ROOT/config/questionnaire_v1.toon" ]]; then
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.toon"
    else
        questionnaire_file="$COUNCIL_ROOT/config/questionnaire_v1.json"
    fi

    local output_file="$self_assessments_dir/self_assessment_arbiter.json"

    # Build questionnaire prompt (reuse from assessment.sh)
    local prompt
    prompt=$(build_questionnaire_prompt "$questionnaire_file")

    # Invoke arbiter
    local temp_response="${output_file}.raw"

    source "$SCRIPT_DIR/adapters/groq_adapter.sh"

    if ! invoke_arbiter "$prompt" "$temp_response" "questionnaire"; then
        log_error "Arbiter failed to complete questionnaire"
        return 1
    fi

    # Extract JSON
    local json_response
    json_response=$(extract_json_from_response "$temp_response")

    if [[ -z "$json_response" ]]; then
        log_error "Arbiter returned invalid JSON"
        cat "$temp_response" > "${output_file}.invalid"
        return 1
    fi

    # Wrap with metadata
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg model_id "arbiter" \
        --arg model_name "$GROQ_MODEL" \
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

    rm -f "$temp_response"

    log_success "Arbiter completed questionnaire"
    return 0
}

log_debug "PM module loaded"
