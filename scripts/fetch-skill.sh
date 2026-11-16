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
    'NotoSansEthiopic-700.woff': ('700', None),
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
echo "==> verifying packaged font (WOFF1 signature + inflatable cmap)"
uv pip install --quiet fonttools >/dev/null 2>&1 || true
.venv/bin/python - <<'PY' 2>/dev/null || python3 - <<'PY'
import glob, os, struct, sys, zlib

def read_cmap_like_engine(ab):
    """Mirror of lib/util.js readCmap: WOFF1 (0x774F4646) or bare TTF/OTF only."""
    sig = struct.unpack('>I', ab[:4])[0]
    if sig == 0x774F4646:                                  # 'wOFF'
        num = struct.unpack('>H', ab[12:14])[0]
        for i in range(num):
            o = 44 + i * 20
            if ab[o:o+4] != b'cmap':
                continue
            off, comp, orig = struct.unpack('>III', ab[o+4:o+16])
            raw = ab[off:off+comp]
            return zlib.decompress(raw) if comp < orig else raw
    elif sig in (0x00010000, 0x4F54544F):                  # TTF / OTTO
        num = struct.unpack('>H', ab[4:6])[0]
        for i in range(num):
            o = 12 + i * 16
            if ab[o:o+4] == b'cmap':
                off, ln = struct.unpack('>II', ab[o+8:o+16])
                return ab[off:off+ln]
    return None

cands = [p for p in glob.glob('skill/scripts/engine/lib/fonts/*') if 'Ethiopic' in p]
if not cands:
    raise SystemExit('FONT FAIL: no Ethiopic font in skill after injection')

for p in cands:
    name = os.path.basename(p)
    if name.endswith('.woff2'):
        raise SystemExit(f'FONT FAIL: {name} is WOFF2 — engine readCmap cannot parse WOFF2')
    ab = open(p, 'rb').read()
    sig = struct.unpack('>I', ab[:4])[0]
    if sig != 0x774F4646:
        raise SystemExit(f'FONT FAIL: {name} signature {hex(sig)} is not WOFF1')
    cm = read_cmap_like_engine(ab)
    if not cm:
        raise SystemExit(f'FONT FAIL: {name} has no readable cmap')
    print(f'  {name}: WOFF1 OK, cmap {len(cm)} bytes, inflated')

print('font verification passed (engine-compatible)')
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
