#!/usr/bin/env bash
set -euo pipefail

# Keep regression failures actionable in CI, especially for strict assertions.
trap 'status=$?; printf "test-xattr-patch.sh: failure at line %s: %s (exit %s)\\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
template="${repo_root}/srcpkgs/velotype/template"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fake_bin="${tmp}/bin"
cargo_home="${tmp}/cargo"
wrksrc="${tmp}/work"
mkdir -p "$fake_bin" "$cargo_home/registry/src/test-index/xattr-0.2.3/src/sys" "$cargo_home/registry/src/test-index/gpui-0.2.2" "$cargo_home/registry/cache/test-index" "$wrksrc" "${tmp}/destdir/usr"

cat > "$wrksrc/Cargo.toml" <<'TOML'
[dependencies]
gpui = { version = "0.2", features = ["runtime_shaders"] }
TOML
cat > "$wrksrc/Cargo.lock" <<'LOCK'
[[package]]
name = "gpui"
version = "0.2.2"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
LOCK

gpui_manifest="$cargo_home/registry/src/test-index/gpui-0.2.2/Cargo.toml"
cat > "$gpui_manifest" <<'TOML'
[package]
name = "gpui"
version = "0.2.2"

[target.'cfg(any(target_os = "linux", target_os = "freebsd"))'.dependencies.xkbcommon]
version = "0.8.0"
features = [
    "wayland",
    "x11",
]
optional = true
TOML
cp "$gpui_manifest" "${tmp}/expected-gpui-Cargo.toml"

cat > "${fake_bin}/cargo" <<'STUB'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
	fetch:*) [ "${CARGO_TEST_MODE:-failure}" = fetch-failure ] && exit 73; exit 0 ;;
	update:*)
		lock_file="${CARGO_TEST_LOCK:?}"
		tmp_lock="${lock_file}.fake-update"
		awk '
			/^\[\[package\]\]/ { in_gpui=0 }
			/^name = "gpui"$/ { in_gpui=1 }
			in_gpui && /^(source|checksum) = / { next }
			{ print }
		' "$lock_file" > "$tmp_lock"
		mv -f "$tmp_lock" "$lock_file"
		;;
	tree:*) cat "$CARGO_TEST_TREE"; exit 0 ;;
	auditable:build|auditable:install)
		case "${CFLAGS:-}" in *-march=skylake*) ;; *) exit 99 ;; esac
		case "${CXXFLAGS:-}" in *-march=skylake*) ;; *) exit 99 ;; esac
		case "${RUSTFLAGS:-}" in *target-cpu=skylake*) ;; *) exit 99 ;; esac
		[ "${CARGO_BUILD_JOBS:-}" = 2 ] || exit 99
		[ "${CARGO_TEST_MODE:-failure}" = success ] && exit 0
		[ "$2" = build ] && exit 71
		exit 72
		;;
	*) exit 0 ;;
esac
STUB
chmod +x "${fake_bin}/cargo"

xattr_file="${cargo_home}/registry/src/test-index/xattr-0.2.3/src/sys/mod.rs"
cat > "$xattr_file" <<'RUST'
pub const ENOATTR: ::libc::c_int = ::libc::ENOATTR;
RUST
cp "$xattr_file" "${tmp}/expected-mod.rs"

# Fake the immutable Cargo crate archive used to recover a stale xattr cache.
archive_root="${tmp}/archive"
mkdir -p "$archive_root/xattr-0.2.3/src/sys"
cp "${tmp}/expected-mod.rs" "$archive_root/xattr-0.2.3/src/sys/mod.rs"
tar -czf "$cargo_home/registry/cache/test-index/xattr-0.2.3.crate" -C "$archive_root" xattr-0.2.3

cat > "${tmp}/cargo-tree.txt" <<'TREE'
gpui v0.2.2
├── gpui feature "font-kit"
├── gpui feature "runtime_shaders"
├── gpui feature "wayland"
├── xkbcommon feature "wayland"
└── wayland-cursor v0.31.14
    └── xcursor v0.3.1
TREE

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
export CARGO_TEST_TREE="${tmp}/cargo-tree.txt"
export CARGO_TEST_LOCK="${wrksrc}/Cargo.lock"
# The template expects this path to be available as a shell variable.
source "$template"
# Sourcing the template sets wrksrc; point it at the isolated test workspace.
wrksrc="$tmp/work"
local_gpui_manifest="$wrksrc/.cargo-patches/gpui/Cargo.toml"
post_patch
# post_patch is idempotent and should never re-enable GPUI defaults.
post_patch
grep -Fq 'default-features = false' "$wrksrc/Cargo.toml"
grep -Fq '"wayland"' "$wrksrc/Cargo.toml"
if grep -Fq 'gpui = { version = "0.2", features = ["runtime_shaders"] }' "$wrksrc/Cargo.toml"; then
	echo "GPUI default features were not disabled" >&2
	exit 1
