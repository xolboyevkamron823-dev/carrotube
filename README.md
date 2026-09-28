# CarroTube

YouTube / YouTube Music ko‘rinishidagi pleer — barcha ovoz Pioneer **Carrozzeria** bosh qurilmasi
(DEH-P01 / DEH-970 / AVH / DMH) DSP’sining nusxasi bo‘lgan C++ dvigatel orqali o‘tadi.
Ekran o‘chiq, ilova yig‘ilgan yoki boshqa ilovaga o‘tilganda ham musiqa to‘xtamaydi.

> Holat: iOS birinchi navbatda yakunlandi (so‘rov bo‘yicha), Android native qatlami ham yozildi.
> Umumiy C++ DSP yadrosi Windows’da g++ bilan kompilyatsiya qilinib, 70 ta unit test o‘tgan;
> Dart kodi `flutter analyze` bilan tekshirilgan. iOS va Android binarlari GitHub Actions’da
> yig‘iladi (bu kompyuterda Xcode/NDK yo‘q).

---

## 1. Papkalar tuzilmasi

```
CarroTube/
├── pubspec.yaml                     ilova paketlari
├── assets/carro/sound_fields.json   Sound Field rejimlari jadvali (quloq bilan sozlanadi)
├── lib/
│   ├── main.dart, app.dart
│   ├── core/        l10n (uz/ru/en), theme (YouTube ranglari), router (5 tab), format
│   ├── data/        models, youtube_service (youtube_explode_dart), database (SQLite),
│   │                library, download_manager, settings, feed
│   ├── player/      player_controller (navbat, autoplay, shuffle/repeat, URL yangilash)
│   ├── dsp/         sound_profile (barcha Carrozzeria parametrlari), sound_controller
│   └── ui/          shell (pastki menyu + mini pleer + watch overlay), home, explore,
│                    search, watch, player, queue, library, channel, playlist, settings,
│                    sound/ (Carrozzeria uslubidagi ekranlar)
├── ios/Runner/      Info.plist (UIBackgroundModes=audio, mikrofon), AppDelegate, SceneDelegate
├── packages/carro_native/           native plagin (Flutter plugin)
│   ├── lib/src/dsp_ffi.dart         dart:ffi → C++ dvigatel
│   ├── lib/src/dsp_params.dart      parametr ID’lari (carro_api.h bilan bir xil)
│   ├── lib/src/native_player.dart   carro/player, carro/system, carro/ircapture kanallari
│   ├── ios/carro_native.podspec     CocoaPods
│   ├── ios/carro_native/Package.swift   Swift Package Manager
│   ├── ios/carro_native/Sources/
│   │   ├── CarroDSP/core/           ★ UMUMIY C++17 DSP YADROSI (iOS + Android)
│   │   │   ├── carro_api.h/.cpp     C ABI
│   │   │   └── dsp/                 fft, biquad, eq, asr, reverb_algo, convolver,
│   │   │                            speakers (crossover/TA/fader), limiter, analysis, wav, engine
│   │   ├── CarroDSP/CarroAudioBridge.mm   MTAudioProcessingTap → C++
│   │   └── carro_native/            Swift: CarroNativePlugin, CarroPlayer (AVPlayer),
│   │                                CarroVideoTexture, CarroIRCapture (AVAudioEngine)
│   ├── android/CMakeLists.txt       libcarro_dsp.so (umumiy yadro + JNI)
│   ├── android/src/main/cpp/        carro_jni.cpp
│   ├── android/src/main/kotlin/…    CarroNativePlugin, CarroPlayerCore (ExoPlayer),
│   │                                CarroAudioProcessor, CarroPlaybackService (Media3),
│   │                                CarroIrCapture, CarroSystem (batareya), CarroDspJni
│   └── tests/                       C++ unit testlar + CMakeLists.txt
├── android/app/…/MainActivity.kt    keshlangan FlutterEngine, PiP
└── .github/workflows/build.yml      CI: DSP testlari + imzosiz iOS .ipa
```

## 2. Signal zanjiri (qat’iy tartib)

