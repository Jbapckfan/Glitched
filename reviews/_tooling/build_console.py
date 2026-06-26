#!/usr/bin/env python3
"""Glitched level-review console: large device shots (iPad emphasized) + Claude/Codex/Gemini/Kimi reviews.
Self-contained HTML (base64 images), click any shot to zoom."""
import json, base64, glob, os, re, html

CL = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign"
SCRATCH = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad"
REVIEWS = f"{CL}/reviews"
OUT = f"{SCRATCH}/glitched-console.html"

CLASS_TO_LEVEL = {
    "BootSequenceScene":0,"HeaderScene":1,"WindBridgeScene":2,"StaticScene":3,"VolumeScene":4,
    "ChargingScene":5,"BrightnessScene":6,"ScreenshotScene":7,"DarkModeScene":8,"TimeTravelScene":9,
    "OrientationScene":10,"NotificationScene":11,"ClipboardScene":12,"WiFiScene":13,"FocusModeScene":14,
    "LowPowerScene":15,"ShakeUndoScene":16,"AirplaneModeScene":17,"AppSwitcherScene":18,"FaceIDScene":19,
    "MetaFinaleScene":20,"DeviceNameScene":21,"VoiceCommandScene":22,"BatteryPercentScene":23,
    "StorageSpaceScene":24,"TimeOfDayScene":25,"LocaleScene":26,"VoiceOverScene":27,"AirDropScene":28,
    "TheLieScene":29,"CreditsFinaleScene":30,"FlashlightScene":31,"MultiTouchScene":32,"AppReviewScene":33,
}

def b64img(path):
    if not os.path.exists(path): return None
    with open(path,"rb") as f: return base64.b64encode(f.read()).decode()

def load_md(tool):
    out = {}
    for p in glob.glob(f"{REVIEWS}/{tool}/*.md"):
        txt = open(p, errors="ignore").read()
        m = re.search(r"[Ll]evel\s+(\d{1,2})\b", txt)
        lvl = int(m.group(1)) if m else CLASS_TO_LEVEL.get(os.path.splitext(os.path.basename(p))[0])
        if lvl is not None and 0 <= lvl <= 33:
            out[lvl] = txt.strip()
    return out

claude = {}
cj = f"{SCRATCH}/claude-reviews.json"
if os.path.exists(cj):
    for r in json.load(open(cj)).get("reviews", []):
        claude[r["level"]] = r
codex, gemini, kimi = load_md("codex"), load_md("gemini"), load_md("kimi")

def claude_html(r):
    if not r: return "<em>pending</em>"
    badge = {"ship":"#1a7f37","polish":"#9a6700","rework":"#cf222e"}.get(r.get("verdict"),"#555")
    return (f'<div class="verdict" style="color:{badge}">{html.escape(r.get("verdict","?").upper())} · {r.get("score","?")}/5</div>'
            f'<p><b>+ strengths</b> {html.escape(r.get("strengths",""))}</p>'
            f'<p><b>! concerns</b> {html.escape(r.get("concerns",""))}</p>'
            f'<p><b>clue/hint</b> {html.escape(r.get("clueHint",""))}</p>'
            f'<p><b>→ fix</b> {html.escape(r.get("suggestion",""))}</p>')

def md_html(t, label):
    if not t: return f"<em>pending — {label} still running</em>"
    body = "\n".join(t.split("\n")[1:]).strip() or t  # drop the "Level N —" header line
    return "<p>" + html.escape(body).replace("\n\n","</p><p>").replace("\n","<br>") + "</p>"

rows = []
for n in range(34):
    nn = f"{n:02d}"
    ip = b64img(f"{REVIEWS}/iphone/L{nn}.png"); pad = b64img(f"{REVIEWS}/ipad/L{nn}.png")
    mech = (claude.get(n) or {}).get("mechanic","")
    ipimg = f'<img class="shot iphone" src="data:image/png;base64,{ip}" onclick="zoom(this.src)">' if ip else "<em>no shot</em>"
    padimg = f'<img class="shot ipad" src="data:image/png;base64,{pad}" onclick="zoom(this.src)">' if pad else "<em>no shot</em>"
    rows.append(f"""
    <section class="row" id="L{n}">
      <div class="lhead">LEVEL {n} <span class="mech">{html.escape(mech)}</span></div>
      <div class="shots">
        <figure><figcaption>iPhone</figcaption>{ipimg}</figure>
        <figure class="ipadfig"><figcaption>iPad — tap to enlarge</figcaption>{padimg}</figure>
      </div>
      <div class="reviews">
        <div class="review claude"><div class="cap">CLAUDE</div>{claude_html(claude.get(n))}</div>
        <div class="review codex"><div class="cap">CODEX</div>{md_html(codex.get(n),'Codex')}</div>
        <div class="review gemini"><div class="cap">GEMINI</div>{md_html(gemini.get(n),'Gemini')}</div>
        <div class="review kimi"><div class="cap">KIMI K2</div>{md_html(kimi.get(n),'Kimi')}</div>
      </div>
    </section>""")

