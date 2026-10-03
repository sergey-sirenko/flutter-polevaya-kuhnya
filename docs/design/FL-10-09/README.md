# FL-10-09 — календарь заказов

30.09.2026. [Правая панель 320 px](orders-panel.png): настоящий Flutter-виджет и AppTheme, две недели, доступные/закрытые дни, выбор и серверные итоги. Данные синтетические, имя обезличено. Локальный widget-render с системным Arial и MaterialIcons; не браузерная и не нативная приёмка. Вид визуально проверен; живую проверку выполняет владелец на flutter-test.

Генерация: `$env:FL_ORDERS_PREVIEW = '1'; flutter test --no-pub test/features/cart/orders_calendar_page_test.dart --plain-name 'увеличенный текст складывает недели'; Remove-Item Env:FL_ORDERS_PREVIEW`. Опциональный рендер использует `C:/Windows/Fonts/arial.ttf`; обычные тесты не зависят от системного шрифта. Выход — `build/fl-10-09/orders-panel.png`; журнал — `build/fl-10-09-preview.log`.

[Карточка](../../tasks/FL-10-09.md). Заказы не отправлялись, API/1С не менялись.
