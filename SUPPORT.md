# Support and compatibility reports

Use the repository issue tracker for bugs and feature requests. This is an
experimental community project without a support SLA.

For an audio issue, include:

- Macam version, macOS version, architecture, and browser/application versions.
- Source application, receiving application, Whole system/selected sources, and
  the explicit playback-exclusion setting.
- Whether the Macam meter moves and whether the receiver sees Macam Audio.
- The failing route, permission prompts, exact error, and minimal reproduction.
- Whether Start/Stop, receiver restart, output switching, or sleep triggered it.

The bundled Browser Audio Tests pages work offline and expose device/permission
diagnostics. Follow `docs/browser-testing.md` for Chrome/Safari route results.
An anonymous input placeholder can reflect browser permission exposure; it does
not establish that the native device is missing.

Sanitize local paths and device identifiers before posting diagnostic snapshots.
Audio samples are usually unnecessary; prefer the quiet bundled tone and text
measurements. Security issues should follow `SECURITY.md`.
