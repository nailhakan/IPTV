# IPTV

Xtream Codes tabanlı, **Flutter** ile yazılmış bir IPTV oynatıcı. Bilgisayarda (Linux) ve Android TV / TV stick'te çalışır. Oynatıcı olarak **mpv** (`media_kit`) kullanır: filmlerin içindeki **tüm ses ve altyazı parçalarını** listeler, yaygın kodekleri oynatır.

> Uygulama **hiçbir içerik sağlamaz**. Kullanıcı kendi IPTV aboneliğinin bilgileriyle giriş yapar.

---

## Şu anki aşama

**Çalışan bir v1 var ve günlük kullanımda.** Masaüstü (Linux) ve TV stick'te (Xiaomi Mi TV Stick, Android 9, 1 GB RAM) denendi. Kaynak kodu bu depoda yayınlandı (MIT lisansı). Eski Electron sürümünün yerine geçer.

| Alan | Durum |
|---|---|
| Xtream girişi, canlı / film / dizi listeleri | ✅ Tamam |
| Oynatıcı (ses/altyazı seçimi, sarma, devam et) | ✅ Tamam |
| Masaüstü arayüzü (Linux) | ✅ Tamam, kurulu |
| TV / kumanda desteği (Android TV, Fire/Mi Stick) | ✅ Çalışıyor, gerçek cihazda denendi |
| Yerel önbellek (hızlı açılış) | ⏳ Sırada |
| Dizilerde otomatik sonraki bölüm | ⏳ Sırada |
| Gelişmiş arama (Türkçe karakter duyarsız) | ⏳ Sırada |
| Favori kanalları kendi sıranla dizme | ⏳ Fikir |
| Windows / macOS / iOS | ❌ Planda yok (iOS için Mac + 99 $/yıl gerekir, vazgeçildi) |

---

## Özellikler

### Giriş ve hesaplar
- **Profil ekranı:** kayıtlı hesaplar büyük kartlar olarak gösterilir, son kullanılan başta.
- **Otomatik giriş:** açılışta son kullanılan hesapla doğrudan girer. "Vazgeç / kullanıcı değiştir" ile iptal edilebilir; çıkış yapınca tekrar otomatik girmez.
- **Çoklu hesap**, düzenleme modunda onaylı silme.
- **Parolalar işletim sistemi anahtarlığında** saklanır (libsecret / KDE Cüzdan / Android Keystore). Anahtarlık yoksa düz tercihlere düşer.
- **Telefondan giriş (QR):** TV'de kumandayla yazmak zor olduğu için ekranda QR çıkar, telefonla okutup bilgileri telefonda yazarsın. Yalnızca yerel ağda, tek kullanımlık rastgele adres.
- Hesap doğrulama; hatalı girişte açık hata mesajı.
- **Eşzamanlı bağlantı sayacı** (Ayarlar → Hesap): "1 / 2 kullanımda".

### İçerik
- **Canlı TV, Filmler, Diziler, Favoriler, Ana Sayfa** sekmeleri.
- **Ana Sayfa:** "Kaldığın yerden devam et", "Son izlenenler", "Son eklenen filmler / diziler".
- **Film / dizi detay sayfası:** afiş, puan, yıl, süre, tür, özet, oyuncular, yönetmen; dizilerde sezon ve bölüm listesi (bölüm görseli, süre, özet, "devam ediliyor").
- **Canlı TV'de program rehberi (EPG):** her kanalda şu anki program ve ilerleme çubuğu, oynatıcıda "Şimdi / Sıradaki". Çağrılar sınırlı ve önbellekli.
- **Favoriler** (kalp ikonu) ve **izleme geçmişi**, kaldığın yerden devam.
- **Kategori yönetimi:** gizleme, **sürükleyerek / oklarla sıralama**, "en üste al", sağ tık menüsü. Sıra canlı, film ve dizi için ayrı tutulur.
- **Yinelenenleri gizleme** ("Tümü" görünümünde aynı adlı kayıtları birleştirir), yetişkin içeriği filtresi.
- **Sıralama:** varsayılan, yeni eklenen, A–Z, yıl.
- **Temiz başlıklar:** "Kör Nokta |2009| TR-EN" → "Kör Nokta" + `2009` `TR` `EN` rozetleri; kategori adlarındaki sağlayıcı öneki kaldırılır.

