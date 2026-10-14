# velotype-musl

Void Linux `x86_64-musl` package for [Velotype](https://github.com/manyougz/velotype), a native Markdown editor built with Rust and GPUI.

The package builds from source through `xbps-src`; it does not reuse upstream Linux binaries. The template pins Velotype `0.7.5` to upstream commit `a61c71955c6104fc5d647088b5957da6d59149ca` and verifies a committed SHA-256 before using the source archive.

## Build locally

```sh
git clone https://github.com/Azuuuuure222/velotype-musl.git
git clone https://github.com/void-linux/void-packages.git
cd velotype-musl

# Verify the pinned source and cache it where xbps-src will find it.
./scripts/prepare-source.sh ../void-packages/hostdir/sources/velotype-0.7.5
cp -a srcpkgs/velotype ../void-packages/srcpkgs/

cd ../void-packages
./xbps-src -A x86_64-musl binary-bootstrap
./xbps-src -A x86_64-musl pkg velotype
```

The package is written under `void-packages/hostdir/binpkgs/`. Install it from that local repository with `xbps-install --repository=hostdir/binpkgs velotype`.

`scripts/prepare-source.sh` verifies the source archive against the committed SHA-256. It refuses a mismatched archive and can reuse a previously downloaded archive only after verifying the same digest. It never updates the expected checksum automatically.

## CI

GitHub Actions builds the package on `x86_64-musl` with `xbps-src` and uploads the generated `.xbps` package as a workflow artifact. It caches the verified upstream source and Void binary-package downloads to reduce repeated downloads. The package is not considered working until the build job succeeds.

## Updating Velotype

When updating upstream, set `version` and `_commit` in `srcpkgs/velotype/template` to the intended release/commit, then deliberately compute and review the source archive SHA-256. Update the committed checksum only after independently verifying that the archive is the intended source. Test the updated package with `xbps-src -A x86_64-musl pkg velotype`.
