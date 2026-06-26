Level 11 — Notification

The opening panel tells the player to "WAIT FOR THE ALERT" (line 694), but the decoy "SYSTEM" alert is deliberately scheduled a full second before the genuine "GLITCHED" one at `max(0.5, realDelay - 1.0)` (line 783), so a first-timer who obeys the text is likely to tap the wrong banner and get recycled through `handleDecoyTapped()` (line 972).

Jump reach is safe on paper: iPhone gaps are 20–40 pt (lines 308–317), and the iPad climb keeps rises within the 85 pt budget with ~30 pt edge-to-edge gaps (lines 376–424). Yet door 1 is hardcoded just 70 pt left of the top-tier rung (line 430), overlapping it by ~37.5 pt and leaving only a ~2.5 pt seam from the previous rung, so the finale geometry looks cramped and can snag Bit.

The t=0 text avoids spoiling the sender puzzle, but the hint system never escalates: `hintText()` returns one static sentence at line 1114 that never reacts to `notePlayerStruggle()` (line 1095) or `notePlayerProgress()` (line 962), so a player who repeatedly taps the decoy or misses the dropped rung gets no targeted guidance.

There are clear implementation rough edges: the permission-denied fallback banner is hit-tested with raw `nodes(at: location)` in scene space (line 1036), while the bell button correctly uses `uiContains`, so the faux notification can become untappable under iPad camera-follow. `drawFloorGrid()` hardcodes `floorY = 140` (line 238) and ignores the lifted iPad floor, leaving the decorative grid floating below the gameplay band, and `uiLayer.addChild(instructionPanel!)` at line 672 force-unwraps an optional constructed on the same line.

Concretely, replace the static `hintText()` with escalating branches (e.g., after a decoy tap warn "LOOK FOR THE GLITCHED SENDER, NOT SYSTEM"; after repeated deaths point to the signal-dropped rung) and route the faux-notification tap through the same `uiContains`/`uiLayer` path as the bell.
