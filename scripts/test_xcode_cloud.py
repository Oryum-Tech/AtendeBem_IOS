"""Cloud version reservation must fail closed and preserve local source files."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CloudVersionTests(unittest.TestCase):
    def invoke(self, sequence, text="MARKETING_VERSION = 1.3.0\nCURRENT_PROJECT_VERSION = 40\n"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Config").mkdir()
            config = root / "Config/App.xcconfig"
            config.write_text(text)
            env = {**os.environ, "CI_PRIMARY_REPOSITORY_PATH": directory,
                   "CI_BUILD_NUMBER": sequence}
            result = subprocess.run(["bash", str(ROOT / "ci_scripts/ci_pre_xcodebuild.sh")],
                                    env=env, capture_output=True, text=True)
            return result.returncode, config.read_text()

    def test_unique_cloud_version_and_unchanged_marketing_version(self):
        for sequence in ("1", "40", "89999"):
            code, text = self.invoke(sequence)
            self.assertEqual(code, 0)
            self.assertIn(f"CURRENT_PROJECT_VERSION = {10000 + int(sequence)}", text)
            self.assertIn("MARKETING_VERSION = 1.3.0", text)

    def test_invalid_sequence_preserves_configuration(self):
        original = "CURRENT_PROJECT_VERSION = 40\n"
        for sequence in ("", "0", "90000", "-1", "1;exit", "abc"):
            code, text = self.invoke(sequence, original)
            self.assertNotEqual(code, 0)
            self.assertEqual(text, original)

    def test_ambiguous_version_preserves_configuration(self):
        original = "CURRENT_PROJECT_VERSION = 40\nCURRENT_PROJECT_VERSION = 41\n"
        code, text = self.invoke("1", original)
        self.assertNotEqual(code, 0)
        self.assertEqual(text, original)


if __name__ == "__main__":
    unittest.main()
