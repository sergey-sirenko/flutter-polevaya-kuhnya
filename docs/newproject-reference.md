# NewProject: применение к «Полевой кухне»

Задача: FL-00-04. Дата просмотра: 26.09.2026.

Изучена ревизия **a15e24bc871cecd2a6753b5aad9e5bd49dfc9b7f**. Файлы прочитаны по URL с этим SHA:

- [README](https://github.com/sergey-sirenko/NewProject/blob/a15e24bc871cecd2a6753b5aad9e5bd49dfc9b7f/README.md)
- [ARCHITECTURE](https://github.com/sergey-sirenko/NewProject/blob/a15e24bc871cecd2a6753b5aad9e5bd49dfc9b7f/ARCHITECTURE.md)
- [AGENTS](https://github.com/sergey-sirenko/NewProject/blob/a15e24bc871cecd2a6753b5aad9e5bd49dfc9b7f/AGENTS.md)

README указывает, что каркас и первый модуль ещё не созданы. Копировать готовое приложение из этого репозитория нельзя: он используется как пример организации разработки.

Приоритет — [ТЗ](<../Техническое задание.md>) и указания пользователя. Эта справка не вводит новые обязательства из внешнего AGENTS.md.

| Область | Применение в нашем проекте | Основание ТЗ |
|---|---|---|
| Стек клиента | Flutter/Dart, Material 3, Riverpod, go_router | 1, 8 |
| Модули | Model → Repository → Controller → UI | 8 |
| Providers и модели | Ручной понятный код без генераторов | 8 |
| Сервер | HTTP 1С через ApiClient вместо Supabase/PostgreSQL | ADR-1 |
| Доступ | Модель 1С вместо pending/admin | ADR-2 |
| Хранение | Токен; исключение для черновика и настроек | 6.1, ADR-3 |
| Платформы | Web, Android, iOS обязательны; desktop через браузер | ADR-4 |
| Зависимости | Разрешённый список ТЗ и проверка трёх платформ | ADR-5, приложение А |
| Пример модуля | menu, затем cart, вместо Customers | ADR-6 |
| Сайт и распространение | Модуль site и единая точка платформенных проверок | ADR-7, П3 |
| Проверки | Обязательные тесты критичных расчётов и CI | BL-4, INF-3 |

ADR оформлены в [ARCHITECTURE.md](../ARCHITECTURE.md) задачей FL-01-04; ADR-8 содержит согласованное пользователем дополнение к П3 о стартовом маршруте. Эта справка не подтверждает сборку, выбор актуальных версий пакетов или готовность API.
