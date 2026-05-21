#!/usr/bin/env bash
# =============================================================================
#  modules/filesystem.sh — Filesystem & Permissions
#  Checks: SUID/SGID, world-writable, mount options, critical file perms
#
#  CHASE_MODULE_NAME: Filesystem & Permissions
#  CHASE_MODULE_DESC: Audits world-writable files, SUID/SGID binaries, mount parameters, and system file permissions
#  CHASE_MODULE_PRIORITY: 20
#  CHASE_MODULE_ENTRY: run_filesystem_checks
# =============================================================================

# Guard against double sourcing
if [[ -n "${_CHASE_MODULE_FILESYSTEM_SOURCED:-}" ]]; then
    return 0
fi
_CHASE_MODULE_FILESYSTEM_SOURCED=1

# BUG FIX #9: Ensure ETC_DIR always has a value even if sourced directly.
ETC_DIR="${ETC_DIR:-/etc}"

# SUID binaries that are expected/acceptable on most systems
EXPECTED_SUID_BINS=(
    /usr/bin/sudo
    /usr/bin/passwd
    /usr/bin/su
    /usr/bin/chsh
    /usr/bin/chfn
    /usr/bin/gpasswd
    /usr/bin/newgrp
    /bin/ping
    /usr/bin/ping
    /bin/su
    /usr/lib/openssh/ssh-keysign
    /usr/lib/dbus-1.0/dbus-daemon-launch-helper
)

run_filesystem_checks() {
    log_info "Module: Filesystem & Permissions"

    [[ "${OPT_QUICK:-0}" -eq 1 ]] && {
        log_info "  --quick flag set: skipping slow filesystem traversal checks"
        check_critical_file_permissions
        check_mount_options
        return 0
    }

    check_world_writable_files
    check_world_writable_dirs
    check_suid_files
    check_sgid_files
    check_orphaned_files
    check_rhosts_netrc
    check_critical_file_permissions
    check_mount_options
    check_ld_preload
}

# --- World-writable files ----------------------------------------------------
check_world_writable_files() {
    log_info "  Scanning for world-writable files (this may take a moment)..."

    safe_find / -type f -perm -0002 -print | while read -r filepath; do
        register_finding "HIGH" "FILESYSTEM" \
            "World-writable file: ${filepath}" \
            "chmod o-w '${filepath}'" \
            "CIS-6.1.1"
    done
}

# --- World-writable directories WITHOUT sticky bit ---------------------------
check_world_writable_dirs() {
    log_info "  Scanning for world-writable directories without sticky bit..."

    safe_find / -type d -perm -0002 ! -perm -1000 -print | while read -r dirpath; do
        register_finding "HIGH" "FILESYSTEM" \
            "World-writable directory without sticky bit: ${dirpath}" \
            "chmod +t '${dirpath}'  # add sticky bit, or: chmod o-w '${dirpath}'" \
            "CIS-6.1.2"
    done
}

