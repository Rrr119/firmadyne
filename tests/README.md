# Tests

Self-contained tests for the multi-architecture emulation support. They run
without QEMU, PostgreSQL, root, or a real firmware image, so they are suitable
for CI or a quick local sanity check.

Run everything:

```sh
./tests/run_tests.sh
```

## Coverage

* `test_getArch.sh` — feeds representative `file(1)` output strings through
  the detection helpers in `scripts/getArch.sh` and checks the resulting
  `<arch><endian>` identifier. This covers the AArch64 ordering fix
  (`ARM aarch64` must not be classified as 32-bit ARM), fixed-endian
  architectures, and PowerPC recognition.
* `test_kernel_version.sh` — checks best-effort kernel-version extraction
  from `file(1)` output.
* `test_config.sh` — verifies that every supported architecture has a
  complete set of `get_*` mappings in `firmadyne.config`
  (kernel, QEMU binary, CPU model, machine, disk, NIC, console) and that
  unsupported architectures are rejected.
* `test_makeNetwork.py` — unit tests for `scripts/makeNetwork.py`: virtio vs.
  e1000 NIC selection, IDE vs. virtio disk selection, the aarch64 CPU/console
  arguments, endianness validation, and the generated QEMU launch script.
