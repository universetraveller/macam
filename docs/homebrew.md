# Homebrew distribution

Macam can be distributed at no cost through a project-maintained **third-party
tap**, a small Git repository containing a cask recipe. It is independent of
Homebrew's official package repositories. The first public release and tap are
being prepared; use the README for the current installation status.

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

3. Create a public GitHub repository named `universetraveller/homebrew-tap`.
   Add the recipe at `Casks/macam.rb` and a README identifying it as Macam's
   project-maintained tap. Include Macam's GPL-3.0-only license for the recipe.
   Commit and push the reviewed files. No Apple signing credentials are needed.

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

Local preparation and Ruby/DSL checks are recorded in
[verification.md](verification.md). They do not establish a working public download
or a successful Homebrew install/upgrade/uninstall. The initial local checks took
place while the repository was private and added no tap, trust entry, or application
installation. The repository is now public; publication and real download/install
results are recorded separately as they are completed.
