# Preparing Macam releases

Macam releases contain a normal `.app` in a ZIP. They do not install a driver,
change audio settings, add a login service, or require Xcode. The current workflow
prepares Apple Silicon (`arm64`) assets with an ad-hoc signature and **no
notarization**. The runtime target is macOS 14.2+; tested systems and manual-check
limits remain in [verification.md](verification.md).

## Placeholders and version metadata

Replace angle-bracketed placeholders before running the commands in this guide:

| Placeholder | Meaning |
| --- | --- |
| `<version>` | The chosen numeric `X.Y.Z` version, without a leading `v` |
| `<arch>` | The app archive's architecture; the current CI release target is `arm64` |

The app version and integer build number live in `Resources/Info.plist`. The bump
helper updates both and opens a new changelog section. Build/package scripts and
CI derive their versions from that metadata; generic documentation examples do
not need editing for each release. Keep historical changelog and verification
versions tied to the releases they actually describe.

## Prepare the current version locally

Use macOS with Command Line Tools, a macOS 26+ SDK, Git, and Node.js. Python 3 is
provided by Command Line Tools; no pip/npm packages are needed. Quit Macam before
building. Run from the repository root:

```sh
./scripts/prepare-release.sh
```

The default requires committed source. For reviewing current, uncommitted work:

```sh
git status --short
./scripts/prepare-release.sh --allow-dirty
```

Review mode includes tracked files and nonignored additions from the worktree,
including documentation; review that list before packaging. It excludes `.git`
and ignored build output. Its notes and manifest explicitly mark the package as
**local review only**. Commit the final changes and prepare again before publishing.
The tool does not tag, push, upload, publish, or change the app version.

Output is `.build/releases/v<version>/`:

| File | Purpose |
| --- | --- |
| `Macam-<version>-<arch>.zip` | Locally signed Macam.app for the declared architecture |
| `Macam-<version>-<arch>.zip.sha256` | Check the app download on its own |
| `Macam-<version>-source.tar.gz` | Matching GPL source, notices, documentation, and build scripts |
| `release-notes.md` | Changelog entry, installation, signing status, and verification limits |
| `release-manifest.json` | Version/build, architecture, commit, worktree state, source fingerprint, toolchain, and hashes |
| `macam.rb` | Homebrew cask pinned to the matching app ZIP and its SHA-256 |
| `SHA256SUMS` | SHA-256 checksums for every other file in the directory |

The app is rebuilt by the deterministic test suite. Preparation then verifies
bundle/source metadata, signs/checks the app, packages it, extracts the ZIP, checks
the extracted signature and executable, and checks that source did not change
during preparation. Source archive ordering, timestamps, and executable modes are
stable. This is source provenance and package verification, **not a reproducible
binary-build guarantee**. The manifest does not claim a live audio test.

Existing release directories are never overwritten. Move a previous local directory
aside before preparing the same version again. `scripts/package.sh [--no-build]`
remains a lightweight app-ZIP tool; use `prepare-release.sh` for a full release.
For compiler-cache cleanup or removal of generated output, see
[Clean build caches](../README.md#clean-build-caches). Cleaning is optional for a
version bump: normal builds compile the app again and copy the current Info.plist.

## Each new version

1. Bump the app version and integer build number, and start a changelog section:

   ```sh
   xcrun python3 scripts/release.py bump "<version>"
   ```

   Fill in its new `CHANGELOG.md` section; an empty section prevents preparation.
   Keep it marked unreleased until publication. Review the working tree and commit
   the version, notes, and intended source/documentation changes. Release
   preparation requires a clean worktree. Push that source commit before its tag.

2. Quit Macam and run `./scripts/prepare-release.sh`. Check `SHA256SUMS`, read the
   generated notes/manifest, and test the extracted app. Record actual native and
   browser checks in the verification documentation; rerun relevant audio checks
   for audio changes. Automated release checks do not replace these observations.

3. When ready to prepare the hosted draft, create and push a matching tag yourself:

   ```sh
   git tag -a "v<version>" -m "Macam <version>"
   git push origin "v<version>"
   ```

   These commands are maintainer actions, not actions taken by the preparation
   script. The [release workflow](../.github/workflows/release.yml) runs on version
   tag pushes. It checks tag/version/HEAD agreement, rebuilds/tests on an arm64
   macOS runner, retains the assets for 14 days as an Actions artifact, then creates
   a **draft GitHub release** using `gh release create --draft --verify-tag`.
   The build job has read access; only the draft job has repository-content write
   access. No extra signing secrets or personal access token are needed.

4. Review the draft's app/source assets, checksums, signing caveat, and verification
   claims. Download and test the actual hosted ZIP. Publish the draft explicitly
   in GitHub when satisfied; update the changelog's release date afterward.

5. Follow [Homebrew: Each new release](homebrew.md#each-new-release) to download
   the published release's `macam.rb` into the shared tap, review its version and
   checksum, and commit/push that separate repository. Use the cask from the
   published CI assets, whose ZIP can differ from your local build. The Macam
   tag workflow prepares the recipe; the tap update is a separate maintainer step.

An existing release makes draft creation fail; the workflow does not replace its
assets or publish it. Its prepared Actions artifact remains available. Review that
artifact and the existing draft manually. Never silently replace a published
version; issue a new version for changed source. A draft/failed workflow is not
a public download. Users need a published release asset.

If GitHub automation is unavailable, prepare from committed source, create the
matching local tag, and run:

```sh
./scripts/prepare-release.sh --tag "v<version>"
```

Push the source and tag, then use GitHub's Releases interface to create a **draft**
from that tag. Attach every file from `.build/releases/v<version>/`, and paste
`release-notes.md` into its description. Review and publish separately.

## Signing and installation

Ad-hoc signing verifies the bundle's local seal; it does not establish a Developer
ID identity or satisfy notarization. See the README's
[download installation steps](../README.md#download-a-release) and
[Apple's instructions](https://support.apple.com/en-us/102445) for the possible
first-launch block and Privacy & Security → Open Anyway. Do not tell users to
disable Gatekeeper globally.

`MACAM_SIGN_IDENTITY` remains available for ordinary local builds. Release
preparation currently rejects a non-ad-hoc identity so its generated instructions
cannot misstate Developer ID/notarization status. Supporting notarized releases
later requires an explicit identity, credentials, signing policy, notarization,
stapling/validation, and corresponding documentation changes. This workflow does
not claim those steps happened.

Include matching source, `LICENSE`, and `THIRD_PARTY_NOTICES.md` with every binary
release. Keep FineTune attribution while its adaptations remain. The source
snapshot lets recipients rebuild without relying on a future source offer.

## Homebrew

Each preparation also generates `macam.rb` from the app ZIP's actual checksum and
bundle metadata. It is included in the manifest and SHA256SUMS. A dirty-source
review recipe is labeled accordingly; publish only the recipe from the clean,
final release. The existing GitHub draft workflow attaches it with the other assets.

Publishing a Macam release does not publish or update a tap. Follow
[Homebrew distribution](homebrew.md) to put the matching recipe into a public tap
and verify the live download before advertising its install command.
