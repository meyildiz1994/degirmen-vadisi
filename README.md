# Değirmen Vadisi

Suluboya görünümlü, cozy bir 3D craft oyunu. Godot **4.7.2-stable**, GDScript, **Mobile** renderer.
Hedef: Steam (PC / Steam Deck), Android, iOS.

Tüm görseller kodla üretilir (primitive + SurfaceTool/ArrayMesh, shader, FastNoiseLite).
Tek harici varlık: OFL lisanslı **Patrick Hand** fontu (`fonts/`).

## Durum: Aşama 6 (eşya hafızası, ayarlar, kayıt, başarımlar). Sesler en sona bırakıldı.

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
| Giriş (klavye/gamepad/dokunmatik) | `scripts/input_manager.gd`, `scenes/ui/touch_controls.tscn`, oyun imleci `scripts/ui/cursor_art.gd`|
| Arayüz (görev, ipucu, duraklat menüsü) | `scenes/ui/hud.tscn`, `scenes/ui/watercolor_theme.tres` |
| Autoload'lar | `autoload/game_state.gd`, `save_system.gd`, `platform_services.gd`, `audio_manager.gd` |
| Ses bus'ları | `audio/default_bus_layout.tres` (Music, SFX, Ambience, UI) |
| Çeviri (TR/EN) | `locale/strings.csv` |

### Aşama 2: toplama

| Sistem | Dosya |
|---|---|
| Malzeme / kaynak / alet verisi | `data/materials.json`, `data/resources.json` |
| Formüller (alet gücü, vuruş sayısı, sallanma süresi) | `scripts/materials.gd`, `scripts/tool_item.gd` |
| Heybe (malzeme sınırsız, alet slotlu) | `scripts/inventory.gd` (GameState.inventory) |
| Toplanabilir kaynak + durum makinesi | `scripts/gathering/gatherable.gd`, `tree_gatherable.gd`, `rock_gatherable.gd`, `pickup_gatherable.gd` |
| Ağaçlar (kesme, devrilme, kütük, fidan) | `scripts/world/tree_field.gd` |
| Ritim vuruşu, otomatik alet seçimi | `scripts/gathering/gather_controller.gd`, `scripts/ui/rhythm_ring.gd` |
| Parçacık, ganimet uçuşu, odak parlaması, dikim | `gather_fx.gd`, `drop_flyer.gd`, `focus_highlight.gd`, `plant_spot.gd` |
| Dünya tarafı + kayıt | `scripts/gathering/gather_world.gd` |
| Metinsiz eğitim (ilk taş balta/kazma) | `scripts/tutorial.gd`, `scripts/ui/icon_hint_card.gd`, `item_icon.gd` |
| Heybe paneli, toplama kartları | `scripts/ui/inventory_panel.gd`, `pickup_feed.gd` |

**Vuruş formülü:** `vuruş = ceil(5 · (kaynak_sertliği / alet_gücü)²)`, alet kaynaktan yumuşaksa ×1.5 (en fazla 24).
Alet gücü = baş malzemenin sertliği × ağız çarpanı (esneklik + işlenebilirlik). Taş balta meşede 5, demir balta 2 vuruş.
Tatlı vuruş 2× ilerleme. Körelmiş alet yarı güçle çalışır, asla engellenmez.

Test: `godot --headless --path . res://tests/test_gathering.tscn`

### Aşama 3: atölye

| Sistem | Dosya |
|---|---|
| Kalıplar (Sap, Balta Başı, Kazma Başı, Kiriş, Bağlantı, Çark Kanadı, Dişli) | `data/molds.json` |
| Üretim formülleri ve tahmin | `scripts/crafting.gd` |
| Atölye paneli (kalıplar / yuvalar / tahmin çubukları) | `scenes/workshop/workshop_panel.gd`, `scripts/ui/stat_bar.gd`, `scripts/ui/modal_panel.gd` |

### Aşama 4: köprü onarımı

