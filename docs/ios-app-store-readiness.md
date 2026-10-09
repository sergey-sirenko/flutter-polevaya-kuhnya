# App Store: сверка карточки и снимков, 06.10.2026

Приложение «Полевая кухня», Apple ID6819387151, страница https://appstoreconnect.apple.com/apps/6819387151/distribution. По поручению заполнить карточку сохранены русские описание, рекламный текст, ключевые слова, support/marketing https://obedmoscow.ru/, copyright 2026 Sergey Sirenko. Описание использует «опубликованное меню», без обещания ещё не опубликованной следующей недели. Подзаголовок «Обеды в офис по меню», категория «Еда и напитки» сохранены и подтверждены после reload. Версия1.0 остаётся «Подготовка к отправке»; выбрана готовая сборка72/1.0.0, Apple принял связывание. Automatic release radio checked ранее, не меняли. App Review не отправляли.

Контакты проверяющего и отдельный демонстрационный доступ предоставлены владельцем специально для Apple и сохранены в review section; значения credentials в документацию/Git не копируются. Добавлены инструкции о публичном меню и входе по коду/паролю. Работоспособность демонстрационного входа ещё не проверена. Privacy/FR-A6, права на контент, возрастной рейтинг и доступность требуют отдельной сверки до App Review; декларации не выдумывались. Полная Release-приёмка на физическом iPhone не выполнена.

## Подборка для просмотра

build/release-check/ios72-selected-screenshots содержит ровно6PNG: iPhone home/menu/delivery и iPad home/menu-landscape/delivery. Только удачные кадры; исключены DaySheet, upside-down, дубликаты, диагностические страницы CI. SHA256 и источники — manifest.json. Файлы копируются без графического редактирования и сохраняют EXIF. Original CI artifacts остаются как доказательства.

Эта прежняя подборка не готова для магазина: содержит DEBUG. Добавлен отдельный workflow ios-store-screenshots: фиксированный Simulator ZIP72 и SHA, iPhone16ProMax/iPadPro13M4, реальные PNG home/menu/delivery; VM service ext.flutter.debugAllowBanner=false, без ретуши, rebuild или Apple API. Auth-код службы сохраняется, соединение loopback; временный журнал не публикуется. Размеры1320×2868/2064×2752 проверяются. Первая попытка6ac55f217394575b200bcc51/a6abad5 остановилась до съёмки: simctl stdout не содержит VM URI. Исправлено обнаружение через unified log по способу Flutter SDK (b89edc5), повтор запущен; результат и визуальная проверка ещё ожидаются. App source/version72/IPA не менялись, SSH/VNC off, снимки Apple пока не передавались.

Спецификация Apple: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications.
