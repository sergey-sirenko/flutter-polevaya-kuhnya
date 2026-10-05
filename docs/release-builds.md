# Локальные выпускные сборки Web и Android

**Актуально 30.09.2026, FL-10-13/FL-10-14:** общий тестовый Web **0.1.0+28** собран локально; публичная версия перед сборкой +26. Выкладку +28 по SSH выполняет пользователь; успешная +27 была затем заменена общей сборкой +28. Android APK/AAB остаются +4 и не содержат последних UI/навигационных изменений; iOS не запускалась. Версии старых выпусков ниже — исторические. [Карточка](tasks/FL-10-13.md), [приёмка](testing-web-android.md#приёмка-fl-10-13--кнопка-назад-и-карточки-дней).

Задача: [FL-07-07](tasks/FL-07-07.md). Сборка артефакта не является публикацией. Конфигурация окружений — [docs/environments.md](environments.md), роли ключей — [FL-07-04](tasks/FL-07-04.md), резерв — [docs/android-signing-recovery.md](android-signing-recovery.md).

Версия задаётся один раз в `pubspec.yaml` (`version: 0.1.0+4` по FL-06-14c). Для Web `web/version.json` должен содержать ту же пару `version`/`build`; перед каждым новым выпуском увеличить build number и обновить оба файла. Android берёт versionName/versionCode из версии Flutter. Прямой APK и AAB одного выпуска используют одинаковую версию и Application ID `ru.obedmoscow.polevayakuhnya`. На тестовом Web опубликована 0.1.0+4; готовые Android APK/AAB также 0.1.0+4. Android APK/AAB 0.1.0+4 подписанно пересобраны и проверены в [FL-07-07d](tasks/FL-07-07d.md); установка на устройство ещё не подтверждена.


## Быстрые команды Web и Android

Используйте PowerShell 7 (`pwsh`), Flutter в PATH и корень `E:\GIT\HlebSol\Flutter`.

```powershell
# Web: только тестовая сборка
pwsh -NoProfile -File .\tools\build_web_test.ps1
# Web: сборка и публикация тестового сайта по SSH
pwsh -NoProfile -File .\tools\deploy_web_test.ps1
# Web: публикация уже готового build/web
pwsh -NoProfile -File .\tools\deploy_web_test.ps1 -SkipBuild
# Android: подписанные AAB и APK, два скрытых запроса паролей
pwsh -NoProfile -File .\tools\build_android_release.ps1
```

Web-выкладка требует увеличенного build number в `pubspec.yaml` и `web/version.json`, доступного SSH и готового серверного окружения. `-SkipBuild` не проверяет свежесть кода: применяйте его только к идентифицированному `build/web`. Следуйте [runbook с резервом и откатом](testing-web-android.md#быстрая-сборка-выкладка-и-откат-тестового-web). Web-скрипт прошёл реальную сборку/SSH-выкладку 0.1.0+4 в [FL-06-14c](tasks/FL-06-14c.md), включая резерв и проверку 41 файла; сам откат ещё не выполнялся. Android-скрипт успешно использован для 0.1.0+4.

## Web prod

Для быстрой тестовой сборки и выкладки на `flutter-test.obedmoscow.ru` используйте единый скрипт и runbook в [docs/testing-web-android.md](testing-web-android.md#быстрая-сборка-выкладка-и-откат-тестового-web). Он не публикует Web prod. Текущий тестовый Web — 0.1.0+4, см. [FL-06-14c](tasks/FL-06-14c.md).

```powershell
flutter build web --release --no-pub --dart-define=APP_ENV=prod --dart-define=API_BASE_URL=https://hleb-sol.su/Zakaz_http/hs/Obmen/ --dart-define=DATA_BASE_URL=https://obedmoscow.ru/data/
```

Результат: `build/web/`. До публикации проверить DNS, CORS, данные, Caddy и живой сценарий с выделенным тестовым пользователем. Эта команда ничего не размещает.

## Android prod

Источник меню и фотографий Android с 28.09.2026 — `https://obedmoscow.ru/data/` по [FL-07-07a](tasks/FL-07-07a.md). Он задан в скрипте через `DATA_BASE_URL`; API 1С прежний. Ранее собранные APK/AAB автоматически не меняются: для нового адреса нужна подписанная пересборка. Web test/prod по [FL-07-07b](tasks/FL-07-07b.md) используют тот же источник; тестовая сборка — [build_web_test.ps1](../tools/build_web_test.ps1).

В интерактивном PowerShell из корня проекта:

```powershell
pwsh -NoProfile -File .\tools\build_android_release.ps1
```

Скрипт запросит пароль `upload` для AAB и пароль `app-signing` для прямого APK. Оба вводятся только в локальном окне, не передаются через аргументы командной строки и не записываются в проект. Keystore находятся вне репозитория. Результаты: `build/app/outputs/bundle/release/app-release.aab` и `build/app/outputs/flutter-apk/app-release.apk`.

Android release без четырёх переменных `POLEVAYA_KEYSTORE_PATH`, `POLEVAYA_KEYSTORE_PASSWORD`, `POLEVAYA_KEY_ALIAS` и `POLEVAYA_KEY_PASSWORD` останавливается с ошибкой и не создаёт неподписанный артефакт. Эти переменные задаёт только указанный скрипт.

Перед использованием проверить:

1. В обоих артефактах Application ID `ru.obedmoscow.polevayakuhnya`, версия и build совпадают с текущим `pubspec.yaml`, target API не ниже текущего требования Google Play.
2. AAB подписан **upload** сертификатом `41:19:B0:22:EA:DE:3B:34:77:50:12:0C:69:DA:E3:23:37:2F:4C:D4:2C:7E:75:FC:E4:CE:82:DE:5D:1D:1F:E9`.
3. APK подписан **app signing** сертификатом `CF:38:A8:1B:90:2D:D5:5A:97:B6:6C:2B:BD:40:4C:64:4F:77:62:8C:B4:F0:5A:3E:71:85:8A:09:B0:11:45:8D`.
4. Для Google Play до первого выпуска выбрать собственный app signing key; в RuStore настроить тот же ключ. После загрузки сверить сертификаты доставляемых APK с прямым APK, затем проверить обновления на тестовом устройстве. Загрузка и публикация относятся к отдельным задачам.

Источник данных `https://obedmoscow.ru/data/` проверяется в FL-07-07b; основной Flutter переходит на `obedmoscow.ru` по [FL-WEB-PROD-01](tasks/FL-WEB-PROD-01.md); перенос +71 выполнен 05.10.2026, журнал и резерв в карточке. iOS-часть FL-07-07 отложена решением пользователя до возвращения к FL-07-06 после Android-публикации; при возобновлении использовать тот же DATA_BASE_URL рабочего сайта.
