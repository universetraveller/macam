# Contributing to Macam

Contributions, reproducible bug reports, browser compatibility results, and
documentation fixes are welcome. Discuss substantial architecture changes in an
issue before implementing them. Small fixes can be submitted directly as pull requests.

## Local workflow

1. Read `AGENTS.md` for the playback and ownership requirements.
2. Use macOS with Command Line Tools and a macOS 26+ SDK. No Xcode project is needed.
3. Quit running Macam before rebuilding. Run `./scripts/test.sh` for deterministic
   checks. Node.js enables browser API mocks; no npm dependencies are required.
4. For audio changes, run the native integration suite with a playing source and
   follow `docs/browser-testing.md`. Record permissions, OS/browser versions,
   source/exclusion choices, actual results, and remaining untested cases.
5. Explain the concrete problem, resulting behavior, and relevant verification in
   the pull request. Distinguish source inspection, mocked tests, and runtime tests.

Use Swift/AppKit for the control path and small C functions for real-time work.
Callbacks must not allocate, lock, log, query properties, dispatch work, or call UI
or Objective-C APIs. Shared callback/UI state needs appropriate synchronization.
Source/exclusion updates must preserve original playback and modify only owned taps.

Never change default devices, volumes, mute state, or hardware routing as a
workaround. Never mute and replay original audio. New dependencies, driver
installation, networking, or persistent services require explicit design discussion.

Keep tests focused on meaningful behavior: routing/isolation, real-time formats,
ownership, lifecycle, and browser compatibility. Do not label API mocks as Safari
or Chrome runtime verification. CI does not have interactive audio permission.

## Project conduct and licensing

Be respectful and specific. Critique behavior and code; avoid personal attacks,
harassment, or sharing other people's private recordings or identifiers.

Contributions are made under GPL-3.0-only. Preserve copyright/license notices and
document copied or adapted third-party code in `THIRD_PARTY_NOTICES.md`. Do not
include signing identities, credentials, personal audio, or local build artifacts.
