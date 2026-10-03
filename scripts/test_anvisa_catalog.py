"""Auditing regressions: do not invent coverage or silently replace public records."""

import csv
from contextlib import closing
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import anvisa_catalog as catalog


class AnvisaCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "input"
        self.source.mkdir()
        self.output = self.root / "snapshot"
        self.rows = [
            ["MEDICAMENTO", "ÁCIDO TESTE", "", "Genérico", "100000001", "", "90000000001", "", "EMPRESA FICTÍCIA", "Ativo", "PRINCÍPIO TESTE"],
            ["MEDICAMENTO", "PRODUTO REPETIDO", "", "", "100000001", "", "90000000001", "", "", "Inativo", ""],
            ["MEDICAMENTO", "SEM REGISTRO", "", "", "", "", "", "", "", "Inativo", ""],
        ]
        self.downloads = [{"file": str(self.source / name), "url": spec["url"], "exit": 0, "stderr": ""}
                          for name, spec in catalog.SOURCES.items()]
        self.analysis = {}
        self.write_csv("registry.csv", [catalog.REGISTRY_HEADER, *self.rows])
        self.write_csv("leaflet_documents.csv", [["posição não interpretada"] + [""] * 9])
        self.write_csv("leaflet_products.csv", [["outra posição"] + [""] * 11])
        self.save_receipts()

    def write_csv(self, name, rows):
        stream = io.StringIO(newline="")
        csv.writer(stream, delimiter=";", lineterminator="\n").writerows(rows)
        self.write_bytes(name, stream.getvalue().encode("cp1252"), rows)

    def write_bytes(self, name, data, rows):
        (self.source / name).write_bytes(data)
        modified = "Fri, 02 Oct 2026 18:28:42 GMT"
        (self.source / (name + ".headers")).write_text(
            f"HTTP/2 200 \ncontent-length: {len(data)}\nlast-modified: {modified}\n\n", encoding="ascii")
        self.analysis[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                               "lastModified": [modified], "status": "HTTP/2 200 "}
        spec = catalog.SOURCES[name]
        payload = rows[1:] if name == "registry.csv" else rows
        if name == "registry.csv":
            status = dict(catalog.Counter(row[9] for row in payload if len(row) > 9))
            self.analysis[spec["analysis"]] = {"rows": len(payload), "status": status}
        else:
            self.analysis[spec["analysis"]] = {"rows": len(payload), "widths": {str(spec["width"]): len(payload)}}

    def save_receipts(self):
        (self.source / "downloads.json").write_text(json.dumps(self.downloads), encoding="utf-8")
        (self.source / "verified-analysis.json").write_text(json.dumps(self.analysis), encoding="utf-8")

    def reject(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.build(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_preserves_duplicate_and_missing_records_and_no_leaflets_claimed(self):
        report = catalog.build(self.source, self.output)
        self.assertEqual(report["registry"]["rows"], 3)
        self.assertEqual(report["registry"]["duplicate_registration_groups"], 1)
        self.assertEqual(report["registry"]["duplicate_registration_rows"], 2)
        self.assertEqual(report["registry"]["without_registration"], 1)
        self.assertEqual(report["registry"]["discarded_rows"], 0)
        self.assertEqual(report["registry"]["merged_rows"], 0)
        self.assertEqual(report["leaflet_texts_read"], 0)
        self.assertFalse(report["production_integration"])
        self.assertEqual(report["interaction_rules_generated"], 0)
        for source in report["leaflet_metadata"].values():
            self.assertEqual(source["schema"], "schema_unknown")
            self.assertEqual(source["semantic_joins_performed"], 0)
        with closing(sqlite3.connect(self.output / "catalog.sqlite")) as db:
            rows = db.execute("SELECT original_json FROM registry ORDER BY row_number").fetchall()
            self.assertEqual([json.loads(row[0]) for row in rows], self.rows)
        for name in catalog.SOURCES:
            self.assertEqual((self.source / name).read_bytes(), (self.output / "sources" / name).read_bytes())

    def test_hash_drift_rejected_before_any_output(self):
        path = self.source / "registry.csv"
        path.write_bytes(path.read_bytes().replace(b"ATIVO", b"atIVO") + b"\n")
        self.reject()

    def test_wrong_record_count_rejected(self):
        self.analysis["registry"]["rows"] += 1
        self.save_receipts()
        self.reject()

    def test_unknown_status_rejected_even_when_receipts_agree(self):
        self.rows[0][9] = "Desconhecido"
        self.write_csv("registry.csv", [catalog.REGISTRY_HEADER, *self.rows])
        self.save_receipts()
        self.reject()

    def test_unofficial_origin_and_duplicate_receipt_rejected(self):
        self.downloads[0]["url"] = "https://dados.anvisa.gov.br.example.invalid/catalog.csv"
        self.save_receipts()
        self.reject()
        self.downloads[0]["url"] = catalog.SOURCES["registry.csv"]["url"]
        self.downloads.append(dict(self.downloads[0]))
        self.save_receipts()
        self.reject()

    def test_changed_header_rejected_even_with_valid_hash(self):
        header = list(catalog.REGISTRY_HEADER)
        header[1] = "NOME_NOVO"
        self.write_csv("registry.csv", [header, *self.rows])
        self.save_receipts()
        self.reject()

    def test_malformed_csv_rejected_even_with_valid_hash(self):
        self.write_bytes("leaflet_documents.csv", b'"unterminated;value\n', [["x"] * 10])
        self.save_receipts()
        self.reject()

    def test_changed_metadata_width_rejected_without_semantic_inference(self):
        self.write_csv("leaflet_products.csv", [["x"] * 11])
        self.save_receipts()
        self.reject()

    def test_partial_response_and_length_mismatch_rejected(self):
        path = self.source / "registry.csv.headers"
        original = path.read_text()
        path.write_text(original.replace("200", "206", 1))
        self.reject()
        path.write_text(original.replace("content-length:", "wrong-length:"))
        self.reject()

    def test_existing_snapshot_and_symlink_not_replaced(self):
        self.output.mkdir()
        sentinel = self.output / "keep.txt"
        sentinel.write_text("preserve")
        with self.assertRaises(catalog.CatalogError):
            catalog.build(self.source, self.output)
        self.assertEqual(sentinel.read_text(), "preserve")
        other = self.root / "linked"
        other.symlink_to(self.output, target_is_directory=True)
        with self.assertRaises(catalog.CatalogError):
            catalog.build(self.source, other)
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_search_normalized_but_returns_original_values_and_provenance(self):
        catalog.build(self.source, self.output)
        result = catalog.search(self.output, "acido teste")
        self.assertEqual(result["returned"], 1)
        hit = result["results"][0]
        self.assertEqual(hit["original"]["NOME_PRODUTO"], "ÁCIDO TESTE")
        self.assertEqual(hit["source_row_number"], 1)
        self.assertEqual(hit["source"]["url"], catalog.SOURCES["registry.csv"]["url"])
        self.assertEqual(catalog.search(self.output, "100000001")["returned"], 2)

    def test_search_parameters_cannot_inject_sql_or_expand_wildcards(self):
        catalog.build(self.source, self.output)
        before = (self.output / "catalog.sqlite").read_bytes()
        for query in ["%' OR 1=1 --", "'; DROP TABLE registry; --", "%", "_"]:
            self.assertEqual(catalog.search(self.output, query)["returned"], 0)
        self.assertEqual(before, (self.output / "catalog.sqlite").read_bytes())
        self.assertEqual(catalog.search(self.output, "100000001", limit=1)["returned"], 1)

    def test_search_opens_sqlite_read_only(self):
        catalog.build(self.source, self.output)
        original = sqlite3.connect
        seen = []
        def inspect(database, **kwargs):
            seen.append((database, kwargs))
            return original(database, **kwargs)
        with patch.object(catalog.sqlite3, "connect", side_effect=inspect):
            catalog.search(self.output, "teste")
        self.assertIn("?mode=ro", seen[0][0])
        self.assertTrue(seen[0][1]["uri"])

    def test_symlink_source_and_invalid_search_limits_rejected(self):
        path = self.source / "registry.csv"
        actual = self.root / "outside.csv"
        path.rename(actual)
        path.symlink_to(actual)
        self.reject()
        for limit in [0, 101, True]:
            with self.assertRaises(catalog.CatalogError):
                catalog.search(self.output, "teste", limit)


    def test_snapshot_is_published_only_after_complete_staging(self):
        original = catalog.publish_snapshot
        observed = []

        def inspect(staging, destination):
            self.assertEqual(staging.parent, destination.parent)
            self.assertFalse(destination.exists())
            coverage = json.loads((staging / "coverage.json").read_text())
            self.assertTrue(coverage["snapshot_complete"])
            self.assertEqual(coverage["database_sha256"], catalog.database_digest(staging / "catalog.sqlite"))
            self.assertEqual(catalog.search(staging, "acido")["returned"], 1)
            observed.append(staging)
            original(staging, destination)

        with patch.object(catalog, "publish_snapshot", side_effect=inspect):
            catalog.build(self.source, self.output)
        self.assertEqual(len(observed), 1)
        self.assertFalse(observed[0].exists())
        self.assertEqual(catalog.search(self.output, "acido")["returned"], 1)

    def test_final_manifest_write_failure_cleans_only_its_staging(self):
        original = Path.write_text
        sibling = self.root / "existing-snapshot"
        sibling.mkdir()
        sentinel = sibling / "keep.txt"
        sentinel.write_text("preserve")

        def fail_manifest(path, *args, **kwargs):
            if path.name == "coverage.json":
                raise OSError("Simulated full disk while finishing manifest")
            return original(path, *args, **kwargs)

        with patch.object(Path, "write_text", autospec=True, side_effect=fail_manifest):
            with self.assertRaises(OSError):
                catalog.build(self.source, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".anvisa-staging-*")))
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_publication_does_not_replace_concurrently_created_destination(self):
        original = catalog.publish_snapshot
        for with_file in [False, True]:
            destination = self.root / f"concurrent-{with_file}"

            def race(staging, target):
                target.mkdir()
                if with_file:
                    (target / "keep.txt").write_text("other writer")
                original(staging, target)

            with self.subTest(with_file=with_file):
                with patch.object(catalog, "publish_snapshot", side_effect=race):
                    with self.assertRaises(OSError):
                        catalog.build(self.source, destination)
                self.assertTrue(destination.is_dir())
                if with_file:
                    self.assertEqual((destination / "keep.txt").read_text(), "other writer")
                else:
                    self.assertEqual(list(destination.iterdir()), [])
                self.assertFalse(list(self.root.glob(".anvisa-staging-*")))

    def test_search_rejects_missing_incomplete_or_partial_manifest(self):
        catalog.build(self.source, self.output)
        manifest = self.output / "coverage.json"
        report = json.loads(manifest.read_text())
        manifest.unlink()
        with self.assertRaises(catalog.CatalogError):
            catalog.search(self.output, "teste")
        incomplete = dict(report, snapshot_complete=False)
        partial = dict(report, sources={"registry.csv": report["sources"]["registry.csv"]})
        for invalid in [incomplete, partial]:
            manifest.write_text(json.dumps(invalid))
            with self.assertRaises(catalog.CatalogError):
                catalog.search(self.output, "teste")

    def test_search_rejects_database_modified_after_build(self):
        catalog.build(self.source, self.output)
        database = self.output / "catalog.sqlite"
        with closing(sqlite3.connect(database)) as connection:
            changed = list(self.rows[0])
            changed[1] = "NOME ADULTERADO"
            connection.execute("UPDATE registry SET original_json = ? WHERE row_number = 1", (json.dumps(changed),))
            connection.commit()
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone(), (catalog.SCHEMA_VERSION,))
        with self.assertRaisesRegex(catalog.CatalogError, "SHA-256"):
            catalog.search(self.output, "acido")

    def test_search_checks_row_completeness_even_if_database_hash_is_recomputed(self):
        catalog.build(self.source, self.output)
        database = self.output / "catalog.sqlite"
        with closing(sqlite3.connect(database)) as connection:
            connection.execute("DELETE FROM leaflet_metadata WHERE source_name = ?", ("leaflet_products.csv",))
            connection.commit()
        manifest = self.output / "coverage.json"
        report = json.loads(manifest.read_text())
        report["database_sha256"] = catalog.database_digest(database)
        manifest.write_text(json.dumps(report))
        with self.assertRaisesRegex(catalog.CatalogError, "incompleto"):
            catalog.search(self.output, "acido")


if __name__ == "__main__":
    unittest.main()
