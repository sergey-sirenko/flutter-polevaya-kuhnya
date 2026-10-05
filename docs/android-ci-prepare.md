# FL-07-14 — Подготовка Android в Codemagic

Статус 05.10.2026: workflow реализован; мобильная сборка и передача ключей CI ещё не выполнены. Проверка Google Play API ранее прошла отдельно. Текущая версия приложения — `1.0.0+71`.

## Что делает workflow

`android-release-prepare` получает полный SHA, выбранные Android-каналы и текст изменений. Единственный доступный режим — `prepare`. Сборка AAB для Google Play подписывается `upload.p12`; APK для RuStore и прямой установки — `app-signing.p12`. Автоматической проверки установщика и запрета установки вне Google Play не добавляется.

Перед сборкой проверяются совпадение SHA с checkout, чистота tracked-файлов, версия из pubspec, наличие секретов, оба пароля/aliases и ожидаемые сертификаты, HTTPS production-policy и dishes.json, DNS/TLS рабочего API. Бизнес-API не вызывается. Flutter 3.47.1 и Java 17 выбираются в YAML; образ фиксируется через Xcode 26.6 (Android-сборка на M2, iOS не запускается). Gradle/AGP закреплены в репозитории. Для проверки используются Build Tools 36.0.0 и bundletool 1.18.3 с фиксированным SHA-256 скачанного JAR.

Зависимости устанавливаются с `--enforce-lockfile`; lockfile сверяется после установки и каждой сборки. Выполняется analyze; автоматические тесты в этом workflow отсутствуют и требуют отдельного согласования. Flutter build использует штатный pub для корректного release plugin registrant, без изменения lockfile. Версия и номер сборки не увеличиваются скриптом.

AAB проверяется bundletool и чтением всех payload-записей через Java JAR verifier с проверкой сертификата; APK — apksigner и aapt2. Package, versionName/versionCode и сертификаты должны совпасть с ожидаемыми. Только после проверки всех выбранных файлов они копируются в доступный для скачивания каталог. Отчёт хранит SHA, версии, статусы каждого канала, отпечатки, SHA-256 артефактов и lockfile. Ключи декодируются во временный каталог с правами 0600 и удаляются после процесса; в артефакты/отчёт не входят. Сырой вывод команд подписи/Gradle подавляется; при ошибке выводятся команда и exit code без её полного вывода и паролей.

## Секреты: владелец добавляет вручную

Откройте **flutter-polevaya-kuhnya → Environment variables**. Создайте группу `android_release_signing` только для этого приложения. Если используете Personal/Team Settings, установите **Application access → только flutter-polevaya-kuhnya**, не All applications. Для каждой строки включите **Secret**.

| Имя | Значение |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64 всего файла `upload.p12` одной строкой |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Пароль хранилища upload |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Пароль ключа upload (если совпадает — тот же пароль) |
| `ANDROID_APP_SIGNING_KEYSTORE_BASE64` | Base64 всего файла `app-signing.p12` одной строкой |
| `ANDROID_APP_SIGNING_STORE_PASSWORD` | Пароль хранилища app-signing |
| `ANDROID_APP_SIGNING_KEY_PASSWORD` | Пароль ключа app-signing (если совпадает — тот же пароль) |

Aliases фиксированы: `upload` и `app-signing`. Существующие файлы используются без генерации новых ключей. Изменять `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS / google_play_release` не требуется; workflow подготовки не импортирует эту группу.

Следующие команды **владелец выполняет локально**, чтобы скопировать одно значение Base64 в буфер обмена без вывода в терминал. Первая команда — для upload; после сохранения соответствующего секрета выполните вторую для app-signing:

```powershell
Set-Clipboard -Value ([Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\Sergey\PolevayaKuhnyaKeys\upload.p12')))
```

```powershell
Set-Clipboard -Value ([Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\Sergey\PolevayaKuhnyaKeys\app-signing.p12')))
```

Вставляйте значения только в соответствующие поля Codemagic. Пароли вводите там вручную. Base64 не является шифрованием; не сохраняйте значения в Git, чат или обычные файлы. После сохранения очистите текущий буфер `Set-Clipboard -Value ''`. При включённой истории/синхронизации буфера отдельно удалите записи с ключами из истории. Сохранение секретов даёт Codemagic доступ к Android private keys; агент их не передавал, и этот документ не означает, что секреты уже созданы.

## Первый запуск — отдельный согласованный шаг

После подтверждения владельцем сохранения шести секретов:

1. Выберите в Codemagic commit или ветку, содержащую новый workflow. Получите полный SHA этой версии из Git; `accepted_commit` должен точно совпасть с checkout. Скрипт сам не переключается на другую ревизию.
2. Выберите **Android signed artifacts (no store upload)**. Оставьте `mode=prepare`, `stores=google_play,rustore` либо один требуемый канал; заполните `release_notes` (1–500 символов). Ввод через environment vars не исполняется как shell-код.
3. Запуск сборки выполнить только после отдельного поручения. Не выбирайте прежний `iOS Simulator (test)`.
4. Скачайте AAB/APK и архив отчёта. Убедитесь, что `release-report.json` содержит `status=prepared`, оба требуемых канала имеют `status=built`, а файлы совпадают с `SHA256SUMS.txt`.
5. При ошибке сохраняется безопасный `release-report.json`; файлы не выгружаются в магазины. После устранения проблемы запускайте новый CI job. Подготовка не доказывает пользовательскую приёмку устройства.

Результаты: `build/release/android/google_play-<version>+<build>.aab`, `rustore-<version>+<build>.apk`, `release-report.json`, `SHA256SUMS.txt`. Не путать служебную фазу Codemagic Publishing (сохранение CI-артефактов) с отправкой в магазин.

## Что остаётся для полного плана

В этом workflow нет store publishing, production-режима, RuStore API, IPA, повторного использования прошлых артефактов и проверки статусов модерации. Здесь состояния каналов ограничены pending/built; uploaded/submitted/rejected/published появятся в последующих подзадачах.

Занятость номера сборки магазинами **не проверяется в подготовке**: `storeVersionAvailabilityChecked=false` явно записывается в отчёт. Уже принятый Google Play `+71` допускается для повторной локальной подготовки, но не для новой загрузки. Проверка допустимости номера и возобновления заявки будет обязательной до будущей отправки. Номер автоматически не меняется. Privacy/Data safety/FR-A6 остаются препятствиями публичного выпуска. Сборки App Store и приёмка iOS требуют отдельного разрешения.

Код приложения/Web/iOS, pubspec/version.json и локальный интерактивный Android-скрипт не меняются. Пересборка Web для этих CI-файлов не требуется.

## Источники

- [Codemagic inputs](https://docs.codemagic.io/knowledge-codemagic/build-inputs/)
- [Codemagic configuration and secret groups](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)
- [Codemagic environment scope](https://docs.codemagic.io/yaml-basic-configuration/configuring-environment-variables/)
- [Fixed macOS image](https://docs.codemagic.io/specs-macos/xcode-26-6/)
- [Android bundle signing](https://developer.android.com/build/building-cmdline)
- [APK signature verification](https://developer.android.com/tools/apksigner)
