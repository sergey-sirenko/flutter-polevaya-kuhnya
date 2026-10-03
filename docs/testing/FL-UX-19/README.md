# FL-UX-19 — Проверки категорий

01.10.2026. [Карточка](../../tasks/FL-UX-19.md). Локальная Web 0.1.0+56, публичная при начале +55. Верхний выбор категорий убран ниже 1200 px; все карточки категорий главной равны в каждой раскладке, включая последнюю строку.

## Проверки

- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/site/site_home_layout_test.dart test/features/site/site_home_page_test.dart test/features/menu/menu_page_test.dart test/app/adaptive_app_shell_test.dart test/app/white_kitchen_home_test.dart test/app/router_test.dart --reporter expanded`: 143 passed.
- Главная: семь категорий разных длин, все строки одной ширины/высоты; 320/390/599/600/768/769/1024/1199/1200/1440 px, текст 100%/160%, полный текст без переполнений.
- Меню: верхний выбор отсутствует ниже 1200; левая колонка 224 px на 1200, нижний выбор, активная категория при прокрутке и resize сохраняются.
- `flutter test --no-pub tools/ux/categories_preview_test.dart --reporter expanded`: 4 passed; Arial/MaterialIcons, PNG визуально просмотрены. Данные обезличены, фото заменены штатными заглушками. Меню в отдельном компоненте без оболочки приложения/нижней навигации; нижняя навигация проверена widget-тестами shell.
- `git diff --check` по затронутым отслеживаемым файлам: прошёл.

## Локальные превью

| Экран | PNG |
|---|---|
| Главная 390 | [Превью](home-390.0.png) |
| Главная 650 | [Превью](home-650.0.png) |
| Главная 1440 | [Превью](home-1440.0.png) |
| Меню 390 | [Превью](menu-390.png) |

## Сборка

`pwsh -File .\tools\build_web_test.ps1`: release Web собран, version-policy подтверждён. Оба поля build = 56, pubspec = 0.1.0+56; минимум +1 и Android/iOS releases сохранены. Действующие источники:

- API: `https://hleb-sol.su/Zakaz_http/hs/Obmen/`.
- Данные/фото: `https://obedmoscow.ru/data/`.
- Версия: `https://flutter-test.obedmoscow.ru/version.json`.

SHA-256 `build/web/main.dart.js`: `1552c1608b82d2b5b2e3de076b0ad7ea5143e835c51552f5905cb6e1ef590a82`. Сохранилось предупреждение предыдущей сборки о CupertinoIcons; сборка успешна, MaterialIcons видимы в превью.

Полный комплект тестов не повторялся; Android не пересобран, iOS не запускалась. API/Zak и бизнес-логика не менялись; живых входов, писем, заказов, публикации и коммита нет. Это локальные проверки, не приёмка публичной Web.

## Следующий шаг

«Пересобрать Web и обновить тестовый flutter-test.obedmoscow.ru по SSH»: сборка +56 готова. Пользователь запускает `pwsh -File .\tools\deploy_web_test.ps1 -SkipBuild`, затем проверяет меню и главную на телефоне/планшете/компьютере, включая последнюю строку категорий. Следующая FL-UX-19 (приёмка): 2/10, низкая трудоёмкость, ≈15% отдельного пакета, LLM лёгкая; основание — готовая сборка и два визуальных критерия. Остановка до сообщения о выкладке и нового поручения.
