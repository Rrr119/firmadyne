#!/bin/bash
# Unit tests for getKernelVersion() in scripts/getArch.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/getArch.sh
source "${REPO_DIR}/scripts/getArch.sh"

FAILED=0

check() {
    local description="$1"
    local filetype="$2"
    local expected="$3"
    local actual
    FILETYPE="${filetype}"
    actual=$(getKernelVersion)
    if [ "${actual}" == "${expected}" ]; then
        echo "PASS: ${description}"
    else
        echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
        FAILED=1
    fi
}

check "capitalised Version prefix" \
    "vmlinux: Linux kernel, Version 3.4.11-rt19, SMP" \
    "3.4.11-rt19"
check "lowercase version prefix" \
    "bzImage: Linux kernel x86 boot executable, version 5.10.120" \
    "5.10.120"
check "plain userspace binary has no kernel version" \
    "busybox: ELF 64-bit LSB executable, x86-64, version 1 (SYSV)" \
    ""

exit ${FAILED}
