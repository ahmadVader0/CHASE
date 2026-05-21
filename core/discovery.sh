#!/usr/bin/env bash
# =============================================================================
#  core/discovery.sh — Dynamic Module Discovery Engine
#  Sourced by chase.sh. NEVER executed directly.
# =============================================================================

declare -gA MOD_NAME_MAP
declare -gA MOD_DESC_MAP
declare -gA MOD_PRIO_MAP
declare -gA MOD_ENTRY_MAP
declare -g -a ALL_DISCOVERED_MODULES

discover_modules() {
    local mod_dir="${CHASE_DIR}/modules"
    local temp_list=""

    ALL_DISCOVERED_MODULES=()

    # Reset maps
    MOD_NAME_MAP=()
    MOD_DESC_MAP=()
    MOD_PRIO_MAP=()
    MOD_ENTRY_MAP=()

    for mod_file in "${mod_dir}"/*.sh; do
        [[ -f "$mod_file" ]] || continue
        local file_base
        file_base="$(basename "$mod_file" .sh)"

        local mod_name="$file_base"
        local mod_desc="No description provided."
        local mod_prio=50
        local mod_entry="run_${file_base}_checks"

        # Read file headers to parse tags
        while IFS= read -r line; do
            # Stop reading after the header block to optimize
            if [[ ! "$line" =~ ^# ]]; then
                # Avoid non-comment line parsing
                break
            fi

            if [[ "$line" =~ CHASE_MODULE_NAME:[[:space:]]*(.*) ]]; then
                mod_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ CHASE_MODULE_DESC:[[:space:]]*(.*) ]]; then
                mod_desc="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ CHASE_MODULE_PRIORITY:[[:space:]]*([0-9]+) ]]; then
                mod_prio="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ CHASE_MODULE_ENTRY:[[:space:]]*(.*) ]]; then
                mod_entry="${BASH_REMATCH[1]}"
            fi
        done < "$mod_file"

        # Strip carriage return and trailing space if any
        mod_name="${mod_name%$'\r'}"
        mod_desc="${mod_desc%$'\r'}"
        mod_prio="${mod_prio%$'\r'}"
        mod_entry="${mod_entry%$'\r'}"

        MOD_NAME_MAP["$file_base"]="$mod_name"
        MOD_DESC_MAP["$file_base"]="$mod_desc"
        MOD_PRIO_MAP["$file_base"]="$mod_prio"
        MOD_ENTRY_MAP["$file_base"]="$mod_entry"

        # Format priority and name for sorting, e.g. "010:iam" or "050:filesystem"
        local padded_prio
        padded_prio="$(printf '%03d' "$mod_prio")"
        temp_list="${temp_list}${padded_prio}:${file_base}"$'\n'
    done

    # Sort temp_list and populate ALL_DISCOVERED_MODULES
    if [[ -n "$temp_list" ]]; then
        while IFS=: read -r _prio key; do
            [[ -n "$key" ]] && ALL_DISCOVERED_MODULES+=( "$key" )
        done < <(echo -n "$temp_list" | sort)
    fi
}