```
Input → SLA → ASR → GEQ → Loudness/Bass Boost → SOUND FIELD → Crossover →
Level/Phase → Time Alignment → Fader/Balance → Limiter → Output
```

* 32-bit float, 44.1/48 kHz (istalgan 8–384 kHz), blokli ishlov (512 namunalik bo‘laklar).
* Audio oqimida **qulf yo‘q, xotira ajratish yo‘q**: parametrlar lock-free triple-buffer orqali,
  konvolver obyektlari atomic pointer almashinuvi bilan uzatiladi.
* Parametrlarni silliqlash (zipper/klik yo‘q), strukturaviy o‘zgarishlarda (EQ 13↔31, Network
  rejimi, filtr yoqish/o‘chirish) 12 ms fade, Sound Field almashishida 30 ms wet-fade.
* Denormal himoya: har callback’da FTZ/DAZ (x86 MXCSR, ARM64 FPCR.FZ, ARMv7 FPSCR) + feedback
  zanjirlarida anti-denormal ofset.
* A/B (bypass) — kechikishi moslangan quruq signal bilan 15 ms crossfade.
* Desktop o‘lchovi: to‘liq zanjir (13-band EQ + ASR + Concert Hall + Network 3-way + TA) bitta
  yadroning ~1.7 %i. O‘rta telefon uchun <10 % CPU.

## 3. Carrozzeria funksiyasi → DSP realizatsiyasi

