#!/usr/bin/env python3
"""Render review materials and fail closed on missing App Store release evidence."""

import argparse
import hashlib
import html
import json
import math
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SOURCE_LAYOUT = (PROJECT / "release" / "app-store").is_dir()
ROOT = PROJECT / "release" / "app-store" if SOURCE_LAYOUT else PROJECT
FIELDS = {"name": 30, "subtitle": 30, "promotional_text": 170,
          "description": 4000, "whats_new": 4000}
STYLE = """*{box-sizing:border-box}body{margin:0;background:#f6f8f7;color:#17231e;font:17px/1.65 system-ui,-apple-system,sans-serif}main{max-width:1080px;margin:auto;padding:40px 24px 80px}h1{font-size:clamp(30px,5vw,48px);line-height:1.12;letter-spacing:-.04em}h2{font-size:25px;line-height:1.3;margin-top:36px}h3{font-size:19px}a{color:#006a44}a:focus-visible{outline:3px solid #005dff;outline-offset:4px}.notice{padding:18px 22px;background:#fff2d8;border-left:4px solid #936700;border-radius:8px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:20px}.card{padding:24px;background:white;border:1px solid #dce5df;border-radius:20px}.placeholder{aspect-ratio:1320/2868;background:#edf2ef;border:2px dashed #adbbb2;border-radius:18px;display:grid;place-items:center;padding:24px;text-align:center;color:#486153}pre{white-space:pre-wrap;font:inherit}small{font-size:14px;color:#516058}img{max-width:100%;height:auto}li{margin:10px 0}.brand{width:54px;height:auto}.pill{display:inline-block;padding:4px 12px;border-radius:30px;background:#e0f2e7;color:#125d39;font-size:14px}nav{display:flex;flex-wrap:wrap;gap:18px}article{max-width:780px}code{overflow-wrap:anywhere}footer{margin-top:48px;color:#516058}"""


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def safe_path(root, relative):
    """Do not bundle or treat evidence outside the release root as reviewed."""
    root = root.resolve()
    if Path(relative).is_absolute():
        raise ValueError("Use um caminho relativo ao pacote")
    path = root / relative
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise ValueError(f"Caminho fora do pacote ou link simbólico: {relative}")
    return path


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def metadata_errors(data):
    errors = []
    for key, limit in FIELDS.items():
        value = data.get(key)
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            errors.append(f"{key}: obrigatório, máximo {limit} caracteres")
    keywords = data.get("keywords", "")
    if not isinstance(keywords, str) or not keywords or len(keywords.encode("utf-8")) > 100:
        errors.append("keywords: máximo 100 bytes UTF-8")
    elif any(len(word.strip()) <= 2 for word in keywords.split(",")):
        errors.append("keywords: cada palavra deve ter mais de dois caracteres")
    for key in ("support_url", "marketing_url", "privacy_url", "privacy_choices_url"):
        value = data.get(key, "")
        if not isinstance(value, str) or not re.fullmatch(r"https://[^\s<>]+", value):
            errors.append(f"{key}: URL HTTPS necessária")
    return errors


def page(title, body):
    return f'''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>{html.escape(title)}</title><style>{STYLE}</style></head><body><main>{body}<footer>AtendeBem · Preparação de publicação · 02/10/2026</footer></main></body></html>'''


def plain_markdown(source):
    """Intentionally small, escaped renderer; preserves full source without remote scripts."""
    def inline(value):
        value = html.escape(value)
        value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
        value = re.sub(r"`([^`]+)`", r"<code>\1</code>", value)
        return re.sub(r"\[([^\]]+)\]\((https://[^\s)]+)\)", r'<a href="\2">\1</a>', value)

    blocks = []
    for block in source.split("\n\n"):
        if block.startswith("# "):
            blocks.append(f"<h1>{inline(block[2:])}</h1>")
        elif block.startswith("## "):
            blocks.append(f"<h2>{inline(block[3:])}</h2>")
        elif block.startswith("- "):
            blocks.append("<ul>" + "".join(f"<li>{inline(line[2:])}</li>" for line in block.splitlines()) + "</ul>")
        else:
            blocks.append(f"<p>{inline(block)}</p>")
    return "\n".join(blocks)


