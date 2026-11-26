#!/bin/bash

# Acceptance test for the FIRMADYNE health-check / console additions.
#
# No real firmware or QEMU is required: tests/mock_qemu.py impersonates
# qemu-system-* while three fixture "firmwares" are driven through the same
# generated scratch/<IID>/run.sh that inferNetwork.sh produces.
#
# Fixtures:
#   101 success       - boots fully, serves a TCP port, must report SUCCESS
#   102 kernel_panic  - dies mounting the rootfs, must report FAILURE and
#                       locate the stuck point at rootfs_mount/kernel
#   103 service_fail  - boots and gets an IP, but the web service crashes,
#                       must report FAILURE at service_start

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/firmadyne-acceptance.XXXXXX")
MOCK_QEMU="${REPO_ROOT}/tests/mock_qemu.py"
PASS_COUNT=0
FAIL_COUNT=0

trap 'rm -rf "${TEST_ROOT}"' EXIT

echo "Test sandbox: ${TEST_ROOT}"

# ---------------------------------------------------------------------------
# Build a fake FIRMWARE_DIR layout with mock qemu binaries on PATH.
# ---------------------------------------------------------------------------
export SCRATCH_DIR="${TEST_ROOT}/scratch"
# firmadyne.config derives all paths from FIRMWARE_DIR; only SCRATCH_DIR is
# overridden so the fixtures stay inside the test sandbox.
export FIRMWARE_DIR="${REPO_ROOT}"
mkdir -p "${SCRATCH_DIR}"

MOCK_BIN="${TEST_ROOT}/bin"
mkdir -p "${MOCK_BIN}"
for qemu in qemu-system-mips qemu-system-mipsel qemu-system-arm; do
    cat > "${MOCK_BIN}/${qemu}" <<EOF
#!/bin/bash
exec python3 "${MOCK_QEMU}" "\$@"
EOF
    chmod +x "${MOCK_BIN}/${qemu}"
done
export PATH="${MOCK_BIN}:${PATH}"

# The mock TAP/tunctl setup must be a no-op: emulate.sh only invokes the
# generated run.sh, and its network section calls sudo/ip/tunctl.  Stub them.
for stub in sudo ip tunctl; do
    cat > "${MOCK_BIN}/${stub}" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${MOCK_BIN}/${stub}"
done

# ---------------------------------------------------------------------------
# Create one scratch/<IID>/run.sh per fixture by rendering the same template
# makeNetwork.py emits, using a tiny driver script.
# ---------------------------------------------------------------------------
create_fixture() {
    local iid=$1
    local guest_ip=$2
    local work_dir="${SCRATCH_DIR}/${iid}"
    mkdir -p "${work_dir}"

    REPO_ROOT="${REPO_ROOT}" python3 - "${iid}" "${work_dir}/run.sh" <<'PY'
import os
import sys

sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts"))

from makeNetwork import qemuCmd

iid = int(sys.argv[1])
outfile = sys.argv[2]
# (guest ip, host device, vlan id, mac) mirrors makeNetwork.py tuples.
network = [("127.0.0.55", "eth0", None, None)]
script = qemuCmd(iid, network, "mips", "el")
with open(outfile, "w") as handle:
    handle.write(script)
os.chmod(outfile, 0o755)
PY

    # Point the route line at the loopback address so host-side probes in the
    # test can reach the mock TCP listener.
    sed -i "s/127\.0\.0\.55/${guest_ip}/g" "${work_dir}/run.sh"
}

export REPO_ROOT

