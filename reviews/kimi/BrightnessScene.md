Level 6 — Brightness

The first encounter avoids hand-holding: the t=0 whisper only admits the darkness is shared, the BRIGHTNESS panel points upward without naming the burn threshold, and the LUX safe band stays hidden until the first burn (lines 421–425).

Platforming stays inside Bit’s safe budget: the phone path caps rise at 58/76 pt and stagger at 130 pt (lines 898–900, 905), and the iPad path bounds edge-to-edge gaps to 130 pt via maxLatC2C = 204 and thinW = 74 (lines 1013, 1028).

The hint pipeline calls notePlayerProgress() when brightness crosses 0.6 (line 1673) and notePlayerStruggle() on every death (line 1757), yet hintText() only returns a single flat string (line 1784), so struggling players get no escalating guidance.

The implementation is rough: maxBrightnessSun!, screenFlash!, and instructionPanel! are force-unwraps (lines 331, 473, 1457), the sun hazard body is a hardcoded 280×50 rectangle (line 522) that overshoots the visible ray span of 4 × raySpacing (120 pt phone, 240 pt tablet), and the burn-zone hazard radius is 40 pt against a 35-pt visual burst (lines 292, 317).

A worse bug is that if the player enters with brightness already above 0.6, the instruction panel never auto-dismisses because notePlayerProgress() is only triggered by a brightness change in handleGameInput() (lines 1668–1673), not the initial UIScreen.main.brightness read in configureScene() (line 101).

On load, the scene should compare the initial UIScreen.main.brightness against the ghost threshold and call notePlayerProgress() / fade the panel, so returning players are not stuck with a persistent BRIGHTNESS tooltip.
