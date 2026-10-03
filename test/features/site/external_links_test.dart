import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:polevaya_kuhnya/shared/external_link.dart';

void main() {
  test(
    'внешний запуск возвращает отказ при false, исключении и относительном URL',
    () async {
      final uri = Uri.parse('https://example.invalid/menu.xls');
      expect(await tryOpenExternal(uri, launcher: (_) async => true), isTrue);
      expect(await tryOpenExternal(uri, launcher: (_) async => false), isFalse);
      expect(
        await tryOpenExternal(
          uri,
          launcher: (_) async => throw StateError('no handler'),
        ),
        isFalse,
      );
      expect(
        await tryOpenExternal(
          Uri.parse('relative'),
          launcher: (_) async => fail('Не должен запускаться'),
        ),
        isFalse,
      );
    },
  );

  for (final throwsError in [false, true]) {
    testWidgets(
      'отказ открытия контакта показывает пояснение: исключение=$throwsError',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openExternal(
                    context,
                    'mailto:fixture@example.invalid',
                    launcher: (uri) async {
                      expect(uri.scheme, 'mailto');
                      if (throwsError) throw StateError('no handler');
                      return false;
                    },
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.externalLinkUnavailable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('успешный запуск не показывает ошибку', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openExternal(
                context,
                'tel:+70000000000',
                launcher: (_) async => true,
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.externalLinkUnavailable), findsNothing);
  });

  testWidgets('поздний отказ после закрытия экрана не вызывает исключение', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openExternal(
                context,
                'tel:+70000000000',
                launcher: (_) => pending.future,
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
