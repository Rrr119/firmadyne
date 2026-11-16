#!/usr/bin/env python3
"""Unit tests for the QEMU command/network generation in makeNetwork.py."""

import importlib.util
import os
import unittest

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = importlib.util.spec_from_file_location(
    "makeNetwork", os.path.join(REPO_DIR, "scripts", "makeNetwork.py"))
makeNetwork = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(makeNetwork)


class ArchEndTests(unittest.TestCase):
    def test_arch_end_splits_suffix(self):
        self.assertEqual(makeNetwork.archEnd("arm64el"), ("arm64", "el"))
        self.assertEqual(makeNetwork.archEnd("mips64eb"), ("mips64", "eb"))
        self.assertEqual(makeNetwork.archEnd("intel64el"), ("intel64", "el"))


class VirtioTests(unittest.TestCase):
    def test_virtio_only_for_arm_family(self):
        self.assertTrue(makeNetwork.useVirtio("arm"))
        self.assertTrue(makeNetwork.useVirtio("arm64"))
        for arch in ("mips", "mips64", "intel", "intel64"):
            self.assertFalse(makeNetwork.useVirtio(arch))


class NetworkConfigTests(unittest.TestCase):
    def test_arm64_placeholder_uses_virtio(self):
        line = makeNetwork.qemuArchNetworkConfig(2, "arm64", None)
        self.assertIn("virtio-net-device", line)
        self.assertIn("listen=:2002", line)
        self.assertNotIn("e1000", line)

    def test_mips64_placeholder_uses_e1000(self):
        line = makeNetwork.qemuArchNetworkConfig(1, "mips64", None)
        self.assertIn("e1000", line)
        self.assertIn("listen=:2001", line)

    def test_x86_tap_uses_e1000_and_mac(self):
        line = makeNetwork.qemuArchNetworkConfig(
            0, "intel64", ("192.168.1.1", "eth0", None, "aa:bb:cc:dd:ee:ff"))
        self.assertIn("e1000", line)
        self.assertIn("tap", line)
        self.assertIn("mac=aa:bb:cc:dd:ee:ff", line)

    def test_arm64_tap_uses_virtio(self):
        line = makeNetwork.qemuArchNetworkConfig(
            0, "arm64", ("192.168.1.1", "eth0", None, None))
        self.assertIn("virtio-net-device", line)
        self.assertIn("tap", line)


class QemuCmdTests(unittest.TestCase):
    NETWORK = [("192.168.0.1", "eth0", None, None)]

    def _generate(self, arch, endianness):
        return makeNetwork.qemuCmd(7, self.NETWORK, arch, endianness)

    def test_arm64_sets_cpu_console_and_virtio(self):
        out = self._generate("arm64", "el")
        self.assertIn("-cpu ${QEMU_CPU}", out)
        self.assertIn("console=${QEMU_CONSOLE}", out)
        self.assertIn("virtio-blk-device", out)
        self.assertIn("user_debug=31", out)
        self.assertIn("QEMU_AUDIO_DRV=none", out)

    def test_arm32_has_no_cpu_arg(self):
        out = self._generate("arm", "el")
        self.assertNotIn("-cpu", out)

    def test_mips64_uses_ide_and_e1000(self):
        for endianness in ("eb", "el"):
            out = self._generate("mips64", endianness)
            self.assertIn("if=ide", out)
            self.assertIn("e1000", out)
            self.assertNotIn("-cpu", out)
            self.assertNotIn("user_debug", out)

    def test_x86_uses_ide_and_e1000(self):
        out = self._generate("intel64", "el")
        self.assertIn("if=ide", out)
        self.assertIn("e1000", out)

    def test_x86_rejects_big_endian(self):
        with self.assertRaises(Exception):
            self._generate("intel", "eb")

    def test_arm_big_endian_rejected(self):
        with self.assertRaises(Exception):
            self._generate("arm", "eb")

    def test_unknown_architecture_rejected(self):
        with self.assertRaises(Exception):
            self._generate("ppc", "eb")

    def test_generated_script_is_shell(self):
        out = self._generate("arm64", "el")
        self.assertTrue(out.startswith("#!/bin/bash"))
        self.assertIn("ARCHEND=arm64el", out)
        self.assertIn("IID=7", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
