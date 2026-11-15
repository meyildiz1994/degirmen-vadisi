#!/usr/bin/env python3
"""Değirmen Vadisi ses üretici (yalnızca GELİŞTİRME sırasında çalışır).

ElevenLabs ile audio_manifest.json'daki sesleri üretir ve res://audio altına yazar.
Oyun hiçbir zaman ElevenLabs'i çağırmaz; API anahtarı yalnızca .env dosyasında durur
(.gitignore'da, export'ta hariç). Bu klasör (.gdignore) Godot'ya ve build'e girmez.

Kullanım:
    python tools/generate_audio.py                 # yalnızca eksik dosyaları üret
    python tools/generate_audio.py --only axe_chop footstep_grass
    python tools/generate_audio.py --force axe_chop   # tek bir sesi yeniden üret
    python tools/generate_audio.py --dry-run         # ne üretileceğini göster
    python tools/generate_audio.py --list

Gerekenler: Python 3.9+, ffmpeg (PATH'te). Ek Python paketi gerekmez.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / "audio_manifest.json"
ENV_FILE = ROOT / ".env"
API = "https://api.elevenlabs.io"
SFX_URL = API + "/v1/sound-generation"
MUSIC_URL = API + "/v1/music"
OUT_DIRS = {"sfx": "audio/sfx", "ui": "audio/sfx", "ambience": "audio/ambience", "music": "audio/music"}


# --- Yardımcılar ---------------------------------------------------------------------
def load_api_key() -> str:
    """Anahtar önce .env'den, yoksa ortam değişkeninden okunur. Asla yazdırılmaz."""
    key = ""
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("ELEVENLABS_API_KEY") and "=" in line:
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    key = key or os.environ.get("ELEVENLABS_API_KEY", "")
    if not key:
        sys.exit("ELEVENLABS_API_KEY bulunamadı. Proje kökünde .env dosyasına ekle:\n"
                 "    ELEVENLABS_API_KEY=xxxxxxxx")
    return key


def target_files(entry: dict) -> list[Path]:
    """Ambiyans ve müzik .ogg, kısa efektler .wav; varyasyonlar _1, _2, _3."""
    kind = entry["type"]
    ext = "ogg" if kind in ("ambience", "music") else "wav"
    base = ROOT / OUT_DIRS[kind]
    n = int(entry.get("variations", 1))
    if n <= 1:
        return [base / f"{entry['id']}.{ext}"]
    return [base / f"{entry['id']}_{i}.{ext}" for i in range(1, n + 1)]


def full_prompt(entry: dict, style: str) -> str:
    return f"{entry['prompt']}. Style: {style}."


def post(url: str, key: str, body: dict, retries: int = 3) -> bytes:
    data = json.dumps(body).encode("utf-8")
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method="POST", headers={
            "xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")[:400]
            if e.code in (429, 500, 502, 503) and attempt < retries - 1:
                time.sleep(4 * (attempt + 1))
                continue
            raise RuntimeError(f"HTTP {e.code}: {msg}") from None
        except urllib.error.URLError as e:
            if attempt < retries - 1:
                time.sleep(4 * (attempt + 1))
                continue
            raise RuntimeError(str(e)) from None
    raise RuntimeError("istek başarısız")


def generate_raw(entry: dict, key: str, models: dict, style: str) -> tuple[bytes, str]:
    if entry["type"] == "music":
        model = models.get("music", "music_v2_5")
        body = {"prompt": full_prompt(entry, style), "model_id": model, "force_instrumental": True,
                "music_length_ms": int(float(entry.get("duration", 120)) * 1000)}
        return post(MUSIC_URL + "?output_format=mp3_44100_128", key, body), model
    model = models.get("sfx", "eleven_text_to_sound_v3")
    body = {"text": full_prompt(entry, style), "model_id": model, "prompt_influence": 0.45,
            "duration_seconds": max(0.5, min(30.0, float(entry.get("duration", 1.0)))),
            "loop": bool(entry.get("loop", False))}
    return post(SFX_URL + "?output_format=mp3_44100_128", key, body), model


def convert(src: Path, dst: Path, lufs: float, kind: str) -> None:
    """ffmpeg: loudness normalize + .wav (kısa efekt) ya da .ogg Vorbis (ambiyans/müzik)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    filt = f"loudnorm=I={lufs}:TP=-1.5:LRA=11"
    if kind in ("sfx", "ui"):
        # Baştaki sessizliği kırp: vuruş anında ses gecikmesin.
        filt = "silenceremove=start_periods=1:start_threshold=-50dB," + filt
        codec = ["-c:a", "pcm_s16le", "-ar", "44100"]
    else:
        codec = ["-c:a", "libvorbis", "-q:a", "5", "-ar", "44100"]
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af", filt, *codec, str(dst)]
    subprocess.run(cmd, check=True)


def save_manifest(manifest: dict) -> None:
    tmp = MANIFEST.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    tmp.replace(MANIFEST)


# --- Ana akış ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", metavar="ID", help="bu sesi (tüm varyasyonlarıyla) yeniden üret")
    ap.add_argument("--only", nargs="+", metavar="ID", help="yalnızca bu sesler")
    ap.add_argument("--type", choices=["sfx", "ui", "ambience", "music"], help="yalnızca bu tür")
    ap.add_argument("--dry-run", action="store_true", help="API çağırmadan neyin üretileceğini göster")
    ap.add_argument("--list", action="store_true", help="manifest'teki sesleri ve durumlarını listele")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    style = manifest.get("style", "")
    models = manifest.get("models", {})
    loud = manifest.get("loudness", {})
    generated = manifest.setdefault("generated", {})

    entries = manifest["sounds"]
    if args.force:
        entries = [e for e in entries if e["id"] == args.force]
        if not entries:
            sys.exit(f"manifest'te yok: {args.force}")
    if args.only:
        entries = [e for e in entries if e["id"] in args.only]
    if args.type:
        entries = [e for e in entries if e["type"] == args.type]

    todo = []
    for e in entries:
        for i, path in enumerate(target_files(e)):
            if args.force or not path.exists():
                todo.append((e, i, path))

    if args.list:
        for e in manifest["sounds"]:
            files = target_files(e)
            have = sum(p.exists() for p in files)
            print(f"{e['id']:<18} {e['type']:<9} {have}/{len(files)}")
        return 0
    if not todo:
        print("Tüm sesler mevcut, üretilecek bir şey yok.")
        return 0
    print(f"{len(todo)} dosya üretilecek.")
    if args.dry_run:
        for e, _, p in todo:
            print("  ", p.relative_to(ROOT), "<-", e["prompt"][:70])
        return 0
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg bulunamadı (PATH).")

    key = load_api_key()
    failed = 0
    with tempfile.TemporaryDirectory() as tmpdir:
        for e, i, path in todo:
            rel = path.relative_to(ROOT).as_posix()
            print(f"-> {rel} ...", end=" ", flush=True)
            try:
                raw, model = generate_raw(e, key, models, style)
                src = Path(tmpdir) / f"{path.stem}.mp3"
                src.write_bytes(raw)
                convert(src, path, float(loud.get(e["type"], -18)), e["type"])
            except Exception as ex:  # tek ses başarısız olursa diğerleri devam etsin
                failed += 1
                print("HATA:", ex)
                continue
            generated[rel] = {
                "id": e["id"],
                "date": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                "model": model,
                "prompt": full_prompt(e, style),
                "source": "ElevenLabs API",
            }
            save_manifest(manifest)  # her dosyadan sonra: yarıda kalırsa kayıt kaybolmasın
            print("tamam")
    print(f"Bitti. Başarısız: {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
