#!/usr/bin/env bash
# =============================================================================
#  modules/software_kernel.sh — Software & Kernel
#  Checks: pending patches, auditd, SELinux/AppArmor, boot params, modules
#
#  CHASE_MODULE_NAME: Software & Kernel
#  CHASE_MODULE_DESC: Audits pending security patches, auditd, system logging, SELinux/AppArmor, boot params, and kernel module loading restrictions
#  CHASE_MODULE_PRIORITY: 40
#  CHASE_MODULE_ENTRY: run_software_kernel_checks
# =============================================================================

# Guard against double sourcing
if [[ -n "${_CHASE_MODULE_SOFTWARE_KERNEL_SOURCED:-}" ]]; then
    return 0
fi
_CHASE_MODULE_SOFTWARE_KERNEL_SOURCED=1

# BUG FIX #9: Ensure ETC_DIR always has a value even if sourced directly.
ETC_DIR="${ETC_DIR:-/etc}"

run_software_kernel_checks() {
    log_info "Module: Software & Kernel"

    check_pending_updates
    check_auditd
    check_syslog
    check_selinux_apparmor
    check_boot_params
    check_kernel_module_restrictions
    check_dangerous_modules
}

# --- Pending security updates ------------------------------------------------
check_pending_updates() {
    log_info "  Checking for pending security updates..."

    # BUG FIX #1: The old code used a pipeline like:
    #   count="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0)"
    # With set -eo pipefail active in chase.sh, if apt-get fails (e.g. locked
    # dpkg, network error), the pipeline exits non-zero and the "|| echo 0"
    # only guards grep, not apt-get — the whole scan would abort with code 3.
    # Fix: capture apt-get output first (|| true makes failure non-fatal),
    # then grep the captured output separately.

    # apt (Debian / Ubuntu)
    if command -v apt-get &>/dev/null; then
        local apt_output count
        apt_output="$(apt-get -s upgrade 2>/dev/null || true)"
        count="$(echo "$apt_output" | grep -c '^Inst')" || count=0
        if [[ "$count" -gt 0 ]]; then
            register_finding "HIGH" "SOFTWARE" \
                "${count} pending package update(s) — may include security fixes" \
                "apt-get update && apt-get upgrade -y" \
                "CIS-1.9"
        fi
        return 0
    fi

    # dnf (RHEL / CentOS / Fedora)
    if command -v dnf &>/dev/null; then
        local dnf_output count
        dnf_output="$(dnf check-update --security -q 2>/dev/null || true)"
        count="$(echo "$dnf_output" | grep -vc '^$')" || count=0
        if [[ "$count" -gt 0 ]]; then
            register_finding "HIGH" "SOFTWARE" \
                "${count} pending security update(s) (dnf)" \
                "dnf update --security -y" \
                "CIS-1.9"
        fi
        return 0
    fi

    # yum (older RHEL / CentOS)
    if command -v yum &>/dev/null; then
        local yum_output count
        yum_output="$(yum check-update --security -q 2>/dev/null || true)"
        count="$(echo "$yum_output" | grep -vc '^$')" || count=0
        if [[ "$count" -gt 0 ]]; then
            register_finding "HIGH" "SOFTWARE" \
                "${count} pending security update(s) (yum)" \
                "yum update --security -y" \
                "CIS-1.9"
        fi
        return 0
    fi

    # apk (Alpine)
    if command -v apk &>/dev/null; then
        local apk_output count
        apk_output="$(apk upgrade --simulate 2>/dev/null || true)"
        count="$(echo "$apk_output" | grep -c 'Upgrading')" || count=0
        if [[ "$count" -gt 0 ]]; then
            register_finding "HIGH" "SOFTWARE" \
                "${count} pending update(s) (apk)" \
                "apk upgrade" \
                "CIS-1.9"
        fi
        return 0
    fi

    log_info "  No supported package manager found — skipping update check"
}

