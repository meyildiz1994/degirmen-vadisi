# tools/

Geliştirme araçları. Bu klasör Godot tarafından içe aktarılmaz (`.gdignore`) ve hiçbir
export'a girmez (export_presets.cfg → `exclude_filter`).

- `generate_audio.py` + `audio_manifest.json` → **Aşama 2**'de eklenecek (ElevenLabs).
  API anahtarı yalnızca proje kökündeki `.env` dosyasından (`ELEVENLABS_API_KEY`) okunur;
  `.env` git'e ve build'lere girmez.
