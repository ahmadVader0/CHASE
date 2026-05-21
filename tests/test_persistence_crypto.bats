#!/usr/bin/env bats
# =============================================================================
#  tests/test_persistence_crypto.bats — Unit tests for modules/persistence_crypto.sh
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
    mkdir -p "${MOCK_ETC}/profile.d"
    export ETC_DIR="$MOCK_ETC"
}

teardown() {
    rm -rf "$MOCK_ETC"
    rm -f "$TMP_FINDINGS_FILE"
}

@test "check_profile_d: flags non-standard file in profile.d" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/persistence_crypto.sh" 2>/dev/null || true

    touch "${MOCK_ETC}/profile.d/suspicious_backdoor.sh"

    check_profile_d

    grep -q "Non-standard file in /etc/profile.d/" "$TMP_FINDINGS_FILE"
}

@test "check_profile_d: does not flag standard files in profile.d" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/persistence_crypto.sh" 2>/dev/null || true

    touch "${MOCK_ETC}/profile.d/bash_completion.sh"
    touch "${MOCK_ETC}/profile.d/umask.sh"

    check_profile_d

    [ ! -s "$TMP_FINDINGS_FILE" ]
}
