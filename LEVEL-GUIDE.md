# Glitched — Level-by-Level Guide

> Your iPhone IS the controller. Each level uses a different device feature as the core puzzle mechanic.

## Controls
- **Move**: Touch and drag left/right of your character
- **Jump**: Tap anywhere (or swipe up)
- **Keyboard** (if connected): Arrow keys to move, Space to jump

If you're stuck on any level for 30+ seconds, a hint will appear at the bottom of the screen.

---

## World 0: Boot Sequence

### Level 0 — BOOT
**Mechanic:** Drag interaction
**Objective:** Complete the loading bar to boot the system.
**How to solve:** After the hacker-style boot text scrolls (detecting hardware, loading kernel modules), a loading bar appears stuck at 99%. Drag the circular handle on the progress bar to the right to push it to 100%. You can only drag forward, not backward.
**What happens next:** The screen fakes a crash (goes black), flashes "JUST KIDDING," then restores with "SYSTEM LOADED" before transitioning to Level 1.
**Easter egg:** The boot sequence logs your actual device time ("OPERATOR TIME: HH:MM ... NOTED.") and shows a warning that `fourth_wall.ko` is UNSTABLE. The corruption error at sector `0x4F4F` foreshadows the game's meta-narrative.

---

## World 1: Hardware Awakening

### Level 1 — Header
**Mechanic:** HUD drag
**Objective:** Cross a spike pit to reach the exit door.
**How to solve:** The level header bar at the top of the screen (the "LEVEL 1" HUD element) is draggable. Drag it down and drop it over the spike pit in the middle of the level. It transforms into a physical bridge spanning the gap. Walk across and enter the exit door on the right.
**Easter egg:** After you drop the header, glitch text appears where it used to be: "HEY, I NEEDED THAT."

---

### Level 2 — Wind
**Mechanic:** Microphone (blowing)
**Objective:** Blow into your phone's microphone to extend a bridge across a chasm.
**How to solve:** There's a chasm between two platforms. Blow into your phone (or make loud noise near the mic). The louder you blow, the further the bridge extends from the right side. The bridge retracts very slowly when you stop, so you have time to cross. Blow hard enough to fully extend it, then walk across to the exit.
**Tips:** The bridge extends quickly but retracts slowly -- you don't need to blow continuously. A strong, sustained breath works best. At maximum power, the screen shakes and the bridge glows.
**Easter egg:** On your first successful blow, the game comments: "DID YOU JUST... BLOW ON YOUR PHONE?"

---

### Level 3 — Static
**Mechanic:** Microphone (sustained noise)
**Objective:** Navigate a laser gauntlet using noise as your shield.
**How to solve:** Four vertical laser barriers block your path across platforms. Making noise into the microphone creates "static" that disables the first three lasers (they dim and become passable). However, the fourth laser is INVERSE -- it activates when you make noise and deactivates in silence. You must make noise to pass the first three lasers, then go silent to pass the fourth one. Time your noise bursts with your movement.
**Tips:** The instruction panel says "MAKE NOISE TO BLOCK LASERS." The trick is realizing the dashed fourth laser operates in reverse. Keep noise above the threshold while navigating the first three, then stop making noise for the final barrier.
**Easter egg:** After your first successful laser block: "THE NEIGHBORS ARE STARTING TO WORRY."

---

### Level 4 — Volume
**Mechanic:** Device volume buttons
**Objective:** Sneak past a sleeping wolf creature without waking it, while managing rising water.
**How to solve:** A wolf creature sleeps in the middle of the level. If your device volume is too high (above ~50%), the wolf stirs and eventually wakes, killing you. Lower your volume below 30% to keep it asleep. BUT there's a second hazard: volume also controls water level. High volume (above 70%) causes flooding that can drown you, while low volume keeps the water safely below the platforms.
**The sweet spot:** Keep volume below 30% to keep the wolf sleeping and prevent flooding. Navigate past the creature and reach the exit door on the right.
**Tips:** The wolf sleep-talks with fourth-wall commentary: "zzz... delete... the app... zzz" and "zzz... lower the volume... please... zzz." The safe zone shrinks over time, adding pressure.
**Easter egg:** The wolf's sleep-talk lines cycle through meta-commentary including "mmm... is that... a square person... zzz" and "mmm... five more levels..."

---

