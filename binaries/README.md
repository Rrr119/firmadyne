Binary files used by the FIRMADYNE framework should be placed here. These include:

* console
   * `console.armel`
   * `console.arm64el`
   * `console.mipseb`
   * `console.mipsel`
   * `console.mips64eb`
   * `console.mips64el`
   * `console.intelel`
   * `console.intel64el`

* libnvram
   * `libnvram.so.armel`
   * `libnvram.so.arm64el`
   * `libnvram.so.mipseb`
   * `libnvram.so.mipsel`
   * `libnvram.so.mips64eb`
   * `libnvram.so.mips64el`
   * `libnvram.so.intelel`
   * `libnvram.so.intel64el`

* kernel
   * `zImage.armel`
   * `Image.arm64el`
   * `vmlinux.mipseb`
   * `vmlinux.mipsel`
   * `vmlinux.mips64eb`
   * `vmlinux.mips64el`
   * `bzImage.intelel`
   * `bzImage.intel64el`

The file name suffix matches the architecture identifiers used by
`scripts/getArch.sh` and the `ARCHS` array in `firmadyne.config`. Kernel image
names follow the conventional per-architecture build artifacts: `zImage`
(32-bit ARM), `Image` (AArch64), `vmlinux` (MIPS/MIPS64), and `bzImage`
(x86/x86-64). `download.sh` only fetches the pre-built `armel`, `mipseb`, and
`mipsel` artifacts; the additional architectures require building or supplying
the matching binaries yourself.
