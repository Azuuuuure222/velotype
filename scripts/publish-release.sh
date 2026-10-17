#!/usr/bin/env bash
set -euo pipefail
version="${VERSION:?VERSION is required}"
revision="${REVISION:?REVISION is required}"
upstream_commit="${UPSTREAM_COMMIT:?UPSTREAM_COMMIT is required}"
release_commit="${RELEASE_COMMIT:?RELEASE_COMMIT is required}"
dist_dir="${1:-dist}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid package version: $version" >&2; exit 1; }
[[ "$revision" =~ ^[0-9]+$ ]] || { echo "Invalid package revision: $revision" >&2; exit 1; }
[[ "$upstream_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid upstream commit SHA: $upstream_commit" >&2; exit 1; }
[[ "$release_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid packaging commit SHA: $release_commit" >&2; exit 1; }
[[ -d "$dist_dir" ]] || { echo "Missing distribution directory: $dist_dir" >&2; exit 1; }

shopt -s nullglob
packages=("$dist_dir"/*.xbps)
if [[ "${#packages[@]}" -ne 1 ]]; then
  printf 'Expected exactly one .xbps asset, found %s\n' "${#packages[@]}" >&2
  exit 1
fi
package_path="${packages[0]}"
package_name="$(basename "$package_path")"
expected_name="velotype-${version}_${revision}.x86_64-musl.xbps"
[[ "$package_name" == "$expected_name" ]] || {
  echo "Unexpected package name: $package_name (expected $expected_name)" >&2
  exit 1
}

release_tag="$version"
revision_number=$((10#$revision))
package_prefix="velotype-${version}_"
notes_file="$dist_dir/RELEASE_NOTES.md"
cat > "$notes_file" <<EOF
Automated Void Linux package release for Velotype ${version} (XBPS revision ${revision}).

- **Tag:** ${release_tag}
- **Package asset:** ${package_name}
- **Target:** x86_64-musl
- **CPU target:** Intel Skylake, including the Core i3-6100U; not intended for pre-Skylake CPUs.
- **Rust optimization:** release opt-level 3, full LTO, one codegen unit; panic=abort and symbol stripping retained.
- **Upstream source commit:** ${upstream_commit}
- **Packaging commit:** ${release_commit}

This is a standalone XBPS package, not a signed, indexed XBPS repository. The release contains the package asset only.
EOF

if gh release view "$release_tag" --json tagName >/dev/null 2>&1; then
  mapfile -t existing_assets < <(gh release view "$release_tag" --json assets --jq '.assets[].name')
  existing_package_assets=()
  current_asset_present=false
  max_revision=0
  for asset in "${existing_assets[@]}"; do
    case "$asset" in
      "${package_prefix}"*.x86_64-musl.xbps)
        asset_revision="${asset#"$package_prefix"}"
        asset_revision="${asset_revision%.x86_64-musl.xbps}"
        if [[ "$asset_revision" =~ ^[0-9]+$ ]]; then
          existing_package_assets+=("$asset")
          asset_revision_number=$((10#$asset_revision))
          if (( asset_revision_number > max_revision )); then max_revision="$asset_revision_number"; fi
          [[ "$asset" == "$package_name" ]] && current_asset_present=true
        fi
        ;;
    esac
  done
  if (( max_revision > revision_number )); then
    echo "Refusing revision downgrade: release has revision $max_revision, requested $revision_number." >&2
    exit 1
  fi

  if [[ "$current_asset_present" == true ]]; then
    existing_dir="$dist_dir/existing"
    rm -rf -- "$existing_dir"
    mkdir -p "$existing_dir"
    if ! gh release download "$release_tag" --pattern "$package_name" --dir "$existing_dir"; then
      echo "Could not download the existing package for verification; refusing to mutate the release." >&2
      exit 1
    fi
    if [[ ! -s "$existing_dir/$package_name" ]] || ! cmp -s "$package_path" "$existing_dir/$package_name"; then
      echo "Package bytes changed without a version/revision change; increment revision." >&2
      exit 1
    fi
  else
    if (( max_revision > 0 && revision_number <= max_revision )); then
      echo "Refusing to replace a release with a non-increasing XBPS revision." >&2
      exit 1
    fi
    # Upload first so failure does not remove the currently downloadable package.
    gh release upload "$release_tag" "$package_path"
  fi

  # Remove older package revisions and legacy sidecars, keeping only this .xbps file.
  for asset in "${existing_assets[@]}"; do
    case "$asset" in
      SHA256SUMS|SHA512SUMS|BUILD-INFO.txt)
        gh release delete-asset "$release_tag" "$asset" --yes
        ;;
      "${package_prefix}"*.x86_64-musl.xbps)
        if [[ "$asset" != "$package_name" ]]; then
          gh release delete-asset "$release_tag" "$asset" --yes
        fi
        ;;
    esac
  done
  gh release edit "$release_tag" --title "$version" --notes-file "$notes_file" --draft=false --latest
else
  gh release create "$release_tag" "$package_path" \
    --title "$version" \
    --notes-file "$notes_file" \
    --target "$release_commit" \
    --latest
fi

release_draft="$(gh release view "$release_tag" --json isDraft --jq .isDraft)"
[[ "$release_draft" == false ]] || { echo "Release $release_tag still appears to be a draft." >&2; exit 1; }
release_url="$(gh release view "$release_tag" --json url --jq .url)"
mapfile -t published_assets < <(gh release view "$release_tag" --json assets --jq '.assets[].name')
printf '%s\n' "${published_assets[@]}" | grep -Fxq "$package_name" || {
  echo "Published release is missing the package asset $package_name." >&2
  exit 1
}
for asset in "${published_assets[@]}"; do
  case "$asset" in
    SHA256SUMS|SHA512SUMS|BUILD-INFO.txt)
      echo "Unexpected metadata asset remains in release: $asset" >&2
      exit 1
      ;;
    "${package_prefix}"*.x86_64-musl.xbps)
      [[ "$asset" == "$package_name" ]] || {
        echo "Unexpected stale package asset remains in release: $asset" >&2
        exit 1
      }
      ;;
  esac
done
{
  echo "## Velotype release published"
  echo
  echo "- Release: [$release_tag]($release_url)"
  echo "- Package: $package_name"
  echo "- Target: x86_64-musl / Intel Skylake"
  echo "- Release assets: package only"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