### Level 5 — Charging
**Mechanic:** Lightning cable / wireless charging
**Objective:** Ride a giant charging plug up through a vertical shaft to reach the exit.
**How to solve:** You start on a platform inside a shaft with a destructible floor. Plug your phone into a charger (lightning cable or wireless pad). A giant plug smashes through the floor from below, creating a rising platform. Ride it upward to the exit door near the top of the shaft. If you unplug, the platform slowly sinks. Plug back in and it rises again.
**Tips:** The plug rises automatically once charging begins. Stay on top of it. If you unplug your phone, the platform sinks at 15 points/sec but rises at 30 points/sec when re-plugged, so you have some margin.
**Easter egg:** When you plug in: "FEEDING ME ELECTRICITY? HOW... NURTURING." When you unplug: "COLD. SO COLD."

---

### Level 6 — Brightness
**Mechanic:** Screen brightness slider
**Objective:** Reveal invisible UV platforms by raising brightness, but avoid burning hazards at max.
**How to solve:** A series of platforms are invisible at low brightness. As you increase your screen brightness (via Control Center slider), the platforms gradually fade in: ghostly below 50%, mostly visible at 80%, fully solid at full brightness. BUT at 95%+ brightness, sun-burst hazard zones activate that will kill you, and the screen flashes white. You need to find the sweet spot (around 80-90%) where platforms are solid but burn zones aren't active.
**Tips:** The brightness indicator on screen shows your current level. Platforms appear in stages -- you can see faint outlines even at medium brightness to plan your route.
**Easter egg:** At minimum brightness: "I CAN'T SEE EITHER, YOU KNOW." At maximum brightness: "MY EYES! THE GOGGLES DO NOTHING!"

---

### Level 7 — Screenshot
**Mechanic:** Taking a screenshot (Side Button + Volume Up)
**Objective:** Freeze a flickering ghost bridge by taking a screenshot, then cross before the timer expires.
**How to solve:** A bridge of 7 segments flickers in and out of existence (100ms visible, 200ms invisible). Taking a screenshot freezes the bridge solid for 5 seconds (first screenshot), giving you time to cross. The freeze duration decreases with each screenshot: 5s, 3.5s, 2s, 1s. A countdown timer appears showing remaining freeze time. The bridge starts flickering again as a warning when under 2 seconds remain.
**Tips:** Take a screenshot, then immediately start running across. You likely need just one well-timed screenshot to cross. If you die, the screenshot count resets. There's a 2-second cooldown between screenshots.
**Easter egg:** First screenshot triggers: "YOU JUST SCREENSHOTTED ME." followed by "THAT'S IN YOUR CAMERA ROLL NOW. FOREVER."

---

### Level 8 — Dark Mode
**Mechanic:** System dark/light mode toggle (Settings > Display & Brightness)
**Objective:** Toggle dark mode to switch which platforms are solid, and navigate a dual-mode maze.
**How to solve:** The level has two types of special platforms: moon-marked platforms (only solid in dark mode) and sun-marked platforms (only solid in light mode). You need to switch between dark and light mode to make different platforms available. Start in your current mode, jump to the appropriate platforms, then switch to the other mode to reveal the next set. The exit door also has a moon sensor that requires dark mode to unlock.
**Tips:** Open Control Center or Settings and toggle Appearance between Light and Dark. Ghost platforms show a dashed outline and their sun/moon icon so you can plan your route. The entire scene's colors invert when you switch modes.
**Easter egg:** In dark mode, hidden text appears that's invisible in light mode. A shadow enemy also patrols only during dark mode.

---

### Level 9 — Orientation
**Mechanic:** Device rotation (portrait vs. landscape)
**Objective:** Rotate your phone to landscape to widen a narrow corridor and escape a crusher wall.
**How to solve:** A massive crusher wall (complete with skull decoration and grinding teeth) slowly advances from the left. A narrow corridor blocks your path -- in portrait mode the gap is only 18 points wide, but your character is 22 points wide, making it impossible to pass. Rotate your phone to landscape mode and the corridor gap widens to 100 points, letting you squeeze through and reach the exit.
**Tips:** The crusher has an ominous rumble animation. Don't wait too long -- rotate to landscape and move through quickly. The world scales to fit the new orientation.
**Easter egg:** If you rapidly rotate your phone back and forth multiple times, the game shows "dizzy" commentary.

