"""Meaningful release checks: UTF-8 limits, privacy evidence and fail-closed state."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app_store_bundle as bundle


class StoreBundleTests(unittest.TestCase):
    def setUp(self):
        self.metadata = bundle.read_json(bundle.ROOT / "metadata/pt-BR.json")

    def test_prepared_metadata_fits_current_limits(self):
        self.assertEqual(bundle.metadata_errors(self.metadata), [])

    def test_keywords_limit_counts_bytes_not_characters(self):
        self.metadata["keywords"] = "á" * 51
        self.assertEqual(len(self.metadata["keywords"]), 51)
        self.assertIn("keywords: máximo 100 bytes UTF-8", bundle.metadata_errors(self.metadata))

    def test_rejects_long_name_and_non_https_policy(self):
        self.metadata["name"] = "x" * 31
        self.metadata["privacy_url"] = "http://example.invalid"
        errors = bundle.metadata_errors(self.metadata)
        self.assertTrue(any(error.startswith("name:") for error in errors))
        self.assertTrue(any(error.startswith("privacy_url:") for error in errors))

    def test_evidence_cannot_escape_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for bad in ("../outside", str(root / "absolute")):
                with self.assertRaises(ValueError):
                    bundle.safe_path(root, bad)
            (root / "link").symlink_to("/private/tmp")
            with self.assertRaises(ValueError):
                bundle.safe_path(root, "link/elsewhere")

    def test_receipt_cannot_validate_changed_capture_or_unreviewed_patient_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "test.jpg"
            path.write_bytes(b"fixture bytes for hash, not an image")
            receipt = {"build": "test", "device": "test", "os": "test", "captured_at": "2026-09-29", "reviewer": "test", "source_file": "raw/test.jpg", "sha256": "0" * 64, "real_app_capture": True, "synthetic_data_only": False}
            path.with_suffix(".jpg.receipt.json").write_text(json.dumps(receipt))
            errors = bundle.receipt_errors(path, root)
            self.assertTrue(any("SHA-256" in error for error in errors))
            self.assertTrue(any("sintéticos" in error for error in errors))

    def test_missing_media_and_evidence_block_submission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ("metadata", "review", "privacy", "media"):
                (root / folder).mkdir()
            (root / "metadata/pt-BR.json").write_text(json.dumps(self.metadata))
            (root / "review/NOTAS-EN.txt").write_text("Review notes")
            (root / "privacy/PrivacyInfo.candidate.xcprivacy").write_bytes((bundle.ROOT / "privacy/PrivacyInfo.candidate.xcprivacy").read_bytes())
            (root / "media/specification.json").write_text(json.dumps({"devices": [{"id": "test", "screenshot_pixels": [1320, 2868], "preview_pixels": [886, 1920]}], "shots": [{"order": 1, "id": "test"}]}))
            (root / "release-status.json").write_text(json.dumps({"gates": [{"id": "qa", "label": "QA", "status": "verified", "evidence": "missing.md"}]}))
            with patch.object(bundle, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                self.assertFalse(bundle.validate(submission=True))
            report = bundle.read_json(root / "validation-report.json")
            self.assertFalse(report["submission_ready"])
            self.assertTrue(any("evidência" in error for error in report["errors"]))
            self.assertTrue(any("Mídia ausente" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
