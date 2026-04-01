# Numara

An accessibility app for people with dyscalculia. Point your camera at a number, equation, or receipt — Numara reads it, explains it in plain language, and speaks the answer through your Ray-Ban glasses speakers. No typing. No math. No stress.

Built by a 16-year-old with a friend in mind who deserves better tools than what exists right now.

---

## What it does

Dyscalculia makes numbers feel like a foreign language. Most "math tools" just solve problems, which doesn't actually help someone who can't read the problem in the first place. Numara is different — it explains, it anchors, it talks. It never solves for you, because the goal is understanding, not answers.

**Camera mode** — point at anything with numbers. Price tag, receipt, quiz question, equation on a whiteboard. Numara identifies what it's looking at and responds appropriately.

**Price / real world** — says the number plainly, then gives a real-world anchor. "$24.99 — about the cost of three Starbucks drinks." That's it. Short and useful.

**Equation mode** — reads the equation out loud naturally, then explains what each part means in plain English. It does not solve it. The equation stays large on screen so you can reference it while listening.

**Voice follow-up** — say "hey numara" through your Ray-Ban mic and ask anything. "What does squared mean?" "Say that again." "What is x?" No typing, no tapping — designed specifically for in-class use where pulling out your phone to type is disrespectful to everyone in the room.

**Silence timeout** — 3 seconds of silence and listening stops automatically, plays a soft chime through the glasses speakers, and returns to the result screen. Nothing to tap, nothing to dismiss.

**Temple tap** — single tap on the Ray-Ban temple triggers listening from a result screen, fires the camera shutter from the capture screen. The phone can stay in your pocket.

---

## Hardware

### Phase 1 — available now
- iPhone (camera, display, processing)
- Ray-Ban Meta smart glasses Gen 1 or Gen 2 (speakers + temple tap over Bluetooth)
- No Ray-Ban SDK required — temple tap uses standard iOS Bluetooth audio events

### Phase 2 — in progress
- Ray-Ban Wearables Device Access Toolkit (glasses camera feed)
- Requires Meta Managed Account at wearables.developer.meta.com

### Phase 3 — hardware prototype
- Custom EMG wristbands built with MyoWare 2.0 sensors + ESP32-C3 microcontrollers
- Gesture-based input — flex, hold, double flex — transmitted over Bluetooth LE
- Companion gesture registry app for per-user EMG calibration
- Two units, one per wrist
- Hardware designed in collaboration with Skyline High School robotics club

### Phase 4 — when Meta opens it
- Ray-Ban Display HUD output (currently locked to third-party developers)
- Neural Band gesture integration

---

## Tech stack

| Layer | Tool |
|---|---|
| Language | Swift / SwiftUI |
| Camera + capture | AVFoundation |
| AI vision + reasoning | Claude API (claude-sonnet-4-6) |
| Speech output | AVSpeechSynthesizer |
| Speech input | SFSpeechRecognizer |
| Remote commands | MPRemoteCommandCenter |
| Glasses integration | Standard iOS Bluetooth audio profiles |
| Ray-Ban camera (Phase 2) | Meta Wearables Device Access Toolkit |
| EMG wristband (Phase 3) | MyoWare 2.0 + ESP32-C3 over BLE |

---

## Project structure

```
Numara/
├── ClaudeService.swift      — API calls, system prompt, follow-up conversation
├── CameraViewModel.swift    — app state, capture, speech I/O, temple tap, silence timeout
├── ContentView.swift        — all screens: capture, result (price + equation), listening, timeout
└── README.md
```

---

## Setup

1. Clone the repo
2. Open in Xcode (requires macOS, Xcode 15+)
3. Add three keys to `Info.plist`:
   - `NSCameraUsageDescription`
   - `NSSpeechRecognitionUsageDescription`
   - `NSMicrophoneUsageDescription`
4. Set your Anthropic API key — for development, add `CLAUDE_API_KEY` as an environment variable in your Xcode scheme (Product → Scheme → Edit Scheme → Run → Environment Variables). For production, move to Keychain.
5. Run on a physical iPhone — camera doesn't work in simulator

Get an API key at console.anthropic.com. A few dollars of credit will last a long time for testing.

---

## Why open source

This tool is for people who need it, not people who can pay for it. Keeping it free and open means anyone can use it, audit it, improve it, or build on it — and nobody has to justify the cost of an accessibility tool to a parent or a school district.

If you have dyscalculia and want to test it, open an issue. If you're a developer who wants to contribute, PRs are welcome. If you're a school or district interested in deploying it, reach out.

---

## Roadmap

- [ ] Phase 1 — iPhone + Ray-Ban speakers + temple tap
- [ ] Voice calculator mode — standalone math via wake word, no scan required
- [ ] Phase 2 — glasses camera feed via Meta Wearables SDK
- [ ] Gesture registry app — EMG calibration companion
- [ ] Phase 3 — custom EMG wristbands
- [ ] App Store release (free, always)
- [ ] Phase 4 — Ray-Ban Display HUD + Neural Band

---

## Built with

- [Claude API](https://anthropic.com) — vision + language reasoning
- [Meta Wearables Device Access Toolkit](https://developers.meta.com/wearables) — Ray-Ban integration (Phase 2+)
- [MyoWare 2.0](https://myoware.com) — EMG sensing (Phase 3)
- [Skyline High School Robotics Club](https://skylinehigh.issaquah.wednet.edu) — hardware prototyping

---

## License

[Numara](https://github.com/JJansen09/Numara) © 2026 by [Jacob Jansen](https://github.com/JJansen09) is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 
![CC](https://mirrors.creativecommons.org/presskit/icons/cc.svg)![BY](https://mirrors.creativecommons.org/presskit/icons/by.svg)![NC](https://mirrors.creativecommons.org/presskit/icons/nc.svg)![SA](https://mirrors.creativecommons.org/presskit/icons/sa.svg)
