# Загрузка существующего IPA без пересборки

Workflow `ios-existing-ipa-upload` использует уже проверенный IPA
`1.0.0+72` из CI `6ac528287394575b200bbaa9`, source commit
`f47895509bcf1da287accb68f45b27acdff63d25`. Manifest
`docs/releases/ios-1.0.0-72.json` фиксирует URL, SHA256, версию и сертификат.
Manifest71 остаётся историческим: его IPA отклонён Apple90474.
IPA72 содержит исправленные четыре ориентации iPad; Apple validation ещё
нужно подтвердить отдельным запуском. Разрешение передачи IPA71 не заменяет
конкретное согласование передачи нового IPA72.
Для следующего артефакта manifest/код нужно отдельно пересмотреть: этот
workflow пока относится к конкретному первому IPA.

App `6819387151`, bundle `ru.obedmoscow.polevayakuhnya`. Codemagic app-level
группа `app_store_connect_release` содержит три Secret:

- `APP_STORE_CONNECT_PRIVATE_KEY` — содержимое нового P8.
- `APP_STORE_CONNECT_KEY_ID` — `KQA8285DNK`.
- `APP_STORE_CONNECT_ISSUER_ID` — `52f09cc4-4799-4d5e-bcd6-b0c0569b46a4`.

Для скачивания IPA в режиме `upload` в этой же app-level группе нужен Secret
`CODEMAGIC_ARTIFACT_API_TOKEN`: личный Codemagic API token пользователя,
имеющего доступ к исходному build. Скрипт использует его только для GET
фиксированного адреса артефакта. Это не отдельный read-only token: реальные
права определяются ролью пользователя Codemagic. Хранение в группе этой app
не ограничивает права самого токена. Владелец подключает его отдельно;
значение не помещается в Git, manifest, URL или журнал. `status` и найденная
существующая сборка Apple не требуют этого токена.

Источник: [Codemagic API authentication](https://docs.codemagic.io/rest-api/codemagic-rest-api/)
и [Artifacts API](https://docs.codemagic.io/rest-api/artifacts/).

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
4. Для диагностики выбрать `validate`: проверка SHA/подписи и Apple package
   validation через publish --enable-package-validation --skip-package-upload.
   Сборка в магазине не создаётся; передача прежнего IPA Apple уже разрешена.
   По исходникам CLI0.69.0 этот набор флагов выполняет validation и пропускает
   upload. Ни группы, ни review flags не задаются.

Вывод неудачной команды Apple сохраняется в `appleDiagnostics` (до20KB),
после удаления PEM/private keys, известных Secret значений, JWT, auth headers
и URL. Исходный вывод не печатается и не публикуется отдельным артефактом.
Отчёт содержит `validationAttempted`, `validationPassed`, `validationExitCode`
и при отправке `uploadExitCode`. Режим upload сначала выполняет отдельную
валидацию, затем повторно проверяет существующие builds и запускает upload.
Ошибка валидации оставляет `uploadAttempted=false`; ошибка upload означает
`upload_unknown`, требует проверки Apple перед повтором.

Источник поведения validation/skip flags:
[Codemagic CLI0.69.0 publish action](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/src/codemagic/tools/app_store_connect/actions/publish_action.py).

Xcode image 26.6. Workflow устанавливает codemagic-cli-tools==0.69.0 из PyPI
в отдельный venv build/ios-upload-tools и использует его Python/PATH.
Версия пакета и вывод CLI записываются в отчёт до проверки версии.
Режим передаётся непосредственно как обязательный --action из inputs.action;
переменная IPA_ACTION и молчаливый fallback на status больше не используются.
Default в форме остаётся status. Фактическую совместимость
publish/altool и доступность artifact URL подтвердит первый отдельный CI.

## Последовательность upload

Проверяется чистый checkout и версия manifest относительно pubspec. JWT ES256
живёт 5 минут, обновляется перед каждым GET, в вывод не попадает. Проверяется
bundle ID app. Apple builds фильтруются по app/buildNumber, сверяется included
preReleaseVersion (version/platform). Existing build не перезагружается:
возвращаются build ID, processingState и expired. FAILED/INVALID/expired
требуют ручного решения с новым номером; старые сборки не удаляются.

Если build отсутствует, IPA скачивается по фиксированному HTTPS Codemagic
artifact URL с Codemagic `x-auth-token`, без Apple credentials.
Публичная ссылка не создаётся. При HTTPS redirect на хранилище token удаляется
из заголовков, HTTP redirect запрещён. Token исключён из окружения дочерних
команд проверки/публикации. HTTP-код скачивания записывается как
`artifactHttpStatus`, тела ошибок/URL перенаправлений не раскрываются.
Отсутствующий token останавливает скачивание с понятной причиной.
Проверяются SHA256, Info.plist,
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
