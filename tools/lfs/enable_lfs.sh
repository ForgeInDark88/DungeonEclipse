#!/usr/bin/env bash
# Moves the heavy assets of DungeonEclipse to Git LFS — run once, on a
# machine whose git can upload to GitHub LFS (the cloud session that
# prepared this could not: its proxy refuses LFS uploads).
#   bash tools/lfs/enable_lfs.sh && git push
# What it does: installs the LFS hooks, puts the rules of
# tools/lfs/gitattributes.lfs into .gitattributes, converts the files that
# are already in git (git add --renormalize: one new commit, the history
# is NOT rewritten).
set -eu
cd "$(dirname "$0")/../.."
command -v git-lfs >/dev/null || { echo "Install Git LFS first: https://git-lfs.com"; exit 1; }
git lfs install --local
cp tools/lfs/gitattributes.lfs .gitattributes
git add .gitattributes
git add --renormalize -- '*.ogg' '*.wav' '*.mp3' '*.ttf' '*.otf' '*.webm' '*.ogv' 'assets/sprites/backgrounds/*.png'
echo "LFS files: $(git lfs ls-files | wc -l)"
git commit -m "Git LFS for audio, fonts, video and backgrounds"
echo "Now: git push   (then CI checks out with lfs: true)"
