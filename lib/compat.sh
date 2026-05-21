#!/usr/bin/env bash
# =============================================================================
#  lib/compat.sh — Compatibility shims for BusyBox vs GNU coreutils
#  Some embedded/minimal Linux distros ship BusyBox awk/sed with reduced feature
#  sets. These wrappers pick the best available variant at runtime.
# =============================================================================

# --- stat: BSD vs GNU --------------------------------------------------------
# GNU stat: stat -c '%a' file
# BSD stat: stat -f '%A' file
_STAT_FLAVOR="gnu"
if stat --version 2>/dev/null | grep -q 'GNU'; then
    _STAT_FLAVOR="gnu"
elif stat -f '%A' /etc/passwd &>/dev/null; then
    _STAT_FLAVOR="bsd"
fi

compat_stat_perms() {
    case "$_STAT_FLAVOR" in
        gnu) stat -c '%a' "$1" 2>/dev/null ;;
        bsd) stat -f '%A' "$1" 2>/dev/null ;;
        *)   echo "000" ;;
    esac
}

compat_stat_owner() {
    case "$_STAT_FLAVOR" in
        gnu) stat -c '%U' "$1" 2>/dev/null ;;
        bsd) stat -f '%Su' "$1" 2>/dev/null ;;
        *)   echo "unknown" ;;
    esac
}

compat_stat_mtime() {
    case "$_STAT_FLAVOR" in
        gnu) stat -c '%Y' "$1" 2>/dev/null ;;
        bsd) stat -f '%m' "$1" 2>/dev/null ;;
        *)   echo 0 ;;
    esac
}

# --- date: GNU vs BSD --------------------------------------------------------
# GNU date supports -d for parsing; BSD uses -j -f
_DATE_FLAVOR="gnu"
if date --version 2>/dev/null | grep -q 'GNU'; then
    _DATE_FLAVOR="gnu"
else
    _DATE_FLAVOR="bsd"
fi

# Parse a date string like "Nov 30 23:59:59 2024 GMT" → epoch seconds
compat_date_to_epoch() {
    local datestr="$1"
    case "$_DATE_FLAVOR" in
        gnu) date -d "$datestr" +%s 2>/dev/null || echo 0 ;;
        bsd) date -j -f "%b %d %H:%M:%S %Y %Z" "$datestr" +%s 2>/dev/null || echo 0 ;;
        *)   echo 0 ;;
    esac
}

# --- ionice availability -----------------------------------------------------
# Some minimal systems lack ionice; fall back to just nice in that case
if command -v ionice &>/dev/null; then
    IONICE_PREFIX="ionice -c 3"
else
    IONICE_PREFIX=""
fi
export IONICE_PREFIX

# --- OS Auto-Detection --------------------------------------------------------
detect_os() {
    CHASE_OS_FAMILY="unknown"
    CHASE_OS_NAME="unknown"
    CHASE_OS_VERSION="unknown"

    if [[ -f "/etc/os-release" ]]; then
        local ID="" NAME="" VERSION_ID="" ID_LIKE=""
        # Read keys cleanly to avoid unsafe eval
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^(ID|NAME|VERSION_ID|ID_LIKE)$ ]] || continue
            # Strip outer quotes if any
            value="${value#\"}"
            value="${value%\"}"
            case "$key" in
                ID)         ID="$value" ;;
                NAME)       NAME="$value" ;;
                VERSION_ID) VERSION_ID="$value" ;;
                ID_LIKE)    ID_LIKE="$value" ;;
            esac
        done < /etc/os-release

        CHASE_OS_NAME="$NAME"
        CHASE_OS_VERSION="$VERSION_ID"

        local check_id
        check_id="$(echo "$ID" | tr '[:upper:]' '[:lower:]')"
        local like
        like="$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"

        if [[ "$check_id" == "ubuntu" || "$check_id" == "debian" || "$like" == *"debian"* || "$like" == *"ubuntu"* ]]; then
            CHASE_OS_FAMILY="debian"
        elif [[ "$check_id" == "rhel" || "$check_id" == "centos" || "$check_id" == "fedora" || "$check_id" == "rocky" || "$check_id" == "almalinux" || "$like" == *"rhel"* || "$like" == *"fedora"* ]]; then
            CHASE_OS_FAMILY="rhel"
        elif [[ "$check_id" == "alpine" ]]; then
            CHASE_OS_FAMILY="alpine"
        fi
    fi
    export CHASE_OS_FAMILY CHASE_OS_NAME CHASE_OS_VERSION
}

pkg_install_cmd() {
    case "${CHASE_OS_FAMILY:-unknown}" in
        debian) echo "apt-get install -y" ;;
        rhel)   echo "dnf install -y"     ;;
        alpine) echo "apk add"            ;;
        *)      echo "apt-get install -y" ;;
    esac
}

