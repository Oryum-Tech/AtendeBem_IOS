"""Cloud version reservation must fail closed and preserve local source files."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CloudVersionTests(unittest.TestCase):
    def invoke(self, sequence, text="MARKETING_VERSION = 1.3.0\nCURRENT_PROJECT_VERSION = 40\n",
               action="archive"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Config").mkdir()
            config = root / "Config/App.xcconfig"
            config.write_text(text)
            env = {**os.environ, "CI_PRIMARY_REPOSITORY_PATH": directory,
                   "CI_BUILD_NUMBER": sequence, "CI_XCODEBUILD_ACTION": action}
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

    def test_simulator_worker_requires_no_source_checkout_or_build_number(self):
        env = {key: value for key, value in os.environ.items()
               if key not in {"CI_PRIMARY_REPOSITORY_PATH", "CI_BUILD_NUMBER"}}
        env["CI_XCODEBUILD_ACTION"] = "test-without-building"
        result = subprocess.run(["bash", str(ROOT / "ci_scripts/ci_pre_xcodebuild.sh")],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("previously compiled test products", result.stdout)

    def test_simulator_worker_does_not_modify_a_source_checkout_if_present(self):
        original = "MARKETING_VERSION = 1.3.0\nCURRENT_PROJECT_VERSION = 40\n"
        code, text = self.invoke("10002", original, action="test-without-building")
        self.assertEqual(code, 0)
        self.assertEqual(text, original)

    def test_build_for_testing_still_prepares_compiled_products(self):
        code, text = self.invoke("10002", action="build-for-testing")
        self.assertEqual(code, 0)
        self.assertIn("CURRENT_PROJECT_VERSION = 20002", text)

    def test_compilation_still_rejects_a_missing_checkout(self):
        env = {key: value for key, value in os.environ.items()
               if key != "CI_PRIMARY_REPOSITORY_PATH"}
        env.update(CI_BUILD_NUMBER="10002", CI_XCODEBUILD_ACTION="build-for-testing")
        result = subprocess.run(["bash", str(ROOT / "ci_scripts/ci_pre_xcodebuild.sh")],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode Cloud repository path is required", result.stderr)


if __name__ == "__main__":
    unittest.main()
