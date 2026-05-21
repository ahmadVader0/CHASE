#!/usr/bin/env bash
# =============================================================================
#  core/logger.sh — Advanced terminal layout, colors, and TUI
#  Sourced by chase.sh; never executed directly.
# =============================================================================

# --- ANSI Vampire/Bloodhound color codes --------------------------------------
_ansi() {
    [[ "${NO_COLOUR:-0}" -eq 1 ]] && printf '' || printf '%b' "$1"
}

# Thematic Colors (Vampire/Bloodhound Theme)
_C1="$(_ansi '\033[38;5;196m')"      # Bright Crimson
_C2="$(_ansi '\033[38;5;160m')"      # Ruby Red
_C3="$(_ansi '\033[38;5;124m')"      # Classic Red
_C4="$(_ansi '\033[38;5;131m')"      # Dark Rust Red
_C5="$(_ansi '\033[38;5;88m')"       # Deep Burgundy

RED="$(_ansi '\033[1;31m')"
CRIMSON="$(_ansi '\033[38;5;160m')"
ORANGE="$(_ansi '\033[38;5;214m')"
YELLOW="$(_ansi '\033[1;33m')"
GREEN="$(_ansi '\033[1;32m')"
CYAN="$(_ansi '\033[1;36m')"
BLUE="$(_ansi '\033[1;34m')"
WHITE="$(_ansi '\033[1;37m')"
ASH="$(_ansi '\033[38;5;246m')"      # Ash Grey
CHARCOAL="$(_ansi '\033[38;5;239m')" # Charcoal Grey
DIM="$(_ansi '\033[2m')"
BOLD="$(_ansi '\033[1m')"
RESET="$(_ansi '\033[0m')"

# Log output formatters (suppressed when live TUI scan is active)
log_crit()    { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${RED}${BOLD}[CRITICAL]${RESET} %s\n"  "$1"; }
log_high()    { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${ORANGE}${BOLD}[HIGH]${RESET}     %s\n"  "$1"; }
log_med()     { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${YELLOW}[MEDIUM]   %s${RESET}\n"  "$1"; }
log_low()     { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${ASH}[LOW]      %s${RESET}\n"  "$1"; }
log_ok()      { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${GREEN}[PASS]     ${RESET}%s\n"  "$1"; }
log_info()    { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${CYAN}[INFO]${RESET}     %s\n"  "$1"; }
log_warn()    { [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] || printf "${YELLOW}[WARN]${RESET}     %s\n"  "$1"; }

log_section() {
    [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]] && return 0
    printf "\n${BOLD}${CRIMSON}»»» %s${RESET}\n" "$1"
    printf "${CHARCOAL}%0.s─${RESET}" {1..60}
    printf '\n'
}

# Simple loading spinner
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep -w "$pid")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# =============================================================================
#  _draw_logo — Advanced pixel letters spelling CHASE
# =============================================================================
_draw_logo() {
    printf '\n'
    printf "  ${CRIMSON}╔══════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "  ${CRIMSON}║${RESET}   ${_C1}██████╗${RESET}██╗  ██╗ ${_C2}█████╗${RESET} ${_C3}███████╗${RESET}${_C4}███████╗${RESET}                                ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}  ${_C1}██╔════╝${RESET}██║  ██║${_C2}██╔══██╗${RESET}${_C3}██╔════╝${RESET}${_C4}██╔════╝${RESET}                                ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}  ${_C1}██║     ${RESET}███████║${_C2}███████║${RESET}${_C3}███████╗${RESET}${_C4}█████╗${RESET}                                  ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}  ${_C1}██║     ${RESET}██╔══██║${_C2}██╔══██║${RESET}${_C3}╚════██║${RESET}${_C4}██╔══╝${RESET}                                  ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}  ${_C1}╚██████╗${RESET}██║  ██║${_C2}██║  ██║${RESET}${_C3}███████║${RESET}${_C4}███████╗${RESET}                                ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}   ${_C1}╚═════╝${RESET}╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝                                ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}                                                                          ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}  ${BOLD}${WHITE}CHASE${RESET} — Configuration & Host Audit Security Evaluator v${CHASE_VERSION}          ${CRIMSON}║${RESET}\n"
    
    local os_str="${CHASE_OS_NAME:-Linux} ${CHASE_OS_VERSION:-}"
    local sys_info
    sys_info="Host: $(hostname) | OS: $os_str | Kernel: $(uname -r)"
    printf "  ${CRIMSON}║${RESET}  ${CHARCOAL}%-70s${RESET}  ${CRIMSON}║${RESET}\n" "$sys_info"
    printf "  ${CRIMSON}╚══════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    printf '\n'
}

