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
  # The @font-face list lives in fonts.js as JS. Generating it from filenames is
  # fragile (variable fonts like Inter-var and subsets like NotoSansSC-sub produce
  # bogus weights such as 'var' / 'sub', which crash the page with
  # "Failed to set 'var' as a property value"). So: only OUR fonts are injected,
  # listed explicitly. Upstream's own entries are left untouched.
  python3 - <<'PY'
import json, os

base = 'skill/scripts/engine/lib/fonts'
js = 'skill/scripts/engine/lib/fonts.js'
src = open(js).read()

# repo-local fonts only: filename -> (css weight, extra desc or None)
OURS = {
    'NotoSansEthiopic-700.woff2': ('700', None),
}

added = []
for fname, (weight, desc) in OURS.items():
    if not os.path.exists(os.path.join(base, fname)):
        raise SystemExit('font file missing in skill: ' + fname)
    fam = fname.rsplit('.', 1)[0]
    if ("family:'%s'" % fam) in src:          # already registered, don't double-add
        continue
    d = (", desc:{weight:'%s'}" % desc) if desc else ''
    added.append("  {family:'%s', url:'lib/fonts/%s'%s}," % (fam, fname, d))

if added:
    i = src.rfind('\n];')
    src = src[:i] + '\n  // ---- injected by fetch-skill.sh (repo-local fonts) ----\n' + '\n'.join(added) + src[i:]
    open(js, 'w').write(src)

# append to index.json only for fonts it does not already list
idx = json.load(open(os.path.join(base, 'index.json')))
have = set(e[0] for e in idx)
for fname, (weight, desc) in OURS.items():
    if fname not in have:
        fam = fname.rsplit('.', 1)[0].replace('_', ' ')
        idx.append([fname, fam, 'normal', weight])
json.dump(idx, open(os.path.join(base, 'index.json'), 'w'))

print('fonts.js registrations added:', added)
PY
fi


# ---------------------------------------------------------------------------
# Structural verification: the skill's loader reads the cmap table to validate
# glyph coverage, and a font without one throws "no cmap table" at render time.
# A converted font can look fine (browsers still shape it) and still be rejected,
# so check the packaged file here — this is seconds, a bad font costs a whole run.
# ---------------------------------------------------------------------------
echo "==> verifying packaged fonts (cmap present)"
. .venv/bin/activate 2>/dev/null || true
uv pip install --quiet fonttools brotli >/dev/null 2>&1 || pip install --quiet fonttools brotli
python - <<'PY'
import glob, os, sys
from fontTools.ttLib import TTFont
bad = []
checked = 0
for p in sorted(glob.glob('skill/scripts/engine/lib/fonts/*.woff*')):
    name = os.path.basename(p)
    if 'Ethiopic' not in name:
        continue
    try:
        f = TTFont(p)
        n = len(f.getBestCmap() or {})
    except Exception as e:
        bad.append(f'{name}: unreadable ({e})')
        continue
    checked += 1
    if n == 0:
        bad.append(f'{name}: cmap missing or empty')
    else:
        print(f'  {name}: {n} codepoints OK')
if bad:
    for b in bad:
        print('FONT FAIL:', b, file=sys.stderr)
    raise SystemExit(1)
if not checked:
    raise SystemExit('no Ethiopic font found after injection')
print('font verification passed')
PY

echo "==> font sanity check"
python3 - <<'PY'
import json, os
base = 'skill/scripts/engine/lib/fonts'
idx = json.load(open(os.path.join(base, 'index.json')))
print('index.json entries:', len(idx))
eth = [f for f in os.listdir(base) if 'Ethiopic' in f]
print('Ethiopic files present:', eth)
js = open('skill/scripts/engine/lib/fonts.js').read()
print('fonts.js registers Ethiopic:', 'Ethiopic' in js)
if not eth: raise SystemExit('MISSING Ethiopic font — Amharic will render as tofu')
if 'Ethiopic' not in js: raise SystemExit('fonts.js has no Ethiopic registration')
PY

echo "==> skill tree:"
du -sh "${DEST}"/* | sort -h
echo "==> engine:"
ls "${DEST}/scripts/engine" | head -30
