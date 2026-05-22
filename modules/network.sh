#!/usr/bin/env bash
# =============================================================================
#  modules/network.sh — Network & Firewall
#  Checks: listening ports, SSH config, firewall state, kernel sysctl params
#
#  CHASE_MODULE_NAME: Network & Firewall
#  CHASE_MODULE_DESC: Audits SSH configuration, open ports, firewall settings, and secure sysctl kernel parameters
#  CHASE_MODULE_PRIORITY: 30
#  CHASE_MODULE_ENTRY: run_network_checks
# =============================================================================

# Guard against double sourcing
if [[ -n "${_CHASE_MODULE_NETWORK_SOURCED:-}" ]]; then
    return 0
fi
_CHASE_MODULE_NETWORK_SOURCED=1

# BUG FIX #9: Ensure ETC_DIR always has a value even if sourced directly.
ETC_DIR="${ETC_DIR:-/etc}"

run_network_checks() {
    log_info "Module: Network & Firewall"

    check_ssh_config        "${ETC_DIR}/ssh/sshd_config"
    check_listening_ports
    check_firewall_state
    check_sysctl_params
}

# --- SSH configuration -------------------------------------------------------
check_ssh_config() {
    local sshd_conf="$1"
    if [[ ! -f "$sshd_conf" ]]; then
        log_info "  sshd_config not found — skipping SSH checks"
        return 0
    fi
    log_info "  Checking SSH configuration..."

    _ssh_val() { sshd_get_val "$sshd_conf" "$1"; }

    local val

    # PermitRootLogin
    val="$(_ssh_val "PermitRootLogin")" || true
    if [[ "$(to_lower "${val:-}")" == "yes" ]]; then
        register_finding "CRITICAL" "NETWORK" \
            "PermitRootLogin is yes — root can authenticate directly over SSH" \
            "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' ${sshd_conf} && systemctl restart sshd" \
            "CIS-5.2.1"
    fi

    # PermitEmptyPasswords
    val="$(_ssh_val "PermitEmptyPasswords")" || true
    if [[ "$(to_lower "${val:-}")" == "yes" ]]; then
        register_finding "CRITICAL" "NETWORK" \
            "PermitEmptyPasswords is yes — accounts with no password can log in over SSH" \
            "sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' ${sshd_conf}" \
            "CIS-5.2.9"
    fi

    # PasswordAuthentication
    val="$(_ssh_val "PasswordAuthentication")" || true
    if [[ "$(to_lower "${val:-}")" == "yes" ]]; then
        register_finding "HIGH" "NETWORK" \
            "PasswordAuthentication is yes — brute-force attacks possible; prefer key-based auth" \
            "Set PasswordAuthentication no in ${sshd_conf} after ensuring key auth works" \
            "CIS-5.2.12"
    fi

    # MaxAuthTries
    val="$(_ssh_val "MaxAuthTries")" || true
    if [[ -n "$val" ]] && is_greater_than "$val" 4; then
        register_finding "HIGH" "NETWORK" \
            "MaxAuthTries is ${val} (should be ≤ 4) — allows many password guesses per connection" \
            "sed -i 's/^MaxAuthTries.*/MaxAuthTries 4/' ${sshd_conf}" \
            "CIS-5.2.7"
    fi

    # LoginGraceTime
    val="$(_ssh_val "LoginGraceTime")" || true
    if [[ -n "$val" ]] && is_greater_than "$val" 60; then
        register_finding "MEDIUM" "NETWORK" \
            "LoginGraceTime is ${val}s (should be ≤ 60s) — connection holds resources longer" \
            "sed -i 's/^LoginGraceTime.*/LoginGraceTime 60/' ${sshd_conf}" \
            "CIS-5.2.6"
    fi

    # X11Forwarding
    val="$(_ssh_val "X11Forwarding")" || true
    if [[ "$(to_lower "${val:-}")" == "yes" ]]; then
        register_finding "MEDIUM" "NETWORK" \
            "X11Forwarding is yes — remote display forwarding can expose local display" \
            "sed -i 's/^X11Forwarding.*/X11Forwarding no/' ${sshd_conf}" \
            "CIS-5.2.10"
    fi

    # UsePAM
    val="$(_ssh_val "UsePAM")" || true
    if [[ "$(to_lower "${val:-}")" == "no" ]]; then
        register_finding "HIGH" "NETWORK" \
            "UsePAM is no — bypasses PAM account/session controls (expiry, limits)" \
            "sed -i 's/^UsePAM.*/UsePAM yes/' ${sshd_conf}" \
            "CIS-5.2.20"
    fi

    # CBC-mode ciphers (weak)
    local ciphers
    ciphers="$(_ssh_val "Ciphers")" || true
    if [[ "${ciphers:-}" == *"-cbc"* ]]; then
        register_finding "HIGH" "NETWORK" \
            "CBC-mode ciphers enabled in SSH — vulnerable to BEAST/Lucky13 attacks" \
            "Remove *-cbc entries from Ciphers line in ${sshd_conf}" \
            "CIS-5.2.13"
    fi

    # MD5 or SHA1 MACs (weak)
    local macs
    macs="$(_ssh_val "MACs")" || true
    if [[ "${macs:-}" =~ hmac-md5|hmac-sha1[^-] ]]; then
        register_finding "HIGH" "NETWORK" \
            "Weak MAC algorithms in SSH config (MD5/SHA1 MACs): ${macs}" \
            "Remove hmac-md5 and hmac-sha1 from MACs line in ${sshd_conf}" \
            "CIS-5.2.14"
    fi

    # No AllowUsers / AllowGroups
    if ! grep -qiE '^(AllowUsers|AllowGroups)' "$sshd_conf" 2>/dev/null; then
        register_finding "MEDIUM" "NETWORK" \
            "No AllowUsers or AllowGroups in sshd_config — all valid accounts can SSH in" \
            "Add 'AllowGroups sshusers' to ${sshd_conf} and add users to that group" \
            "CIS-5.2.21"
    fi

    # Protocol 1 (broken)
    val="$(_ssh_val "Protocol")" || true
    if [[ "${val:-}" == "1" ]]; then
        register_finding "CRITICAL" "NETWORK" \
            "SSH Protocol 1 explicitly enabled — cryptographically broken protocol" \
            "Remove 'Protocol 1' from ${sshd_conf} (Protocol 2 is the default)" \
            "CIS-5.2.2"
    fi
}

