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

## Режимы чтения

- **Вбок** — `#content` это multicol-контейнер фиксированной высоты. Ширина колонки равна `viewport − 2·gutter`, `column-gap` — `2·gutter`, поэтому шаг ровно равен ширине экрана: `scrollLeft = page·width`. JS сам выставляет ширину/отступы/`column-gap` в пикселях (без `calc()`), чтобы избежать расхождений на iOS 12.
- **Вниз** — колонки отключаются, документ прокручивается нативно (`window.scrollTo`), прогресс считается по `scrollTop / (scrollHeight − innerHeight)`.

`Omni` умеет: `prepare(fraction)`, `relayout(fraction)`, `next/prev`, `goTo`, `goToAnchor`, `find`, `applyStyle`, `state`. Смена темы/шрифта/направления не перезагружает документ — меняются CSS-переменные и вызывается `relayout`.

## Интерфейс ридера

Верхняя панель: выход, название, поиск, оглавление. Нижняя: слайдер, номер страницы (тап — быстрый переход по номеру/проценту), кнопки «назад/вперёд», `Aa`, закладки (`📑`, долгое нажатие — список), озвучка, переключение направления (`↕`). Панели скрываются тапом по тексту; тап по пустому месту панели тоже закрывает интерфейс.

## Закладки

Хранятся в `ORBook.bookmarks` (JSON в `library.json`): `fraction`, `page`, `note`, `createdAt`. Добавление/удаление — кнопкой на текущей странице, заметка — через диалог. Список — долгое нажатие на `📑`.

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
