#!/usr/bin/env python3
"""Split a pasted multi-review response into reviews/<tool>/<SceneClassName>.md
Usage: python3 parse_reviews.py <response.txt> <tool>
Delimiter: '===== REVIEW: <ClassName> ====='  (body = everything until next delimiter)."""
import re, os, sys

CL = "/private/tmp/claude-501/-Users-jamesalford/c8847d3f-395c-4922-94b7-945b288fcb87/scratchpad/glitched-redesign"
src_path, tool = sys.argv[1], sys.argv[2]
src = open(src_path, errors="ignore").read()
outdir = f"{CL}/reviews/{tool}"
os.makedirs(outdir, exist_ok=True)

parts = re.split(r"=====\s*REVIEW:\s*(\w+)\s*=====", src)
count = 0
for i in range(1, len(parts), 2):
    name = parts[i].strip()
    body = parts[i + 1].strip()
    if not body:
        continue
    with open(os.path.join(outdir, f"{name}.md"), "w") as f:
        f.write(body + "\n")
    count += 1
print(f"wrote {count} {tool} reviews to {outdir}")
