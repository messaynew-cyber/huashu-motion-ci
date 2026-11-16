# huashu-motion-ci

Render [**huashu-art-motion**](https://github.com/alchaincyf/huashu-art-motion) films on
**GitHub Actions**. No GPU, no VPS, no local Chromium.

The skill (`alchaincyf/huashu-art-motion`) teaches an agent to write *code that animates*:
36 art styles, 9 narration grammars, 8 parameterized clip types. This repo is the missing
piece — the **muscle** that turns a storyboard into an `.mp4` in CI.

## The split

```
 agent (writes storyboard + scene code)  →  git push  →  GitHub Actions (renders)
```

The skill itself needs an LLM with agent tooling (Claude Code / Codex / Kimi). Actions has
no model in it. That is the correct division of labour: **brain writes, runner renders.**

## Pipeline

Every run is three gates, cheapest first — a bad storyboard fails in 20 seconds, not 30 minutes.

| Step | Script | Fails the build when |
|---|---|---|
| 1. Storyboard lint | `scripts/storyboard_lint.py` | text-card ending, blank shot, 3 consecutive push-ins, screen text ≠ spoken numbers |
| 2. Render | `scripts/engine/render.py` | headless Chromium throws, a glyph is missing, ffmpeg dies |
| 3. Film gate | `scripts/film_gate.py` | film is nearly static, ≥0.3 s of dead frames |

Step 2 is the expensive one (headless Chromium → canvas readback → ffmpeg pipe). Steps 1
and 3 are near-free and exist precisely so you never pay for step 2 with a broken input.

## Setup

Nothing to install locally. The workflow fetches the upstream skill itself at a pinned tag:

```yaml
env:
  SKILL_REPO: alchaincyf/huashu-art-motion
  SKILL_REF:  v1.3.1
  RENDER_MODE: spec          # spec | film
  SPEC_FILE:  clips/clip.json
```

**Why not fork upstream?** It is **72.6 MB**, of which **48.8 MB is `assets/`** (showreel
GIFs, woff2 fonts, jpgs). Forking inherits all of it and charges you on every checkout.
We fetch a tarball at runtime instead — no history, no LFS, no bloat.

## Modes

**`spec`** (default, cheap) — renders one parameterized clip from `clips/clip.json`.
Duration is exact (`round(duration × fps)` frames), 1280×720 first, then a real 1920×1080.

**`film`** — full-length cut from `镜头表.md` + `scripts/engine/eras.js`. Slow: a 60 s
60 fps film is 3 600 frames and roughly **20–45 min on a 4 vCPU runner**.

Both accept `--stills 0.5,2` for spot-check frames before committing to the full render.

## Runner reality check

- Public repo → **free, 4 vCPU, ~16 GB**. Keep it public; 2 vCPU private runners are ~2.3×
  slower and the free-minute budget evaporates after two films.
- 6-hour per-job cap. Disk is ~14 GB — `render.py` already pipes frames to stdout instead
  of writing them, which is what keeps you off that cliff. Do not add bulk `--stills` dumps.
- No GPU, and none needed. Everything here is CPU.

## Layout

```
clips/clip.json        the parameterized clip spec (see references/09 contract)
storyboard/镜头表.md     optional full-film storyboard
scripts/fetch-skill.sh pinned tarball fetch + unzip into skill/
.github/workflows/     render.yml (spec) | render-film.yml (full film)
out/                   artifacts, gitignored
```

## Licence

This repo: MIT. Upstream `huashu-art-motion`: MIT, © 花叔 — fetched at runtime, never
vendored. Art credit belongs upstream; read their `README.md` acknowledgements.
