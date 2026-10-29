#!/usr/bin/env bash
set -euo pipefail
repo="${GITHUB_REPOSITORY:?}"
branch=""
branch_pushed=0
cleanup() {
  if [[ "$branch_pushed" == "1" && "$branch" == automation/upstream-* ]]; then
    git push origin ":refs/heads/$branch" || echo "::warning::Could not delete temporary branch $branch"
  fi
}
trap cleanup EXIT

git config user.name github-actions[bot]
git config user.email 41898282+github-actions[bot]@users.noreply.github.com
git remote add upstream https://github.com/swoole/swoole-cli.git
git fetch --no-tags upstream main
git fetch --no-tags origin main
initial="$(git rev-parse origin/main)"
official="$(git rev-parse upstream/main)"
if git merge-base --is-ancestor "$official" "$initial"; then
  echo "Upstream already incorporated."
  exit 0
fi
branch="automation/upstream-$(date -u +%Y%m%d%H%M)-${official:0:8}"
git checkout -B "$branch" "$initial"

# These five platform workflows are intentionally retired in our fork.
retired=(
  .github/workflows/android-arm64-v8a-runtime.yml
  .github/workflows/artifact-hash.yml
  .github/workflows/auto-cache-pool-tarball.yml
  .github/workflows/iphoneos-arm64-runtime.yml
  .github/workflows/linux-aarch64.yml
)
platforms=(.github/workflows/linux-x86_64.yml .github/workflows/macos-aarch64.yml)

# Only resolve conflicts with an explicitly defined policy.
if ! git merge --no-commit --no-ff "$official"; then
  mapfile -d '' -t conflicts < <(git diff --name-only --diff-filter=U -z)
  if (("${#conflicts[@]}" == 0)); then
    echo '::error::Merge failed without resolvable conflicts.'
    git merge --abort || true
    exit 1
  fi
  for path in "${conflicts[@]}"; do
    case "$path" in
      .github/workflows/android-arm64-v8a-runtime.yml|\
      .github/workflows/artifact-hash.yml|\
      .github/workflows/auto-cache-pool-tarball.yml|\
      .github/workflows/iphoneos-arm64-runtime.yml|\
      .github/workflows/linux-aarch64.yml)
        echo "Keeping retired platform removed: $path"
        git rm -f -- "$path" ;;
      .github/workflows/linux-x86_64.yml|.github/workflows/macos-aarch64.yml)
        echo "Preserving tested custom build workflow: $path"
        git checkout --ours -- "$path"
        git add -- "$path" ;;
      *)
        echo "::error::Unknown merge conflict: $path; main untouched."
        git merge --abort || true
        exit 1 ;;
    esac
  done
fi
if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
  echo '::error::Unresolved merge conflicts.'
  git merge --abort || true
  exit 1
fi

# A new official platform workflow must not silently re-enable extra builds.
while IFS= read -r workflow; do
  case "$workflow" in
    .github/workflows/linux-x86_64.yml|.github/workflows/macos-aarch64.yml|\
    .github/workflows/publish-release.yml|.github/workflows/sync-upstream.yml) ;;
    *) echo "Removing unsupported upstream workflow: $workflow"; git rm -f -- "$workflow" ;;
  esac
done < <(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

# Fail closed if official changes any of our build fixes or release safeguards.
for path in "${retired[@]}"; do
  if [[ -e "$path" || -n "$(git ls-files -- "$path")" ]]; then
    echo "::error::Retired platform reappeared: $path"
    git merge --abort || true
    exit 1
  fi
done
for path in \
  sapi/src/builder/extension/protobuf.php \
  sapi/src/builder/extension/xlswriter.php \
  sapi/scripts/patch-xlswriter3-headers.php \
  .github/scripts/publish-verified-release.sh \
  .github/workflows/publish-release.yml \
  .github/scripts/sync-upstream.sh \
  .github/workflows/sync-upstream.yml; do
  if ! git diff --cached --quiet "$initial" -- "$path"; then
    echo "::error::Protected customization changed: $path"
    git merge --abort || true
    exit 1
  fi
done
for path in "${platforms[@]}"; do
  for marker in '+protobuf +xlswriter' 'patch-xlswriter3-headers.php' 'php_protobuf.h' 'Verify Required Extensions' 'workflow_dispatch'; do
    if ! grep -Fq -- "$marker" "$path"; then
      echo "::error::Build invariant '$marker' missing from $path"
      git merge --abort || true
      exit 1
    fi
  done
done

git commit -m "Merge official swoole-cli $official (retain verified custom build)"
candidate="$(git rev-parse HEAD)"
git push origin "HEAD:refs/heads/$branch"
branch_pushed=1

# A GITHUB_TOKEN push will not trigger push workflows. Dispatch explicitly.
gh workflow run linux-x86_64.yml -R "$repo" --ref "$branch"
gh workflow run macos-aarch64.yml -R "$repo" --ref "$branch"

find_run() {
  local workflow="$1"
  gh run list -R "$repo" -w "$workflow" -b "$branch" -L 100 \
    --json databaseId,status,conclusion,headSha |
    jq -r --arg sha "$candidate" '[.[] | select(.headSha == $sha)] | first | .databaseId // empty'
}

# Find the precise dispatched commits, rather than a stale successful run.
linux_id=""
macos_id=""
for _ in {1..50}; do
  linux_id="$(find_run linux-x86_64.yml)"
  macos_id="$(find_run macos-aarch64.yml)"
  if [[ -n "$linux_id" && -n "$macos_id" ]]; then break; fi
  sleep 12
done
if [[ -z "$linux_id" || -z "$macos_id" ]]; then
  echo '::error::Missing one or both dispatched builds; main untouched.'
  exit 1
fi
echo "Linux: https://github.com/$repo/actions/runs/$linux_id"
echo "macOS: https://github.com/$repo/actions/runs/$macos_id"

# Poll both builds concurrently; failure or timeout keeps main untouched.
for _ in {1..240}; do
  linux_state="$(gh run view "$linux_id" -R "$repo" --json status,conclusion --jq '[.status,.conclusion] | join(" ")')"
  macos_state="$(gh run view "$macos_id" -R "$repo" --json status,conclusion --jq '[.status,.conclusion] | join(" ")')"
  [[ "$linux_state" != 'completed '* || "$linux_state" == 'completed success' ]] || { echo "::error::Linux CI: $linux_state"; exit 1; }
  [[ "$macos_state" != 'completed '* || "$macos_state" == 'completed success' ]] || { echo "::error::macOS CI: $macos_state"; exit 1; }
  if [[ "$linux_state" == 'completed success' && "$macos_state" == 'completed success' ]]; then break; fi
  sleep 30
done
[[ "${linux_state:-}" == 'completed success' && "${macos_state:-}" == 'completed success' ]] || {
  echo '::error::Build timeout; main untouched.'
  exit 1
}

git fetch --no-tags origin main
if [[ "$(git rev-parse origin/main)" != "$initial" ]]; then
  echo '::error::main changed during build; refusing to overwrite it.'
  exit 1
fi
# Fast-forward, never force push.
git push origin "$candidate:refs/heads/main"

# Automatic release from the same verified binaries, without recompilation.
gh workflow run publish-release.yml -R "$repo" --ref main \
  -f "linux_run_id=$linux_id" -f "macos_run_id=$macos_id"
echo "Verified upstream merged and Release workflow dispatched: $candidate"
