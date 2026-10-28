#!/usr/bin/env python3
"""Local release preparation. Never tags, pushes, uploads, or publishes."""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")


def run(*args, root=ROOT):
    return subprocess.check_output(args, cwd=root, text=True).strip()


def bundle_info(path):
    with path.open("rb") as stream:
        info = plistlib.load(stream)
    if not VERSION.fullmatch(info["CFBundleShortVersionString"]):
        raise ValueError("Use a numeric X.Y.Z app version.")
    if not re.fullmatch(r"[1-9][0-9]*", info["CFBundleVersion"]):
        raise ValueError("CFBundleVersion must be a positive integer.")
    if info["CFBundleIdentifier"] != "org.macam.Macam":
        raise ValueError("Unexpected bundle identifier.")
    return info


def changelog_notes(text, version):
    sections = re.split(r"(?m)^## ", text)
    for section in sections[1:]:
        heading, _, body = section.partition("\n")
        if heading.split(" — ", 1)[0] == version:
            body = body.strip()
            if not body or not re.search(r"(?m)^- \S", body):
                raise ValueError(f"Add release notes under CHANGELOG.md's {version} heading.")
            return body
    raise ValueError(f"Missing CHANGELOG.md entry for {version}.")


def source_snapshot(root):
    # Tracked files plus explicitly opted-in, nonignored worktree additions.
    listing = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
    )
    files = {}
    for name in sorted(set(os.fsdecode(n) for n in listing.split(b"\0") if n)):
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or ".git" in relative.parts:
            raise ValueError(f"Unsafe source path: {name}")
        path = root / relative
        if path.is_symlink():
            raise ValueError(f"Source snapshots require regular files: {name}")
        if not path.exists():  # A deleted worktree file is absent from its snapshot.
            continue
        if not path.is_file():
            raise ValueError(f"Source snapshots require regular files: {name}")
        mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
        files[name] = (path.read_bytes(), mode)
    if "LICENSE" not in files or "scripts/build.sh" not in files:
        raise ValueError("Source snapshot is missing its license or build script.")
    return files


def snapshot_hash(files):
    entries = [(name, mode, hashlib.sha256(data).hexdigest())
               for name, (data, mode) in sorted(files.items())]
    return hashlib.sha256(json.dumps(entries, ensure_ascii=True).encode()).hexdigest()


def write_source(path, version, files):
    # Stable ordering, modes and timestamps make the source snapshot reproducible.
    with path.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, (data, mode) in sorted(files.items()):
                entry = tarfile.TarInfo(f"macam-{version}/{name}")
                entry.size, entry.mode, entry.mtime = len(data), mode, 0
                archive.addfile(entry, io.BytesIO(data))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def homebrew_cask(root, version, checksum, arch, minimum_macos, dirty):
    if not VERSION.fullmatch(version) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ValueError("Homebrew requires a numeric version and an actual ZIP SHA-256.")
    if arch not in ("arm64", "x86_64"):
        raise ValueError("Unsupported Homebrew architecture.")
    if not re.fullmatch(r"14\.[0-9]+(?:\.[0-9]+)?", minimum_macos):
        raise ValueError("Update the Homebrew OS dependency when changing the app's major OS minimum.")
    template = (root / "packaging/homebrew/macam.rb.in").read_text()
    values = {"VERSION": version, "SHA256": checksum, "ARCH": arch,
              "MINIMUM_MACOS": minimum_macos,
              "REVIEW_COMMENT": "# LOCAL REVIEW ONLY: uncommitted source; do not publish this cask.\n" if dirty else ""}
    for key, value in values.items():
        template = template.replace(f"@{key}@", value)
    if re.search(r"@[A-Z_]+@", template):
        raise ValueError("Unresolved Homebrew template field.")
    return template


def validate_tag(root, tag, version, commit):
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match app version v{version}.")
    if run("git", "rev-parse", f"refs/tags/{tag}^{{commit}}", root=root) != commit:
        raise ValueError("Release tag does not point to the checked-out commit.")


