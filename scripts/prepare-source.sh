#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
template="${repo_root}/srcpkgs/velotype/template"

version="$(sed -n 's/^version=//p' "$template")"
commit="$(sed -n 's/^_commit=//p' "$template")"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	printf 'Invalid package version in %s\n' "$template" >&2
	exit 1
}
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
	printf 'Expected a full 40-character upstream commit SHA in %s\n' "$template" >&2
	exit 1
}

archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT

url="https://github.com/manyougz/velotype/archive/${commit}.tar.gz"
printf 'Downloading pinned Velotype source (version %s): %s\n' "$version" "$commit"
curl --fail --location --retry 5 --retry-all-errors \
	--connect-timeout 30 --max-time 300 \
	--output "$archive" "$url"

sha256="$(sha256sum "$archive" | awk '{print $1}')"
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || {
	printf 'Failed to calculate a valid source SHA-256\n' >&2
	exit 1
}

sed -i "s/^checksum=.*/checksum=${sha256}/" "$template"
bash -n "$template"
printf 'Updated %s with source checksum %s\n' "$template" "$sha256"
