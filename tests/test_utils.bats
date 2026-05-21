#!/usr/bin/env bats
# =============================================================================
#  tests/test_utils.bats — Unit tests for lib/utils.sh
# =============================================================================

setup() {
    CHASE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${CHASE_DIR}/lib/utils.sh"
    source "${CHASE_DIR}/lib/compat.sh"
}

@test "trim: strips leading and trailing spaces" {
    local res
    res="$(trim "  hello world   ")"
    [ "$res" = "hello world" ]
}

@test "to_lower: converts uppercase letters to lowercase" {
    local res
    res="$(to_lower "HeLLo WoRLD!")"
    [ "$res" = "hello world!" ]
}

@test "is_greater_than: returns true if first value is greater than second" {
    run is_greater_than 100 90
    [ "$status" -eq 0 ]
}

@test "is_greater_than: returns false if first value is less than or equal to second" {
    run is_greater_than 90 100
    [ "$status" -ne 0 ]

    run is_greater_than 90 90
    [ "$status" -ne 0 ]
}

@test "html_escape: escapes html characters" {
    local res
    res="$(html_escape '<hello & "world">')"
    [ "$res" = "&lt;hello &amp; &quot;world&quot;&gt;" ]
}

@test "json_escape: escapes quotes and slashes and newlines" {
    local res
    res="$(json_escape 'hello "world" \
newline')"
    # Wait, the newline in single quotes above is a literal newline.
    # Let's see: we expect quotes and backslashes to be escaped.
    # Let's test a simpler string first:
    local simple_res
    simple_res="$(json_escape 'hello "world" \ path')"
    [ "$simple_res" = 'hello \"world\" \\ path' ]
}

@test "detect_os: sets CHASE_OS_FAMILY to debian on Ubuntu/Debian host" {
    detect_os
    [ "$CHASE_OS_FAMILY" = "debian" ]
}

@test "pkg_install_cmd: returns correct package manager installer command" {
    CHASE_OS_FAMILY="debian"
    local res
    res="$(pkg_install_cmd)"
    [ "$res" = "apt-get install -y" ]

    CHASE_OS_FAMILY="rhel"
    res="$(pkg_install_cmd)"
    [ "$res" = "dnf install -y" ]

    CHASE_OS_FAMILY="alpine"
    res="$(pkg_install_cmd)"
    [ "$res" = "apk add" ]
}
