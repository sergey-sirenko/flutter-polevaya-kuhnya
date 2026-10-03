import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_freshness.dart';
import 'package:polevaya_kuhnya/features/cart/cart_order_request.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submission_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_snapshot.dart';
import 'package:polevaya_kuhnya/features/cart/server_order_totals.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';

enum CartSubmitPhase {
  idle,
  restoring,
  preparing,
  submitting,
  checkingResult,
  succeeded,
  failed,
  outcomeUnknown,
  recoveryBlocked,
}

final class CartSubmitState {
  const CartSubmitState({
    this.phase = CartSubmitPhase.idle,
    this.message,
    this.submissionId,
    this.comparisons = const [],
    this.canSafeRetry = false,
  });
  final CartSubmitPhase phase;
  final String? message;
  final String? submissionId;
  final List<FinalAmountComparison> comparisons;
  final bool canSafeRetry;
  bool get isBusy => switch (phase) {
    CartSubmitPhase.restoring ||
    CartSubmitPhase.preparing ||
    CartSubmitPhase.submitting ||
    CartSubmitPhase.checkingResult => true,
    _ => false,
  };
  bool get editingLocked =>
      isBusy ||
      phase == CartSubmitPhase.outcomeUnknown ||
      phase == CartSubmitPhase.recoveryBlocked;
}

final cartSubmitControllerProvider =
    NotifierProvider<CartSubmitController, CartSubmitState>(
      CartSubmitController.new,
    );

class CartSubmitController extends Notifier<CartSubmitState> {
  CartPendingSubmission? _pending;
  int _epoch = 0;

