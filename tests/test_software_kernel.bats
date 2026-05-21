#!/usr/bin/env bats
# =============================================================================
#  tests/test_software_kernel.bats — Unit tests for modules/software_kernel.sh
# =============================================================================

setup() {
    CHASE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    register_finding() { echo "FINDING:$1:$2:$3" >> "$TMP_FINDINGS_FILE"; }
    log_info() { :; }; log_ok() { :; }; log_warn() { :; }

    source "${CHASE_DIR}/lib/utils.sh"
    source "${CHASE_DIR}/lib/compat.sh"

    TMP_FINDINGS_FILE="$(mktemp /tmp/bats_findings.XXXXXX)"
    export TMP_FINDINGS_FILE

    # Setup temp mock ETC directory
    MOCK_ETC="$(mktemp -d)"
    mkdir -p "${MOCK_ETC}/audit"
    mkdir -p "${MOCK_ETC}/modprobe.d"
    export ETC_DIR="$MOCK_ETC"
}

teardown() {
    rm -rf "$MOCK_ETC"
    rm -f "$TMP_FINDINGS_FILE"
}

@test "check_auditd: flags disk_full_action set to IGNORE" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/software_kernel.sh" 2>/dev/null || true

    echo "disk_full_action = IGNORE" > "${MOCK_ETC}/audit/auditd.conf"

    # We stub systemctl so it says auditd is running
    systemctl() {
        if [[ "$1" == "is-active" && "$3" == "auditd" ]]; then
            return 0
        fi
        command systemctl "$@"
    }

    check_auditd

    grep -q "disk_full_action not configured or set to IGNORE" "$TMP_FINDINGS_FILE"
}

@test "check_dangerous_modules: flags un-blacklisted dangerous module" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/software_kernel.sh" 2>/dev/null || true

    # Dangerous modules array: DANGEROUS_MODULES=( dccp sctp rds ... )
    # Create an empty modprobe.d directory. All dangerous modules will be flagged.
    check_dangerous_modules

    grep -q "Kernel module 'dccp' is not blacklisted" "$TMP_FINDINGS_FILE"
}

@test "check_dangerous_modules: passes if dangerous modules are blacklisted" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/software_kernel.sh" 2>/dev/null || true

    # Create hardening conf with all dangerous modules blacklisted
    local hardening_conf="${MOCK_ETC}/modprobe.d/chase-hardening.conf"
    for mod in "${DANGEROUS_MODULES[@]}"; do
        echo "install ${mod} /bin/true" >> "$hardening_conf"
    done

    check_dangerous_modules

    [ ! -s "$TMP_FINDINGS_FILE" ]
}
