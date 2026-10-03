#!/usr/bin/env python3
"""Export only an existing real app capture. Requires native ffmpeg + ffprobe."""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--device", choices=["iphone", "ipad"], required=True)
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--audio", type=Path, help="Optional original/licensed narration, at least 25 seconds")
    args = parser.parse_args()
    try:
        if not args.capture.is_file() or args.output.exists() or args.start < 0:
            raise ValueError("Informe uma captura existente, início >= 0 e saída nova")
        ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
        if not ffmpeg or not ffprobe:
            raise ValueError("Instale ffmpeg e ffprobe compatíveis com a arquitetura desta máquina")
        probe = subprocess.run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(args.capture)], capture_output=True, text=True, check=True)
        data = json.loads(probe.stdout)
        if float(data["format"]["duration"]) < args.start + 25:
            raise ValueError("A captura deve ter pelo menos 25 segundos após o início selecionado")
        track = next(s for s in data["streams"] if s["codec_type"] == "video")
        width, height = (886, 1920) if args.device == "iphone" else (1200, 1600)
        if abs(track["width"] / track["height"] - width / height) > .01:
            raise ValueError("Proporção da captura não corresponde ao dispositivo; não transformar iPhone em iPad")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        command = [ffmpeg, "-n", "-ss", str(args.start), "-i", str(args.capture)]
        if args.audio:
            if not args.audio.is_file():
                raise ValueError("Narração inexistente")
            command += ["-i", str(args.audio)]
        command += ["-map", "0:v:0"]
        if args.audio:
            command += ["-map", "1:a:0", "-af", "apad", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2"]
        else:
            command += ["-an"]
        # Minimal padding preserves the real capture; no replacement UI or invented scenes.
        command += ["-t", "25", "-vf", f"scale={width}:{height}:force_original_aspect_ratio=decrease:force_divisible_by=2,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30", "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p", "-b:v", "11M", "-maxrate", "12M", "-bufsize", "24M", "-movflags", "+faststart", str(args.output)]
        subprocess.run(command, check=True)
        print("Exportação concluída. Inspecione o vídeo, confirme os direitos e crie o recibo; não é aprovação para upload.")
    except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError) as error:
        print(f"Vídeo não exportado: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
