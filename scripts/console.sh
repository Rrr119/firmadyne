#!/bin/bash

# Interactive entry point into an emulated firmware image.
#
# Connects to a Unix-domain socket exposed by QEMU:
#   * the first serial port ttyS0 (default): boot log and the guest login
#     prompt,
#   * the second serial port ttyS1 with --shell: the root shell provided by
#     sources/console (/firmadyne/console), no login required,
#   * the QEMU monitor with --monitor (info/status and clean shutdown via
#     `quit`).
#
# Works with both socket layouts:
#   - new daemon mode:  scratch/<IID>/console.sock / monitor.sock
#   - legacy layout:    /tmp/qemu.<IID>.S1    / /tmp/qemu.<IID>

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
Usage: console.sh <image ID> [--shell] [--monitor]

  --shell     attach to the ttyS1 root shell instead of the ttyS0 console
  --monitor   attach to the QEMU monitor instead of the guest serial console

The emulation for this image must already be running, e.g.
  ./scripts/emulate.sh <IID> --daemon

Exit the console with Ctrl-] (netcat) or ~. (socat); shut QEMU down cleanly
from the monitor with the 'quit' command.
EOF
}

if [ $# -lt 1 ] || [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
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

MODE="console"
for arg in "$@"; do
    case "${arg}" in
        --shell) MODE="shell" ;;
        --monitor) MODE="monitor" ;;
        *) echo "Error: unknown argument '${arg}'"; usage; exit 1 ;;
    esac
done

WORK_DIR=$(get_scratch "${IID}")

if [ "${MODE}" = "monitor" ]; then
    SOCKETS=("${WORK_DIR}/monitor.sock" "/tmp/qemu.${IID}")
elif [ "${MODE}" = "shell" ]; then
    SOCKETS=("${WORK_DIR}/shell.sock" "/tmp/qemu.${IID}.S1")
else
    SOCKETS=("${WORK_DIR}/console.sock" "/tmp/qemu.${IID}.S1")
fi

SOCKET=""
for candidate in "${SOCKETS[@]}"; do
    if [ -S "${candidate}" ]; then
        SOCKET=${candidate}
        break
    fi
done

if [ -z "${SOCKET}" ]; then
    echo "Error: no running ${MODE} socket found for image ${IID}."
    echo "Looked for: ${SOCKETS[*]}"
    echo "Start the emulation first, e.g. ./scripts/emulate.sh ${IID} --daemon"
    exit 1
fi

echo "Connecting to ${MODE} socket ${SOCKET} ... (Ctrl-] to leave netcat)"

if command -v socat >/dev/null 2>&1; then
    # CRLF handling makes BusyBox shells behave better than raw netcat.
    exec socat - "UNIX-CONNECT:${SOCKET}"
elif command -v nc >/dev/null 2>&1; then
    exec nc -U "${SOCKET}"
else
    echo "Error: neither 'socat' nor 'nc' is installed." >&2
    exit 1
fi