| Carrozzeria funksiyasi | Diapazon / qadam | DSP realizatsiyasi (fayl) |
|---|---|---|
| **SLA** (Source Level Adjuster) | −4…+4 dB, 1 dB | Silliqlangan kirish kuchaytirgichi (`engine.cpp`, `inGain_`) |
| **ASR** (Advanced Sound Retriever) OFF/MODE1/MODE2 | 3 holat | 3.5 kHz (MODE2: 2.5 kHz) LR4 HPF → darajaga bog‘liq bo‘lmagan 2-/3-garmonika generatori (x·\|x\|/env) → post-HPF → mix; tez/sekin envelope nisbati bilan transient tiklash (+2 / +4 dB) (`asr.cpp`) |
| **GEQ 13-band** 50…12.5 kHz | −12…+12 dB, 1 dB | 13 ta RBJ peaking biquad, Q=2.15 (2/3 oktava), 32 namunada koeffitsient qayta hisobi, 0 dB bandlar o‘tkazib yuboriladi (`eq.cpp`) |
| GEQ presetlari SUPER BASS, POWERFUL, NATURAL, VOCAL, FLAT, CUSTOM1, CUSTOM2 | — | `sound_profile.dart` (`eqPresets13`). Pioneer zavod egri chiziqlarini e’lon qilmagan — qiymatlar quloq bilan tanlangan, tahrirlanadi |
| **Pro 31-band** 1/3 oktava | −12…+12 dB | 31 ta RBJ peaking, Q=4.32, ISO 20 Hz…20 kHz (`eq.cpp`) |
| Network rejimida alohida **L/R EQ** | — | Har kanal uchun alohida egri (`eq[2][31]`, `P.eqBand` index = ch·32+band) |
| **LOUDNESS** OFF/LOW/MID/HIGH | 4 holat | Low-shelf 100 Hz (+3.5/+6.5/+9.5 dB) + high-shelf 10 kHz (+2/+3.5/+5 dB) (`eq.cpp`, `ToneStage`) |
| **BASS BOOST** | 0…+6 | 60 Hz peaking, Q=0.8, 1.5 dB/qadam |
| **Crossover Standard**: FRONT HPF, REAR HPF, SUB LPF | 25 Hz…12.5 kHz (1/3 okt. qadamlar) | Butterworth 1…6-tartib yoki Linkwitz-Riley (LR2/LR4/LR6) kaskadlari, log-chastota bo‘yicha silliqlangan (`biquad.h designCrossover`, `speakers.cpp`) |
| **Crossover Network 3-way**: HIGH HPF, MID HPF+LPF, SUB LPF | 25 Hz…12.5 kHz | Xuddi shu kaskadlar, MID ikkala filtr bilan |
| Slope | −6/−12/−18/−24/−30/−36 dB/okt | BW tartibi = slope/6; LR juft tartiblar uchun BW(N/2)² |
| Kanal **LEVEL** | −24…+10 dB | Silliqlangan kuchaytirish (fader bilan birga) |
| **PHASE** NORMAL/REVERSE | — | Ishorali silliqlangan gain (+g ↔ −g, klik yo‘q) |
| **SUBWOOFER** ON/OFF + level | −24…+10 dB | Mono (L+R)/2 → LPF → level/phase → o‘z TA kechikishi → ikkala chiqishga |
| **Time Alignment** (TA) | 0…350 cm, 2.5 cm | Masofa modeli: `delay = (d_max − d) / 343 m/s`, har virtual karnay uchun fraksiyali (lineer interpolatsiya) silliqlangan kechikish (`speakers.cpp`) |
| TA presetlari OFF / FRONT-LEFT / FRONT-RIGHT / FRONT / ALL / CUSTOM (= Listening Position) | — | Odatdagi chap-rulli sedan masofalari (`taPresetDistances`) |
| **Sonic Center Control** | L15…R15 | Bir tomondagi karnaylarga qadamiga 2.5 cm (≈0.073 ms) qo‘shimcha kechikish → markaz tasviri siljiydi |
| **FADER / BALANCE** | −15…+15 | Front/rear og‘irliklari (Network rejimida fader o‘chadi, xuddi qurilmadagidek), balans chiziqli −∞ gacha |
| Telefon/quloqchinda simulyatsiya | CAR / HEADPHONES | Virtual karnaylar stereo’ga yig‘iladi (TA → interaural kechikish); HEADPHONES: Bauer uslubidagi crossfeed (700 Hz LP, 0.25 ms) |
| **Sound Field** OFF, STUDIO, JAZZ CLUB, CONCERT HALL, CATHEDRAL, STADIUM, LIVE, DOME | LEVEL 0…10, SIZE S/M/L | 2 dvigatel (quyida) |
| Algoritmik rejim | — | Pre-delay 8–45 ms → image-source erta aks-sadolar (har manba uchun 24 ta 1–2 tartibli tasvir, ≤150 ms) → 4 bosqichli allpass diffuziya → **8×8 Hadamard FDN**, modulyatsiyalangan kechikish chiziqlari, ikki polosali so‘nish (low multiplier + mid) + uzunlikka bog‘liq HF damping (Jot), M/S kenglik, wet HPF 150 Hz + LPF (`reverb_algo.cpp`). CONCERT HALL M: **RT60 = 1.99 s** (500 Hz/1 kHz, test bilan tekshirilgan) |
| Konvolyutsiya rejimi (haqiqiy 1:1) | IR ≤ 6 s | True-stereo (LL, LR, RL, RR) **non-uniform partitioned FFT**: bosh qism B=256 audio oqimida, dum P=4096 ishchi oqimda (P namuna zaxira vaqti bilan, CPU sakrashlarisiz), kechikish 256 namuna, quruq yo‘l moslangan (`convolver.cpp`) |
| Dry/Wet, pre-delay, IR trim, loudness match | — | IR energiyasi bo‘yicha normallash + teng quvvatli mix → ON/OFF bir xil balandlik (test: 0.01 dB farq) |
| LEVEL / SIZE | 0…10 / S-M-L | Algoritmik: wet −20…−4 dB (unit-energy wet, kalibrlash render orqali), SIZE → o‘lchamlar ×0.8/1/1.25, RT60 ×0.82/1/1.22. Konvolyutsiya: har rejim+o‘lcham uchun alohida IR sloti |
| **IR capture** (qurilmadan o‘lchash) | 20 Hz–20 kHz, 10 s | Eksponensial sinus sweep (Farina), regularizatsiyalangan spektral bo‘lish, avtomatik kechikish tekislash, shovqin sathi bo‘yicha qirqish, fade, normallash, 4-kanalli WAV (`analysis.cpp`, `CarroIRCapture.swift`) |
| REW import | WAV 16/24/32-int, 32/64-float, 1/2/4 kanal | `wav.cpp` + Kaiser-sinc resampler |
| Yakuniy **true-peak brickwall limiter** | ceiling −6…0 dBTP | 4× polifaza interpolyatsiya detektori, 1.5 ms look-ahead, sliding-min + release + box-car (nazariy jihatdan overs yo‘q) (`limiter.cpp`) |
| Spektr analizatori, meterlar | — | Lock-free chiqish tapi → 4096-FFT → log bandlar (`analysis.cpp`) |

