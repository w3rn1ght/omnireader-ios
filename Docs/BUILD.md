# Сборка и установка

## 1. GitHub Actions (рекомендуется)

Workflow `.github/workflows/build.yml` уже в репозитории:

- runner `macos-15`, Xcode 16.2;
- Theos + официальный SDK iPhoneOS 12.4;
- `xcrun ibtool` компилирует `LaunchScreen.storyboard`;
- `make package FINALPACKAGE=1` → `packages/*.deb`;
- артефакт `omnireader-deb` (90 дней), тег `v*` создаёт релиз.

Запуск: **Actions → Build → Run workflow**.

## 2. Локально на macOS

```sh
brew install ldid xz
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"
export PATH="$THEOS/bin:$PATH"

# SDK 12.4 (sparse clone)
git clone --depth=1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
cd /tmp/theos-sdks && git sparse-checkout set iPhoneOS12.4.sdk
mkdir -p "$THEOS/sdks" && cp -R iPhoneOS12.4.sdk "$THEOS/sdks/"

cd omnireader
chmod +x layout/DEBIAN/postinst layout/DEBIAN/postrm
make package FINALPACKAGE=1
```

Результат: `packages/com.w3rn1ght.omnireader_1.0.0_iphoneos-arm.deb`.

Полезные цели: `make clean`, `make package FINALPACKAGE=1 DEBUG=0`.

## 3. Установка на устройство

Через пакетный менеджер:

1. Откройте `.deb` в **Sileo / Zebra / Filza** → Install.
2. Если иконки нет: `uicache -p /Applications/OmniReader.app` или respring.

По SSH:

```sh
scp packages/*.deb root@device:/var/root/
ssh root@device
dpkg -i /var/root/com.w3rn1ght.omnireader_1.0.0_iphoneos-arm.deb
uicache -p /Applications/OmniReader.app
killall -9 SpringBoard   # при необходимости
```

Удаление:

```sh
dpkg -r com.w3rn1ght.omnireader
```

## 4. Быстрая сборка без упаковки

```sh
make
make install                 # если настроен THEOS_DEVICE_IP
```

## 5. Как открывать файлы

- «Файлы» → долгое нажатие на книгу → «Поделиться» → OmniReader.
- Почта/Telegram/Safari: «Открыть в…» → OmniReader.
- iTunes/Finder: File Sharing включён (`UIFileSharingEnabled`), файлы можно закинуть в Documents.
- Внутри приложения: «+» → «Импортировать файл» (UIDocumentPicker).

## 6. Частые проблемы

| Симптом | Причина / решение |
| --- | --- |
| `ibtool: command not found` | сборка не на macOS или нет Xcode (`xcode-select -p`) |
| `error: SDK not found` | не установлен `iPhoneOS12.4.sdk` в `$THEOS/sdks` |
| `ldid: command not found` | `brew install ldid` и `export PATH` |
| приложение падает на старте | посмотрите `idevicesyslog \| grep OmniReader`, часто это несовпадение подписи: переустановите deb |
| EPUB пустой | файл с DRM/нестандартный контейнер; проверьте лог `[OmniReader]` |
| Яндекс: 401 | токен истёк — «Настройки → Яндекс Книги → Войти» |
| Яндекс: 404 | изменились пути API — см. `Docs/YANDEX.md` |
| OPDS: «нет файла для скачивания» | это раздел каталога — откройте его; либо каталог отдаёт только HTML-страницы и требует cookie-сессию (Basic Auth недостаточно). В алерте показываются MIME-типы записи, в логе — все ссылки (`idevicesyslog \| grep OPDS`). |
| OPDS: ATS / «requires a secure connection» | каталог отдаёт `http://`. В 1.1.0 исправлено: удалён `NSAllowsArbitraryLoadsInWebContent`, который на iOS 10+ отключал `NSAllowsArbitraryLoads`. Если каталог всё равно не открывается, используйте `https://`. |
| OPDS: поиск не работает | каталог не публикует OpenSearch. Приложение пробует `?q=`; если каталог его не понимает — поиск недоступен на стороне сервера. |

## 7. Требования к подписи

Theos использует ad-hoc подпись (`ldid -S`), этого достаточно для джейлбрейка. Если ставите через AltStore/AppSync, приложение будет работать, но фоновое аудио зависит от entitlements — они выданы в `Info.plist` (`UIBackgroundModes: audio`).