# --- Listening ports ---------------------------------------------------------
DANGEROUS_PORTS=(
    "21:FTP — unencrypted file transfer:HIGH:CIS-2.1.1"
    "23:Telnet — sends credentials in plaintext:CRITICAL:CIS-2.1.2"
    "513:rlogin — legacy trust-based remote login:HIGH:CIS-2.1.4"
    "514:rsh/rexec — unauthenticated remote shell:CRITICAL:CIS-2.1.5"
    "2049:NFS — check if intentional:MEDIUM:N/A"
    "6000:X11 — remote display server exposed:MEDIUM:N/A"
)

check_listening_ports() {
    log_info "  Checking for services listening on all interfaces..."

    ss -tulpn 2>/dev/null | tail -n +2 | while read -r _netid _state _recvq _sendq local_addr _remote_addr _process; do
        local ip port
        local_addr="${local_addr//\[/}"
        local_addr="${local_addr//\]/}"
        ip="${local_addr%:*}"
        port="${local_addr##*:}"

        [[ "$ip" == "0.0.0.0" || "$ip" == "*" || "$ip" == "::" ]] || continue

        for entry in "${DANGEROUS_PORTS[@]}"; do
            IFS=: read -r bad_port desc severity benchmark <<< "$entry"
            if [[ "$port" == "$bad_port" ]]; then
                register_finding "$severity" "NETWORK" \
                    "Port ${port} (${desc}) listening on all interfaces" \
                    "Disable the service or bind it to localhost: 127.0.0.1:${port}" \
                    "$benchmark"
            fi
        done

        if [[ "$port" == "80" ]]; then
            register_finding "HIGH" "NETWORK" \
                "HTTP (port 80) listening on all interfaces — unencrypted traffic, consider redirect to HTTPS" \
                "Configure web server to redirect :80 → :443 (TLS)" \
                "N/A"
        fi
    done
}

