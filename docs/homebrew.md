# Homebrew distribution

Macam can be distributed at no cost through a project-maintained **third-party
tap**, a small Git repository containing a cask recipe. It is independent of
Homebrew's official package repositories. The
[public tap](https://github.com/universetraveller/homebrew-tap) installs the
published [Macam release](https://github.com/universetraveller/macam/releases/latest):

```sh
brew install --cask universetraveller/tap/macam
```

The official `homebrew/cask` repository requires Gatekeeper-compatible Apple
signing/notarization and applies additional acceptance/notability criteria. Our
ad-hoc releases are not eligible for that repository. A third-party tap keeps
distribution free without requiring paid Apple Developer membership. It does not
make the app notarized or remove macOS's first-launch approval requirement.

The generated recipe uses public, versioned downloads from
`universetraveller/macam`. A draft release remains inaccessible to anonymous users
until it is published. Local cask preparation never changes repository visibility
or publishes a release on its own.

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

In the commands below, replace `<version>` with the chosen release version, without
the leading `v`, and `<tap-checkout>` with your local `homebrew-tap` checkout path.

Publish the new version's reviewed app assets, then copy its generated `macam.rb`
over the tap's `Casks/macam.rb`. Check the URL and checksum against the published
ZIP and commit/push the tap update. Keep previous published assets unchanged.
Use the recipe downloaded from the published release: CI's ZIP can differ from a
local build, so the recipe from local preparation is not interchangeable with it.

For example, save that exact published recipe into your tap checkout:

```sh
curl --fail --location \
  "https://github.com/universetraveller/macam/releases/download/v<version>/macam.rb" \
  --output "<tap-checkout>/Casks/macam.rb"
cd "<tap-checkout>"
git diff -- Casks/macam.rb
```

Review the new version, download URL, and SHA-256 before committing and pushing:

```sh
git add Casks/macam.rb
git commit -m "Update Macam to <version>"
git push origin HEAD
```

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

See [verification.md](verification.md) for dated release versions, CI results,
public-download checks, Homebrew install/removal results, and linked machine-readable
reports. Those records identify the versions actually tested; updating a recipe
does not extend their results to a new version. Cross-version upgrades and
first-launch UI approval remain separate checks.
