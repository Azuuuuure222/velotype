#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
template="${repo_root}/srcpkgs/velotype/template"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fake_bin="${tmp}/bin"
cargo_home="${tmp}/cargo"
wrksrc="${tmp}/work"
mkdir -p "$fake_bin" "$cargo_home/registry/src/test-index/xattr-0.2.3/src/sys" "$wrksrc" "${tmp}/destdir/usr"

cat > "${fake_bin}/cargo" <<'STUB'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
	fetch:*) exit 0 ;;
	auditable:build) exit 71 ;;
	auditable:install) exit 72 ;;
	*) exit 0 ;;
esac
STUB
chmod +x "${fake_bin}/cargo"

xattr_file="${cargo_home}/registry/src/test-index/xattr-0.2.3/src/sys/mod.rs"
cat > "$xattr_file" <<'RUST'
pub const ENOATTR: ::libc::c_int = ::libc::ENOATTR;
RUST
cp "$xattr_file" "${tmp}/expected-mod.rs"

export PATH="${fake_bin}:${PATH}"
export CARGO_HOME="$cargo_home"
export XBPS_TARGET_MACHINE=x86_64-musl
export XBPS_TARGET_LIBC=musl
export RUST_TARGET=x86_64-unknown-linux-musl
export CFLAGS=
export CXXFLAGS=
export RUSTFLAGS=
export CARGO_BUILD_JOBS=2
export DESTDIR="${tmp}/destdir"
export configure_args=
export make_build_args=
export make_install_args=
# The template expects this path to be available as a shell variable.
source "$template"
# Sourcing the template sets wrksrc; point it at the isolated test workspace.
wrksrc="$tmp/work"

assert_original_source() {
	if ! cmp -s "$xattr_file" "${tmp}/expected-mod.rs"; then
		echo "xattr source was not restored after a Cargo phase" >&2
		diff -u "${tmp}/expected-mod.rs" "$xattr_file" >&2 || true
		exit 1
	fi
}

# Exercise a clean patch/restore cycle, as used by a successful phase.
_velotype_apply_xattr_patch
grep -Fq '::libc::ENODATA' "$xattr_file"
if grep -Fq '::libc::ENOATTR' "$xattr_file"; then
	echo "ENOATTR remained after applying the musl compatibility patch" >&2
	exit 1
fi
_velotype_restore_xattr_patch
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

# Exercise failure cleanup for both Cargo phases. The stub returns distinct
# errors instead of compiling, so this regression test is fast and offline.
if do_build; then
	echo "expected the mocked Cargo build to fail" >&2
	exit 1
else
	status=$?
	[[ "$status" -eq 71 ]] || { echo "unexpected build status: $status" >&2; exit 1; }
fi
assert_original_source

if do_install; then
	echo "expected the mocked Cargo install to fail" >&2
	exit 1
else
	status=$?
	[[ "$status" -eq 72 ]] || { echo "unexpected install status: $status" >&2; exit 1; }
fi
assert_original_source

echo "xattr musl patch lifecycle tests passed"
