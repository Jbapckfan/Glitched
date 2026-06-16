# Glitched App Store Connect Listing

Research notes:
- Apple App Store Connect lists promotional text and keyword metadata in the platform-version information reference, with keywords capped at 100 bytes and no need to duplicate app name/company name terms: https://developer.apple.com/help/app-store-connect/reference/platform-version-information
- Apple App Store Connect lists app name at 30 characters max and subtitle at 30 characters max: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Apple's Games browse page includes Puzzle, Adventure, Indie, and related game groupings: https://apps.apple.com/us/iphone/grouping/25180
- App previews can be up to 30 seconds and should show real app/gameplay footage: https://developer.apple.com/app-store/app-previews/

## Recommended Metadata

App name:
Glitched

Subtitle, 30 characters max:
Your phone is the puzzle

Character count: 24

Promotional text:
A puzzle-platformer where the controller is your iPhone: rotate it, leave the app, take screenshots, plug in power, and listen when the OS starts talking back.

Character count: 159

Keyword field, 100 bytes max:
puzzle,platformer,iphone,tilt,mic,darkmode,screenshot,meta,indie,brain,escape,sensors,physics,phone

Byte count: 99

Primary category:
Games

Primary game subcategory:
Puzzle

Secondary category/subcategory:
Games / Adventure

Rationale:
Puzzle is the strongest intent match: every level is a compact mechanical riddle. Adventure is the secondary browse fit because the campaign has worlds, narrator beats, bosses, and a finale rather than only isolated brainteasers.

## Full Description

Your phone is not just where Glitched runs. Your phone is the controller.

Glitched is a black-on-white line-art puzzle-platformer where every level is solved by using a real iOS feature. Rotate the device to reshape the world. Blow into the mic. Take a screenshot to freeze the game. Toggle Dark Mode and watch the whole level recolor. Plug in your charger. Leave the app and come back. Use Face ID, VoiceOver, AirDrop, the flashlight, multi-touch, and more.

You play as Bit, a small line-art character trapped inside a broken operating system. The OS notices what you do. It comments on your settings. It questions your choices. It sometimes lies.

What starts as a clean little platformer becomes a conversation between the game and the device in your hands.

Features:
- 34 handcrafted levels across 6 worlds
- World 0 and World 1 free, including 11 levels that show the core idea
- One Full Game unlock for Worlds 2-5
- Real iOS mechanics used as puzzle inputs
- Line-art platforming with physics-based juice
- Dry fourth-wall narrator voice
- Accessibility and fallback controls for hardware-gated mechanics
- iPhone and iPad support
- No ads

Worlds:
- Boot
- Hardware Awakening
- Control Surface
- Data Corruption
- Reality Break
- System Override

Glitched is built for the moment when someone next to you asks, "Wait, did the game just make you change your phone settings?"

Yes. It did.

## What's New

Launch version.

34 levels of device-feature puzzle-platforming: screenshots, Dark Mode, charging, brightness, notifications, clipboard, Focus, Low Power Mode, Face ID, VoiceOver, AirDrop, flashlight, multi-touch, and more.

## Age Rating Questionnaire Draft

Use this as the App Store Connect answer baseline. Reconfirm against the final binary before submission.

- Cartoon or fantasy violence: Infrequent/Mild
  - Reason: line-art hazards, falls, spikes, lasers, and non-realistic character deaths.
- Realistic violence: None
- Prolonged graphic or sadistic realistic violence: None
- Profanity or crude humor: None
- Mature/suggestive themes: None
- Horror/fear themes: Infrequent/Mild
  - Reason: unsettling OS narrator, glitch/meta moments, no gore.
- Medical/treatment information: None
- Alcohol, tobacco, or drug use/references: None
- Simulated gambling: None
- Contests: None
- Unrestricted web access: No
- User-generated content: No
- Messaging/chat/social features: No
- Gambling and contests: No
- In-app purchases: Yes
  - One non-consumable Full Game unlock.
- Ads: No
- Location access: No

Expected rating target:
9+ is the conservative target because of mild cartoon/fantasy violence and mild fear themes. It may resolve lower depending on App Store Connect's current questionnaire weighting, but do not force lower with inaccurate answers.

## Alternative Name / Subtitle Options

1. Name: Glitched
   Subtitle: The phone is the controller
   - Subtitle character count: 27
   - Rationale: Slightly stronger marketing line than "Your phone is the puzzle"; less keyword dense.

2. Name: Glitched: Phone Puzzles
   Subtitle: Use the real device
   - Name character count: 23
   - Subtitle character count: 19
   - Rationale: Better search clarity for "puzzle" and "phone", but less elegant and less premium.

3. Name: Glitched OS
   Subtitle: Puzzle with your iPhone
   - Name character count: 11
   - Subtitle character count: 23
   - Rationale: Emphasizes the living operating-system premise. Risk: "OS" could imply a utility app rather than a game.

## Metadata QA Checklist

- Do not mention features that are not in the binary.
- Keep "World 0+1 free; Worlds 2-5 via Full Game IAP" consistent across listing, screenshots, and paywall.
- Do not imply real device settings are permanently changed. The game reacts to supported iOS features and provides fallback controls where needed.
- Avoid "horror game" positioning; the tone is unsettling, not horror.
