# velotype-musl

Void Linux `x86_64-musl` package for [Velotype](https://github.com/manyougz/velotype), a native Rust/GPUI Markdown editor.

This package pins Velotype `0.7.5` to upstream commit `a61c71955c6104fc5d647088b5957da6d59149ca`, and verifies the committed SHA-256 before building.

## Target hardware

The binary is optimized specifically for the Intel Core i3-6100U (Skylake): C/C++ components use `-O2 -march=skylake`, and Rust uses `-C target-cpu=skylake`. It is not intended for pre-Skylake x86_64 CPUs. Cargo builds default to two parallel jobs to limit build-time memory pressure.

## Build locally

```sh
git clone https://github.com/Azuuuuure222/velotype-musl.git
git clone https://github.com/void-linux/void-packages.git
cd velotype-musl

./scripts/prepare-source.sh ../void-packages/hostdir/sources/velotype-0.7.5
cp -a srcpkgs/velotype ../void-packages/srcpkgs/

cd ../void-packages
./xbps-src -A x86_64-musl binary-bootstrap
./xbps-src -A x86_64-musl pkg velotype
```

The generated package is placed under `void-packages/hostdir/binpkgs/`.

## musl compatibility

Upstream's transitive `xattr 0.2.3` references `libc::ENOATTR`, which is unavailable on musl Linux. The package template patches this to `libc::ENODATA` only after Cargo fetches the pinned dependency, then restores the shared Cargo registry source on success or failure.

## CI and reproducibility

GitHub Actions builds the actual `.xbps` package through `xbps-src`, and uploads it as a workflow artifact. CI caches the pinned source archive, Cargo registry and Void binary packages. Source archives are always validated against the committed SHA-256; the expected checksum is never silently regenerated. The package cache is saved after the build attempt, including failures, so it retains the actual dependency downloads.

When updating Velotype, review the upstream source commit and archive checksum, then build with `./xbps-src -A x86_64-musl pkg velotype` before merging.
