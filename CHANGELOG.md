# Changelog

## 0.2.0 — unreleased

- Playback exclusion is optional and Off by default. Macam itself stays excluded.
- Support Chrome → Chrome, Safari → Safari, Chrome → Safari, and Safari → Chrome.
  All four routes passed user-observed tone/input checks on macOS 27.0.1.
- Ignore the old implicit Chrome receiver preference on upgrade while retaining
  source choices. Use Playback exclusion to opt in again.
- Add `--exclude`; retain `--receiver` as a legacy explicit-exclusion alias.
- Add browser-neutral receiver diagnostics and an offline stereo tone source;
  open either page in Chrome, Safari, or the default browser from Macam's menu.
- Feature-detect Web Audio, permission queries, and MediaRecorder formats.
- Add four-route selection/migration tests and separate Chromium/Safari API mocks.
- Add contributor, support, security, issue/PR, packaging, and CI documentation.

## 0.1.0 — prototype

- Native unmuted process tap and public Macam Audio stereo input.
- Menu-bar lifecycle, source discovery, meter, exact-journal crash recovery, and
  Command Line Tools build/signing.
- Initial native and Chrome capture/reconnection verification.
