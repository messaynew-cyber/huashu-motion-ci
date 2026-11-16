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
cp -R /tmp/skill-x/scripts    "${DEST}/"
cp -R /tmp/skill-x/references "${DEST}/"
cp -R /tmp/skill-x/schemas    "${DEST}/" 2>/dev/null || true
cp -R /tmp/skill-x/defaults   "${DEST}/" 2>/dev/null || true
cp /tmp/skill-x/SKILL.md      "${DEST}/" 2>/dev/null || true
cp /tmp/skill-x/LICENSE       "${DEST}/" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Inject extra fonts kept in ./fonts (repository-local, not upstream).
# fonts.js registers each face explicitly, so we append entries here and drop
# the files next to the other fonts. Ethiopic script (Amharic) is NOT in the
# upstream font set — this is what makes Adwa possible.
# ---------------------------------------------------------------------------
if [ -d fonts ] && [ -n "$(ls -A fonts 2>/dev/null)" ]; then
  echo "==> injecting local fonts: $(ls fonts | tr '\n' ' ')"
  cp fonts/* "${DEST}/scripts/engine/lib/fonts/"
  python3 - <<'PY'
import json, os
base = 'skill/scripts/engine/lib/fonts'
idx = json.load(open(os.path.join(base, 'index.json')))
have = set(f for f, *_ in idx)
extra = []
for f in sorted(os.listdir(base)):
    if not f.endswith(('.woff', '.woff2')):
        continue
    if f in have:
        continue
    # filename convention: <Family>-<weight>.<ext>
    stem = f.rsplit('.', 1)[0]
    family, weight = (stem.rsplit('-', 1) + ['400'])[:2] if '-' in stem else (stem, '400')
    extra.append([f, family.replace('_', ' '), 'normal', weight])
idx.extend(extra)
json.dump(idx, open(os.path.join(base, 'index.json'), 'w'))
print('index.json entries added:', extra)

# append @font-face registrations to fonts.js
js = os.path.join('skill/scripts/engine/lib/fonts.js')
src = open(js).read()
lines = []
for f, fam, style, weight in extra:
    famname = f.rsplit('.', 1)[0]
    desc = f", desc:{{weight:'{weight}'}}" if weight else ''
    lines.append("  {family:'%s', url:'lib/fonts/%s'%s}," % (famname, f, desc))
if lines:
    marker = '\n];'
    i = src.rfind(marker)
    src = src[:i] + '\n  // ---- injected by fetch-skill.sh (repo-local fonts) ----\n' + '\n'.join(lines) + src[i:]
    open(js, 'w').write(src)
    print('fonts.js registrations added:', len(lines))
PY
fi

echo "==> skill tree:"
du -sh "${DEST}"/* | sort -h
echo "==> engine:"
ls "${DEST}/scripts/engine" | head -30
