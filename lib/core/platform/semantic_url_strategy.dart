import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

/// Возврат приложения не создаёт новую запись посещения в браузере.
/// Учёт начинается только с записей текущего запуска; чужую историю не читаем.
class SemanticUrlStrategy extends UrlStrategy {
  SemanticUrlStrategy(this.delegate);
  final UrlStrategy delegate;
  final _paths = <String>[];
  int _cursor = -1;
  bool _recovering = false;
  bool Function()? consumeBack;

  @override
  VoidCallback addPopStateListener(void Function(Object?) fn) =>
      delegate.addPopStateListener((state) {
        if (_recovering) {
          _recovering = false;
          return;
        }
        final index = _paths.indexOf(getPath());
        if (index >= 0 && index < _cursor && (consumeBack?.call() ?? false)) {
          _recovering = true;
          unawaited(delegate.go(_cursor - index));
          return;
        }
        if (index >= 0) _cursor = index;
        fn(state);
      });

  @override
  String getPath() => delegate.getPath();
  @override
  Object? getState() => delegate.getState();
  @override
  String prepareExternalUrl(String internalUrl) =>
      delegate.prepareExternalUrl(internalUrl);
  @override
  Future<void> go(int count) => delegate.go(count);

  bool _returnTo(String url) {
    final index = _paths.indexOf(url);
    if (index >= 0 && index < _cursor) {
      unawaited(delegate.go(index - _cursor));
      return true;
    }
    return false;
  }

  @override
  void pushState(Object? state, String title, String url) {
    if (_returnTo(url)) return;
    // Прямой вход не создаёт искусственного посещения главной. При первом
    // возврате на неё заменяем текущий раздел, не добавляя его в историю Back.
    if (url == '/' || (_cursor >= 0 && _paths[_cursor] == url)) {
      replaceState(state, title, url);
      return;
    }
    if (_cursor + 1 < _paths.length) {
      _paths.removeRange(_cursor + 1, _paths.length);
    }
    _paths.add(url);
    _cursor = _paths.length - 1;
    delegate.pushState(state, title, url);
  }

  @override
  void replaceState(Object? state, String title, String url) {
    if (_returnTo(url)) return;
    if (_cursor < 0) {
      _paths.add(url);
      _cursor = 0;
    } else {
      _paths[_cursor] = url;
    }
    delegate.replaceState(state, title, url);
  }
}