# --- Firewall state ----------------------------------------------------------
check_firewall_state() {
    log_info "  Checking firewall status..."

    local fw_active=0
    local checked=()

    for fw in ufw firewalld iptables nftables; do
        command -v "$fw" &>/dev/null || continue
        checked+=("$fw")
    done

    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q 'Status: active'; then
            fw_active=1
            log_ok "  Firewall: ufw is active"
        fi
    fi

    if [[ "$fw_active" -eq 0 ]] && command -v firewall-cmd &>/dev/null; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            fw_active=1
            log_ok "  Firewall: firewalld is active"
        fi
    fi

    if [[ "$fw_active" -eq 0 ]] && command -v nft &>/dev/null; then
        if systemctl is-active --quiet nftables 2>/dev/null; then
            fw_active=1
            log_ok "  Firewall: nftables is active"
        fi
    fi

    if [[ "$fw_active" -eq 0 ]] && command -v iptables &>/dev/null; then
        local rule_count
        rule_count="$(iptables -L INPUT --line-numbers 2>/dev/null | grep -vc '^num\|^Chain\|^target\|^$')" || rule_count=0
        if [[ "$rule_count" -gt 0 ]]; then
            fw_active=1
            log_ok "  Firewall: iptables has ${rule_count} INPUT rules"
        fi
    fi

    if [[ "$fw_active" -eq 0 ]]; then
        register_finding "CRITICAL" "NETWORK" \
            "No active firewall detected (checked: ${checked[*]:-none found})" \
            "Enable ufw: ufw default deny incoming && ufw allow ssh && ufw enable" \
            "CIS-3.5.1"
    fi
}

# --- Kernel sysctl security parameters ---------------------------------------
check_sysctl_params() {
    log_info "  Checking kernel security parameters (sysctl)..."

    local -a checks=(
        "kernel.randomize_va_space:2:HIGH:ASLR not fully enabled — memory layout attacks easier:sysctl -w kernel.randomize_va_space=2:CIS-1.5.3"
        "net.ipv4.ip_forward:0:HIGH:IPv4 forwarding enabled — this host is routing packets (if not a router, disable):sysctl -w net.ipv4.ip_forward=0:CIS-3.1.1"
        "net.ipv4.tcp_syncookies:1:HIGH:SYN cookies disabled — host vulnerable to SYN flood DoS attacks:sysctl -w net.ipv4.tcp_syncookies=1:CIS-3.2.8"
        "net.ipv4.conf.all.accept_redirects:0:HIGH:ICMP redirect acceptance enabled — routing table can be manipulated:sysctl -w net.ipv4.conf.all.accept_redirects=0:CIS-3.2.2"
        "net.ipv4.conf.all.send_redirects:0:HIGH:ICMP redirect sending enabled — host is redirecting other hosts:sysctl -w net.ipv4.conf.all.send_redirects=0:CIS-3.1.2"
        "net.ipv4.conf.all.rp_filter:1:MEDIUM:Reverse path filtering disabled — IP spoofing easier:sysctl -w net.ipv4.conf.all.rp_filter=1:CIS-3.2.7"
        "net.ipv4.conf.all.log_martians:1:LOW:Martian packets (impossible source IPs) not logged:sysctl -w net.ipv4.conf.all.log_martians=1:CIS-3.2.4"
        "kernel.dmesg_restrict:1:MEDIUM:Unprivileged users can read kernel ring buffer — may leak sensitive addresses:sysctl -w kernel.dmesg_restrict=1:CIS-1.5.4"
        "kernel.kptr_restrict:2:MEDIUM:Kernel pointer addresses exposed — aids in exploiting kernel vulnerabilities:sysctl -w kernel.kptr_restrict=2:CIS-1.5.5"
        "fs.protected_hardlinks:1:MEDIUM:Hard link protection disabled — privilege escalation via hard links possible:sysctl -w fs.protected_hardlinks=1:CIS-1.5.5"
        "fs.protected_symlinks:1:MEDIUM:Symlink protection disabled — symlink attacks in world-writable dirs possible:sysctl -w fs.protected_symlinks=1:CIS-1.5.5"
        "net.ipv6.conf.all.accept_redirects:0:HIGH:IPv6 ICMP redirect acceptance enabled:sysctl -w net.ipv6.conf.all.accept_redirects=0:CIS-3.2.2"
        "net.ipv4.conf.all.accept_source_route:0:HIGH:Source-routed packet acceptance enabled — attacker can dictate packet path:sysctl -w net.ipv4.conf.all.accept_source_route=0:CIS-3.2.1"
    )

    for check in "${checks[@]}"; do
        IFS=: read -r key expected_val severity title remediation benchmark <<< "$check"
        local actual
        actual="$(sysctl_get "$key")"
        [[ -z "$actual" ]] && continue
        if [[ "$actual" != "$expected_val" ]]; then
            register_finding "$severity" "NETWORK" \
                "${title} (${key} = ${actual}, expected ${expected_val})" \
                "$remediation  # also persist in /etc/sysctl.d/99-chase.conf" \
                "$benchmark"
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
    run_network_checks
fi