def render():
    data = read_json(ROOT / "metadata/pt-BR.json")
    errors = metadata_errors(data)
    if errors:
        raise ValueError("; ".join(errors))
    target = ROOT / "metadata/pt-BR"
    target.mkdir(parents=True, exist_ok=True)
    for key, value in data.items():
        (target / f"{key}.txt").write_text(value + "\n", encoding="utf-8")
    site = ROOT / "site"
    site.mkdir(exist_ok=True)
    for path in sorted((ROOT / "policies").glob("*.md")):
        content = plain_markdown(path.read_text(encoding="utf-8"))
        (site / f"{path.stem}.html").write_text(page(path.stem, f"<article>{content}</article>"), encoding="utf-8")
    specs = read_json(ROOT / "media/specification.json")
    status = read_json(ROOT / "release-status.json")
    cards = []
    for shot in specs["shots"]:
        cards.append(f'''<section class="card"><div class="placeholder">Captura real pendente<br>{html.escape(shot['screen'])}</div><h3>{shot['order']:02d}. {html.escape(shot['headline'])}</h3><p>{html.escape(shot['caption'])}</p><small>{html.escape(shot['instruction'])}</small></section>''')
    gates = "".join(f"<li><strong>{html.escape(item['label'])}</strong>: {html.escape(item['status'])} — {html.escape(item['note'])}</li>" for item in status["gates"])
    counts = " · ".join(f"{key}: {len(data[key])}/{limit}" for key, limit in FIELDS.items())
    policies = "".join(f'<li><a href="../site/{p.stem}.html">{html.escape(p.stem.capitalize())}</a></li>' for p in sorted((ROOT / "policies").glob("*.md")))
    body = f'''<nav><a href="#textos">Textos</a><a href="#imagens">Imagens</a><a href="#video">Vídeo</a><a href="#politicas">Políticas</a><a href="#pendencias">Pendências</a></nav><p class="pill">Revisão local · pt-BR</p><h1>{html.escape(data['name'])}</h1><p>{html.escape(data['subtitle'])}</p><p class="notice"><strong>Pacote de preparação.</strong> Esta página organiza os materiais; não simula uma página publicada. As capturas e o vídeo finais ainda precisam ser produzidos com o app real.</p><section id="textos"><h2>Uma rotina mais próxima do cuidado</h2><p>{html.escape(data['promotional_text'])}</p><div class="card"><pre>{html.escape(data['description'])}</pre></div><p><small>{html.escape(counts)} · keywords: {len(data['keywords'].encode('utf-8'))}/100 bytes</small></p><h3>Palavras-chave</h3><p>{html.escape(data['keywords'])}</p></section><section id="imagens"><h2>Oito cenas, quatro abas</h2><p>iPhone: 1320 × 2868 px · iPad: 2064 × 2752 px. Nenhuma imagem fictícia está sendo apresentada como captura do aplicativo.</p><div class="grid">{''.join(cards)}</div></section><section id="video"><h2>App Preview · 25 segundos</h2><p>Hoje → Modelos → Histórico → LARI → Configurações. O roteiro e as legendas estão preparados. A gravação real depende do build e da conta demonstrativa.</p><p><a href="../media/ROTEIRO.md">Roteiro de gravação e exportação</a> · <a href="../media/preview.pt-BR.srt">Legendas</a></p></section><section id="politicas"><h2>Documentos para revisão</h2><ul>{policies}</ul><p>URLs públicas verificadas em 02/10/2026. A política específica do aplicativo ainda requer consolidação:</p><ul>{''.join(f'<li>{html.escape(data[key])}</li>' for key in ('support_url','marketing_url','privacy_url','privacy_choices_url'))}</ul></section><section id="pendencias"><h2>Condições para envio</h2><ul>{gates}</ul></section>'''
    body = '<img src="../brand/app-icon-1024.png" width="96" height="96" alt="Ícone do AtendeBem">' + body
    (ROOT / "preview").mkdir(exist_ok=True)
    (ROOT / "preview/index.html").write_text(page(data["name"], body), encoding="utf-8")
    print("Textos separados, minutas HTML e página de revisão gerados.")


