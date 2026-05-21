#!/usr/bin/env bash
# =============================================================================
#  lib/utils.sh — Shared utility functions used across modules
# =============================================================================

# --- HTML / JSON escaping ----------------------------------------------------
html_escape() {
    local s="$1"
    s="${s//&/\&amp;}"
    s="${s//</\&lt;}"
    s="${s//>/\&gt;}"
    s="${s//\"/\&quot;}"
    s="${s//\'/\&#39;}"
    printf '%s' "$s"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# --- File checks -------------------------------------------------------------
# Returns 0 if file exists and is readable
file_readable() { [[ -f "$1" && -r "$1" ]]; }

# Returns 0 if directory exists
dir_exists() { [[ -d "$1" ]]; }

# Get octal permissions of a file: e.g. "644"
file_perms_octal() {
    compat_stat_perms "$1" || echo "000"
}

# Get owner username of a file
file_owner() {
    compat_stat_owner "$1" || echo "unknown"
}

# --- Sysctl helper -----------------------------------------------------------
# Read a kernel parameter. Prints value or empty string if not found.
sysctl_get() {
    sysctl -n "$1" 2>/dev/null || true
}

# --- SSH config helper -------------------------------------------------------
# Read a value from an sshd_config-style file (case-insensitive key)
sshd_get_val() {
    local file="$1"
    local key="$2"
    grep -i "^${key}[[:space:]]" "$file" 2>/dev/null \
        | awk '{print $2}' | tail -1 || true
}

# --- find wrapper with safe exclusions and low priority ----------------------
# Usage: safe_find ROOT [extra find args...]
# Automatically applies: -xdev, EXCLUDE_DIRS pruning, nice/ionice, 2>/dev/null
# Uses IONICE_PREFIX from lib/compat.sh (empty string on systems without ionice).
safe_find() {
    local root="$1"
    shift
    local -a prune_args=()

    for dir in "${EXCLUDE_DIRS[@]:-/proc /sys /dev /run}"; do
        prune_args+=( -path "${dir}" -prune -o )
    done

    # IONICE_PREFIX is set by lib/compat.sh: "ionice -c 3" if available, "" otherwise.
    # We split it into an array so it expands correctly with zero words when empty.
    local -a io_prefix=()
    # shellcheck disable=SC2206
    [[ -n "${IONICE_PREFIX:-}" ]] && io_prefix=( ${IONICE_PREFIX} )

    nice -n 19 "${io_prefix[@]}" find "$root" \
        "${prune_args[@]}" \
        -xdev \
        "$@" \
        2>/dev/null || true
}

# --- Numeric comparison helper -----------------------------------------------
# is_greater_than VALUE THRESHOLD
is_greater_than() {
    local val="$1"
    local threshold="$2"
    [[ "$val" =~ ^[0-9]+$ ]] && [[ "$threshold" =~ ^[0-9]+$ ]] \
        && (( val > threshold ))
}

# --- String helpers ----------------------------------------------------------
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim()      { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
