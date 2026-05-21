#!/usr/bin/env bash
# =============================================================================
#  CHASE — Configuration & Host Audit Security Evaluator
#  Entry point. Run as: sudo ./chase.sh [options]
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Version & Constants -----------------------------------------------------
CHASE_VERSION="2.0"
CHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exit codes
EXIT_CLEAN=0
EXIT_WARNING=1     # Medium or low findings only
EXIT_CRITICAL=2    # High or critical findings present
EXIT_ERROR=3       # Execution/system error

# --- Default CLI options (overridden by flags below) -------------------------
OPT_OUTPUT_DIR=""
OPT_MODULES=""
OPT_QUICK=0
OPT_DELTA=0
OPT_NO_COLOUR=0
OPT_VERBOSE=0
OPT_QUIET=0
OPT_REMEDIATE=0

# --- Parse CLI arguments -----------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)  OPT_OUTPUT_DIR="$2"; shift 2 ;;
            --modules)     OPT_MODULES="$2";    shift 2 ;;
            --quick)       OPT_QUICK=1;         shift   ;;
            --delta)       OPT_DELTA=1;         shift   ;;
            --no-colour)   OPT_NO_COLOUR=1;     shift   ;;
            --verbose|-v)  OPT_VERBOSE=1;       shift   ;;
            --quiet|-q)    OPT_QUIET=1;         shift   ;;
            --remediate|-r) OPT_REMEDIATE=1;    shift   ;;
            --version)     echo "CHASE Security Auditor v${CHASE_VERSION}"; exit 0 ;;
            --help|-h)     usage; exit 0               ;;
            *)             echo "Unknown option: $1"; usage; exit "$EXIT_ERROR" ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: sudo ./chase.sh [OPTIONS]

Options:
  --output-dir DIR    Save reports to DIR (default: /var/log/chase)
  --modules LIST      Comma-separated module list (short or full names)
                        Short names : iam, filesystem, network, software, persistence
                        Examples    : --modules iam,network
  --quick             Skip slow filesystem traversal (world-writable scans)
  --delta             Show diff vs last scan findings
  --no-colour         Plain text output (disabled ANSI colors)
  --verbose, -v       Verbose output with detailed logs
  --quiet, -q         Minimal output (only critical alerts and summary)
  --remediate, -r     Run interactive remediation wizard after scan
  --version           Show version and exit
  --help, -h          Show this message

Exit codes:
  0 = Clean (no findings above LOW)
  1 = Warning (MEDIUM or LOW findings only)
  2 = Critical (HIGH or CRITICAL findings present)
  3 = Execution Error (not root, missing tool, etc.)
EOF
}

# --- Source core components --------------------------------------------------
source_core() {
    source "${CHASE_DIR}/core/logger.sh"
    source "${CHASE_DIR}/core/preflight.sh"
    source "${CHASE_DIR}/core/discovery.sh"
    source "${CHASE_DIR}/lib/utils.sh"
    source "${CHASE_DIR}/lib/compat.sh"
}

