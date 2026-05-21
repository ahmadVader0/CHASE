#!/usr/bin/env bash
# =============================================================================
#  modules/persistence_crypto.sh — Persistence & Crypto
#  Checks: cron scripts, systemd units, rc.local, SSL cert expiry, key perms
#
#  CHASE_MODULE_NAME: Persistence & Crypto
#  CHASE_MODULE_DESC: Audits cron jobs, systemd backdoor files, startup scripts, SSL/TLS certificate expiries, and private key permissions
#  CHASE_MODULE_PRIORITY: 50
#  CHASE_MODULE_ENTRY: run_persistence_crypto_checks
# =============================================================================

# Guard against double sourcing
if [[ -n "${_CHASE_MODULE_PERSISTENCE_CRYPTO_SOURCED:-}" ]]; then
    return 0
fi
_CHASE_MODULE_PERSISTENCE_CRYPTO_SOURCED=1

# BUG FIX #9: Ensure ETC_DIR always has a value even if sourced directly.
ETC_DIR="${ETC_DIR:-/etc}"

run_persistence_crypto_checks() {
    log_info "Module: Persistence & Crypto"

    check_cron_scripts
    check_systemd_units
    check_rc_local
    check_profile_d
    check_ssl_certificates
    check_private_keys
}

# --- Cron scripts: world-writable or pointing to bad paths -------------------
CRON_DIRS=(
    /etc/cron.d
    /etc/cron.daily
    /etc/cron.hourly
    /etc/cron.monthly
    /etc/cron.weekly
    /var/spool/cron/crontabs
)

