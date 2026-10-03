import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_store.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_edit_flow_test.dart' show Harness, date, other, config;

class _FailClear extends CartWorkStore {
  _FailClear() : super(config);
  @override
  Future<void> clear(String login, String device) async =>
      throw StateError('disk');
}

Future<void> _mount(WidgetTester tester, Harness h) async {
  await tester.runAsync(() async {
    await h.container.read(cartRepeatControllerProvider.notifier).ready;
    await h.edit.persistNow();
  });
  h.container.read(routerProvider).go('/cart');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(routerConfig: h.container.read(routerProvider)),
    ),
  );
  await tester.pumpAndSettle();
  h.calls.clear();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('FL-UX-28 общая отмена двух дней $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = Harness();
      await tester.runAsync(() async {
        await h.init();
        await h.edit.begin(date);
        h.draft.increment(date, 'dish');
        h.draft.increment(other, 'dish');
      });
      await _mount(tester, h);
      final save = find.byKey(const ValueKey('cart-save-all'));
      final cancel = find.byKey(const ValueKey('cart-cancel-all'));
      final title = find.byKey(const ValueKey('route-page-title'));
      expect(find.widgetWithText(FilledButton, 'Сохранить'), findsOneWidget);
      expect(tester.getCenter(cancel).dy, tester.getCenter(save).dy);
      expect(
        (tester.getCenter(title).dy - tester.getCenter(save).dy).abs(),
        lessThan(1),
      );
      expect(find.text('Ср!\n02.01'), findsOneWidget);
      expect(find.text('Чт!\n03.01'), findsOneWidget);
      expect(find.textContaining('К сохранению'), findsNothing);
      expect(find.textContaining('Сохраняются изменения'), findsNothing);
      expect(find.text('Начать заново'), findsNothing);
      await _tap(tester, 'cart-cancel-all');
      expect(
        h.container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/orders',
      );
      expect(h.container.read(cartDraftProvider), isEmpty);
      expect(h.state.active, isFalse);
      expect(h.requests, isEmpty);
      expect(h.calls, isEmpty);
      await tester.runAsync(() async {
        expect(
          await h.container
              .read(cartWorkStoreProvider)
              .load('alice', h.container.read(sessionApiProvider)!.deviceId),
          isNull,
        );
      });
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in ['accepted', 'failed', 'unknown', 'snapshot-missing']) {
    testWidgets('FL-UX-28 общая отправка двух дней $outcome', (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.init();
        await h.edit.begin(date);
        h.draft.increment(date, 'dish');
        h.draft.increment(other, 'dish');
        h.basketError = outcome == 'failed' ? 'order_changed' : null;
        h.loseResponse = outcome == 'unknown';
        h.omitAcceptedSnapshot = outcome == 'snapshot-missing';
      });
      await _mount(tester, h);
      await _tap(tester, 'cart-save-all');
      expect(h.requests, hasLength(1));
      expect(h.requests.single['order'], hasLength(2));
      expect(h.calls, ['basket']);
      if (outcome == 'accepted' || outcome == 'snapshot-missing') {
        expect(
          h.container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/orders',
        );
        expect(h.container.read(cartDraftProvider), isEmpty);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(AppStrings.cartAcknowledge), findsNothing);
        expect(find.textContaining(AppStrings.cartFinalChanged), findsNothing);
        expect(
          find.textContaining('Не удалось обновить данные'),
          outcome == 'snapshot-missing' ? findsOneWidget : findsNothing,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(h.requests, hasLength(1));
      } else {
        expect(
          h.container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/cart',
        );
        expect(h.container.read(cartDraftProvider)[date]?['dish'], 3);
        expect(h.container.read(cartDraftProvider)[other]?['dish'], 1);
        expect(find.byType(SnackBar), findsNothing);
        if (outcome == 'unknown') {
          expect(
            h.container.read(cartSubmitControllerProvider).phase,
            CartSubmitPhase.outcomeUnknown,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('cart-save-all')),
                )
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('cart-cancel-all')),
                )
                .onPressed,
            isNull,
          );
          expect(find.text(AppStrings.cartCheckResult), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('FL-UX-28 сбой сброса сохраняет правки и страницу', (
    tester,
  ) async {
    final h = Harness();
    await tester.runAsync(() async {
      await h.init(workStore: _FailClear());
      await h.edit.begin(date);
      h.draft.increment(date, 'dish');
    });
    await _mount(tester, h);
    await _tap(tester, 'cart-cancel-all');
    expect(
      h.container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/cart',
    );
    expect(h.container.read(cartDraftProvider)[date]?['dish'], 3);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(h.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FL-UX-28 закрытые даты не выводятся в корзине и заказах', (
    tester,
  ) async {
    final h = Harness()..allowed.remove(other);
    await tester.runAsync(() async {
      await h.init();
      await h.edit.begin(date);
    });
    expect(h.state.message, contains(other));
    await _mount(tester, h);
    expect(find.byKey(const ValueKey('work-report')), findsNothing);
    expect(find.text(h.state.message!), findsNothing);
    h.container.read(routerProvider).go('/orders');
    await tester.pumpAndSettle();
    expect(find.text(h.state.message!), findsNothing);
    expect(find.byKey(const ValueKey('work-report')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