nav = " ".join(f'<a href="#L{n}">{n}</a>' for n in range(34))
doc = f"""<!doctype html><html><head><meta charset="utf-8"><title>Glitched — Level Review Console</title>
<style>
:root{{--ink:#111;--bg:#fff;--mut:#777;--claude:#6e40c9;--codex:#0969da;--gemini:#1a7f37;--kimi:#cf5b00;}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 "SF Mono",Menlo,Consolas,monospace}}
header{{position:sticky;top:0;background:var(--bg);border-bottom:2px solid var(--ink);padding:12px 20px;z-index:20}}
header h1{{margin:0 0 6px;font-size:18px;letter-spacing:3px}}
.leg{{font-size:11px;color:var(--mut)}} .leg b{{padding:1px 5px;border-radius:3px;color:#fff}}
.nav a{{display:inline-block;width:26px;text-align:center;color:var(--ink);text-decoration:none;border:1px solid #ccc;margin:1px;border-radius:3px;font-size:12px}}
.nav a:hover{{background:var(--ink);color:#fff}}
.row{{border-bottom:2px solid var(--ink);padding:22px 24px;display:grid;grid-template-columns:auto 1fr;gap:26px;align-items:start}}
.lhead{{grid-column:1/3;font-size:18px;font-weight:700;letter-spacing:2px}}
.mech{{color:var(--mut);font-weight:400;font-size:14px;margin-left:10px}}
.shots{{display:flex;gap:16px;align-items:flex-start}}
figure{{margin:0}} figcaption{{font-size:11px;letter-spacing:2px;color:var(--mut);margin-bottom:6px;text-transform:uppercase}}
.shot{{border:1px solid #ddd;border-radius:8px;display:block;cursor:zoom-in;background:#fafafa}}
.shot.iphone{{height:600px}} .shot.ipad{{height:740px}}
.ipadfig figcaption{{color:var(--codex);font-weight:700}}
.reviews{{display:grid;grid-template-columns:1fr 1fr;gap:18px}}
.review{{border-left:3px solid #eee;padding-left:12px}}
.review .cap{{font-size:11px;letter-spacing:3px;margin-bottom:6px;font-weight:700}}
.review.claude{{border-left-color:var(--claude)}} .review.claude .cap{{color:var(--claude)}}
.review.codex{{border-left-color:var(--codex)}} .review.codex .cap{{color:var(--codex)}}
.review.gemini{{border-left-color:var(--gemini)}} .review.gemini .cap{{color:var(--gemini)}}
.review.kimi{{border-left-color:var(--kimi)}} .review.kimi .cap{{color:var(--kimi)}}
.review p{{margin:6px 0}} .verdict{{font-weight:700;letter-spacing:1px;margin-bottom:6px}}
#lb{{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;align-items:center;justify-content:center;z-index:100;cursor:zoom-out}}
#lb img{{max-width:96vw;max-height:96vh}}
@media(max-width:1500px){{.row{{grid-template-columns:1fr}} .lhead{{grid-column:1}} .shot.iphone{{height:480px}} .shot.ipad{{height:580px}}}}
</style></head><body>
<header><h1>GLITCHED — LEVEL REVIEW CONSOLE</h1>
<div class="leg"><b style="background:var(--claude)">CLAUDE</b> visual+code &nbsp; <b style="background:var(--codex)">CODEX</b> code &nbsp; <b style="background:var(--gemini)">GEMINI</b> code &nbsp; <b style="background:var(--kimi)">KIMI</b> code</div>
<div class="nav">{nav}</div></header>
{''.join(rows)}
<div id="lb" onclick="this.style.display='none'"><img id="lbimg"></div>
<script>function zoom(s){{document.getElementById('lbimg').src=s;document.getElementById('lb').style.display='flex';}}</script>
</body></html>"""
open(OUT,"w").write(doc)
print(f"wrote {OUT}  ({os.path.getsize(OUT)//1024} KB)")
print(f"claude:{len(claude)} codex:{len(codex)} gemini:{len(gemini)} kimi:{len(kimi)}  /34")
