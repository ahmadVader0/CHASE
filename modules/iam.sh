#!/usr/bin/env bash
# =============================================================================
#  modules/iam.sh — Identity & Access Management
#  Checks: empty passwords, UID 0 dupes, sudoers, SSH keys, password policy
#
#  CHASE_MODULE_NAME: Identity & Access Management (IAM)
#  CHASE_MODULE_DESC: Audits users, shadow file, sudoers, SSH keys, password policies
#  CHASE_MODULE_PRIORITY: 10
#  CHASE_MODULE_ENTRY: run_iam_checks
# =============================================================================

# Guard against double sourcing
if [[ -n "${_CHASE_MODULE_IAM_SOURCED:-}" ]]; then
    return 0
fi
_CHASE_MODULE_IAM_SOURCED=1

# BUG FIX #9: Ensure ETC_DIR always has a value even if chase.conf was not
# loaded (e.g. someone sources this module directly for testing).
ETC_DIR="${ETC_DIR:-/etc}"

run_iam_checks() {
    log_info "Module: Identity & Access Management (IAM)"

    check_empty_passwords   "${ETC_DIR}/shadow"
    check_uid_zero          "${ETC_DIR}/passwd"
    check_duplicate_uids    "${ETC_DIR}/passwd"
    check_pass_max_days     "${ETC_DIR}/login.defs"
    check_sudoers           "${ETC_DIR}/sudoers" "${ETC_DIR}/sudoers.d"
    check_weak_hashes       "${ETC_DIR}/shadow"
    check_service_accounts  "${ETC_DIR}/passwd"
    check_home_dirs         "${ETC_DIR}/passwd"
    check_ssh_authorized_keys
}

# --- Empty password in /etc/shadow -------------------------------------------
check_empty_passwords() {
    local shadow_file="$1"
    file_readable "$shadow_file" || { log_info "  /etc/shadow not readable — skipping"; return 0; }

    while IFS=: read -r username password _rest; do
        # Skip NIS/YP compatibility entries (lines starting with + or -)
        [[ "$username" == +* || "$username" == -* ]] && continue

        # Only flag truly empty password fields — not locked (! !!), disabled (*),
        # or any other non-empty placeholder.
        [[ -z "$password" ]] || continue

        register_finding "CRITICAL" "IAM" \
            "Account '${username}' has no password set (empty shadow field)" \
            "passwd ${username}  # set a password, or: usermod -L ${username}  # lock the account" \
            "CIS-5.4.1"
    done < "$shadow_file"
}

# --- Any non-root account with UID 0 -----------------------------------------
check_uid_zero() {
    local passwd_file="$1"
    file_readable "$passwd_file" || return 0

    while IFS=: read -r username _pw uid _rest; do
        [[ "$uid" -eq 0 && "$username" != "root" ]] || continue
        register_finding "CRITICAL" "IAM" \
            "Non-root account '${username}' has UID 0 (full root privileges)" \
            "usermod -u <new_uid> ${username}  # reassign a non-zero UID" \
            "CIS-5.4.2"
    done < "$passwd_file"
}

# --- Duplicate UIDs ----------------------------------------------------------
check_duplicate_uids() {
    local passwd_file="$1"
    file_readable "$passwd_file" || return 0

    local dupes
    dupes="$(awk -F: '{print $3}' "$passwd_file" | sort | uniq -d)" || true
    if [[ -n "$dupes" ]]; then
        while read -r uid; do
            local users
            users="$(awk -F: -v u="$uid" '$3==u {print $1}' "$passwd_file" | tr '\n' ' ')"

            # BUG FIX #2: UID 0 duplicates are CRITICAL (same as check_uid_zero),
            # not just HIGH. A duplicate UID 0 is a backdoor root account.
            if [[ "$uid" -eq 0 ]]; then
                register_finding "CRITICAL" "IAM" \
                    "Duplicate UID 0 shared by accounts: ${users}— likely a backdoor root account" \
                    "Remove or reassign the non-root UID 0 account immediately" \
                    "CIS-5.4.2"
            else
                register_finding "HIGH" "IAM" \
                    "Duplicate UID ${uid} shared by accounts: ${users}" \
                    "Review and reassign unique UIDs; investigate possible backdoor" \
                    "CIS-5.4.2"
            fi
        done <<< "$dupes"
    fi
}

# --- Password max age > 90 days in login.defs --------------------------------
check_pass_max_days() {
    local defs_file="$1"
    file_readable "$defs_file" || return 0

    local val
    val="$(grep -E '^PASS_MAX_DAYS' "$defs_file" 2>/dev/null | awk '{print $2}')" || true
    [[ -z "$val" ]] && return 0

    if is_greater_than "$val" 90; then
        register_finding "MEDIUM" "IAM" \
            "PASS_MAX_DAYS is ${val} (should be ≤ 90) — passwords rarely expire" \
            "sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' ${defs_file}" \
            "CIS-5.4.1.1"
    fi
}

# --- Sudoers: NOPASSWD and dangerous shell-escape binaries -------------------
SHELL_ESCAPE_BINS=( vim vi nano find awk python python3 perl bash sh env less more )

