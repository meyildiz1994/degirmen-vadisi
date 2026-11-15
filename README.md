# Değirmen Vadisi

Suluboya görünümlü, cozy bir 3D craft oyunu. Godot **4.7.2-stable**, GDScript, **Mobile** renderer.
Hedef: Steam (PC / Steam Deck), Android, iOS.

Tüm görseller kodla üretilir (primitive + SurfaceTool/ArrayMesh, shader, FastNoiseLite).
Tek harici varlık: OFL lisanslı **Patrick Hand** fontu (`fonts/`).

## Durum: Aşama 1

| Sistem | Dosya |
|---|---|
| Ana sahne | `scenes/world/world.tscn` |
| Arazi / dere / şelale | `scripts/world/valley_shape.gd`, `valley_terrain.gd`, `river_water.gd` |
| Gün batımı, gökyüzü, sis, uzak tepeler | `scripts/world/atmosphere.gd`, `shaders/sky.gdshader` |
| Ağaç / çimen / saz (MultiMesh) | `scripts/world/vegetation.gd`, `shaders/foliage.gdshader` |
| Kaynak görselleri (taş, bakır, demir, kil) | `scripts/world/resource_props.gd` |
| Yıkık değirmen, yıkık köprü | `scenes/world/mill.tscn`, `bridge.tscn` |
| Atölye kulübesi | `scenes/workshop/workshop.tscn` |
| Oyuncu + SpringArm3D kamera | `scenes/player/player.tscn` |
| Suluboya nesne shader'ı + kenar çizgisi | `shaders/watercolor_object.gdshader`, `watercolor_outline.gdshader`, `watercolor_common.gdshaderinc` |
| Ekran efekti (kâğıt, taşma, kenar beyazlatma, Kuwahara) | `shaders/watercolor_screen.gdshader`, `scenes/ui/screen_effect.tscn` |
| Materyal kütüphanesi + palet | `scripts/render/watercolor_materials.gd`, `palette.gd`, `mesh_kit.gd` |
| Giriş (klavye/gamepad/dokunmatik) | `scripts/input_manager.gd`, `scenes/ui/touch_controls.tscn` |
| Arayüz (görev, ipucu, duraklat menüsü) | `scenes/ui/hud.tscn`, `scenes/ui/watercolor_theme.tres` |
| Autoload'lar | `autoload/game_state.gd`, `save_system.gd`, `platform_services.gd`, `audio_manager.gd` |
| Ses bus'ları | `audio/default_bus_layout.tres` (Music, SFX, Ambience, UI) |
| Çeviri (TR/EN) | `locale/strings.csv` |

`/scripts` altındaki `materials.gd`, `crafting.gd`, `inventory.gd`, `repair.gd`, `item_memory.gd`,
`save_system.gd` ve `/tools/generate_audio.py` ilgili aşamalarda eklenecek.

### Kalite katmanları

| | Düşük (mobil varsayılan) | Orta | Yüksek (PC varsayılan) |
|---|---|---|---|
| Basamaklı ışık, kâğıt dokusu, renk kaydırma, kenar beyazlatma | ✓ | ✓ | ✓ |
| Kenar çizgisi (inverted hull), renk taşması, ıslak kenarlar | | ✓ | ✓ |
| Kuwahara, 512 px noise, 2048 gölge atlası | | | ✓ |

Oyunda **F5** (veya gamepad LB) ya da duraklat menüsündeki "Grafik" butonu kaliteyi değiştirir.

## Kontroller

| Aksiyon | Klavye/Fare | Gamepad | Dokunmatik |
|---|---|---|---|
| move | WASD / oklar | Sol çubuk | Sol yarıda sanal joystick |
| look | Fare (oyun alanına tıkla) | Sağ çubuk | Sağ yarıda sürükle |
| interact | E | A | Sağ alttaki "Etkileşim" |
| inventory | Tab / I | Y | Üstteki "Heybe" |
| pause | Esc | Start | Üstteki ‖ butonu |
| (geliştirici) kalite | F5 | LB | Duraklat menüsü |
| (geliştirici) dokunmatik önizleme | F2 | | |

## Ekran görüntüsü aracı (geliştirici)

```
godot --path . -- --screenshot=user://shot.png --quality=2 --locale=tr
godot --path . -- --screenshot=user://wide.png --cam=16,9,18,-3,0.5,-10
```

## Gizli anahtarlar

`.env` (ElevenLabs anahtarı) `.gitignore`'da ve tüm export preset'lerinde `exclude_filter` ile hariç.
`tools/` klasörü `.gdignore` ile içe aktarılmaz ve export'a girmez.
