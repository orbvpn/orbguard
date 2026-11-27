"""The version a store sees must be the app's version.

app/pubspec.yaml holds the version (1.2.3+45). The Snap Store reads its own
copy in snap/snapcraft.yaml, and the Microsoft Store reads msix_version in
pubspec.yaml. Both are written by hand, and a copy left behind ships the new
app under an old number. These tests fail CI when a copy drifts.

Run from app/:  python3 -m unittest discover -s tools -p "test_*.py"
"""

import re
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
PUBSPEC = APP / "pubspec.yaml"
SNAPCRAFT = APP.parent / "snap" / "snapcraft.yaml"


def app_version() -> str:
    """The app's version without its build number."""
    match = re.search(r"^version:\s*([0-9.]+)\+", PUBSPEC.read_text(), re.M)
    assert match, "pubspec.yaml has no version line of the form 1.2.3+45"
    return match.group(1)


class ReleaseVersions(unittest.TestCase):
    def test_the_snap_ships_the_app_version(self):
        match = re.search(
            r"^version:\s*'?([0-9.]+)'?\s*$", SNAPCRAFT.read_text(), re.M)
        if match is None:
            self.fail("snap/snapcraft.yaml has no version line")
        self.assertEqual(match.group(1), app_version())

    def test_the_msix_ships_the_app_version(self):
        match = re.search(
            r"^\s+msix_version:\s*([0-9.]+)\s*$", PUBSPEC.read_text(), re.M)
        if match is None:
            self.fail("pubspec.yaml has no msix_version")
        parts = match.group(1).split(".")
        self.assertEqual(len(parts), 4, "msix_version needs four parts")
        self.assertEqual(".".join(parts[:3]), app_version())


if __name__ == "__main__":
    unittest.main()
