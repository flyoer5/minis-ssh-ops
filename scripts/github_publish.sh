#!/bin/sh
# Create GitHub repo and push current branch using GH_TOKEN / GITHUB_TOKEN.
# Usage: GH_TOKEN=ghp_xxx ./scripts/github_publish.sh [repo_name]
set -e
cd "$(dirname "$0")/.."

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: set GH_TOKEN or GITHUB_TOKEN (fine-grained or classic PAT with repo scope)" >&2
  exit 1
fi

REPO_NAME="${1:-minis-ssh-ops}"
API="https://api.github.com"

# Who am I?
USER_JSON=$(curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$API/user")
OWNER=$(printf '%s' "$USER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['login'])")
echo "GitHub user: $OWNER"
echo "Repo: $OWNER/$REPO_NAME"

# Create repo if missing (user account)
CODE=$(curl -sS -o /tmp/gh_create.json -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -X POST "$API/user/repos" \
  -d "{\"name\":\"$REPO_NAME\",\"description\":\"Local private AI SSH ops for Android (opsd + Flutter)\",\"private\":false,\"auto_init\":false}")

if [ "$CODE" = "201" ]; then
  echo "Created repository."
elif [ "$CODE" = "422" ]; then
  echo "Repo may already exist, continuing…"
  cat /tmp/gh_create.json | head -c 300; echo
else
  echo "Create repo failed HTTP $CODE"
  cat /tmp/gh_create.json
  exit 1
fi

REMOTE="https://x-access-token:${TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE"

# Avoid storing token in .git/config permanently: use push URL once
git push -u origin HEAD:main

# Rewrite remote without token
git remote set-url origin "https://github.com/${OWNER}/${REPO_NAME}.git"

echo ""
echo "OK: https://github.com/${OWNER}/${REPO_NAME}"
echo "Actions: https://github.com/${OWNER}/${REPO_NAME}/actions"
echo "Trigger: Actions → Build Android APK → Run workflow"
