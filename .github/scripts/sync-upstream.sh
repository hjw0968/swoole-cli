#!/usr/bin/env bash
set -euo pipefail
repo="${GITHUB_REPOSITORY:?}"
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
branch="automation/upstream-$(date -u +%Y%m%d)-${official:0:8}"
git checkout -B "$branch" "$initial"
if ! git merge --no-edit "$official"; then
  git merge --abort || true
  echo "::error::Upstream merge conflict; main unchanged."
  exit 1
fi
candidate="$(git rev-parse HEAD)"
git push --force-with-lease origin "HEAD:refs/heads/$branch"
gh workflow run linux-x86_64.yml -R "$repo" --ref "$branch"
gh workflow run macos-aarch64.yml -R "$repo" --ref "$branch"

get_run() {
  local wf="$1"
  gh run list -R "$repo" -w "$wf" -b "$branch" -c "$candidate" -L 50 \
      --json databaseId,status,conclusion,headSha \
      --jq '[.[] | select(.headSha == "$candidate")] | first | .databaseId // empty'
}
wait_run() {
  local wf="$1" run="" status="" outcome=""
  for _ in {1..50}; do
    run="$(get_run "$wf")"
    if [[ -n "$run" ]]; then break; fi
    sleep 12
  done
  [[ -n "$run" ]] || { echo "::error::$wf was not scheduled"; return 1; }
  echo "$wf run $run"
  for _ in {1..240}; do
    status="$(gh run view "$run" -R "$repo" --json status --jq .status)"
    if [[ "$status" == "completed" ]]; then
      outcome="$(gh run view "$run" -R "$repo" --json conclusion --jq .conclusion)"
      [[ "$outcome" == "success" ]] || { echo "::error::$wf concluded $outcome"; return 1; }
      return 0
    fi
    sleep 30
  done
  echo "::error::$wf timed out"; return 1
}
if ! wait_run linux-x86_64.yml; then exit 1; fi
if ! wait_run macos-aarch64.yml; then exit 1; fi
git fetch --no-tags origin main
[[ "$(git rev-parse origin/main)" == "$initial" ]] || {
  echo "::error::main advanced while verifying; no merge performed."
  exit 1
}
git push origin "$candidate:refs/heads/main"
echo "Verified upstream merged into main at $candidate"