def receipt_errors(path, root):
    receipt_path = path.with_suffix(path.suffix + ".receipt.json")
    if not receipt_path.is_file():
        return [f"{path.name}: falta recibo de captura/revisão"]
    receipt = read_json(receipt_path)
    errors = []
    for key in ("build", "device", "os", "captured_at", "reviewer"):
        if not isinstance(receipt.get(key), str) or not receipt[key].strip():
            errors.append(f"{path.name}: falta {key} no recibo")
    if receipt.get("sha256") != digest(path):
        errors.append(f"{path.name}: recibo não corresponde ao SHA-256 atual")
    if receipt.get("real_app_capture") is not True or receipt.get("synthetic_data_only") is not True:
        errors.append(f"{path.name}: autenticidade/dados sintéticos não confirmados")
    source = receipt.get("source_file")
    if not isinstance(source, str) or not source:
        errors.append(f"{path.name}: falta referência ao original")
    else:
        safe_path(root, source)
    return errors


def image_errors(path, dimensions):
    if path.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
        return [f"{path.name}: formato de imagem inválido"]
    result = subprocess.run(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)], capture_output=True, text=True, check=True, timeout=30)
    values = dict(re.findall(r"(pixelWidth|pixelHeight|hasAlpha):\s+(\S+)", result.stdout))
    actual = [int(values.get("pixelWidth", 0)), int(values.get("pixelHeight", 0))]
    errors = []
    if actual != dimensions:
        errors.append(f"{path.name}: {actual}, esperado {dimensions}")
    if values.get("hasAlpha") != "no":
        errors.append(f"{path.name}: canal alpha ausente não comprovado")
    return errors


def video_errors(path, dimensions):
    probe = shutil.which("ffprobe")
    if probe is None:
        return ["ffprobe compatível não instalado; vídeo não validado"]
    result = subprocess.run([probe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], capture_output=True, text=True, check=True, timeout=30)
    data = json.loads(result.stdout)
    video = [s for s in data["streams"] if s["codec_type"] == "video"]
    errors = []
    if len(video) != 1:
        return [f"{path.name}: deve ter uma faixa de vídeo"]
    stream = video[0]
    if [stream["width"], stream["height"]] != dimensions:
        errors.append(f"{path.name}: dimensões incorretas")
    duration = float(data["format"]["duration"])
    if not math.isfinite(duration) or not 15 <= duration <= 30 or path.stat().st_size > 500_000_000:
        errors.append(f"{path.name}: fora do limite de duração/tamanho")
    numerator, denominator = map(int, stream["avg_frame_rate"].split("/"))
    if denominator == 0 or not 0 < numerator / denominator <= 30:
        errors.append(f"{path.name}: taxa de quadros inválida")
    if stream.get("codec_name") != "h264" or stream.get("field_order") not in {"progressive", None}:
        errors.append(f"{path.name}: este pacote exige H.264 progressivo")
    for audio in (s for s in data["streams"] if s["codec_type"] == "audio"):
        if audio.get("codec_name") != "aac" or audio.get("channels") != 2 or int(audio.get("sample_rate", 0)) not in {44100, 48000}:
            errors.append(f"{path.name}: áudio fora do perfil AAC estéreo")
    return errors