| Sistem | Dosya |
|---|---|
| Onarım yerleri ve istenen özellik eşikleri | `data/repairs.json` |
| Onarım mantığı (takma, zayıf parça, çatlama, kayıt) | `scripts/repair.gd`, `scripts/world/repair_site.gd` |
| Köprü (yuvalar, rampalar, geçiş kapıları, animasyon) | `scenes/world/bridge.gd` |
| Onarım paneli (istenen ↔ seçilen parça) | `scripts/ui/repair_panel.gd` |

Köprü 2 kiriş + 1 bağlantı ister. Kiriş: Sağlamlık ≥ 5, Esneklik ≥ 2 (meşe ve demir tutar; çam zayıf, taş kırılgan).
Bağlantı: Sağlamlık ≥ 4, Esneklik ≥ 4 (meşe ve bakır tutar; saz zayıf). Eşiği tutmayan parça da takılır,
köprü açılır, ama oyuncu iki kez geçtikten sonra batı kıyıya döndüğünde çatlar (oyuncu karşıda mahsur kalmaz).
Onarım bitince `ACH_BRIDGE_REPAIRED` başarımı açılır, görev demir damarına yönelir.

### Oyun testi sonrası netlik geçişi

| Sistem | Dosya |
|---|---|
| Malzeme kartı: 5 özellik çubuğu + "neye yarar" notu (atölye ve heybe) | `scripts/ui/material_card.gd` |
| Kalıp açıklaması ve "Yapıldı: X" sonuç kartı | `scenes/workshop/workshop_panel.gd` |
| Alet kemeri (sağ üst): sahip olunan aletler, dayanıklılık, eldeki parlak | `scripts/ui/tool_belt.gd` |
| Görev işaretçisi: hedefin yeri ve mesafesi, ekran dışındaysa kenarda ok | `scripts/ui/quest_marker.gd` |
| Köprüden sonra: demir kaz → demirden alet yap → değirmeni incele | `scripts/tutorial.gd` |
| Animasyonlar: kurulma, çarpma + kısa duraksama, savrulma, çömelip alma | `scenes/player/player_model.gd` |

Oyuncu bir ağaca/kayaya yaklaşınca uygun aleti kendiliğinden eline alır; aletin başı malzemesinin rengindedir.
Vuruşta gövde öne atılır ve ezilir (yay-sönüm), kamera çok hafif sarsılır, kaya basılıp geri gelir.

### Aşama 5: değirmen duvarı, çark ve final

| Sistem | Dosya |
|---|---|
| Yeni kalıplar: Duvar Taşı (gövde + harç), Aks | `data/molds.json` |
| Onarım yerleri: duvar (3 sıra), çark (aks + dişli + 6 kanat) | `data/repairs.json` |
| Çok yuvalı parçalar ("block:stone:clay") | `scripts/crafting.gd` |
| Yıkık duvar, sıra sıra örülür | `scenes/world/mill_wall.gd`, `scripts/world/stone_wall.gd` |
| Çark: eğik/kırık → doğrulur, kanatlar takılır, döner, su sıçratır | `scenes/world/mill_wheel.gd` |
| Final sahnesi (kamera, ışık, pencere, ışık tozları, final müziği) | `scripts/world/finale.gd` |

Duvar: Sağlamlık ≥ 6, Ağırlık ≥ 7, Bağlama ≥ 7 → taş (ya da demir) gövde + kil harç. Saz/dal harç zayıf.
Çark kanadı: Hafiflik ≥ 3, Suya dayanım ≥ 6 → yalnız meşe (taş ağır, çam çürür). Dişli: Hassasiyet ≥ 5,
Sağlamlık ≥ 4 (meşe, bakır). Aks: Sağlamlık ≥ 6, Dayanıklılık ≥ 6 (meşe, demir, taş).
Zayıf parça takılırsa yapı çalışır ama değirmende süreyle (duvar 50 sn, çark 40 sn) çatlar.
Duvar ve çark ilk kez birlikte tamamlanınca final oynar (etkileşim tuşu ile geçilebilir); sonra serbest oyun.