_draw_menu() {
    printf "     ${CRIMSON}┌─────────────────────────────────────────────────────────┐${RESET}\n"
    printf "     ${CRIMSON}│${RESET}   ${BOLD}${WHITE}CHASE OPERATIONS DASHBOARD${RESET}  ${CHARCOAL}│${RESET} Host Vulnerability Sentry  ${CRIMSON}│${RESET}\n"
    printf "     ${CRIMSON}└─────────────────────────────────────────────────────────┘${RESET}\n"
    printf '\n'
    printf "     ${CHARCOAL}┌─────────────────────────────────────────────────────────┐${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${_C1}[ 1 ]${RESET}  ${BOLD}${WHITE}Initiate Security Audit Scan${RESET}                  ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${_C2}[ 2 ]${RESET}  Select & Execute Specific Modules          ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${_C3}[ 3 ]${RESET}  List Loaded Audit Module Plugins           ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${_C4}[ 4 ]${RESET}  Review Active Configurations               ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${_C5}[ 5 ]${RESET}  Inspect Generated Audit Reports            ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}│${RESET}  ${ASH}[ 6 ]${RESET}  Exit Operations Control                    ${CHARCOAL}│${RESET}\n"
    printf "     ${CHARCOAL}└─────────────────────────────────────────────────────────┘${RESET}\n"
    printf '\n'
}