## 4. C++ unit testlar

`packages/carro_native/tests/dsp_tests.cpp` — 70 ta tekshiruv:
filtrlar javobi (RBJ, BW/LR slope’lari, LR yig‘indisi tekisligi), GEQ impuls javobi (13/31),
to‘liq zanjir impuls testi (sof kechikish), A/B va strukturaviy o‘zgarishlarda klik yo‘qligi,
RT60 o‘lchovi (barcha rejimlar), reverb barqarorligi va dekorrelyatsiyasi, konvolyutsiya ↔
to‘g‘ridan-to‘g‘ri konvolyutsiya (inline va threaded), denormal yo‘qligi (30 s sukunat),
clipping yo‘qligi (+12 dB EQ, true-peak), IR capture (sweep → deconvolution, korrelyatsiya 1.0000),
WAV + IR yuklash + loudness match, unumdorlik.

```bash
cmake -S packages/carro_native/tests -B build/dsp -DCMAKE_BUILD_TYPE=Release
cmake --build build/dsp -j 8
ctest --test-dir build/dsp --output-on-failure
```

## 5. iOS: yig‘ish va sideload (Mac kerak emas)

Windows’da iOS ilovani to‘g‘ridan-to‘g‘ri yig‘ib bo‘lmaydi (Xcode faqat macOS’da). Shuning uchun
imzosiz `.ipa` GitHub’ning bepul macOS serverida yig‘iladi, keyin **Sideloadly** yoki **AltStore**
uni sizning Apple ID’ingiz bilan imzolaydi.

### 5.1. GitHub Actions orqali IPA
1. github.com’da yangi **private** repozitoriy oching (masalan `carrotube`).
2. `CarroTube` papkasini unga yuklang:
   ```bash
   git init
   ```
   ```bash
   git add . && git commit -m "CarroTube" && git branch -M main
   ```
   ```bash
   git remote add origin https://github.com/<login>/carrotube.git && git push -u origin main
   ```
3. Repozitoriyda **Actions → build** ishga tushadi (yoki *Run workflow*). ~15–25 daqiqadan so‘ng
   **Artifacts** bo‘limidan `CarroTube-ios-unsigned-ipa` ni yuklab oling va zip’dan chiqaring →
   `CarroTube-unsigned.ipa`.

### 5.2. Sideloadly (Windows)
1. iTunes (Apple saytidan, Microsoft Store versiyasi emas) va Sideloadly’ni o‘rnating.
2. iPhone’ni USB bilan ulang, “Trust this computer”.
3. Sideloadly’da `.ipa` ni tanlang, Apple ID kiriting (parolni Sideloadly’ning o‘zi so‘raydi), **Start**.
4. iPhone: *Settings → General → VPN & Device Management* → Apple ID’ingizga ishonch bering.
   iOS 16+: *Settings → Privacy & Security → Developer Mode* ni yoqing.
5. Bepul Apple ID bilan ilova 7 kun ishlaydi — Sideloadly/AltStore bilan qayta imzolanadi.

### 5.3. AltStore
AltServer’ni kompyuterga o‘rnating → iPhone’ga AltStore’ni o‘rnating → AltStore’da **My Apps → +**
→ `CarroTube-unsigned.ipa`. AltStore har 7 kunda Wi-Fi orqali avtomatik yangilaydi.

### 5.4. Mac bo‘lsa (ixtiyoriy)
```bash
flutter pub get
```
```bash
flutter build ios --release --no-codesign
```
yoki Xcode’da `ios/Runner.xcworkspace` → Signing → o‘z jamoangiz → Run.

