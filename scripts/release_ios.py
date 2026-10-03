#!/usr/bin/env python3
"""Local release assistant. Delivery is a separate, explicit command."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "Config/App.xcconfig"
STORE_RECORD = ROOT / "release/app-store/app-store-connect.json"
OUTPUT = ROOT / "release/builds"
TRANSPORTER = Path("/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter")
MIN_FREE_GIB = 8
IDENTITY_KEYS = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "CFBundleName", "CFBundleDisplayName")


def configuration(path=CONFIG):
    values = dict(re.findall(r"^([A-Z][A-Za-z_]+)\s*=\s*([^\n]+)$", path.read_text(), re.M))
    values = {k: v.strip() for k, v in values.items()}
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", values["MARKETING_VERSION"]):
        raise ValueError("A versão deve ter três números, por exemplo 1.0.0.")
    build = values["CURRENT_PROJECT_VERSION"]
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("O número de build deve ser um inteiro de 1 a 9999.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", values["PRODUCT_BUNDLE_IDENTIFIER"]):
        raise ValueError("Bundle identifier inválido.")
    if values["PRODUCT_NAME"] != "AtendeBem":
        raise ValueError("O produto do scheme deve continuar sendo AtendeBem.")
    check_store_identity(values)
    return values


def check_store_identity(config, path=STORE_RECORD):
    record = json.loads(path.read_text())
    if record.get("bundle_id") != config["PRODUCT_BUNDLE_IDENTIFIER"]:
        raise ValueError("Bundle ID diverge do cadastro verificado no App Store Connect. Confira o registro da Apple antes de preparar ou enviar outro pacote.")
    last_build = record.get("last_observed_build", 0)
    if type(last_build) is not int or not 0 <= last_build <= 9999:
        raise ValueError("Último build observado no App Store Connect inválido.")
    return record


def identity(config):
    return dict(zip(IDENTITY_KEYS, (config["PRODUCT_BUNDLE_IDENTIFIER"], config["MARKETING_VERSION"],
                                  config["CURRENT_PROJECT_VERSION"], config["INFOPLIST_KEY_CFBundleName"],
                                  config["INFOPLIST_KEY_CFBundleDisplayName"])))


def check_identity(info, config):
    for key, value in identity(config).items():
        if info.get(key) != value:
            raise ValueError(f"{key}: esperado {value!r}, encontrado {info.get(key)!r}. Prepare um novo Archive.")


def require_space():
    free = shutil.disk_usage(ROOT).free / 1024**3
    if free < MIN_FREE_GIB:
        raise ValueError(f"Só {free:.1f} GiB livres; são necessários pelo menos {MIN_FREE_GIB} GiB para iniciar. Nenhum cache foi apagado.")
    return round(free, 2)


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def run(command, log=None):
    # Arguments are never interpolated into a shell; credentials are never printed.
    print(f"Executando {Path(command[0]).name}." + (f" Log: {log}" if log else ""), flush=True)
    if log:
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=False)
    else:
        result = subprocess.run(command, cwd=ROOT, check=False)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} terminou com código {result.returncode}." + (f" Consulte {log}." if log else ""))


def existing_builds(bundle_id, roots):
    builds = []
    for root in roots:
        for path in root.glob("**/*.xcarchive/Info.plist"):
            info = read_plist(path).get("ApplicationProperties", {})
            if info.get("CFBundleIdentifier") == bundle_id:
                value = str(info.get("CFBundleVersion", ""))
                if value.isdigit():
                    builds.append(int(value))
                else:
                    raise ValueError(f"Archive com build não inteiro: {path}. Defina uma estratégia de migração antes de incrementar.")
    return builds


def prepare(version=None):
    config = configuration()
    if version is not None and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Use uma versão como 1.0.0.")
    builds = existing_builds(config["PRODUCT_BUNDLE_IDENTIFIER"], [OUTPUT, Path.home() / "Library/Developer/Xcode/Archives"])
    store_record = check_store_identity(config)
    next_build = max([int(config["CURRENT_PROJECT_VERSION"]), store_record.get("last_observed_build", 0), *builds]) + 1
    if next_build > 9999:
        raise ValueError("Faixa de build esgotada; não reutilize um número já enviado.")
    text = CONFIG.read_text()
    text = re.sub(r"^CURRENT_PROJECT_VERSION = .+$", f"CURRENT_PROJECT_VERSION = {next_build}", text, flags=re.M)
    if version:
        text = re.sub(r"^MARKETING_VERSION = .+$", f"MARKETING_VERSION = {version}", text, flags=re.M)
    CONFIG.write_text(text)
    return configuration()


def archive_info(path, config):
    path = path.resolve(strict=True)
    if path.suffix != ".xcarchive":
        raise ValueError("Selecione um .xcarchive.")
    metadata = read_plist(path / "Info.plist")
    apps = list((path / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Archive deve conter exatamente um aplicativo iOS instalável.")
    app = apps[0]
    info = read_plist(app / "Info.plist")
    check_identity(info, config)
    properties = metadata.get("ApplicationProperties", {})
    for key in IDENTITY_KEYS[:3]:
        if properties.get(key) != info.get(key):
            raise ValueError(f"Metadados do Organizer divergentes: {key}.")
    if properties.get("Team") != config["DEVELOPMENT_TEAM"]:
        raise ValueError("A equipe do Archive difere da configuração.")
    if not (app / "PrivacyInfo.xcprivacy").is_file():
        raise ValueError("Manifesto de privacidade não incluído no aplicativo.")
    if not (path / "dSYMs/AtendeBem.app.dSYM").is_dir():
        raise ValueError("Símbolos dSYM do app ausentes.")
    return app


def archive(config):
    free = require_space()
    folder = OUTPUT / f"AtendeBem-{config['MARKETING_VERSION']}-{config['CURRENT_PROJECT_VERSION']}"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "AtendeBem.xcarchive"
    if path.exists():
        raise ValueError("Esse Archive já existe. Use prepare para reservar outro build; nada foi sobrescrito.")
    command = ["xcodebuild", "-project", "AtendeBem.xcodeproj", "-scheme", "AtendeBem", "-configuration", "Release",
               "-destination", "generic/platform=iOS", "-derivedDataPath", str(ROOT / "DerivedData"),
               "-archivePath", str(path), "-allowProvisioningUpdates", "archive"]
    run(command, folder / "archive.log")
    app = archive_info(path, config)
    run(["codesign", "--verify", "--deep", "--strict", str(app)], folder / "signature.log")
    write_json(folder / "archive-receipt.json", {"created_at": datetime.now(timezone.utc).isoformat(),
               "identity": identity(config), "free_gib_before": free, "archive": str(path),
               "info_sha256": hashlib.sha256((app / "Info.plist").read_bytes()).hexdigest(),
               "validation": "Archive e assinatura local verificados; não comprova validação Apple ou QA clínico."})
    print(f"Archive conferido: {path}")
    return path


def ipa_info(path, config):
    with zipfile.ZipFile(path) as ipa:
        for item in ipa.infolist():
            name = PurePosixPath(item.filename)
            if name.is_absolute() or ".." in name.parts or "\\" in item.filename or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("IPA contém caminho ou link não permitido para extração local.")
        names = [n for n in ipa.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(names) != 1:
            raise ValueError("IPA deve conter exatamente um aplicativo.")
        info = plistlib.loads(ipa.read(names[0]))
        check_identity(info, config)
        prefix = names[0].removesuffix("Info.plist")
        if prefix + "embedded.mobileprovision" not in ipa.namelist():
            raise ValueError("IPA sem perfil de distribuição incorporado.")
    return info


def check_distribution_profile(profile, config):
    entitlements = profile.get("Entitlements", {})
    expected = config["DEVELOPMENT_TEAM"] + "." + config["PRODUCT_BUNDLE_IDENTIFIER"]
    if entitlements.get("application-identifier") != expected:
        raise ValueError("O perfil não corresponde à equipe e ao bundle configurados.")
    if profile.get("TeamIdentifier") != [config["DEVELOPMENT_TEAM"]]:
        raise ValueError("Equipe incorreta no perfil de distribuição.")
    if entitlements.get("get-task-allow") is not False or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("O IPA não usa um perfil da App Store; não envie uma exportação de desenvolvimento, Ad Hoc ou Enterprise.")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime) or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("Perfil de distribuição vencido ou sem validade verificável.")


def verify_ipa(path, config):
    ipa_info(path, config)
    with tempfile.TemporaryDirectory(prefix="atendebem-ipa-") as directory:
        folder = Path(directory)
        # This is the local Xcode export. ditto preserves the signed bundle layout.
        run(["ditto", "-x", "-k", str(path), str(folder)])
        apps = list((folder / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Estrutura do aplicativo exportado inválida.")
        app = apps[0]
        result = subprocess.run(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")],
                                capture_output=True, check=True)
        check_distribution_profile(plistlib.loads(result.stdout), config)
        run(["codesign", "--verify", "--deep", "--strict", str(app)])


def export(path, config):
    require_space()
    app = archive_info(path, config)
    run(["codesign", "--verify", "--deep", "--strict", str(app)], path.parent / "signature-export.log")
    destination = path.parent / "AppStore"
    if destination.exists():
        raise ValueError("A pasta AppStore já existe. Inspecione o resultado anterior antes de exportar novamente.")
    options = path.parent / "ExportOptions.plist"
    options.write_bytes(plistlib.dumps({"method": "app-store-connect", "destination": "export",
                        "teamID": config["DEVELOPMENT_TEAM"], "signingStyle": "automatic",
                        "manageAppVersionAndBuildNumber": False, "uploadSymbols": True, "stripSwiftSymbols": True}))
    run(["xcodebuild", "-exportArchive", "-archivePath", str(path), "-exportPath", str(destination),
         "-exportOptionsPlist", str(options), "-allowProvisioningUpdates"], path.parent / "export.log")
    ipas = list(destination.glob("*.ipa"))
    if len(ipas) != 1:
        raise ValueError("A exportação não produziu exatamente um IPA.")
    verify_ipa(ipas[0], config)
    write_json(path.parent / "export-receipt.json", {"created_at": datetime.now(timezone.utc).isoformat(),
               "identity": identity(config), "ipa": str(ipas[0]),
               "sha256": hashlib.sha256(ipas[0].read_bytes()).hexdigest(), "uploaded": False})
    print(f"IPA conferido: {ipas[0]}")
    return ipas[0]


def transporter(path, config):
    verify_ipa(path, config)
    if not TRANSPORTER.is_file():
        raise ValueError("Instale Transporter pela Mac App Store.")
    run(["open", "-a", "Transporter", str(path)])
    print("Abertura solicitada ao Transporter. Confira se o pacote aparece na janela; se necessário, use Adicionar Pacote e selecione este IPA. Isso ainda não confirma importação ou entrega à Apple.")


def deliver(path, config, confirm):
    if not confirm:
        raise ValueError("Upload não autorizado pelo comando. Use --confirm-upload somente quando decidir enviar esse build.")
    verify_ipa(path, config)
    key, issuer = os.environ.get("ASC_KEY_ID", ""), os.environ.get("ASC_ISSUER_ID", "")
    if not re.fullmatch(r"[A-Za-z0-9]{10}", key) or not re.fullmatch(r"[0-9a-fA-F-]{36}", issuer):
        raise ValueError("Defina ASC_KEY_ID e ASC_ISSUER_ID; mantenha AuthKey_<ID>.p8 no diretório privado reconhecido pelo Transporter, fora do projeto.")
    if not TRANSPORTER.is_file():
        raise ValueError("Transporter não instalado.")
    # The key is read by Apple's tool, never opened or copied by this assistant.
    run([str(TRANSPORTER), "-m", "upload", "-assetFile", str(path), "-apiKey", key, "-apiIssuer", issuer, "-v", "informational"])
    print("Transporter concluiu a entrega. Confira o processamento no App Store Connect; nenhuma publicação foi solicitada.")


@contextmanager
def release_lock():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with (OUTPUT / ".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Outra preparação está em andamento.") from error
        yield


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "prepare", "archive", "inspect", "export", "transporter", "upload", "release"])
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--confirm-upload", action="store_true")
    args = parser.parse_args()
    if args.version and args.command not in ("prepare", "release"):
        parser.error("--version só pode ser usado com prepare ou release.")
    try:
        with release_lock():
            config = configuration()
            if args.command == "status":
                print(json.dumps({"identity": identity(config), "team": config['DEVELOPMENT_TEAM'],
                      "free_gib": round(shutil.disk_usage(ROOT).free / 1024**3, 2), "transporter": TRANSPORTER.is_file(),
                      "note": "A disponibilidade no App Store Connect e o último build enviado não foram consultados."}, indent=2, ensure_ascii=False))
            elif args.command == "prepare":
                print(json.dumps(identity(prepare(args.version)), indent=2))
            elif args.command in ("archive", "release"):
                require_space()
                if args.command == "release":
                    config = prepare(args.version)
                path = archive(config)
                if args.command == "release":
                    transporter(export(path, config), config)
            else:
                if args.path is None:
                    raise ValueError("Informe o caminho do Archive ou IPA.")
                path = args.path.expanduser().resolve(strict=True)
                if args.command == "inspect":
                    archive_info(path, config) if path.suffix == ".xcarchive" else verify_ipa(path, config)
                    print("Identidade e estrutura conferidas localmente.")
                elif args.command == "export":
                    export(path, config)
                elif args.command == "transporter":
                    transporter(path, config)
                else:
                    deliver(path, config, args.confirm_upload)
        return 0
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.CalledProcessError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print(f"Preparação interrompida: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