print_banner() {
    if [[ ! -t 0 ]]; then
        return 0
    fi

    clear
    _draw_logo

    while true; do
        _draw_menu
        printf "   ${CRIMSON}»»»${RESET} Select option ${_C1}[1-6]${RESET}: "
        local choice
        read -r choice 2>/dev/null || choice=""
        printf '\n'

        case "$choice" in
            1|"")
                clear
                log_info "Initiating full audit scan...\n"
                break
                ;;
            2)
                clear
                printf "   ${_C1}Available Modules to Audit:${RESET}\n\n"
                local idx=0
                declare -A _MOD_INDEX_MAP
                for m_key in "${ALL_DISCOVERED_MODULES[@]}"; do
                    idx=$(( idx + 1 ))
                    local padded_idx
                    padded_idx="$(printf '%02d' "$idx")"
                    _MOD_INDEX_MAP["$padded_idx"]="$m_key"
                    _MOD_INDEX_MAP["$idx"]="$m_key" # Support both 01 and 1
                    
                    local m_name="${MOD_NAME_MAP[$m_key]:-$m_key}"
                    local m_desc="${MOD_DESC_MAP[$m_key]:-}"
                    
                    # Cycle through colors C1 to C5
                    local mod_color_idx=$(( (idx - 1) % 5 + 1 ))
                    local color_var="_C${mod_color_idx}"
                    local color_code="${!color_var}"
                    
                    printf "     ${color_code}%s${RESET}  %-20s — %s\n" "$padded_idx" "$m_key" "$m_desc"
                done
                printf '\n'
                printf "   ${CRIMSON}»»»${RESET} Select modules to run ${_C1}[e.g. 01,03 or 1,2 or iam,network]${RESET}: "
                local mod_input
                read -r mod_input 2>/dev/null || mod_input="01"
                printf '\n'
                
                mod_input="${mod_input//[[:space:]]/}" # strip spaces
                
                local normalized_list=()
                local token
                IFS=',' read -ra _raw_tokens <<< "$mod_input"
                for token in "${_raw_tokens[@]}"; do
                    if [[ -n "${_MOD_INDEX_MAP[$token]:-}" ]]; then
                        normalized_list+=( "${_MOD_INDEX_MAP[$token]}" )
                    else
                        normalized_list+=( "$token" )
                    fi
                done

                OPT_MODULES=$(IFS=,; echo "${normalized_list[*]}")
                clear
                log_info "Initiating target module(s) scan: ${OPT_MODULES}\n"
                break
                ;;
            3)
                clear
                printf "   ${BOLD}${WHITE}CHASE System Modules${RESET}\n"
                printf "   ${CHARCOAL}─────────────────────────────────────────────────────${RESET}\n\n"
                local idx=0
                for m_key in "${ALL_DISCOVERED_MODULES[@]}"; do
                    idx=$(( idx + 1 ))
                    local m_name="${MOD_NAME_MAP[$m_key]:-$m_key}"
                    
                    local mod_color_idx=$(( (idx - 1) % 5 + 1 ))
                    local color_var="_C${mod_color_idx}"
                    local color_code="${!color_var}"
                    
                    printf "   ${color_code}%-25s${RESET}  %s\n" "${m_key}.sh" "$m_name"
                done
                printf '\n'
                printf "   ${ASH}Press Enter to return to menu...${RESET} "
                read -r 2>/dev/null || true
                clear
                _draw_logo
                ;;
            4)
                clear
                printf "   ${BOLD}${WHITE}Configuration System${RESET} ${DIM}(config/chase.conf)${RESET}\n"
                printf "   ${CHARCOAL}─────────────────────────────────────────────────────${RESET}\n\n"
                printf "   ${_C1}REPORT_DIR${RESET}                 — where HTML/JSON reports are saved\n"
                printf "   ${_C2}MODULES${RESET}                    — which modules run by default\n"
                printf "   ${_C3}EXCLUDE_DIRS${RESET}               — paths skipped during filesystem scans\n"
                printf "   ${_C4}CERT_WARN_DAYS / CRIT${RESET}      — thresholds for SSL cert warning alerts\n"
                printf "   ${_C5}SYSLOG_ENABLED${RESET}             — set to 1 to forward findings to syslog\n"
                printf "   ${_C1}BENCHMARK${RESET}                  — filter checks by level (cis_level1/2)\n"
                printf "   ${_C2}SUID_BASELINE_MAX_AGE_DAYS${RESET} — age warning threshold for SUID whitelist\n"
                printf '\n'
                printf "   ${ASH}Press Enter to return to menu...${RESET} "
                read -r 2>/dev/null || true
                clear
                _draw_logo
                ;;
            5)
                clear
                local rdir="${REPORT_DIR:-/var/log/chase}"
                printf "   ${BOLD}${WHITE}Recent Reports${RESET} ${DIM}(${rdir})${RESET}\n"
                printf "   ${CHARCOAL}─────────────────────────────────────────────────────${RESET}\n\n"
                if [[ -d "$rdir" ]]; then
                    local reports
                    reports="$(ls -t "${rdir}"/chase_report_*.html 2>/dev/null | head -10)"
                    if [[ -n "$reports" ]]; then
                        while IFS= read -r r; do
                            printf "   ${GREEN}▶${RESET}  %s\n" "$(basename "$r")"
                        done <<< "$reports"
                    else
                        printf "   ${ASH}No reports yet. Run option 1 first.${RESET}\n"
                    fi
                else
                    printf "   ${ASH}Report directory not found: ${rdir}${RESET}\n"
                fi
                printf '\n'
                printf "   ${ASH}Press Enter to return to menu...${RESET} "
                read -r 2>/dev/null || true
                clear
                _draw_logo
                ;;
            6|q|Q|exit|quit)
                clear
                printf "\n   ${ASH}Exiting CHASE. Remain vigilant.${RESET}\n\n"
                exit 0
                ;;
            *)
                clear
                printf "   ${YELLOW}[WARN]${RESET} Invalid option '${choice}' — please choose 1-6.\n\n"
                _draw_logo
                ;;
        esac
    done
}