# --- SUID files: catalog and flag non-standard ones -------------------------
check_suid_files() {
    log_info "  Scanning for SUID binaries..."

    local baseline_file="${REPORT_DIR}/suid_baseline.txt"
    local current_suid_file
    current_suid_file="$(mktemp "${REPORT_DIR}/chase_suid.XXXXXX")"
    chmod 600 "$current_suid_file"

    safe_find / -type f -perm -4000 -print | sort > "$current_suid_file"

    while read -r suid_bin; do
        local expected=0
        for ok_bin in "${EXPECTED_SUID_BINS[@]}"; do
            [[ "$suid_bin" == "$ok_bin" ]] && expected=1 && break
        done

        if [[ "$expected" -eq 0 ]]; then
            register_finding "HIGH" "FILESYSTEM" \
                "Unexpected SUID binary: ${suid_bin}" \
                "chmod u-s '${suid_bin}'  # remove SUID bit if not needed" \
                "CIS-6.1.10"
        fi
    done < "$current_suid_file"

    if [[ -f "$baseline_file" ]]; then
        # SUID baseline age check
        local mtime
        mtime="$(compat_stat_mtime "$baseline_file")"
        local now
        now="$(date +%s)"
        local age_seconds=$(( now - mtime ))
        local age_days=$(( age_seconds / 86400 ))
        local max_age="${SUID_BASELINE_MAX_AGE_DAYS:-30}"

        if (( age_days > max_age )); then
            register_finding "MEDIUM" "FILESYSTEM" \
                "SUID baseline file is stale (${age_days} days old, max is ${max_age})" \
                "Regenerate baseline: rm '${baseline_file}' and run a scan to recreate it" \
                "N/A"
        fi

        local new_suids
        new_suids="$(comm -23 <(sort "$current_suid_file") <(sort "$baseline_file") 2>/dev/null || true)"
        if [[ -n "$new_suids" ]]; then
            while read -r new_bin; do
                register_finding "HIGH" "FILESYSTEM" \
                    "NEW SUID binary since last scan: ${new_bin}" \
                    "Investigate why this binary has SUID set: ls -la '${new_bin}'" \
                    "CIS-6.1.10"
            done <<< "$new_suids"
        fi
    else
        mkdir -p "$REPORT_DIR"
        cp "$current_suid_file" "$baseline_file"
        log_info "  SUID baseline saved: ${baseline_file}"
    fi

    rm -f "$current_suid_file"
}

# --- SGID files --------------------------------------------------------------
check_sgid_files() {
    log_info "  Scanning for SGID binaries..."

    safe_find / -type f -perm -2000 -print | while read -r sgid_bin; do
        register_finding "MEDIUM" "FILESYSTEM" \
            "SGID binary found: ${sgid_bin} — review if group elevation is necessary" \
            "chmod g-s '${sgid_bin}'  # remove SGID bit if not needed" \
            "CIS-6.1.11"
    done
}

# --- Files with no valid owner -----------------------------------------------
check_orphaned_files() {
    log_info "  Scanning for orphaned files (no valid owner/group)..."

    safe_find / \( -nouser -o -nogroup \) -print | while read -r orphan; do
        register_finding "MEDIUM" "FILESYSTEM" \
            "Orphaned file (invalid owner/group): ${orphan}" \
            "chown root:root '${orphan}'  # or delete if unknown: rm '${orphan}'" \
            "CIS-6.1.12"
    done
}

# --- .rhosts and .netrc files ------------------------------------------------
check_rhosts_netrc() {
    safe_find /home /root -maxdepth 3 \
        \( -name '.rhosts' -o -name '.netrc' \) -print | while read -r badfile; do
        register_finding "CRITICAL" "FILESYSTEM" \
            "Legacy trust file found: ${badfile} — allows password-less remote access" \
            "rm -f '${badfile}'" \
            "CIS-6.2.12"
    done
}

