#!/bin/bash
# PUSH-ME.command — one-double-click push of release_staging/ to the
# carlanotech/Cloud2GroundAI private GitHub repo.
#
# How to use (the first time):
#   1. Create the private GitHub repo via the GitHub web UI:
#        Org:  carlanotech
#        Repo: Cloud2GroundAI
#        Visibility: PRIVATE (you will flip to public later)
#        Do NOT initialise with README, LICENSE, or .gitignore — this
#        script seeds those from the staging folder.
#   2. Double-click this file in Finder.
#   3. If prompted by Terminal about "PUSH-ME.command can't be opened",
#      right-click → Open → Open in the dialog. macOS only asks once.
#
# How to use (subsequent pushes):
#   1. Edit files in release_staging/.
#   2. Double-click this file.
#   3. Enter a commit message when prompted (or accept the default).
#
# What this script does:
#   - cd's into the staging folder
#   - initialises git if needed
#   - adds carlanotech/Cloud2GroundAI as the origin remote
#   - stages, commits, and pushes
#   - uses gh CLI for auth if available, falls back to plain git otherwise
#
# Requirements:
#   - git installed (every Mac has it via Xcode Command Line Tools)
#   - either `gh` authenticated to a GitHub account with push access to
#     carlanotech/Cloud2GroundAI, OR a personal access token cached
#     in macOS Keychain via git's credential helper.

set -e
set -u

# ─── Configuration ──────────────────────────────────────────────────────────
REPO_OWNER="carlanotech"
REPO_NAME="Cloud2GroundAI"
REMOTE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
DEFAULT_BRANCH="main"

# ─── Locate the staging folder (this script is inside it) ───────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "================================================================"
echo "  PUSH-ME — Cloud2GroundAI release_staging push"
echo "================================================================"
echo "Folder: ${SCRIPT_DIR}"
echo "Remote: ${REMOTE_URL}"
echo ""

# ─── Verify git is available ────────────────────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is not installed."
    echo "Install Xcode Command Line Tools first: xcode-select --install"
    read -p "Press any key to exit." -n 1
    exit 1
fi

# ─── Initialise git if needed ───────────────────────────────────────────────
if [ ! -d ".git" ]; then
    echo "→ Initialising new git repo..."
    git init -b "${DEFAULT_BRANCH}"
    echo "✓ git initialised"
    echo ""

    # First-time-only: configure remote
    git remote add origin "${REMOTE_URL}"
    echo "✓ added remote: ${REMOTE_URL}"
    echo ""
else
    # Make sure the remote is correct (in case it was previously
    # pointed somewhere else).
    CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ "${CURRENT_REMOTE}" != "${REMOTE_URL}" ]; then
        if [ -z "${CURRENT_REMOTE}" ]; then
            git remote add origin "${REMOTE_URL}"
        else
            echo "→ Updating remote from ${CURRENT_REMOTE} to ${REMOTE_URL}"
            git remote set-url origin "${REMOTE_URL}"
        fi
    fi
fi

# ─── Stage everything ───────────────────────────────────────────────────────
echo "→ Staging changes..."
git add -A

# Show what's about to be committed
echo ""
echo "Changes to commit:"
git status --short
echo ""

# Empty diff = nothing to do
if git diff --staged --quiet; then
    echo "✓ No changes to commit. Working tree clean."
    echo ""
    read -p "Press any key to close." -n 1
    exit 0
fi

# ─── Get commit message ─────────────────────────────────────────────────────
DEFAULT_MSG="Update release_staging — $(date +%Y-%m-%d)"
echo "Default commit message:"
echo "  ${DEFAULT_MSG}"
echo ""
read -p "Enter commit message (or press Return for default): " USER_MSG
if [ -z "${USER_MSG}" ]; then
    COMMIT_MSG="${DEFAULT_MSG}"
else
    COMMIT_MSG="${USER_MSG}"
fi

# ─── Commit with DCO sign-off ───────────────────────────────────────────────
echo ""
echo "→ Committing..."
git commit -s -m "${COMMIT_MSG}"
echo "✓ committed"

# ─── Push ───────────────────────────────────────────────────────────────────
echo ""
echo "→ Pushing to ${REMOTE_URL}..."
echo ""

# set -e is active for the rest of this script, but we need the exit code
# from `git push` specifically (to show the friendly troubleshooting tips
# on failure instead of just aborting) — disable it for this one command.
#
# --force: this staging folder is the single source of truth for the repo
# (you edit here, not on GitHub). Force lets the first push cleanly overwrite
# the repo's auto-generated starter commit (README/LICENSE/.gitignore created
# via the GitHub "new repo" screen), and keeps later pushes simple. It never
# touches tags/releases, so published releases are safe. Only caveat: don't
# edit files directly in the GitHub web UI, since the next push would overwrite
# those edits.
set +e
git push -u --force origin "${DEFAULT_BRANCH}"
PUSH_STATUS=$?
set -e

echo ""
if [ ${PUSH_STATUS} -eq 0 ]; then
    echo "================================================================"
    echo "  ✅ Done. Pushed to ${REMOTE_URL}"
    echo "================================================================"
else
    echo "================================================================"
    echo "  ❌ Push failed. See errors above."
    echo "================================================================"
    echo ""
    echo "Common fixes:"
    echo "  - Repo not yet created on GitHub: create it via the web UI as"
    echo "    a PRIVATE repo at https://github.com/new"
    echo "  - Not authenticated: run 'gh auth login' in Terminal, or"
    echo "    configure git credential helper for GitHub."
    echo "  - Wrong remote URL: edit REPO_OWNER/REPO_NAME at the top of"
    echo "    this script."
fi

echo ""
read -p "Press any key to close." -n 1