---

### Level 10 — Time Travel
**Mechanic:** App backgrounding (pressing Home / swiping up)
**Objective:** Grow a sapling into a mature tree by letting time pass while the app is backgrounded.
**How to solve:** A small sapling blocks a gap. The instruction panel says "LEAVE APP" and "WAIT 5 SEC" then "RETURN." Press the Home button (or swipe up) to background the app, wait at least 5 seconds, then return. Time passes at 2x rate while you're away, and the tree grows through stages: sapling, young tree, mature tree, ancient tree. Once it's fully grown, it creates a physical bridge you can walk across to reach the exit. The tree needs about 10 "game years" (approximately 5 real seconds away).
**Tips:** A clock display shows elapsed game years. You can leave and return multiple times -- progress accumulates.
**Easter egg:** If you come back very quickly (under 2 seconds): "THAT WAS FAST. COMMITMENT ISSUES?" Otherwise: "YOU WERE GONE FOR X SECONDS. I COUNTED EVERY ONE."

---

## World 2: Control Surface

### Level 11 — Notification
**Mechanic:** Push notifications
**Objective:** Unlock doors by requesting and tapping push notifications.
**How to solve:** Two locked doors block your path. Tap the bell/notification button in the level to request a push notification. Leave the app or wait for the notification to arrive. Tap the notification to send the unlock command back to the game. The first door opens. Repeat for the second door. If you request enough notifications, the game eventually relents with a sequential set of fourth-wall messages.
**Tips:** The instruction panel says "TAP BELL" and "WAIT FOR NOTIFICATION." Allow notification permissions when prompted. The fourth-wall notification messages escalate: "BIT IS WAITING FOR YOU IN LEVEL 11" then "SERIOUSLY, THE DOOR IS RIGHT THERE" and finally "FINE. I'LL OPEN IT MYSELF."

---

### Level 12 — Clipboard
**Mechanic:** System clipboard (copy/paste)
**Objective:** Enter the correct password into a terminal by pasting it from your clipboard.
**How to solve:** A password-locked terminal blocks a door. The password is `GLITCH3D`. The game checks your clipboard automatically on load. Copy the text `GLITCH3D` to your clipboard (from Notes, Safari, or any app), then return to the game. The terminal scans your clipboard and if it matches, the locked door opens. You can also re-trigger a scan by interacting with the terminal.
**Tips:** The terminal screen displays a password prompt. Open any app, type `GLITCH3D`, copy it, then switch back to the game.

---

### Level 13 — WiFi
**Mechanic:** WiFi toggle
**Objective:** Use WiFi state to control platforms and complete a download progress bar.
**How to solve:** Some platforms and walls are WiFi-dependent. When WiFi is enabled, WiFi-marked platforms are solid (walkable) but WiFi walls also block your path. When WiFi is off, those platforms phase out and walls become passable. A download progress bar fills while WiFi is connected. You need to toggle WiFi on/off strategically: use WiFi-on to walk on signal platforms, then toggle WiFi off to pass through signal walls. Complete the download (keep WiFi on long enough) to unlock the final section.
**Tips:** The signal bar indicator in the corner shows WiFi status. WiFi platforms have a small signal icon above them.

---

### Level 14 — Focus Mode
**Mechanic:** Do Not Disturb / Focus Mode
**Objective:** Enable Focus Mode to freeze deadly hazards, then navigate safely to the exit.
**How to solve:** Multiple spike hazards orbit and oscillate through the level. Enable Focus Mode (Do Not Disturb) via Control Center or Settings. When Focus is active, all hazards freeze in place and a calm overlay appears, making the level peaceful and safe to navigate. The exit door unlocks only after Focus has been active. Navigate through the frozen hazards to the exit.
**Tips:** Swipe down from the top-right corner and tap Focus/DND to enable it. The hazards have various orbital patterns that make timing nearly impossible without freezing them.

---

### Level 15 — Low Power
**Mechanic:** Low Power Mode toggle
**Objective:** Toggle between normal and lunar gravity to navigate a multi-section obstacle course.
**How to solve:** Low Power Mode changes gravity from normal (-20) to lunar (-6). The level has four sections requiring alternating gravity states:
1. **Start area** (normal gravity): Basic platform climbing
2. **Narrow drop** (NEEDS normal gravity): A tight gap you must fall through -- low gravity makes you float too much
3. **Wide chasm** (NEEDS low gravity): A huge gap impossible to jump normally, but floatable in low gravity
4. **Final drop** (NEEDS normal gravity): A platform below you must drop to normally