# =============================================================================
#  register_finding — Filter findings by BENCHMARK level & output them
# =============================================================================
register_finding() {
    local severity="$1"
    local domain="$2"
    local title="$3"
    local remediation="$4"
    local benchmark="${5:-N/A}"

    # BENCHMARK Level Filtering Logic
    # Level 2 benchmarks are marked with suffix " (L2)" or contains "Level2" in code
    local current_benchmark_level="${BENCHMARK:-cis_level1}"
    if [[ "$current_benchmark_level" == "cis_level1" ]]; then
        # If running in level1 mode, skip any Level 2 tagged findings
        if [[ "$benchmark" == *"(L2)"* || "$benchmark" == *"-Level2"* ]]; then
            return 0
        fi
    fi

    # Sanitize inputs (no newlines/tabs)
    title="${title//$'\t'/ }"
    title="${title//$'\n'/ }"
    remediation="${remediation//$'\t'/ }"
    remediation="${remediation//$'\n'/ }"
    domain="${domain//$'\t'/ }"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$severity" "$domain" "$title" "$remediation" "$benchmark" \
        >> "$TMP_FINDINGS_FILE"

    # Increment findings count for live status
    if [[ "${CHASE_LIVE_TUI:-0}" -eq 1 && "${CHASE_SCAN_ACTIVE:-0}" -eq 1 ]]; then
        if [[ -n "${CHASE_CURRENT_MODULE:-}" ]]; then
            local current_count=${CHASE_MOD_FINDINGS["$CHASE_CURRENT_MODULE"]:-0}
            CHASE_MOD_FINDINGS["$CHASE_CURRENT_MODULE"]=$(( current_count + 1 ))
        fi
        draw_live_status
    else
        case "$severity" in
            CRITICAL) log_crit  "[${domain}] ${title}" ;;
            HIGH)     log_high  "[${domain}] ${title}" ;;
            MEDIUM)   log_med   "[${domain}] ${title}" ;;
            LOW)      log_low   "[${domain}] ${title}" ;;
            *)        log_info  "[${domain}] ${title}" ;;
        esac
    fi

    if [[ "${SYSLOG_ENABLED:-0}" -eq 1 ]]; then
        local syslog_priority
        case "$severity" in
            CRITICAL) syslog_priority="security.crit"    ;;
            HIGH)     syslog_priority="security.err"     ;;
            MEDIUM)   syslog_priority="security.warning" ;;
            LOW)      syslog_priority="security.notice"  ;;
            *)        syslog_priority="security.info"    ;;
        esac
        logger -t "${SYSLOG_TAG:-chase}" -p "$syslog_priority" \
            "${severity} [${domain}] ${title} | fix: ${remediation} | ${benchmark}" \
            2>/dev/null || true
    fi
}

# =============================================================================
#  init_live_status — Initialize Live TUI Scan State
# =============================================================================
init_live_status() {
    # Check if we should run in live TUI mode
    # Needs to be interactive (tty), and not in silent/quiet mode, and not in verbose mode.
    if [[ -t 0 && -t 1 && "${OPT_QUIET:-0}" -eq 0 && "${OPT_VERBOSE:-0}" -eq 0 ]]; then
        CHASE_LIVE_TUI=1
    else
        CHASE_LIVE_TUI=0
    fi
    export CHASE_LIVE_TUI

    if [[ "$CHASE_LIVE_TUI" -eq 1 ]]; then
        declare -gA CHASE_MOD_STATUS
        declare -gA CHASE_MOD_FINDINGS
        for mod in "${MODULES[@]}"; do
            CHASE_MOD_STATUS["$mod"]="PENDING"
            CHASE_MOD_FINDINGS["$mod"]=0
        done
        LIVE_STATUS_DRAWN=0
        CHASE_SCAN_ACTIVE=1
    else
        CHASE_SCAN_ACTIVE=0
    fi
    export CHASE_SCAN_ACTIVE
}