fi

assert_original_source() {
	if ! cmp -s "$xattr_file" "${tmp}/expected-mod.rs"; then
		echo "xattr source was not restored after a Cargo phase" >&2
		diff -u "${tmp}/expected-mod.rs" "$xattr_file" >&2 || true
		exit 1
	fi
	if ! cmp -s "$gpui_manifest" "${tmp}/expected-gpui-Cargo.toml"; then
		echo "GPUI registry manifest was not restored after a Cargo phase" >&2
		diff -u "${tmp}/expected-gpui-Cargo.toml" "$gpui_manifest" >&2 || true
		exit 1
	fi
}

# A failed Cargo fetch must be propagated rather than hidden by later checks.
mv "$cargo_home/registry/src/test-index/xattr-0.2.3" "${tmp}/xattr-0.2.3"
export CARGO_TEST_MODE=fetch-failure
if _velotype_apply_xattr_patch; then
	echo "expected the mocked Cargo fetch to fail" >&2
	exit 1
else
	status=$?
	[[ "$status" -eq 73 ]] || { echo "unexpected fetch status: $status" >&2; exit 1; }
fi
mv "${tmp}/xattr-0.2.3" "$cargo_home/registry/src/test-index/xattr-0.2.3"
export CARGO_TEST_MODE=failure

# Exercise a clean patch/restore cycle, as used by a successful phase.
_velotype_apply_xattr_patch
grep -Fq '::libc::ENODATA' "$xattr_file"
[[ "$(_velotype_gpui_x11_count "$gpui_manifest")" -eq 1 ]]
[[ "$(_velotype_gpui_x11_count "$local_gpui_manifest")" -eq 0 ]]
[[ "$(_velotype_gpui_wayland_count "$local_gpui_manifest")" -ge 1 ]]
[[ "$(_velotype_gpui_default_false_count "$local_gpui_manifest")" -eq 1 ]]
grep -Fxq 'gpui = { path = ".cargo-patches/gpui" }' "$wrksrc/Cargo.toml"
if awk '/^\[\[package\]\]/ { in_gpui=0 } /^name = "gpui"$/ { in_gpui=1 } in_gpui && /^(source|checksum) = / { found=1 } END { exit !found }' "$wrksrc/Cargo.lock"; then
	echo "GPUI lock entry retained registry source/checksum after path override" >&2
	exit 1
fi
if grep -Fq '::libc::ENOATTR' "$xattr_file"; then
	echo "ENOATTR remained after applying the musl compatibility patch" >&2
	exit 1
fi

# Prove the resolved-feature assertion rejects a graph that re-enables X11.
cat > "${tmp}/cargo-tree-with-x11.txt" <<'TREE'
gpui v0.2.2
├── gpui feature "wayland"
├── gpui feature "x11"
└── xkbcommon feature "x11"
TREE
export CARGO_TEST_TREE="${tmp}/cargo-tree-with-x11.txt"
if _velotype_assert_wayland_only >/dev/null 2>&1; then
	echo "Wayland-only assertion accepted an X11-enabled feature graph" >&2
	exit 1
fi
export CARGO_TEST_TREE="${tmp}/cargo-tree.txt"

_velotype_restore_xattr_patch
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

# Simulate an interrupted run leaving xattr patched but the local GPUI
# override intact. The registry copy of GPUI must remain pristine.
sed -i 's/::libc::ENOATTR/::libc::ENODATA/' "$xattr_file"
_velotype_apply_xattr_patch
[[ "$(_velotype_gpui_x11_count "$gpui_manifest")" -eq 1 ]]
[[ "$(_velotype_gpui_x11_count "$local_gpui_manifest")" -eq 0 ]]
grep -Fq '::libc::ENODATA' "$xattr_file"
_velotype_restore_xattr_patch
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

# Exercise both success and failure cleanup without compiling the application.
export CARGO_TEST_MODE=success
if ! do_build; then
	echo "mocked Cargo build unexpectedly failed" >&2
	exit 1
fi
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

if ! do_install; then
	echo "mocked Cargo install unexpectedly failed" >&2
	exit 1
fi
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

export CARGO_TEST_MODE=failure
if do_build; then
	echo "expected the mocked Cargo build to fail" >&2
	exit 1
else
	status=$?
	[[ "$status" -eq 71 ]] || { echo "unexpected build status: $status" >&2; exit 1; }
fi
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

if do_install; then
	echo "expected the mocked Cargo install to fail" >&2
	exit 1
else
	status=$?
	[[ "$status" -eq 72 ]] || { echo "unexpected install status: $status" >&2; exit 1; }
fi
trap 'rm -rf -- "$tmp"' EXIT
assert_original_source

echo "xattr musl patch lifecycle tests passed"