def validate(submission=False):
    errors = metadata_errors(read_json(ROOT / "metadata/pt-BR.json"))
    notes = (ROOT / "review/NOTAS-EN.txt").read_text(encoding="utf-8")
    if len(notes.encode("utf-8")) > 4000:
        errors.append("Notas de revisão excedem 4000 bytes")
    with (ROOT / "privacy/PrivacyInfo.candidate.xcprivacy").open("rb") as source:
        plistlib.load(source)
    specs = read_json(ROOT / "media/specification.json")
    assets = []
    for device in specs["devices"]:
        for shot in specs["shots"]:
            assets.append((f"media/final/{device['id']}/{shot['order']:02d}-{shot['id']}.jpg", "image", device["screenshot_pixels"]))
        assets.append((f"media/final/{device['id']}/preview.mp4", "video", device["preview_pixels"]))
    assets.append(("brand/app-icon-1024.png", "icon", [1024, 1024]))
    missing = []
    for relative, kind, dimensions in assets:
        path = safe_path(ROOT, relative)
        if not path.is_file():
            missing.append(relative)
            continue
        try:
            errors.extend(video_errors(path, dimensions) if kind == "video" else image_errors(path, dimensions))
            if kind != "icon":
                errors.extend(receipt_errors(path, ROOT))
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            errors.append(f"{relative}: não validado ({type(error).__name__})")
    status = read_json(ROOT / "release-status.json")
    pending = []
    for gate in status["gates"]:
        if gate["status"] != "verified":
            pending.append(gate["label"])
        else:
            evidence = gate.get("evidence")
            if not evidence or not safe_path(ROOT, evidence).is_file():
                errors.append(f"{gate['id']}: marcado verificado sem arquivo de evidência")
    if submission:
        errors.extend(f"Mídia ausente: {item}" for item in missing)
        errors.extend(f"Pendente: {item}" for item in pending)
        manifest = PROJECT / "App/PrivacyInfo.xcprivacy"
        if not manifest.is_file():
            errors.append("Manifesto final ainda não integrado ao app")
    report = {"checked_at": datetime.now(timezone.utc).isoformat(), "mode": "submission" if submission else "preparation", "passed": not errors, "submission_ready": submission and not errors,
              "errors": errors, "missing_assets": missing, "pending_gates": pending,
              "limits": "Validação local não substitui revisão de conteúdo, testes no iOS ou validação Apple."}
    (ROOT / "validation-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return not errors


def package():
    render()
    if not validate():
        raise ValueError("Corrija os materiais antes de empacotar")
    output = (PROJECT / "release" if SOURCE_LAYOUT else PROJECT.parent) / "AtendeBem-AppStore-Preparacao.zip"
    allowed = {".md", ".txt", ".json", ".html", ".css", ".xcprivacy", ".srt", ".svg", ".png", ".jpg", ".jpeg", ".mp4"}
    files = []
    for path in sorted(ROOT.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Link simbólico recusado: {path.name}")
        if path.is_file() and path.suffix in allowed and "raw" not in path.relative_to(ROOT).parts:
            safe_path(ROOT, str(path.relative_to(ROOT)))
            files.append(path)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in files:
            bundle.write(path, "AtendeBem-AppStore-Preparacao/" + str(path.relative_to(ROOT)))
        for name in ("app_store_bundle.py", "export_app_preview.py", "export_brand_icon.swift"):
            bundle.write(PROJECT / "scripts" / name, "AtendeBem-AppStore-Preparacao/scripts/" + name)
        bundle.writestr("AtendeBem-AppStore-Preparacao/SHA256SUMS.txt", "\n".join(f"{digest(p)}  {p.relative_to(ROOT)}" for p in files) + "\n")
    print(f"Pacote de preparação: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["render", "validate", "package"])
    parser.add_argument("--submission", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "render":
            render()
        elif args.command == "package":
            package()
        else:
            return 0 if validate(args.submission) else 1
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        print(f"Erro: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
