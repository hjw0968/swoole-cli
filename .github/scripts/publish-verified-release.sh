#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
main_sha="$(gh api "repos/$repo/branches/main" --jq '.commit.sha')"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

verified_run() {
  local id="$1" data
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "::error::Invalid run ID: $id"; exit 1; }
  data="$(gh run view "$id" -R "$repo" --json headSha,status,conclusion,headBranch)"
  [[ "$(jq -r .status <<<"$data")" == "completed" ]] || { echo "::error::Run $id is not complete"; exit 1; }
  [[ "$(jq -r .conclusion <<<"$data")" == "success" ]] || { echo "::error::Run $id did not succeed"; exit 1; }
  jq -r .headSha <<<"$data"
}

find_run() {
  local workflow="$1" sha="$2"
  gh run list -R "$repo" -w "$workflow" -c "$sha" -L 100 \
    --json databaseId,status,conclusion,headSha \
    --jq '[.[] | select(.status == "completed" and .conclusion == "success")] | first | .databaseId // empty'
}

if [[ -n "${LINUX_RUN_ID:-}" || -n "${MACOS_RUN_ID:-}" ]]; then
  [[ -n "${LINUX_RUN_ID:-}" && -n "${MACOS_RUN_ID:-}" ]] || { echo "::error::Provide BOTH verified run IDs"; exit 1; }
  linux_id="$LINUX_RUN_ID"
  macos_id="$MACOS_RUN_ID"
  sha="$(verified_run "$linux_id")"
  [[ "$(verified_run "$macos_id")" == "$sha" ]] || { echo "::error::Builds have different commit IDs"; exit 1; }
  git fetch --quiet origin main
  main_sha="$(git rev-parse FETCH_HEAD)"
  git merge-base --is-ancestor "$sha" "$main_sha" || { echo "::error::Build commit is not on main"; exit 1; }
else
  [[ "${EVENT_NAME:-}" == "workflow_run" ]] || { echo "::error::Specify both run IDs for manual release"; exit 1; }
  sha="${EVENT_HEAD_SHA:?}"
  if [[ "$sha" != "$main_sha" ]]; then
    echo "Skip superseded commit $sha (main is $main_sha)"
    exit 0
  fi
  linux_id="$(find_run linux-x86_64.yml "$sha")"
  macos_id="$(find_run macos-aarch64.yml "$sha")"
  if [[ -z "$linux_id" || -z "$macos_id" ]]; then
    echo "Other platform is not successful yet; later workflow_run event will retry."
    exit 0
  fi
  [[ "$(verified_run "$linux_id")" == "$sha" && "$(verified_run "$macos_id")" == "$sha" ]]
fi

php_version="$(git show "$sha:sapi/PHP-VERSION.conf" | tr -d '[:space:]')"
swoole_version="$(git show "$sha:sapi/SWOOLE-VERSION.conf" | tr -d '[:space:]')"
swoole_version="${swoole_version#v}"
if [[ -n "${RELEASE_TAG:-}" ]]; then
  tag="$RELEASE_TAG"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-php[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$ ]] || { echo "::error::Invalid release tag"; exit 1; }
else
  tag="v${swoole_version}-php${php_version}-g${sha:0:7}"
fi

if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
  echo "Release $tag already exists; no duplicate publication."
  exit 0
fi

mkdir -p "$workdir/linux" "$workdir/macos" "$workdir/dist"
gh run download "$linux_id" -R "$repo" -n "swoole-cli-v${swoole_version}-linux-x64" -D "$workdir/linux"
gh run download "$macos_id" -R "$repo" -n "swoole-cli-v${swoole_version}-macos-arm64" -D "$workdir/macos"

[[ -s "$workdir/linux/swoole-cli" && -s "$workdir/macos/swoole-cli" ]] || { echo "::error::Missing production binaries"; exit 1; }
file "$workdir/linux/swoole-cli" | grep -q 'ELF 64-bit' || { echo "::error::Linux artifact not ELF"; exit 1; }
file "$workdir/macos/swoole-cli" | grep -q 'Mach-O 64-bit.*arm64' || { echo "::error::macOS artifact not Mach-O arm64"; exit 1; }

cat >"$workdir/BUILD-INFO.txt" <<EOF
Swoole CLI custom build
Git commit: $sha
PHP: $php_version (ZTS)
Swoole: $swoole_version
protobuf: 5.36.2
xlswriter: 3.0.0
Built and verified using GitHub Actions:
Linux: https://github.com/$repo/actions/runs/$linux_id
macOS: https://github.com/$repo/actions/runs/$macos_id
This archive contains an existing CI production binary; it was not recompiled for publication.
EOF

for platform in linux-x64 macos-arm64; do
  if [[ "$platform" == "linux-x64" ]]; then src="$workdir/linux"; else src="$workdir/macos"; fi
  cp "$workdir/BUILD-INFO.txt" "$src/BUILD-INFO.txt"
  tar -C "$src" -cJf "$workdir/dist/swoole-cli-v${swoole_version}-$platform.tar.xz" swoole-cli BUILD-INFO.txt
done
(cd "$workdir/dist" && sha256sum *.tar.xz > SHA256SUMS)

notes="$workdir/RELEASE-NOTES.md"
cat >"$notes" <<EOF
## Swoole CLI custom build — PHP $php_version / Swoole $swoole_version

| Component | Version |
| --- | --- |
| PHP | $php_version (ZTS) |
| Swoole | $swoole_version |
| protobuf | 5.36.2 |
| xlswriter | 3.0.0 |
| libssh2 / built-in Swoole SSH2 | 1.11.1 / enabled |

### What we changed
- Built both Linux x86_64 and macOS ARM64 with static protobuf and xlswriter.
- Preserved protobuf's static registration header and fixed \`arginfo_void\` collisions recursively in nested source files.
- Upgraded xlswriter to 3.0.0 and isolated its bundled minizip headers from PHP's libzip to prevent \`zip.h\` name collisions.
- Removed the obsolete macOS xlswriter 1.5.8 minizip-prototype patch.
- Kept Swoole 6's native SSH2, so no separate PECL ssh2 extension is needed.

### Validation
- [Linux CI run](https://github.com/$repo/actions/runs/$linux_id): passed, including required extension checks.
- [macOS CI run](https://github.com/$repo/actions/runs/$macos_id): passed, including required extension checks.
EOF
if [[ "$sha" == "90dde65e86479fd561a80a5f3d66606f94b27725" ]]; then
cat >>"$notes" <<'EOF'
- macOS 27 / Apple Silicon local verification: **5/5 PASS** (versions, protobuf binary/JSON round-trip, XLSX write/read with ZipArchive, Swoole coroutines, SSH2 function registration).
EOF
fi
cat >>"$notes" <<EOF

### Downloads
- \`swoole-cli-v${swoole_version}-macos-arm64.tar.xz\`
- \`swoole-cli-v${swoole_version}-linux-x64.tar.xz\`
- \`SHA256SUMS\` to verify archives after download.

Source commit: [${sha:0:12}](https://github.com/$repo/commit/$sha)

Note: Linux has been tested in CI only; macOS local smoke test is recorded only for the original verified build. These archives reuse the successful CI production binaries.
EOF

gh release create "$tag" -R "$repo" \
  --target "$sha" \
  --title "Swoole CLI $swoole_version · PHP $php_version · Custom Build" \
  --notes-file "$notes" --draft \
  "$workdir/dist/"*
gh release edit "$tag" -R "$repo" --draft=false
echo "Published release: https://github.com/$repo/releases/tag/$tag"