# --- Critical system file permissions ----------------------------------------
check_critical_file_permissions() {
    local -a checks=(
        "${ETC_DIR}/passwd:644:HIGH:CIS-6.1.2"
        "${ETC_DIR}/shadow:000:CRITICAL:CIS-6.1.3"
        "${ETC_DIR}/group:644:HIGH:CIS-6.1.4"
        "${ETC_DIR}/gshadow:000:CRITICAL:CIS-6.1.5"
        "${ETC_DIR}/sudoers:440:HIGH:CIS-5.3.1"
        "${ETC_DIR}/ssh/sshd_config:600:HIGH:CIS-5.2.1"
    )

    for entry in "${checks[@]}"; do
        IFS=: read -r filepath expected_max severity benchmark <<< "$entry"
        [[ -f "$filepath" ]] || continue

        local actual_perms
        actual_perms="$(compat_stat_perms "$filepath")"

        if [[ "$filepath" =~ shadow ]]; then
            local world=$(( 8#${actual_perms:-777} & 7 ))
            if [[ "$world" -ne 0 ]]; then
                register_finding "$severity" "FILESYSTEM" \
                    "${filepath} is world-readable (perms: ${actual_perms}) — exposes password hashes" \
                    "chmod 000 '${filepath}'" \
                    "$benchmark"
            fi
        fi

        if [[ "$filepath" =~ passwd$|group$ ]]; then
            local world=$(( 8#${actual_perms:-777} & 2 ))
            if [[ "$world" -ne 0 ]]; then
                register_finding "$severity" "FILESYSTEM" \
                    "${filepath} is world-writable (perms: ${actual_perms})" \
                    "chmod 644 '${filepath}'" \
                    "$benchmark"
            fi
        fi
    done
}

# --- Mount options -----------------------------------------------------------
check_mount_options() {
    local mounts_file="/proc/mounts"
    [[ -f "$mounts_file" ]] || return 0

    local tmp_opts
    tmp_opts="$(awk '$2=="/tmp" {print $4}' "$mounts_file" 2>/dev/null || true)"
    if [[ -n "$tmp_opts" ]]; then
        [[ "$tmp_opts" != *"noexec"* ]] && register_finding "HIGH" "FILESYSTEM" \
            "/tmp is mounted without noexec — attackers can run binaries from /tmp" \
            "Remount: mount -o remount,noexec,nosuid,nodev /tmp  (also fix /etc/fstab)" \
            "CIS-1.1.3"
        [[ "$tmp_opts" != *"nosuid"* ]] && register_finding "HIGH" "FILESYSTEM" \
            "/tmp is mounted without nosuid — SUID binaries can be placed in /tmp" \
            "Remount: mount -o remount,noexec,nosuid,nodev /tmp  (also fix /etc/fstab)" \
            "CIS-1.1.4"
        [[ "$tmp_opts" != *"nodev"* ]] && register_finding "MEDIUM" "FILESYSTEM" \
            "/tmp is mounted without nodev — device files can be created in /tmp" \
            "Remount: mount -o remount,noexec,nosuid,nodev /tmp  (also fix /etc/fstab)" \
            "CIS-1.1.5"
    fi

    local shm_opts
    shm_opts="$(awk '$2=="/dev/shm" {print $4}' "$mounts_file" 2>/dev/null || true)"
    if [[ -n "$shm_opts" && "$shm_opts" != *"noexec"* ]]; then
        register_finding "MEDIUM" "FILESYSTEM" \
            "/dev/shm is mounted without noexec — shared memory exploitable for code execution" \
            "mount -o remount,noexec,nosuid,nodev /dev/shm" \
            "CIS-1.1.16"
    fi

    local proc_opts
    proc_opts="$(awk '$2=="/proc" {print $4}' "$mounts_file" 2>/dev/null || true)"
    if [[ -n "$proc_opts" && "$proc_opts" != *"hidepid=2"* ]]; then
        register_finding "MEDIUM" "FILESYSTEM" \
            "/proc is mounted without hidepid=2 — unprivileged users can see all process info" \
            "mount -o remount,hidepid=2 /proc  (add hidepid=2 to /etc/fstab proc entry)" \
            "N/A"
    fi

    awk '$3=="nfs" || $3=="nfs4" {print $2, $4}' "$mounts_file" 2>/dev/null \
    | while read -r mountpoint opts; do
        [[ "$opts" != *"nosuid"* ]] && register_finding "HIGH" "FILESYSTEM" \
            "NFS mount ${mountpoint} is missing nosuid — remote server could plant SUID files" \
            "Add nosuid to NFS mount options in /etc/fstab and remount" \
            "CIS-1.1.6"
    done
}

# --- /etc/ld.so.preload (library injection) ----------------------------------
check_ld_preload() {
    local preload="/etc/ld.so.preload"
    if [[ -s "$preload" ]]; then
        register_finding "CRITICAL" "FILESYSTEM" \
            "/etc/ld.so.preload exists and is non-empty — injects libraries into every process" \
            "Review: cat ${preload}  — if unexpected, remove: > ${preload}" \
            "N/A"
    fi
}

# --- Run all checks ----------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "${TMP_FINDINGS_FILE:-}" ]]; then
        echo "[ERROR] TMP_FINDINGS_FILE is not set. Run via chase.sh or set it manually:" >&2
        echo "  export TMP_FINDINGS_FILE=\$(mktemp)" >&2
        exit 3
    fi
    run_filesystem_checks
fi
