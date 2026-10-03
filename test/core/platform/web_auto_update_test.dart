import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_repository.dart';
import 'package:polevaya_kuhnya/core/platform/web_auto_update.dart';
import 'package:polevaya_kuhnya/core/platform/web_update_browser_api.dart';

import 'app_version_controller_test.dart' show policy, PendingRepository;

class Browser implements WebUpdateBrowser {
  @override
  bool supported = true;
  @override
  bool visible = true;
  final reloads = <String>[];
  void Function()? foreground;
  @override
  void Function() watchForeground(void Function() onForeground) {
    foreground = onForeground;
    return () => foreground = null;
  }

  @override
  Future<bool> reloadRelease(String release) async {
    reloads.add(release);
    return true;
  }
}

class Repository implements AppVersionRepository {
  AppVersionPolicy result = policy(release: 9);
  Exception? error;
  int calls = 0;
  @override
  Future<AppVersionPolicy> fetch() async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

WebAutoUpdate updater(
  AppVersionRepository repo,
  Browser browser, {
  bool enabled = true,
}) => WebAutoUpdate(
  repository: repo,
  current: AppVersion.tryParse('0.1.0', 8),
  browser: browser,
  enabled: enabled,
);

void main() {
  test('current и старый release не перезагружают, новый однократно, следующий допустим', () async {
    final browser = Browser();
    final update = updater(Repository(), browser);
    addTearDown(update.dispose);
    await update.consider(policy(release: 8).web);
    await update.consider(policy(release: 7).web);
    expect(browser.reloads, isEmpty);
    await update.consider(policy(release: 9).web);
    await update.consider(policy(release: 9).web);
    await update.consider(policy(release: 10).web);
    expect(browser.reloads, ['0.1.0+9', '0.1.0+10']);
  });

  for (final error in [
    Exception('offline'),
    const FormatException('invalid policy'),
  ]) {
    test(
      'ошибка $error: без reload, следующая успешная проверка работает',
      () async {
        final repo = Repository()..error = error;
        final browser = Browser();
        final update = updater(repo, browser);
        addTearDown(update.dispose);
        await update.check();
        expect(browser.reloads, isEmpty);
        repo.error = null;
        await update.check();
        expect(browser.reloads, ['0.1.0+9']);
      },
    );
  }

  test('нет параллельных GET и позднего reload после dispose', () async {
    final repo = PendingRepository();
    final browser = Browser();
    final update = updater(repo, browser);
    final first = update.check();
    await update.check();
    expect(repo.calls, hasLength(1));
    update.dispose();
    repo.calls.single.complete(policy(release: 9));
    await first;
    expect(browser.reloads, isEmpty);
  });

  for (final native in [true, false]) {
    test(
      'native/неподдерживаемый runtime $native: без GET, слушателей и reload',
      () async {
        final repo = Repository();
        final browser = Browser()..supported = native;
        final update = updater(repo, browser, enabled: !native);
        addTearDown(update.dispose);
        update.start();
        await update.check();
        await update.consider(policy(release: 9).web);
        expect(repo.calls, 0);
        expect(browser.foreground, isNull);
        expect(browser.reloads, isEmpty);
      },
    );
  }

  testWidgets(
    '10 секунд / foreground; hidden не проверяется, dispose убирает timer',
    (tester) async {
      final repo = Repository()..result = policy(release: 8);
      final browser = Browser();
      final update = updater(repo, browser);
      update.start();
      update.start();
      await tester.pump(const Duration(seconds: 9));
      expect(repo.calls, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(repo.calls, 1);
      browser.visible = false;
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls, 1);
      browser.visible = true;
      repo.result = policy(release: 9);
      browser.foreground!();
      await tester.pump();
      expect(repo.calls, 2);
      expect(browser.reloads, ['0.1.0+9']);
      update.dispose();
      await tester.pump(const Duration(seconds: 20));
      expect(repo.calls, 2);
      expect(browser.foreground, isNull);
    },
  );

  test('адрес/path/query/fragment и повторные значения сохранены, replace на том же origin', () {
    const href =
        'https://flutter-test.obedmoscow.ru/menu?day=2026-10-05&x=one&x=two#from-menu';
    final next = Uri.parse(webUpdateLocation(href, '0.1.0+9', null)!);
    expect(next.origin, Uri.parse(href).origin);
    expect(next.path, '/menu');
    expect(next.fragment, 'from-menu');
    expect(next.queryParametersAll['x'], ['one', 'two']);
    expect(next.queryParameters['day'], '2026-10-05');
    expect(next.queryParameters['_app_update'], '0.1.0+9');
    expect(webUpdateLocation(next.toString(), '0.1.0+9', null), isNull);
    expect(webUpdateLocation(href, '0.1.0+9', '0.1.0+9'), isNull);
    expect(
      webUpdateLocation(next.toString(), '0.1.0+10', '0.1.0+9'),
      isNotNull,
    );
  });
}
