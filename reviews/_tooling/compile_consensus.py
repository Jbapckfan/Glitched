#!/usr/bin/env python3
"""Compile the round-2 adjudication results into a master triage doc (CONSENSUS.md)."""
import json, sys, os

CL = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign"
SCRATCH = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad"
res = json.load(open(f"{SCRATCH}/adj_results.json"))
res.sort(key=lambda r: r["level"])
present = [r["level"] for r in res]
missing = [n for n in range(34) if n not in present]

SEV_ORDER = ["crash-softlock", "fairness", "polish", "cosmetic", "n/a"]
SEV_LABEL = {"crash-softlock":"🔴 CRASH / SOFTLOCK","fairness":"🟠 FAIRNESS","polish":"🟡 POLISH","cosmetic":"⚪ COSMETIC","n/a":"n/a"}

def cls_of(lvl): return next(r["className"] for r in res if r["level"]==lvl)

# ---- aggregate ----
survivors=[]   # real-unfixed + new
fps=[]; fixed=[]; contested=[]
for r in res:
    for f in r["findings"]:
        rec={**f,"level":r["level"],"className":r["className"]}
        if f["status"] in ("real-unfixed","new"): survivors.append(rec)
        elif f["status"]=="false-positive": fps.append(rec)
        elif f["status"]=="already-fixed": fixed.append(rec)
    for c in r.get("contested",[]): contested.append((r["level"],r["className"],c))

def sev_key(f):
    s=f["severity"]
    return SEV_ORDER.index(s) if s in SEV_ORDER else 99
survivors.sort(key=lambda f:(sev_key(f), f["level"]))

out=[]
out.append("# Glitched — Round-2 Consensus Triage (code-grounded)\n")
out.append(f"Each level's 4–5 blind round-1 reviews reconciled by a fresh adjudicator that read the **current** "
           f"(post-PR#15) source and tagged every finding `real-unfixed` / `already-fixed` / `false-positive` / `new`.\n")
out.append(f"**Coverage: {len(present)}/34 levels.**" + (f" Missing (re-run pending): {missing}.\n" if missing else "\n"))
out.append(f"- **Survivors to act on (real-unfixed + new): {len(survivors)}**")
out.append(f"- Thrown out — false-positives: {len(fps)} · already-fixed (PR#15 etc.): {len(fixed)}")
out.append(f"- Contested (want a Gemini/DeepSeek tiebreak): {len(contested)}\n")

# ---- THE FIX BACKLOG ----
out.append("## Fix backlog — survivors by severity\n")
cur=None
for f in survivors:
    if f["severity"]!=cur:
        cur=f["severity"]
        out.append(f"\n### {SEV_LABEL.get(cur,cur)}\n")
    tag = "🆕" if f["status"]=="new" else ""
    who = ",".join(f["reviewers"])
    out.append(f"- **L{f['level']} {f['className']} — {f['title']}** {tag}")
    out.append(f"  - `{f['codeRef']}` · raised by: {who}")
    out.append(f"  - {f['note']}")

# ---- contested ----
if contested:
    out.append("\n## Contested — optional external tiebreak\n")
    for lvl,cls,c in contested:
        out.append(f"- **L{lvl} {cls}**: {c}")

# ---- per-level ----
out.append("\n## Per-level verdicts\n")
for r in res:
    out.append(f"\n### L{r['level']} — {r['className']}")
    out.append(f"*{r['verdictLine']}*\n")
    if r.get("topActions"):
        out.append("**Top actions:**")
        for a in r["topActions"]: out.append(f"- {a}")
    # compact finding table
    out.append("\n| status | sev | finding | ref |")
    out.append("|---|---|---|---|")
    for f in r["findings"]:
        out.append(f"| {f['status']} | {f['severity']} | {f['title']} | `{f['codeRef']}` |")

doc="\n".join(out)+"\n"
open(f"{CL}/reviews/CONSENSUS.md","w").write(doc)
print(f"wrote reviews/CONSENSUS.md ({len(doc)//1024} KB)")
print(f"survivors={len(survivors)} fp={len(fps)} fixed={len(fixed)} contested={len(contested)} | missing={missing}")
# headline: severity histogram of survivors
from collections import Counter
hist=Counter(f["severity"] for f in survivors)
print("survivor severity:", dict(hist))
print("\nSURVIVOR TITLES (ranked):")
for f in survivors:
    tag="NEW" if f["status"]=="new" else "   "
    print(f"  [{f['severity']:<14}] {tag} L{f['level']:>2} {f['title']}")
