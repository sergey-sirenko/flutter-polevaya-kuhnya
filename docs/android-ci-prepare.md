# FL-07-14 — Подготовка Android в Codemagic

Статус 05.10.2026: шесть signing secrets подключены на уровне приложения; подготовка AAB/APK в Codemagic успешно выполнена из `16fd44e4af559a63a539afbfefd7df7ba139bb54`. Подписи и контрольные суммы скачанных файлов проверены локально. Загрузки в магазины не было; установка именно этих CI-файлов на телефон ещё не выполнена. Проверка Google Play API ранее прошла отдельно. Версия приложения — `1.0.0+71`.

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


**05.10.2026 — FL-07-14, два Android keystore сохранены в Codemagic.** Владелец прямо разрешил сохранить upload.p12 и app-signing.p12 как два Secret только flutter-polevaya-kuhnya, пароли вводит самостоятельно. Выполнены два Add в Application environment variables: ANDROID_UPLOAD_KEYSTORE_BASE64 и ANDROID_APP_SIGNING_KEYSTORE_BASE64 / android_release_signing / Secret checked. Значения получены из существующих файлов C:/Users/Sergey/PolevayaKuhnyaKeys, без вывода Base64 в чат/терминал и без сохранения новой локальной копии. После reload и открытия Environment variables обе строки присутствуют, значения замаскированы, группа app-level подтверждена. Google API secret не изменялся.

Снимок build/play-signing/codemagic-signing-keystores-saved.jpg. Подготовлена пустая форма ANDROID_UPLOAD_STORE_PASSWORD с android_release_signing и Secret enabled для владельца. Осталось вручную добавить четыре password Secret: ANDROID_UPLOAD_STORE_PASSWORD, ANDROID_UPLOAD_KEY_PASSWORD, ANDROID_APP_SIGNING_STORE_PASSWORD, ANDROID_APP_SIGNING_KEY_PASSWORD. Пароли не читались/не передавались агентом, первый prepare-run не запускался; фактическая работоспособность CI-подписи ещё не проверена. +71, runtime-код, YAML без изменений в этой подзадаче; тесты/сборки/iOS/публикация/коммит не выполнялись.

Следующая: остаток FL-07-14 — ручной ввод четырёх password Secret и сверка списка; сложность 2/10; трудоёмкость низкая, ≈1% пакета; LLM средняя; основание — ввод владельцем и точные имена/группа, внешнее ожидание отдельно. Затем prepare-run только отдельным поручением. Остановка для ручного ввода и по AGENTS.md. «Пересобрать Web и обновить тестовый flutter-test.obedmoscow.ru по SSH»: технически не требуется.


**05.10.2026 — FL-07-14, все шесть Android signing secrets подтверждены в UI.** После сообщения владельца «сделал» проверен app-level список Application environment variables flutter-polevaya-kuhnya: оба ANDROID_*_KEYSTORE_BASE64 и четыре ANDROID_UPLOAD/APP_SIGNING_STORE/KEY_PASSWORD присутствуют в android_release_signing, значения замаскированы. Значения/пароли не раскрывались. Это подтверждение имён и области группы, не успешной подписи; правильность паролей/декодирования проверит первый prepare-run. Снимок build/play-signing/codemagic-signing-six-secrets.jpg, вкладка оставлена. Google API secret без изменений. Сборки/тесты/iOS/публикация/коммит не запускались; +71 сохранена.

Следующая: FL-07-14 — первый android-release-prepare из конкретного Git SHA, без отправки в магазины; сложность 4/10; трудоёмкость средняя, ≈4% пакета; LLM средняя; основание — CI-инструменты/подписи/проверка двух артефактов и отчёта, ожидание машины отдельно. Требуется новое поручение на запуск по остановке AGENTS.md; текущий b4980cf уже в origin/master, номер 71 менять автоматически нельзя и повторно загружать в Play не нужно. «Пересобрать Web и обновить тестовый flutter-test.obedmoscow.ru по SSH»: технически не требуется.


**05.10.2026 — FL-07-14, Android CI prepare успешно завершён.** Повтор #2 https://codemagic.io/app/6ab8f89650cf00a2e023cde0/build/6ac3c52b7394575b200b53d2 / commit 16fd44e4af559a63a539afbfefd7df7ba139bb54 завершился Finished. Подготовительный шаг 4m56s, Publishing 5s — только сохранение CI artifacts. В отчёте status=prepared, mode=prepare, version=1.0.0, versionCode=71, google_play/rustore status=built, storeUploadPerformed=false, storeVersionAvailabilityChecked=false. Рабочие production URLs/lockfile/checkout/пароли/certs/analyze прошли; тесты/iOS не запускались. Мобильные артефакты собраны по прямому поручению владельца, в магазины не загружались.

Скачаны и сохранены в build/release-check/android-attempt-2/build/release/android: google_play-1.0.0+71.aab SHA256 76e9000ba49c188afc82c352b7e54b3b51a455e3896321f2dfba086eddfae38b; rustore-1.0.0+71.apk SHA256 1344973161ab9f75da32037299d256ed4838c73b05faf9542e6db9262a6e768e; release-report.json/SHA256SUMS.txt. Codemagic убрал плюс из download filenames; локальные копии именованы по report без изменения байтов. Оба скачанных SHA совпали с CI, lockfile SHA 277bb705bf90c4283cecc7915f05d1313370dbcc4a071055452cbed3c91c75c9 совпал с локальным. Java verifier локально подтвердил подписанные payload entries AAB с upload 4119…1FE9. Локальный apksigner verify успешен, v2, единственный signer CF38…458D; aapt2 подтвердил package ru.obedmoscow.polevayakuhnya/version 1.0.0/code71/target36. CI bundletool validate/AAB manifest/APK badging также успешны. Снимок build/play-signing/android-ci-prepare-passed.jpg.

Версия +71 и общий runtime-код не изменены; новые CI-файлы на устройство не устанавливались. Прежняя пользовательская приёмка Play/прямого APK +71 относится к прежним артефактам. Новый AAB +71 повторно отправлять Play нельзя; автоматическая занятость номера будет проверяться перед будущим publishing. Техническая Google-подготовка с API/подписью подтверждена, полная автоматизация трёх магазинов ещё не завершена. Privacy/Data safety/FR-A6, новый JSON external backup, future higher-code cross-channel update остаются открытыми. Store publishing, retry existing artifacts, moderation polling и IPA требуют следующих подзадач.

Следующая: FL-07-15 — подготовка RuStore (карточка, первая версия и API-доступ для автоматизации); сложность 5/10; трудоёмкость средняя, ≈10% пакета; LLM средняя; основание — материалы, кабинет магазина/первоначальная версия и защищённый API-доступ, ожидание владельца и модерации отдельно. Перед любым фактическим распространением отдельное согласование конкретного действия. Остановка после успешной Android-подготовки по AGENTS.md. «Пересобрать Web и обновить тестовый flutter-test.obedmoscow.ru по SSH»: технически не требуется, +71 сохранена.