# =============================================================================
#  draw_live_status — Draw single-frame box-drawn scanning grid
# =============================================================================
draw_live_status() {
    [[ "${CHASE_LIVE_TUI:-0}" -eq 1 ]] || return 0

    local num_mods=${#MODULES[@]}
    local lines_to_clear=$(( num_mods + 6 ))

    if [[ "${LIVE_STATUS_DRAWN:-0}" -eq 1 ]]; then
        # Move cursor up and clear lines
        local i
        for (( i=0; i<lines_to_clear; i++ )); do
            printf "\033[A\033[2K"
        done
    fi
    LIVE_STATUS_DRAWN=1

    local n_crit=0 n_high=0 n_med=0 n_low=0
    if [[ -n "${TMP_FINDINGS_FILE:-}" && -f "$TMP_FINDINGS_FILE" ]]; then
        n_crit="$(grep -c '^CRITICAL' "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
        n_high="$(grep -c '^HIGH'     "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
        n_med="$( grep -c '^MEDIUM'   "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
        n_low="$( grep -c '^LOW'      "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    fi

    # Draw the top border
    printf "  ${CRIMSON}┌────────────────────────────────────────────────────────┐${RESET}\n"
    printf "  ${CRIMSON}│${RESET}  ${BOLD}${WHITE}CHASE LIVE SCANNING STATUS${RESET}                           ${CRIMSON}│${RESET}\n"
    printf "  ${CRIMSON}├────────────────────────────────────────────────────────┤${RESET}\n"

    # Draw each module line
    local idx=0
    for mod in "${MODULES[@]}"; do
        idx=$(( idx + 1 ))
        local friendly_name="${MOD_NAME_MAP[$mod]:-$mod}"
        local disp_name="${friendly_name:0:30}"
        
        local status="${CHASE_MOD_STATUS[$mod]:-PENDING}"
        local raw_status_str=""
        local color_prefix=""
        case "$status" in
            PENDING)  raw_status_str="PENDING";   color_prefix="$ASH" ;;
            RUNNING)  raw_status_str="RUNNING…";  color_prefix="$YELLOW" ;;
            PASSED)   raw_status_str="PASSED";    color_prefix="$GREEN" ;;
            FINDINGS) 
                local f_count=${CHASE_MOD_FINDINGS[$mod]:-0}
                if [[ "$f_count" -eq 1 ]]; then
                    raw_status_str="1 FINDING"
                else
                    raw_status_str="${f_count} FINDINGS"
                fi
                color_prefix="$CRIMSON"
                ;;
        esac
        
        local padded_status
        padded_status="$(printf '%-12s' "$raw_status_str")"
        local status_str="${color_prefix}[ ${padded_status} ]${RESET}"

        printf "  ${CRIMSON}│${RESET}  [%d/%d] %-30s  %-21s  ${CRIMSON}│${RESET}\n" \
            "$idx" "$num_mods" "$disp_name" "$status_str"
    done

    # Draw the scoreboard divider and findings count
    printf "  ${CRIMSON}├────────────────────────────────────────────────────────┤${RESET}\n"
    
    local summary_str
    summary_str="$(printf 'FINDINGS: CRIT:%d | HIGH:%d | MED:%d | LOW:%d' "$n_crit" "$n_high" "$n_med" "$n_low")"
    local len=${#summary_str}
    local spaces_to_add=$(( 52 - len ))
    local spaces=""
    if (( spaces_to_add > 0 )); then
        spaces="$(printf '%*s' "$spaces_to_add" '')"
    fi

    printf "  ${CRIMSON}│${RESET}  ${BOLD}FINDINGS:${RESET} ${RED}CRIT:%d${RESET} | ${ORANGE}HIGH:%d${RESET} | ${YELLOW}MED:%d${RESET} | ${ASH}LOW:%d${RESET}%s  ${CRIMSON}│${RESET}\n" \
        "$n_crit" "$n_high" "$n_med" "$n_low" "$spaces"
    printf "  ${CRIMSON}└────────────────────────────────────────────────────────┘${RESET}\n"
}

