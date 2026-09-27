# Проверочный CI

**FL-01-15, 27.09.2026.** [Workflow](../.github/workflows/flutter-ci.yml) запускается на каждом `push`, `pull_request` и вручную через GitHub Actions. Один job на `ubuntu-latest` последовательно получает Flutter 3.47.1, разрешает зависимости по `pubspec.lock`, запускает анализ и тесты. Шаги используют обычное прекращение job при ненулевом коде; `continue-on-error` не задан. Права GitHub token ограничены чтением содержимого, checkout не сохраняет учётные данные.

Локальная эквивалентная проверка из корня проекта:

```text
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub -r compact
```

Workflow не собирает приложение, не обращается к 1С, не подписывает и не публикует результат. Выпускные сборки Web/Android/iOS и секреты подписи относятся к дальнейшим задачам. Flutter Git сейчас `master` без коммитов и remote: конфигурация ещё не исполнялась на GitHub runner. После размещения репозитория нужно проверить фактический зелёный запуск и отрицательный запуск при ошибке анализа или теста; локальная проверка не заменяет это подтверждение.

Версии действий выбраны по [официальному checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) и [репозиторию flutter-action](https://github.com/subosito/flutter-action/releases/tag/v2.23.0). Версия Flutter соответствует локальному SDK и [официальному changelog](https://github.com/flutter/flutter/blob/master/CHANGELOG.md). При обновлении версий действий и SDK сначала проверить их требования к runner и повторить команды.