# --- auditd ------------------------------------------------------------------
check_auditd() {
    log_info "  Checking audit daemon..."

    if ! systemctl is-active --quiet auditd 2>/dev/null; then
        register_finding "HIGH" "SOFTWARE" \
            "auditd is not running — system activity not being audited" \
            "systemctl enable --now auditd" \
            "CIS-4.1.1"
    fi

    local auditd_conf="${ETC_DIR}/audit/auditd.conf"
    if [[ -f "$auditd_conf" ]]; then
        local action
        action="$(grep -i '^disk_full_action' "$auditd_conf" 2>/dev/null | awk -F= '{print $2}' | trim)"
        if [[ -z "$action" || "$(to_lower "$action")" == "ignore" ]]; then
            register_finding "MEDIUM" "SOFTWARE" \
                "auditd disk_full_action not configured or set to IGNORE — audit logs silently dropped on full disk" \
                "Set disk_full_action = SYSLOG or HALT in ${auditd_conf}" \
                "CIS-4.1.2"
        fi
    fi

    if command -v auditctl &>/dev/null; then
        local rule_count
        rule_count="$(auditctl -l 2>/dev/null | grep -vc '^No\|^$')" || rule_count=0
        if [[ "$rule_count" -eq 0 ]]; then
            register_finding "MEDIUM" "SOFTWARE" \
                "auditd is running but has no audit rules configured" \
                "Add audit rules to /etc/audit/rules.d/ — see REMEDIATION.md" \
                "CIS-4.1.3"
        fi
    fi
}

# --- Syslog / journald -------------------------------------------------------
check_syslog() {
    log_info "  Checking system logging..."

    local syslog_ok=0

    systemctl is-active --quiet rsyslog   2>/dev/null && syslog_ok=1
    systemctl is-active --quiet syslogd   2>/dev/null && syslog_ok=1
    systemctl is-active --quiet syslog-ng 2>/dev/null && syslog_ok=1
    systemctl is-active --quiet systemd-journald 2>/dev/null && syslog_ok=1

    if [[ "$syslog_ok" -eq 0 ]]; then
        register_finding "HIGH" "SOFTWARE" \
            "No syslog service is active — system events are not being logged" \
            "systemctl enable --now rsyslog" \
            "CIS-4.2.1"
    fi
}

# --- SELinux and AppArmor ----------------------------------------------------
check_selinux_apparmor() {
    log_info "  Checking Mandatory Access Control (SELinux / AppArmor)..."

    local mac_active=0

    if command -v getenforce &>/dev/null; then
        local selinux_mode
        selinux_mode="$(getenforce 2>/dev/null || echo 'Unknown')"
        case "$selinux_mode" in
            Enforcing)
                log_ok "  SELinux is in Enforcing mode"
                mac_active=1
                ;;
            Permissive)
                register_finding "HIGH" "SOFTWARE" \
                    "SELinux is in Permissive mode — policies are logged but NOT enforced" \
                    "setenforce 1  # also set SELINUX=enforcing in /etc/selinux/config" \
                    "CIS-1.6.1.2"
                mac_active=1
                ;;
            Disabled)
                register_finding "HIGH" "SOFTWARE" \
                    "SELinux is Disabled — no mandatory access control active" \
                    "Set SELINUX=enforcing in /etc/selinux/config and reboot" \
                    "CIS-1.6.1.1"
                ;;
        esac
    fi

    if command -v aa-status &>/dev/null; then
        local complain_count enforce_count
        complain_count="$(aa-status 2>/dev/null | grep -c 'profiles are in complain')" || complain_count=0
        enforce_count="$(aa-status  2>/dev/null | grep -c 'profiles are in enforce')" || enforce_count=0

        if [[ "$enforce_count" -gt 0 ]]; then
            log_ok "  AppArmor: ${enforce_count} enforcing profile(s)"
            mac_active=1
        fi
        if [[ "$complain_count" -gt 0 ]]; then
            register_finding "MEDIUM" "SOFTWARE" \
                "AppArmor has ${complain_count} profile(s) in complain mode — not enforced" \
                "aa-enforce /etc/apparmor.d/*  # switch all to enforce" \
                "CIS-1.6.2"
            mac_active=1
        fi

        if [[ "$enforce_count" -eq 0 && "$complain_count" -eq 0 ]]; then
            register_finding "HIGH" "SOFTWARE" \
                "AppArmor is installed but no profiles are active" \
                "systemctl enable --now apparmor && aa-enforce /etc/apparmor.d/*" \
                "CIS-1.6.2"
        fi
    fi

    if [[ "$mac_active" -eq 0 ]]; then
        register_finding "HIGH" "SOFTWARE" \
            "No Mandatory Access Control (SELinux or AppArmor) is active on this system" \
            "Install and enable AppArmor (Debian/Ubuntu) or SELinux (RHEL/CentOS)" \
            "CIS-1.6.1"
    fi

    if grep -qE 'selinux=0|enforcing=0' /proc/cmdline 2>/dev/null; then
        register_finding "CRITICAL" "SOFTWARE" \
            "SELinux is disabled on the kernel command line (selinux=0 or enforcing=0)" \
            "Remove selinux=0 / enforcing=0 from GRUB config and reboot" \
            "CIS-1.6.1.1"
    fi
    if grep -q 'apparmor=0' /proc/cmdline 2>/dev/null; then
        register_finding "CRITICAL" "SOFTWARE" \
            "AppArmor is disabled on the kernel command line (apparmor=0)" \
            "Remove apparmor=0 from GRUB config and reboot" \
            "CIS-1.6.2"
    fi
}

