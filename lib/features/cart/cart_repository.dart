import 'package:polevaya_kuhnya/features/cart/cart_snapshot.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submission_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_models.dart';

final cartRepositoryProvider = Provider<CartRepository?>((ref) {
  final api = ref.watch(sessionApiProvider);
  if (api == null) return null;
  return CartRepository(
    sessionApi: api,
    store: ref.watch(cartSubmissionStoreProvider),
  );
});

final class BasketDayState {
  const BasketDayState({required this.dateKey, required this.revision});

  final String dateKey;
  final String revision;
}

final class BasketSubmissionReceipt {
  const BasketSubmissionReceipt({
    required this.id,
    required this.status,
    required this.replayed,
    required this.response,
  });

  final String id;
  final String status;
  final bool replayed;
  final Map<String, Object?> response;

  bool get isAccepted => status == 'accepted';
}

/// HTTP-операции корзины через SessionApi (FL-05-09…12).
final class CartRepository {
  const CartRepository({required this.sessionApi, this.store});

  final SessionApi sessionApi;
  final CartSubmissionStore? store;

  Future<OrderSnapshot> loadSnapshot([List<String>? dateKeys]) async {
    if (dateKeys != null &&
        (dateKeys.isEmpty ||
            dateKeys.length > 31 ||
            dateKeys.toSet().length != dateKeys.length ||
            dateKeys.any((date) => menuCalendarDateKey(date) != date))) {
      throw const FormatException('Нужны 1–31 уникальная календарная дата.');
    }
    final response = await sessionApi.postJson('V1/Orders/snapshot', {
      if (dateKeys != null)
        'dates': [for (final date in dateKeys) '${date}T00:00:00'],
    });
    if (response['success'] != true) {
      throw ApiException(
        kind: ApiErrorKind.business,
        message: 'Не удалось получить снимок заказа.',
        code: response['code']?.toString(),
      );
    }
    return OrderSnapshot.parse(response, dateKeys);
  }

  Future<RepeatResponse> loadRepeat(List<String> dateKeys) async {
    final response = await sessionApi.postJson('V1/Orders/repeat', {
      'dates': [for (final date in dateKeys) '${date}T00:00:00'],
    });
    if (response['success'] != true) {
      throw ApiException(
        kind: ApiErrorKind.business,
        message:
            response['message']?.toString() ?? 'Не удалось повторить заказ.',
        code: response['code']?.toString(),
      );
    }
    return RepeatResponse.parse(response, dateKeys);
  }

  Future<CartPendingSubmission?> loadPending(String owner) =>
      store!.load(owner);
  Future<void> savePending(CartPendingSubmission pending) =>
      store!.save(pending);
  Future<void> clearPending(String owner) => store!.clear(owner);

  Future<Map<String, String>> loadRevisions(List<String> dateKeys) async {
    final dates = [for (final key in dateKeys) '${key}T00:00:00'];
    final response = await sessionApi.postJson('V1/Orders/basketstate', {
      'dates': dates,
    });
    if (response['success'] != true) {
      throw ApiException(
        kind: ApiErrorKind.business,
        message:
            response['message']?.toString() ??
            'Не удалось получить состояние корзины.',
        code: response['code']?.toString(),
      );
    }
    final states = response['states'];
    if (states is! List) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Ответ basketstate не содержит states.',
      );
    }
    final result = <String, String>{};
    for (final raw in states) {
      if (raw is! Map) continue;
      final date = raw['date']?.toString() ?? '';
      final revision = raw['revision']?.toString() ?? '';
      if (date.length < 10 || revision.isEmpty) continue;
      result[date.substring(0, 10)] = revision;
    }
    return result;
  }

  Future<Map<String, Object?>> submitBasket(Map<String, Object?> body) async {
    final response = await sessionApi.postJson('V1/Orders/basket', body);
    return Map<String, Object?>.from(response);
  }

  Future<BasketSubmissionReceipt?> readSubmissionResult(
    String submissionId, {
    bool includeSnapshot = false,
  }) async {
    try {
      final response = await sessionApi.postJson('V1/Orders/basketresult', {
        'submissionId': submissionId,
        if (includeSnapshot) 'includeSnapshot': true,
      });
      final submission = response['submission'];
      if (submission is! Map) {
        final status = response['status']?.toString();
        if (status == 'not_found') return null;
        throw const ApiException(
          kind: ApiErrorKind.format,
          message: 'Ответ basketresult без submission.',
        );
      }
      final id = submission['id']?.toString() ?? submissionId;
      final status = submission['status']?.toString() ?? '';
      if (status == 'not_found') return null;
      if (id != submissionId ||
          status != 'accepted' ||
          response['success'] != true) {
        throw const ApiException(
          kind: ApiErrorKind.format,
          message: 'Исход операции не подтверждён квитанцией.',
          outcomeUnknown: true,
        );
      }
      return BasketSubmissionReceipt(
        id: id,
        status: status,
        replayed: submission['replayed'] == true,
        response: Map<String, Object?>.from(response),
      );
    } on ApiException catch (error) {
      if (error.code == 'not_found') return null;
      rethrow;
    }
  }
}