def bump(root, version):
    if not VERSION.fullmatch(version):
        raise ValueError("Use a numeric X.Y.Z version, for example 0.4.0.")
    path = root / "Resources/Info.plist"
    info = bundle_info(path)
    old = info["CFBundleShortVersionString"]
    if tuple(map(int, version.split("."))) <= tuple(map(int, old.split("."))):
        raise ValueError(f"New version must be greater than {old}.")
    changelog = root / "CHANGELOG.md"
    text = changelog.read_text()
    if re.search(rf"(?m)^## {re.escape(version)}(?: — |$)", text):
        raise ValueError("Changelog already contains this version; update the version manually.")
    # Preserve Info.plist formatting and change only the two version values.
    xml = path.read_text()
    for key, value in (("CFBundleShortVersionString", version),
                       ("CFBundleVersion", str(int(info["CFBundleVersion"]) + 1))):
        xml, count = re.subn(rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)",
                             lambda match: match[1] + value + match[2], xml)
        if count != 1:
            raise ValueError(f"Expected one {key} entry.")
    first = re.search(r"(?m)^## ", text)
    if first is None:
        raise ValueError("Changelog needs an existing version section.")
    text = text[:first.start()] + f"## {version} — unreleased\n\n" + text[first.start():]
    path.write_text(xml)
    changelog.write_text(text)
    print(f"Version {old} → {version}; build {int(info['CFBundleVersion']) + 1}.")
    print("Fill in the new CHANGELOG.md section before preparing the release.")


