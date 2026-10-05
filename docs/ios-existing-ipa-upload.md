# Загрузка существующего IPA без пересборки

Workflow `ios-existing-ipa-upload` использует уже проверенный IPA
`1.0.0+71` из CI `6ac401007394575b200b6643`, source commit
`594c889cbff139e7ecc8067abaffb863e07abb46`. Manifest
`docs/releases/ios-1.0.0-71.json` фиксирует URL, SHA256, версию и сертификат.
Для следующего артефакта manifest/код нужно отдельно пересмотреть: этот
workflow пока относится к конкретному первому IPA.

App `6819387151`, bundle `ru.obedmoscow.polevayakuhnya`. Codemagic app-level
группа `app_store_connect_release` содержит три Secret:

- `APP_STORE_CONNECT_PRIVATE_KEY` — содержимое нового P8.
- `APP_STORE_CONNECT_KEY_ID` — `KQA8285DNK`.
- `APP_STORE_CONNECT_ISSUER_ID` — `52f09cc4-4799-4d5e-bcd6-b0c0569b46a4`.

Apple Team key имеет App Manager scope ко всем приложениям Apple команды.
App-level хранение в Codemagic этот scope не сужает. Скрипт обращается только
к указанной app; код CI имеет доступ к ключу, поэтому изменения CI нужно
рассматривать как изменения защищённой конфигурации.

## Перед запуском

1. Проверить наличие workflow/скрипта/manifest в выбранном commit origin.
   Сборки/тесты/загрузка при разработке не запускались.
2. После отдельного поручения выбрать `ios-existing-ipa-upload` и `action`.
   По умолчанию `status`: только GET Apple API, без скачивания IPA/отправки.
3. Для `upload` нужно отдельное разрешение передать конкретный IPA Apple.
   Запуск не включает пересборку, review или распространение тестерам.

Xcode image 26.6, bundled Codemagic CLI должен быть 0.69.0 (проверка перед
действиями); CLI не устанавливается автоматически. Фактическую совместимость
publish/altool и доступность artifact URL подтвердит первый отдельный CI.

## Последовательность upload

Проверяется чистый checkout и версия manifest относительно pubspec. JWT ES256
живёт 5 минут, обновляется перед каждым GET, в вывод не попадает. Проверяется
bundle ID app. Apple builds фильтруются по app/buildNumber, сверяется included
preReleaseVersion (version/platform). Existing build не перезагружается:
возвращаются build ID, processingState и expired. FAILED/INVALID/expired
требуют ручного решения с новым номером; старые сборки не удаляются.

Если build отсутствует, IPA скачивается по фиксированному HTTPS Codemagic
artifact URL без Apple credentials. Проверяются SHA256, Info.plist,
embedded profile/expiry/Team/App ID и codesign strict/deep с фактическим
сертификатом. Затем занятость номера проверяется повторно, выполняется
`app-store-connect publish` с package validation и одним upload attempt.
Нет `--testflight`, `--beta-group`, `--app-store`, cancel/expire flags:
внешняя beta review, приглашения тестерам и App Review не запускаются.

Артефакты сохраняют только `build/release/ios-upload/upload-report.json`.
P8 и IPA временные; P8 mode0600, private key CLI `@file`, сырые diagnostics
подавлены. IPA не пересобирается и повторно не артефактится.

## Интерпретация статусов и повтор

- `not_found`: Apple ещё не показывает сборку, режим status ничего не отправил.
- `existing_build`: номер занят, upload пропущен. Report показывает processing
  state; наличие сборки не доказывает совпадение байтов с нашим IPA, Apple
  не возвращает его SHA256. Проверить provenance вручную при сомнениях.
- `uploaded`: upload command успешна; processing и доступ тестерам ещё не
  подтверждены. Затем запускать `status` отдельно, не держать машину на review.
- `upload_unknown`: команда началась, но успех передачи не подтверждён.
  Сначала status и кабинет Apple; не повторять upload до выяснения.
- `failed`: preflight/проверки не прошли либо existing build недопустим.

API может показывать только что загруженную сборку с задержкой. Поэтому
между независимыми CI запуском статусами нет абсолютной защиты от повторной
попытки передачи: Apple отклонит повтор version/build, а владелец должен
разрешить upload только после проверки неопределённого результата. Два
upload запуска одновременно не запускать. Автоматического retry неизвестной
передачи и удаления предыдущей заявки нет. Дальнейший общий release journal
и автоматическое возобновление трёх магазинов остаются отдельной реализацией.

Privacy/FR-A6, export compliance, сведения TestFlight/группа владельца,
проверка на iPhone и App Store metadata не закрываются upload. Подготовленный
App Store IPA нельзя установить на iPhone напрямую: дальнейшая приёмка —
через TestFlight после обработки и настройки владельцем.

Источник команд и разграничения флагов:
[Codemagic CLI publish](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/app-store-connect/publish.md).