  @override
  CartSubmitState build() {
    final repository = ref.watch(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    final epoch = ++_epoch;
    _pending = null;
    ref.onDispose(() => _epoch++);
    if (repository == null || owner == null || owner.isEmpty) {
      return const CartSubmitState();
    }
    unawaited(Future<void>.microtask(() => _restore(repository, owner, epoch)));
    return const CartSubmitState(phase: CartSubmitPhase.restoring);
  }

  bool _current(int epoch, CartRepository repository) =>
      ref.mounted &&
      epoch == _epoch &&
      identical(ref.read(cartRepositoryProvider), repository);

  Future<void> _restore(
    CartRepository repository,
    String owner,
    int epoch,
  ) async {
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).ready;
      if (!_current(epoch, repository)) return;
      final pending = await repository.loadPending(owner);
      if (!_current(epoch, repository)) return;
      _pending = pending;
      state = pending == null
          ? const CartSubmitState()
          : CartSubmitState(
              phase: CartSubmitPhase.outcomeUnknown,
              submissionId: pending.id,
              message: AppStrings.cartRestoredAttempt,
              canSafeRetry: true,
            );
    } catch (_) {
      if (!_current(epoch, repository)) return;
      state = const CartSubmitState(
        phase: CartSubmitPhase.recoveryBlocked,
        message: AppStrings.cartRecoveryBlocked,
      );
    }
  }

  Future<void> retryRestore() async {
    if (state.phase != CartSubmitPhase.recoveryBlocked) return;
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    if (repository == null || owner == null) return;
    state = const CartSubmitState(phase: CartSubmitPhase.restoring);
    await _restore(repository, owner, _epoch);
  }

  Future<void> submit({Set<String> confirmedCancellations = const {}}) async {
    if (state.editingLocked || _pending != null) return;
    final edit = ref.read(cartEditControllerProvider);
    if (ref.read(cartRepeatWorkProvider).loading) return;
    final preparedDates = ref.read(cartChangedDatesProvider);
    final cancelled = ref.read(cartCancelledDatesProvider).toSet();
    if (!setEquals(cancelled, confirmedCancellations)) {
      state = const CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: 'Подтвердите список отменяемых дней перед сохранением.',
      );
      return;
    }
    if (preparedDates.isEmpty || preparedDates.length > 31) {
      state = const CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: 'Нет изменений или превышен предел 31 даты.',
      );
      return;
    }
    if (!edit.active ||
        preparedDates.any((d) => !ref.read(cartDayEditPermissionProvider(d)))) {
      state = const CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: 'Начните изменение заказа кнопкой корзины выбранного дня.',
      );
      return;
    }
    final repository = ref.read(cartRepositoryProvider);
    final owner = ref.read(sessionProfileProvider)?.login;
    final pricing = ref.read(cartSubmissionPricingProvider);
    final cart = ref.read(submittingCartProvider);
    final menu = ref.read(menuControllerProvider).asData?.value;
    final allowed = ref.read(menuAllowedDatesProvider).asData?.value;
    if (repository == null ||
        owner == null ||
        pricing == null ||
        menu == null) {
      state = const CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: AppStrings.cartSessionOrMenuMissing,
      );
      return;
    }
    if ((cart.isEmpty && cancelled.isEmpty) || pricing.hasBlockingConstraint) {
      state = CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: cart.isEmpty
            ? AppStrings.cartEmpty
            : AppStrings.cartFixConstraints,
      );
      return;
    }
    final freshness = checkCartFreshness(
      cart: cart,
      weeks: menu,
      allowedDateKeys: allowed,
    );
    if (freshness.any((i) => i.kind != CartFreshnessKind.priceChanged)) {
      state = const CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: AppStrings.cartStaleDraft,
      );
      return;
    }
    final epoch = _epoch;
    // cart/pricing/menu выше — согласованный снимок ДО первого await.
    state = const CartSubmitState(phase: CartSubmitPhase.preparing);
    var dispatched = false;
    try {
      final dateKeys = preparedDates;
      // Даты обычного набора проверяются basket в транзакции по revisions
      // подготовки. Дополнительные проверки многодневного повтора сохранены.
      var revisions = edit.preparedRevisions;
      if (!edit.isRepeat) {
        await ref.read(cartEditControllerProvider.notifier).persistNow();
        if (!_current(epoch, repository)) return;
      }
      if (edit.isRepeat) {
        await ref.read(menuAllowedDatesProvider.notifier).reload();
        if (!_current(epoch, repository)) return;
        final latestDates = ref.read(menuAllowedDatesProvider);
        if (latestDates.isLoading ||
            latestDates.hasError ||
            latestDates.asData?.value == null ||
            dateKeys.any(
              (d) => !isOrderDateAllowed(latestDates.asData!.value, d),
            )) {
          ref
              .read(cartEditControllerProvider.notifier)
              .block(
                'День закрыт или доступность не подтверждена. Вернитесь в заказы.',
              );
          state = const CartSubmitState(
            phase: CartSubmitPhase.failed,
            message: 'Доступность дня не подтверждена. Вернитесь в заказы.',
          );
          return;
        }
        final snapshot = RepeatSnapshot(
          ownerScope: edit.repeatScope!,
          selectedDateKey: edit.dateKey!,
          revisions: edit.revisions,
          quantities: {
            for (final d in cart.days)
              d.dateKey: {
                for (final item in d.items) item.dishId: item.quantity,
              },
          },
        );
        final repeatStore = ref.read(cartRepeatStoreProvider);
        await ref
            .read(repeatWriteQueueProvider)
            .run(
              () => repeatStore.save(
                owner,
                repository.sessionApi.deviceId,
                snapshot,
              ),
            );
        if (!_current(epoch, repository)) return;
        final checked = await repository.loadRepeat(dateKeys);
        if (!_current(epoch, repository)) return;
        if (checked.ownerScope != edit.repeatScope ||
            checked.days.any(
              (d) =>
                  !{'ready', 'no_history'}.contains(d.status) ||
                  d.revision != edit.revisions[d.dateKey],
            )) {
          ref
              .read(cartEditControllerProvider.notifier)
              .block(
                'Владелец, доступность или заказ изменились. Повторённая корзина сохранена.',
              );
          state = const CartSubmitState(
            phase: CartSubmitPhase.failed,
            message: 'Повторённая корзина не отправлена: серверное состояние изменилось.',
          );
          return;
        }
        revisions = await repository.loadRevisions(dateKeys);
        if (!_current(epoch, repository)) return;
        if (dateKeys.any((date) => !revisions.containsKey(date)) ||
            revisions.values.any((r) => r == 'ambiguous')) {
          if (revisions.values.any((r) => r == 'ambiguous')) {
            ref
                .read(cartEditControllerProvider.notifier)
                .block(AppStrings.cartRevisionUnavailable);
          }
          state = const CartSubmitState(
            phase: CartSubmitPhase.failed,
            message: AppStrings.cartRevisionUnavailable,
          );
          return;
        }
        if (dateKeys.any((d) => revisions[d] != edit.preparedRevisions[d])) {
          ref
              .read(cartEditControllerProvider.notifier)
              .block('Заказ изменился. Обновите его через заказы.');
          state = const CartSubmitState(
            phase: CartSubmitPhase.failed,
            message: 'Заказ изменился. Обновите его через заказы.',
          );
          return;
        }
      }
      if (dateKeys.isEmpty ||
          dateKeys.any(
            (d) =>
                revisions[d] == null ||
                revisions[d]!.isEmpty ||
                revisions[d] == 'ambiguous',
          )) {
        state = const CartSubmitState(
          phase: CartSubmitPhase.failed,
          message: AppStrings.cartRevisionUnavailable,
        );
        return;
      }
      final currentEdit = ref.read(cartEditControllerProvider);
      if (dateKeys.any((d) => !ref.read(cartDayEditPermissionProvider(d))) ||
          !currentEdit.active ||
          currentEdit.repeatScope != edit.repeatScope ||
          dateKeys.any(
            (d) =>
                currentEdit.preparedRevisions[d] != edit.preparedRevisions[d],
          ) ||
          currentEdit.blocked ||
          versionBlocksWork(ref.read(appVersionControllerProvider))) {
        state = const CartSubmitState(
          phase: CartSubmitPhase.failed,
          message: 'Изменение заказа завершено или временно недоступно.',
        );
        return;
      }
      final pending = CartPendingSubmission(
        owner: owner,
        body:
            buildBasketRequestBody(
              submissionId: _newSubmissionId(),
              orderDays: buildBasketOrderDays(
                cart: cart,
                pricing: pricing,
                allowedDateKeys: {...dateKeys},
                revisionsByDate: revisions,
                weeksForNames: menu,
              ),
            )..addAll({
              if (!edit.isRepeat) 'includeSnapshot': true,
              if (!edit.isRepeat && edit.snapshotScope != null)
                'expectedOwnerScope': edit.snapshotScope,
            }),
        preliminary: {
          for (final day in pricing.days) day.dateKey: day.totals.finalTotal,
        },
      );
      _pending = pending;
      await repository.savePending(pending);
      if (!_current(epoch, repository)) return;
      state = CartSubmitState(
        phase: CartSubmitPhase.submitting,
        submissionId: pending.id,
      );
      dispatched = true;
      final response = await repository.submitBasket(pending.body);
      if (!_current(epoch, repository)) return;
      await _handleResponse(response, pending, repository, epoch);
    } catch (error) {
      if (!_current(epoch, repository)) return;
      if (dispatched) {
        await _failure(error, repository, epoch, writing: true);
      } else if (_pending != null) {
        // Запись в локальное хранилище не подтверждена: сеть НЕ вызываем.
        state = const CartSubmitState(
          phase: CartSubmitPhase.recoveryBlocked,
          message: AppStrings.cartRecoveryBlocked,
        );
      } else {
        state = CartSubmitState(
          phase: CartSubmitPhase.failed,
          message: error is ApiException
              ? error.message
              : AppStrings.cartPrepareFailed,
        );
      }
    }
  }

  Future<void> resolveUnknownOutcome() async {
    if (state.phase != CartSubmitPhase.outcomeUnknown) return;
    final repository = ref.read(cartRepositoryProvider);
    final pending = _pending;
    if (repository == null || pending == null) return;
    final epoch = _epoch;
    var writing = false;
    state = CartSubmitState(
      phase: CartSubmitPhase.checkingResult,
      submissionId: pending.id,
    );
    try {
      final receipt = await repository.readSubmissionResult(
        pending.id,
        includeSnapshot: pending.body['includeSnapshot'] == true,
      );
      if (!_current(epoch, repository)) return;
      Map<String, Object?> response;
      if (receipt == null) {
        // Только доказанный not_found разрешает повтор того же снимка.
        state = CartSubmitState(
          phase: CartSubmitPhase.submitting,
          submissionId: pending.id,
        );
        writing = true;
        response = await repository.submitBasket(pending.body);
      } else {
        response = receipt.response;
      }
      if (!_current(epoch, repository)) return;
      await _handleResponse(response, pending, repository, epoch);
    } catch (error) {
      if (!_current(epoch, repository)) return;
      await _failure(error, repository, epoch, writing: writing);
    }
  }

  Future<void> _handleResponse(
    Map<String, Object?> response,
    CartPendingSubmission pending,
    CartRepository repository,
    int epoch,
  ) async {
    if (response['success'] != true) {
      await repository.clearPending(pending.owner);
      if (!_current(epoch, repository)) return;
      _pending = null;
      state = CartSubmitState(
        phase: CartSubmitPhase.failed,
        message: response['message']?.toString() ?? AppStrings.cartRejected,
      );
      return;
    }
    final receipt = response['submission'];
    if (receipt is! Map ||
        receipt['id'] != pending.id ||
        receipt['status'] != 'accepted') {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: AppStrings.cartReceiptMissing,
        outcomeUnknown: true,
      );
    }
    final comparisons = reconcileServerOrderTotals(
      response: response,
      preliminaryRublesByDay: pending.preliminary,
    );
    // Квитанция уже подтверждает запись: ошибка снимка не делает исход
    // неизвестным и не разрешает новую отправку той же операции.
    final wantsSnapshot = pending.body['includeSnapshot'] == true;
    var snapshotApplied = false;
    if (wantsSnapshot) {
      try {
        final raw = response['snapshot'];
        if (raw is! Map) throw const FormatException('Снимок недоступен.');
        final snapshot = OrderSnapshot.parse(
          Map<String, dynamic>.from(raw),
          pending.quantities.keys.toList(),
        );
        if (snapshot.profile.login != pending.owner ||
            (pending.body['expectedOwnerScope'] != null &&
                snapshot.ownerScope != pending.body['expectedOwnerScope'])) {
          throw const FormatException('Владелец снимка изменился.');
        }
        ref
            .read(sessionControllerProvider.notifier)
            .applyProfileSnapshot(
              snapshot.profile,
              generation: ref.read(sessionControllerProvider).generation,
              ownerScope: snapshot.ownerScope,
            );
        ref
            .read(menuAllowedDatesProvider.notifier)
            .applySnapshot(snapshot.allowedDates);
        snapshotApplied = true;
      } on FormatException {
        // Неполный или чужой снимок не заменяет актуальное состояние клиента.
      }
    }
    // Сначала сохраняем очищенный draft, затем удаляем попытку. При сбое
    // записи попытка остаётся и повторно проверяется, а новый POST блокируется.
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).ready;
      if (!_current(epoch, repository)) return;
      // После подтверждённого успеха удаляем и прежние локальные черновики.
      // При ошибке/неизвестном исходе этот шаг не выполняется.
      ref.read(cartDraftProvider.notifier).clearAll();
      await ref.read(cartPersistenceControllerProvider.notifier).persistNow();
      if (!_current(epoch, repository)) return;
      await ref
          .read(cartEditControllerProvider.notifier)
          .clearSavedAfterAccepted(
            pending.owner,
            repository.sessionApi.deviceId,
          );
      if (!_current(epoch, repository)) return;
      final repeatStore = ref.read(cartRepeatStoreProvider);
      await ref
          .read(repeatWriteQueueProvider)
          .run(
            () => repeatStore.clear(
              pending.owner,
              repository.sessionApi.deviceId,
            ),
          );
      if (!_current(epoch, repository)) return;
      ref.read(cartRepeatWorkProvider.notifier).clear();
      if (!_current(epoch, repository)) return;
      await repository.clearPending(pending.owner);
      if (!_current(epoch, repository)) return;
      _pending = null;
    } catch (_) {
      if (_current(epoch, repository)) {
        _unknown(AppStrings.cartAcceptedCleanupFailed);
      }
      return;
    }
    state = CartSubmitState(
      phase: CartSubmitPhase.succeeded,
      comparisons: comparisons,
      message: wantsSnapshot && !snapshotApplied
          ? 'Изменения приняты. Не удалось обновить данные; обновите заказы вручную.'
          : pending.quantities.values.every((day) => day.isEmpty)
          ? 'Изменения приняты. Заказ отменён.'
          : AppStrings.cartAccepted,
    );
    ref.read(cartEditControllerProvider.notifier).end(force: true);
    // Ошибка чтения профиля не отменяет уже подтверждённую квитанцию.
    if (!wantsSnapshot) {
      try {
        await ref.read(sessionControllerProvider.notifier).refreshProfile();
      } catch (_) {
        // Пользователь может повторить обновление на странице заказов.
      }
    }
    // История обновляется при переходе пользователя «К заказам»; restore
    // здесь не вызываем: он меняет поколение сессии и скрывает результат.
  }

  Future<void> _failure(
    Object error,
    CartRepository repository,
    int epoch, {
    required bool writing,
  }) async {
    if (error is ApiException &&
        (error.code == 'order_changed' || error.code == 'order_day_closed')) {
      ref.read(cartEditControllerProvider.notifier).block(error.message);
    }
    if (error is ApiException &&
        writing &&
        !error.outcomeUnknown &&
        error.code != 'submission_conflict' &&
        (error.kind == ApiErrorKind.business ||
            error.kind == ApiErrorKind.unauthorized ||
            error.kind == ApiErrorKind.forbidden)) {
      try {
        final pending = _pending;
        if (pending != null) await repository.clearPending(pending.owner);
        if (!_current(epoch, repository)) return;
        _pending = null;
        state = CartSubmitState(
          phase: CartSubmitPhase.failed,
          message: error.message,
        );
      } catch (_) {
        if (!_current(epoch, repository)) return;
        _unknown(AppStrings.cartUnknownOutcome);
      }
    } else {
      _unknown(
        error is ApiException ? error.message : AppStrings.cartUnknownOutcome,
      );
    }
    if (error is ApiException &&
        error.requiresReauth &&
        _current(epoch, repository)) {
      await ref.read(sessionControllerProvider.notifier).clearLocalSession();
    }
  }

  void _unknown(String message) {
    state = CartSubmitState(
      phase: CartSubmitPhase.outcomeUnknown,
      submissionId: _pending?.id,
      message: message,
      canSafeRetry: true,
    );
  }

  void acknowledge() {
    if (state.phase == CartSubmitPhase.succeeded ||
        state.phase == CartSubmitPhase.failed) {
      state = const CartSubmitState();
    }
  }

  String _newSubmissionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Восстановление/сохранение черновика при смене владельца (FL-05-05/06).
