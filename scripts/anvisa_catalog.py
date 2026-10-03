#!/usr/bin/env python3
"""Audit already downloaded ANVISA files and build a local, non-clinical index.

No network, credentials, LLM, service calls, or production database access.
The receipt is evidence of a recorded download, not a digital signature by ANVISA.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import closing
import ctypes
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
import tempfile
from typing import Literal, TypedDict, Union, cast
import unicodedata


JSONValue = Union[None, bool, int, float, str, list["JSONValue"], dict[str, "JSONValue"]]
PathInput = Union[str, os.PathLike[str]]
CSVRows = list[list[str]]


class SourceSpec(TypedDict):
    """The fixed public source address and observed CSV structure."""

    url: str
    analysis: str
    width: int
    schema: str


class HTTPReceipt(TypedDict):
    """Facts extracted from the recorded final HTTP response."""

    status: int
    content_length: int
    last_modified: list[str]
    download_date: list[str]


class SourceManifest(HTTPReceipt):
    """Provenance and counts for one verified source file."""

    url: str
    sha256: str
    bytes: int
    rows: int
    schema: str


class VerifiedSource(TypedDict):
    """Source bytes and parsed rows retained after runtime verification."""

    data: bytes
    header_raw: bytes
    rows: CSVRows
    manifest: SourceManifest


class RegistryCoverage(TypedDict):
    """Measured inventory counts without interpretation of clinical meaning."""

    rows: int
    status: dict[str, int]
    without_registration: int
    without_active_principle: int
    duplicate_registration_groups: int
    duplicate_registration_rows: int
    duplicate_process_groups: int
    exact_duplicate_row_groups: int
    discarded_rows: Literal[0]
    merged_rows: Literal[0]


class LeafletMetadataCoverage(TypedDict):
    """Uninterpreted metadata inventory, never a claim of leaflet ingestion."""

    rows: int
    schema: Literal["schema_unknown"]
    semantic_joins_performed: Literal[0]


class InternalCoverage(TypedDict):
    """Coverage stored in SQLite before the completed database is hashed."""

    schema_version: int
    built_at: str
    scope: Literal["local_public_source_snapshot"]
    production_integration: Literal[False]
    snapshot_complete: Literal[True]
    registry: RegistryCoverage
    sources: dict[str, SourceManifest]
    leaflet_metadata: dict[str, LeafletMetadataCoverage]
    leaflet_texts_read: Literal[0]
    leaflet_documents_downloaded: Literal[0]
    indications_extracted: Literal[0]
    interaction_rules_generated: Literal[0]
    limitation: str


class SnapshotCoverage(InternalCoverage):
    """Published coverage, including the digest of the closed SQLite file."""

    database_sha256: str


class SearchHit(TypedDict):
    """An original CSV row and the provenance of its source snapshot."""

    source_row_number: int
    original: dict[str, str]
    source: SourceManifest


class SearchResult(TypedDict):
    """Bounded local search output; no clinical interpretation is produced."""

    query: str
    limit: int
    returned: int
    results: list[SearchHit]
    leaflet_texts_read: Literal[0]
    limitation: str


SOURCES: dict[str, SourceSpec] = {
    "registry.csv": {
        "url": "https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv",
        "analysis": "registry", "width": 11, "schema": "registry_header_v1",
    },
    "leaflet_documents.csv": {
        "url": "https://dados.anvisa.gov.br/dados/CONSULTAS/DOCUMENTOS/TA_CONSULTA_BULA_DOCUMENTO.CSV",
        "analysis": "documents", "width": 10, "schema": "schema_unknown",
    },
    "leaflet_products.csv": {
        "url": "https://dados.anvisa.gov.br/dados/CONSULTAS/DOCUMENTOS/TA_CONSULTA_BULA_PRODUTO.CSV",
        "analysis": "products", "width": 12, "schema": "schema_unknown",
    },
}
REGISTRY_HEADER = [
    "TIPO_PRODUTO", "NOME_PRODUTO", "DATA_FINALIZACAO_PROCESSO", "CATEGORIA_REGULATORIA",
    "NUMERO_REGISTRO_PRODUTO", "DATA_VENCIMENTO_REGISTRO", "NUMERO_PROCESSO",
    "CLASSE_TERAPEUTICA", "EMPRESA_DETENTORA_REGISTRO", "SITUACAO_REGISTRO", "PRINCIPIO_ATIVO",
]
MAX_SOURCE_BYTES = 64 * 1024 * 1024
MAX_ROWS = 300_000
MAX_DATABASE_BYTES = 512 * 1024 * 1024
SCHEMA_VERSION = 1
LIMITATION = (
    "Índice local de cadastro e metadados públicos de um snapshot. Não integrado à LARI de produção. "
    "Nenhum texto de bula foi ingerido ou lido. Não determina indicações, interações, segurança "
    "ou completude do mercado brasileiro. Metadados de bula permanecem sem esquema oficial confirmado."
)


class CatalogError(ValueError):
    """A source or snapshot could not be verified; fail without partial clinical data."""


def normalized(value: str) -> str:
    """Normalization is exclusively for search; original CSV values are preserved."""
    return "".join(c for c in unicodedata.normalize("NFKD", value.casefold())
                   if not unicodedata.combining(c))


def read_regular(path: Path, maximum: int = MAX_SOURCE_BYTES) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise CatalogError(f"Arquivo regular obrigatório, sem link simbólico: {path.name}")
    if not 0 < path.stat().st_size <= maximum:
        raise CatalogError(f"Tamanho ausente ou fora do limite: {path.name}")
    data = path.read_bytes()
    if not 0 < len(data) <= maximum:
        raise CatalogError(f"Tamanho mudou ou excedeu o limite: {path.name}")
    return data


def json_receipt(path: Path) -> tuple[JSONValue, bytes]:
    raw = read_regular(path, 2 * 1024 * 1024)
    try:
        return cast(JSONValue, json.loads(raw)), raw
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CatalogError(f"Recibo JSON inválido: {path.name}") from exc


def positive_int(value: object, label: str) -> int:
    if type(value) is not int or value <= 0:
        raise CatalogError(f"Contagem inválida no recibo: {label}")
    return value


def parse_headers(raw: bytes, expected_bytes: int) -> HTTPReceipt:
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        raise CatalogError("Cabeçalhos HTTP inválidos") from exc
    # Curl may record CONNECT and redirects. Only the final response is accepted.
    blocks = re.split(r"(?m)(?=^HTTP/)", text)
    blocks = [block for block in blocks if block.startswith("HTTP/")]
    if not blocks:
        raise CatalogError("Recibo sem resposta HTTP")
    lines = blocks[-1].splitlines()
    if not re.fullmatch(r"HTTP/\S+\s+200(?:\s+.*)?", lines[0].strip()):
        raise CatalogError("O download completo deve terminar em HTTP 200")
    headers: dict[str, list[str]] = {}
    for line in lines[1:]:
        if not line.strip():
            continue
        if ":" not in line:
            raise CatalogError("Linha inválida nos cabeçalhos HTTP")
        key, value = line.split(":", 1)
        headers.setdefault(key.lower().strip(), []).append(value.strip())
    lengths = headers.get("content-length", [])
    if len(lengths) != 1 or not lengths[0].isdigit() or int(lengths[0]) != expected_bytes:
        raise CatalogError("Content-Length diverge do arquivo completo")
    if "content-range" in headers:
        raise CatalogError("Download parcial não é aceito")
    return {"status": 200, "content_length": expected_bytes,
            "last_modified": headers.get("last-modified", []),
            "download_date": headers.get("date", [])}


def parse_rows(data: bytes, name: str, spec: SourceSpec) -> CSVRows:
    try:
        text = data.decode("cp1252", errors="strict")
        if "\x00" in text:
            raise CatalogError(f"CSV contém byte NUL: {name}")
        reader = csv.reader(io.StringIO(text, newline=""), delimiter=";", strict=True)
        if name == "registry.csv" and next(reader, None) != REGISTRY_HEADER:
            raise CatalogError("Cabeçalho de medicamentos não corresponde ao esquema verificado")
        rows: CSVRows = []
        for number, fields in enumerate(reader, 1):
            if number > MAX_ROWS or len(fields) != spec["width"]:
                raise CatalogError(f"CSV com largura/contagem inesperada: {name}, registro {number}")
            if name == "registry.csv" and fields[9] not in {"Ativo", "Inativo"}:
                raise CatalogError(f"Situação regulatória desconhecida no registro {number}")
            rows.append(fields)
        if not rows:
            raise CatalogError(f"CSV sem registros: {name}")
        return rows
    except (UnicodeDecodeError, csv.Error) as exc:
        raise CatalogError(f"CSV inválido: {name}: {exc}") from exc


def verify_sources(source_dir: Path) -> tuple[dict[str, VerifiedSource], dict[str, bytes]]:
    downloads, download_raw = json_receipt(source_dir / "downloads.json")
    analysis, analysis_raw = json_receipt(source_dir / "verified-analysis.json")
    if not isinstance(downloads, list) or not isinstance(analysis, dict):
        raise CatalogError("Formato inválido dos recibos de download/análise")
    verified: dict[str, VerifiedSource] = {}
    for name, spec in SOURCES.items():
        matches = [entry for entry in downloads if isinstance(entry, dict)
                   and isinstance(entry.get("file"), str) and Path(cast(str, entry["file"])).name == name]
        if (len(matches) != 1 or matches[0].get("url") != spec["url"]
                or type(matches[0].get("exit")) is not int or matches[0]["exit"] != 0):
            raise CatalogError(f"Origem oficial/download bem-sucedido não comprovado: {name}")
        receipt = analysis.get(name)
        counts = analysis.get(spec["analysis"])
        if not isinstance(receipt, dict) or not isinstance(counts, dict):
            raise CatalogError(f"Análise anterior ausente: {name}")
        expected_bytes = positive_int(receipt.get("bytes"), name + ".bytes")
        expected_rows = positive_int(counts.get("rows"), name + ".rows")
        expected_hash = receipt.get("sha256")
        if not isinstance(expected_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", expected_hash):
            raise CatalogError(f"SHA-256 inválido no recibo: {name}")
        data = read_regular(source_dir / name)
        digest = hashlib.sha256(data).hexdigest()
        if len(data) != expected_bytes or digest != expected_hash:
            raise CatalogError(f"Bytes/SHA-256 divergem da análise anterior: {name}")
        header_raw = read_regular(source_dir / (name + ".headers"), 64 * 1024)
        http = parse_headers(header_raw, len(data))
        if receipt.get("lastModified") != http["last_modified"]:
            raise CatalogError(f"Last-Modified diverge da análise anterior: {name}")
        if not isinstance(receipt.get("status"), str) or not re.fullmatch(
                r"HTTP/\S+\s+200(?:\s+.*)?", cast(str, receipt["status"]).strip()):
            raise CatalogError(f"Análise anterior não confirma HTTP 200: {name}")
        rows = parse_rows(data, name, spec)
        if len(rows) != expected_rows:
            raise CatalogError(f"Número de registros diverge da análise anterior: {name}")
        if name == "registry.csv":
            observed = dict(Counter(row[9] for row in rows))
            if counts.get("status") != observed:
                raise CatalogError("Contagem de ativos/inativos diverge da análise anterior")
        elif counts.get("widths") != {str(spec["width"]): len(rows)}:
            raise CatalogError(f"Largura observada diverge da análise anterior: {name}")
        verified[name] = {"data": data, "header_raw": header_raw, "rows": rows,
                          "manifest": {"url": spec["url"], "sha256": digest, "bytes": len(data),
                                       "rows": len(rows), "schema": spec["schema"], **http}}
    return verified, {"downloads.json": download_raw, "verified-analysis.json": analysis_raw}


def registry_coverage(rows: CSVRows) -> RegistryCoverage:
    registrations = Counter(row[4] for row in rows if row[4].strip())
    processes = Counter(row[6] for row in rows if row[6].strip())
    duplicate_rows = Counter(json.dumps(row, ensure_ascii=False) for row in rows)
    return {
        "rows": len(rows), "status": dict(Counter(row[9] for row in rows)),
        "without_registration": sum(not row[4].strip() for row in rows),
        "without_active_principle": sum(not row[10].strip() for row in rows),
        "duplicate_registration_groups": sum(count > 1 for count in registrations.values()),
        "duplicate_registration_rows": sum(count for count in registrations.values() if count > 1),
        "duplicate_process_groups": sum(count > 1 for count in processes.values()),
        "exact_duplicate_row_groups": sum(count > 1 for count in duplicate_rows.values()),
        "discarded_rows": 0, "merged_rows": 0,
    }


def publish_snapshot(staging: Path, destination: Path) -> None:
    """Atomically publish a directory, refusing even an empty concurrent target."""
    # POSIX rename can replace an existing empty directory. RENAME_EXCL provides
    # the no-replacement guarantee required for these immutable macOS snapshots.
    if sys.platform != "darwin":
        raise CatalogError("Publicação atômica exclusiva disponível somente no macOS")
    library = ctypes.CDLL(None, use_errno=True)
    rename = getattr(library, "renamex_np", None)
    if rename is None:
        raise CatalogError("O sistema não oferece publicação atômica exclusiva")
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(staging), os.fsencode(destination), 0x00000004) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def database_digest(database: Path) -> str:
    if database.is_symlink() or not database.is_file():
        raise CatalogError("Índice SQLite local não encontrado ou não regular")
    size = database.stat().st_size
    if not 0 < size <= MAX_DATABASE_BYTES:
        raise CatalogError("Tamanho do índice SQLite fora do limite")
    digest = hashlib.sha256()
    consumed = 0
    with database.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            consumed += len(chunk)
            if consumed > MAX_DATABASE_BYTES:
                raise CatalogError("Índice SQLite excedeu o limite durante a leitura")
            digest.update(chunk)
    if consumed != size:
        raise CatalogError("Índice SQLite mudou durante a leitura")
    return digest.hexdigest()


def build(source_dir: PathInput, output_dir: PathInput) -> SnapshotCoverage:
    source_dir, output_dir = Path(source_dir), Path(output_dir)
    if output_dir.exists() or output_dir.is_symlink():
        raise CatalogError("O snapshot de saída já existe; selecione uma pasta nova")
    verified, receipts = verify_sources(source_dir)
    if not output_dir.parent.is_dir():
        raise CatalogError("A pasta pai do snapshot deve existir")
    staging = Path(tempfile.mkdtemp(prefix=".anvisa-staging-", dir=output_dir.parent))
    connection: sqlite3.Connection | None = None
    try:
        source_output = staging / "sources"
        source_output.mkdir(mode=0o700)
        connection = sqlite3.connect(staging / "catalog.sqlite")
        connection.executescript("""
            PRAGMA user_version = 1;
            CREATE TABLE sources (name TEXT PRIMARY KEY, manifest_json TEXT NOT NULL);
            CREATE TABLE registry (
                row_number INTEGER PRIMARY KEY, source_name TEXT NOT NULL REFERENCES sources(name),
                original_json TEXT NOT NULL, name TEXT NOT NULL, principle TEXT NOT NULL,
                registration TEXT NOT NULL, status TEXT NOT NULL,
                search_name TEXT NOT NULL, search_principle TEXT NOT NULL, search_registration TEXT NOT NULL
            );
            CREATE TABLE leaflet_metadata (
                source_name TEXT NOT NULL REFERENCES sources(name), row_number INTEGER NOT NULL,
                raw_fields_json TEXT NOT NULL, schema_status TEXT NOT NULL CHECK(schema_status = 'schema_unknown'),
                PRIMARY KEY(source_name, row_number)
            );
            CREATE TABLE snapshot (key TEXT PRIMARY KEY, value_json TEXT NOT NULL);
            CREATE INDEX registry_search_name ON registry(search_name);
            CREATE INDEX registry_search_principle ON registry(search_principle);
            CREATE INDEX registry_search_registration ON registry(search_registration);
        """)
        for name, source in verified.items():
            (source_output / name).write_bytes(source["data"])
            (source_output / (name + ".headers")).write_bytes(source["header_raw"])
            connection.execute("INSERT INTO sources VALUES (?, ?)",
                               (name, json.dumps(source["manifest"], ensure_ascii=False)))
            if name == "registry.csv":
                connection.executemany("INSERT INTO registry VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (
                    (number, name, json.dumps(row, ensure_ascii=False), row[1], row[10], row[4], row[9],
                     normalized(row[1]), normalized(row[10]), normalized(row[4]))
                    for number, row in enumerate(source["rows"], 1)))
            else:
                connection.executemany("INSERT INTO leaflet_metadata VALUES (?, ?, ?, ?)", (
                    (name, number, json.dumps(row, ensure_ascii=False), "schema_unknown")
                    for number, row in enumerate(source["rows"], 1)))
        for name, raw in receipts.items():
            (source_output / name).write_bytes(raw)
        report: InternalCoverage = {
            "schema_version": SCHEMA_VERSION, "built_at": datetime.now(timezone.utc).isoformat(),
            "scope": "local_public_source_snapshot", "production_integration": False,
            "snapshot_complete": True,
            "registry": registry_coverage(verified["registry.csv"]["rows"]),
            "sources": {name: item["manifest"] for name, item in verified.items()},
            "leaflet_metadata": {name: {"rows": len(item["rows"]), "schema": "schema_unknown",
                                        "semantic_joins_performed": 0}
                                 for name, item in verified.items() if name != "registry.csv"},
            "leaflet_texts_read": 0, "leaflet_documents_downloaded": 0,
            "indications_extracted": 0, "interaction_rules_generated": 0,
            "limitation": LIMITATION,
        }
        connection.execute("INSERT INTO snapshot VALUES (?, ?)",
                           ("coverage", json.dumps(report, ensure_ascii=False)))
        connection.commit()
        if connection.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise CatalogError("Falha na integridade do índice SQLite")
        connection.close()
        connection = None
        # The same report gains its final field only after the database is closed.
        completed_report = cast(SnapshotCoverage, report)
        completed_report["database_sha256"] = database_digest(staging / "catalog.sqlite")
        (staging / "coverage.json").write_text(json.dumps(completed_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        publish_snapshot(staging, output_dir)
        return completed_report
    except BaseException:
        if connection is not None:
            connection.close()
        # A concurrent destination is never ours to remove. Clean only our staging.
        if staging.exists():
            shutil.rmtree(staging)
        raise


def verified_snapshot_coverage(snapshot_dir: Path, database: Path) -> SnapshotCoverage:
    report, _ = json_receipt(snapshot_dir / "coverage.json")
    if (not isinstance(report, dict) or report.get("snapshot_complete") is not True
            or type(report.get("schema_version")) is not int
            or report["schema_version"] != SCHEMA_VERSION
            or report.get("scope") != "local_public_source_snapshot"
            or report.get("production_integration") is not False):
        raise CatalogError("Manifesto do snapshot incompleto ou incompatível")
    for field in ("leaflet_texts_read", "leaflet_documents_downloaded",
                  "indications_extracted", "interaction_rules_generated"):
        if type(report.get(field)) is not int or report[field] != 0:
            raise CatalogError("Manifesto contém alegação de corpus clínico não suportada")
    sources = report.get("sources")
    if not isinstance(sources, dict) or set(sources) != set(SOURCES):
        raise CatalogError("Manifesto não contém todas as fontes esperadas")
    for name, spec in SOURCES.items():
        source = sources[name]
        if (not isinstance(source, dict) or source.get("url") != spec["url"]
                or source.get("schema") != spec["schema"]):
            raise CatalogError(f"Fonte do snapshot incompatível: {name}")
        positive_int(source.get("rows"), name + ".rows")
    expected = report.get("database_sha256")
    if not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise CatalogError("Manifesto sem SHA-256 válido do índice")
    if database_digest(database) != expected:
        raise CatalogError("SHA-256 do índice diverge do snapshot concluído")
    # Casts describe the producer's schema; the runtime checks above and the
    # subsequent SQLite coverage comparison remain the integrity boundary.
    return cast(SnapshotCoverage, report)


def verify_database_coverage(connection: sqlite3.Connection, report: SnapshotCoverage) -> None:
    internal = connection.execute("SELECT value_json FROM snapshot WHERE key = 'coverage'").fetchone()
    expected = {key: value for key, value in report.items() if key != "database_sha256"}
    if internal is None or json.loads(internal[0]) != expected:
        raise CatalogError("Cobertura interna diverge do manifesto do snapshot")
    sources = dict(connection.execute("SELECT name, manifest_json FROM sources").fetchall())
    if set(sources) != set(SOURCES):
        raise CatalogError("Índice sem todas as fontes esperadas")
    for name, spec in SOURCES.items():
        manifest = report["sources"][name]
        if json.loads(sources[name]) != manifest:
            raise CatalogError(f"Proveniência interna divergente: {name}")
        table = "registry" if name == "registry.csv" else "leaflet_metadata"
        # Table is chosen only from literals above; source values remain bound.
        count = connection.execute(f"SELECT COUNT(*) FROM {table} WHERE source_name = ?", (name,)).fetchone()[0]
        if count != manifest["rows"]:
            raise CatalogError(f"Índice incompleto para a fonte: {name}")


def search(snapshot_dir: PathInput, query: str, limit: int = 20) -> SearchResult:
    if type(limit) is not int or not 1 <= limit <= 100:
        raise CatalogError("Limite de busca deve ficar entre 1 e 100")
    if not isinstance(query, str) or not query.strip() or len(query) > 200:
        raise CatalogError("Informe um termo de busca entre 1 e 200 caracteres")
    snapshot_dir = Path(snapshot_dir)
    database = snapshot_dir / "catalog.sqlite"
    report = verified_snapshot_coverage(snapshot_dir, database)
    uri = database.resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True)) as connection:
        connection.execute("PRAGMA query_only = ON")
        if connection.execute("PRAGMA user_version").fetchone() != (SCHEMA_VERSION,):
            raise CatalogError("Versão do índice local não suportada")
        verify_database_coverage(connection, report)
        pattern = normalized(query.strip()).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = "%" + pattern + "%"
        rows: list[tuple[int, str, str]] = connection.execute("""
            SELECT r.row_number, r.original_json, s.manifest_json FROM registry r
            JOIN sources s ON s.name = r.source_name
            WHERE r.search_name LIKE ? ESCAPE '\\' OR r.search_principle LIKE ? ESCAPE '\\'
               OR r.search_registration LIKE ? ESCAPE '\\'
            ORDER BY r.row_number LIMIT ?
        """, (pattern, pattern, pattern, limit)).fetchall()
        results: list[SearchHit] = [
            {"source_row_number": number,
             "original": dict(zip(REGISTRY_HEADER, cast(list[str], json.loads(raw)))),
             "source": cast(SourceManifest, json.loads(manifest))}
            for number, raw, manifest in rows
        ]
        if database_digest(database) != report["database_sha256"]:
            raise CatalogError("Índice mudou durante a pesquisa; resultado descartado")
        return {"query": query, "limit": limit, "returned": len(results), "results": results,
                "leaflet_texts_read": 0, "limitation": LIMITATION}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("build", help="Auditar fontes já baixadas e criar snapshot novo")
    create.add_argument("--source-dir", required=True, type=Path)
    create.add_argument("--output-dir", required=True, type=Path)
    lookup = commands.add_parser("search", help="Pesquisar o SQLite local em modo somente leitura")
    lookup.add_argument("--snapshot-dir", required=True, type=Path)
    lookup.add_argument("--query", required=True)
    lookup.add_argument("--limit", type=int, default=20)
    args = parser.parse_args(argv)
    try:
        result = build(args.source_dir, args.output_dir) if args.command == "build" else search(args.snapshot_dir, args.query, args.limit)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (CatalogError, OSError, sqlite3.Error, json.JSONDecodeError) as exc:
        print(f"Índice ANVISA não concluído: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
