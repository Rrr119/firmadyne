#!/bin/bash
# Runs the full self-contained test suite. These tests do not require QEMU,
# PostgreSQL, root privileges, or a firmware image.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0

run() {
    echo "=================================================================="
    echo "Running $1"
    echo "------------------------------------------------------------------"
    if "$@"; then
        echo "OK: $1"
    else
        echo "FAILED: $1"
        FAILED=1
    fi
}

# Static syntax checks for every shell script touched by the multi-arch work.
echo "Running shell syntax checks..."
while IFS= read -r script; do
    if ! bash -n "${script}"; then
        echo "FAIL: syntax error in ${script}"
        FAILED=1
    fi
done < <(find "${REPO_DIR}/scripts" -maxdepth 1 -name '*.sh' -print)

run bash "${SCRIPT_DIR}/test_getArch.sh"
run bash "${SCRIPT_DIR}/test_kernel_version.sh"
run bash "${SCRIPT_DIR}/test_config.sh"
run python3 "${SCRIPT_DIR}/test_makeNetwork.py"

echo "=================================================================="
if [ "${FAILED}" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests failed."
fi
exit ${FAILED}
