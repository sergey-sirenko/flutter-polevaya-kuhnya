# Подготовка IPA без отправки в App Store

Workflow `ios-release-prepare` в `codemagic.yaml` запускается вручную только
после отдельного поручения владельца на iOS-сборку. Автоматических triggers,
тестов и publishing нет. Существующий simulator workflow сохранён отдельно.

## Настройки

Codemagic app `flutter-polevaya-kuhnya`, ID `6ab8f89650cf00a2e023cde0`.
App-level группа `ios_release_signing`:

- `IOS_DISTRIBUTION_P12_BASE64` — новый защищённый P12.
- `IOS_PROVISIONING_PROFILE_BASE64` — обновлённый App Store профиль.
- `IOS_DISTRIBUTION_P12_PASSWORD` — пароль P12, введённый владельцем.

Bundle ID `ru.obedmoscow.polevayakuhnya`, Team `F8BS872XC2`, ожидаемый
сертификат SHA1 `0556DF536EE5F42D407B48B6029FCE1FD1ED5E37`.
При смене сертификата нужно явно обновить проверку в скрипте и профиль.

Flutter `3.47.1`, Xcode `26.6`, mac_mini_m2. Используется bundled Codemagic
CLI; его фактическая версия записывается в report, отдельный version pin пока
не установлен. Проект использует Flutter Swift Package Manager, Podfile нет.
Зависимости Flutter берутся с `--enforce-lockfile`; новые SwiftPM resolution
проверяются первым CI-запуском, полностью воспроизводимая SwiftPM фиксация
этим шагом не подтверждена.

## Ручной запуск после разрешения

1. Проверить, что выбранный commit с файлами workflow доступен в origin.
   Локальные изменения Codemagic не видит.
2. Выбрать нужный checkout и `ios-release-prepare`.
3. В `accepted_commit` указать полный 40-значный SHA этого checkout.
4. В `release_notes` ввести 1–500 символов. Текст сохраняется только в отчёте.

Версия X.Y.Z+N читается из pubspec без изменения; build — одна компонента
1…9999. Занятость номера App Store здесь не проверяется: отчёт явно содержит
`storeVersionAvailabilityChecked=false`. Подготовка уже занятого номера
возможна; отправка потребует отдельной проверки через Apple API.

## Проверки и артефакты

Скрипт проверяет чистый checkout/SHA, production version.json, menu JSON,
DNS/TLS API без бизнес-вызовов, версии Flutter/Xcode, profile App ID/Team/
expiry/certificate, доступность приватного ключа через импорт в отдельную
временную keychain. Затем pub get, analyze, archive/export IPA. Автотесты
не запускаются. Production адреса совпадают с Android prepare.

Готовый IPA проверяется codesign strict/deep, bundle/version/build,
embedded profile UUID и SHA1 фактического сертификата подписи. Только после
проверок он копируется в `build/release/ios`, вместе с SHA256SUMS.txt и
release-report.json. Неуспех даёт безопасный report и ненулевой exit.
P12/profile/keychain временные, пароль передаётся CLI через `@env`, сырые
диагностики команд подавлены. Xcode signing edits восстановлены в finally.
В artifacts не включаются archive, temporary keys или исходные журналы.

05.10.2026 macOS CI из 594c889 успешно подготовил и проверил IPA 1.0.0+71.
Xcode 26.6 / Codemagic CLI 0.69.0 / подпись подтверждены этим запуском.
Apple API подключён и read-only доступ проверен. Прежний IPA71 отклонён
валидацией90474. Исправленный IPA72, TestFlight, проверка на iPhone/iPad,
App Privacy/FR-A6, metadata и публичный выпуск — следующие этапы.

Источники: [ручная подпись Codemagic](https://docs.codemagic.io/yaml-code-signing/alternative-code-signing-methods/),
[use-profiles](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/xcode-project/use-profiles.md),
[безопасный аргумент пароля](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/keychain/add-certificates.md).

## Исправление Apple 90474 (06.10.2026)

Apple validation исходного IPA1.0.0+71 отклонила пакет: iPad multitasking
требует четыре ориентации. В Info.plist для iPad добавлены portrait upside down
и оба landscape; iPhone по-прежнему использует portrait. Приложение сохраняет
поддержку iPad (TARGETED_DEVICE_FAMILY=1,2). Flutter orientation lock на iPad
при включённой многозадачности не применяется; повороты/размеры окна требуют
ручной приёмки на iPad. UIRequiresFullScreen не добавлялся.

Номер исправленной сборки —1.0.0+72; pubspec/web version согласованы.
verify_ipa дополнительно проверяет ориентации для iPad с multitasking до
сохранения артефактов. Исправленный IPA пока не собран и Apple не проверен.
Manifest docs/releases/ios-1.0.0-71.json остаётся историческим: перенаправлять
его на новый IPA без проверенного prepare/SHA/source build нельзя.
До нового manifest существующий upload workflow на checkout+72 остановится
из-за несовпадения версии, как предусмотрено.

Источники: [Apple supported orientations](https://developer.apple.com/documentation/uikit/uiviewcontroller/supportedinterfaceorientations),
[Flutter setPreferredOrientations](https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html).
