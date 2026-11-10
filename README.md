# OmniReader для iOS 12 (jailbreak)

Универсальная читалка для устройств на **iOS 12 с джейлбрейком**. Открывает PDF, документы Office, электронные книги и комиксы, проигрывает аудиокниги, интегрирована с Яндекс Книгами (вход в аккаунт) и каталогами OPDS.

> Приложение не содержит контента, не обходит DRM и не является официальным клиентом Яндекса.

## Возможности

| Группа | Форматы |
| --- | --- |
| Книги | EPUB (2 и 3), FB2, FB2.zip, MOBI, AZW/AZW3 (без DRM), TXT, Markdown, HTML |
| Документы | PDF (PDFKit), DOCX, XLSX, PPTX (нативное извлечение текста), DOC/XLS/PPT (QuickLook) |
| Комиксы | CBZ; CBR — только если внутри ZIP |
| Аудио | MP3, M4A, M4B, AAC, FLAC, WAV, прямые ссылки на поток |
| Каталоги | OPDS 1.2 (Project Gutenberg, Calibre и т. п.), Basic Auth |
| Сервисы | Яндекс Книги: OAuth / токен, полка, загрузка книг и аудио |

Читалка:

- постраничная вёрстка на CSS-колонках с плавным перелистыванием;
- темы: бумага, сепия, серый, ночь;
- шрифт, кегль, межстрочный интервал, отступы, выравнивание, переносы;
- оглавление, сохранение прогресса, слайдер страниц;
- озвучка текста голосом (AVSpeechSynthesizer) с любой страницы;
- PDF: непрерывный скролл, масштаб, оглавление по страницам, озвучка страницы;
- комиксы: свайпы, пинч-зум, ленивая загрузка страниц.

Аудиоплеер:

- фоновое воспроизведение и экран блокировки (Now Playing, пульт);
- таймер сна (5–60 минут), скорость 0.75×–3×, ±30 с;
- продолжение с места остановки, мини-плеер в библиотеке.

Библиотека: обложки (из EPUB/FB2/PDF/CBZ), поиск, фильтры, сортировка, импорт из «Файлов», открытие файлов из других приложений, удаление, шаринг.

## Требования

- iOS **12.0–12.5.7**, arm64, джейлбрейк (unc0ver / checkra1n / Chimera).
- Rootful-бутстрап (`iphoneos-arm`).
- Для сборки: macOS + Xcode, [Theos](https://theos.dev), SDK iPhoneOS 12.4, `ldid`, `xz`.

## Сборка

### GitHub Actions

Workflow `.github/workflows/build.yml` собирает `.deb` на `macos-15` с Xcode 16.2, Theos и SDK 12.4:

- push в `main` → артефакт `omnireader-deb`;
- тег `v*` → релиз с `.deb`.

### Локально

```sh
brew install ldid xz
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"

git clone --depth=1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
cd /tmp/theos-sdks && git sparse-checkout set iPhoneOS12.4.sdk
mkdir -p "$THEOS/sdks" && cp -R iPhoneOS12.4.sdk "$THEOS/sdks/"

cd omnireader
make package FINALPACKAGE=1
```

Пакет появится в `packages/`. LaunchScreen компилируется через `xcrun ibtool` (правило в `Makefile`).

## Установка

1. Скачайте `.deb` из артефактов/релизов.
2. Установите через **Sileo / Zebra / Filza** («Install from file»).
3. Или по SSH:

```sh
dpkg -i com.w3rn1ght.omnireader_1.0.1_iphoneos-arm.deb
uicache -p /Applications/OmniReader.app
```

Удаление: `dpkg -r com.w3rn1ght.omnireader`.

## Яндекс Книги

Подробности и ограничения — [Docs/YANDEX.md](Docs/YANDEX.md). Кратко:

- официального публичного API у Яндекс Книг нет; адаптер использует веб-эндпоинты и терпим к изменениям схемы;
- вход: Client ID OAuth (в настройках) либо вставка токена;
- DRM-файлы не расшифровываются — если сервис отдаёт защищённый файл, приложение сообщит об ошибке;
- всегда можно импортировать купленный файл вручную через «+» → «Импортировать файл».

## Структура

```
Makefile, control, Resources/Info.plist   Theos-таргет и метаданные пакета
layout/DEBIAN/                            postinst/postrm (uicache)
Support/LaunchScreen.storyboard           экран запуска
Sources/
  main.m, ORAppDelegate                   запуск, открытие файлов извне
  ORCore                                  модели, библиотека, настройки, Keychain
  ORUtil, ORText, ORXML, ORZip, ORHTTP    утилиты, кодировки, XML, ZIP (zlib), сеть
  OREPUB, ORFB2, ORMOBI, ORPlainTextBook  парсеры книг
  OROfficeText                            текст из DOCX/XLSX/PPTX
  ORMetadata                              обложки и метаданные
  ORPagedAssets, ORPagedReaderController  постраничный ридер
  ORPDFReaderController, OROfficeReaderController, ORComicReaderController
  ORAudioPlayer, ORAudioPlayerController  аудио (фон, таймер сна)
  ORLibraryViewController, ORSettingsViewController, ORReaderSettingsController
  OROPDS*                                 каталоги OPDS
  ORYandex*                               Яндекс Книги
```

## Ограничения

- DJVU не поддерживается.
- CBR (RAR) не распаковывается: конвертируйте в CBZ.
- MOBI/AZW3: PalmDOC-сжатие; HUFF/CDIC и DRM — нет. Конвертация через Calibre решает.
- DOC/XLS/PPT (старый бинарный формат) открываются только QuickLook — извлечение текста для них не делается.
- Встроенный RAR, EPUB с тяжёлыми скриптами и фиксированной вёрсткой могут отображаться упрощённо.
- Приложение не подписано сертификатом Apple — ad-hoc подпись `ldid`, достаточная для джейлбрейка.

## Дисклеймер

Проект предоставляется «как есть». Все права на книги, документы и товарные знаки принадлежат их владельцам. Не используйте приложение для обхода DRM или нарушения условий сервисов.
