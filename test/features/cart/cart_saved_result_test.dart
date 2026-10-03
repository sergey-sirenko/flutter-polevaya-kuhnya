import 'package:polevaya_kuhnya/features/cart/cart_draft_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_summary_bar.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_edit_flow_test.dart' show Harness, date, other;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final scenario in ['save', 'cancel', 'lost-response']) {
    testWidgets(
      'квитанция $scenario скрывает чужой состав, удаляя старые draft',
      (tester) async {
        final h = Harness();
        await tester.runAsync(() async {
          await h.init();
          h.draft.setQuantity(other, 'dish', 7);
          expect(await h.edit.begin(date), isTrue);
          if (scenario == 'cancel') {
            h.draft.clearDay(date);
          } else {
            h.draft.increment(date, 'dish');
          }
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: MaterialApp(
              home: Column(
                children: [
                  const Expanded(child: CartPage()),
                  CartSummaryBar(onOpenCart: () {}),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scenario != 'cancel') {
          expect(
            find.byKey(const ValueKey('cart-sticky-header')),
            findsNothing,
          );
        }
        await tester.runAsync(() async {
          if (scenario == 'lost-response') h.loseResponse = true;
          await h.submit.submit(
            confirmedCancellations: scenario == 'cancel' ? {date} : const {},
          );
          if (scenario == 'lost-response') {
            expect(
              h.container.read(cartSubmitControllerProvider).phase,
              CartSubmitPhase.outcomeUnknown,
            );
            expect(h.container.read(editingCartProvider).isEmpty, isFalse);
            await h.submit.resolveUnknownOutcome();
          }
        });
        await tester.pumpAndSettle();
        expect(
          h.container.read(cartSubmitControllerProvider).phase,
          CartSubmitPhase.idle,
        );
        expect(h.container.read(cartDraftProvider), isEmpty);
        expect(h.container.read(editingCartProvider).isEmpty, isTrue);
        expect(find.byKey(const ValueKey('cart-sticky-header')), findsNothing);
        expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
        expect(find.text('Тестовый суп'), findsNothing);
        expect(find.text(AppStrings.cartGoToOrders), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining(AppStrings.cartFinalChanged), findsNothing);
        expect(
          find.textContaining(AppStrings.cartFinalUnchanged),
          findsNothing,
        );
        expect(find.text(AppStrings.cartContinueChoosing), findsNothing);
        expect(h.requests, hasLength(1));
        await tester.runAsync(() async {
          final persisted = await h.container
              .read(cartDraftStoreProvider)
              .load('alice');
          expect(persisted, isNull);
        });
        expect(find.text(AppStrings.cartAcknowledge), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(
          h.container.read(cartSubmitControllerProvider).phase,
          CartSubmitPhase.idle,
        );
        expect(h.container.read(editingCartProvider).isEmpty, isTrue);
        expect(find.byKey(const ValueKey('cart-sticky-header')), findsNothing);
        expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
        expect(find.text('Тестовый суп'), findsNothing);
        expect(h.container.read(cartDraftProvider), isEmpty);
        // Повторное открытие и сброс режима не возвращают старые позиции.
        h.edit.end();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: const MaterialApp(home: CartPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Тестовый суп'), findsNothing);
        expect(find.byKey(const ValueKey('cart-sticky-header')), findsNothing);
        expect(find.text(AppStrings.cartContinueChoosing), findsNothing);
        // Новая подготовка загружает серверный состав выбранного дня.
        await tester.runAsync(() async {
          h.submit.acknowledge();
          await h.container.read(cartRepeatControllerProvider.notifier).ready;
          final prepared = await h.edit.begin(other);
          expect(
            prepared,
            isTrue,
            reason: h.container.read(cartEditControllerProvider).message,
          );
        });
        await tester.pumpAndSettle();
        expect(h.container.read(editingCartProvider).dayFor(other), isNull);
        expect(h.container.read(cartDraftProvider)[date]?['dish'], 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
