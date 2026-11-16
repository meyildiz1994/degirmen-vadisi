# Oda kodu aracısı (relay)

Farklı evlerdeki iki oyuncu port açmadan buluşsun diye küçük bir WebSocket sunucusu.
Ev sahibi oyunda **Oyun aç** deyince buradan 6 harfli bir oda kodu alır; arkadaşı bu kodu
yazıp **Katıl** der. Sunucu oyun verisine bakmaz, iki taraf arasında paketleri iletir.
Kayıt tutmaz, hesap istemez.

## Yerelde denemek
```
pip install -r requirements.txt
python relay.py            # ws://127.0.0.1:8765
godot --path . -- --relay=ws://127.0.0.1:8765
```

## Yayına almak (Render, ücretsiz)
1. https://render.com hesabı aç (GitHub ile giriş yeterli).
2. **New → Blueprint** → bu depoyu seç. Kökteki `render.yaml` sunucuyu kendisi kurar.
3. Kurulum bitince adres `https://degirmen-relay-XXXX.onrender.com` gibi olur.
4. `project.godot` içinde `[degirmen] net/relay_url` değerini `wss://degirmen-relay-XXXX.onrender.com`
   yap (https yerine **wss**).

Ücretsiz planda sunucu 15 dakika boşta kalınca uyur; ilk **Oyun aç**'ta uyanması ~30-50 sn
sürebilir (oyun 60 sn bekler). Uyanık kalsın istenirse ücretli plana geçilebilir ya da başka
bir yere (Fly.io, kendi sunucun) aynı Dockerfile ile kurulabilir.