final cartPersistenceControllerProvider =
    NotifierProvider<CartPersistenceController, String?>(
      CartPersistenceController.new,
    );

class CartPersistenceController extends Notifier<String?> {
  int _generation = 0;
  Future<void> _tail = Future<void>.value();
  Future<void> _lastOperation = Future<void>.value();
  Future<void> get ready => _lastOperation;

  void _observe(Future<void> future) {
    // Ошибку по-прежнему получает ready/persistNow; фоновый listener
    // не оставляет необработанного исключения в UI zone.
    unawaited(future.catchError((Object _) {}));
  }

  @override
  String? build() {
    ref.listen<UserProfile?>(sessionProfileProvider, (previous, next) {
      if (previous?.login == next?.login) return;
      _onOwnerChanged(next);
    });
    ref.listen(cartDraftProvider, (previous, next) {
      _observe(persistNow());
    });
    final profile = ref.read(sessionProfileProvider);
    final owner = profile == null ? null : cartDraftOwnerKey(profile.login);
    final generation = ++_generation;
    if (owner != null) {
      _observe(_queue(() => _loadFor(owner, generation)));
    }
    ref.onDispose(() => _generation++);
    return owner;
  }

  Future<void> _queue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _lastOperation = result;
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _save(String owner, Map<String, Map<String, int>> draft) async {
    final store = ref.read(cartDraftStoreProvider);
    if (draft.isEmpty) {
      await store.clear(owner);
    } else {
      await store.save(
        CartDraftSnapshot(
          version: cartDraftFormatVersion,
          ownerKey: owner,
          quantities: draft,
        ),
      );
    }
  }

  Future<void> persistNow() {
    final owner = state;
    if (owner == null) return Future<void>.value();
    final snapshot = ref.read(cartDraftProvider);
    return _queue(() => _save(owner, snapshot));
  }

  void _onOwnerChanged(UserProfile? next) {
    final previousOwner = state;
    final previousDraft = ref.read(cartDraftProvider);
    final generation = ++_generation;
    state = null;
    ref.read(cartDraftProvider.notifier).clearAll();
    final owner = next == null ? null : cartDraftOwnerKey(next.login);
    state = owner;
    _observe(
      _queue(() async {
        if (previousOwner != null) await _save(previousOwner, previousDraft);
        if (owner != null) await _loadFor(owner, generation);
      }),
    );
  }

  Future<void> _loadFor(String owner, int generation) async {
    final snapshot = await ref.read(cartDraftStoreProvider).load(owner);
    if (!ref.mounted ||
        generation != _generation ||
        state != owner ||
        snapshot == null) {
      return;
    }
    ref.read(cartDraftProvider.notifier).replaceAll(snapshot.quantities);
  }
}
