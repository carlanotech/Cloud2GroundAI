#!/bin/bash
#
# ── Cloud to Ground AI → private GitHub repo ─────────────────────────
# Double-click this file. It will:
#   1. Make sure the GitHub CLI (gh) is installed + you're logged in
#   2. Create a PRIVATE repo  carlanotech/cloud-to-ground-ai  (if it
#      doesn't already exist)
#   3. Push everything in THIS folder to it
#
# Safe to run repeatedly — it force-pushes this folder as the source of truth.
# Only the files in this folder go up. The website, legal docx, roadmap, and
# release plan live OUTSIDE this folder and are never included.
# ──────────────────────────────────────────────────────────────────────

REPO="carlanotech/cloud-to-ground-ai"

cd "$(dirname "$0")" || exit 1

echo "=============================================="
echo " Cloud to Ground AI → GitHub (PRIVATE)"
echo "=============================================="
echo ""

# ── 1. Ensure gh is installed ──
if ! command -v gh >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing GitHub CLI (gh) via Homebrew..."
    brew install gh
  else
    echo "GitHub CLI (gh) isn't installed and Homebrew isn't available."
    echo "Install gh from https://cli.github.com then run this again."
    read -p "Press return to close."; exit 1
  fi
fi

# ── 2. Ensure logged in ──
if ! gh auth status >/dev/null 2>&1; then
  echo "Logging you into GitHub (a browser window will open)..."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git >/dev/null 2>&1

# ── 3. Create the private repo if it doesn't exist ──
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "Creating private repo $REPO ..."
  gh repo create "$REPO" --private --description "Cloud to Ground AI — file-based protocol to delegate mechanical work from a cloud AI to a local model." || {
    echo "Could not create the repo. If it already exists under a different name, create it manually on github.com (PRIVATE) and re-run."
    read -p "Press return to close."; exit 1
  }
fi

# ── 4. Build local git + push ──
echo ""
echo "Preparing files and pushing..."
rm -rf .git
git init -q
git branch -M main
git add -A
git -c user.email="carlanotech@pm.me" -c user.name="Carlano Technology Solutions" \
    commit -q -m "Cloud to Ground AI — initial private snapshot"
git remote add origin "https://github.com/$REPO.git"

if git push -u --force origin main; then
  echo ""
  echo "────────────────────────────────────────────────────────────"
  echo " Pushed. Private repo:"
  echo "   https://github.com/$REPO"
  echo " It is PRIVATE — only you can see it until you choose to publish."
  echo "────────────────────────────────────────────────────────────"
  open "https://github.com/$REPO"
else
  echo ""
  echo "Push failed. Copy the message above and send it to Claude."
fi

echo ""
read -p "Press return to close."
