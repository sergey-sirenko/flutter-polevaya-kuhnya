import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:polevaya_kuhnya/core/platform/semantic_url_strategy.dart';

class _History extends UrlStrategy {
  final paths = <String>['/external', '/orders'];
  final states = <Object?>['external-state', 'initial-state'];
  final listeners = <void Function(Object?)>[];
  int index = 1;
  @override
  String getPath() => paths[index];
  @override
  Object? getState() => states[index];
  @override
  String prepareExternalUrl(String url) => url;
  @override
  VoidCallback addPopStateListener(void Function(Object?) fn) {
    listeners.add(fn);
    return () => listeners.remove(fn);
  }

  @override
  void pushState(Object? state, String title, String url) {
    paths.removeRange(index + 1, paths.length);
    states.removeRange(index + 1, states.length);
    paths.add(url);
    states.add(state);
    index++;
  }

  @override
  void replaceState(Object? state, String title, String url) {
    paths[index] = url;
    states[index] = state;
  }

  @override
  Future<void> go(int count) async {
    index += count;
    for (final listener in List.of(listeners)) {
      listener(getState());
    }
  }
}

void main() {
  test(
    'Back и повторный шаг используют прежнюю запись, без новых посещений',
    () async {
      final browser = _History();
      final strategy = SemanticUrlStrategy(browser);
      final reported = <Object?>[];
      strategy.addPopStateListener(reported.add);
      strategy.replaceState('orders', '', '/orders');
      strategy.pushState('cart', '', '/cart');
      strategy.pushState('categories', '', '/orders/categories');
      strategy.pushState('menu', '', '/menu');
      strategy.pushState('back-categories', '', '/orders/categories');
      expect(browser.getPath(), '/orders/categories');
      expect(browser.paths, [
        '/external',
        '/orders',
        '/cart',
        '/orders/categories',
        '/menu',
      ]);
      expect(reported, ['categories']);
      strategy.replaceState('shortcut-cart', '', '/cart');
      expect(browser.getState(), 'cart');
      strategy.pushState('new-categories', '', '/orders/categories');
      expect(browser.paths, [
        '/external',
        '/orders',
        '/cart',
        '/orders/categories',
      ]);
      expect(browser.states.first, 'external-state');
    },
  );

  test('основные разделы заменяются, первый возврат домой не сохраняет их', () {
    final browser = _History();
    final strategy = SemanticUrlStrategy(browser);
    strategy.addPopStateListener((_) {});
    strategy.replaceState('orders', '', '/orders');
    strategy.replaceState('profile', '', '/profile');
    strategy.pushState('home', '', '/');
    expect(browser.paths, ['/external', '/']);
    expect(browser.states.first, 'external-state');
    strategy.pushState('orders', '', '/orders');
    strategy.pushState('home-again', '', '/');
    expect(browser.index, 1);
    expect(browser.paths.length, 3);
  });

  test(
    'панель/фото и W07 потребляют браузерный Back и сохраняют URL',
    () async {
      final browser = _History();
      final strategy = SemanticUrlStrategy(browser);
      final reported = <Object?>[];
      strategy.addPopStateListener(reported.add);
      strategy.replaceState('orders', '', '/orders');
      strategy.pushState('menu', '', '/menu');
      var consumed = 0;
      strategy.consumeBack = () {
        consumed++;
        return true;
      };
      await browser.go(-1);
      expect(consumed, 1);
      expect(browser.getPath(), '/menu');
      expect(reported, isEmpty);
      strategy.consumeBack = () => false;
      await browser.go(-1);
      expect(browser.getPath(), '/orders');
      expect(reported, ['orders']);
    },
  );
}