# =============================================================================
#  run_remediation_wizard — Interactive CLI prompt loop to apply fixes
# =============================================================================
run_remediation_wizard() {
    if [[ ! -s "$TMP_FINDINGS_FILE" ]]; then
        printf "  ${GREEN}✓${RESET} No findings available for remediation.\n"
        return 0
    fi

    clear
    printf "\n"
    printf "  ${CRIMSON}╔══════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "  ${CRIMSON}║${RESET}   ${BOLD}${WHITE}CHASE INTERACTIVE REMEDIATION WIZARD${RESET}                             ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}║${RESET}   ${ASH}Review each security finding and choose whether to apply the fix. ${RESET}   ${CRIMSON}║${RESET}\n"
    printf "  ${CRIMSON}╚══════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    printf "\n"

    local count=0
    local applied=0
    local failed=0
    local skipped=0

    # Read the findings file line by line
    while IFS=$'\t' read -r severity domain title remediation benchmark; do
        if [[ -z "$remediation" || "$remediation" == "N/A" ]]; then
            continue
        fi

        count=$(( count + 1 ))

        local sev_color="$ASH"
        case "$severity" in
            CRITICAL) sev_color="$RED" ;;
            HIGH)     sev_color="$ORANGE" ;;
            MEDIUM)   sev_color="$YELLOW" ;;
            LOW)      sev_color="$ASH" ;;
        esac

        printf "  ${CHARCOAL}──────────────────────────────────────────────────────────────────────────${RESET}\n"
        printf "  ${BOLD}Finding #%d:${RESET} [%s%s${RESET}] [%s%s${RESET}] %s\n" \
            "$count" "$sev_color" "$severity" "$CYAN" "$domain" "$title"
        if [[ -n "$benchmark" && "$benchmark" != "N/A" ]]; then
            printf "  ${BOLD}Benchmark:${RESET}  %s\n" "$benchmark"
        fi
        printf "  ${BOLD}Remediation Command:${RESET}\n"
        printf "    ${CYAN}%s${RESET}\n" "$remediation"
        printf "  ${CHARCOAL}──────────────────────────────────────────────────────────────────────────${RESET}\n"

        while true; do
            printf "  ${CRIMSON}»»»${RESET} Apply this fix? [y/N/q]: "
            local choice
            read -r choice 2>/dev/null || choice="n"
            choice="$(to_lower "$choice")"

            if [[ "$choice" =~ ^(q|quit)$ ]]; then
                printf "\n  ${ASH}Exiting remediation wizard. Summary: applied %d, failed %d, skipped %d.${RESET}\n\n" \
                    "$applied" "$failed" "$(( skipped + 1 ))"
                return 0
            elif [[ "$choice" =~ ^(y|yes)$ ]]; then
                printf "  ${YELLOW}Executing fix...${RESET}\n"
                
                local err_out
                # Run command as root, capture stdout & stderr
                if err_out="$(eval "$remediation" 2>&1)"; then
                    applied=$(( applied + 1 ))
                    printf "  ${GREEN}✓ Success!${RESET} Remediation command executed successfully.\n"
                else
                    local exit_code=$?
                    failed=$(( failed + 1 ))
                    printf "  ${RED}✗ Error (Exit Code %d):${RESET}\n" "$exit_code"
                    printf "    %s\n" "$err_out"
                fi
                break
            elif [[ "$choice" =~ ^(n|no)$ || -z "$choice" ]]; then
                skipped=$(( skipped + 1 ))
                printf "  ${ASH}Skipped.${RESET}\n"
                break
            else
                printf "  ${YELLOW}Invalid choice. Please enter 'y', 'n', or 'q'.${RESET}\n"
            fi
        done
        printf "\n"
    done < "$TMP_FINDINGS_FILE"

    printf "  ${CHARCOAL}──────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf "  ${BOLD}Remediation Wizard Completed!${RESET}\n"
    printf "  Total evaluated   : %d\n" "$count"
    printf "  Applied successfully: ${GREEN}%d${RESET}\n" "$applied"
    printf "  Failed to apply   : ${RED}%d${RESET}\n" "$failed"
    printf "  Skipped           : %s%d${RESET}\n" "$ASH" "$skipped"
    printf "  ${CHARCOAL}──────────────────────────────────────────────────────────────────────────${RESET}\n\n"
}