check_cron_scripts() {
    log_info "  Checking cron scripts..."

    for cron_dir in "${CRON_DIRS[@]}"; do
        [[ -d "$cron_dir" ]] || continue

        while IFS= read -r script; do
            local perms
            perms="$(compat_stat_perms "$script")"

            local world_write=$(( 8#${perms:-000} & 2 ))
            if [[ "$world_write" -ne 0 ]]; then
                register_finding "CRITICAL" "PERSISTENCE" \
                    "World-writable cron script: ${script} (perms: ${perms})" \
                    "chmod o-w '${script}'" \
                    "CIS-5.1.2"
            fi

            if grep -qE '/tmp/|/dev/shm/' "$script" 2>/dev/null; then
                register_finding "HIGH" "PERSISTENCE" \
                    "Cron script references world-writable directory: ${script}" \
                    "Review ${script} and replace /tmp/ paths with secure directories" \
                    "CIS-5.1.2"
            fi
        done < <(find "$cron_dir" -maxdepth 1 -type f 2>/dev/null)
    done

    if [[ -f "/etc/crontab" ]]; then
        local perms
        perms="$(compat_stat_perms /etc/crontab)"
        local world=$(( 8#${perms:-000} & 22 ))
        if [[ "$world" -ne 0 ]]; then
            register_finding "CRITICAL" "PERSISTENCE" \
                "/etc/crontab has unsafe permissions: ${perms}" \
                "chmod 600 /etc/crontab && chown root:root /etc/crontab" \
                "CIS-5.1.2"
        fi
    fi
}

# --- Systemd units with suspicious ExecStart ---------------------------------
check_systemd_units() {
    log_info "  Checking systemd unit files..."

    local unit_dirs=(
        /etc/systemd/system
        /usr/lib/systemd/system
    )

    for unit_dir in "${unit_dirs[@]}"; do
        [[ -d "$unit_dir" ]] || continue

        grep -rl "ExecStart=" "$unit_dir" 2>/dev/null \
        | while read -r unit_file; do
            local exec_line
            exec_line="$(grep 'ExecStart=' "$unit_file" | head -1)"

            if [[ "$exec_line" =~ /tmp/|/dev/shm/ ]]; then
                register_finding "HIGH" "PERSISTENCE" \
                    "Systemd unit ${unit_file} runs from world-writable path: ${exec_line}" \
                    "Move the script to /usr/local/bin/ and update the unit file" \
                    "N/A"
            fi

            if grep -q 'base64 --decode\|base64 -d' "$unit_file" 2>/dev/null; then
                register_finding "CRITICAL" "PERSISTENCE" \
                    "Systemd unit ${unit_file} contains base64 decode — possible obfuscated payload" \
                    "Inspect immediately: cat '${unit_file}'" \
                    "N/A"
            fi
        done
    done
}

# --- /etc/rc.local non-standard entries --------------------------------------
check_rc_local() {
    local rc_local="/etc/rc.local"
    [[ -f "$rc_local" ]] || return 0

    local meaningful_lines
    meaningful_lines="$(grep -vE '^[[:space:]]*(#|$|exit 0|#!/)' "$rc_local" 2>/dev/null | wc -l)"

    if [[ "$meaningful_lines" -gt 0 ]]; then
        register_finding "MEDIUM" "PERSISTENCE" \
            "/etc/rc.local has ${meaningful_lines} non-standard startup command(s) — review for unauthorised persistence" \
            "Review /etc/rc.local contents; migrate to proper systemd units" \
            "N/A"
    fi
}

# --- Non-standard files in /etc/profile.d ------------------------------------
KNOWN_PROFILE_D_PREFIXES=( bash_completion umask colour proxy locale lang )

check_profile_d() {
    local profile_d="${ETC_DIR}/profile.d"
    [[ -d "$profile_d" ]] || return 0

    while IFS= read -r f; do
        local fname
        fname="$(basename "$f")"
        local known=0
        for prefix in "${KNOWN_PROFILE_D_PREFIXES[@]}"; do
            [[ "$fname" == *"$prefix"* ]] && known=1 && break
        done
        if [[ "$known" -eq 0 ]]; then
            register_finding "MEDIUM" "PERSISTENCE" \
                "Non-standard file in /etc/profile.d/: ${fname} — sourced in every login shell" \
                "Review: cat '${f}'  — remove if unknown or unauthorized" \
                "N/A"
        fi
    done < <(find "$profile_d" -maxdepth 1 -type f -name '*.sh' 2>/dev/null)
}

# --- SSL / TLS certificate expiry --------------------------------------------
check_ssl_certificates() {
    log_info "  Checking SSL/TLS certificate expiry..."

    if [[ "${OPTIONAL_AVAILABLE[openssl]:-0}" -eq 0 ]]; then
        log_info "  openssl not available — skipping certificate checks"
        return 0
    fi

    local cert_dirs=( /etc/ssl/certs /etc/pki/tls/certs /etc/nginx/ssl /etc/apache2/ssl /etc/letsencrypt/live )

    local now_epoch
    now_epoch="$(date +%s)"

    for cert_dir in "${cert_dirs[@]}"; do
        [[ -d "$cert_dir" ]] || continue

        find "$cert_dir" -type f \( -name '*.crt' -o -name '*.pem' \) 2>/dev/null \
        | while read -r cert_file; do
            [[ "$(basename "$cert_file")" =~ ca-certificates|ca-bundle ]] && continue

            local end_date
            end_date="$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null \
                | cut -d= -f2)" || continue
            [[ -z "$end_date" ]] && continue

            local end_epoch
            end_epoch="$(compat_date_to_epoch "$end_date")"
            [[ "$end_epoch" -eq 0 ]] && continue

            local days_left=$(( (end_epoch - now_epoch) / 86400 ))

            if [[ "$days_left" -lt 0 ]]; then
                register_finding "CRITICAL" "PERSISTENCE" \
                    "Certificate EXPIRED ${cert_file} — expired ${days_left#-} day(s) ago" \
                    "Renew the certificate immediately" \
                    "N/A"
            elif [[ "$days_left" -lt "${CERT_CRIT_DAYS:-7}" ]]; then
                register_finding "CRITICAL" "PERSISTENCE" \
                    "Certificate expires in ${days_left} day(s): ${cert_file}" \
                    "Renew before $(date -d "@${end_epoch}" '+%Y-%m-%d' 2>/dev/null || echo "$end_date")" \
                    "N/A"
            elif [[ "$days_left" -lt "${CERT_WARN_DAYS:-30}" ]]; then
                register_finding "HIGH" "PERSISTENCE" \
                    "Certificate expires in ${days_left} day(s): ${cert_file}" \
                    "Renew before $(date -d "@${end_epoch}" '+%Y-%m-%d' 2>/dev/null || echo "$end_date")" \
                    "N/A"
            fi

            local sig_alg
            sig_alg="$(openssl x509 -noout -text -in "$cert_file" 2>/dev/null \
                | grep 'Signature Algorithm' | head -1 | awk '{print $NF}')" || true
            if [[ "$sig_alg" =~ md5|sha1 ]]; then
                register_finding "HIGH" "PERSISTENCE" \
                    "Certificate uses weak signature algorithm (${sig_alg}): ${cert_file}" \
                    "Reissue the certificate with SHA-256 or better" \
                    "N/A"
            fi

            local key_bits
            key_bits="$(openssl x509 -noout -text -in "$cert_file" 2>/dev/null \
                | grep 'Public-Key:' | grep -o '[0-9]*')" || true
            if [[ -n "$key_bits" && "$key_bits" -lt 2048 ]]; then
                register_finding "HIGH" "PERSISTENCE" \
                    "Certificate RSA key is only ${key_bits} bits (minimum 2048): ${cert_file}" \
                    "Reissue the certificate with a 2048-bit or 4096-bit RSA key (or ECDSA P-256)" \
                    "N/A"
            fi
        done
    done
}

# --- Private key files world-readable ----------------------------------------
check_private_keys() {
    log_info "  Checking private key file permissions..."

    local key_dirs=( /etc/ssl /etc/pki /etc/nginx /etc/apache2 /etc/letsencrypt )

    for key_dir in "${key_dirs[@]}"; do
        [[ -d "$key_dir" ]] || continue

        find "$key_dir" -type f -name '*.key' 2>/dev/null \
        | while read -r key_file; do
            local perms
            perms="$(compat_stat_perms "$key_file")"
            local world=$(( 8#${perms:-000} & 4 ))
            if [[ "$world" -ne 0 ]]; then
                register_finding "CRITICAL" "PERSISTENCE" \
                    "Private key is world-readable: ${key_file} (perms: ${perms})" \
                    "chmod 600 '${key_file}'  # only the service user should read this" \
                    "N/A"
            fi
        done
    done
}

# --- Run all checks ----------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "${TMP_FINDINGS_FILE:-}" ]]; then
        echo "[ERROR] TMP_FINDINGS_FILE is not set. Run via chase.sh or set it manually:" >&2
        echo "  export TMP_FINDINGS_FILE=\$(mktemp)" >&2
        exit 3
    fi
    run_persistence_crypto_checks
fi
