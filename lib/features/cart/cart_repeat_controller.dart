import 'dart:async';

import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

final class CartRepeatState {
  const CartRepeatState({
    this.loading = false,
    this.saved,
    this.message,
    this.recoveryBlocked = false,
  });
  final bool loading;
  final RepeatSnapshot? saved;
  final String? message;
  final bool recoveryBlocked;
}

final cartRepeatControllerProvider =
    NotifierProvider<CartRepeatController, CartRepeatState>(
      CartRepeatController.new,
    );

class CartRepeatController extends Notifier<CartRepeatState> {
  int _epoch = 0;
  Future<void> _ready = Future<void>.value();
  Future<void> get ready => _ready;

  @override
  CartRepeatState build() {
    final repository = ref.watch(cartRepositoryProvider);
    final store = ref.watch(cartRepeatStoreProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    final epoch = ++_epoch;
    ref.onDispose(() => _epoch++);
    ref.listen(cartRepeatWorkProvider, (previous, next) {
      if (previous != null && next.cleared != previous.cleared) {
        _epoch++;
        _set(const CartRepeatState());
      }
    });
    ref.listen(cartDraftProvider, (_, next) => _persistObserved());
    ref.listen(cartEditControllerProvider, (_, next) => _persistObserved());
    _ready = Future<void>.microtask(() async {
      if (repository == null || owner == null || owner.isEmpty) return;
      if (!_current(epoch, repository)) return;
      _set(const CartRepeatState(loading: true));
      try {
        final saved = await store.load(owner, repository.sessionApi.deviceId);
        if (_current(epoch, repository)) _set(CartRepeatState(saved: saved));
      } catch (_) {
        if (_current(epoch, repository)) {
          _set(
            const CartRepeatState(
              message: 'Не удалось прочитать сохранённый повтор.',
              recoveryBlocked: true,
            ),
          );
        }
      }
    });
    return CartRepeatState(
      loading: repository != null && owner != null && owner.isNotEmpty,
    );
  }

  bool _current(int epoch, CartRepository repository) =>
      ref.mounted &&
      epoch == _epoch &&
      identical(ref.read(cartRepositoryProvider), repository);
  bool get _locked =>
      ref.read(cartSubmitControllerProvider).editingLocked ||
      ref.read(cartEditControllerProvider).loading ||
      versionBlocksWork(ref.read(appVersionControllerProvider));

  void _set(CartRepeatState value) {
    state = value;
    ref
        .read(cartRepeatWorkProvider.notifier)
        .set(
          loading: value.loading,
          saved: value.saved != null || value.recoveryBlocked,
        );
  }

  Future<void> _queue(Future<void> Function() action) =>
      ref.read(repeatWriteQueueProvider).run(action);

  RepeatSnapshot? _snapshot() {
    final edit = ref.read(cartEditControllerProvider);
    if (!edit.isRepeat || !edit.active) return null;
    final draft = ref.read(cartDraftProvider);
    return RepeatSnapshot(
      ownerScope: edit.repeatScope!,
      selectedDateKey: edit.dateKey!,
      revisions: edit.revisions,
      quantities: {
        for (final date in edit.revisions.keys)
          if (draft.containsKey(date)) date: draft[date]!,
      },
    );
  }

  Future<void> persistNow() {
    final snapshot = _snapshot();
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (snapshot == null || repository == null || owner == null) {
      return Future.value();
    }
    final store = ref.read(cartRepeatStoreProvider);
    final device = repository.sessionApi.deviceId;
    return _queue(() => store.save(owner, device, snapshot));
  }

  void _persistObserved() {
    final epoch = _epoch;
    unawaited(
      persistNow().catchError((Object _) {
        if (ref.mounted && epoch == _epoch) {
          _set(
            CartRepeatState(
              saved: state.saved,
              loading: state.loading,
              message: 'Не удалось сохранить повторённую корзину. Проверьте хранилище и повторите сохранение.',
            ),
          );
          if (!ref.read(cartEditControllerProvider).blocked) {
            ref
                .read(cartEditControllerProvider.notifier)
                .block('Повторённая корзина не сохранена.');
          }
        }
      }),
    );
  }

  bool _targetValid(String date) {
    final dates = ref.read(menuAllowedDatesProvider);
    final menu = ref.read(menuControllerProvider);
    return !dates.isLoading &&
        !dates.hasError &&
        dates.asData?.value != null &&
        isOrderDateAllowed(dates.asData!.value, date) &&
        !menu.isLoading &&
        !menu.hasError &&
        (menu.asData?.value ?? const []).any(
          (w) => w.deliveryDays.any((d) => d.dateKey == date),
        );
  }

  Future<void> _reload() async {
    await ref.read(menuControllerProvider.notifier).reload();
    if (!ref.mounted) return;
    await ref.read(menuAllowedDatesProvider.notifier).reload();
  }

  String _error(Object error) => error is ApiException
      ? error.message
      : error is FormatException
      ? error.message.toString()
      : 'Не удалось загрузить повтор. Корзина сохранена.';

  Future<bool> repeat(
    List<String> dates, {
    String? selected,
    bool Function()? viewCurrent,
  }) async {
    if (state.loading || _locked) return false;
    await ref.read(cartEditControllerProvider.notifier).ready;
    if (!ref.mounted) return false;
    final ordinary = ref.read(cartEditControllerProvider);
    if ((!ordinary.isRepeat && ordinary.active) || ordinary.hasSavedWork) {
      _set(
        CartRepeatState(
          saved: state.saved,
          recoveryBlocked: state.recoveryBlocked,
          message: 'Завершите обычный набор или подтвердите начало заново перед повтором.',
        ),
      );
      return false;
    }
    await ready;
    if (!ref.mounted ||
        state.saved != null ||
        state.recoveryBlocked ||
        state.loading ||
        _locked) {
      return false;
    }
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (repository == null || owner == null || owner.isEmpty || dates.isEmpty) {
      return false;
    }
    final epoch = ++_epoch;
    _set(const CartRepeatState(loading: true));
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).ready;
      if (!_current(epoch, repository)) return false;
      await _reload();
      if (!_current(epoch, repository)) return false;
      final response = await repository.loadRepeat(dates);
      if (!_current(epoch, repository) ||
          _locked ||
          !(viewCurrent?.call() ?? true)) {
        return false;
      }
      final edit = ref.read(cartEditControllerProvider);
      if (edit.isRepeat && edit.repeatScope != response.ownerScope) {
        throw const FormatException(
          'Владелец корзины изменился. Повтор не применён.',
        );
      }
      final previousDraft = ref.read(cartDraftProvider);
      final draft = {...previousDraft};
      final revisions = {
        ...(edit.isRepeat ? edit.revisions : <String, String>{}),
      };
      final report = <String>[];
      var added = 0;
      final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
      for (final day in response.days) {
        final label = formatCalendarDate(day.dateKey);
        if ((draft[day.dateKey]?.isNotEmpty ?? false)) {
          report.add('$label: есть черновик — пропущен.');
          continue;
        }
        if (day.status != 'ready' || !_targetValid(day.dateKey)) {
          final reason = switch (day.status) {
            'occupied' => 'уже есть заказ',
            'no_history' => 'нет заказа за прошлые две недели',
            'ambiguous' => 'неоднозначные данные заказа',
            _ => 'день закрыт',
          };
          report.add('$label: $reason.');
          continue;
        }
        final menuIds = {
          for (final week in weeks)
            for (final d in week.days)
              if (d.dateKey == day.dateKey)
                for (final category in d.categories)
                  for (final dish in category.dishes) dish.dishId,
        };
        final quantities = <String, int>{};
        for (final dish in day.dishes) {
          if (menuIds.contains(dish.id)) {
            quantities[dish.id] = dish.quantity;
          } else {
            report.add('$label: ${dish.name} — отсутствует в меню, пропущено.');
          }
        }
        if (quantities.isEmpty) {
          report.add(
            '$label: источник от ${formatCalendarDate(day.sourceDateKey!)}; доступных блюд для повторения нет.',
          );
          continue;
        }
        draft[day.dateKey] = quantities;
        revisions[day.dateKey] = day.revision;
        added++;
        report.add(
          '$label: повторён заказ от ${formatCalendarDate(day.sourceDateKey!)}.',
        );
      }
      if (added == 0) {
        _set(CartRepeatState(message: report.join('\n')));
        return false;
      }
      final chosen = revisions.containsKey(selected)
          ? selected!
          : (revisions.keys.toList()..sort()).first;
      // Сначала атомарно сохраняем снимок; при отказе хранилища ничего не применяем.
      final snapshot = RepeatSnapshot(
        ownerScope: response.ownerScope,
        selectedDateKey: chosen,
        revisions: revisions,
        quantities: {
          for (final d in revisions.keys)
            if (draft.containsKey(d)) d: draft[d]!,
        },
      );
      final store = ref.read(cartRepeatStoreProvider);
      Future<void> rollback() => _queue(() {
        if (!_current(epoch, repository)) return Future<void>.value();
        final previousSnapshot = _snapshot();
        return previousSnapshot == null
            ? store.clear(owner, repository.sessionApi.deviceId)
            : store.save(
                owner,
                repository.sessionApi.deviceId,
                previousSnapshot,
              );
      });
      await _queue(
        () => store.save(owner, repository.sessionApi.deviceId, snapshot),
      );
      if (!_current(epoch, repository) ||
          _locked ||
          !(viewCurrent?.call() ?? true)) {
        if (_current(epoch, repository)) {
          await rollback();
        }
        return false;
      }
      if (!identical(previousDraft, ref.read(cartDraftProvider)) ||
          revisions.keys.any((date) => !_targetValid(date))) {
        await rollback();
        throw const FormatException(
          'Черновик или доступность изменились во время загрузки. Повтор не применён.',
        );
      }
      ref.read(cartDraftProvider.notifier).replaceAll(draft);
      ref
          .read(cartEditControllerProvider.notifier)
          .prepareRepeat(
            owner: owner,
            scope: response.ownerScope,
            revisions: revisions,
            selected: chosen,
          );
      ref.read(cartSubmitControllerProvider.notifier).acknowledge();
      _set(CartRepeatState(message: report.join('\n')));
      return true;
    } catch (error) {
      if (_current(epoch, repository)) {
        _set(CartRepeatState(message: _error(error)));
      }
      return false;
    } finally {
      if (_current(epoch, repository) && state.loading) {
        _set(const CartRepeatState());
      }
    }
  }

  Future<bool> resume({bool Function()? viewCurrent}) async {
    if (state.loading || _locked) return false;
    await ref.read(cartEditControllerProvider.notifier).ready;
    if (!ref.mounted) return false;
    final ordinary = ref.read(cartEditControllerProvider);
    if ((!ordinary.isRepeat && ordinary.active) || ordinary.hasSavedWork) {
      _set(
        CartRepeatState(
          saved: state.saved,
          recoveryBlocked: state.recoveryBlocked,
          message: 'Завершите обычный набор перед восстановлением повтора.',
        ),
      );
      return false;
    }
    await ready;
    if (!ref.mounted || state.loading || _locked) return false;
    final saved = state.saved ?? _snapshot();
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (saved == null || repository == null || owner == null || owner.isEmpty) {
      return false;
    }
    final epoch = ++_epoch;
    _set(CartRepeatState(loading: true, saved: saved));
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).ready;
      if (!_current(epoch, repository)) return false;
      await _reload();
      if (!_current(epoch, repository)) return false;
      final response = await repository.loadRepeat(
        saved.revisions.keys.toList(),
      );
      if (!_current(epoch, repository) ||
          _locked ||
          !(viewCurrent?.call() ?? true)) {
        return false;
      }
      if (response.ownerScope != saved.ownerScope) {
        throw const FormatException(
          'Сохранённый повтор принадлежит другому владельцу.',
        );
      }
      final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
      for (final day in response.days) {
        if (day.revision != saved.revisions[day.dateKey] ||
            !{'ready', 'no_history'}.contains(day.status) ||
            !_targetValid(day.dateKey)) {
          throw FormatException(
            '${formatCalendarDate(day.dateKey)}: заказ изменился или день закрыт. Сохранённый состав не заменён.',
          );
        }
        final ids = {
          for (final w in weeks)
            for (final d in w.days)
              if (d.dateKey == day.dateKey)
                for (final c in d.categories)
                  for (final dish in c.dishes) dish.dishId,
        };
        if ((saved.quantities[day.dateKey]?.keys ?? const <String>[]).any(
          (id) => !ids.contains(id),
        )) {
          throw FormatException(
            '${formatCalendarDate(day.dateKey)}: меню изменилось. Сохранённый состав не заменён.',
          );
        }
      }
      final previousDraft = ref.read(cartDraftProvider);
      final draft = {...previousDraft};
      for (final date in saved.revisions.keys) {
        draft.remove(date);
        if (saved.quantities.containsKey(date)) {
          draft[date] = saved.quantities[date]!;
        }
      }
      final store = ref.read(cartRepeatStoreProvider);
      await _queue(
        () => store.save(owner, repository.sessionApi.deviceId, saved),
      );
      if (!_current(epoch, repository) ||
          _locked ||
          !(viewCurrent?.call() ?? true)) {
        return false;
      }
      if (!identical(previousDraft, ref.read(cartDraftProvider)) ||
          saved.revisions.keys.any((date) => !_targetValid(date))) {
        throw const FormatException(
          'Черновик или доступность изменились во время восстановления. Сохранённый повтор не заменён.',
        );
      }
      ref.read(cartDraftProvider.notifier).replaceAll(draft);
      ref
          .read(cartEditControllerProvider.notifier)
          .prepareRepeat(
            owner: owner,
            scope: saved.ownerScope,
            revisions: saved.revisions,
            selected: saved.selectedDateKey,
          );
      _set(
        const CartRepeatState(
          message: 'Повторённая корзина восстановлена. Проверьте состав и текущие цены.',
        ),
      );
      return true;
    } catch (error) {
      if (_current(epoch, repository)) {
        _set(CartRepeatState(saved: saved, message: _error(error)));
      }
      return false;
    } finally {
      if (_current(epoch, repository) && state.loading) {
        _set(CartRepeatState(saved: saved));
      }
    }
  }

  Future<void> clearSaved() async {
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (repository == null || owner == null) return;
    final epoch = ++_epoch;
    final store = ref.read(cartRepeatStoreProvider);
    await _queue(() => store.clear(owner, repository.sessionApi.deviceId));
    if (_current(epoch, repository)) _set(const CartRepeatState());
  }

  Future<void> discard() async {
    if (state.loading || _locked) return;
    final edit = ref.read(cartEditControllerProvider);
    try {
      await clearSaved();
      if (!ref.mounted) return;
      if (edit.isRepeat &&
          ref.read(cartEditControllerProvider).repeatScope ==
              edit.repeatScope) {
        ref.read(cartEditControllerProvider.notifier).end(force: true);
        final draft = {...ref.read(cartDraftProvider)};
        for (final date in edit.revisions.keys) {
          draft.remove(date);
        }
        ref.read(cartDraftProvider.notifier).replaceAll(draft);
      }
    } catch (error) {
      if (ref.mounted) {
        _set(
          CartRepeatState(
            saved: state.saved,
            recoveryBlocked: state.recoveryBlocked,
            message: _error(error),
          ),
        );
      }
    }
  }
}
