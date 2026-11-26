#!/bin/bash

# End-to-end emulation entry point with an automatic health verdict.
#
# Replaces the manual "run scratch/<IID>/run.sh and hope for the best" flow:
#   1. boots the firmware (foreground or detached daemon mode),
#   2. waits for the boot to settle,
#   3. runs scripts/healthCheck.py to decide SUCCESS / FAILURE and, on
#      failure, reports the exact boot stage where emulation got stuck,
#   4. in foreground mode leaves the analyst at the guest console; in daemon
#      mode keeps QEMU running and prints the console.sh attach command.
#
# Fully compatible with the existing per-image scratch/<IID>/run.sh generated
# by inferNetwork.sh / makeNetwork.py: when FIRMADYNE_DAEMON is unset the
# generated script behaves exactly as before.

set -u

if [ -e ./firmadyne.config ]; then
    source ./firmadyne.config
elif [ -e ../firmadyne.config ]; then
    source ../firmadyne.config
else
    echo "Error: Could not find 'firmadyne.config'!"
    exit 1
fi

usage() {
    cat <<EOF
Usage: emulate.sh <image ID> [<architecture>] [options]

Options:
  --daemon            run QEMU in the background instead of taking over the
                      terminal; attach later with scripts/console.sh <IID>
  --boot-timeout S    seconds to wait for boot before health checks (default: 90)
  --check-timeout S   seconds the health check may probe services (default: 60)
  -p, --ports PORTS   comma-separated TCP ports that must be listening
                      (default: 80,443; pass '' to rely on ICMP only)
  -H, --host IP       guest IP; auto-detected from scratch/<IID>/run.sh
  --no-check          boot only, skip the health check
  -h, --help          show this help
EOF
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    if [ $# -lt 1 ]; then
        exit 1
    fi
    exit 0
fi

if ! printf '%s' "$1" | grep -Eq '^[0-9]+$' || check_number "$1"; then
    usage
    exit 1
fi
IID=${1}
shift

ARCH=""
DAEMON=0
BOOT_TIMEOUT=90
CHECK_TIMEOUT=60
PORTS="80,443"
HOST=""
DO_CHECK=1

while [ $# -gt 0 ]; do
    case "$1" in
        --daemon) DAEMON=1; shift ;;
        --boot-timeout) BOOT_TIMEOUT=$2; shift 2 ;;
        --check-timeout) CHECK_TIMEOUT=$2; shift 2 ;;
        -p|--ports) PORTS=$2; shift 2 ;;
        -H|--host) HOST=$2; shift 2 ;;
        --no-check) DO_CHECK=0; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Error: unknown option $1"; usage; exit 1 ;;
        *)
            if [ -z "${ARCH}" ]; then
                ARCH=$1
                shift
            else
                echo "Error: unexpected argument $1"
                usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "${ARCH}" ]; then
    echo -n "Querying database for architecture... "
    ARCH=$(psql -d firmware -U firmadyne -h 127.0.0.1 -t -q \
        -c "SELECT arch from image WHERE id=${IID};" 2>/dev/null | tr -d '[:space:]')
    echo "${ARCH:-<not found>}"
    if [ -z "${ARCH}" ]; then
        echo "Error: Unable to lookup architecture. Please specify {armel,mipseb,mipsel} as the second argument!"
        exit 1
    fi
fi

if check_arch "${ARCH}"; then
    echo "Error: Invalid architecture '${ARCH}'!"
    exit 1
fi

WORK_DIR=$(get_scratch "${IID}")
RUN_SCRIPT="${WORK_DIR}/run.sh"

if [ ! -x "${RUN_SCRIPT}" ]; then
    echo "Error: ${RUN_SCRIPT} not found."
    echo "Run the extraction/makeImage/inferNetwork steps first (see example_analysis.sh)."
    exit 1
fi

QEMU_LOG="${WORK_DIR}/qemu.final.serial.log"
PID_FILE="${WORK_DIR}/qemu.pid"
REPORT_FILE="${WORK_DIR}/healthcheck.json"

cleanup_stale() {
    if [ -f "${PID_FILE}" ] && ! kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
        rm -f "${PID_FILE}"
    fi
}

cleanup_stale
if [ -f "${PID_FILE}" ]; then
    echo "Error: emulation for image ${IID} already appears to be running (pid $(cat "${PID_FILE}"))."
    echo "Attach with: ./scripts/console.sh ${IID}"
    exit 1
fi

if [ "${DAEMON}" -eq 1 ]; then
    echo "Starting firmware ${IID} (${ARCH}) in daemon mode..."
    FIRMADYNE_DAEMON=1 "${RUN_SCRIPT}" &
    QEMU_PID=$!
    echo "${QEMU_PID}" > "${PID_FILE}"

    # Reap the wrapper automatically if it exits, and drop the stale pid file.
    (
        wait "${QEMU_PID}" 2>/dev/null
        rm -f "${PID_FILE}"
    ) &

    echo "QEMU wrapper pid ${QEMU_PID}; waiting ${BOOT_TIMEOUT}s for boot to settle..."
    sleep "${BOOT_TIMEOUT}"

    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
        echo "[emulate] QEMU exited early; serial log tail:"
        tail -n 20 "${QEMU_LOG}" 2>/dev/null || true
    fi
else
    echo "Starting firmware ${IID} (${ARCH}) in foreground..."
    echo "QEMU takes over this terminal; Ctrl-a x terminates the emulation."
    echo "The health check runs in the background after ${BOOT_TIMEOUT}s and"
    echo "writes its verdict to ${REPORT_FILE}."
    (
        sleep "${BOOT_TIMEOUT}"
        python3 "${SCRIPT_DIR}/healthCheck.py" "${IID}" \
            -S "${SCRATCH_DIR}" -t "${CHECK_TIMEOUT}" -p "${PORTS}" \
            ${HOST:+-H "${HOST}"} -o "${REPORT_FILE}" \
            > "${WORK_DIR}/healthcheck.out" 2>&1 || true
    ) &
    exec "${RUN_SCRIPT}"
fi

if [ "${DO_CHECK}" -eq 0 ]; then
    echo "Boot requested without health check (--no-check)."
    echo "Attach to the guest: ./scripts/console.sh ${IID}"
    exit 0
fi

CHECK_ARGS=("${IID}" -S "${SCRATCH_DIR}" -t "${CHECK_TIMEOUT}"
            -p "${PORTS}" -o "${REPORT_FILE}")
if [ -n "${HOST}" ]; then
    CHECK_ARGS+=(-H "${HOST}")
fi

echo "Running health check..."
python3 "${SCRIPT_DIR}/healthCheck.py" "${CHECK_ARGS[@]}"
VERDICT=$?

if [ "${VERDICT}" -eq 0 ]; then
    echo ""
    echo "[emulate] SUCCESS: firmware ${IID} is emulated and healthy."
    echo "Attach to the guest shell: ./scripts/console.sh ${IID}"
    echo "Stop the emulation:      kill \$(cat ${PID_FILE})"
else
    echo ""
    echo "[emulate] FAILURE: firmware ${IID} did not emulate correctly."
    python3 - "${REPORT_FILE}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as handle:
        report = json.load(handle)
except OSError:
    sys.exit(0)
print("  stuck at stage: %s" % report.get("failure_stage"))
print("  reason:         %s" % report.get("reason"))
failure = report.get("serial_failure")
if failure:
    print("  log evidence:   %s" % failure.get("evidence"))
PY
    echo "Inspect the serial log: tail -n 100 ${QEMU_LOG}"
fi

exit "${VERDICT}"
