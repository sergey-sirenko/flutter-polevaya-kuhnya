import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_update_browser_api.dart';

WebUpdateBrowser createWebUpdateBrowser() => _Browser();

class _Browser implements WebUpdateBrowser {
  static const _key = 'polevaya-kuhnya.web-update.attempt';
  @override
  bool get supported => true;
  @override
  bool get visible => web.document.visibilityState != 'hidden';

  @override
  void Function() watchForeground(void Function() onForeground) {
    final listener = ((web.Event event) {
      if (visible) onForeground();
    }).toJS;
    web.window.addEventListener('focus', listener);
    web.document.addEventListener('visibilitychange', listener);
    return () {
      web.window.removeEventListener('focus', listener);
      web.document.removeEventListener('visibilitychange', listener);
    };
  }

  @override
  Future<bool> reloadRelease(String release) async {
    String? previous;
    try {
      previous = web.window.sessionStorage.getItem(_key);
    } catch (_) {
      // Маркер в URL защищает от цикла и при недоступном sessionStorage.
    }
    final url = webUpdateLocation(web.window.location.href, release, previous);
    if (url == null) return false;
    try {
      web.window.sessionStorage.setItem(_key, release);
    } catch (_) {}
    web.window.location.replace(url);
    return true;
  }
}
