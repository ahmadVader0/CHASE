#!/usr/bin/env bash
# =============================================================================
#  run_tests.sh — CHASE test runner
#  Executes all BATS unit tests in the suite.
# =============================================================================

set -euo pipefail

CHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure bats is installed
if ! command -v bats &>/dev/null; then
    echo "[ERROR] bats is not installed. Please install it first:" >&2
    echo "  sudo apt install -y bats" >&2
    exit 1
fi

echo "============================================================================="
echo "  Running CHASE Test Suite"
echo "============================================================================="
echo

# Run all bats tests in the tests directory
bats "${CHASE_DIR}/tests/"*.bats