def prepare(root, args):
    info = bundle_info(root / "Resources/Info.plist")
    version = info["CFBundleShortVersionString"]
    notes = changelog_notes((root / "CHANGELOG.md").read_text(), version)
    commit = run("git", "rev-parse", "HEAD", root=root)
    dirty = bool(run("git", "status", "--porcelain", "--untracked-files=all", root=root))
    if dirty and (not args.allow_dirty or args.tag):
        raise ValueError("Commit source changes first, or use --allow-dirty for local review only.")
    if args.tag:
        validate_tag(root, args.tag, version, commit)
    files = source_snapshot(root)
    fingerprint = snapshot_hash(files)
    destination = root / ".build/releases" / f"v{version}"
    if destination.exists():
        raise ValueError(f"{destination} already exists. Move it aside before preparing again.")
    if shutil.which("node") is None:
        raise ValueError("Install Node.js to include browser logic tests in release verification.")
    if dirty:
        print("Preparing a LOCAL REVIEW package from uncommitted files; do not publish it.", flush=True)
    # Always rebuild; a valid signature alone cannot establish source/binary correspondence.
    subprocess.run(["./scripts/test.sh"], cwd=root, check=True)
    built = bundle_info(root / ".build/Macam.app/Contents/Info.plist")
    if built != info:
        raise ValueError("Built app metadata does not match source metadata.")
    binary = root / ".build/Macam.app/Contents/MacOS/Macam"
    arch = run("lipo", "-archs", str(binary), root=root)
    if arch not in ("arm64", "x86_64"):
        raise ValueError(f"Unsupported release architecture: {arch}")
    subprocess.run(["./scripts/package.sh", "--no-build"], cwd=root, check=True)
    signing = subprocess.run(["codesign", "-dv", "--verbose=2", ".build/Macam.app"],
                             cwd=root, check=True, capture_output=True, text=True).stderr
    if "Signature=adhoc" not in signing:
        raise ValueError("This release workflow currently describes ad-hoc signing only. "
                         "Unset MACAM_SIGN_IDENTITY or extend the signing/notarization workflow first.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Only a complete package becomes visible at the final path.
    with tempfile.TemporaryDirectory(prefix=f".v{version}-", dir=destination.parent) as temporary:
        stage = Path(temporary) / f"v{version}"
        stage.mkdir()
        app_name = f"Macam-{version}-{arch}.zip"
        app_zip = stage / app_name
        shutil.copyfile(root / ".build" / app_name, app_zip)
        (stage / "macam.rb").write_text(homebrew_cask(
            root, version, sha256(app_zip), arch, info["LSMinimumSystemVersion"], dirty))
        subprocess.run(["/usr/bin/ruby", "-c", str(stage / "macam.rb")], check=True)
        source_name = f"Macam-{version}-source.tar.gz"
        write_source(stage / source_name, version, files)
        warning = ("**Local review only: contains uncommitted source changes. Do not publish.**\n\n"
                   if dirty else "")
        label = "Apple Silicon" if arch == "arm64" else "Intel (runtime unverified)"
        release_notes = (
            f"# Macam {version} — Mac Audio Mirror\n\nMirror your Mac’s audio.\n\n{warning}"
            f"{notes}\n\n"
            f"## Download and install\n\n"
            f"Download **{app_name}** for **{label}**. Requires macOS "
            f"{info['LSMinimumSystemVersion']} or later. Quit any running Macam, unzip, "
            "and drag Macam.app to Applications. Launch it manually; it starts stopped.\n\n"
            "This build is **ad-hoc signed and not notarized**. macOS may block its first "
            "launch. If you trust this download, try opening it, then use System Settings → "
            "Privacy & Security → Open Anyway. See "
            "[Apple’s instructions](https://support.apple.com/en-us/102445).\n\n"
            "Click Start and allow System Audio Recording. In the receiving app, select "
            "Macam Audio (sometimes labeled Macam Audio (Aggregate)) and grant its input "
            "permission. Original playback and system audio defaults stay unchanged.\n\n"
            f"`{source_name}` contains matching GPL-3.0-only source and build scripts; "
            "GitHub’s automatic Source code archives are not prebuilt apps. "
            f"Verify downloads with `shasum -a 256 -c SHA256SUMS` after downloading all "
            "listed assets, or use the app ZIP’s `.sha256` sidecar.\n\n"
            "`macam.rb` is a checksummed cask recipe for a project-maintained Homebrew "
            "tap. It is not an official Homebrew listing or evidence that a tap is live. "
            "See `docs/homebrew.md` in the matching source for publication steps.\n\n"
            "## Verification and limits\n\n"
            "Local deterministic tests, signature verification, and archive round-trip "
            "checks passed during preparation. They do not establish live audio capture "
            "on the release host. Read `docs/verification.md` and `docs/browser-testing.md` "
            "in the matching source for dated native/browser results and remaining checks. "
            "The runtime deployment target is not a claim of testing every supported OS.\n\n"
            "Macam-specific code is 100% LLM-generated under human direction; credited "
            "third-party adaptations retain their licenses. No warranty.\n"
        )
        (stage / "release-notes.md").write_text(release_notes)
        # Unzip and check the delivered bundle, including its seal and executable mode.
        unpacked = Path(temporary) / "roundtrip"
        subprocess.run(["ditto", "-x", "-k", str(app_zip), str(unpacked)], check=True)
        subprocess.run(["codesign", "--verify", "--strict", str(unpacked / "Macam.app")], check=True)
        restored = unpacked / "Macam.app/Contents/MacOS/Macam"
        if sha256(restored) != sha256(binary) or not os.access(restored, os.X_OK):
            raise ValueError("App archive did not preserve the executable.")
        if snapshot_hash(source_snapshot(root)) != fingerprint:
            raise ValueError("Source changed during preparation. Prepare again from stable source.")
        if run("git", "rev-parse", "HEAD", root=root) != commit:
            raise ValueError("HEAD changed during preparation.")
        manifest = {
            "schemaVersion": 1, "project": "Macam", "version": version,
            "build": info["CFBundleVersion"], "bundleIdentifier": info["CFBundleIdentifier"],
            "architecture": arch, "minimumMacOS": info["LSMinimumSystemVersion"],
            "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "gitCommit": commit, "tag": args.tag, "dirtyWorktree": dirty,
            "sourceSnapshotSHA256": fingerprint,
            "signing": {"kind": "ad-hoc", "notarized": False},
            "buildHost": run("sw_vers", "-productVersion", root=root),
            "sdkVersion": run("xcrun", "--sdk", "macosx", "--show-sdk-version", root=root),
            "swiftVersion": run("xcrun", "swiftc", "--version", root=root),
            "checks": {"deterministicTests": "passed", "archiveRoundTrip": "passed",
                       "signatureVerification": "passed", "liveAudioTestedDuringPreparation": False},
            "sha256": {name: sha256(stage / name)
                       for name in (app_name, source_name, "release-notes.md", "macam.rb")},
        }
        (stage / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (stage / f"{app_name}.sha256").write_text(f"{sha256(app_zip)}  {app_name}\n")
        checksums = "".join(f"{sha256(path)}  {path.name}\n" for path in sorted(stage.iterdir()))
        (stage / "SHA256SUMS").write_text(checksums)
        stage.rename(destination)
    print(f"\nPrepared {destination}")
    print("No tag, upload, or publication was performed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    bump_parser = commands.add_parser("bump", help="Bump app/build versions and open a changelog section")
    bump_parser.add_argument("version")
    prepare_parser = commands.add_parser("prepare", help="Build/test and prepare local release assets")
    prepare_parser.add_argument("--allow-dirty", action="store_true", help="Local review only; include nonignored uncommitted files")
    prepare_parser.add_argument("--tag", help="Require clean source and a matching tag at HEAD (used by CI)")
    args = parser.parse_args()
    try:
        if args.command == "bump":
            bump(ROOT, args.version)
        else:
            prepare(ROOT, args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release preparation failed: {error}\n")


if __name__ == "__main__":
    main()