# --- Load configuration ------------------------------------------------------
load_config() {
    local conf="${CHASE_DIR}/config/chase.conf"
    if [[ -f "$conf" ]]; then
        source "$conf"
    else
        log_warn "config/chase.conf not found — using built-in defaults"
        # Built-in defaults so the script still works without a conf file
        REPORT_DIR="/var/log/chase"
        CERT_WARN_DAYS=30
        CERT_CRIT_DAYS=7
        SYSLOG_ENABLED=0
        SYSLOG_TAG="chase"
        ETC_DIR="/etc"
        EXCLUDE_DIRS=( /proc /sys /dev /run /snap /mnt /media )
        MODULES=( "${ALL_DISCOVERED_MODULES[@]}" )
        BENCHMARK="cis_level1"
        SUID_BASELINE_MAX_AGE_DAYS=30
    fi

    # Fallback if MODULES is empty
    if [[ ${#MODULES[@]} -eq 0 ]]; then
        MODULES=( "${ALL_DISCOVERED_MODULES[@]}" )
    fi

    # CLI overrides
    [[ -n "$OPT_OUTPUT_DIR" ]] && REPORT_DIR="$OPT_OUTPUT_DIR"

    # --modules flag: map short name to file suffix
    if [[ -n "$OPT_MODULES" ]]; then
        declare -A _SHORT_TO_MOD=(
            [iam]="iam"
            [filesystem]="filesystem"
            [network]="network"
            [software]="software_kernel"
            [persistence]="persistence_crypto"
        )
        MODULES=()
        local token
        IFS=',' read -ra _raw_modules <<< "$OPT_MODULES"
        for token in "${_raw_modules[@]}"; do
            token="${token// /}"   # strip accidental spaces
            if [[ -n "${_SHORT_TO_MOD[$token]:-}" ]]; then
                MODULES+=( "${_SHORT_TO_MOD[$token]}" )
            else
                local found=0
                for d_mod in "${ALL_DISCOVERED_MODULES[@]}"; do
                    if [[ "$d_mod" == "$token" ]]; then
                        MODULES+=( "$d_mod" )
                        found=1
                        break
                    fi
                done
                [[ "$found" -eq 0 ]] && MODULES+=( "$token" )
            fi
        done
    fi
}

# --- Cleanup — always runs on EXIT -------------------------------------------
_CLEANUP_DONE=0
cleanup() {
    [[ "$_CLEANUP_DONE" -eq 1 ]] && return
    _CLEANUP_DONE=1
    [[ -n "${TMP_FINDINGS_FILE:-}" && -f "$TMP_FINDINGS_FILE" ]] && rm -f "$TMP_FINDINGS_FILE"
    [[ -f "${LOCKFILE:-}" ]] && rm -f "$LOCKFILE"
}

# --- Run all enabled modules -------------------------------------------------
run_modules() {
    # Initialize the live TUI status if applicable
    init_live_status

    local total="${#MODULES[@]}"
    local idx=0

    for mod in "${MODULES[@]}"; do
        idx=$(( idx + 1 ))
        local mod_file="${CHASE_DIR}/modules/${mod}.sh"

        if [[ ! -f "$mod_file" ]]; then
            log_warn "Module file not found — skipping: ${mod_file}"
            continue
        fi

        local entrypoint="${MOD_ENTRY_MAP[$mod]:-run_${mod}_checks}"
        local friendly_name="${MOD_NAME_MAP[$mod]:-$mod}"

        CHASE_CURRENT_MODULE="$mod"
        if [[ "${CHASE_LIVE_TUI:-0}" -eq 1 ]]; then
            CHASE_MOD_STATUS["$mod"]="RUNNING"
            draw_live_status
        else
            log_section "Running Module ${idx}/${total}: ${friendly_name}"
        fi

        source "$mod_file"
        if declare -f "$entrypoint" &>/dev/null; then
            "$entrypoint"
        else
            if [[ "${CHASE_LIVE_TUI:-0}" -ne 1 ]]; then
                log_warn "No entry-point registered for module '${mod}' — skipping execution"
            fi
        fi

        if [[ "${CHASE_LIVE_TUI:-0}" -eq 1 ]]; then
            local f_count=${CHASE_MOD_FINDINGS["$mod"]:-0}
            if [[ "$f_count" -gt 0 ]]; then
                CHASE_MOD_STATUS["$mod"]="FINDINGS"
            else
                CHASE_MOD_STATUS["$mod"]="PASSED"
            fi
            draw_live_status
        fi
    done

    CHASE_SCAN_ACTIVE=0
}

# --- Determine exit code from findings ---------------------------------------
compute_exit_code() {
    if grep -qE '^(CRITICAL|HIGH)\t' "$TMP_FINDINGS_FILE" 2>/dev/null; then
        return "$EXIT_CRITICAL"
    elif grep -qE '^(MEDIUM|LOW)\t' "$TMP_FINDINGS_FILE" 2>/dev/null; then
        return "$EXIT_WARNING"
    else
        return "$EXIT_CLEAN"
    fi
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    parse_args "$@"

    source_core
    
    # Run module auto-discovery first
    discover_modules
    
    print_banner
    load_config

    [[ "$OPT_NO_COLOUR" -eq 1 ]] && NO_COLOUR=1

    # Run preflight — exits with code EXIT_ERROR on failure
    run_preflight

    # Create temp findings file under REPORT_DIR
    mkdir -p "$REPORT_DIR"
    TMP_FINDINGS_FILE="$(mktemp "${REPORT_DIR}/chase_findings.XXXXXX")" \
        || TMP_FINDINGS_FILE="$(mktemp /tmp/chase_findings.XXXXXX)"
    chmod 600 "$TMP_FINDINGS_FILE"
    export TMP_FINDINGS_FILE

    # Register cleanup for normal exit, Ctrl-C, and kill
    trap 'cleanup' EXIT INT TERM

    run_modules

    source "${CHASE_DIR}/core/reporting.sh"

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local report_base="${REPORT_DIR}/chase_report_${timestamp}"

    apply_suppressions "${CHASE_DIR}/config/suppressions.list"

    generate_json_report "${report_base}.json"
    generate_html_report "${report_base}.html"

    [[ "$OPT_DELTA" -eq 1 ]] && run_delta_report

    print_summary "${report_base}"

    local run_wiz="$OPT_REMEDIATE"
    if [[ "$run_wiz" -eq 0 && -t 0 && -t 1 ]]; then
        if [[ -s "$TMP_FINDINGS_FILE" ]]; then
            printf "\n  ${CRIMSON}»»»${RESET} Would you like to run the interactive remediation wizard now? [y/N]: "
            local ans
            read -r ans 2>/dev/null || ans="n"
            if [[ "$(to_lower "$ans")" =~ ^(y|yes)$ ]]; then
                run_wiz=1
            fi
        fi
    fi

    if [[ "$run_wiz" -eq 1 ]]; then
        run_remediation_wizard
    fi

    # Return exit code based on findings
    compute_exit_code
    exit $?
}

main "$@"
