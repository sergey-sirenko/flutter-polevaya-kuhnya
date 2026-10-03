# FL-UX-21 — Проверки автоматического Web-обновления

Завершено локально 02.10.2026. [Карточка](../../tasks/FL-UX-21.md). Локальная +58, публичная до/после работы +57. Прямое поручение: автоматически применять новую Web-версию, без дополнительного сохранения данных.

## Реализация

Проверка валидной policy на старте, каждые 10 секунд активной вкладки и при focus/visibilitychange; release сравнивается с compiled current прежним числовым сравнением. Только канал Web и supported adapter; native no-op. Фоновые GET не меняют gate и не блокируют формы. Неверный JSON/ошибка/timeout не вызывают reload; старые/equal версии игнорируются. Дополнительных запросов бизнес-API, flush данных/ожидания submission/очистки хранилищ нет.

location.replace сохраняет origin/path/query/fragment и добавляет технический release-маркер. Однократная попытка в процессе, sessionStorage и URL guard после перезагрузки; недоступность sessionStorage компенсирует URL-маркер. Новый index имеет отдельный URL release, bootstrap включён inline, main.dart.js всегда имеет stamp сборки в URL. Worker заново не регистрируется. Реализация bootstrap сверена с установленным SDK и [официальным механизмом Flutter initialization](https://docs.flutter.dev/platform-integration/web/initialization).

## Фактические проверки

| Проверка | Результат |
|---|---|
| flutter analyze --no-pub | No issues found |
| flutter test --no-pub test/core/platform/web_auto_update_test.dart test/core/platform/app_version_controller_test.dart test/core/platform/app_version_policy_test.dart test/core/platform/app_version_repository_test.dart test/app/version_gate_test.dart test/app/router_test.dart test/app/white_kitchen_home_test.dart --reporter expanded | 76 passed |
| Новые проверки | 8 сервис/URL + 1 app startup/retry; версии, ошибки, native, timer/foreground/hidden, одноразовый reload, поздний ответ/dispose, query/fragment |
| node tools/check_web_auto_update.cjs --built | 4 URL-сценария, stamp/inline/no worker/no unresolved tokens прошли |
| tools/build_web_test.ps1 | Release Web +58 и version-policy прошли |
| git diff --check + пробелы новых файлов | Прошли |

Готовый браузерный Dart-адаптер прошёл Web-компиляцию и Wasm dry run. Unit/widget-тесты с fake browser не подтверждают живую смену документа/HTTP-кэш/PWA. Публичная миграция и несколько вкладок проверяются после пользовательской выкладки. Полный комплект тестов не повторялся; Android не пересобран, iOS runtime не запускался. API/Zak и бизнес-контроллеры не менялись; Caddy/серверные настройки не изменялись. Живых входов/заказов/писем, публикации и коммита нет.

## Выпуск

Оба поля build = 58, pubspec = 0.1.0+58. Минимум +1 и Android/iOS releases null сохранены. Источники: API `https://hleb-sol.su/Zakaz_http/hs/Obmen/`, data `https://obedmoscow.ru/data/`, version `https://flutter-test.obedmoscow.ru/version.json`. Единственная dependency-дельта — web 1.1.1 direct вместо transitive; pub get офлайн. Существующее предупреждение CupertinoIcons сохранено.

SHA-256 `build/web/main.dart.js`: `8132f88e9d499f7a948aef5564cbc0e965582fa958f5c9ed806478dc3479f472`.

## Следующее действие

«Пересобрать Web и обновить тестовый flutter-test.obedmoscow.ru по SSH»: локальная +58 готова, пользователь запускает `pwsh -File .\tools\deploy_web_test.ps1 -SkipBuild`. Для существующих +57 вкладок нужен один ручной reload после выкладки: прежний код не содержит механизма. Затем из +58 проверить реальный переход на следующий согласованный выпуск, задержку активной вкладки (10 секунд плюс сеть), foreground, тот же маршрут, отсутствие циклов и ложных переходов при сбое сети. Дополнительный выпуск только для приёмки не создавался/не публиковался. Следующая FL-UX-21 (приёмка): 3/10, низкая трудоёмкость, ≈15% отдельного пакета, LLM средняя; основание — реальный кэш/миграция. Остановка до нового поручения.