### Aşama 6: eşya hafızası, ayarlar, kayıt, başarımlar

| Sistem | Dosya |
|---|---|
| Eşya hafızası: aşınma/koyulaşma, 50 kullanımda isim, geçmiş, tamir | `scripts/item_memory.gd`, `scripts/tool_item.gd` |
| Heybede alet geçmişi ve tamir düğmesi (baş malzemesinden 1) | `scripts/ui/inventory_panel.gd` |
| Ses ayarları (Müzik, Efektler, Doğa, Arayüz), duraklatma menüsünde | `scripts/ui/volume_settings.gd` |
| Başarımlar bir kez açılır, kayda yazılır, Steam'e yeniden bildirilir | `autoload/platform_services.gd` |
| Otomatik kayıt (90 sn, onarım bitince, kapanış, mobilde arka plan) | `autoload/save_system.gd` |

İsim, aletin kimliğinden seçilen bir sıfat + malzeme + alet: "Yaşlı Taş Balta", "Loyal Iron Axe".
Sıfat anahtar olarak saklanır, dil değişince isim de çevrilir. Geçmiş: "12 ağaç kesti, köprüyü onardı".
Testler ve ekran görüntüsü aracı oyuncunun kaydını okumaz ve yazmaz.

## Sesler (ElevenLabs, yalnızca geliştirme sırasında)

```
echo "ELEVENLABS_API_KEY=..." > .env       # git'e ve build'e girmez
python tools/generate_audio.py --dry-run   # neyin üretileceğini göster
python tools/generate_audio.py             # sadece eksik dosyaları üret
python tools/generate_audio.py --only axe_chop footstep_grass amb_stream
python tools/generate_audio.py --force axe_chop   # tek sesi yeniden üret
```

Ses listesi, model adları ve hedef ses seviyeleri `tools/audio_manifest.json` içinde. Her üretimden sonra
tarih, model ve prompt `generated` bölümüne yazılır (lisans kaydı). Efektler `.wav`, ambiyans/müzik `.ogg`.

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
| look | Sağ tuş basılıyken fareyi sürükle | Sağ çubuk | Sağ yarıda sürükle |
| interact (topla / kes / kır / dik / onar) | E veya imlecin altındakine sol tık | A | Sağ alttaki "Etkileşim" |
| inventory | Tab / I | Y | Üstteki "Heybe" |
| pause | Esc | Start | Üstteki ‖ butonu |
| quest_log (görev kartı) | J veya sağ üstteki ikon | D-pad yukarı | Sağ üstteki görev ikonu |
| (geliştirici) kalite | F5 | LB | Duraklat menüsü |
| (geliştirici) dokunmatik önizleme | F2 | | |

## Ekran görüntüsü aracı (geliştirici)

```
godot --path . -- --screenshot=user://shot.png --quality=2 --locale=tr
godot --path . -- --screenshot=user://wide.png --cam=16,9,18,-3,0.5,-10
godot --path . -- --screenshot=user://anim.png --give=1 --player=-9.5,9.5,90 --side_cam=4 --anim=strike:0.02
godot --path . -- --screenshot=user://made.png --workshop=axe_head,iron,handle:branch --craft=1
godot --path . -- --screenshot=user://mill.png --mill_cam=7,2.6,4.5 --mill_wall=stone,stone,- --mill_wheel=3
godot --path . -- --screenshot=user://final.png --mill_wall=stone,stone,stone --mill_wheel=8 --finale=6
```

## Gizli anahtarlar

`.env` (ElevenLabs anahtarı) `.gitignore`'da ve tüm export preset'lerinde `exclude_filter` ile hariç.
`tools/` klasörü `.gdignore` ile içe aktarılmaz ve export'a girmez.
