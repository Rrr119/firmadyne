#!/usr/bin/env python3
"""Deterministic stand-in for qemu-system-* used by the acceptance tests.

It emulates just enough of the QEMU command-line surface that the generated
scratch/<IID>/run.sh and the new health/emulate tooling exercise:

* parses -chardev socket,...,path=... plus -serial/-monitor/-nographic,
* streams a scenario-driven boot transcript into the serial sink (a logfile
  chardev or stdio),
* optionally listens on a real TCP port so healthCheck.py's port probes have
  something to find,
* stays alive until killed, like a real emulation.

The scenario is selected with the FIRMADYNE_MOCK_SCENARIO environment
variable: success | kernel_panic | service_fail.
"""

import os
import re
import signal
import socket
import sys
import threading
import time


SCENARIOS = {
    "success": [
        (0.1, "Linux version 4.1.17 (firmadyne) test-mock\n"),
        (0.1, "[    0.100] VFS: Mounted root (ext2 filesystem) readonly.\n"),
        (0.2, "[    0.400] firmadyne: execve of /sbin/init recorded\n"),
        (0.2, "init started: BusyBox v1.24\n"),
        (0.3, "[    1.000] __inet_insert_ifa[br0]: device:br0 ifa:0x0100a8c0\n"),
        (0.2, "br0: link becomes ready, br0: UP\n"),
        (0.2, "httpd: starting web service\n"),
        (0.1, "login: \n"),
    ],
    "kernel_panic": [
        (0.1, "Linux version 2.6.32 (firmadyne) test-mock\n"),
        (0.2, "[    0.200] VFS: Cannot open root device \"sda1\" or unknown-block(8,1)\n"),
        (0.1, "[    0.210] Please append a correct \"root=\" boot option; here are the available partitions:\n"),
        (0.1, "[    0.220] Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(8,1)\n"),
    ],
    "service_fail": [
        (0.1, "Linux version 2.6.32 (firmadyne) test-mock\n"),
        (0.1, "[    0.100] VFS: Mounted root (ext2 filesystem) readonly.\n"),
        (0.2, "[    0.400] firmadyne: execve of /sbin/init recorded\n"),
        (0.2, "init started: BusyBox v1.19\n"),
        (0.3, "[    1.000] __inet_insert_ifa[br0]: device:br0 ifa:0x6400a8c0\n"),
        (0.2, "br0: link becomes ready, br0: UP\n"),
        (0.2, "httpd: Segmentation fault (core dumped)\n"),
        (0.1, "login: \n"),
    ],
}


def parse_chardev_paths(argv):
    """Return mapping chardev id -> (socket path, logfile path)."""
    devices = {}
    for index, token in enumerate(argv):
        if token == "-chardev" and index + 1 < len(argv):
            fields = argv[index + 1].split(",")
            dev_id = None
            sock_path = None
            logfile = None
            for field in fields:
                if field.startswith("id="):
                    dev_id = field[3:]
                elif field.startswith("path="):
                    sock_path = field[5:]
                elif field.startswith("logfile="):
                    logfile = field[8:]
            if dev_id:
                devices[dev_id] = (sock_path, logfile)
    return devices


def first_logfile(devices):
    for sock_path, logfile in devices.values():
        if logfile:
            return logfile
    return None


def serve_socket(sock_path):
    """Pretend to be a QEMU unix socket: accept and hold the connection."""
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    listener.bind(sock_path)
    listener.listen(1)

    def accept_loop():
        while True:
            try:
                conn, _ = listener.accept()
            except OSError:
                return
            # Real QEMU keeps the connection open for the VM lifetime.
            threading.Thread(target=lambda c: _hold(c), daemon=True).start()

    thread = threading.Thread(target=accept_loop, daemon=True)
    thread.start()


def _hold(conn):
    try:
        while True:
            data = conn.recv(64)
            if not data:
                break
    except OSError:
        pass
    finally:
        conn.close()


def start_tcp_service(port):
    """Open a real listening TCP port so healthCheck.py can connect."""
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(("127.0.0.1", port))
    except OSError as exc:
        sys.stderr.write("mock_qemu: cannot bind test port %d: %s\n" % (port, exc))
        return
    listener.listen(8)
    listener.settimeout(0.5)

    def serve():
        while True:
            try:
                conn, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            conn.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok")
            conn.close()

    threading.Thread(target=serve, daemon=True).start()


def main():
    scenario = os.environ.get("FIRMADYNE_MOCK_SCENARIO", "success")
    if scenario not in SCENARIOS:
        sys.stderr.write("unknown mock scenario: %s\n" % scenario)
        return 2

    argv = sys.argv[1:]
    devices = parse_chardev_paths(argv)
    for sock_path, _logfile in devices.values():
        if sock_path:
            serve_socket(sock_path)

    # service_fail deliberately opens nothing; success opens the requested
    # port.  The port number is passed via the environment by the test runner.
    if scenario == "success":
        port = int(os.environ.get("FIRMADYNE_MOCK_TCP_PORT", "18080"))
        start_tcp_service(port)

    nographic = "-nographic" in argv
    logfile = first_logfile(devices)

    def emit(line):
        if logfile:
            with open(logfile, "a", encoding="utf-8") as handle:
                handle.write(line)
        if nographic:
            # Line-buffered, like a real QEMU serial console, so `tee` in the
            # generated run.sh pipeline receives data promptly.
            print(line, end="", flush=True)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    for delay, line in SCENARIOS[scenario]:
        time.sleep(delay)
        emit(line)

    # Stay resident until killed, mirroring a running emulation.
    while True:
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
