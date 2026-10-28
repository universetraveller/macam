# Homebrew distribution

Macam can be distributed at no cost through a project-maintained **third-party
tap**, a small Git repository containing a cask recipe. It is independent of
Homebrew's official package repositories. The
[public tap](https://github.com/universetraveller/homebrew-tap) installs the
published [Macam 0.3.0 release](https://github.com/universetraveller/macam/releases/tag/v0.3.0):

```sh
brew install --cask universetraveller/tap/macam
```

The official `homebrew/cask` repository requires Gatekeeper-compatible Apple
signing/notarization and applies additional acceptance/notability criteria. Our
ad-hoc releases are not eligible for that repository. A third-party tap keeps
distribution free without requiring paid Apple Developer membership. It does not
make the app notarized or remove macOS's first-launch approval requirement.

The maintainer made `universetraveller/macam` public and authorized release/tap
publication on 2026-10-28. The generated recipe uses that repository's public
versioned release downloads. A draft release remains inaccessible to anonymous
users until it is published. Local cask preparation never changes repository
visibility or publishes a release on its own.

See Homebrew's [cask acceptance policy](https://docs.brew.sh/Acceptable-Casks),
[tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), and
[tap trust model](https://docs.brew.sh/Tap-Trust).

## Prepare and publish

1. Follow [Preparing releases](releasing.md) to commit the final source, prepare
   the matching version tag and app/source assets, and publish the reviewed GitHub
   release. The repository and download must be public for unauthenticated users.
   A private repository or draft release does not provide a public cask download.

2. Use the generated `macam.rb` from that **exact release**. It contains the app
   ZIP's actual SHA-256, versioned GitHub download URL, architecture restriction,
   app name, minimum macOS requirement, uninstall-quit action, and launch guidance.
   A recipe marked LOCAL REVIEW ONLY must be regenerated from committed source.

3. Update `Casks/macam.rb` in the existing public
   `universetraveller/homebrew-tap` repository. Keep its project-maintained tap
   README and GPL-3.0-only license with the recipe. Commit and push the reviewed
   files. No Apple signing credentials are needed.

4. Test the **published** tap and app download before advertising installation:

   ```sh
   brew install --cask universetraveller/tap/macam
   ```

   The short tap name resolves to `universetraveller/homebrew-tap`. Current
   Homebrew trusts the specifically named cask when installing by its full name;
   a tap-wide trust grant is unnecessary. Before replacing a manually installed
   Macam in Applications, quit it and move the old copy aside if Homebrew reports
   that an app already exists there.

5. Open Macam manually. It starts stopped. Test first-launch approval, system-audio
   permission, and capture in the receiving app. Macam remains ad-hoc signed and
   not notarized: macOS may require an opening attempt followed by
   **System Settings → Privacy & Security → Open Anyway** if the user trusts it.
   Keep quarantine intact; the recipe performs no security override or auto-launch.

The recipe's OS dependency covers Sonoma and later, matching Homebrew's
major-release dependency model. The bundle and installation caveat specify the
actual **14.2+** minimum; installing files on 14.0/14.1 would not make the app runnable.
Current prepared downloads target Apple Silicon only. Installed app preferences
remain on uninstall. Only Macam itself is asked to quit; no audio settings,
unrelated applications, login services, drivers, or permissions are changed.

## Each new release

Publish the new version's reviewed app assets, then copy its generated `macam.rb`
over the tap's `Casks/macam.rb`. Check the URL and checksum against the published
ZIP and commit/push the tap update. Keep previous published assets unchanged.
Users can then quit Macam and run:

```sh
brew update
brew upgrade --cask universetraveller/tap/macam
```

To uninstall the Homebrew-managed copy:

```sh
brew uninstall --cask universetraveller/tap/macam
```

No background updater is added to Macam. Upgrades remain user-initiated Homebrew
operations. Quit removes Macam's temporary audio input through its normal cleanup.

## Verification status

The tag-triggered GitHub release workflow and Checks passed for 0.3.0. Anonymous
download matched the reviewed ZIP checksum. Homebrew 7.0.11 installed the public
cask into a temporary app directory and uninstalled it successfully. Its binary
matched the release, strict signature verification passed, and quarantine remained
present. The upgrade command recognized 0.3.0 as current; an upgrade between
different versions has not yet been tested.

Gatekeeper assessment rejected the ad-hoc build, as expected; no security override
was performed and the first-launch UI approval remains a manual step. The temporary
test installation was removed. The project tap and cask-specific trust entry remain
available locally. See [verification.md](verification.md) and the
[machine-readable release check](verification-release-0.3.json) for exact evidence.
