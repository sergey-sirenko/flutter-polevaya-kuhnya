import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_store.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';

final class CartEditState {
  const CartEditState({
    this.dateKey,
    this.owner,
    this.revision,
    this.original = const {},
    this.names = const {},
    this.loading = false,
    this.message,
    this.blocked = false,
    this.repeatScope,
    this.revisions = const {},
    this.snapshotScope,
    this.originals = const {},
    this.namesByDate = const {},
    this.recovery,
    this.restoring = false,
    this.recoveryError = false,
    this.storageError = false,
  });
  final String? dateKey;
  final String? owner;
  final String? revision;
  final Map<String, int> original;
  final Map<String, String> names;
  final bool loading;
  final String? message;
  final bool blocked;
  final String? repeatScope;
  final Map<String, String> revisions;
  final String? snapshotScope;
  final Map<String, Map<String, int>> originals;
  final Map<String, Map<String, String>> namesByDate;
  final CartWorkSnapshot? recovery;
  final bool restoring;
  final bool recoveryError;
  final bool storageError;
  bool get isRepeat => repeatScope != null;
  Map<String, String> get preparedRevisions => revisions.isNotEmpty
      ? revisions
      : {if (dateKey != null && revision != null) dateKey!: revision!};
  bool get active => dateKey != null && revision != null;
  bool get canCancel => !isRepeat && active && revision != 'none';
  bool get hasSavedWork => recovery != null || recoveryError || restoring;

  List<String> changedDates(Map<String, Map<String, int>> draft) =>
      (preparedRevisions.keys
          .where(
            (d) => !mapEquals(
              originals[d] ?? (d == dateKey ? original : const <String, int>{}),
              draft[d] ?? const <String, int>{},
            ),
          )
          .toList()
        ..sort());

  CartEditState copy({
    String? dateKey,
    bool? loading,
    bool? blocked,
    String? message,
    bool clearMessage = false,
    bool? storageError,
    bool? restoring,
    bool? recoveryError,
  }) => CartEditState(
    dateKey: dateKey ?? this.dateKey,
    owner: owner,
    revision: dateKey == null ? revision : preparedRevisions[dateKey],
    original: dateKey == null ? original : originals[dateKey] ?? const {},
    names: names,
    loading: loading ?? this.loading,
    message: clearMessage ? null : message ?? this.message,
    blocked: blocked ?? this.blocked,
    repeatScope: repeatScope,
    revisions: revisions,
    snapshotScope: snapshotScope,
    originals: originals,
    namesByDate: namesByDate,
    recovery: recovery,
    restoring: restoring ?? this.restoring,
    recoveryError: recoveryError ?? this.recoveryError,
    storageError: storageError ?? this.storageError,
  );
}

final cartEditControllerProvider =
    NotifierProvider<CartEditController, CartEditState>(CartEditController.new);
final cartChangedDatesProvider = Provider<List<String>>((ref) {
  final edit = ref.watch(cartEditControllerProvider);
  if (!edit.active) return const [];
  if (edit.isRepeat) {
    return ref.watch(editingCartProvider).days.map((d) => d.dateKey).toList();
  }
  return edit.changedDates(ref.watch(cartDraftProvider));
});
final cartCancelledDatesProvider = Provider<List<String>>((ref) {
  final edit = ref.watch(cartEditControllerProvider);
  if (edit.isRepeat) return const [];
  final draft = ref.watch(cartDraftProvider);
  return ref
      .watch(cartChangedDatesProvider)
      .where(
        (d) =>
            edit.preparedRevisions[d] != 'none' && (draft[d]?.isEmpty ?? true),
      )
      .toList();
});
final submittingCartProvider = Provider<Cart>((ref) {
  final cart = ref.watch(editingCartProvider);
  final dates = ref.watch(cartChangedDatesProvider).toSet();
  return Cart(days: cart.days.where((d) => dates.contains(d.dateKey)).toList());
});

