# velotype-musl

Void Linux `x86_64-musl` package for [Velotype](https://github.com/manyougz/velotype), a native Markdown editor built with Rust and GPUI.

The package is built from source through `xbps-src`; it does not use upstream Linux binaries that may be linked against glibc. The template pins upstream commit `a61c71955c6104fc5d647088b5957da6d59149ca` (Velotype `0.7.5`).

## Build locally

Run this on a machine with network access and the usual Void package-build prerequisites. This repository includes a preparation script to calculate the SHA-256 checksum for GitHub's generated source archive.

```sh
git clone https://github.com/Azuuuuure222/velotype-musl.git
cd velotype-musl
./scripts/prepare-source.sh

cd ..
git clone https://github.com/void-linux/void-packages.git
cp -a velotype-musl/srcpkgs/velotype void-packages/srcpkgs/

cd void-packages
./xbps-src -A x86_64-musl binary-bootstrap
./xbps-src -A x86_64-musl pkg velotype
```

The result is written under `void-packages/hostdir/binpkgs/`. Install it from that local repository with `xbps-install --repository=hostdir/binpkgs velotype`.

The source archive is pinned to a full upstream commit. `scripts/prepare-source.sh` downloads that exact archive, calculates its SHA-256, and writes the digest into `srcpkgs/velotype/template`. It starts with a placeholder because GitHub does not publish a checksum for its generated source archive. Review and commit the generated digest when updating the source pin.

## CI

GitHub Actions performs the `x86_64-musl` build using `xbps-src` and uploads the resulting `.xbps` package as a workflow artifact. A successful template check alone is not considered a successful build; the package job must finish successfully.

## Updating Velotype

Update both `version` and `_commit` in `srcpkgs/velotype/template` to a known upstream commit, then run `./scripts/prepare-source.sh`. Review the diff and rebuild before committing the update to `main`.
