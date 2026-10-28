"""Release invariants: source fidelity, version/tag consistency, and notes."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Resources").mkdir()
        (self.root / "scripts").mkdir()
        (self.root / "packaging/homebrew").mkdir(parents=True)
        (self.root / "packaging/homebrew/macam.rb.in").write_bytes(
            (release.ROOT / "packaging/homebrew/macam.rb.in").read_bytes())
        original = release.ROOT / "Resources/Info.plist"
        (self.root / "Resources/Info.plist").write_bytes(original.read_bytes())
        (self.root / "scripts/build.sh").write_text("#!/bin/bash\nexit 0\n")
        (self.root / "scripts/build.sh").chmod(0o755)
        (self.root / "LICENSE").write_text("test license\n")
        (self.root / ".gitignore").write_text(".build/\n")
        self.version = release.bundle_info(original)["CFBundleShortVersionString"]
        (self.root / "CHANGELOG.md").write_text(f"# Changelog\n\n## {self.version} — unreleased\n\n- Current change.\n\n## 0.0.1 — prototype\n\n- Old change.\n")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def initialize_git(self):
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("-c", "user.name=Release Tests", "-c", "user.email=release@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture")

    def test_changelog_is_scoped_and_requires_actual_notes(self):
        text = (self.root / "CHANGELOG.md").read_text()
        self.assertEqual(release.changelog_notes(text, self.version), "- Current change.")
        with self.assertRaisesRegex(ValueError, "Missing"):
            release.changelog_notes(text, "8.0.0")
        with self.assertRaisesRegex(ValueError, "Add release notes"):
            release.changelog_notes("## 8.0.0 — unreleased\n\n## 0.0.1\n- Old", "8.0.0")

    def test_bump_preserves_metadata_and_increments_build(self):
        before = release.bundle_info(self.root / "Resources/Info.plist")
        next_version = f"{int(self.version.split('.')[0]) + 1}.0.0"
        with contextlib.redirect_stdout(io.StringIO()):
            release.bump(self.root, next_version)
        after = release.bundle_info(self.root / "Resources/Info.plist")
        self.assertEqual(after.pop("CFBundleShortVersionString"), next_version)
        self.assertEqual(int(after.pop("CFBundleVersion")), int(before["CFBundleVersion"]) + 1)
        before.pop("CFBundleShortVersionString")
        before.pop("CFBundleVersion")
        self.assertEqual(after, before)
        with self.assertRaisesRegex(ValueError, "Add release notes"):
            release.changelog_notes((self.root / "CHANGELOG.md").read_text(), next_version)
        with self.assertRaisesRegex(ValueError, "greater"):
            release.bump(self.root, self.version)
        with self.assertRaisesRegex(ValueError, "numeric"):
            release.bump(self.root, "v100.0.0")

    def test_snapshot_tracks_worktree_and_preserves_source_modes(self):
        self.initialize_git()
        baseline = release.snapshot_hash(release.source_snapshot(self.root))
        (self.root / "LICENSE").write_text("modified license\n")
        (self.root / "new-file.txt").write_text("new source\n")
        (self.root / ".build").mkdir()
        (self.root / ".build/secret").write_text("must not be packaged\n")
        files = release.source_snapshot(self.root)
        self.assertNotEqual(release.snapshot_hash(files), baseline)
        self.assertEqual(files["LICENSE"][0], b"modified license\n")
        self.assertIn("new-file.txt", files)
        self.assertFalse(any(name.startswith((".git/", ".build/")) for name in files))
        first, second = self.root / "one.tar.gz", self.root / "two.tar.gz"
        release.write_source(first, self.version, files)
        release.write_source(second, self.version, files)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with tarfile.open(first) as archive:
            for name, (data, mode) in files.items():
                member = archive.getmember(f"macam-{self.version}/{name}")
                self.assertEqual(archive.extractfile(member).read(), data)
                self.assertEqual(member.mode, mode)
        (self.root / "new-file.txt").unlink()
        (self.root / "new-file.txt").symlink_to("/no-such-release-file")
        with self.assertRaisesRegex(ValueError, "regular files"):
            release.source_snapshot(self.root)

    def test_tag_must_match_version_and_commit(self):
        self.initialize_git()
        commit = self.git("rev-parse", "HEAD")
        tag = f"v{self.version}"
        self.git("-c", "tag.gpgsign=false", "tag", tag)
        release.validate_tag(self.root, tag, self.version, commit)
        with self.assertRaisesRegex(ValueError, "does not match"):
            release.validate_tag(self.root, "v90.0.0", self.version, commit)
        with self.assertRaisesRegex(ValueError, "checked-out commit"):
            release.validate_tag(self.root, tag, self.version, "0" * 40)

    def test_dirty_source_is_opt_in_and_forbidden_for_tagged_release(self):
        self.initialize_git()
        (self.root / "LICENSE").write_text("uncommitted change\n")
        args = argparse.Namespace(allow_dirty=False, tag=None)
        with self.assertRaisesRegex(ValueError, "Commit source changes"):
            release.prepare(self.root, args)
        args.allow_dirty, args.tag = True, f"v{self.version}"
        with self.assertRaisesRegex(ValueError, "Commit source changes"):
            release.prepare(self.root, args)

    def test_bundle_rejects_wrong_identity_and_invalid_version(self):
        path = self.root / "Resources/Info.plist"
        info = release.bundle_info(path)
        info["CFBundleIdentifier"] = "org.example.Other"
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "identifier"):
            release.bundle_info(path)
        info["CFBundleIdentifier"] = "org.macam.Macam"
        info["CFBundleShortVersionString"] = "0.3.0/bad"
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "numeric"):
            release.bundle_info(path)

    def test_cask_pins_zip_identity_and_rejects_invalid_metadata(self):
        checksum = "b" * 64
        recipe = release.homebrew_cask(self.root, self.version, checksum, "arm64", "14.2", False)
        self.assertIn(f'version "{self.version}"', recipe)
        self.assertIn(f'sha256 "{checksum}"', recipe)
        self.assertIn('Macam-#{version}-arm64.zip', recipe)
        self.assertIn("depends_on arch: :arm64", recipe)
        self.assertIn('Requires macOS 14.2 or later.', recipe)
        self.assertIn('depends_on macos: :sonoma', recipe)
        self.assertIn('uninstall quit: "org.macam.Macam"', recipe)
        self.assertNotIn("@VERSION@", recipe)
        self.assertNotIn("LOCAL REVIEW ONLY", recipe)
        preview = release.homebrew_cask(self.root, self.version, checksum, "arm64", "14.2", True)
        self.assertTrue(preview.startswith("# LOCAL REVIEW ONLY"))
        for version, digest, arch, minimum in (("v0.3.0", checksum, "arm64", "14.2"),
                (self.version, "unknown", "arm64", "14.2"),
                (self.version, checksum, "universal", "14.2"),
                (self.version, checksum, "arm64", "15.0")):
            with self.assertRaises(ValueError):
                release.homebrew_cask(self.root, version, digest, arch, minimum, False)


if __name__ == "__main__":
    unittest.main()
