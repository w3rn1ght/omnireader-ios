# Архитектура

## Слои

```
UI (UIKit)
 ├─ ORLibraryViewController      библиотека, импорт, мини-плеер
 ├─ ORSettingsViewController     настройки приложения
 ├─ ORPagedReaderController      постраничный ридер (EPUB/FB2/TXT/Office-текст)
 ├─ ORPDFReaderController        PDFKit
 ├─ OROfficeReaderController     QuickLook + текстовый фолбэк
 ├─ ORComicReaderController      CBZ
 ├─ ORAudioPlayerController      UI аудиоплеера
 ├─ ORYandexViewController       полка Яндекса
 └─ OROPDSViewController         каталоги OPDS

Домен / сервисы
 ├─ ORLibrary / ORSettings       JSON + UserDefaults + Keychain
 ├─ ORBookImporter               копирование, sniffing формата, метаданные
 ├─ ORMetadata                   обложки: PDF/EPUB/FB2/CBZ/Office
 ├─ ORAudioPlayer                AVPlayer, Now Playing, таймер сна
 ├─ OROPDS                       Atom-парсинг, Basic Auth, загрузка
 └─ ORYandexAPI / ORYandexAuth   неофициальный API + OAuth

Форматы
 ├─ OREPUB        ZIP → OPF → единый HTML (data: и file:// ресурсы)
 ├─ ORFB2         XML → HTML, base64-изображения на диск
 ├─ ORMOBI        PalmDB + PalmDOC, EXTH
 ├─ ORPlainTextBook TXT/HTML/Markdown
 └─ OROfficeText  DOCX/XLSX/PPTX → HTML

Инфраструктура
 ├─ ORZip   ZIP-ридер на zlib (deflate), защита от zip-slip
 ├─ ORXML   маленькое DOM-дерево поверх NSXMLParser
 ├─ ORText  кодировки (UTF-8/BOM/windows-1251/KOI8-R/…), HTML-хелперы
 ├─ ORHTTP  NSURLSession-обёртка
 └─ ORUtil  пути, алерты, цвета, изображения
```

## Поток открытия книги

1. `ORReaderFactory openBook:…` определяет формат.
2. Тяжёлые форматы парсятся в фоне (`QOS_CLASS_USER_INITIATED`), UI создаётся на главном потоке.
3. Для текстовых книг парсер возвращает:
   - `htmlBody` — `<section data-chapter>` на главу;
   - `extraCSS` — стили книги;
   - `basePath` — каталог с ресурсами;
   - `toc` — `ORTOCItem[]`.
4. `ORPagedReaderController` собирает HTML (`ORPagedAssets`), пишет его в `basePath/__omnireader.html` и грузит через `loadFileURL` (доступ к картинкам/шрифтам).
5. JS-пагинатор (`window.Omni`) считает колонки, отдаёт состояние через `WKScriptMessageHandler`, а нативные свайпы/слайдер вызывают `Omni.goTo`.

## Пагинация

`#content` — multicol-контейнер фиксированной высоты, ширина колонки `--pw - 2*--gutter`, `margin-left: --gutter`. Колонки уходят вправо за пределы `#viewport` (overflow hidden), страница = `scrollLeft`, шаг = ширина вьюпорта.

`Omni` умеет: `prepare(fraction)`, `relayout(fraction)`, `next/prev`, `goTo`, `goToAnchor`, `applyStyle`, `state`. Смена темы/шрифта не перезагружает документ — меняются CSS-переменные и вызывается `relayout`.

## Прогресс

Хранится как доля 0…1 в `ORBook.progress` (`library.json`). Для текста — номер страницы / (всего−1), для PDF — индекс страницы, для аудио — время / длительность, для комиксов — индекс изображения.

## Файлы на устройстве

```
~/Application Support/OmniReader/
  library.json
  Books/<uuid>.<ext>
  Covers/<uuid>.jpg
  Extracted/<uuid>/          распакованные EPUB/FB2/TXT/Office
~/Library/Caches/OmniReader/ временные загрузки
```

## Память

- EPUB целиком распаковывается на диск, в память попадает только один HTML-документ.
- Комиксы держат в `NSCache` не больше 5 страниц.
- ZIP читается через `NSDataReadingMappedIfSafe`, распаковка — потоковая.

## Совместимость с iOS 12

Не используются: SwiftUI, Combine, async/await, `UIMenu`, SF Symbols, `UTType`, scenes. Проверки `@available(iOS 13.0, *)` — только для косметики.
