#!/usr/bin/env bats
# =============================================================================
#  tests/test_network.bats — Unit tests for modules/network.sh
# =============================================================================

setup() {
    CHASE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    register_finding() { echo "FINDING:$1:$2:$3" >> "$TMP_FINDINGS_FILE"; }
    log_info() { :; }; log_ok() { :; }; log_high() { :; }

    source "${CHASE_DIR}/lib/utils.sh"
    source "${CHASE_DIR}/lib/compat.sh"

    TMP_FINDINGS_FILE="$(mktemp /tmp/bats_findings.XXXXXX)"
    export TMP_FINDINGS_FILE
}

teardown() { rm -f "$TMP_FINDINGS_FILE"; }

# ---------------------------------------------------------------------------
@test "check_ssh_config: detects PermitRootLogin yes" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/network.sh" 2>/dev/null || true

    check_ssh_config "${CHASE_DIR}/tests/fixtures/sshd_config.vulnerable"

    grep -q "PermitRootLogin" "$TMP_FINDINGS_FILE"
}

@test "check_ssh_config: hardened config produces no CRITICAL SSH findings" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/network.sh" 2>/dev/null || true

    check_ssh_config "${CHASE_DIR}/tests/fixtures/sshd_config.hardened"

    ! grep -q "CRITICAL" "$TMP_FINDINGS_FILE"
}

@test "check_ssh_config: detects CBC ciphers" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/network.sh" 2>/dev/null || true

    check_ssh_config "${CHASE_DIR}/tests/fixtures/sshd_config.vulnerable"

    grep -q "CBC" "$TMP_FINDINGS_FILE"
}

@test "check_ssh_config: detects MaxAuthTries > 4" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/network.sh" 2>/dev/null || true

    check_ssh_config "${CHASE_DIR}/tests/fixtures/sshd_config.vulnerable"

    grep -q "MaxAuthTries" "$TMP_FINDINGS_FILE"
}
