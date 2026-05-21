#!/usr/bin/env bash
# =============================================================================
#  core/preflight.sh — Pre-flight validation
#  Exits with code 3 on any failure. Sourced by chase.sh.
# =============================================================================

LOCKFILE="/var/run/chase.lock"

# Required tools that must exist before any module runs
REQUIRED_TOOLS=(
    bash grep awk sed find stat cat cut
    sort uniq wc date tee ss ip uname
    systemctl sysctl chmod logger mktemp comm printf
)

# Optional tools — checked and noted but not fatal
OPTIONAL_TOOLS=(
    openssl auditctl apt yum dnf apk
)

run_preflight() {
    log_info "Initialising CHASE Core Engine..."

    _check_root
    _check_bash_version
    _check_required_tools
    
    # Run OS auto-detection
    detect_os
    log_info "Host OS Detected  : ${GREEN}${CHASE_OS_NAME} ${CHASE_OS_VERSION}${RESET} (Family: ${CHASE_OS_FAMILY})"

    _check_optional_tools
    _acquire_lockfile

    log_info "Pre-flight checks passed. Starting scan."
    echo ""
}

# --- Must be root ------------------------------------------------------------
_check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf '[ERROR] CHASE must be run as root. Use: sudo ./chase.sh\n' >&2
        exit 3
    fi
    log_info "Root Privileges    : ${GREEN}OK${RESET}"
}

# --- Bash 4.0+ required for associative arrays and [[ features ---------------
_check_bash_version() {
    local major="${BASH_VERSINFO[0]}"
    if [[ "$major" -lt 4 ]]; then
        printf '[ERROR] Bash 4.0+ required (found %s). Upgrade bash.\n' \
            "$BASH_VERSION" >&2
        exit 3
    fi
    log_info "Bash Version       : ${GREEN}${BASH_VERSION} OK${RESET}"
}

# --- Hard required tools -----------------------------------------------------
_check_required_tools() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '[ERROR] Required tools missing: %s\n' "${missing[*]}" >&2
        exit 3
    fi
    log_info "Core Dependencies  : ${GREEN}OK${RESET} (${REQUIRED_TOOLS[*]})"
}

# --- Optional tools — sets feature flags used by modules ---------------------
_check_optional_tools() {
    declare -gA OPTIONAL_AVAILABLE
    local found=() missing=()

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            OPTIONAL_AVAILABLE["$tool"]=1
            found+=("$tool")
        else
            OPTIONAL_AVAILABLE["$tool"]=0
            missing+=("$tool")
        fi
    done

    [[ ${#found[@]}   -gt 0 ]] && log_info "Optional tools     : ${GREEN}found:${RESET} ${found[*]}"
    [[ ${#missing[@]} -gt 0 ]] && log_info "Optional tools     : ${DIM}absent (gracefully skipped):${RESET} ${missing[*]}"
}

# --- Lockfile — prevent concurrent scans ------------------------------------
_acquire_lockfile() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid="$(cat "$LOCKFILE" 2>/dev/null || echo '?')"
        printf '[ERROR] Another CHASE scan is running (PID %s). Lockfile: %s\n' \
            "$pid" "$LOCKFILE" >&2
        printf '        If this is stale, remove it: rm %s\n' "$LOCKFILE" >&2
        exit 3
    fi

    # Write our PID into the lockfile for diagnostics
    printf '%s\n' "$$" > "$LOCKFILE"
    log_info "Lock Acquired      : ${GREEN}${LOCKFILE}${RESET}"
}