# --- Boot parameters ---------------------------------------------------------
check_boot_params() {
    log_info "  Checking kernel boot parameters..."

    [[ -r /proc/cmdline ]] || return 0

    local cmdline
    cmdline="$(cat /proc/cmdline)"

    if [[ "$cmdline" == *"vsyscall=native"* ]]; then
        register_finding "MEDIUM" "SOFTWARE" \
            "Kernel booted with vsyscall=native — increases attack surface for ROP chains" \
            "Set vsyscall=none or vsyscall=emulate in GRUB" \
            "N/A"
    fi

    if [[ "$cmdline" =~ init=/bin/(bash|sh) ]]; then
        register_finding "CRITICAL" "SOFTWARE" \
            "Kernel booted with init=/bin/bash — system running as root shell, no init daemon" \
            "Remove init= override from GRUB and reboot normally" \
            "N/A"
    fi
}

# --- Kernel module loading restrictions --------------------------------------
check_kernel_module_restrictions() {
    log_info "  Checking kernel module restrictions..."

    local val
    val="$(sysctl_get "kernel.modules_disabled")"
    if [[ "${val:-0}" -eq 0 ]]; then
        register_finding "MEDIUM" "SOFTWARE" \
            "Kernel module loading is not locked (kernel.modules_disabled = 0) — modules can be loaded at runtime" \
            "sysctl -w kernel.modules_disabled=1  # WARNING: prevents loading any further modules" \
            "CIS-1.1.1"
    fi
}

# --- Dangerous / unneeded kernel modules should be blacklisted ---------------
DANGEROUS_MODULES=( dccp sctp rds tipc usb-storage cramfs freevxfs hfs hfsplus jffs2 udf )

check_dangerous_modules() {
    log_info "  Checking for dangerous kernel modules..."

    local modprobe_dir="${ETC_DIR}/modprobe.d"
    [[ -d "$modprobe_dir" ]] || return 0

    for mod in "${DANGEROUS_MODULES[@]}"; do
        # BUG FIX #13: Old code used grep with "\|" (BRE alternation), which
        # works in GNU grep but is treated as a literal backslash-pipe in BSD
        # and BusyBox grep. Use -E (ERE) with plain "|" for portability.
        if ! grep -rqE "install ${mod} /bin/true|blacklist ${mod}" "$modprobe_dir" 2>/dev/null; then
            register_finding "MEDIUM" "SOFTWARE" \
                "Kernel module '${mod}' is not blacklisted — can be loaded if triggered" \
                "echo 'install ${mod} /bin/true' >> ${modprobe_dir}/chase-hardening.conf" \
                "CIS-3.4.1"
        fi
    done
}

# --- Run all checks ----------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "${TMP_FINDINGS_FILE:-}" ]]; then
        echo "[ERROR] TMP_FINDINGS_FILE is not set. Run via chase.sh or set it manually:" >&2
        echo "  export TMP_FINDINGS_FILE=\$(mktemp)" >&2
        exit 3
    fi
    run_software_kernel_checks
fi
