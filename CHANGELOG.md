# Changelog

## 0.3.1 — unreleased
- Update all hardcoded entries in reusable instructions to use placeholders
- Test releasing manually 

## 0.3.0 — 2026-10-28

- Prepare a checksummed Homebrew cask with each release for a project-maintained
  tap; document publication, upgrades, and the ad-hoc signing limitations.
- Add release-download installation instructions and repeatable release preparation:
  versioned app/source archives, checksums, release notes, provenance, and a
  tag-triggered GitHub draft-release workflow.
- Select multiple playback exclusions independently; Clear all restores Off.
- Preserve explicit 0.2 exclusions on migration. Repeated `--exclude` flags add
  applications; `--exclude none` clears earlier selections.
- Use a one-line menu heading and place status beside Start/Stop. Click status for
  full details. Keep the meter and source/exclusion controls in the main menu.
- Move browser diagnostics, test-tone tools, and permission help into About Macam.
- Rewrite the README with a prominent 100% LLM-generated code disclosure,
  primary-source comparisons, and focused FineTune adaptation/license credit.
- Add AppKit component rendering for visual review without screen capture.

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
