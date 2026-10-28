# FineTune

Macam's process/helper discovery and lifecycle implementation were informed by
targeted inspection of [FineTune](https://github.com/ronitsingh10/FineTune),
Copyright (C) 2026 Ronit Singh, licensed under GNU GPL version 3.

Inspected revision: `2285279d36d3f8115c1c2d4aecd904f1bdf96a51`.
The guarded responsibility lookup and ancestry/helper grouping in
`Sources/Realtime.c` and `Sources/Processes.swift` are adaptations of the direction
in `FineTune/Audio/Monitors/AudioProcessMonitor.swift`. Attribution is retained
here and in the source. Macam is distributed under GPL-3.0-only; see `LICENSE`.

Other targeted references were `ProcessTapController.swift`, `AudioEngine.swift`,
`TapResources.swift`, and `OrphanedTapCleanup.swift` in `FineTune/Audio/Engine/`.
Macam uses a different audio path: a public unmuted tap-only aggregate, no replay
or processing, no default-device/volume management, and exact journaled resource
ownership instead of name-prefix cleanup. No FineTune binary or dependency is
bundled. Apple framework calls use the installed SDK; Apple documentation is
linked in `docs/implementation-plan.md`.