### Muhim iOS eslatmalari
* Fon rejimi: `UIBackgroundModes = audio`, `AVAudioSession.playback`; ilova fonga o‘tganda video
  treklari o‘chiriladi, ovoz uzilmay davom etadi (PiP faol bo‘lsa video qoladi).
* Lock screen / Control Center / Bluetooth va rul tugmalari: `MPRemoteCommandCenter` +
  `MPNowPlayingInfoCenter` (rasm, seek, oldingi/keyingi).
* Qo‘ng‘iroq/uzilishlar, quloqchin/Bluetooth uzilishi (pauza) va mashinaga qayta ulanganda davom
  etish (sozlamalarda) qo‘llab-quvvatlanadi.
* **CarPlay**: now-playing va rul tugmalari ishlaydi; to‘liq CarPlay ilova interfeysi uchun Apple’ning
  `com.apple.developer.carplay-audio` ruxsatnomasi kerak — bepul/sideload imzoda bu mumkin emas.
* YouTube’ning HLS oqimlariga MTAudioProcessingTap ulanmaydi, shuning uchun iOS’da DASH
  MP4/AAC audio + H.264 video oqimlari ishlatiladi (HD uchun AVMutableComposition).
* dart:ffi statik bog‘langan C++ belgilarini topishi uchun Runner’da `STRIP_STYLE = non-global`.

## 6. Android: yig‘ish va o‘rnatish

Arxitektura (`packages/carro_native/android`):
* `CarroPlayerCore` — process darajasidagi Media3 **ExoPlayer**; audio-only, muxed yoki
  `MergingMediaSource` (alohida video + audio oqimlari), YouTube User-Agent sarlavhasi,
  audio focus (qo‘ng‘iroqlar), `setHandleAudioBecomingNoisy` (quloqchin chiqarilsa pauza),
  Bluetooth/mashina qayta ulanganda davom ettirish.
* `CarroAudioProcessor` — ExoPlayer `AudioProcessor`, har bir namuna JNI orqali C++ DSP’dan
  o‘tadi (`libcarro_dsp.so`; Dart ham shu kutubxonani dart:ffi bilan ochadi — bitta dvigatel).
* `CarroPlaybackService` — `MediaLibraryService` (foreground, media notification, lock screen,
  rul/Bluetooth tugmalari, **Android Auto** ro‘yxati = navbat + keyingilar).
* `MainActivity` keshlangan `FlutterEngine` ishlatadi (`shouldDestroyEngineWithHost=false`):
  ilova “recents”dan surib yopilganda ham musiqa va Dart navbat mantiqi ishlashda davom etadi.
* PiP: `supportsPictureInPicture`, Android 12+ da video ijro etilayotganda avtomatik PiP.
* Batareya: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + Xiaomi/Samsung/Huawei/Oppo/Vivo
  autostart ekranlariga to‘g‘ridan-to‘g‘ri o‘tish (Sozlamalar → Fonda ijro).

### 6.1. GitHub Actions orqali APK
`build` workflow’i `CarroTube-android-apk` artefaktini beradi (`app-arm64-v8a-release.apk` —
zamonaviy telefonlar uchun). Telefonga yuklab, “Noma’lum manbalardan o‘rnatish”ga ruxsat bering.

### 6.2. Kompyuterda (Android Studio bilan)
Android Studio o‘rnating (SDK 36, NDK va CMake 3.22.1 ni SDK Manager’dan qo‘shing), keyin:
```bash
flutter pub get
```
```bash
flutter build apk --release --split-per-abi
```
Natija: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

### 6.3. Birinchi ishga tushirishdan keyin
Sozlamalar → **Fonda ijro** bo‘limida batareya optimallashtirishni o‘chiring va telefoningiz
brendi uchun ko‘rsatilgan qadamlarni bajaring (Xiaomi: Autostart + “No restrictions”,
Samsung: “Unrestricted” + Sleeping apps ro‘yxatidan chiqarish, Huawei: App launch → Manual).