Toggle Low Power Mode on and off as needed for each section.
**Tips:** Open Settings > Battery > Low Power Mode, or ask Siri "Turn on/off Low Power Mode." The battery indicator turns amber in low power. Floating particles become more visible in low gravity.

---

### Level 16 — Shake Undo
**Mechanic:** Shake to undo (device shake gesture)
**Objective:** Use limited time-rewind shakes to navigate tricky platforming with a moving platform.
**How to solve:** The level has a gap with a moving platform and tricky jumps. You get 3 undo charges. Shake your phone to rewind 3 seconds of gameplay (your position and the moving platform both rewind). This lets you recover from missed jumps or bad timing. The position history is recorded continuously, and shaking snaps you back to where you were 3 seconds ago.
**Tips:** Use undos strategically -- you only get 3. The counter shows remaining undos (x3, x2, x1). Time your jumps with the moving platform, and shake if you miss. After undos are depleted, shaking shows "NO UNDOS LEFT."
**Easter egg:** On your first undo, fourth-wall commentary appears about rewinding time.

---

### Level 17 — Airplane Mode
**Mechanic:** Airplane Mode toggle
**Objective:** Toggle Airplane Mode to make platforms "fly up" or "land."
**How to solve:** Three platforms have two positions each: a low "landed" position and a high "flying" position. When Airplane Mode is OFF, platforms sit low (landed). When you enable Airplane Mode, the platforms animate upward to their flying positions. The exit is on a high platform only reachable when the flying platforms are elevated. Toggle Airplane Mode on to raise platforms, jump to elevated positions, and reach the exit.
**Tips:** Each platform rises with a slightly staggered delay (0.0s, 0.3s, 0.6s) for a cascading effect. The exit platform is at groundY + 200, only reachable via the flying platforms. Turbulence effects shake the platforms in airplane mode.
**Easter egg:** Fourth-wall commentary appears about flight safety.

---