### Oynatıcı
- Videonun içindeki **tüm ses ve altyazı parçalarını** listeler ve seçtirir (Chromium'un yapamadığı şey; bu yüzden mpv).
- Tercih edilen ses/altyazı dili ayarı (Türkçe / İngilizce).
- **Hızlanan sarma** (10 sn → 30 sn → 1 dk → 5 dk → 10 dk) ve kumandayla çalışan **"Zamana git"** penceresi.
- Oynatma hızı, ses, sessiz, tam ekran, kaldığın yerden devam.
- **Hata yönetimi:** canlı yayın koparsa otomatik yeniden bağlanma; **bağlantı sınırı doluysa** nedeni açıkça söyler ("Bağlantı sınırı dolu (2/2)…").
- Klavye: `Boşluk`, `←/→`, `↑/↓`, `M`, `F`, `Esc`; medya tuşları.

### Arayüz ve TV
- **Arayüz ölçeği** (%50–%140), TV'de varsayılan %70.
- **Kumanda (TV) modu:** belirgin odak çerçevesi, kumandayla gezinme, metin alanlarına **OK ile giriş** (ekran klavyesi odak gelince kendiliğinden açılmaz), oynatıcıda "video modu / çubuk modu".
- Fare üstüne gelince büyüyen kartlar, ortak afiş bileşeni.
- 1 GB'lık cihazlar için **bellek optimizasyonları:** küçük mpv ön belleği, hızlı (anahtar kareye) sarma, küçük çözünürlüklü afişler.

### Ayarlar
Hesap · Oynatıcı (dil, sarma süresi, ön bellek, donanım hızlandırma, devam et) · İçerik (yetişkin, yinelenen, gizli kategoriler) · Görünüm (kumanda modu, ölçek) · Kısayollar.

---

## Kurulum ve çalıştırma

**Gereksinimler:** Flutter SDK, Linux için `clang cmake ninja gtk3` ve **`mpv`** (libmpv). Android için ayrıca JDK 17 + Android SDK.

```bash
flutter pub get
flutter run -d linux
```

**Linux'a kurmak** (`~/.local` altına, kök yetkisi gerekmez; menüde "IPTV" ve `iptv` komutu):

```bash
flutter build linux --release
./linux/packaging/install.sh
```

**Android TV / stick** (cihazda geliştirici seçenekleri ve USB hata ayıklama açık olmalı):

```bash
flutter build apk --release --target-platform android-arm   # 32 bit ARM stick'ler için
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Testler:**

```bash
flutter analyze
flutter test      # 39 test
```

---

## Proje yapısı

```
lib/
  main.dart                  tema, arayüz ölçeği, başlangıç
  src/
    xtream.dart              Xtream API istemcisi (giriş, canlı, film, dizi, EPG, detay)
    accounts.dart            hesap depolama (anahtarlık) + son kullanılan
    login_page.dart          profil kartları, otomatik giriş, ekleme formu
    remote_entry.dart        telefondan giriş (QR + yerel sunucu)
    home_page.dart           sekmeler, listeler, kategori yönetimi, sıralama
    detail_page.dart         film / dizi detayı
    player_page.dart         mpv oynatıcı, kumanda modları, hata/yeniden bağlanma
    settings.dart / settings_page.dart
    library.dart             favoriler, geçmiş, devam konumu
    epg_widgets.dart         program rehberi önbelleği
    title_utils.dart         başlık/kategori temizleme
    poster_card.dart, focus_frame.dart, tv_text_field.dart, ui_scale.dart
test/                        birim ve widget testleri
linux/packaging/             install.sh, uygulama ikonu
```

---

## Bilinen sınırlar

- Yalnızca **Xtream Codes** (M3U listesi desteği yok).
- Cihazlar arası **eşitleme yok**: favoriler, geçmiş ve kategori sırası her cihazda ayrı.
- Liste her açılışta sunucudan iniyor (yerel önbellek yok); 1 GB'lık stick'te büyük listeler yavaş açılabilir.
- Dizilerde bir sonraki bölüme **otomatik geçiş yok**.
- Arama düz "içerir" araması (Türkçe karakterleri ayırt eder).
- TV'de kumandayla parola yazmak zahmetli: QR ile girişi kullan.
- `mpv` sistemde kurulu olmalı (Linux).
- Kumanda desteği Xiaomi Mi TV Stick'te denendi; diğer TV cihazlarında ayar gerekebilir.

## Yol haritası

1. Yerel önbellek (SQLite): listeleri diske kaydedip uygulamayı anında açmak.
2. Dizilerde otomatik sonraki bölüm.
3. Arama: Türkçe karakter duyarsız, film/dizi/kanalı birlikte tarayan genel arama.
4. Favori kanalları kendi sıranla dizme (örn. "bugünkü maçlar").
5. Canlı TV'de kanal numarası ve yukarı/aşağı ile hızlı geçiş, günlük program rehberi.
6. Cihazlar arası favori / geçmiş eşitleme.

## Lisans

[MIT](LICENSE). Uygulama içerik sağlamaz; yayınları kullanıcının kendi aboneliği sağlar ve sorumluluk kullanıcıya aittir.
