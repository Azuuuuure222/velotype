# velotype-musl

Void Linux `x86_64-musl` package for [Velotype](https://github.com/manyougz/velotype), a native Rust/GPUI Markdown editor.

This package pins Velotype `0.7.5` to upstream commit `a61c71955c6104fc5d647088b5957da6d59149ca`, and verifies the committed SHA-256 before building.

## Target hardware

The binary is optimized specifically for the Intel Core i3-6100U (Skylake): C/C++ components use `-O2 -march=skylake`, and Rust uses `-C target-cpu=skylake`. It is not intended for pre-Skylake x86_64 CPUs. Cargo builds default to two parallel jobs to limit build-time memory pressure.

## Wayland-only build

The package explicitly disables GPUI's default features and enables its Wayland backend; X11 headers and client development libraries are not package dependencies. GPUI 0.2.2 also enables `xkbcommon/x11` explicitly and leaves `xkbcommon` default features enabled, which can reintroduce X11 even with GPUI's own X11 backend disabled. The package build removes the explicit X11 feature and disables `xkbcommon` defaults while preserving Wayland. It checks the normal/build Cargo feature graph for Wayland and rejects X11 features/crates, then checks the executable's direct ELF dependencies for X11 libraries.

Vulkan, Mesa, Wayland, xkbcommon, fontconfig and freetype dependencies are retained because GPUI still needs the renderer, display protocol, keyboard handling and font/text stack. The build remains tuned for Skylake and limits Cargo concurrency to two jobs to reduce memory pressure.

## Latest release

After a successful package build from `main`, Actions creates a package-versioned GitHub Release or verifies that an existing release contains identical package bytes before marking it **Latest**. Each release includes the native `.xbps` package, `SHA256SUMS`, `SHA512SUMS`, and `BUILD-INFO.txt`.

Download assets from the [latest release](https://github.com/Azuuuuure222/velotype-musl/releases/latest), then verify them from the directory containing the downloaded files:

```sh
sha256sum -c SHA256SUMS
sha512sum -c SHA512SUMS
```

These are standalone package releases, not a signed, indexed XBPS repository. The package targets `x86_64-musl` and is optimized for Intel Skylake; it is not suitable for older x86_64 CPUs.
Release tags include the package version and XBPS revision. If a build with the same version/revision produces different package bytes, the release job fails rather than replacing a published package silently; increment `revision` in `srcpkgs/velotype/template` when changing the packaged output.

## Build locally

```sh
git clone https://github.com/Azuuuuure222/velotype-musl.git
git clone https://github.com/void-linux/void-packages.git
cd velotype-musl

./scripts/prepare-source.sh ../void-packages/hostdir/sources/velotype-0.7.5
mkdir -p ../void-packages/srcpkgs/velotype
cp -a srcpkgs/velotype/. ../void-packages/srcpkgs/velotype/

cd ../void-packages
./xbps-src -A x86_64-musl binary-bootstrap
./xbps-src -A x86_64-musl pkg velotype
```

The generated package is placed under `void-packages/hostdir/binpkgs/`.

## musl compatibility

Upstream's transitive `xattr 0.2.3` references `libc::ENOATTR`, which is unavailable on musl Linux. The build phase applies a narrow, context-checked `ENOATTR` → `ENODATA` substitution while `cargo auditable build` runs, then restores the cached source on success or failure. The install phase copies the already-built auditable release executable instead of running `cargo install` and recompiling the full Rust dependency graph; this avoids a second expensive release/LTO compile and reduces build time, memory pressure, and disk I/O. If an interrupted build left the shared registry patched, the build recovers the pristine file from Cargo's cached crate archive before applying the patch. The workflow runs `scripts/test-xattr-patch.sh` before the full build, covering patch restoration, feature checks, build failures, and binary-install behavior without compiling the application.

## CI and reproducibility

GitHub Actions builds the actual `.xbps` package through `xbps-src` and uploads it as a workflow artifact. CI caches the pinned source archive, Cargo registry and Void binary packages. The source cache key includes both the upstream commit and its expected SHA-256; source archives are validated against that checksum on every run, and the checksum is never silently regenerated. The workflow checks shell syntax and the musl patch lifecycle before bootstrapping Void and compiling the application.

When updating Velotype, review the upstream source commit and archive checksum, then build with `./xbps-src -A x86_64-musl pkg velotype` before merging.
