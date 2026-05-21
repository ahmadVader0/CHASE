#!/usr/bin/env bats
# =============================================================================
#  tests/test_iam.bats — Unit tests for modules/iam.sh
#  Run with: bats tests/test_iam.bats
# =============================================================================

setup() {
    CHASE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

    # Minimal stubs for logger functions
    register_finding() { echo "FINDING:$1:$2:$3" >> "$TMP_FINDINGS_FILE"; }
    log_info()  { :; }
    log_ok()    { :; }

    # Helpers from utils
    source "${CHASE_DIR}/lib/utils.sh"
    source "${CHASE_DIR}/lib/compat.sh"

    # Each test gets a fresh temp findings file
    TMP_FINDINGS_FILE="$(mktemp /tmp/bats_findings.XXXXXX)"
    export TMP_FINDINGS_FILE
}

teardown() {
    rm -f "$TMP_FINDINGS_FILE"
}

# ---------------------------------------------------------------------------
@test "check_empty_passwords: detects account with truly empty password" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true  # defines functions without running

    check_empty_passwords "${CHASE_DIR}/tests/fixtures/shadow.empty_passwords"

    grep -q "CRITICAL" "$TMP_FINDINGS_FILE"
}

@test "check_empty_passwords: clean shadow file produces no CRITICAL findings" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    # Create a clean shadow file with no empty passwords
    local clean_shadow
    clean_shadow="$(mktemp)"
    echo 'root:$6$salt$hashedpw:19000:0:99999:7:::' > "$clean_shadow"
    echo 'daemon:*:18561:0:99999:7:::' >> "$clean_shadow"

    check_empty_passwords "$clean_shadow"
    rm -f "$clean_shadow"

    [ ! -s "$TMP_FINDINGS_FILE" ]
}

@test "check_uid_zero: detects UID 0 backdoor account" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    check_uid_zero "${CHASE_DIR}/tests/fixtures/passwd.with_uid0_backdoor"

    grep -q "eviluser" "$TMP_FINDINGS_FILE"
}

@test "check_uid_zero: clean passwd file produces no UID 0 findings" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    check_uid_zero "${CHASE_DIR}/tests/fixtures/passwd.clean"

    [ ! -s "$TMP_FINDINGS_FILE" ]
}

@test "check_duplicate_uids: detects duplicate UID" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    local dupe_passwd
    dupe_passwd="$(mktemp)"
    printf 'root:x:0:0:root:/root:/bin/bash\nalice:x:1001:1001::/home/alice:/bin/bash\nbob:x:1001:1001::/home/bob:/bin/bash\n' > "$dupe_passwd"

    check_duplicate_uids "$dupe_passwd"
    rm -f "$dupe_passwd"

    grep -q "Duplicate UID" "$TMP_FINDINGS_FILE"
}

@test "check_pass_max_days: flags PASS_MAX_DAYS > 90" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    local defs
    defs="$(mktemp)"
    echo "PASS_MAX_DAYS 999" > "$defs"

    check_pass_max_days "$defs"
    rm -f "$defs"

    grep -q "PASS_MAX_DAYS" "$TMP_FINDINGS_FILE"
}

@test "check_pass_max_days: does not flag PASS_MAX_DAYS = 90" {
    source "${CHASE_DIR}/core/logger.sh" 2>/dev/null || true
    source "${CHASE_DIR}/modules/iam.sh" 2>/dev/null || true

    local defs
    defs="$(mktemp)"
    echo "PASS_MAX_DAYS 90" > "$defs"

    check_pass_max_days "$defs"
    rm -f "$defs"

    [ ! -s "$TMP_FINDINGS_FILE" ]
}
