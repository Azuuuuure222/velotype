#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
template="${repo_root}/srcpkgs/velotype/template"

version="$(sed -n 's/^version=//p' "$template")"
commit="$(sed -n 's/^_commit=//p' "$template")"
expected="$(sed -n 's/^checksum=//p' "$template")"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	printf 'Invalid package version in %s\n' "$template" >&2
	exit 1
}
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
	printf 'Expected a full 40-character upstream commit SHA in %s\n' "$template" >&2
	exit 1
}
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
	printf 'Expected a pinned 64-character SHA-256 in %s\n' "$template" >&2
	exit 1
}

source_name="${commit}.tar.gz"
source_dir="${1:-}"
source_file=""
if [[ -n "$source_dir" ]]; then
	mkdir -p "$source_dir"
	source_file="${source_dir%/}/${source_name}"
	if [[ -s "$source_file" ]]; then
		actual="$(sha256sum "$source_file" | awk '{print $1}')"
		if [[ "$actual" == "$expected" ]]; then
			printf 'Verified cached Velotype source: %s\n' "$source_file"
			exit 0
		fi
		printf 'Discarding cached source with incorrect SHA-256: %s\n' "$source_file" >&2
		rm -f -- "$source_file"
	fi
fi

archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
url="https://github.com/manyougz/velotype/archive/${commit}.tar.gz"

printf 'Downloading pinned Velotype source %s (%s)\n' "$version" "$commit"
curl --fail --location --retry 5 --retry-all-errors \
	--connect-timeout 30 --max-time 300 \
	--output "$archive" "$url"

actual="$(sha256sum "$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
	printf 'Source SHA-256 mismatch!\nExpected: %s\nActual:   %s\n' "$expected" "$actual" >&2
	exit 1
fi

if [[ -n "$source_file" ]]; then
	install -m 0644 "$archive" "$source_file"
	printf 'Verified and cached source archive: %s\n' "$source_file"
else
	printf 'Verified pinned source archive SHA-256: %s\n' "$actual"
fi
