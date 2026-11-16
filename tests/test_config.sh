#!/bin/bash
# Validates that every architecture advertised by check_arch has a complete,
# internally consistent set of QEMU helper mappings in firmadyne.config.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FIRMWARE_DIR="${REPO_DIR}"
# shellcheck source=../firmadyne.config
source "${REPO_DIR}/firmadyne.config"

FAILED=0

EXPECTED_ARCHES=(armel arm64el mipseb mipsel mips64eb mips64el intelel intel64el)

# check_arch returns failure (1) for a *valid* arch and success (0) otherwise.
for arch in "${EXPECTED_ARCHES[@]}"; do
    if check_arch "${arch}"; then
        echo "FAIL: ${arch} missing from check_arch/ARCHS"
        FAILED=1
    else
        echo "PASS: ${arch} recognised by check_arch"
    fi

    for helper in get_kernel get_qemu get_qemu_cpu get_qemu_disk \
                  get_qemu_machine get_qemu_net_device get_qemu_console \
                  get_console get_nvram; do
        value=$("${helper}" "${arch}")
        if [[ "${value}" == Error:* ]]; then
            echo "FAIL: ${helper} ${arch} -> ${value}"
            FAILED=1
        fi
    done
done

# An unsupported architecture must be rejected instead of silently mapping.
if check_arch "ppceb"; then
    echo "PASS: ppceb rejected as unsupported"
else
    echo "FAIL: ppceb should not be a supported emulation target"
    FAILED=1
fi

# Spot-check concrete QEMU/machine/device values.
assert_eq() {
    if [ "$2" == "$3" ]; then
        echo "PASS: $1 == $3"
    else
        echo "FAIL: $1 (expected $3, got $2)"
        FAILED=1
    fi
}

assert_eq "qemu arm64"    "$(get_qemu arm64el)"    "qemu-system-aarch64"
assert_eq "qemu mips64eb" "$(get_qemu mips64eb)"   "qemu-system-mips64"
assert_eq "qemu mips64el" "$(get_qemu mips64el)"   "qemu-system-mips64el"
assert_eq "qemu i386"     "$(get_qemu intelel)"    "qemu-system-i386"
assert_eq "qemu x86_64"   "$(get_qemu intel64el)"  "qemu-system-x86_64"
assert_eq "machine arm64" "$(get_qemu_machine arm64el)" "virt"
assert_eq "machine x86"   "$(get_qemu_machine intel64el)" "pc"
assert_eq "machine m64"   "$(get_qemu_machine mips64el)" "malta"
assert_eq "cpu arm64"     "$(get_qemu_cpu arm64el)" "cortex-a57"
assert_eq "cpu mips"      "$(get_qemu_cpu mipsel)"  ""
assert_eq "console arm64" "$(get_qemu_console arm64el)" "ttyAMA0"
assert_eq "console x86"   "$(get_qemu_console intelel)" "ttyS0"
assert_eq "net arm64"     "$(get_qemu_net_device arm64el)" "virtio-net-device"
assert_eq "net x86"       "$(get_qemu_net_device intel64el)" "e1000"
assert_eq "disk arm64"    "$(get_qemu_disk arm64el)" "/dev/vda1"
assert_eq "disk x86"      "$(get_qemu_disk intelel)" "/dev/sda1"

exit ${FAILED}
