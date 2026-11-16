#!/usr/bin/env bash
# Fetch the huashu-art-motion skill at a pinned ref into ./skill/
# We pull a tarball instead of cloning a fork: upstream is 72.6 MB and
# 48.8 MB of that is assets/ (showreel GIFs + fonts). No history, no LFS.
set -euo pipefail

SKILL_REPO="${SKILL_REPO:-alchaincyf/huashu-art-motion}"
SKILL_REF="${SKILL_REF:-v1.3.1}"
DEST="${DEST:-skill}"

echo "==> fetching ${SKILL_REPO}@${SKILL_REF}"
rm -rf "${DEST}" /tmp/skill.tar.gz /tmp/skill-x
mkdir -p "${DEST}"

# 60s budget: the tarball is ~70 MB
curl -sSL --retry 4 --retry-delay 3 --max-time 300 \
  -o /tmp/skill.tar.gz \
  "https://codeload.github.com/${SKILL_REPO}/tar.gz/refs/tags/${SKILL_REF}" \
  || curl -sSL --retry 4 --retry-delay 3 --max-time 300 \
     -o /tmp/skill.tar.gz \
     "https://codeload.github.com/${SKILL_REPO}/tar.gz/refs/heads/${SKILL_REF}"

ls -lh /tmp/skill.tar.gz
mkdir -p /tmp/skill-x
tar -xzf /tmp/skill.tar.gz -C /tmp/skill-x --strip-components=1

# keep the parts we actually render with; skip the 48 MB of showreel media
cp -R /tmp/skill-x/scripts  "${DEST}/"
cp -R /tmp/skill-x/references "${DEST}/"
cp -R /tmp/skill-x/schemas  "${DEST}/" 2>/dev/null || true
cp -R /tmp/skill-x/defaults "${DEST}/" 2>/dev/null || true
cp /tmp/skill-x/SKILL.md    "${DEST}/" 2>/dev/null || true
cp /tmp/skill-x/LICENSE     "${DEST}/" 2>/dev/null || true

# fonts are needed for text rendering but live under scripts/engine/lib — already copied
echo "==> skill tree:"
du -sh "${DEST}"/* | sort -h
echo "==> engine:"
ls "${DEST}/scripts/engine" | head -30
