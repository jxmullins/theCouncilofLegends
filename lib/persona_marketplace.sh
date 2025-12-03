#!/usr/bin/env bash
#
# The Council of Legends - Persona Marketplace
# Import, export, and manage personas from external sources
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNCIL_ROOT="${COUNCIL_ROOT:-$SCRIPT_DIR/..}"

# Source utilities
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
source "$SCRIPT_DIR/persona_validator.sh" 2>/dev/null || true

# Directories
PERSONAS_DIR="$COUNCIL_ROOT/config/personas"
EXPORTS_DIR="$COUNCIL_ROOT/exports/personas"
IMPORTS_DIR="$COUNCIL_ROOT/imports"
TOON_UTIL="$COUNCIL_ROOT/lib/toon_util.py"

#=============================================================================
# Export Functions
#=============================================================================

# Export a persona to a shareable package
# Args: $1 = persona ID, $2 = output directory (optional)
export_persona() {
    local persona_id="$1"
    local output_dir="${2:-$EXPORTS_DIR}"

    # Find the persona file
    local persona_file=""
    if [[ -f "$PERSONAS_DIR/${persona_id}.toon" ]]; then
        persona_file="$PERSONAS_DIR/${persona_id}.toon"
    elif [[ -f "$PERSONAS_DIR/${persona_id}.json" ]]; then
        persona_file="$PERSONAS_DIR/${persona_id}.json"
    else
        echo "Error: Persona '$persona_id' not found"
        return 1
    fi

    # Validate before export
    echo "Validating persona..."
    if ! validate_persona_file "$persona_file" >/dev/null 2>&1; then
        echo "Error: Persona validation failed"
        validate_persona_file "$persona_file"
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir"

    # Parse persona to JSON for metadata extraction
    local json
    if [[ "$persona_file" == *.toon ]]; then
        json=$(python3 "$TOON_UTIL" parse "$persona_file" 2>/dev/null)
    else
        json=$(cat "$persona_file")
    fi

    local name version author
    name=$(echo "$json" | jq -r '.name')
    version=$(echo "$json" | jq -r '.version')
    author=$(echo "$json" | jq -r '.author // "Unknown"')

    # Create export package name
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local package_name="${persona_id}_v${version}_${timestamp}"
    local package_dir="$output_dir/$package_name"

    mkdir -p "$package_dir"

    # Copy persona file (prefer TOON format)
    if [[ "$persona_file" == *.toon ]]; then
        cp "$persona_file" "$package_dir/${persona_id}.toon"
    else
        # Convert JSON to TOON for export
        if python3 "$TOON_UTIL" convert "$persona_file" "$package_dir/${persona_id}.toon" 2>/dev/null; then
            : # Success
        else
            # Fallback to JSON
            cp "$persona_file" "$package_dir/${persona_id}.json"
        fi
    fi

    # Create manifest
    cat > "$package_dir/MANIFEST.json" <<EOF
{
    "package_format": "1.0",
    "persona_id": "$persona_id",
    "persona_name": "$name",
    "version": "$version",
    "author": "$author",
    "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "exported_from": "Council of Legends",
    "council_version": "$(cat "$COUNCIL_ROOT/VERSION" 2>/dev/null || echo "unknown")",
    "checksum": "$(shasum -a 256 "$package_dir/${persona_id}".* 2>/dev/null | head -1 | cut -d' ' -f1)"
}
EOF

    # Create README
    cat > "$package_dir/README.md" <<EOF
# ${name} Persona

**ID:** ${persona_id}
**Version:** ${version}
**Author:** ${author}

## Installation

1. Copy to your Council of Legends personas directory:
   \`\`\`bash
   cp ${persona_id}.toon /path/to/council/config/personas/
   \`\`\`

2. Or use the marketplace import:
   \`\`\`bash
   ./lib/persona_marketplace.sh import ${package_name}/
   \`\`\`

## Usage

\`\`\`bash
./council.sh "Your topic" --personas claude:${persona_id}
\`\`\`

---
*Exported from The Council of Legends*
EOF

    # Create archive
    local archive_file="$output_dir/${package_name}.tar.gz"
    (cd "$output_dir" && tar -czf "${package_name}.tar.gz" "$package_name")

    echo ""
    echo "=== Export Complete ==="
    echo "Persona:  $name v$version"
    echo "Package:  $package_dir/"
    echo "Archive:  $archive_file"
    echo ""

    return 0
}

#=============================================================================
# Import Functions
#=============================================================================

# Check for version conflicts
# Args: $1 = persona ID, $2 = new version
# Returns: 0 if no conflict, 1 if conflict exists
check_version_conflict() {
    local persona_id="$1"
    local new_version="$2"

    # Check if persona exists
    if ! persona_id_exists "$persona_id"; then
        return 0  # No conflict - new persona
    fi

    # Get existing version
    local existing_file
    if [[ -f "$PERSONAS_DIR/${persona_id}.toon" ]]; then
        existing_file="$PERSONAS_DIR/${persona_id}.toon"
    else
        existing_file="$PERSONAS_DIR/${persona_id}.json"
    fi

    local existing_version
    if [[ "$existing_file" == *.toon ]]; then
        existing_version=$(python3 "$TOON_UTIL" parse "$existing_file" 2>/dev/null | jq -r '.version')
    else
        existing_version=$(jq -r '.version' "$existing_file")
    fi

    if [[ "$existing_version" == "$new_version" ]]; then
        echo "same"  # Same version
        return 1
    fi

    # Compare versions (simple semver comparison)
    local existing_major existing_minor existing_patch
    local new_major new_minor new_patch

    IFS='.' read -r existing_major existing_minor existing_patch <<< "$existing_version"
    IFS='.' read -r new_major new_minor new_patch <<< "$new_version"

    if [[ "$new_major" -gt "$existing_major" ]] || \
       [[ "$new_major" -eq "$existing_major" && "$new_minor" -gt "$existing_minor" ]] || \
       [[ "$new_major" -eq "$existing_major" && "$new_minor" -eq "$existing_minor" && "$new_patch" -gt "$existing_patch" ]]; then
        echo "upgrade"  # New version is newer
        return 1
    else
        echo "downgrade"  # New version is older
        return 1
    fi
}

# Import a persona from a package or file
# Args: $1 = path to persona file or package directory
#       $2 = conflict resolution: "skip", "overwrite", "backup", "rename" (default: prompt)
import_persona() {
    local source="$1"
    local conflict_mode="${2:-prompt}"

    if [[ ! -e "$source" ]]; then
        echo "Error: Source not found: $source"
        return 1
    fi

    local persona_file=""
    local manifest_file=""
    local source_dir=""

    # Handle different source types
    if [[ -d "$source" ]]; then
        # Package directory
        source_dir="$source"
        for f in "$source_dir"/*.toon "$source_dir"/*.json; do
            if [[ -f "$f" ]] && [[ "$(basename "$f")" != "MANIFEST.json" ]]; then
                persona_file="$f"
                break
            fi
        done
        manifest_file="$source_dir/MANIFEST.json"
    elif [[ "$source" == *.tar.gz ]]; then
        # Archive - extract first
        local temp_dir
        temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/persona_import.XXXXXX")
        tar -xzf "$source" -C "$temp_dir"

        # Find the extracted directory
        source_dir=$(find "$temp_dir" -maxdepth 1 -type d | tail -1)
        for f in "$source_dir"/*.toon "$source_dir"/*.json; do
            if [[ -f "$f" ]] && [[ "$(basename "$f")" != "MANIFEST.json" ]]; then
                persona_file="$f"
                break
            fi
        done
        manifest_file="$source_dir/MANIFEST.json"
    else
        # Single file
        persona_file="$source"
    fi

    if [[ ! -f "$persona_file" ]]; then
        echo "Error: No persona file found in source"
        return 1
    fi

    # Validate the persona
    echo "Validating persona..."
    if ! validate_persona_file "$persona_file"; then
        echo "Error: Persona validation failed"
        return 1
    fi

    # Extract persona info
    local json
    if [[ "$persona_file" == *.toon ]]; then
        json=$(python3 "$TOON_UTIL" parse "$persona_file" 2>/dev/null)
    else
        json=$(cat "$persona_file")
    fi

    local persona_id name version author
    persona_id=$(echo "$json" | jq -r '.id')
    name=$(echo "$json" | jq -r '.name')
    version=$(echo "$json" | jq -r '.version')
    author=$(echo "$json" | jq -r '.author // "Unknown"')

    echo ""
    echo "=== Importing Persona ==="
    echo "ID:      $persona_id"
    echo "Name:    $name"
    echo "Version: $version"
    echo "Author:  $author"

    # Check for conflicts
    local conflict_type
    conflict_type=$(check_version_conflict "$persona_id" "$version")
    local conflict_code=$?

    if [[ $conflict_code -ne 0 ]]; then
        echo ""
        echo "Conflict detected: $conflict_type"

        case "$conflict_mode" in
            skip)
                echo "Skipping import (conflict mode: skip)"
                return 0
                ;;
            overwrite)
                echo "Overwriting existing persona (conflict mode: overwrite)"
                ;;
            backup)
                echo "Backing up existing persona..."
                backup_persona "$persona_id"
                ;;
            rename)
                # Generate new ID
                local new_id="${persona_id}_imported_$(date +%Y%m%d)"
                echo "Renaming to: $new_id"

                # Modify the persona file with new ID
                local temp_file
                temp_file=$(mktemp "${TMPDIR:-/tmp}/persona_rename.XXXXXX")

                if [[ "$persona_file" == *.toon ]]; then
                    # Update TOON file
                    sed "s/^id: .*/id: $new_id/" "$persona_file" > "$temp_file"
                    cp "$temp_file" "$PERSONAS_DIR/${new_id}.toon"
                else
                    # Update JSON file
                    jq --arg id "$new_id" '.id = $id' "$persona_file" > "$PERSONAS_DIR/${new_id}.json"
                fi

                rm -f "$temp_file"
                echo "Imported as: $new_id"
                return 0
                ;;
            prompt|*)
                echo ""
                echo "Options:"
                echo "  1) Overwrite existing"
                echo "  2) Backup existing, then import"
                echo "  3) Import with new ID"
                echo "  4) Skip"
                echo ""
                read -rp "Choose [1-4]: " choice

                case "$choice" in
                    1) import_persona "$source" "overwrite" ;;
                    2) import_persona "$source" "backup" ;;
                    3) import_persona "$source" "rename" ;;
                    4) echo "Skipped."; return 0 ;;
                    *) echo "Invalid choice. Skipping."; return 1 ;;
                esac
                return $?
                ;;
        esac
    fi

    # Copy persona to personas directory
    local dest_file
    if [[ "$persona_file" == *.toon ]]; then
        dest_file="$PERSONAS_DIR/${persona_id}.toon"
    else
        dest_file="$PERSONAS_DIR/${persona_id}.json"
    fi

    cp "$persona_file" "$dest_file"

    echo ""
    echo "=== Import Complete ==="
    echo "Installed: $dest_file"
    echo ""
    echo "Usage: ./council.sh \"topic\" --personas claude:$persona_id"
    echo ""

    # Cleanup temp directory if we created one
    if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
    fi

    return 0
}

# Backup an existing persona before overwriting
# Args: $1 = persona ID
backup_persona() {
    local persona_id="$1"
    local backup_dir="$COUNCIL_ROOT/backups/personas"

    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    for ext in toon json; do
        local file="$PERSONAS_DIR/${persona_id}.$ext"
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_dir/${persona_id}_${timestamp}.$ext"
            echo "Backed up: $backup_dir/${persona_id}_${timestamp}.$ext"
        fi
    done
}

#=============================================================================
# Search and Discovery
#=============================================================================

# Search personas by tag
# Args: $1 = tag to search for
search_by_tag() {
    local search_tag="$1"
    local matches=()

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ ! -f "$file" ]]; then
            continue
        fi

        local json
        if [[ "$file" == *.toon ]]; then
            json=$(python3 "$TOON_UTIL" parse "$file" 2>/dev/null) || continue
        else
            json=$(cat "$file")
        fi

        local tags
        tags=$(echo "$json" | jq -r '.tags[]? // empty' 2>/dev/null)

        if echo "$tags" | grep -qi "$search_tag"; then
            local id name
            id=$(echo "$json" | jq -r '.id')
            name=$(echo "$json" | jq -r '.name')
            matches+=("$id|$name|$(echo "$tags" | tr '\n' ',')")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "No personas found with tag: $search_tag"
        return 1
    fi

    echo ""
    echo "=== Personas with tag '$search_tag' ==="
    echo ""
    for match in "${matches[@]}"; do
        IFS='|' read -r id name tags <<< "$match"
        printf "  %-20s %s\n" "$id" "$name"
        printf "    Tags: %s\n" "${tags%,}"
    done
    echo ""
}

# Search personas by keyword in description or name
# Args: $1 = keyword to search for
search_by_keyword() {
    local keyword="$1"
    local matches=()

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ ! -f "$file" ]]; then
            continue
        fi

        local json
        if [[ "$file" == *.toon ]]; then
            json=$(python3 "$TOON_UTIL" parse "$file" 2>/dev/null) || continue
        else
            json=$(cat "$file")
        fi

        local name description
        name=$(echo "$json" | jq -r '.name')
        description=$(echo "$json" | jq -r '.description')

        if echo "$name $description" | grep -qi "$keyword"; then
            local id
            id=$(echo "$json" | jq -r '.id')
            matches+=("$id|$name|$description")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "No personas found matching: $keyword"
        return 1
    fi

    echo ""
    echo "=== Personas matching '$keyword' ==="
    echo ""
    for match in "${matches[@]}"; do
        IFS='|' read -r id name description <<< "$match"
        printf "  %-20s %s\n" "$id" "$name"
        printf "    %s\n" "$description"
    done
    echo ""
}

# Show detailed info about a persona
# Args: $1 = persona ID
show_persona_info() {
    local persona_id="$1"

    local persona_file=""
    if [[ -f "$PERSONAS_DIR/${persona_id}.toon" ]]; then
        persona_file="$PERSONAS_DIR/${persona_id}.toon"
    elif [[ -f "$PERSONAS_DIR/${persona_id}.json" ]]; then
        persona_file="$PERSONAS_DIR/${persona_id}.json"
    else
        echo "Error: Persona '$persona_id' not found"
        return 1
    fi

    local json
    if [[ "$persona_file" == *.toon ]]; then
        json=$(python3 "$TOON_UTIL" parse "$persona_file" 2>/dev/null)
    else
        json=$(cat "$persona_file")
    fi

    echo ""
    echo "=== Persona Details ==="
    echo ""
    echo "ID:          $(echo "$json" | jq -r '.id')"
    echo "Name:        $(echo "$json" | jq -r '.name')"
    echo "Version:     $(echo "$json" | jq -r '.version')"
    echo "Author:      $(echo "$json" | jq -r '.author // "Unknown"')"
    echo "Description: $(echo "$json" | jq -r '.description')"
    echo ""
    echo "Tags:        $(echo "$json" | jq -r '.tags | if type=="array" then join(", ") else . end')"
    echo ""
    echo "Style:"
    echo "  Tone:      $(echo "$json" | jq -r '.style.tone // "Not specified"')"
    echo "  Approach:  $(echo "$json" | jq -r '.style.approach // "Not specified"')"
    echo "  Strengths: $(echo "$json" | jq -r '.style.strengths | if type=="array" then join(", ") else . end')"
    echo ""
    echo "Compatibility:"
    echo "  Debate modes:  $(echo "$json" | jq -r '.compatibility.debate_modes | if type=="array" then join(", ") else "all" end')"
    echo "  Works well with: $(echo "$json" | jq -r '.compatibility.works_well_with | if type=="array" then join(", ") else "all" end')"
    echo ""
    echo "File: $persona_file"
    echo ""
}

#=============================================================================
# Bulk Operations
#=============================================================================

# Export all personas
export_all() {
    local output_dir="${1:-$EXPORTS_DIR}"
    local count=0

    echo "Exporting all personas to: $output_dir"
    echo ""

    for file in "$PERSONAS_DIR"/*.toon "$PERSONAS_DIR"/*.json; do
        if [[ -f "$file" ]]; then
            local basename
            basename=$(basename "$file")
            local id="${basename%.*}"

            echo "Exporting: $id"
            if export_persona "$id" "$output_dir" >/dev/null 2>&1; then
                ((count++))
            else
                echo "  Failed to export $id"
            fi
        fi
    done

    echo ""
    echo "Exported $count personas to: $output_dir"
}

# Import all personas from a directory
import_all() {
    local source_dir="$1"
    local conflict_mode="${2:-skip}"
    local count=0
    local failed=0

    if [[ ! -d "$source_dir" ]]; then
        echo "Error: Directory not found: $source_dir"
        return 1
    fi

    echo "Importing personas from: $source_dir"
    echo "Conflict mode: $conflict_mode"
    echo ""

    # Look for persona files and packages
    for item in "$source_dir"/*.toon "$source_dir"/*.json "$source_dir"/*/; do
        if [[ -e "$item" ]]; then
            echo "Processing: $(basename "$item")"
            if import_persona "$item" "$conflict_mode" >/dev/null 2>&1; then
                ((count++))
            else
                ((failed++))
            fi
        fi
    done

    echo ""
    echo "Imported: $count"
    echo "Failed:   $failed"
}

#=============================================================================
# CLI Interface
#=============================================================================

show_help() {
    cat <<EOF
Usage: persona_marketplace.sh [command] [options]

Commands:
    export <id> [dir]       Export a persona to a shareable package
    export-all [dir]        Export all personas
    import <source> [mode]  Import a persona from file, directory, or archive
                            Conflict modes: skip, overwrite, backup, rename, prompt (default)
    import-all <dir> [mode] Import all personas from a directory

    search-tag <tag>        Find personas by tag
    search <keyword>        Find personas by name/description keyword
    info <id>               Show detailed info about a persona

    backup <id>             Backup a persona

    help                    Show this help message

Examples:
    ./lib/persona_marketplace.sh export philosopher
    ./lib/persona_marketplace.sh export educator ~/Desktop/
    ./lib/persona_marketplace.sh import downloaded_persona.toon
    ./lib/persona_marketplace.sh import ~/Downloads/my_persona_v1.0.0.tar.gz
    ./lib/persona_marketplace.sh import persona_package/ overwrite
    ./lib/persona_marketplace.sh search-tag ethics
    ./lib/persona_marketplace.sh search "clear explanations"
    ./lib/persona_marketplace.sh info educator
EOF
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        export)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a persona ID to export"
                exit 1
            fi
            export_persona "$1" "${2:-}"
            ;;
        export-all)
            export_all "${1:-}"
            ;;
        import)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a source to import"
                exit 1
            fi
            import_persona "$1" "${2:-prompt}"
            ;;
        import-all)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a directory to import from"
                exit 1
            fi
            import_all "$1" "${2:-skip}"
            ;;
        search-tag)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a tag to search for"
                exit 1
            fi
            search_by_tag "$1"
            ;;
        search)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a keyword to search for"
                exit 1
            fi
            search_by_keyword "$1"
            ;;
        info)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a persona ID"
                exit 1
            fi
            show_persona_info "$1"
            ;;
        backup)
            if [[ -z "$1" ]]; then
                echo "Error: Please specify a persona ID to backup"
                exit 1
            fi
            backup_persona "$1"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
