# Macam — Mac Audio Mirror

- App/project: **Macam**; expanded name: **Mac Audio Mirror**; virtual input: **Macam Audio**; tagline: **Mirror your Mac’s audio.**
- Build a free, open-source, local-only macOS menu-bar utility using Swift, AppKit, Core Audio, Command Line Tools, and `swiftc`. No Xcode IDE requirement without a concrete reason. Package and locally sign a normal app with a stable bundle ID.
- Mirror whole-system or selected-application audio into a stereo input for another app. Original playback must continue through existing output devices.
- Never change default input/output/system-output devices, device volumes, mute state, normal volume controls, or headphone switching, even temporarily. Never mute and replay original audio. Only create/remove Macam-owned audio resources.
- Manual launch; no login item, networking, analytics, update checks, accounts, or built-in recording feature. Minimal Start/Stop, source selection, status, and meter.
- Investigate option A first: unmuted process tap plus public aggregate input. Public visibility is a hypothesis, not proof of recordable audio. Verify from a separate receiving process/application.
- If A fails after focused testing, prefer native capture into explicitly selected BlackHole 2ch (B), without changing default output. Explain A/B inadequacy before implementing a custom HAL driver (C).
- Capture Chrome → Chrome, Safari → Safari, Chrome → Safari, and Safari → Chrome. Playback exclusion is optional and OFF by default; always exclude Macam itself. Never assume a receiver, browser, or personal setup. Process taps select applications/helpers, not browser tabs; explain this limit and avoid monitoring feedback in same-browser use.
- Playback exclusions support multiple checked applications; preserve existing explicit exclusions on migration. Keep the menu compact: a single description line, Start/Stop with adjacent status, source/exclusion controls, About, and Quit. Diagnostic tools belong in About.
- README must disclose that Macam's code is 100% LLM-generated under human direction, with human testing/review distinguished from code authorship. Explain differences from related products using primary sources. Preserve FineTune attribution wherever adapted code remains; do not imply all generated code is original.
- Handle process/helper identity changes, optional playback exclusion, device/rate changes, sleep/wake, real-time safety, cleanup, and crash recovery. Never destroy unrelated resources.
- Maintain a public open-source project: browser-neutral UI/test tools, portable scripts, contributor guidance, changelog, CI checks, and an explicit support/verification matrix. Keep local machine observations in verification records, not product defaults.
- Use current Apple docs and targeted FineTune source inspection to resolve concrete gaps. FineTune is GPL-3.0; preserve attribution for copied/adapted code and use compatible licensing.
- Keep `docs/implementation-plan.md` current with hypotheses, decisions, evidence, and remaining uncertainties. Record actual build/runtime results; never equate source review with tested behavior.
- Verify independent input enumeration/non-silent capture, unchanged settings, normal playback and switching, longer-run drift/dropouts, and cleanup/restart. Ask for the target receiving app when interoperability testing needs it.
