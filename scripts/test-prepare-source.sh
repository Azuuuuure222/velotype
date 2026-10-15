#!/usr/bin/env bash
set -euo pipefail

# Test the source helper with isolated files and a mocked network client.
# No real upstream downloads or repository-tree modifications are performed.
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fixture_repo="${tmp}/repo"
fake_bin="${tmp}/bin"
cache="${tmp}/cache"
curl_log="${tmp}/curl.log"
good_archive="${tmp}/good.tar.gz"
bad_archive="${tmp}/bad.tar.gz"
commit="0123456789abcdef0123456789abcdef01234567"
mkdir -p "${fixture_repo}/scripts" "${fixture_repo}/srcpkgs/velotype" "$fake_bin" "$cache"
cp "${repo_root}/scripts/prepare-source.sh" "${fixture_repo}/scripts/prepare-source.sh"

printf 'pinned test source archive\n' > "$good_archive"
printf 'corrupt test archive\n' > "$bad_archive"
checksum="$(sha256sum "$good_archive" | awk '{print $1}')"
cat > "${fixture_repo}/srcpkgs/velotype/template" <<EOF
version=0.1.0
_commit=${commit}
checksum=${checksum}
EOF

cat > "${fake_bin}/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
	case "$1" in
		--output)
			[[ $# -ge 2 ]] || exit 64
			output="$2"
			shift 2
			;;
		*)
			shift
			;;
	esac
done
[[ -n "$output" ]] || { echo "mock curl: --output was not provided" >&2; exit 64; }
printf 'download\n' >> "${CURL_LOG:?}"
cp -- "${CURL_FIXTURE:?}" "$output"
CURL
chmod +x "${fake_bin}/curl"
export PATH="${fake_bin}:$PATH"
export CURL_LOG="$curl_log"
archive="${cache}/${commit}.tar.gz"
: > "$curl_log"

# A valid cached archive should be verified and reused without networking.
cp "$good_archive" "$archive"
CURL_FIXTURE="$good_archive" "${fixture_repo}/scripts/prepare-source.sh" "$cache"
[[ ! -s "$curl_log" ]] || { echo "valid source cache unexpectedly downloaded again" >&2; exit 1; }

# A corrupt cached archive must be discarded and replaced only after checksum
# verification of the downloaded copy succeeds.
printf 'stale cache contents\n' > "$archive"
CURL_FIXTURE="$good_archive" "${fixture_repo}/scripts/prepare-source.sh" "$cache"
cmp -s "$good_archive" "$archive" || { echo "verified download was not installed in the cache" >&2; exit 1; }
[[ "$(wc -l < "$curl_log")" -eq 1 ]] || { echo "expected exactly one download after cache corruption" >&2; exit 1; }

# A bad download must fail closed and must not leave a cache entry behind.
printf 'stale cache contents\n' > "$archive"
if CURL_FIXTURE="$bad_archive" "${fixture_repo}/scripts/prepare-source.sh" "$cache" >"${tmp}/bad-download.log" 2>&1; then
	echo "source helper accepted a download with the wrong SHA-256" >&2
	exit 1
fi
grep -Fq 'Source SHA-256 mismatch' "${tmp}/bad-download.log" || {
	echo "checksum failure did not produce the expected diagnostic" >&2
	cat "${tmp}/bad-download.log" >&2
	exit 1
}
[[ ! -e "$archive" ]] || { echo "checksum-failed archive was left in the cache" >&2; exit 1; }
[[ "$(wc -l < "$curl_log")" -eq 2 ]] || { echo "unexpected download count after checksum failure" >&2; exit 1; }

# The no-cache mode must still verify the downloaded bytes.
CURL_FIXTURE="$good_archive" "${fixture_repo}/scripts/prepare-source.sh"
[[ "$(wc -l < "$curl_log")" -eq 3 ]] || { echo "no-cache mode did not download exactly once" >&2; exit 1; }

echo "source preparation checksum/cache tests passed"