/// Право каждой даты подтверждается снимком текущей сессии, а не draft.
final cartDayEditPermissionProvider = Provider.family<bool, String>((
  ref,
  dateKey,
) {
  final edit = ref.watch(cartEditControllerProvider);
  final dates = ref.watch(menuAllowedDatesProvider);
  final profile = ref.watch(sessionProfileProvider);
  final menu = ref.watch(menuControllerProvider);
  return !((profile?.orders ?? const <UserOrderDay>[]).any(
        (d) => d.dateRaw.startsWith(dateKey) && !d.changes,
      )) &&
      edit.active &&
      !edit.loading &&
      !edit.blocked &&
      edit.preparedRevisions.containsKey(dateKey) &&
      edit.owner == profile?.login &&
      !dates.isLoading &&
      !dates.hasError &&
      dates.asData?.value != null &&
      isOrderDateAllowed(dates.asData!.value, dateKey) &&
      !menu.isLoading &&
      !menu.hasError &&
      (menu.asData?.value ?? const []).any(
        (w) => w.deliveryDays.any((d) => d.dateKey == dateKey),
      ) &&
      !versionBlocksWork(ref.watch(appVersionControllerProvider));
});
final cartDayEditableProvider = Provider.family<bool, String>(
  (ref, dateKey) =>
      ref.watch(cartDayEditPermissionProvider(dateKey)) &&
      !ref.watch(cartRepeatWorkProvider).loading &&
      !ref.watch(cartSubmitControllerProvider).editingLocked,
);

final editingCartProvider = Provider<Cart>((ref) {
  final edit = ref.watch(cartEditControllerProvider);
  if (!edit.active) return Cart.fromDraft(const {});
  final draft = ref.watch(cartDraftProvider);
  return Cart.fromDraft({
    for (final d in edit.preparedRevisions.keys)
      if (draft.containsKey(d)) d: draft[d]!,
  });
});

class CartEditController extends Notifier<CartEditState> {
  int _epoch = 0;
  int _writeVersion = 0;
  bool _pauseWrites = false;
  Future<void> _ready = Future<void>.value();
  Future<void> get ready => _ready;

