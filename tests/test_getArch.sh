#!/bin/bash
# Unit tests for the architecture/endianness detection helpers in
# scripts/getArch.sh. The script is sourced so the database/tarball logic is
# not exercised.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/getArch.sh
source "${REPO_DIR}/scripts/getArch.sh"

FAILED=0

# classify <file-output> <expected-arch-end>
classify() {
    FILETYPE="$1"
    getArch
    getEndian
    if [ -z "${END}" ]; then
        END=$(defaultEndian "${ARCH}")
    fi
    echo "${ARCH}${END}"
}

check() {
    local description="$1"
    local filetype="$2"
    local expected="$3"
    local actual
    actual=$(classify "${filetype}")
    if [ "${actual}" == "${expected}" ]; then
        echo "PASS: ${description}"
    else
        echo "FAIL: ${description} (expected ${expected}, got ${actual})"
        FAILED=1
    fi
}

# Real `file(1)` strings observed on router binaries across architectures.
check "32-bit little-endian ARM" \
    "busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV)" \
    "armel"
check "64-bit little-endian ARM (aarch64 keyword)" \
    "busybox: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV)" \
    "arm64el"
check "64-bit little-endian ARM (ARM64 keyword)" \
    "busybox: ELF 64-bit LSB executable, ARM64, version 1 (SYSV)" \
    "arm64el"
check "32-bit big-endian MIPS" \
    "busybox: ELF 32-bit MSB executable, MIPS, MIPS32 version 1 (SYSV)" \
    "mipseb"
check "32-bit little-endian MIPS" \
    "busybox: ELF 32-bit LSB executable, MIPS, MIPS32 rel2 version 1 (SYSV)" \
    "mipsel"
check "64-bit big-endian MIPS" \
    "busybox: ELF 64-bit MSB executable, MIPS, MIPS64 rel2 version 1 (SYSV)" \
    "mips64eb"
check "64-bit little-endian MIPS (N64 ABI)" \
    "busybox: ELF 64-bit LSB executable, MIPS, MIPS64 rel2, N64 version 1 (SYSV)" \
    "mips64el"
check "32-bit x86" \
    "busybox: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV)" \
    "intelel"
check "64-bit x86-64" \
    "busybox: ELF 64-bit LSB executable, x86-64, version 1 (SYSV)" \
    "intel64el"
check "32-bit big-endian PowerPC (recognised, not yet emulated)" \
    "busybox: ELF 32-bit MSB executable, PowerPC or cisco 4500, version 1 (SYSV)" \
    "ppceb"
check "64-bit big-endian PowerPC (recognised, not yet emulated)" \
    "busybox: ELF 64-bit MSB executable, 64-bit PowerPC or cisco 7500, version 1 (SYSV)" \
    "ppc64eb"

# Fixed-endian architectures must still get an endian suffix even when the
# `file` output omits an LSB/MSB token.
check "aarch64 without explicit LSB marker" \
    "busybox: ELF 64-bit executable, ARM aarch64, version 1 (SYSV)" \
    "arm64el"

# Unknown input must yield an empty architecture instead of crashing.
FILETYPE="busybox: data"
getArch
getEndian
if [ -z "${ARCH}" ] && [ -z "${END}" ]; then
    echo "PASS: unknown file type yields empty architecture"
else
    echo "FAIL: unknown file type (got arch='${ARCH}' end='${END}')"
    FAILED=1
fi

exit ${FAILED}
