import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';

void main() {
  test(
    'позиция имеет составной ключ: одна дата или одно блюдо не достаточны',
    () {
      final cart = Cart.fromDraft({
        '2030-01-03': {'dish-1': 2},
        '2030-01-02': {'dish-2': 1, 'dish-1': 3},
      });

      expect(cart.days.map((day) => day.dateKey), ['2030-01-02', '2030-01-03']);
      expect(cart.dayFor('2030-01-02')?.itemFor('dish-1')?.quantity, 3);
      expect(cart.dayFor('2030-01-03')?.itemFor('dish-1')?.quantity, 2);
      expect(cart.dayFor('2030-01-02')?.itemFor('dish-2')?.quantity, 1);
      expect(cart.dayFor('2030-01-04'), isNull);

      final firstId = cart.dayFor('2030-01-02')!.itemFor('dish-1')!.id;
      final sameId = (dateKey: '2030-01-02', dishId: 'dish-1');
      final otherDayId = cart.dayFor('2030-01-03')!.itemFor('dish-1')!.id;
      expect(firstId, sameId);
      expect(firstId, isNot(otherDayId));
      expect({firstId: 'first'}[sameId], 'first');
    },
  );

  test('снимок корзины не меняется через исходный черновик и списки', () {
    final draft = <String, Map<String, int>>{
      '2030-01-02': {'d1': 2},
    };
    final cart = Cart.fromDraft(draft);
    draft['2030-01-02']!['d1'] = 5;
    draft['2030-01-03'] = {'d2': 1};
    expect(cart.days, hasLength(1));
    expect(cart.dayFor('2030-01-02')!.itemFor('d1')!.quantity, 2);
    expect(() => cart.days.clear(), throwsUnsupportedError);
    expect(() => cart.days.first.items.clear(), throwsUnsupportedError);

    final sourceItems = [
      CartItem(dateKey: '2030-01-02', dishId: 'd1', quantity: 2),
    ];
    final day = CartDay(dateKey: '2030-01-02', items: sourceItems);
    sourceItems.clear();
    final sourceDays = [day];
    final fromLists = Cart(days: sourceDays);
    sourceDays.clear();
    expect(fromLists.days.single.items, hasLength(1));
  });

  test('повреждённые даты, количества и дубли отвергаются', () {
    expect(
      () => Cart.fromDraft({
        '2030-02-30': {'d1': 1},
      }),
      throwsFormatException,
    );
    expect(
      () => Cart.fromDraft({
        '2030-01-02': {'': 1},
      }),
      throwsFormatException,
    );
    expect(
      () => Cart.fromDraft({
        '2030-01-02': {'d1': 0},
      }),
      throwsFormatException,
    );
    expect(() => Cart.fromDraft({'2030-01-02': {}}), throwsFormatException);
    final item = CartItem(dateKey: '2030-01-02', dishId: 'd1', quantity: 1);
    expect(
      () => CartDay(dateKey: '2030-01-03', items: [item]),
      throwsFormatException,
    );
    expect(
      () => CartDay(dateKey: '2030-01-02', items: [item, item]),
      throwsFormatException,
    );
    final day = CartDay(dateKey: '2030-01-02', items: [item]);
    expect(() => Cart(days: [day, day]), throwsFormatException);
  });

  test('модель отражает выбор меню без второго изменяемого состояния', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(cartModelProvider).isEmpty, isTrue);

    final draft = container.read(cartDraftProvider.notifier);
    draft.increment('2030-01-02', 'd1');
    draft.increment('2030-01-03', 'd1');
    expect(container.read(cartModelProvider).days, hasLength(2));
    expect(
      container
          .read(cartModelProvider)
          .dayFor('2030-01-02')
          ?.itemFor('d1')
          ?.quantity,
      1,
    );
    draft.decrement('2030-01-02', 'd1');
    expect(container.read(cartModelProvider).dayFor('2030-01-02'), isNull);
    expect(container.read(cartModelProvider).dayFor('2030-01-03'), isNotNull);
  });
}