# Pick an ephemeral port that is free on this host.
TCP_PORT=$(python3 -c "
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
")
export FIRMADYNE_MOCK_TCP_PORT="${TCP_PORT}"
echo "Using ephemeral service port ${TCP_PORT}"

create_fixture 101 "127.0.0.1"
create_fixture 102 "127.0.0.1"
create_fixture 103 "127.0.0.1"

run_fixture() {
    local iid=$1
    local scenario=$2
    local expected=$3
    local expected_stage=$4

    echo ""
    echo "=== Fixture ${iid}: scenario=${scenario} expect=${expected} ==="
    FIRMADYNE_MOCK_SCENARIO="${scenario}" \
        "${REPO_ROOT}/scripts/emulate.sh" "${iid}" mipsel \
        --daemon --boot-timeout 3 --check-timeout 6 -p "${TCP_PORT}" \
        > "${TEST_ROOT}/${iid}.out" 2>&1
    local rc=$?
    cat "${TEST_ROOT}/${iid}.out"

    # Stop the mock emulation no matter how the verdict went.
    local pid_file="${SCRATCH_DIR}/${iid}/qemu.pid"
    if [ -f "${pid_file}" ]; then
        kill "$(cat "${pid_file}")" 2>/dev/null || true
    fi
    pkill -f "mock_qemu.py" 2>/dev/null || true

    local ok=1
    if [ "${expected}" = "success" ] && [ "${rc}" -ne 0 ]; then
        echo "  ASSERT FAIL: expected exit 0, got ${rc}"
        ok=0
    fi
    if [ "${expected}" = "failure" ] && [ "${rc}" -eq 0 ]; then
        echo "  ASSERT FAIL: expected non-zero exit, got 0"
        ok=0
    fi

    local report="${SCRATCH_DIR}/${iid}/healthcheck.json"
    if [ ! -f "${report}" ]; then
        echo "  ASSERT FAIL: healthcheck report missing at ${report}"
        ok=0
    else
        local verdict stage
        verdict=$(python3 -c "import json;print(json.load(open('${report}'))['success'])")
        stage=$(python3 -c "import json;print(json.load(open('${report}')).get('failure_stage'))")
        echo "  report: success=${verdict} failure_stage=${stage}"
        if [ "${expected}" = "success" ] && [ "${verdict}" != "True" ]; then
            echo "  ASSERT FAIL: report.success is not true"
            ok=0
        fi
        if [ "${expected}" = "failure" ]; then
            if [ "${verdict}" != "False" ]; then
                echo "  ASSERT FAIL: report.success should be false"
                ok=0
            fi
            if [ -n "${expected_stage}" ] && [ "${stage}" != "${expected_stage}" ]; then
                echo "  ASSERT FAIL: expected failure_stage '${expected_stage}', got '${stage}'"
                ok=0
            fi
        fi
    fi

    if [ "${ok}" -eq 1 ]; then
        echo "  -> PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  -> FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

run_fixture 101 success success ""
run_fixture 102 kernel_panic failure "kernel"
run_fixture 103 service_fail failure "service_start"

# ---------------------------------------------------------------------------
# Extra check: interactive console entry can attach to the exposed socket.
# ---------------------------------------------------------------------------
echo ""
echo "=== Fixture 101: console socket attach ==="
FIRMADYNE_MOCK_SCENARIO=success FIRMADYNE_DAEMON=1 \
    "${SCRATCH_DIR}/101/run.sh" >/dev/null 2>&1 &
RUN_PID=$!
sleep 4
if [ -S "${SCRATCH_DIR}/101/console.sock" ]; then
    # QEMU keeps a serial socket open for the VM lifetime, so a successful
    # attach looks like nc connecting and then idling until the timeout
    # (rc 124).  A refused/unavailable socket exits immediately with rc 1.
    set +e
    timeout 2 nc -U "${SCRATCH_DIR}/101/console.sock" </dev/null >/dev/null 2>&1
    nc_rc=$?
    set -e
    if [ "${nc_rc}" -eq 124 ]; then
        echo "  console.sock accepts and holds a connection -> PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  console.sock connection failed (nc rc=${nc_rc}) -> FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  console.sock not created -> FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
kill "${RUN_PID}" 2>/dev/null || true
pkill -f "mock_qemu.py" 2>/dev/null || true

echo ""
echo "Acceptance summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "${FAIL_COUNT}" -eq 0 ]