check_sudoers() {
    local sudoers_file="$1"
    local sudoers_dir="$2"

    local -a files_to_check=()
    file_readable "$sudoers_file" && files_to_check+=( "$sudoers_file" )
    dir_exists   "$sudoers_dir"   && while IFS= read -r f; do
        file_readable "$f" && files_to_check+=( "$f" )
    done < <(find "$sudoers_dir" -maxdepth 1 -type f 2>/dev/null)

    for f in "${files_to_check[@]}"; do
        # NOPASSWD rule
        if grep -q 'NOPASSWD' "$f" 2>/dev/null; then
            local rule
            rule="$(grep 'NOPASSWD' "$f" | head -1 | xargs)"
            register_finding "HIGH" "IAM" \
                "NOPASSWD sudo rule in ${f}: ${rule}" \
                "Remove NOPASSWD from ${f} — require password for privilege escalation" \
                "CIS-5.3.6"
        fi

        # BUG FIX #12: Old regex "(^[^#].*[[:space:]]|/)${bin}([[:space:]]|$)"
        # had two problems:
        #   1. It matched substrings — "vim" matched inside "davidim" or "/usr/bin/avim"
        #   2. It could match commented lines if the comment contained a path
        # New regex requires the binary to be preceded by a path separator or
        # whitespace, and followed by whitespace or end of line. The [^#] anchor
        # is kept at the start so commented lines are skipped.
        for bin in "${SHELL_ESCAPE_BINS[@]}"; do
            if grep -qE "^[^#].*(^|[[:space:]]/|/)${bin}([[:space:]]|$)" "$f" 2>/dev/null; then
                register_finding "HIGH" "IAM" \
                    "Sudo rule in ${f} allows '${bin}' — enables shell escape to root" \
                    "Remove ${bin} from sudo rules; see https://gtfobins.github.io" \
                    "CIS-5.3.6"
            fi
        done
    done
}

# --- Weak password hash algorithm in /etc/shadow -----------------------------
check_weak_hashes() {
    local shadow_file="$1"
    file_readable "$shadow_file" || return 0

    while IFS=: read -r username hash _rest; do
        [[ -z "$hash" || "$hash" == "!" || "$hash" == "*" || "$hash" == "!!" ]] && continue

        if [[ "$hash" =~ ^\$1\$ ]]; then
            register_finding "CRITICAL" "IAM" \
                "Account '${username}' uses MD5 password hash (\$1\$) — trivially crackable" \
                "Force password reset: chage -d 0 ${username}; ensure PAM uses yescrypt/sha512" \
                "CIS-5.4.4"
        elif [[ "${#hash}" -eq 13 && ! "$hash" =~ ^\$ ]]; then
            register_finding "CRITICAL" "IAM" \
                "Account '${username}' uses legacy DES password hash — trivially crackable" \
                "Force password reset: chage -d 0 ${username}; ensure PAM uses yescrypt/sha512" \
                "CIS-5.4.4"
        fi
    done < "$shadow_file"
}

# --- Service accounts with interactive shells --------------------------------
KNOWN_SERVICE_ACCOUNTS=(
    daemon bin sys sync games man lp mail news uucp proxy www-data
    backup list irc gnats nobody systemd-network systemd-resolve
    messagebus syslog _apt landscape pollinate sshd
)

check_service_accounts() {
    local passwd_file="$1"
    file_readable "$passwd_file" || return 0

    while IFS=: read -r username _pw _uid _gid _gecos _home shell; do
        # BUG FIX #3: Use trim() from lib/utils.sh to strip leading/trailing
        # whitespace from the shell field. A passwd entry with trailing spaces
        # like "/bin/bash " would not match the nologin/false pattern and would
        # be incorrectly flagged or missed depending on the check direction.
        shell="$(trim "$shell")"

        # Skip non-interactive shells
        [[ "$shell" =~ (nologin|false|sync|halt|shutdown) ]] && continue
        [[ -z "$shell" ]] && continue

        for svc in "${KNOWN_SERVICE_ACCOUNTS[@]}"; do
            if [[ "$username" == "$svc" ]]; then
                register_finding "MEDIUM" "IAM" \
                    "Service account '${username}' has interactive shell: ${shell}" \
                    "usermod -s /usr/sbin/nologin ${username}" \
                    "CIS-5.4.3"
                break
            fi
        done
    done < "$passwd_file"
}

# --- Home directories that don't exist on disk --------------------------------
check_home_dirs() {
    local passwd_file="$1"
    file_readable "$passwd_file" || return 0

    while IFS=: read -r username _pw _uid _gid _gecos home _shell; do
        [[ "$home" == "/dev/null" || "$home" == "/nonexistent" || -z "$home" ]] && continue
        [[ "$home" == "/" ]] && continue

        if [[ ! -d "$home" ]]; then
            register_finding "LOW" "IAM" \
                "Account '${username}' home directory missing: ${home}" \
                "mkdir -p ${home} && chown ${username}: ${home}" \
                "N/A"
        fi
    done < "$passwd_file"
}

# --- SSH authorized_keys world-readable --------------------------------------
check_ssh_authorized_keys() {
    local passwd_file="${ETC_DIR}/passwd"
    file_readable "$passwd_file" || return 0

    while IFS=: read -r username _pw _uid _gid _gecos home _shell; do
        local akfile="${home}/.ssh/authorized_keys"
        [[ -f "$akfile" ]] || continue

        local perms
        perms="$(compat_stat_perms "$akfile")"
        local world_bits=$(( 8#$perms & 4 ))
        if [[ "$world_bits" -ne 0 ]]; then
            register_finding "HIGH" "IAM" \
                "SSH authorized_keys is world-readable: ${akfile} (${perms})" \
                "chmod 600 ${akfile}" \
                "CIS-5.2.16"
        fi
    done < "$passwd_file"
}

# --- Run all checks ----------------------------------------------------------
# Guard: only auto-execute when this file is run directly (not sourced by tests
# or by chase.sh). When run directly, also check TMP_FINDINGS_FILE is set so
# register_finding has somewhere to write — BUG FIX #10.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "${TMP_FINDINGS_FILE:-}" ]]; then
        echo "[ERROR] TMP_FINDINGS_FILE is not set. Run via chase.sh or set it manually:" >&2
        echo "  export TMP_FINDINGS_FILE=\$(mktemp)" >&2
        exit 3
    fi
    run_iam_checks
fi