### Level 18 — App Switcher
**Mechanic:** App Switcher peek (swipe up to multitask view)
**Objective:** Use the app switcher to freeze hazards and reveal their trajectory lines.
**How to solve:** Fast-moving spike hazards oscillate through the level, making timing nearly impossible at full speed. Swipe up slightly to peek at the app switcher (don't fully leave the app). The level freezes and trajectory lines appear showing each hazard's path. You get 5 seconds of peek time (first peek) to study the patterns. Return to the app and navigate through the gaps. Peek time decreases with each use.
**Tips:** Swipe up just enough to trigger the app switcher -- you don't need to fully background the app. Study the dashed trajectory lines to plan your route through the hazard gauntlet.

---

### Level 19 — Face ID
**Mechanic:** Face ID / biometric authentication
**Objective:** Authenticate with Face ID to unlock vault doors.
**How to solve:** A large vault door with a face scanning frame blocks your path. Approach the vault and trigger the Face ID scan (the game initiates a real biometric authentication prompt). Successfully authenticate to unlock the first door. A second, smaller biometric door waits further along. Authenticate again to unlock it and proceed to the exit. The scan is multi-step: step 1 opens the first door, step 2 opens the second.
**Tips:** Devices without Face ID/Touch ID fall back to a proximity-based simulation. The vault has an animated scan line and face-tracking frame.
**Easter egg:** After the final unlock, fourth-wall text comments on the identity verification.

---

### Level 20 — Meta Finale (World 2 Boss)
**Mechanic:** App deletion / simulated system purge
**Objective:** Clear a corruption wall by triggering a system purge.
**How to solve:** The level opens with an ominous sequence: heartbeat haptics, warning messages ("CRITICAL SYSTEM FAILURE DETECTED", "CORRUPTION LEVEL: TERMINAL"). A wall of corrupted data blocks the exit. Walk into the corruption wall to trigger a simulated purge sequence -- the screen glitches, fakes a crash, shows a reboot animation, and then "reboots" into a clean state with the corruption cleared. Your progress is saved via Keychain, so it persists even through a real app reinstall.
**Tips:** The intro sequence sets a dark, threatening mood. The corruption wall pulses with a heartbeat effect. Despite the dramatic framing, you don't actually need to delete the app -- walking into the wall triggers the simulated purge. If the game detects a real reinstall (via Keychain), it also clears the wall.

---

## World 3: Data Corruption

### Level 21 — Voice Command
**Mechanic:** Voice/speech recognition
**Objective:** Speak specific commands to manipulate the game world.
**How to solve:** Three obstacles require three different voice commands:
1. **"BRIDGE"** -- Say "bridge" to extend a bridge across the first gap
2. **"OPEN"** -- Say "open" to unlock a door blocking the middle section
3. **"FLY"** -- Say "fly" to give your character a brief upward impulse, reaching a high platform

Hint labels near each puzzle show which command to say. Speak clearly into your phone's microphone.
**Tips:** The mic indicator pulses when it detects your voice. Each command only needs to be spoken once. The "FLY" command gives a brief upward boost -- time it while near the high platform.
**Easter egg:** Fourth-wall commentary appears after your first spoken command.

---

### Level 22 — Battery Percentage
**Mechanic:** Battery level reading
**Objective:** Discover that the real exit is hidden below platform 5, reachable only at lower battery.
**How to solve:** 10 stepping stones span a chasm, but their visibility depends on your battery percentage. At 100% all 10 are visible, leading to a FAKE exit on the far right. The real exit is hidden BELOW stepping stone #5, only reachable when platforms 6-10 vanish (battery under 60%). The trick: follow the obvious path to discover the fake exit is a dead end, then realize you need fewer platforms to reveal the gap that leads down to the real exit.
**Tips:** A battery display shows your current percentage. There's a drain button for simulator testing. The fake exit is visually marked but doesn't actually trigger level completion. Look for the hidden exit below the midpoint of the stepping stones.

---

### Level 23 — Device Name
**Mechanic:** Device name reading (Settings > General > About > Name)
**Objective:** Prove you're the real player, not the doppelganger.
**How to solve:** The game reads your device's owner name and addresses you personally. A name-labeled door displays your device name and opens when you approach (it recognizes you). A doppelganger NPC (a mirror copy of your character) follows a preset path through the level. The exit door only opens for the "real" player -- you must reach it while the doppelganger is elsewhere. The doppelganger cannot open the name door.
**Tips:** Your device name appears on the door label. The doppelganger mimics your character's appearance but follows a scripted path, not your movements.
**Easter egg:** The game greets you by name with fourth-wall commentary, and a follow-up message appears later.

---

### Level 24 — Storage Space
**Mechanic:** App cache / storage
**Objective:** Dissolve a "data mass" wall by clearing the app's cache.
**How to solve:** A wall of corrupted data blocks labeled "DATA MASS" blocks the path to the exit. The game monitors its cache/storage usage. Clear the app's cache (Settings > General > iPhone Storage > Glitched > Offload App, or use the in-game clear button as a fallback). When storage is freed, the data mass dissolves with a dramatic scatter effect, and the blocker physics body is removed.
**Tips:** The storage display shows current app cache size. A fallback "CLEAR CACHE" button appears in the level for devices/simulators where manual cache clearing isn't practical.
**Easter egg:** Fourth-wall commentary appears about the game feeling "lighter."

---

### Level 25 — Time of Day
**Mechanic:** Real device clock
**Objective:** Play during the right time of day to make enemies sleep, or discover the secret hour.
**How to solve:** The level changes based on your device's actual time:
- **Day (6 AM - 9 PM):** Enemies actively patrol and will kill you. Bright background.
- **Night (9 PM - 6 AM):** Enemies fall asleep (with "zzz" indicators). Dark, peaceful background. Safe to walk past them.
- **Secret Hour (3:33 AM):** A haunted variant with ghost enemies and an eerie glitch overlay.

Play at night for the easiest path (sleeping enemies), or change your device clock. A toggle button allows cycling through modes without changing system time.
**Tips:** The time display shows the current hour and mode. A day/night toggle button lets you test different modes without waiting. Enemies in night mode display sleep animations and are completely harmless.
**Easter egg:** The 3:33 AM "secret hour" variant spawns ghostly entities and applies a glitch overlay to the entire scene.

---

## World 4: Reality Break

### Level 26 — Locale
**Mechanic:** Device language / locale
**Objective:** Unscramble direction signs by changing your device language, revealing the correct path.
**How to solve:** All in-game text on direction signs is scrambled unicode (block characters like `▓░█▒`). The platforms are arranged in two layouts: the visible "wrong" route and a hidden "correct" route. When you change your device's language (Settings > General > Language & Region), the game detects the locale change and:
1. Signs unscramble into readable directions ("JUMP RIGHT", "GO UP", "LEAP LEFT", "ALMOST THERE")
2. Wrong-route platforms fade out
3. Correct-route platforms fade in

Follow the unscrambled directions to reach the exit.
**Tips:** You don't need to change to a specific language -- any language change triggers the unscramble. The hint texts tell you exactly where to jump next.

---

### Level 27 — VoiceOver
**Mechanic:** VoiceOver accessibility feature
**Objective:** Find invisible platforms by enabling VoiceOver, which reads their accessibility labels aloud.
**How to solve:** A wide gap separates the start platform from the exit platform. Five invisible bridge platforms span the gap -- they're always physically solid (you can walk on them) but completely invisible. Enable VoiceOver (Settings > Accessibility > VoiceOver, or triple-click the side button if configured). VoiceOver reads accessibility labels on the invisible platforms saying "STEP HERE," revealing their positions. Platforms also gain a visible shimmer effect when VoiceOver is active.
**Tips:** The platforms have slight vertical variation (alternating heights). After 3+ deaths, a fallback hint system may appear. In debug builds, a test button reveals the platforms. The platforms are always solid -- you can technically walk across them blind if you know where they are.

---

### Level 28 — Share Code
**Mechanic:** System share sheet
**Objective:** Share a displayed code, then type it back on an in-game keyboard to unlock the door.
**How to solve:** A terminal screen displays a randomly generated 6-character code. A share button lets you send this code via the system share sheet (Messages, Notes, AirDrop, etc.). After sharing, an in-game keyboard appears. Type the code back into the input field. When the entered code matches the displayed code, the locked door opens and you can proceed to the exit.
**Tips:** The code uses characters `A-Z` (no I or O) and `2-9` (no 0 or 1) to avoid ambiguity. You can share to yourself (e.g., paste into Notes) and reference it while typing. The share button and keyboard appear on the middle platform.

---

### Level 29 — The Lie
**Mechanic:** None (that's the lie)
**Objective:** Realize the exit was behind you all along.
**How to solve:** The subtitle reads "NO GIMMICK. JUST WALK." The level presents a long, scrolling platformer with moving spike hazards leading to a door labeled "EXIT" far to the right. It looks like a normal level. When you reach the fake exit and touch it, the screen glitches violently -- the game reveals that the real exit was behind you at the start position the whole time. A new platform and door appear near where you spawned. Walk back left to the revealed real exit.
**Tips:** The game tracks your behavior (touches, hesitation, standing still time) throughout the level. The fake exit at x=1150 triggers the reveal sequence. After the glitch, the camera pans back to show the real exit at x=80. All the difficult platforming was a distraction.
**Easter egg:** The level subtitle "NO GIMMICK. JUST WALK." is itself the gimmick. The game is watching whether you hesitate, suspecting a trick.

---

### Level 30 — Credits Finale
**Mechanic:** None (victory lap)
**Objective:** Climb the credits to reach "THANK YOU FOR PLAYING."
**How to solve:** The final level has a dark background (inverted colors). Developer credit lines serve as physical platforms arranged in a vertical zigzag pattern. Climb upward from "GLITCHED - THE FINAL LEVEL" through credits including "CREATED BY: A GLITCHED PRODUCTION," "QA TESTING: YOUR PATIENCE," "BUGS FOUND: TOO MANY," and more. Avoid bug enemies (literal insects) scattered on platforms -- they're the game's last hazards. Reach the top platform "THANK YOU FOR PLAYING" and enter the final exit door.
**Tips:** The credits zigzag left and right as you climb. Bug enemies patrol individual platforms. The world scrolls vertically as you ascend. Stars twinkle in the dark background.
**Easter egg:** Midway through the credits: "YOU'RE STANDING ON THE PEOPLE WHO MADE ME." followed by "SAY THANK YOU." The credit for "BUGS REMAINING" is "THIS ONE" -- the bug enemies are literally the remaining bugs.
