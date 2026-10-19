#!/bin/sh
# Deploys the newest CI image of an app's main branch: ./deploy.sh api|web
#
# Flux applies only commits signed by syeyoung's key (see clusters/syeyoung-kube/flux-system), so a
# deploy is a signed commit here that pins the image by digest. Before signing, this checks that
# every commit since the last deploy, here and in the app's repo, carries that same signature, so
# commits pushed by someone else through GitHub are never deployed under it.
set -eu
cd "$(dirname "$0")"

KEY=85CEA8FCC07F297F79DE8169296393DBF79539FC
# The first commit Flux verified; everything after it must be signed too.
BASE=__BASE__

app=${1:-}
case "$app" in api | web) ;; *) echo "usage: $0 api|web" >&2; exit 2 ;; esac
src=../$app
repo=cyoung06/assistant-$app
image=ghcr.io/$repo

# Every commit in a range signed (and good) by KEY; prints the ones that aren't.
signed() {
  git -C "$1" log --format='%H %G? %GP %s' "$2" | awk -v k="$KEY" '$2 != "G" || $3 != k { print "  " $0; bad = 1 } END { exit bad }'
}

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash changes here first." >&2; exit 1; }
git fetch -q origin main
signed . "$BASE..origin/main" || { echo "Commits in assistant-gitops not signed by $KEY (above): not deploying." >&2; exit 1; }
git merge -q --ff-only origin/main

git -C "$src" fetch -q origin main
head=$(git -C "$src" rev-parse origin/main)
deployed=$(sed -n "s|.*image: $image:[0-9]*-\([0-9a-f]*\)@.*|\1|p" "apps/assistant/$app.yaml")
range=$head
if [ -n "$deployed" ] && git -C "$src" merge-base --is-ancestor "$deployed" "$head" 2>/dev/null; then range="$deployed..$head"; else range="-1 $head"; fi
# shellcheck disable=SC2086
signed "$src" $range || { echo "Commits in $repo not signed by $KEY (above): not deploying." >&2; exit 1; }
[ "${deployed:-x}" != "$(echo "$head" | cut -c1-7)" ] || { echo "assistant-$app is already at ${head%"${head#???????}"}."; exit 0; }

# Wait for CI on that commit, which tags the image <run number>-<short sha>.
run=$(gh run list -R "$repo" --commit "$head" --workflow ci --json databaseId,number -q '.[0] | "\(.databaseId) \(.number)"')
[ -n "$run" ] || { echo "No CI run for $head yet." >&2; exit 1; }
gh run watch -R "$repo" "${run% *}" --exit-status >/dev/null
tag="${run#* }-$(echo "$head" | cut -c1-7)"

token=$(curl -fsS "https://ghcr.io/token?scope=repository:$repo:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
digest=$(curl -fsSI -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json" \
  "https://ghcr.io/v2/$repo/manifests/$tag" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')
case "$digest" in sha256:*) ;; *) echo "No digest for $image:$tag." >&2; exit 1 ;; esac

sed -i '' "s|image: $image:[^ ]*|image: $image:$tag@$digest|" "apps/assistant/$app.yaml"
git commit -q -S -m "Deploy $image:$tag" "apps/assistant/$app.yaml"
git push -q origin main
flux reconcile source git flux-system -n flux-system >/dev/null
flux reconcile kustomization apps -n flux-system >/dev/null
echo "Deployed $image:$tag@$digest"