  @override
  CartEditState build() {
    final api = ref.watch(sessionApiProvider);
    ref.watch(cartWorkStoreProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    final epoch = ++_epoch;
    _writeVersion++;
    _pauseWrites = false;
    ref.onDispose(() => _epoch++);
    ref.listen(cartDraftProvider, (_, _) => _persistObserved());
    ref.listen(menuSelectionProvider, (_, next) {
      if (next != null && state.active && state.dateKey != next.dateKey) {
        selectDay(next.dateKey);
      }
    });
    _ready = Future<void>.microtask(() async {
      if (api == null || owner == null || !_current(epoch)) return;
      try {
        await ref.read(cartWorkQueueProvider).run(() async {
          final result = await _loadSavedChanges(owner, api.deviceId);
          if (_current(epoch)) state = CartEditState(recovery: result);
        });
      } catch (_) {
        if (_current(epoch)) {
          state = const CartEditState(
            recoveryError: true,
            message: 'Не удалось прочитать сохранённый набор. Повторите чтение или выберите «Оставить как есть».',
          );
        }
      }
    });
    return CartEditState(restoring: api != null && owner != null);
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;

  Future<CartWorkSnapshot?> _loadSavedChanges(
    String owner,
    String device,
  ) async {
    final saved = await ref.read(cartWorkStoreProvider).load(owner, device);
    // Само открытие корзины сохраняет исходный состав. Продолжение требуется
    // только для локальных правок, включая удаление всех блюд выбранного дня.
    return saved != null && saved.changedDates.isNotEmpty ? saved : null;
  }

  bool get _locked =>
      ref.read(cartSubmitControllerProvider).editingLocked ||
      versionBlocksWork(ref.read(appVersionControllerProvider)) ||
      ref.read(cartRepeatWorkProvider).loading;

  void end({bool force = false}) {
    // Навигация завершает только незавершённую подготовку.
    if (!force && !state.loading) return;
    final recovery = force ? null : state.recovery ?? workSnapshot();
    _epoch++;
    state = CartEditState(
      recovery: recovery,
      recoveryError: !force && state.recoveryError,
    );
    _pauseWrites = false;
  }

  void block(String message) {
    _epoch++;
    state = state.copy(blocked: true, loading: false, message: message);
  }

  void prepareRepeat({
    required String owner,
    required String scope,
    required Map<String, String> revisions,
    required String selected,
  }) {
    _epoch++;
    state = CartEditState(
      owner: owner,
      dateKey: selected,
      revision: revisions[selected],
      repeatScope: scope,
      revisions: Map.unmodifiable(revisions),
    );
  }

  void selectDay(String date) {
    if (!state.active ||
        state.loading ||
        _locked ||
        !state.preparedRevisions.containsKey(date)) {
      return;
    }
    if (!_dayAllowed(date)) return;
    state = state.copy(dateKey: date);
    _persistObserved();
  }

  void selectRepeatDay(String date) => selectDay(date);

  bool _dayAllowed(String date) {
    final dates = ref.read(menuAllowedDatesProvider);
    final profile = ref.read(sessionProfileProvider);
    return !state.blocked &&
        state.owner == profile?.login &&
        !dates.isLoading &&
        !dates.hasError &&
        dates.asData?.value != null &&
        isOrderDateAllowed(dates.asData!.value, date) &&
        !(profile?.orders ?? const <UserOrderDay>[]).any(
          (d) => d.dateRaw.startsWith(date) && !d.changes,
        );
  }

  CartWorkSnapshot? workSnapshot() {
    if (!state.active || state.isRepeat || state.snapshotScope == null) {
      return null;
    }
    final draft = ref.read(cartDraftProvider);
    return CartWorkSnapshot(
      ownerScope: state.snapshotScope!,
      selectedDateKey: state.dateKey!,
      revisions: state.preparedRevisions,
      originals: state.originals,
      names: state.namesByDate,
      quantities: {
        for (final d in state.preparedRevisions.keys)
          if (draft.containsKey(d)) d: draft[d]!,
      },
    );
  }

  Future<void> persistNow() async {
    final snapshot = workSnapshot();
    if (snapshot == null || _pauseWrites) return;
    final api = ref.read(sessionApiProvider);
    final owner = state.owner;
    if (api == null || owner == null) {
      return;
    }
    final epoch = _epoch;
    final version = ++_writeVersion;
    final store = ref.read(cartWorkStoreProvider);
    try {
      await ref
          .read(cartWorkQueueProvider)
          .run(() => store.save(owner, api.deviceId, snapshot));
      if (_current(epoch) && version == _writeVersion && state.storageError) {
        state = state.copy(storageError: false, clearMessage: true);
      }
    } catch (_) {
      if (_current(epoch) && version == _writeVersion) {
        state = state.copy(
          storageError: true,
          message:
              'Не удалось сохранить набор на устройстве. Повторите сохранение.',
        );
      }
      rethrow;
    }
  }

  void _persistObserved() {
    if (_pauseWrites || !state.active || state.isRepeat || state.loading) {
      return;
    }
    unawaited(persistNow().catchError((Object _) {}));
  }

  Future<void> clearSavedAfterAccepted(String owner, String device) async {
    _pauseWrites = true;
    _writeVersion++;
    final store = ref.read(cartWorkStoreProvider);
    await ref.read(cartWorkQueueProvider).run(() => store.clear(owner, device));
  }

  Future<void> discard() async {
    if (state.loading || _locked || state.isRepeat) return;
    final api = ref.read(sessionApiProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (api == null || owner == null) return;
    final epoch = ++_epoch;
    final previous = state;
    state = state.copy(loading: true);
    try {
      final dates =
          state.recovery?.revisions.keys ?? state.preparedRevisions.keys;
      await clearSavedAfterAccepted(owner, api.deviceId);
      if (!_current(epoch)) return;
      final draft = {...ref.read(cartDraftProvider)};
      for (final d in dates) {
        draft.remove(d);
      }
      ref.read(cartDraftProvider.notifier).replaceAll(draft);
      state = const CartEditState();
      _pauseWrites = false;
    } catch (_) {
      if (_current(epoch)) {
        _pauseWrites = false;
        state = previous.copy(message: 'Не удалось удалить набор. Повторите.');
      }
    }
  }

  Future<bool> begin(String dateKey) async {
    await ready;
    if (!ref.mounted || state.loading || _locked) return false;
    if (state.active) {
      if (state.blocked || !state.preparedRevisions.containsKey(dateKey)) {
        state = state.copy(
          message: 'Этот день не подготовлен или набор заблокирован. Выберите «Оставить как есть» и подтвердите сброс локальных правок.',
        );
        return false;
      }
      selectDay(dateKey);
      return _dayAllowed(dateKey);
    }
    if (state.hasSavedWork) {
      state = state.copy(
        message: 'Есть сохранённые изменения. Выберите «Восстановить изменения» или «Оставить как есть».',
      );
      return false;
    }
    return _prepare(dateKey);
  }

  Future<bool> resume({bool restoreOpenedCart = false}) async {
    await ready;
    if (!ref.mounted || state.loading || _locked || state.isRepeat) {
      return false;
    }
    var saved = state.recovery ?? workSnapshot();
    if (saved == null && restoreOpenedCart && !state.recoveryError) {
      final api = ref.read(sessionApiProvider);
      final owner = ref.read(sessionProfileProvider)?.login;
      if (api == null || owner == null) return false;
      final epoch = _epoch;
      final store = ref.read(cartWorkStoreProvider);
      try {
        // На /cart после F5 восстанавливаем и открытый исходный заказ.
        // На остальных страницах recovery по-прежнему содержит только правки.
        await ref.read(cartWorkQueueProvider).run(() async {
          saved = await store.load(owner, api.deviceId);
        });
      } catch (_) {
        if (_current(epoch)) {
          state = state.copy(
            recoveryError: true,
            message:
                'Не удалось прочитать сохранённый набор. Повторите чтение.',
          );
        }
        return false;
      }
      if (!_current(epoch) ||
          !identical(api, ref.read(sessionApiProvider)) ||
          state.active ||
          state.loading ||
          _locked ||
          state.isRepeat) {
        return false;
      }
      if (saved != null) state = CartEditState(recovery: saved);
    }
    final work = saved;
    if (work == null) return false;
    return _prepare(work.selectedDateKey, saved: work);
  }

  Future<void> retryRead() async {
    if (state.loading || _locked || state.active) return;
    final api = ref.read(sessionApiProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (api == null || owner == null) return;
    final epoch = ++_epoch;
    state = state.copy(loading: true);
    try {
      final saved = await _loadSavedChanges(owner, api.deviceId);
      if (_current(epoch)) state = CartEditState(recovery: saved);
    } catch (_) {
      if (_current(epoch)) {
        state = const CartEditState(
          recoveryError: true,
          message: 'Не удалось прочитать сохранённый набор.',
        );
      }
    }
  }

  Future<bool> _prepare(String selected, {CartWorkSnapshot? saved}) async {
    final repeat = ref.read(cartRepeatWorkProvider);
    if (repeat.loading || repeat.saved) return false;
    final repository = ref.read(cartRepositoryProvider);
    final api = ref.read(sessionApiProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (repository == null || api == null || owner == null) return false;
    final generation = ref.read(sessionControllerProvider).generation;
    final epoch = ++_epoch;
    final previous = state;
    state = state.copy(loading: true, clearMessage: true);
    _pauseWrites = true;
    var resetSavedChanges = false;
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).ready;
      if (!_current(epoch)) return false;
      if (saved != null) {
        await ref.read(menuControllerProvider.notifier).reload();
      }
      if (!_current(epoch)) return false;
      final weeks = ref.read(menuControllerProvider).asData?.value;
      final menuDates = <String>{
        for (final w in weeks ?? const [])
          for (final d in w.deliveryDays) d.dateKey,
      };
      final requested = (saved?.revisions.keys.toList() ?? menuDates.toList())
        ..sort();
      if ((saved == null && !menuDates.contains(selected)) ||
          requested.isEmpty ||
          requested.length > 31) {
        throw const FormatException(
          'Меню недоступно или содержит более 31 даты. Набор не подготовлен.',
        );
      }
      final snapshot = await repository.loadSnapshot(requested);
      if (!_current(epoch) ||
          !identical(api, ref.read(sessionApiProvider)) ||
          generation != ref.read(sessionControllerProvider).generation) {
        return false;
      }
      if (snapshot.profile.login != owner ||
          (saved != null && saved.ownerScope != snapshot.ownerScope)) {
        throw const FormatException('Владелец сохранённого набора изменился.');
      }
      final revisions = <String, String>{};
      final originals = <String, Map<String, int>>{};
      final names = <String, Map<String, String>>{};
      for (final date in requested) {
        final orders = snapshot.profile.orders
            .where((d) => d.dateRaw.startsWith(date))
            .toList();
        final revision = snapshot.revisions[date];
        String? reason;
        // Закрытие даты сбрасывает только её локальный набор. Версия и
        // состав закрытого заказа уже не нужны для восстановления корзины.
        if (!menuDates.contains(date) ||
            !isOrderDateAllowed(snapshot.allowedDates, date) ||
            orders.any((o) => !o.changes)) {
          continue;
        }
        if (revision == null || revision == 'ambiguous' || orders.length > 1) {
          reason = 'заказ неоднозначен';
        }
        if (reason != null) {
          if (date == selected || saved != null) {
            throw FormatException('$date: $reason. Набор сохранён.');
          }
          continue;
        }
        final quantities = <String, int>{};
        final dishNames = <String, String>{};
        for (final dish
            in orders.isEmpty
                ? const <UserOrderDish>[]
                : orders.single.dishes) {
          if (dish.dishId.trim().isEmpty ||
              !dish.quantity.isFinite ||
              dish.quantity <= 0 ||
              dish.quantity != dish.quantity.toInt() ||
              quantities.containsKey(dish.dishId)) {
            throw const FormatException(
              'Состав заказа содержит некорректное количество или идентификатор блюда.',
            );
          }
          quantities[dish.dishId] = dish.quantity.toInt();
          dishNames[dish.dishId] = dish.name;
        }
        if (revision == 'none' && quantities.isNotEmpty) {
          throw const FormatException(
            'Состав не соответствует версии пустого заказа.',
          );
        }
        if (saved != null &&
            (saved.revisions[date] != revision ||
                !mapEquals(saved.originals[date], quantities))) {
          // При единственном доступном действии автоматически оставляем
          // серверный заказ как есть. Применяем его только после проверки
          // всего ответа и успешной записи нового локального снимка.
          resetSavedChanges = true;
        }
        revisions[date] = revision!;
        originals[date] = quantities;
        names[date] = dishNames;
      }
      final restoredQuantities = resetSavedChanges
          ? originals
          : saved?.quantities ?? originals;
      final work = revisions.isEmpty
          ? null
          : CartWorkSnapshot(
              ownerScope: snapshot.ownerScope,
              selectedDateKey: revisions.containsKey(selected)
                  ? selected
                  : revisions.keys.first,
              revisions: revisions,
              originals: originals,
              names: names,
              quantities: {
                for (final date in revisions.keys)
                  if (restoredQuantities[date]?.isNotEmpty ?? false)
                    date: restoredQuantities[date]!,
              },
            );
      if (!_current(epoch) || _locked) return false;
      ref
          .read(sessionControllerProvider.notifier)
          .applyProfileSnapshot(
            snapshot.profile,
            generation: generation,
            ownerScope: snapshot.ownerScope,
          );
      {
        final store = ref.read(cartWorkStoreProvider);
        await ref.read(cartWorkQueueProvider).run(() async {
          if (!_current(epoch)) return;
          if (work == null) {
            await store.clear(owner, api.deviceId);
          } else {
            await store.save(owner, api.deviceId, work);
          }
          // Очистка выполняется в той же очереди, до сохранения нового набора.
          if (!_current(epoch)) await store.clear(owner, api.deviceId);
        });
        if (!_current(epoch)) return false;
      }
      if (_locked || !identical(api, ref.read(sessionApiProvider))) {
        return false;
      }
      ref
          .read(menuAllowedDatesProvider.notifier)
          .applySnapshot(snapshot.allowedDates);
      final next = {...ref.read(cartDraftProvider)};
      for (final date in requested) {
        next.remove(date);
        if (work?.quantities[date]?.isNotEmpty ?? false) {
          next[date] = work!.quantities[date]!;
        }
      }
      ref.read(cartDraftProvider.notifier).replaceAll(next);
      if (work == null) {
        state = const CartEditState();
        return false;
      }
      state = CartEditState(
        dateKey: work.selectedDateKey,
        owner: owner,
        revision: work.revisions[work.selectedDateKey],
        original: work.originals[work.selectedDateKey]!,
        revisions: work.revisions,
        originals: work.originals,
        namesByDate: work.names,
        names: {
          for (final day in work.names.entries)
            for (final item in day.value.entries)
              '${day.key}|${item.key}': item.value,
        },
        snapshotScope: work.ownerScope,
      );
      _pauseWrites = false;
      ref.read(cartSubmitControllerProvider.notifier).acknowledge();
      return true;
    } catch (error) {
      if (_current(epoch)) {
        state = previous.copy(
          loading: false,
          blocked: saved != null && previous.active,
          message: error is FormatException ? error.message.toString() : 'Не удалось подготовить набор. Повторите загрузку; правки сохранены.',
        );
      }
      return false;
    } finally {
      if (_current(epoch)) {
        _pauseWrites = false;
        if (state.loading) state = previous;
      }
    }
  }
}
