#!/usr/bin/env python3
"""Paced Gemini-2.5-flash review: one API call per scene (free-tier rate-limit safe).
Reviews the MISSING scenes only (keeps the 7 the agentic CLI already wrote)."""
import os, glob, re, json, time, subprocess

KEY = os.environ["GEMINI_API_KEY"]
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={KEY}"
CL = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign"
os.makedirs(f"{CL}/reviews/gemini", exist_ok=True)

SHARED = """You are reviewing ONE scene of Glitched, a line-art SpriteKit puzzle-platformer (34 levels, each maps to a real iOS device feature). The player is "Bit". Levels were just REORDERED, so a file's name may not equal its level number — read the levelID set in configureScene for the true number (e.g. index 9 = Time Travel, 10 = Orientation, 21 = Device Name, 22 = Voice, 23 = Battery).
Design facts: Bit's safe jump reach is edge-to-edge gap <= 130pt and top-to-top rise <= 85pt (hard caps 145/91). On iPad the level should FILL the vertical band (a confined vertical column reads better than a shallow diagonal camera-follow). t=0 clue text should NOT spoil the trick; a stuck player should get escalating help via notePlayerStruggle()/hintText().

Write a markdown review for this scene. FIRST line EXACTLY: "Level <N> — <mechanic>" (N from the levelID). Then a single concise, genuinely critical paragraph (~6-8 sentences) covering: (1) mechanic clarity / first-encounter fairness; (2) completability / jump-reach; (3) clue/hint quality (no t=0 spoiler + stuck-player escalation); (4) a specific code bug or rough edge (e.g. isWideCanvas hardcoded to a constant, force-unwraps, dead code); (5) ONE concrete improvement. Output ONLY the markdown, no code fences."""

def review(src, cls):
    prompt = SHARED + f"\n\nScene class {cls} source:\n{src}"
    body = {"contents":[{"parts":[{"text":prompt}]}],
            "generationConfig":{"temperature":0.4,"maxOutputTokens":1200}}
    r = subprocess.run(["curl","-sS","-X","POST",URL,"-H","Content-Type: application/json","--data-binary","@-"],
                       input=json.dumps(body).encode(), capture_output=True, timeout=120)
    d = json.loads(r.stdout or b"{}")
    if "candidates" not in d:
        raise RuntimeError(json.dumps(d)[:200])
    return d["candidates"][0]["content"]["parts"][0]["text"]

scenes = sorted(glob.glob(f"{CL}/Glitched/Scenes/Level*.swift"))
wrote = skipped = errs = 0
for f in scenes:
    src = open(f).read()
    m = re.search(r"(?:final\s+)?class\s+(\w+Scene)\s*:", src)
    if not m:
        continue
    cls = m.group(1)
    out = f"{CL}/reviews/gemini/{cls}.md"
    if os.path.exists(out) and os.path.getsize(out) > 50:
        skipped += 1; continue
    for attempt in range(4):
        try:
            txt = review(src, cls).strip()
            if txt:
                open(out, "w").write(txt)
                wrote += 1; print(f"wrote {cls}", flush=True)
            break
        except Exception as e:
            msg = str(e)[:120]
            if "429" in msg or "quota" in msg.lower():
                print(f"  rate-limited on {cls}, wait 45s (attempt {attempt+1})", flush=True); time.sleep(45)
            else:
                print(f"ERR {cls}: {msg}", flush=True); errs += 1; break
    time.sleep(13)  # pace ~4.6 req/min, under the 5/min free cap
print(f"DONE wrote:{wrote} skipped(existing):{skipped} errs:{errs}  total now: {len(glob.glob(CL+'/reviews/gemini/*.md'))}/34")
